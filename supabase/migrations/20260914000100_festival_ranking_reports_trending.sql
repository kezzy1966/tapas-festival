-- Public ranking presentation settings, recent-rating activity, and admin tapa-vote detail.
begin;

alter table festival.festivals
  add column show_total_rating_count boolean not null default true;

-- One public query supplies currently trending tapas. It deliberately uses
-- created_at: editing an old rating never creates new-rating activity.
create view festival.tapa_recent_rating_activity with (security_invoker = true) as
with recent as (
  select
    e.festival_id,
    r.tapa_id,
    count(r.rating)::bigint as new_rating_count
  from festival.reviews r
  join festival.tapas t on t.id = r.tapa_id
  join festival.establishments e on e.id = t.establishment_id
  join festival.festivals f on f.id = e.festival_id
  where r.rating is not null
    and r.moderation_status = 'visible'
    and r.created_at >= now() - interval '24 hours'
    and t.is_published and t.participation_status = 'active'
    and e.is_published and e.participation_status = 'active'
    and f.publication_status in ('published', 'archived')
  group by e.festival_id, r.tapa_id
), ranked as (
  select
    festival_id,
    tapa_id,
    new_rating_count,
    row_number() over (partition by festival_id order by new_rating_count desc, tapa_id) as activity_rank
  from recent
  where new_rating_count >= 3
)
select festival_id, tapa_id, new_rating_count
from ranked
where activity_rank <= 3;

revoke all on festival.tapa_recent_rating_activity from public, anon, authenticated;
grant select on festival.tapa_recent_rating_activity to anon, authenticated;

-- This is an authenticated-admin report boundary. It returns masked identity
-- labels only and never grants API access to auth.users or festival_private.
create function festival.tapa_rating_detail(p_tapa_id uuid)
returns table (
  programme_number integer,
  establishment_name text,
  tapa_name text,
  total_rating_count bigint,
  average_rating numeric,
  rating_1_19_count bigint,
  rating_2_29_count bigint,
  rating_3_39_count bigint,
  rating_4_44_count bigint,
  rating_45_50_count bigint,
  user_label text,
  rating numeric,
  review_text text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not festival.is_current_admin() then
    raise exception 'administrator access required' using errcode = '42501';
  end if;

  return query
  with target as (
    select t.id, t.festival_number, e.name as establishment_name,
      coalesce(t.name_en, t.name_es) as tapa_name
    from festival.tapas t
    join festival.establishments e on e.id = t.establishment_id
    where t.id = p_tapa_id
  ), summary as (
    select
      count(r.rating)::bigint as total_rating_count,
      avg(r.rating) as average_rating,
      count(r.rating) filter (where r.rating >= 1.0 and r.rating < 2.0)::bigint as rating_1_19_count,
      count(r.rating) filter (where r.rating >= 2.0 and r.rating < 3.0)::bigint as rating_2_29_count,
      count(r.rating) filter (where r.rating >= 3.0 and r.rating < 4.0)::bigint as rating_3_39_count,
      count(r.rating) filter (where r.rating >= 4.0 and r.rating < 4.5)::bigint as rating_4_44_count,
      count(r.rating) filter (where r.rating >= 4.5 and r.rating <= 5.0)::bigint as rating_45_50_count
    from festival.reviews r
    where r.tapa_id = p_tapa_id
  )
  select
    target.festival_number,
    target.establishment_name,
    target.tapa_name,
    summary.total_rating_count,
    summary.average_rating,
    summary.rating_1_19_count,
    summary.rating_2_29_count,
    summary.rating_3_39_count,
    summary.rating_4_44_count,
    summary.rating_45_50_count,
    case when u.email is null or position('@' in u.email) = 0 then 'User'
      else left(split_part(u.email, '@', 1), 6)
        || repeat('?', greatest(char_length(split_part(u.email, '@', 1)) - 6, 0))
        || '@'
        || left(split_part(u.email, '@', 2), 6)
        || repeat('?', greatest(char_length(split_part(u.email, '@', 2)) - 6, 0))
    end,
    r.rating,
    r.review_text,
    r.created_at
  from target
  cross join summary
  left join festival.reviews r on r.tapa_id = target.id
  left join auth.users u on u.id = r.user_id
  order by r.created_at desc nulls last;
end
$$;

revoke all on function festival.tapa_rating_detail(uuid) from public, anon, authenticated;
grant execute on function festival.tapa_rating_detail(uuid) to authenticated;

commit;
