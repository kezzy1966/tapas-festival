begin;
\ir support/setup.sql
select pg_temp.assert_true((select reloptions @> array['security_invoker=true'] from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'festival' and c.relname = 'tapa_rating_stats'), 'statistics view is security invoker');
set local role anon;
select set_config('request.jwt.claims', '{}', true);
select pg_temp.assert_true((select rating_count = 2 and average_rating = 4 and good_excellent_count = 1 and good_excellent_percentage = 50
  from festival.tapa_rating_stats where tapa_id = '30000000-0000-0000-0000-000000000001'), 'public totals exclude hidden reviews and include 4/5 only as good/excellent');
select pg_temp.assert_true((select rating_count = 0 and average_rating is null and good_excellent_count = 0 and good_excellent_percentage is null
  from festival.tapa_rating_stats where tapa_id = '30000000-0000-0000-0000-000000000002'), 'unrated tapa has zero count and NULL average/percentage');
select pg_temp.assert_true((select rating_count = 1 and average_rating = 4 and good_excellent_count = 1 and good_excellent_percentage = 100
  from festival.tapa_rating_stats where tapa_id = '30000000-0000-0000-0000-000000000003'), 'withdrawn tapa keeps historical statistics');
select pg_temp.assert_true((select count(*) = 7 from festival.tapa_rating_stats), 'draft festival, establishment and tapa excluded from statistics');
select pg_temp.expect_error('update festival.tapa_rating_stats set rating_count = 9', '55000', 'aggregate view is not updatable');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
select pg_temp.assert_true((select rating_count = 2 and average_rating = 4 from festival.tapa_rating_stats
  where tapa_id = '30000000-0000-0000-0000-000000000001'), 'hidden author sees the same public aggregate');
update festival.reviews set rating = 5 where id = '40000000-0000-0000-0000-000000000003';
select pg_temp.assert_true((select rating_count = 2 and average_rating = 4 from festival.tapa_rating_stats
  where tapa_id = '30000000-0000-0000-0000-000000000001'), 'editing hidden rating does not change public score');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select pg_temp.assert_true((select count(*) = 7 from festival.tapa_rating_stats), 'admin does not gain draft rows through public stats view');
select pg_temp.assert_true((select rating_count = 2 and average_rating = 4 from festival.tapa_rating_stats
  where tapa_id = '30000000-0000-0000-0000-000000000001'), 'admin does not count hidden reviews in public score');
update festival.reviews set moderation_status = 'visible' where id = '40000000-0000-0000-0000-000000000003';
select pg_temp.assert_true((select rating_count = 3 and abs(average_rating - 13.0/3) < 0.00000001
  and good_excellent_count = 2 and abs(good_excellent_percentage - 200.0/3) < 0.00000001
  from festival.tapa_rating_stats where tapa_id = '30000000-0000-0000-0000-000000000001'), 'unhiding immediately updates unrounded statistics');
update festival.reviews set moderation_status = 'hidden' where tapa_id = '30000000-0000-0000-0000-000000000001';
select pg_temp.assert_true((select rating_count = 0 and average_rating is null and good_excellent_percentage is null
  from festival.tapa_rating_stats where tapa_id = '30000000-0000-0000-0000-000000000001'), 'all-hidden reviews behave like no public ratings');
update festival.reviews set moderation_status = 'visible' where id = '40000000-0000-0000-0000-000000000002';

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
update festival.reviews set rating = 4 where id = '40000000-0000-0000-0000-000000000002';
select pg_temp.assert_true((select rating_count = 1 and average_rating = 4 and good_excellent_count = 1
  from festival.tapa_rating_stats where tapa_id = '30000000-0000-0000-0000-000000000001'), 'visible rating edits immediately update statistics');
delete from festival.reviews where id = '40000000-0000-0000-0000-000000000002';
select pg_temp.assert_true((select rating_count = 0 and average_rating is null from festival.tapa_rating_stats
  where tapa_id = '30000000-0000-0000-0000-000000000001'), 'review deletion immediately updates statistics');

set local role anon;
select set_config('request.jwt.claims', '{}', true);
select pg_temp.assert_true(not exists (
  select 1 from festival.tapa_rating_stats s
  join festival.tapas t on t.id = s.tapa_id join festival.establishments e on e.id = t.establishment_id
  where t.participation_status = 'active' and e.participation_status = 'active'
    and t.id in ('30000000-0000-0000-0000-000000000003','30000000-0000-0000-0000-000000000005')
), 'participation filter removes withdrawn tapas and withdrawn venues from leaderboard');
rollback;
