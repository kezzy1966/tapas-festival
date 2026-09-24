-- Run only on a disposable local database; see README.md. All fixtures roll back.
begin;
\ir support/setup.sql

select pg_temp.assert_true((select count(*) = 9 from pg_class c join pg_namespace n on n.oid = c.relnamespace
  where n.nspname in ('festival', 'festival_private') and c.relkind = 'r' and c.relrowsecurity), 'RLS enabled on all nine tables');
select pg_temp.assert_true((select bool_and(p.proconfig @> array['search_path=""']) from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'festival_private' and p.prosecdef), 'all definer functions have a fixed empty search path');
select pg_temp.assert_true(not has_function_privilege('authenticated', 'festival_private.validate_field_graph()', 'EXECUTE')
  and not has_function_privilege('anon', 'festival_private.create_profile()', 'EXECUTE'), 'trigger-only definer functions are not callable by clients');
select pg_temp.assert_true((select display_name = 'Festival visitor' from festival.profiles
  where user_id = '00000000-0000-0000-0000-000000000002'), 'signup profile ignores email and untrusted metadata');

set local role anon;
select set_config('request.jwt.claims', '{}', true);
select pg_temp.assert_true(not festival_private.is_admin(), 'anonymous visitor is not admin');
select pg_temp.assert_true((select count(*) = 3 from festival.festivals), 'anonymous can browse published and archived festivals, not drafts');
select pg_temp.assert_true((select count(*) = 5 from festival.establishments), 'anonymous establishment visibility follows parent festival');
select pg_temp.assert_true((select count(*) = 7 from festival.tapas), 'anonymous tapa visibility follows entire parent chain');
select pg_temp.assert_true((select count(*) = 3 from festival.reviews), 'anonymous sees only public visible reviews');
select pg_temp.assert_true((select count(*) = 2 from festival.field_definitions), 'anonymous sees only active public definitions');
select pg_temp.assert_true((select count(*) = 2 from festival.field_values), 'anonymous sees only values on public targets and active definitions');
select pg_temp.assert_true((select count(*) = 1 from festival.establishments where participation_status = 'withdrawn'), 'withdrawn establishment remains public');
select pg_temp.assert_true((select count(*) = 1 from festival.establishments where closure_status = 'temporarily_closed'), 'closed establishment remains public');
select pg_temp.assert_true((select count(*) = 1 from festival.tapas where participation_status = 'withdrawn'), 'withdrawn tapa remains public');
select pg_temp.expect_error('select * from festival_private.admin_users', '42501', 'anonymous cannot read administrator membership');
select pg_temp.expect_error($q$insert into festival.reviews(tapa_id, user_id, rating) values
  ('30000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002',5)$q$, '42501', 'anonymous cannot submit reviews');
select pg_temp.expect_error('update festival.festivals set reviews_enabled = false', '42501', 'anonymous cannot modify content');
select pg_temp.expect_error('delete from festival.reviews', '42501', 'anonymous cannot delete reviews');

