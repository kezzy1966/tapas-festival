-- Phase 1A: additive foundation. Apply only after deployment approval.
-- Requires PostgreSQL 15+ and Supabase Auth. Does not expose either schema to the API.
begin;

create schema festival;
create schema festival_private;
revoke all on schema festival, festival_private from public, anon, authenticated;

-- Restrict schema-local defaults; explicit revokes below also handle global defaults.
alter default privileges in schema festival revoke all on tables from public, anon, authenticated;
alter default privileges in schema festival_private revoke all on tables from public, anon, authenticated;
alter default privileges in schema festival revoke execute on functions from public, anon, authenticated;
alter default privileges in schema festival_private revoke execute on functions from public, anon, authenticated;

create function festival_private.has_translation(en text, es text)
returns boolean language sql immutable set search_path = ''
as $$ select nullif(btrim(en), '') is not null or nullif(btrim(es), '') is not null $$;

-- Missing weekday = unknown; [] = closed. ISO weekdays 1 (Monday) to 7.
-- An end earlier than its start means next day. Equal times are rejected.
create function festival_private.valid_opening_hours(hours jsonb)
returns boolean language plpgsql immutable set search_path = '' as $$
declare day_key text; periods jsonb; period jsonb;
begin
  if hours is null then return true; end if;
  if jsonb_typeof(hours) <> 'object' then return false; end if;
  for day_key, periods in select * from jsonb_each(hours) loop
    if day_key !~ '^[1-7]$' or jsonb_typeof(periods) <> 'array' then return false; end if;
    for period in select * from jsonb_array_elements(periods) loop
      if jsonb_typeof(period) <> 'array' then return false; end if;
      if jsonb_array_length(period) <> 2 then return false; end if;
      if jsonb_typeof(period -> 0) <> 'string' or jsonb_typeof(period -> 1) <> 'string'
        or (period ->> 0) !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
        or (period ->> 1) !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
        or (period ->> 0) = (period ->> 1) then return false; end if;
    end loop;
  end loop;
  return true;
end $$;

-- A select definition has [{"key":"stable_key","label_en":"...","label_es":"..."}].
create function festival_private.valid_field_options(kind text, options jsonb)
returns boolean language plpgsql immutable set search_path = '' as $$
declare option jsonb; seen text[] := '{}'; option_key text;
begin
  if kind <> 'select' then return options is null; end if;
  if options is null or jsonb_typeof(options) <> 'array' then return false; end if;
  if jsonb_array_length(options) = 0 then return false; end if;
  for option in select * from jsonb_array_elements(options) loop
    if jsonb_typeof(option) <> 'object' then return false; end if;
    if (option - array['key', 'label_en', 'label_es']) <> '{}'::jsonb then return false; end if;
    option_key := option ->> 'key';
    if jsonb_typeof(option -> 'key') is distinct from 'string'
      or option_key !~ '^[a-z][a-z0-9_]*$' or option_key = any(seen) then return false; end if;
    if (option ? 'label_en' and jsonb_typeof(option -> 'label_en') <> 'string')
      or (option ? 'label_es' and jsonb_typeof(option -> 'label_es') <> 'string')
      or not festival_private.has_translation(option ->> 'label_en', option ->> 'label_es')
      then return false; end if;
    seen := array_append(seen, option_key);
  end loop;
  return true;
end $$;

create function festival_private.valid_field_value(kind text, options jsonb, val jsonb)
returns boolean language plpgsql immutable set search_path = '' as $$
begin
  if val is null or val = 'null'::jsonb then return false; end if;
  case kind
    when 'text' then
      if jsonb_typeof(val) <> 'object' then return false; end if;
      return (val - array['en', 'es']) = '{}'::jsonb
        and (not (val ? 'en') or jsonb_typeof(val -> 'en') = 'string')
        and (not (val ? 'es') or jsonb_typeof(val -> 'es') = 'string')
        and festival_private.has_translation(val ->> 'en', val ->> 'es');
    when 'number' then return jsonb_typeof(val) = 'number';
    when 'boolean' then return jsonb_typeof(val) = 'boolean';
    when 'select' then
      if jsonb_typeof(val) <> 'string' then return false; end if;
      return exists (select 1 from jsonb_array_elements(options) o where o -> 'key' = val);
    else return false;
  end case;
end $$;

create table festival.festivals (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  name_en text, name_es text,
  description_en text, description_es text,
  start_date date not null, end_date date not null,
  default_tapa_price numeric(8,2) not null check (default_tapa_price >= 0 and default_tapa_price <> 'NaN'::numeric),
  currency_code text not null default 'EUR' check (currency_code ~ '^[A-Z]{3}$'),
  city text not null check (nullif(btrim(city), '') is not null),
  timezone text not null default 'Europe/Madrid',
  default_language text not null default 'en' check (default_language in ('en', 'es')),
  publication_status text not null default 'draft' check (publication_status in ('draft', 'published', 'archived')),
  reviews_enabled boolean not null default false,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint festival_name_present check (festival_private.has_translation(name_en, name_es)),
  constraint festival_date_order check (end_date >= start_date)
);

