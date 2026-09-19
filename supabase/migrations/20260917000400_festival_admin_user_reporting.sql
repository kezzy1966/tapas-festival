-- Admin-only user reporting and Superadmin-only administrator account labels.
-- These RPCs are the sole browser boundary for the limited auth.users fields
-- required by the protected Admin UI.
begin;

create or replace function festival.list_administrators()
returns table (
  account_id uuid,
  account text,
  role text,
  added_at timestamptz,
  status text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform festival_private.require_superuser();

  return query
  select
    a.user_id,
    coalesce(nullif(u.email, ''), 'Account'),
    a.role,
    a.created_at,
    'Active'::text
  from festival_private.admin_users a
  join auth.users u on u.id = a.user_id
  order by (a.role = 'superuser') desc, a.created_at, a.user_id;
end
$$;

create function festival.search_registered_users(
  p_query text default null,
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  account_id uuid,
  account text,
  registered_at timestamptz,
  last_festival_activity_at timestamptz,
  tapa_rating_count bigint,
  written_review_count bigint,
  bar_rating_count bigint,
  total_activity_count bigint,
  status text,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  normalized_query text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_query, '')));
  safe_limit integer := pg_catalog.least(pg_catalog.greatest(coalesce(p_limit, 50), 1), 100);
  safe_offset integer := pg_catalog.least(pg_catalog.greatest(coalesce(p_offset, 0), 0), 10000);
begin
  if (select auth.uid()) is null or not festival.is_current_admin() then
    raise exception 'administrator access required' using errcode = '42501';
  end if;

  return query
  with account_activity as (
    select
      u.id as user_id,
      u.email,
      u.created_at as registered_at,
      coalesce(tr.tapa_rating_count, 0)::bigint as tapa_rating_count,
      coalesce(tr.written_review_count, 0)::bigint as written_review_count,
      coalesce(br.bar_rating_count, 0)::bigint as bar_rating_count,
      greatest(tr.last_activity_at, br.last_activity_at) as last_festival_activity_at
    from auth.users u
    left join lateral (
      select
        count(*) filter (where r.rating is not null)::bigint as tapa_rating_count,
        count(*) filter (where nullif(pg_catalog.btrim(r.review_text), '') is not null)::bigint as written_review_count,
        max(r.updated_at) as last_activity_at
      from festival.reviews r
      where r.user_id = u.id
    ) tr on true
    left join lateral (
      select count(*)::bigint as bar_rating_count, max(r.updated_at) as last_activity_at
      from festival.establishment_reviews r
      where r.user_id = u.id
    ) br on true
  ), labelled_accounts as (
    select
      aa.*,
      case
        when aa.email is null or pg_catalog.strpos(aa.email, '@') = 0 then 'Account'
        else pg_catalog.left(pg_catalog.split_part(aa.email, '@', 1), 6)
          || pg_catalog.repeat('?', pg_catalog.greatest(pg_catalog.char_length(pg_catalog.split_part(aa.email, '@', 1)) - 6, 0))
          || '@'
          || pg_catalog.left(pg_catalog.split_part(aa.email, '@', 2), 6)
          || pg_catalog.repeat('?', pg_catalog.greatest(pg_catalog.char_length(pg_catalog.split_part(aa.email, '@', 2)) - 6, 0))
      end as account
    from account_activity aa
  ), matching_accounts as (
    select la.*
    from labelled_accounts la
    where normalized_query = ''
      or pg_catalog.lower(coalesce(la.email, '')) like '%' || normalized_query || '%'
      or pg_catalog.lower(la.account) like '%' || normalized_query || '%'
  )
  select
    ma.user_id,
    ma.account,
    ma.registered_at,
    ma.last_festival_activity_at,
    ma.tapa_rating_count,
    ma.written_review_count,
    ma.bar_rating_count,
    ma.tapa_rating_count + ma.written_review_count + ma.bar_rating_count,
    'Active'::text,
    count(*) over ()::bigint
  from matching_accounts ma
  order by ma.last_festival_activity_at desc nulls last, ma.registered_at desc, ma.user_id
  limit safe_limit offset safe_offset;
end
$$;

create function festival.registered_user_activity(p_account_id uuid)
returns table (
  activity_kind text,
  festival_name text,
  establishment_name text,
  tapa_name text,
  rating numeric(2,1),
  review_text text,
  activity_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null or not festival.is_current_admin() then
    raise exception 'administrator access required' using errcode = '42501';
  end if;

  if p_account_id is null or not exists (select 1 from auth.users u where u.id = p_account_id) then
    raise exception 'user account not found' using errcode = 'P0002';
  end if;

  return query
  select
    case
      when r.rating is not null and nullif(pg_catalog.btrim(r.review_text), '') is not null then 'Tapa rating and review'
      when r.rating is not null then 'Tapa rating'
      else 'Written review'
    end,
    f.name_en,
    e.name,
    coalesce(t.name_en, t.name_es),
    r.rating,
    nullif(pg_catalog.btrim(r.review_text), ''),
    r.updated_at
  from festival.reviews r
  join festival.tapas t on t.id = r.tapa_id
  join festival.establishments e on e.id = t.establishment_id
  join festival.festivals f on f.id = e.festival_id
  where r.user_id = p_account_id

  union all

  select
    'Bar rating'::text,
    f.name_en,
    e.name,
    null::text,
    r.rating,
    null::text,
    r.updated_at
  from festival.establishment_reviews r
  join festival.establishments e on e.id = r.establishment_id
  join festival.festivals f on f.id = e.festival_id
  where r.user_id = p_account_id

  order by 7 desc;
end
$$;

revoke all on function festival.list_administrators(), festival.search_registered_users(text, integer, integer), festival.registered_user_activity(uuid) from public, anon, authenticated;
grant execute on function festival.list_administrators(), festival.search_registered_users(text, integer, integer), festival.registered_user_activity(uuid) to authenticated;

commit;
