-- Focused disposable tests for user suspension. Included only by the local runner.
begin;
set local session_replication_role = replica;
\ir support/setup.sql
insert into festival.profiles(user_id) select id from auth.users on conflict (user_id) do nothing;
insert into festival.festival_controls(festival_id) select id from festival.festivals on conflict (festival_id) do nothing;
set local session_replication_role = origin;

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
set local role authenticated;
select pg_temp.assert_true(exists (select 1 from festival.tapas t join festival.establishments e on e.id = t.establishment_id where t.id = '30000000-0000-0000-0000-000000000002' and t.participation_status = 'active' and e.participation_status = 'active'), 'active tapa fixture is eligible');
select pg_temp.assert_true(festival_private.can_review_tapa('30000000-0000-0000-0000-000000000002'), 'active tapa helper permits participation');

select pg_temp.assert_true((select festival_private.is_user_suspended((select auth.uid()))) = false, 'active user starts unsuspended');
insert into festival.reviews(tapa_id, user_id, rating, review_text)
values ('30000000-0000-0000-0000-000000000002', (select auth.uid()), 4, 'Initial review');
select pg_temp.assert_true((select rating from festival.reviews where tapa_id = '30000000-0000-0000-0000-000000000002' and user_id = (select auth.uid())) = 4, 'active user can insert a tapa rating and review');
update festival.reviews set rating = 4.5, review_text = 'Updated review' where tapa_id = '30000000-0000-0000-0000-000000000002' and user_id = (select auth.uid());
select pg_temp.assert_true((select review_text from festival.reviews where tapa_id = '30000000-0000-0000-0000-000000000002' and user_id = (select auth.uid())) = 'Updated review', 'active user can update rating and review');
insert into festival.establishment_reviews(establishment_id, user_id, rating)
values ('20000000-0000-0000-0000-000000000001', (select auth.uid()), 4.2);

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select festival.suspend_user('00000000-0000-0000-0000-000000000002', 'test suspension');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select pg_temp.assert_true((select festival.is_current_user_suspended()), 'suspended status is readable to the current user');
select pg_temp.expect_error($cmd$insert into festival.reviews(tapa_id, user_id, rating) values ('30000000-0000-0000-0000-000000000002', (select auth.uid()), 5)$cmd$, '42501', 'suspended user cannot insert a tapa rating');
select pg_temp.expect_error($cmd$update festival.reviews set rating = 4.9 where tapa_id = '30000000-0000-0000-0000-000000000002' and user_id = (select auth.uid())$cmd$, '42501', 'suspended user cannot change a tapa rating');
select pg_temp.expect_error($cmd$update festival.reviews set review_text = 'Changed while suspended' where tapa_id = '30000000-0000-0000-0000-000000000002' and user_id = (select auth.uid())$cmd$, '42501', 'suspended user cannot change review text');
select pg_temp.expect_error($cmd$insert into festival.establishment_reviews(establishment_id, user_id, rating) values ('20000000-0000-0000-0000-000000000001', (select auth.uid()), 5)$cmd$, '42501', 'suspended user cannot insert a bar rating');
select pg_temp.expect_error($cmd$update festival.establishment_reviews set rating = 4.8 where establishment_id = '20000000-0000-0000-0000-000000000001' and user_id = (select auth.uid())$cmd$, '42501', 'suspended user cannot change a bar rating');
select pg_temp.assert_true((select count(*) from festival.reviews where tapa_id = '30000000-0000-0000-0000-000000000002' and user_id = (select auth.uid())) = 1, 'suspended contributions remain readable');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select festival.set_festival_control('10000000-0000-0000-0000-000000000001', 'public_read_only', true);
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select pg_temp.expect_error($cmd$delete from festival.reviews where tapa_id = '30000000-0000-0000-0000-000000000002' and user_id = (select auth.uid())$cmd$, '42501', 'Public Read-only blocks suspended-user removal');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select festival.set_festival_control('10000000-0000-0000-0000-000000000001', 'public_read_only', false);
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
update festival.reviews set review_text = null where tapa_id = '30000000-0000-0000-0000-000000000002' and user_id = (select auth.uid());
delete from festival.reviews where tapa_id = '30000000-0000-0000-0000-000000000002' and user_id = (select auth.uid());
delete from festival.establishment_reviews where establishment_id = '20000000-0000-0000-0000-000000000001' and user_id = (select auth.uid());
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select pg_temp.expect_error($cmd$select festival.suspend_user('00000000-0000-0000-0000-000000000001', 'must fail')$cmd$, '42501', 'Suspend RPC rejects Admin target');
select festival.reactivate_user('00000000-0000-0000-0000-000000000002');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select pg_temp.assert_true((select festival.is_current_user_suspended()) = false, 'reactivation restores participation');
update festival.reviews set rating = 5 where tapa_id = '30000000-0000-0000-0000-000000000002' and user_id = (select auth.uid());
select pg_temp.assert_true((select count(*) from festival.reviews where user_id = (select auth.uid()) and rating is not null) > 0, 'reactivated user can participate again');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select pg_temp.assert_true((select festival_private.is_user_suspended((select auth.uid()))) = false, 'Admin bypass remains active');

rollback;
