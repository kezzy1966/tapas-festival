-- Run only through run-withdrawn-participation-local.mjs on a disposable local database.
begin;
set local session_replication_role = replica;
\ir support/setup.sql
set local session_replication_role = origin;
insert into festival.profiles(user_id) select id from auth.users on conflict (user_id) do nothing;
insert into festival.festival_controls(festival_id) select id from festival.festivals on conflict (festival_id) do nothing;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
insert into festival.establishment_reviews(establishment_id, user_id, rating) values
  ('20000000-0000-0000-0000-000000000001', auth.uid(), 4);
insert into festival.reviews(tapa_id, user_id, rating, review_text) values
  ('30000000-0000-0000-0000-000000000002', auth.uid(), 4, 'Historic review');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
insert into festival.establishment_reviews(establishment_id, user_id, rating) values
  ('20000000-0000-0000-0000-000000000001', auth.uid(), 4);
update festival.establishments set participation_status = 'withdrawn'
where id = '20000000-0000-0000-0000-000000000001';
select pg_temp.assert_true((select participation_status = 'withdrawn' from festival.establishments where id = '20000000-0000-0000-0000-000000000001'), 'suspended establishment remains present as withdrawn');

-- The guard bypasses administrators, allowing their existing own contributions to be managed.
update festival.establishment_reviews set rating = 5
where establishment_id = '20000000-0000-0000-0000-000000000001' and user_id = auth.uid();
update festival.reviews set rating = 4
where id = '40000000-0000-0000-0000-000000000001';
select pg_temp.assert_true((select rating = 5 from festival.establishment_reviews where establishment_id = '20000000-0000-0000-0000-000000000001' and user_id = auth.uid())
  and (select rating = 4 from festival.reviews where id = '40000000-0000-0000-0000-000000000001'), 'administrator bypass remains functional for withdrawn establishment participation');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
select pg_temp.expect_error('insert into festival.establishment_reviews(establishment_id,user_id,rating) values (''20000000-0000-0000-0000-000000000001'',auth.uid(),4)', '42501', 'ordinary user cannot add rating to withdrawn bar');
select pg_temp.expect_error('insert into festival.reviews(tapa_id,user_id,rating,review_text) values (''30000000-0000-0000-0000-000000000002'',auth.uid(),4,''New review'')', '42501', 'ordinary user cannot add rating or review to tapa belonging to withdrawn bar');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select pg_temp.expect_error('update festival.establishment_reviews set rating = 5 where establishment_id = ''20000000-0000-0000-0000-000000000001'' and user_id = auth.uid()', '42501', 'ordinary user cannot change existing bar rating');
with removed as (delete from festival.establishment_reviews where establishment_id = '20000000-0000-0000-0000-000000000001' and user_id = auth.uid() returning *)
select pg_temp.assert_true((select count(*) = 1 from removed), 'ordinary user can remove existing bar rating');
select pg_temp.expect_error('update festival.reviews set rating = 5 where tapa_id = ''30000000-0000-0000-0000-000000000002'' and user_id = auth.uid()', '42501', 'ordinary user cannot change existing tapa rating');
select pg_temp.expect_error('update festival.reviews set review_text = ''Changed review'' where tapa_id = ''30000000-0000-0000-0000-000000000002'' and user_id = auth.uid()', '42501', 'ordinary user cannot edit existing tapa review');
update festival.reviews set review_text = null
where tapa_id = '30000000-0000-0000-0000-000000000002' and user_id = auth.uid();
select pg_temp.assert_true((select review_text is null from festival.reviews where tapa_id = '30000000-0000-0000-0000-000000000002' and user_id = auth.uid()), 'ordinary user can remove existing written review');
with removed as (delete from festival.reviews where tapa_id = '30000000-0000-0000-0000-000000000002' and user_id = auth.uid() returning *)
select pg_temp.assert_true((select count(*) = 1 from removed), 'ordinary user can remove existing tapa rating');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
update festival.establishments set participation_status = 'active'
where id = '20000000-0000-0000-0000-000000000001';
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
insert into festival.establishment_reviews(establishment_id, user_id, rating) values
  ('20000000-0000-0000-0000-000000000001', auth.uid(), 4);
insert into festival.reviews(tapa_id, user_id, rating, review_text) values
  ('30000000-0000-0000-0000-000000000002', auth.uid(), 4, 'Returned after reactivation');
select pg_temp.assert_true((select count(*) = 1 from festival.establishment_reviews where establishment_id = '20000000-0000-0000-0000-000000000001' and user_id = auth.uid())
  and (select count(*) = 1 from festival.reviews where tapa_id = '30000000-0000-0000-0000-000000000002' and user_id = auth.uid()), 'reactivated bar permits ordinary participation again');

rollback;
