-- Permanent venue identities for annual festival establishment participations.
-- Run as the trusted migration owner (normally postgres), never as an API role.
begin;

create table festival.venues (
  id uuid primary key default gen_random_uuid(),
  canonical_name text not null check (nullif(btrim(canonical_name), '') is not null),
  canonical_address text,
  canonical_latitude double precision,
  canonical_longitude double precision,
  canonical_phone text,
  canonical_whatsapp text,
  canonical_website_url text,
  canonical_facebook_url text,
  canonical_instagram text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint venue_coordinates check (
    (canonical_latitude is null and canonical_longitude is null) or
    (canonical_latitude is not null and canonical_longitude is not null
      and canonical_latitude between -90 and 90
      and canonical_longitude between -180 and 180)
  )
);

create trigger venues_touch_row before insert or update on festival.venues
for each row execute function festival_private.touch_row();

-- Adding a column is incompatible with any deferred content-graph events left
-- pending by a surrounding migration runner transaction.
set constraints all immediate;

alter table festival.establishments
  add column venue_id uuid references festival.venues(id) on delete restrict;

-- The 2025 import stores an establishment Instagram handle as the English text
-- value of its festival-scoped `instagram` custom field. Only take a value when
-- exactly one such non-empty string exists; otherwise leave the canonical value
-- null rather than choosing between ambiguous data.
with instagram_values as (
  select
    e.id as establishment_id,
    case when count(*) filter (
      where d.festival_id = e.festival_id
        and d.applies_to = 'establishment'
        and d.key = 'instagram'
        and jsonb_typeof(v.value) = 'object'
        and jsonb_typeof(v.value -> 'en') = 'string'
        and nullif(btrim(v.value ->> 'en'), '') is not null
    ) = 1 then max(nullif(btrim(v.value ->> 'en'), '')) filter (
      where d.festival_id = e.festival_id
        and d.applies_to = 'establishment'
        and d.key = 'instagram'
        and jsonb_typeof(v.value) = 'object'
        and jsonb_typeof(v.value -> 'en') = 'string'
        and nullif(btrim(v.value ->> 'en'), '') is not null
    ) end as canonical_instagram
  from festival.establishments e
  left join festival.field_values v on v.establishment_id = e.id
  left join festival.field_definitions d on d.id = v.field_definition_id
  group by e.id
), source as materialized (
  select
    e.id as establishment_id,
    gen_random_uuid() as venue_id,
    case
      when e.name ~ '^[[:space:]]*[0-9]+\.[[:space:]]+\S'
        then btrim(regexp_replace(e.name, '^[[:space:]]*[0-9]+\.[[:space:]]*', ''))
      else e.name
    end as canonical_name,
    e.address as canonical_address,
    e.latitude as canonical_latitude,
    e.longitude as canonical_longitude,
    e.phone as canonical_phone,
    e.whatsapp as canonical_whatsapp,
    e.website_url as canonical_website_url,
    e.facebook_url as canonical_facebook_url,
    i.canonical_instagram
  from festival.establishments e
  left join instagram_values i on i.establishment_id = e.id
), inserted as (
  insert into festival.venues (
    id, canonical_name, canonical_address, canonical_latitude,
    canonical_longitude, canonical_phone, canonical_whatsapp,
    canonical_website_url, canonical_facebook_url, canonical_instagram
  )
  select
    venue_id, canonical_name, canonical_address, canonical_latitude,
    canonical_longitude, canonical_phone, canonical_whatsapp,
    canonical_website_url, canonical_facebook_url, canonical_instagram
  from source
  returning id
)
update festival.establishments e
set venue_id = s.venue_id
from source s
where e.id = s.establishment_id;

do $$
declare
  establishment_count bigint;
  venue_count bigint;
  linked_venue_count bigint;
begin
  select count(*) into establishment_count from festival.establishments;
  select count(*) into venue_count from festival.venues;
  select count(distinct venue_id) into linked_venue_count from festival.establishments;

  if exists (select 1 from festival.establishments where venue_id is null)
    or venue_count <> establishment_count
    or linked_venue_count <> establishment_count then
    raise exception 'venue backfill must create exactly one linked venue per establishment'
      using errcode = '23514';
  end if;
end $$;

alter table festival.establishments
  alter column venue_id set not null,
  add constraint establishments_festival_venue_key unique (festival_id, venue_id);

-- Fail closed: public venue data is not an API surface. Authenticated admins
-- receive the same direct table-management path used for other festival content.
alter table festival.venues enable row level security;
revoke all on table festival.venues from public, anon, authenticated;
grant select on table festival.venues to authenticated;
grant insert (
  canonical_name, canonical_address, canonical_latitude, canonical_longitude,
  canonical_phone, canonical_whatsapp, canonical_website_url,
  canonical_facebook_url, canonical_instagram
) on table festival.venues to authenticated;
grant update (
  canonical_name, canonical_address, canonical_latitude, canonical_longitude,
  canonical_phone, canonical_whatsapp, canonical_website_url,
  canonical_facebook_url, canonical_instagram
) on table festival.venues to authenticated;

create policy venues_admin_manage on festival.venues for all to authenticated
using ((select festival_private.is_admin()))
with check ((select festival_private.is_admin()));

commit;
