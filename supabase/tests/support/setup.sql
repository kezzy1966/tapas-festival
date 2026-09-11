-- Included inside each test transaction. Synthetic fixtures; never run on production.
create function pg_temp.assert_true(condition boolean, message text)
returns text language plpgsql security invoker as $$
begin
  if condition is distinct from true then raise exception 'ASSERTION FAILED: %', message; end if;
  return message;
end $$;

create function pg_temp.expect_error(command text, expected_state text, message text)
returns text language plpgsql security invoker as $$
declare actual_state text;
begin
  begin
    execute command;
  exception when others then
    get stacked diagnostics actual_state = returned_sqlstate;
    if not (actual_state = any(string_to_array(expected_state, '|'))) then
      raise exception 'ASSERTION FAILED: %, expected SQLSTATE %, got %: %', message, expected_state, actual_state, sqlerrm;
    end if;
    return message;
  end;
  raise exception 'ASSERTION FAILED: %, expected SQLSTATE % but command succeeded', message, expected_state;
end $$;

insert into auth.users(id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-000000000001', 'admin@example.invalid', '{}'),
  ('00000000-0000-0000-0000-000000000002', 'alice-private@example.invalid', '{"is_admin":true,"display_name":"alice-private@example.invalid"}'),
  ('00000000-0000-0000-0000-000000000003', 'bob-private@example.invalid', '{}');
insert into festival_private.admin_users(user_id) values ('00000000-0000-0000-0000-000000000001');

insert into festival.festivals(id, slug, name_en, name_es, start_date, end_date, default_tapa_price, city, publication_status, reviews_enabled) values
  ('10000000-0000-0000-0000-000000000001', 'test-public', 'English festival', null, '2000-01-01', '2000-01-02', 5, 'Castellón', 'published', true),
  ('10000000-0000-0000-0000-000000000002', 'test-draft', null, 'Festival español', '2100-01-01', '2100-01-02', 6, 'Castellón', 'draft', true),
  ('10000000-0000-0000-0000-000000000003', 'test-archived', 'Archived', null, '2000-01-01', '2000-01-02', 4, 'Castellón', 'archived', true),
  ('10000000-0000-0000-0000-000000000004', 'test-disabled', 'Voting disabled', null, '2100-01-01', '2100-01-02', 7, 'Castellón', 'published', false);

insert into festival.establishments(id, festival_id, name, address, latitude, longitude, is_published, participation_status, closure_status, opening_hours) values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'Public venue', 'Test address', 39.98, -0.04, true, 'active', 'normal', '{"1":[],"2":[["12:00","16:00"],["19:00","23:00"]],"6":[["20:00","02:00"]]}'),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002', 'Draft festival venue', 'Test address', 39.98, -0.04, true, 'active', 'normal', null),
  ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', 'Withdrawn venue', 'Test address', 39.98, -0.04, true, 'withdrawn', 'normal', null),
  ('20000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000001', 'Closed venue', 'Test address', 39.98, -0.04, true, 'active', 'temporarily_closed', '{"1":[],"2":[],"3":[],"4":[],"5":[],"6":[],"7":[]}'),
  ('20000000-0000-0000-0000-000000000005', '10000000-0000-0000-0000-000000000001', 'Draft venue', 'Test address', null, null, false, 'active', 'normal', '{}'),
  ('20000000-0000-0000-0000-000000000006', '10000000-0000-0000-0000-000000000003', 'Archived venue', 'Test address', 39.98, -0.04, true, 'active', 'normal', null),
  ('20000000-0000-0000-0000-000000000007', '10000000-0000-0000-0000-000000000004', 'Disabled venue', 'Test address', 39.98, -0.04, true, 'active', 'normal', null);

insert into festival.tapas(id, establishment_id, name_en, name_es, is_published, participation_status) values
  ('30000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Rated tapa', null, true, 'active'),
  ('30000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', null, 'Sin valoraciones', true, 'active'),
  ('30000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000001', 'Withdrawn tapa', null, true, 'withdrawn'),
  ('30000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000002', 'Draft festival tapa', null, true, 'active'),
  ('30000000-0000-0000-0000-000000000005', '20000000-0000-0000-0000-000000000003', 'Withdrawn venue tapa', null, true, 'active'),
  ('30000000-0000-0000-0000-000000000006', '20000000-0000-0000-0000-000000000004', 'Closed venue tapa', null, true, 'active'),
  ('30000000-0000-0000-0000-000000000007', '20000000-0000-0000-0000-000000000005', 'Draft venue tapa', null, true, 'active'),
  ('30000000-0000-0000-0000-000000000008', '20000000-0000-0000-0000-000000000001', 'Unpublished tapa', null, false, 'active'),
  ('30000000-0000-0000-0000-000000000009', '20000000-0000-0000-0000-000000000006', 'Archived tapa', null, true, 'active'),
  ('30000000-0000-0000-0000-000000000010', '20000000-0000-0000-0000-000000000007', 'Disabled tapa', null, true, 'active');

insert into festival.reviews(id, tapa_id, user_id, rating, moderation_status) values
  ('40000000-0000-0000-0000-000000000001', '30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 5, 'visible'),
  ('40000000-0000-0000-0000-000000000002', '30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002', 3, 'visible'),
  ('40000000-0000-0000-0000-000000000003', '30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000003', 1, 'hidden'),
  ('40000000-0000-0000-0000-000000000004', '30000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000002', 4, 'visible'),
  ('40000000-0000-0000-0000-000000000005', '30000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000002', 5, 'visible');

insert into festival.field_definitions(id, festival_id, key, label_en, field_type, applies_to, active) values
  ('50000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', 'vegetarian', 'Vegetarian', 'boolean', 'tapa', true),
  ('50000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', 'note', 'Extra note', 'text', 'establishment', true),
  ('50000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001', 'inactive', 'Inactive', 'number', 'tapa', false),
  ('50000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000002', 'draft', 'Draft', 'boolean', 'tapa', true);
insert into festival.field_values(id, field_definition_id, establishment_id, tapa_id, value) values
  ('60000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001', null, '30000000-0000-0000-0000-000000000001', 'true'),
  ('60000000-0000-0000-0000-000000000002', '50000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000001', null, '{"en":"An English-only value"}'),
  ('60000000-0000-0000-0000-000000000003', '50000000-0000-0000-0000-000000000003', null, '30000000-0000-0000-0000-000000000001', '3'),
  ('60000000-0000-0000-0000-000000000004', '50000000-0000-0000-0000-000000000004', null, '30000000-0000-0000-0000-000000000004', 'false'),
  ('60000000-0000-0000-0000-000000000005', '50000000-0000-0000-0000-000000000001', null, '30000000-0000-0000-0000-000000000008', 'false');

-- Force checks now and on each subsequent test statement unless explicitly deferred.
set constraints all immediate;
