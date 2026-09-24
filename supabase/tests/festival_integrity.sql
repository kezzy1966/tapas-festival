begin;
\ir support/setup.sql
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000001","role":"authenticated"}', true);

select pg_temp.assert_true((select name_en is not null and name_es is null and default_language = 'en' from festival.festivals where slug = 'test-public'), 'English-only festival and English default are valid');
select pg_temp.assert_true((select name_en is null and name_es is not null from festival.festivals where slug = 'test-draft'), 'Spanish-only festival is valid');
select pg_temp.assert_true((select festival_year = 2025 and extract(year from start_date) = 2000 from festival.festivals where slug = 'test-public'), 'edition year is independent of operational start date');
select pg_temp.expect_error($q$update festival.festivals set festival_year = null where slug = 'test-public'$q$, '23502', 'festival year is required');
select pg_temp.expect_error($q$update festival.festivals set festival_year = 1999 where slug = 'test-public'$q$, '23514', 'festival year below 2000 rejected');
select pg_temp.expect_error($q$update festival.festivals set festival_year = 2101 where slug = 'test-public'$q$, '23514', 'festival year above 2100 rejected');
insert into festival.festivals(slug, name_en, festival_year, start_date, end_date, default_tapa_price, city) values
  ('same-edition-year-one', 'Same edition year one', 2026, '2000-01-01', '2000-01-02', 5, 'Castellón'),
  ('same-edition-year-two', 'Same edition year two', 2026, '2100-01-01', '2100-01-02', 5, 'Castellón');
select pg_temp.assert_true((select count(*) = 2 from festival.festivals where festival_year = 2026), 'multiple festival rows may share an edition year');
update festival.festivals set default_language = 'es', name_es = 'Festival público' where slug = 'test-public';
select pg_temp.assert_true((select default_language = 'es' and name_en is not null and name_es is not null from festival.festivals where slug = 'test-public'), 'both translations and changing default language need no schema change');
select pg_temp.expect_error($q$update festival.festivals set name_en = ' ', name_es = null where slug = 'test-public'$q$, '23514', 'at least one festival name required');
select pg_temp.expect_error($q$update festival.tapas set name_en = null, name_es = '' where id = '30000000-0000-0000-0000-000000000001'$q$, '23514', 'at least one tapa name required');
select pg_temp.expect_error($q$update festival.field_definitions set label_en = null, label_es = ' ' where id = '50000000-0000-0000-0000-000000000001'$q$, '23514', 'at least one custom label required');
select pg_temp.expect_error($q$update festival.festivals set end_date = '1999-01-01' where slug = 'test-public'$q$, '23514', 'festival date order validated');
select pg_temp.expect_error($q$update festival.festivals set default_language = 'fr' where slug = 'test-public'$q$, '23514', 'default language is bounded to en/es');
select pg_temp.expect_error($q$update festival.festivals set timezone = 'Mars/Olympus' where slug = 'test-public'$q$, '23514', 'timezone must exist');
select pg_temp.expect_error($q$update festival.festivals set currency_code = 'eur' where slug = 'test-public'$q$, '23514', 'currency format validated');
select pg_temp.expect_error($q$update festival.festivals set default_tapa_price = -1 where slug = 'test-public'$q$, '23514', 'negative festival price rejected');
select pg_temp.expect_error($q$update festival.festivals set default_tapa_price = 'NaN' where slug = 'test-public'$q$, '23514', 'non-finite numeric price rejected');
select pg_temp.expect_error($q$update festival.tapas set price_override = -1 where id = '30000000-0000-0000-0000-000000000001'$q$, '23514', 'negative override rejected');
select pg_temp.expect_error($q$update festival.festivals set slug = 'test-public' where slug = 'test-draft'$q$, '23505', 'festival slug unique');
select pg_temp.expect_error($q$update festival.establishments set latitude = 91 where id = '20000000-0000-0000-0000-000000000001'$q$, '23514', 'invalid latitude rejected');
select pg_temp.expect_error($q$update festival.establishments set longitude = 181 where id = '20000000-0000-0000-0000-000000000001'$q$, '23514', 'invalid longitude rejected');
select pg_temp.expect_error($q$update festival.establishments set latitude = null where id = '20000000-0000-0000-0000-000000000001'$q$, '23514', 'partial coordinates rejected');
select pg_temp.expect_error($q$update festival.establishments set is_published = true where id = '20000000-0000-0000-0000-000000000005'$q$, '23514', 'publishing a map venue requires coordinates');
select pg_temp.assert_true(festival_private.valid_opening_hours(null)
  and festival_private.valid_opening_hours('{}')
  and festival_private.valid_opening_hours('{"1":[],"2":[["12:00","16:00"],["19:00","23:00"]],"6":[["20:00","02:00"]]}'), 'unknown, closed, split and overnight schedules supported');