set local role authenticated;
select pg_temp.expect_error($q$insert into festival.reviews(tapa_id, user_id, rating) values
  ('30000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002',5)$q$, '42501', 'authenticated role without a user cannot submit');
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select pg_temp.assert_true(not festival_private.is_admin(), 'user metadata cannot make Alice admin');
select pg_temp.assert_true((select count(*) = 4 from festival.reviews), 'author can see own review under a draft parent but not another user hidden review');
select pg_temp.expect_error('select * from festival_private.admin_users', '42501', 'ordinary user cannot read administrator membership');
select pg_temp.expect_error($q$insert into festival_private.admin_users(user_id) values ('00000000-0000-0000-0000-000000000002')$q$, '42501', 'user cannot self-appoint as administrator');
select pg_temp.expect_error($q$update festival.profiles set user_id = '00000000-0000-0000-0000-000000000001'$q$, '42501', 'profile identity has no update grant');
select pg_temp.expect_error('update festival.profiles set created_at = now()', '42501', 'profile creation time has no update grant');
select pg_temp.expect_error($q$insert into festival.profiles(user_id) values ('00000000-0000-0000-0000-000000000002')$q$, '42501', 'profiles can only be provisioned by trusted signup code');
update festival.profiles set display_name = 'Alice', avatar_url = 'https://example.invalid/avatar.png'
where user_id = '00000000-0000-0000-0000-000000000002';
select pg_temp.assert_true((select display_name = 'Alice' from festival.profiles where user_id = auth.uid()), 'user can update allowed profile fields');
with changed as (update festival.profiles set display_name = 'Tampered' where user_id = '00000000-0000-0000-0000-000000000003' returning *)
select pg_temp.assert_true((select count(*) = 0 from changed), 'user cannot update another profile');
with changed as (update festival.festivals set reviews_enabled = false returning *)
select pg_temp.assert_true((select count(*) = 0 from changed), 'user cannot update festivals');
with changed as (update festival.establishments set name = 'Tampered' returning *)
select pg_temp.assert_true((select count(*) = 0 from changed), 'user cannot update establishments');
with changed as (update festival.tapas set name_en = 'Tampered' returning *)
select pg_temp.assert_true((select count(*) = 0 from changed), 'user cannot update tapas');
with changed as (update festival.field_definitions set active = false returning *)
select pg_temp.assert_true((select count(*) = 0 from changed), 'user cannot update field definitions');
with changed as (update festival.field_values set value = 'false' returning *)
select pg_temp.assert_true((select count(*) = 0 from changed), 'user cannot update field values');
select pg_temp.expect_error($q$insert into festival.tapas(establishment_id,name_en) values ('20000000-0000-0000-0000-000000000001','Unauthorised')$q$, '42501', 'user cannot insert festival content');
with changed as (update festival.reviews set rating = 1 where id = '40000000-0000-0000-0000-000000000001' returning *)
select pg_temp.assert_true((select count(*) = 0 from changed), 'user cannot update another review');
with changed as (delete from festival.reviews where id = '40000000-0000-0000-0000-000000000001' returning *)
select pg_temp.assert_true((select count(*) = 0 from changed), 'user cannot delete another review');
select pg_temp.expect_error($q$update festival.reviews set moderation_status = 'hidden' where id = '40000000-0000-0000-0000-000000000002'$q$, '42501', 'owner cannot change moderation state');
select pg_temp.expect_error($q$update festival.reviews set tapa_id = '30000000-0000-0000-0000-000000000002'$q$, '42501', 'review target is protected by column grants');
select pg_temp.expect_error($q$update festival.reviews set user_id = '00000000-0000-0000-0000-000000000003'$q$, '42501', 'review author is protected by column grants');
select pg_temp.expect_error('update festival.reviews set id = gen_random_uuid()', '42501', 'review ID is protected by column grants');
select pg_temp.expect_error('update festival.reviews set created_at = now()', '42501', 'review creation time is protected by column grants');
select pg_temp.expect_error('update festival.reviews set updated_at = now()', '42501', 'review update time is database managed');
select pg_temp.expect_error($q$insert into festival.reviews(tapa_id,user_id,rating,moderation_status) values
  ('30000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002',4,'hidden')$q$, '42501', 'client cannot supply moderation status on insert');
select pg_temp.expect_error($q$insert into festival.reviews(tapa_id,user_id,rating) values
  ('30000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000003',4)$q$, '42501', 'cannot submit on behalf of another user');
select pg_temp.expect_error($q$insert into festival.reviews(tapa_id,user_id,rating) values
  ('30000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000002',4)$q$, '42501', 'withdrawn tapa cannot receive new ratings');
select pg_temp.expect_error($q$insert into festival.reviews(tapa_id,user_id,rating) values
  ('30000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000002',4)$q$, '42501', 'withdrawn establishment cannot receive new ratings');
select pg_temp.expect_error($q$insert into festival.reviews(tapa_id,user_id,rating) values
  ('30000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000002',4)$q$, '42501', 'draft festival cannot receive new ratings');
select pg_temp.expect_error($q$insert into festival.reviews(tapa_id,user_id,rating) values
  ('30000000-0000-0000-0000-000000000007','00000000-0000-0000-0000-000000000002',4)$q$, '42501', 'unpublished establishment cannot receive new ratings');
select pg_temp.expect_error($q$insert into festival.reviews(tapa_id,user_id,rating) values
  ('30000000-0000-0000-0000-000000000008','00000000-0000-0000-0000-000000000002',4)$q$, '42501', 'unpublished tapa cannot receive new ratings');
select pg_temp.expect_error($q$insert into festival.reviews(tapa_id,user_id,rating) values
  ('30000000-0000-0000-0000-000000000009','00000000-0000-0000-0000-000000000002',4)$q$, '42501', 'archived festival is read only even when reviews_enabled remains true');
select pg_temp.expect_error($q$insert into festival.reviews(tapa_id,user_id,rating) values
  ('30000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000002',4)$q$, '42501', 'reviews_enabled false blocks submission');

