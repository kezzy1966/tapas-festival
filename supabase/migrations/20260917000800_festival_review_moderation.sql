-- Admin review moderation using the existing moderation_status field.
begin;

create table festival_private.review_moderation_audit (
  id bigint generated always as identity primary key,
  review_id uuid not null,
  action text not null check (action in ('hidden', 'restored')),
  performed_by uuid not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp()
);

create index review_moderation_audit_review_created_idx
  on festival_private.review_moderation_audit(review_id, created_at desc);

alter table festival_private.review_moderation_audit enable row level security;
revoke all on table festival_private.review_moderation_audit from public, anon, authenticated;

create index reviews_moderation_status_created_idx
  on festival.reviews(moderation_status, created_at desc);

-- Hidden reviews are available to Administrators only; ordinary users cannot read
-- their own hidden row through the public table API.
drop policy if exists reviews_owner_read on festival.reviews;
create policy reviews_owner_read on festival.reviews for select to authenticated
using (user_id = (select auth.uid()) and moderation_status = 'visible'
  and festival_private.is_public_tapa(tapa_id));

create function festival.list_review_moderation(
  p_query text default '',
  p_status text default 'all',
  p_limit integer default 25,
  p_offset integer default 0
)
returns table (
  review_id uuid,
  created_at timestamptz,
  user_label text,
  establishment_name text,
  tapa_name text,
  rating smallint,
  review_text text,
  status text,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  safe_query text := pg_catalog.btrim(coalesce(p_query, ''));
  like_query text;
  page_size integer := case
    when coalesce(p_limit, 25) < 1 then 1
    when p_limit > 25 then 25
    else coalesce(p_limit, 25)
  end;
  page_offset integer := case
    when coalesce(p_offset, 0) < 0 then 0
    else coalesce(p_offset, 0)
  end;
begin
  if not festival.is_current_admin() then
    raise exception 'administrator access required' using errcode = '42501';
  end if;
  if p_status not in ('all', 'visible', 'hidden') then
    raise exception 'status must be all, visible, or hidden' using errcode = '22023';
  end if;

  like_query := '%' ||
    pg_catalog.replace(
      pg_catalog.replace(
        pg_catalog.replace(safe_query, E'\\', E'\\\\'),
        '%', E'\\%'
      ),
      '_', E'\\_'
    ) || '%';

  return query
  with matching as (
    select
      r.id,
      r.created_at,
      r.user_id,
      r.tapa_id,
      r.rating,
      r.review_text,
      r.moderation_status
    from festival.reviews r
    join festival.tapas t on t.id = r.tapa_id
    join festival.establishments e on e.id = t.establishment_id
    join auth.users u on u.id = r.user_id
    where nullif(pg_catalog.btrim(r.review_text), '') is not null
      and (p_status = 'all' or r.moderation_status = p_status)
      and (
        safe_query = ''
        or u.email ilike like_query escape E'\\'
        or e.name ilike like_query escape E'\\'
        or coalesce(t.name_en, '') ilike like_query escape E'\\'
        or coalesce(t.name_es, '') ilike like_query escape E'\\'
        or r.review_text ilike like_query escape E'\\'
      )
  )
  select
    m.id,
    m.created_at,
    case
      when u.email is null or pg_catalog.strpos(u.email, '@') = 0 then 'User'
      else pg_catalog.left(pg_catalog.split_part(u.email, '@', 1), 6)
        || pg_catalog.repeat('?', greatest(pg_catalog.char_length(pg_catalog.split_part(u.email, '@', 1)) - 6, 0))
        || '@'
        || pg_catalog.left(pg_catalog.split_part(u.email, '@', 2), 6)
        || pg_catalog.repeat('?', greatest(pg_catalog.char_length(pg_catalog.split_part(u.email, '@', 2)) - 6, 0))
    end,
    e.name,
    coalesce(t.name_en, t.name_es),
    m.rating,
    m.review_text,
    m.moderation_status,
    count(*) over ()::bigint
  from matching m
  join festival.tapas t on t.id = m.tapa_id
  join festival.establishments e on e.id = t.establishment_id
  join auth.users u on u.id = m.user_id
  order by m.created_at desc, m.id desc
  limit page_size offset page_offset;
end
$$;

create function festival.set_review_moderation(
  p_review_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  previous_status text;
  next_action text;
begin
  caller_id := (select auth.uid());
  if caller_id is null or not festival.is_current_admin() then
    raise exception 'administrator access required' using errcode = '42501';
  end if;
  if p_status not in ('visible', 'hidden') then
    raise exception 'status must be visible or hidden' using errcode = '22023';
  end if;

  select r.moderation_status
    into previous_status
  from festival.reviews r
  where r.id = p_review_id
    and nullif(pg_catalog.btrim(r.review_text), '') is not null
  for update;

  if previous_status is null then
    raise exception 'written review not found' using errcode = 'P0002';
  end if;
  if previous_status = p_status then
    raise exception 'review already has that status' using errcode = '22023';
  end if;

  next_action := case when p_status = 'hidden' then 'hidden' else 'restored' end;
  update festival.reviews r
  set moderation_status = p_status,
      updated_at = pg_catalog.clock_timestamp()
  where r.id = p_review_id;

  insert into festival_private.review_moderation_audit(review_id, action, performed_by)
  values (p_review_id, next_action, caller_id);
end
$$;

revoke all on function festival.list_review_moderation(text, text, integer, integer) from public, anon, authenticated;
revoke all on function festival.set_review_moderation(uuid, text) from public, anon, authenticated;
grant execute on function festival.list_review_moderation(text, text, integer, integer) to authenticated;
grant execute on function festival.set_review_moderation(uuid, text) to authenticated;

commit;