select pg_temp.expect_error($q$update festival.establishments set opening_hours = '{"0":[]}' where id = '20000000-0000-0000-0000-000000000001'$q$, '23514', 'weekday keys restricted to ISO 1-7');
select pg_temp.expect_error($q$update festival.establishments set opening_hours = '{"1":[["24:00","02:00"]]}' where id = '20000000-0000-0000-0000-000000000001'$q$, '23514', 'time syntax validated');
select pg_temp.expect_error($q$update festival.establishments set opening_hours = '{"1":[["12:00","12:00"]]}' where id = '20000000-0000-0000-0000-000000000001'$q$, '23514', 'ambiguous equal start/end rejected');
select pg_temp.expect_error($q$update festival.establishments set opening_hours = '{"1":"closed"}' where id = '20000000-0000-0000-0000-000000000001'$q$, '23514', 'opening periods require array structure');
select pg_temp.expect_error($q$update festival.tapas set festival_number = 0 where id = '30000000-0000-0000-0000-000000000001'$q$, '23514', 'programme number must be positive');
select pg_temp.assert_true((select count(*) > 2 from festival.tapas where establishment_id = '20000000-0000-0000-0000-000000000001'), 'more than two tapas permitted');
update festival.tapas set price_override = 6.25 where id = '30000000-0000-0000-0000-000000000001';
select pg_temp.assert_true((select coalesce(t.price_override, f.default_tapa_price) = 6.25 from festival.tapas t
  join festival.establishments e on e.id = t.establishment_id join festival.festivals f on f.id = e.festival_id
  where t.id = '30000000-0000-0000-0000-000000000001'), 'override determines effective price');
select pg_temp.assert_true((select coalesce(t.price_override, f.default_tapa_price) = 5 from festival.tapas t
  join festival.establishments e on e.id = t.establishment_id join festival.festivals f on f.id = e.festival_id
  where t.id = '30000000-0000-0000-0000-000000000002'), 'null override inherits default price');

select pg_temp.expect_error($q$update festival.establishments set festival_id = '10000000-0000-0000-0000-000000000002' where id = '20000000-0000-0000-0000-000000000001'$q$, '23514', 'establishment cannot move between festivals');
select pg_temp.expect_error($q$update festival.tapas set establishment_id = '20000000-0000-0000-0000-000000000002' where id = '30000000-0000-0000-0000-000000000001'$q$, '23514', 'tapa cannot move between establishments');
select pg_temp.expect_error($q$update festival.festivals set created_at = '2000-01-01' where slug = 'test-public'$q$, '23514', 'content creation timestamp immutable');
select pg_temp.expect_error($q$delete from festival.festivals where slug = 'test-public'$q$, '23503|23001', 'populated festival deletion restricted');
select pg_temp.expect_error($q$delete from festival.establishments where id = '20000000-0000-0000-0000-000000000001'$q$, '23503|23001', 'venue deletion with tapas restricted');
select pg_temp.expect_error($q$delete from festival.tapas where id = '30000000-0000-0000-0000-000000000001'$q$, '23503|23001', 'reviewed tapa deletion restricted');

