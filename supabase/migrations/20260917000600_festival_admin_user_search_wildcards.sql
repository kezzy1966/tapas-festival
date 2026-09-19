-- Add safe Admin user-search wildcards. Only * and ? are user wildcards;
-- SQL LIKE metacharacters supplied by callers remain literal.
begin;

create or replace function festival.search_registered_users(
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
  safe_limit integer := least(greatest(coalesce(p_limit, 50)::integer, 1::integer), 100::integer);
  safe_offset integer := least(greatest(coalesce(p_offset, 0)::integer, 0::integer), 10000::integer);
  escaped_like_query text;
  search_pattern text;
begin
  if (select auth.uid()) is null or not festival.is_current_admin() then
    raise exception 'administrator access required' using errcode = '42501';
  end if;

  escaped_like_query := pg_catalog.replace(
    pg_catalog.replace(
      pg_catalog.replace(normalized_query, E'\\', E'\\\\'),
      '%', E'\\%'
    ),
    '_', E'\\_'
  );
  search_pattern := case
    when pg_catalog.strpos(normalized_query, '*') > 0 or pg_catalog.strpos(normalized_query, '?') > 0
      then pg_catalog.replace(pg_catalog.replace(escaped_like_query, '*', '%'), '?', '_')
    else '%' || escaped_like_query || '%'
  end;

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
          || pg_catalog.repeat('?', greatest((pg_catalog.char_length(pg_catalog.split_part(aa.email, '@', 1)) - 6)::integer, 0::integer))
          || '@'
          || pg_catalog.left(pg_catalog.split_part(aa.email, '@', 2), 6)
          || pg_catalog.repeat('?', greatest((pg_catalog.char_length(pg_catalog.split_part(aa.email, '@', 2)) - 6)::integer, 0::integer))
      end as account
    from account_activity aa
  ), matching_accounts as (
    select la.*
    from labelled_accounts la
    where pg_catalog.lower(coalesce(la.email, '')) like search_pattern escape E'\\'
      or pg_catalog.lower(la.account) like search_pattern escape E'\\'
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

revoke all on function festival.search_registered_users(text, integer, integer) from public, anon, authenticated;
grant execute on function festival.search_registered_users(text, integer, integer) to authenticated;

commit;