insert into festival.reviews(tapa_id,user_id,rating) values
  ('30000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002',4),
  ('30000000-0000-0000-0000-000000000006','00000000-0000-0000-0000-000000000002',4);
select pg_temp.assert_true((select count(*) = 2 from festival.reviews where user_id = auth.uid()
  and tapa_id in ('30000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000006')), 'past festival dates, closed hours, and closure status do not block eligible reviews');
select pg_temp.expect_error($q$insert into festival.reviews(tapa_id,user_id,rating) values
  ('30000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002',5)$q$, '23505', 'one review per user per tapa');
update festival.reviews set rating = 5, review_text = 'Excellent' where user_id = auth.uid() and tapa_id = '30000000-0000-0000-0000-000000000002';
select pg_temp.assert_true((select rating = 5 and review_text = 'Excellent' and updated_at >= created_at from festival.reviews
  where user_id = auth.uid() and tapa_id = '30000000-0000-0000-0000-000000000002'), 'owner may update own rating and text');

-- Bob sees his hidden review and can edit it without un-hiding it.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
select pg_temp.assert_true((select moderation_status = 'hidden' from festival.reviews where id = '40000000-0000-0000-0000-000000000003'), 'author can read hidden review');
update festival.reviews set review_text = 'Edited while hidden' where id = '40000000-0000-0000-0000-000000000003';
select pg_temp.assert_true((select moderation_status = 'hidden' from festival.reviews where id = '40000000-0000-0000-0000-000000000003'), 'editing a hidden review preserves moderation state');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select pg_temp.assert_true(festival_private.is_admin(), 'appointed administrator is recognised');
select pg_temp.expect_error('select * from festival_private.admin_users', '42501', 'even app admins do not directly browse membership');
select pg_temp.assert_true((select count(*) = 4 from festival.festivals), 'administrator can read drafts');
update festival.festivals set reviews_enabled = false where id = '10000000-0000-0000-0000-000000000001';
update festival.festivals set reviews_enabled = true where id = '10000000-0000-0000-0000-000000000004';
update festival.establishments set name = 'Admin edited venue' where id = '20000000-0000-0000-0000-000000000001';
update festival.tapas set name_en = 'Admin edited tapa' where id = '30000000-0000-0000-0000-000000000001';
update festival.field_definitions set label_en = 'Admin edited label' where id = '50000000-0000-0000-0000-000000000001';
update festival.field_values set value = 'false' where id = '60000000-0000-0000-0000-000000000001';
select pg_temp.assert_true((select name = 'Admin edited venue' from festival.establishments where id = '20000000-0000-0000-0000-000000000001')
  and (select name_en = 'Admin edited tapa' from festival.tapas where id = '30000000-0000-0000-0000-000000000001')
  and (select label_en = 'Admin edited label' from festival.field_definitions where id = '50000000-0000-0000-0000-000000000001')
  and (select value = 'false'::jsonb from festival.field_values where id = '60000000-0000-0000-0000-000000000001'), 'administrator can manage content and custom fields');
update festival.reviews set moderation_status = 'hidden' where id = '40000000-0000-0000-0000-000000000002';
select pg_temp.assert_true((select moderation_status = 'hidden' from festival.reviews where id = '40000000-0000-0000-0000-000000000002'), 'administrator may moderate after voting closes');
select pg_temp.expect_error($q$update festival.reviews set rating = 2 where id = '40000000-0000-0000-0000-000000000002'$q$, '42501', 'administrator cannot rewrite another author rating');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select pg_temp.expect_error($q$update festival.reviews set rating = 2 where id = '40000000-0000-0000-0000-000000000002'$q$, '42501', 'voting switch also closes owner edits');
with changed as (delete from festival.reviews where id = '40000000-0000-0000-0000-000000000002' returning *)
select pg_temp.assert_true((select count(*) = 1 from changed), 'owner may delete hidden review after voting closes');
insert into festival.reviews(tapa_id,user_id,rating) values
  ('30000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000002',4);
select pg_temp.assert_true((select count(*) = 1 from festival.reviews where tapa_id = '30000000-0000-0000-0000-000000000010' and user_id = auth.uid()), 'future festival accepts reviews once admin enables them');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
with changed as (delete from festival.reviews where id = '40000000-0000-0000-0000-000000000003' returning *)
select pg_temp.assert_true((select count(*) = 1 from changed), 'administrator may delete moderated reviews');
rollback;