select pg_temp.expect_error($q$insert into festival.field_values(field_definition_id, tapa_id, value) values
  ('50000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000004','true')$q$, '23514', 'cross-festival custom value rejected');
select pg_temp.expect_error($q$insert into festival.field_values(field_definition_id, establishment_id, value) values
  ('50000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','true')$q$, '23514', 'wrong custom entity type rejected');
select pg_temp.expect_error($q$insert into festival.field_values(field_definition_id, establishment_id, tapa_id, value) values
  ('50000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000002','true')$q$, '23514', 'two custom targets rejected');
select pg_temp.expect_error($q$insert into festival.field_values(field_definition_id, value) values
  ('50000000-0000-0000-0000-000000000001','true')$q$, '23514', 'missing custom target rejected');
select pg_temp.expect_error($q$insert into festival.field_values(field_definition_id, tapa_id, value) values
  ('50000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','true')$q$, '23505', 'duplicate custom value rejected');
select pg_temp.expect_error($q$insert into festival.field_values(field_definition_id, tapa_id, value) values
  ('50000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000002','"true"')$q$, '23514', 'boolean JSON string rejected');
select pg_temp.expect_error($q$update festival.field_values set value = 'null' where id = '60000000-0000-0000-0000-000000000001'$q$, '23514', 'JSON null is not a custom value');
select pg_temp.expect_error($q$update festival.field_values set value = '{"en":"","es":" "}' where id = '60000000-0000-0000-0000-000000000002'$q$, '23514', 'custom text requires one nonblank translation');
select pg_temp.expect_error($q$update festival.field_values set value = '{"en":42}' where id = '60000000-0000-0000-0000-000000000002'$q$, '23514', 'custom text translation must be string');
update festival.field_values set value = '{"es":"Solo español"}' where id = '60000000-0000-0000-0000-000000000002';
select pg_temp.assert_true((select value ->> 'es' = 'Solo español' from festival.field_values where id = '60000000-0000-0000-0000-000000000002'), 'Spanish-only custom text supported');
select pg_temp.expect_error($q$update festival.field_definitions set field_type = 'number' where id = '50000000-0000-0000-0000-000000000001'$q$, '23514', 'populated field type cannot change');
select pg_temp.expect_error($q$update festival.field_definitions set key = 'renamed' where id = '50000000-0000-0000-0000-000000000001'$q$, '23514', 'custom machine keys are stable');
select pg_temp.expect_error($q$update festival.field_definitions set required = true where id = '50000000-0000-0000-0000-000000000001'$q$, '23514', 'required flag cannot invalidate existing published tapas');

insert into festival.field_definitions(id,festival_id,key,label_es,field_type,applies_to,options) values
  ('50000000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000001','temperature','Temperatura','select','tapa',
   '[{"key":"hot","label_en":"Hot"},{"key":"cold","label_es":"Fría"}]');
insert into festival.field_values(field_definition_id,tapa_id,value) values
  ('50000000-0000-0000-0000-000000000005','30000000-0000-0000-0000-000000000001','"hot"');
select pg_temp.expect_error($q$insert into festival.field_values(field_definition_id,tapa_id,value) values
  ('50000000-0000-0000-0000-000000000005','30000000-0000-0000-0000-000000000002','"unknown"')$q$, '23514', 'select value must use a defined stable key');
select pg_temp.expect_error($q$update festival.field_definitions set options = '[{"key":"cold","label_en":"Cold"}]' where key = 'temperature'$q$, '23514', 'cannot remove an option that is in use');
select pg_temp.expect_error($q$update festival.field_definitions set options = '[{"key":"hot","label_en":"Hot"},{"key":"hot","label_es":"Caliente"}]' where key = 'temperature'$q$, '23514', 'duplicate select option keys rejected');
select pg_temp.expect_error($q$update festival.field_definitions set options = '[{"key":"hot","label_en":""}]' where key = 'temperature'$q$, '23514', 'select option needs one translated label');
update festival.field_definitions set options = '[{"key":"hot","label_en":"Served hot","label_es":"Caliente"},{"key":"cold","label_en":"Cold"}]' where key = 'temperature';
select pg_temp.assert_true((select options -> 0 ->> 'label_en' = 'Served hot' from festival.field_definitions where key = 'temperature'), 'select labels may change without changing stored key');

