-- Run only on a disposable local database; see README.md.
begin;
\ir support/setup.sql

select pg_temp.assert_true(
  (select count(*) from festival.venues) = (select count(*) from festival.establishments)
  and not exists (select 1 from festival.establishments where venue_id is null)
  and (select count(distinct venue_id) from festival.establishments) = (select count(*) from festival.establishments),
  'fixture establishments each have one distinct required venue link'
);
select pg_temp.assert_true(
  not exists (
    select 1 from festival.tapas t left join festival.establishments e on e.id = t.establishment_id where e.id is null
  ) and not exists (
    select 1 from festival.reviews r left join festival.tapas t on t.id = r.tapa_id where t.id is null
  ),
  'venue links leave tapa and review relationships unchanged'
);

set local role anon;
select set_config('request.jwt.claims', '{}', true);
select pg_temp.expect_error('select * from festival.venues', '42501', 'anon has no direct venue table access');
select pg_temp.expect_error($q$insert into festival.venues(canonical_name) values ('Anon venue')$q$, '42501', 'anon cannot insert venues');
select pg_temp.expect_error($q$update festival.venues set canonical_name = 'Tampered'$q$, '42501', 'anon cannot update venues');
select pg_temp.expect_error('delete from festival.venues', '42501', 'anon cannot delete venues');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select pg_temp.assert_true((select count(*) = 0 from festival.venues), 'ordinary authenticated user cannot read venues');
select pg_temp.expect_error($q$insert into festival.venues(canonical_name) values ('Unauthorised venue')$q$, '42501', 'ordinary authenticated user cannot insert venues');
with changed as (update festival.venues set canonical_name = 'Tampered' returning *)
select pg_temp.assert_true((select count(*) = 0 from changed), 'ordinary authenticated user cannot modify venues');
select pg_temp.expect_error('delete from festival.venues', '42501', 'ordinary authenticated user cannot delete venues');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select pg_temp.assert_true((select count(*) = 7 from festival.venues), 'administrator can select venues');
insert into festival.venues(canonical_name, canonical_address, canonical_phone) values
  ('Shared venue', 'Admin address', '123');
update festival.venues set canonical_phone = '456' where canonical_name = 'Shared venue';
select pg_temp.assert_true((select canonical_phone = '456' from festival.venues where canonical_name = 'Shared venue'), 'administrator can insert and update permitted canonical fields');
select pg_temp.expect_error($q$update festival.venues set id = gen_random_uuid() where canonical_name = 'Shared venue'$q$, '42501', 'administrator cannot update venue ID');
select pg_temp.expect_error($q$update festival.venues set created_at = now() where canonical_name = 'Shared venue'$q$, '42501', 'administrator cannot update venue creation time');
select pg_temp.expect_error($q$update festival.venues set updated_at = now() where canonical_name = 'Shared venue'$q$, '42501', 'administrator cannot update database-managed venue update time');
select pg_temp.assert_true(not has_table_privilege('authenticated', 'festival.venues', 'DELETE'), 'authenticated and administrators have no venue delete table privilege');
insert into festival.establishments(id, festival_id, venue_id, name, address, latitude, longitude) values
  ('20000000-0000-0000-0000-000000000009', '10000000-0000-0000-0000-000000000003', (select id from festival.venues where canonical_name = 'Shared venue'), 'Shared venue 2024', 'Test address', 39.98, -0.04),
  ('20000000-0000-0000-0000-000000000010', '10000000-0000-0000-0000-000000000004', (select id from festival.venues where canonical_name = 'Shared venue'), 'Shared venue 2026', 'Test address', 39.98, -0.04);
select pg_temp.assert_true((select count(*) = 2 from festival.establishments where venue_id = (select id from festival.venues where canonical_name = 'Shared venue')), 'one venue can participate in different festivals');
select pg_temp.expect_error($q$insert into festival.establishments(id, festival_id, venue_id, name, address, latitude, longitude) values
  ('20000000-0000-0000-0000-000000000011', '10000000-0000-0000-0000-000000000003', (select id from festival.venues where canonical_name = 'Shared venue'), 'Duplicate participation', 'Test address', 39.98, -0.04)$q$, '23505', 'one venue cannot participate twice in one festival');

rollback;
