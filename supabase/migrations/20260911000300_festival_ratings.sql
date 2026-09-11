-- Phase 1A: live derived statistics, never stored positions or authoritative totals.
begin;

create view festival.tapa_rating_stats with (security_invoker = true) as
select
  t.id as tapa_id,
  f.id as festival_id,
  count(r.id) as rating_count,
  avg(r.rating) as average_rating,
  count(r.id) filter (where r.rating >= 4) as good_excellent_count,
  100.0 * count(r.id) filter (where r.rating >= 4) / nullif(count(r.id), 0) as good_excellent_percentage
from festival.tapas t
join festival.establishments e on e.id = t.establishment_id
join festival.festivals f on f.id = e.festival_id
left join festival.reviews r on r.tapa_id = t.id and r.moderation_status = 'visible'
where t.is_published and e.is_published and f.publication_status in ('published', 'archived')
group by t.id, f.id;

-- Explicit public filters are essential: admins/owners can see hidden base rows.
-- Withdrawn content retains its historical stats. Filter participation when ranking.
revoke all on festival.tapa_rating_stats from public, anon, authenticated;
grant select on festival.tapa_rating_stats to anon, authenticated;

comment on view festival.tapa_rating_stats is
  'Public published/archived tapa statistics from visible reviews only; includes withdrawn tapas. Order a participating leaderboard by average_rating DESC NULLS LAST, rating_count DESC, tapa_id ASC.';

commit;
