-- Fast public tapa aggregates and an index for recent-rating activity.
begin;

-- This deliberately exposes only the aggregate fields already used by the
-- public ranking. It does not return review, user, or private-schema data.
create function festival.public_tapa_rating_stats(p_festival_id uuid)
returns table (
  tapa_id uuid,
  festival_id uuid,
  rating_count bigint,
  average_rating numeric,
  good_excellent_count bigint,
  good_excellent_percentage numeric
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    t.id as tapa_id,
    f.id as festival_id,
    count(r.rating)::bigint as rating_count,
    avg(r.rating) as average_rating,
    count(r.rating) filter (where r.rating >= 4.0)::bigint as good_excellent_count,
    100.0 * count(r.rating) filter (where r.rating >= 4.0)
      / nullif(count(r.rating), 0) as good_excellent_percentage
  from festival.tapas t
  join festival.establishments e on e.id = t.establishment_id
  join festival.festivals f on f.id = e.festival_id
  left join festival.reviews r on r.tapa_id = t.id
    and r.moderation_status = 'visible'
    and r.rating is not null
  where f.id = p_festival_id
    and f.publication_status = 'published'
    and e.is_published
    and t.is_published
  group by t.id, f.id;
$$;

revoke all on function festival.public_tapa_rating_stats(uuid) from public, anon, authenticated;
grant execute on function festival.public_tapa_rating_stats(uuid) to anon, authenticated;

-- Matches Trending's per-tapa, recent, visible numeric-rating lookup.
create index reviews_visible_numeric_tapa_created_idx
  on festival.reviews (tapa_id, created_at)
  where moderation_status = 'visible' and rating is not null;

commit;
