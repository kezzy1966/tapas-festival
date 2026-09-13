-- Allow one-decimal public ratings while preserving existing rows, ownership, RLS, and derived aggregates.
begin;

-- PostgreSQL protects a view's dependent column type. Recreate the unchanged,
-- read-only aggregates atomically around the type changes.
drop view festival.tapa_rating_stats;
drop view festival.establishment_rating_stats;

alter table festival.reviews
  alter column rating type numeric(2,1) using rating::numeric(2,1);
alter table festival.reviews drop constraint reviews_rating_check;
alter table festival.reviews
  add constraint reviews_rating_check check (rating between 1.0 and 5.0);

alter table festival.establishment_reviews
  alter column rating type numeric(2,1) using rating::numeric(2,1);
alter table festival.establishment_reviews drop constraint establishment_reviews_rating_check;
alter table festival.establishment_reviews
  add constraint establishment_reviews_rating_check check (rating between 1.0 and 5.0);

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

create view festival.establishment_rating_stats with (security_invoker = true) as
select
  e.id as establishment_id,
  f.id as festival_id,
  count(r.id) as rating_count,
  avg(r.rating) as average_rating
from festival.establishments e
join festival.festivals f on f.id = e.festival_id
left join festival.establishment_reviews r on r.establishment_id = e.id
where e.is_published and f.publication_status in ('published', 'archived')
group by e.id, f.id;

revoke all on festival.tapa_rating_stats, festival.establishment_rating_stats from public, anon, authenticated;
grant select on festival.tapa_rating_stats, festival.establishment_rating_stats to anon, authenticated;

comment on view festival.tapa_rating_stats is
  'Public published/archived tapa statistics from visible reviews only; includes withdrawn tapas.';
comment on column festival.reviews.rating is
  'A public tapa rating from 1.0 through 5.0, stored to one decimal place.';
comment on column festival.establishment_reviews.rating is
  'A public establishment rating from 1.0 through 5.0, stored to one decimal place.';

commit;