create table festival.establishments (
  id uuid primary key default gen_random_uuid(),
  festival_id uuid not null references festival.festivals(id) on delete restrict,
  name text not null check (nullif(btrim(name), '') is not null),
  description_en text, description_es text,
  address text not null check (nullif(btrim(address), '') is not null),
  latitude double precision, longitude double precision,
  phone text, whatsapp text, facebook_url text, website_url text,
  opening_hours jsonb,
  hours_notes_en text, hours_notes_es text,
  photo_path text,
  is_published boolean not null default false,
  participation_status text not null default 'active' check (participation_status in ('active', 'withdrawn')),
  closure_status text not null default 'normal' check (closure_status in ('normal', 'temporarily_closed', 'permanently_closed')),
  status_note_en text, status_note_es text,
  sort_order integer not null default 0 check (sort_order >= 0),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint establishment_coordinates check (
    (latitude is null and longitude is null) or
    (latitude is not null and longitude is not null and latitude between -90 and 90 and longitude between -180 and 180)
  ),
  constraint published_establishment_coordinates check (not is_published or (latitude is not null and longitude is not null)),
  constraint establishment_hours_valid check (festival_private.valid_opening_hours(opening_hours))
);
create index establishments_festival_order_idx on festival.establishments(festival_id, sort_order);

create table festival.tapas (
  id uuid primary key default gen_random_uuid(),
  establishment_id uuid not null references festival.establishments(id) on delete restrict,
  name_en text, name_es text,
  description_en text, description_es text,
  price_override numeric(8,2) check (price_override >= 0 and price_override <> 'NaN'::numeric),
  photo_path text,
  is_published boolean not null default false,
  participation_status text not null default 'active' check (participation_status in ('active', 'withdrawn')),
  status_note_en text, status_note_es text,
  festival_number integer check (festival_number > 0),
  sort_order integer not null default 0 check (sort_order >= 0),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint tapa_name_present check (festival_private.has_translation(name_en, name_es))
);
create index tapas_establishment_order_idx on festival.tapas(establishment_id, sort_order);

