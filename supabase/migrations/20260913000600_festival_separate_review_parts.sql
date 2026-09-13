-- Preserve the single review row per user/tapa while allowing its rating and text
-- to be removed independently. A row must always retain at least one of them.
begin;

alter table festival.reviews
  alter column rating drop not null;

alter table festival.reviews
  add constraint reviews_rating_or_text_present
  check (rating is not null or nullif(btrim(review_text), '') is not null);

-- Text-only visible reviews remain public, but only numeric ratings contribute to
-- public statistics and ranking inputs.
create or replace view festival.tapa_rating_stats with (security_invoker = true) as
select
  t.id as tapa_id,
  f.id as festival_id,
  count(r.rating) as rating_count,
  avg(r.rating) as average_rating,
  count(r.rating) filter (where r.rating >= 4) as good_excellent_count,
  100.0 * count(r.rating) filter (where r.rating >= 4) / nullif(count(r.rating), 0) as good_excellent_percentage
from festival.tapas t
join festival.establishments e on e.id = t.establishment_id
join festival.festivals f on f.id = e.festival_id
left join festival.reviews r on r.tapa_id = t.id
  and r.moderation_status = 'visible'
  and r.rating is not null
where t.is_published and e.is_published and f.publication_status in ('published', 'archived')
group by t.id, f.id;

-- Admin activity is a rating report, so text-only reviews do not count as a
-- tapa rating or appear as a numeric activity record.
create or replace function festival.user_rating_activity(p_festival_id uuid default null)
returns table (
  festival_id uuid,
  user_label text,
  tapa_rating_count bigint,
  bar_rating_count bigint,
  total_rating_count bigint,
  tapa_ratings jsonb,
  bar_ratings jsonb
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
  with tapa_activity as (
    select
      e.festival_id,
      r.user_id,
      count(*)::bigint as rating_count,
      jsonb_agg(
        jsonb_build_object(
          'establishment_name', e.name,
          'tapa_name', coalesce(t.name_en, t.name_es),
          'rating', r.rating
        ) order by r.updated_at desc
      ) as ratings
    from festival.reviews r
    join festival.tapas t on t.id = r.tapa_id
    join festival.establishments e on e.id = t.establishment_id
    where r.rating is not null
      and (p_festival_id is null or e.festival_id = p_festival_id)
    group by e.festival_id, r.user_id
  ), bar_activity as (
    select
      e.festival_id,
      r.user_id,
      count(*)::bigint as rating_count,
      jsonb_agg(
        jsonb_build_object(
          'establishment_name', e.name,
          'rating', r.rating
        ) order by r.updated_at desc
      ) as ratings
    from festival.establishment_reviews r
    join festival.establishments e on e.id = r.establishment_id
    where p_festival_id is null or e.festival_id = p_festival_id
    group by e.festival_id, r.user_id
  ), report_users as (
    select ta.festival_id, ta.user_id from tapa_activity ta
    union
    select ba.festival_id, ba.user_id from bar_activity ba
  )
  select
    ru.festival_id,
    case when u.email is null or position('@' in u.email) = 0 then 'User'
      else left(split_part(u.email, '@', 1), 6)
        || repeat('?', greatest(char_length(split_part(u.email, '@', 1)) - 6, 0))
        || '@'
        || left(split_part(u.email, '@', 2), 6)
        || repeat('?', greatest(char_length(split_part(u.email, '@', 2)) - 6, 0))
    end as user_label,
    coalesce(ta.rating_count, 0),
    coalesce(ba.rating_count, 0),
    coalesce(ta.rating_count, 0) + coalesce(ba.rating_count, 0),
    coalesce(ta.ratings, '[]'::jsonb),
    coalesce(ba.ratings, '[]'::jsonb)
  from report_users ru
  join auth.users u on u.id = ru.user_id
  left join tapa_activity ta on ta.festival_id = ru.festival_id and ta.user_id = ru.user_id
  left join bar_activity ba on ba.festival_id = ru.festival_id and ba.user_id = ru.user_id
  order by 5 desc, 2;
end
$$;

revoke all on function festival.user_rating_activity(uuid) from public, anon, authenticated;
grant execute on function festival.user_rating_activity(uuid) to authenticated;

comment on column festival.reviews.rating is
  'Optional public tapa rating from 1.0 through 5.0; a review row must retain either this rating or non-empty review text.';

commit;
