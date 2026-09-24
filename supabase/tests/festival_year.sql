-- Run only on a disposable local database; see README.md.
begin;
\ir support/setup.sql

select pg_temp.assert_true(
  (select count(*) = 4 from festival.festivals where festival_year is not null)
  and (select count(*) = 4 from festival.festivals where festival_year between 2000 and 2100),
  'fixture festivals have valid required edition years'
);
select pg_temp.assert_true(
  (select count(*) = 2 from festival.festivals where festival_year = 2025),
  'festival year is intentionally not unique'
);

rollback;