insert into festival.field_values(field_definition_id,establishment_id,value) values
  ('50000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000003','{"en":"Withdrawn venue note"}'),
  ('50000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000004','{"en":"Closed venue note"}');
update festival.field_definitions set required = true where id = '50000000-0000-0000-0000-000000000002';
select pg_temp.assert_true((select required from festival.field_definitions where id = '50000000-0000-0000-0000-000000000002'), 'required field can be enabled after published entities are populated');
select pg_temp.expect_error($q$delete from festival.field_values where id = '60000000-0000-0000-0000-000000000002'$q$, '23514', 'required published value cannot be deleted');
insert into festival.venues(canonical_name) values ('New draft');
insert into festival.establishments(id,festival_id,venue_id,name,address,latitude,longitude) values
  ('20000000-0000-0000-0000-000000000008','10000000-0000-0000-0000-000000000001',(select id from festival.venues where canonical_name = 'New draft'),'New draft','Test',39.98,-0.04);
select pg_temp.expect_error($q$update festival.establishments set is_published = true where id = '20000000-0000-0000-0000-000000000008'$q$, '23514', 'draft may omit required value but publication cannot');
set constraints all deferred;
update festival.establishments set is_published = true where id = '20000000-0000-0000-0000-000000000008';
insert into festival.field_values(field_definition_id,establishment_id,value) values
  ('50000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000008','{"en":"Ready to publish"}');
set constraints all immediate;
select pg_temp.assert_true((select is_published from festival.establishments where id = '20000000-0000-0000-0000-000000000008'), 'deferred checks permit atomic publication and value creation');
update festival.field_definitions set active = false where id = '50000000-0000-0000-0000-000000000002';
delete from festival.field_values where id = '60000000-0000-0000-0000-000000000002';
select pg_temp.assert_true(not exists(select 1 from festival.field_values where id = '60000000-0000-0000-0000-000000000002'), 'inactive field no longer imposes publication completeness');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select pg_temp.expect_error($q$insert into festival.reviews(tapa_id,user_id,rating) values
  ('30000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002',0)$q$, '23514', 'rating below one rejected');
select pg_temp.expect_error($q$insert into festival.reviews(tapa_id,user_id,rating) values
  ('30000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002',6)$q$, '23514', 'rating above five rejected');
select pg_temp.expect_error($q$insert into festival.reviews(tapa_id,user_id,rating,review_text) values
  ('30000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002',4,repeat('x',3001))$q$, '23514', 'review length bounded');

reset role;
delete from auth.users where id = '00000000-0000-0000-0000-000000000002';
select pg_temp.assert_true(not exists(select 1 from festival.profiles where user_id = '00000000-0000-0000-0000-000000000002')
  and not exists(select 1 from festival.reviews where user_id = '00000000-0000-0000-0000-000000000002'), 'account deletion cascades to profile and authored reviews');
delete from auth.users where id = '00000000-0000-0000-0000-000000000001';
select pg_temp.assert_true(not exists(select 1 from festival_private.admin_users where user_id = '00000000-0000-0000-0000-000000000001'), 'account deletion removes admin membership');
rollback;

-- A repeatable-read snapshot cannot safely validate the shared custom-field graph.
begin isolation level repeatable read;
do $$
begin
  begin
    insert into festival.festivals(slug,name_en,festival_year,start_date,end_date,default_tapa_price,city)
    values ('repeatable-read-test','Test',2025,'2000-01-01','2000-01-02',5,'Test');
    raise exception 'ASSERTION FAILED: repeatable-read content write succeeded';
  exception when sqlstate '25000' then null;
  end;
end $$;
select 'repeatable-read content writes fail closed' as assert_true;
rollback;