create table festival.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Festival visitor' check (char_length(btrim(display_name)) between 1 and 80),
  avatar_url text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table festival.reviews (
  id uuid primary key default gen_random_uuid(),
  tapa_id uuid not null references festival.tapas(id) on delete restrict,
  user_id uuid not null references festival.profiles(user_id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  review_text text check (char_length(review_text) <= 3000),
  moderation_status text not null default 'visible' check (moderation_status in ('visible', 'hidden')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint reviews_one_per_user_tapa unique(user_id, tapa_id)
);
create index reviews_tapa_idx on festival.reviews(tapa_id);
create index reviews_visible_tapa_idx on festival.reviews(tapa_id) where moderation_status = 'visible';

create table festival_private.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table festival.field_definitions (
  id uuid primary key default gen_random_uuid(),
  festival_id uuid not null references festival.festivals(id) on delete restrict,
  key text not null check (key ~ '^[a-z][a-z0-9_]*$'),
  label_en text, label_es text,
  description_en text, description_es text,
  field_type text not null check (field_type in ('text', 'number', 'boolean', 'select')),
  applies_to text not null check (applies_to in ('establishment', 'tapa')),
  options jsonb,
  required boolean not null default false,
  sort_order integer not null default 0 check (sort_order >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint field_key_unique unique(festival_id, applies_to, key),
  constraint field_label_present check (festival_private.has_translation(label_en, label_es)),
  constraint field_options_valid check (festival_private.valid_field_options(field_type, options))
);
create index field_definitions_festival_order_idx on festival.field_definitions(festival_id, applies_to, sort_order);

create table festival.field_values (
  id uuid primary key default gen_random_uuid(),
  field_definition_id uuid not null references festival.field_definitions(id) on delete cascade,
  establishment_id uuid references festival.establishments(id) on delete cascade,
  tapa_id uuid references festival.tapas(id) on delete cascade,
  value jsonb not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint field_value_one_target check (num_nonnulls(establishment_id, tapa_id) = 1)
);
create unique index field_values_establishment_unique on festival.field_values(establishment_id, field_definition_id) where establishment_id is not null;
create unique index field_values_tapa_unique on festival.field_values(tapa_id, field_definition_id) where tapa_id is not null;
create index field_values_definition_idx on festival.field_values(field_definition_id);

-- Fail closed even if core is applied separately from the security migration.
alter table festival.festivals enable row level security;
alter table festival.establishments enable row level security;
alter table festival.tapas enable row level security;
alter table festival.profiles enable row level security;
alter table festival.reviews enable row level security;
alter table festival.field_definitions enable row level security;
alter table festival.field_values enable row level security;
alter table festival_private.admin_users enable row level security;
revoke all on all tables in schema festival, festival_private from public, anon, authenticated;

create function festival_private.touch_row()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    if new.created_at is distinct from old.created_at then raise exception 'created_at is immutable' using errcode = '23514'; end if;
    new.updated_at := clock_timestamp();
  else
    new.created_at := clock_timestamp(); new.updated_at := new.created_at;
  end if;
  return new;
end $$;

create function festival_private.guard_content_identity()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.id is distinct from old.id then raise exception 'id is immutable' using errcode = '23514'; end if;
  if tg_table_name = 'establishments' then
    if new.festival_id is distinct from old.festival_id then raise exception 'festival_id is immutable' using errcode = '23514'; end if;
  elsif tg_table_name = 'tapas' then
    if new.establishment_id is distinct from old.establishment_id then raise exception 'establishment_id is immutable' using errcode = '23514'; end if;
  elsif tg_table_name = 'field_definitions' then
    if (new.festival_id, new.key, new.applies_to) is distinct from (old.festival_id, old.key, old.applies_to)
      then raise exception 'field identity is immutable' using errcode = '23514'; end if;
    if new.field_type is distinct from old.field_type and exists (
      select 1 from festival.field_values v where v.field_definition_id = old.id
    ) then raise exception 'cannot change the type of a populated field' using errcode = '23514'; end if;
  end if;
  return new;
end $$;

create function festival_private.validate_timezone()
returns trigger language plpgsql set search_path = '' as $$
begin
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = new.timezone)
    then raise exception 'unknown timezone' using errcode = '23514'; end if;
  return new;
end $$;
create trigger festival_timezone before insert or update on festival.festivals
for each row execute function festival_private.validate_timezone();

-- Serializes small admin content transactions so concurrent publication/field edits
-- cannot both pass completeness checks against an outdated graph. No review lock.
create function festival_private.lock_content_graph()
returns trigger language plpgsql set search_path = '' as $$
begin
  -- Repeatable-read snapshots can remain stale after waiting for this lock.
  if current_setting('transaction_isolation') = 'repeatable read' then
    raise exception 'festival content writes require read committed or serializable isolation' using errcode = '25000';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(74621, 1);
  return null;
end $$;

-- Deferred checks let admins populate required fields and publish atomically.
-- At this scale scanning the small custom-field graph is simpler than cached state.
create function festival_private.validate_field_graph()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if exists (
    select 1 from festival.field_values v
    join festival.field_definitions d on d.id = v.field_definition_id
    left join festival.tapas t on t.id = v.tapa_id
    left join festival.establishments e on e.id = coalesce(v.establishment_id, t.establishment_id)
    where d.festival_id is distinct from e.festival_id
      or (d.applies_to = 'establishment') is distinct from (v.establishment_id is not null)
      or not festival_private.valid_field_value(d.field_type, d.options, v.value)
  ) then raise exception 'custom field target, festival, or value is invalid' using errcode = '23514'; end if;

  if exists (
    select 1 from festival.field_definitions d
    join festival.establishments e on e.festival_id = d.festival_id
    where d.active and d.required and d.applies_to = 'establishment' and e.is_published
      and not exists (select 1 from festival.field_values v where v.field_definition_id = d.id and v.establishment_id = e.id)
  ) or exists (
    select 1 from festival.field_definitions d
    join festival.establishments e on e.festival_id = d.festival_id
    join festival.tapas t on t.establishment_id = e.id
    where d.active and d.required and d.applies_to = 'tapa' and t.is_published
      and not exists (select 1 from festival.field_values v where v.field_definition_id = d.id and v.tapa_id = t.id)
  ) then raise exception 'published content is missing a required custom field' using errcode = '23514'; end if;
  return null;
end $$;

do $$
declare table_name text;
begin
  foreach table_name in array array['festivals', 'establishments', 'tapas', 'profiles', 'reviews', 'field_definitions', 'field_values'] loop
    execute format('create trigger touch_row before insert or update on festival.%I for each row execute function festival_private.touch_row()', table_name);
  end loop;
  foreach table_name in array array['festivals', 'establishments', 'tapas', 'field_definitions', 'field_values'] loop
    execute format('create trigger content_identity before update on festival.%I for each row execute function festival_private.guard_content_identity()', table_name);
    execute format('create trigger content_graph_lock before insert or update or delete on festival.%I for each statement execute function festival_private.lock_content_graph()', table_name);
  end loop;
  foreach table_name in array array['establishments', 'tapas', 'field_definitions', 'field_values'] loop
    execute format('create constraint trigger field_graph_valid after insert or update or delete on festival.%I deferrable initially deferred for each row execute function festival_private.validate_field_graph()', table_name);
  end loop;
end $$;

revoke all on all functions in schema festival_private from public, anon, authenticated;
commit;
