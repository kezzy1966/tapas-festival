-- Phase 1A: explicit grants, RLS, protected review edits, and profile provisioning.
-- Run as the trusted migration owner (normally postgres), never as an API role.
begin;

create function festival_private.is_admin()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from festival_private.admin_users a where a.user_id = (select auth.uid())
  )
$$;

-- Invoker helpers retain RLS and explicitly test publication even for admins.
create function festival_private.is_public_establishment(establishment uuid)
returns boolean language sql stable security invoker set search_path = ''
as $$
  select exists (
    select 1 from festival.establishments e
    join festival.festivals f on f.id = e.festival_id
    where e.id = establishment and e.is_published
      and f.publication_status in ('published', 'archived')
  )
$$;

create function festival_private.is_public_tapa(tapa uuid)
returns boolean language sql stable security invoker set search_path = ''
as $$
  select exists (
    select 1 from festival.tapas t where t.id = tapa and t.is_published
      and festival_private.is_public_establishment(t.establishment_id)
  )
$$;

create function festival_private.can_review_tapa(tapa uuid)
returns boolean language sql stable security invoker set search_path = ''
as $$
  select exists (
    select 1 from festival.tapas t
    join festival.establishments e on e.id = t.establishment_id
    join festival.festivals f on f.id = e.festival_id
    where t.id = tapa and t.is_published and e.is_published
      and t.participation_status = 'active' and e.participation_status = 'active'
      and f.publication_status = 'published' and f.reviews_enabled
  )
$$;

create function festival_private.guard_review_update()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if (new.id, new.user_id, new.tapa_id, new.created_at)
    is distinct from (old.id, old.user_id, old.tapa_id, old.created_at)
    then raise exception 'review identity and creation time are immutable' using errcode = '42501'; end if;

  if new.moderation_status is distinct from old.moderation_status
    and not festival_private.is_admin()
    then raise exception 'only an administrator can moderate reviews' using errcode = '42501'; end if;

  -- Admins moderate; they cannot rewrite another person's rating or words.
  -- Owners may edit a hidden review, but this does not restore its visibility.
  if (new.rating, new.review_text) is distinct from (old.rating, old.review_text) then
    if old.user_id is distinct from (select auth.uid())
      or not festival_private.can_review_tapa(old.tapa_id)
      then raise exception 'review edits require the author and an eligible tapa' using errcode = '42501'; end if;
  end if;
  return new;
end $$;
create trigger review_update_guard before update on festival.reviews
for each row execute function festival_private.guard_review_update();

create function festival_private.create_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  -- Intentionally ignore email and untrusted provider/user metadata.
  insert into festival.profiles(user_id) values (new.id) on conflict (user_id) do nothing;
  return new;
end $$;
create trigger festival_profile_on_signup after insert on auth.users
for each row execute function festival_private.create_profile();

-- Existing Tastemap accounts acquire an independent festival profile only.
insert into festival.profiles(user_id)
select id from auth.users on conflict (user_id) do nothing;

-- Revoke first: installations may have permissive global default privileges.
revoke all on all tables in schema festival, festival_private from public, anon, authenticated;
revoke all on all functions in schema festival_private from public, anon, authenticated;
grant usage on schema festival, festival_private to anon, authenticated;
grant select on festival.festivals, festival.establishments, festival.tapas,
  festival.profiles, festival.reviews, festival.field_definitions, festival.field_values to anon, authenticated;
grant insert, update, delete on festival.festivals, festival.establishments,
  festival.tapas, festival.field_definitions, festival.field_values to authenticated;
grant update(display_name, avatar_url) on festival.profiles to authenticated;
grant insert(tapa_id, user_id, rating, review_text) on festival.reviews to authenticated;
grant update(rating, review_text, moderation_status) on festival.reviews to authenticated;
grant delete on festival.reviews to authenticated;

-- No client table privileges or policies for festival_private.admin_users.
-- Private schema USAGE permits policy helper resolution, not membership access.
grant execute on function festival_private.is_admin(),
  festival_private.is_public_establishment(uuid), festival_private.is_public_tapa(uuid)
  to anon, authenticated;
grant execute on function festival_private.can_review_tapa(uuid),
  festival_private.has_translation(text, text), festival_private.valid_opening_hours(jsonb),
  festival_private.valid_field_options(text, jsonb) to authenticated;
-- Trigger-only and graph-validation functions remain non-callable by API roles.

create policy festivals_public_read on festival.festivals for select to anon, authenticated
using (publication_status in ('published', 'archived'));
create policy festivals_admin_manage on festival.festivals for all to authenticated
using ((select festival_private.is_admin())) with check ((select festival_private.is_admin()));

create policy establishments_public_read on festival.establishments for select to anon, authenticated
using (is_published and exists (
  select 1 from festival.festivals f where f.id = festival_id and f.publication_status in ('published', 'archived')
));
create policy establishments_admin_manage on festival.establishments for all to authenticated
using ((select festival_private.is_admin())) with check ((select festival_private.is_admin()));

create policy tapas_public_read on festival.tapas for select to anon, authenticated
using (is_published and festival_private.is_public_establishment(establishment_id));
create policy tapas_admin_manage on festival.tapas for all to authenticated
using ((select festival_private.is_admin())) with check ((select festival_private.is_admin()));

-- These columns are intentionally public. No email or private metadata is stored.
create policy profiles_public_read on festival.profiles for select to anon, authenticated using (true);
create policy profiles_owner_update on festival.profiles for update to authenticated
using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy reviews_public_read on festival.reviews for select to anon, authenticated
using (moderation_status = 'visible' and festival_private.is_public_tapa(tapa_id));
create policy reviews_owner_read on festival.reviews for select to authenticated
using (user_id = (select auth.uid()));
create policy reviews_admin_read on festival.reviews for select to authenticated
using ((select festival_private.is_admin()));
create policy reviews_owner_insert on festival.reviews for insert to authenticated
with check (user_id = (select auth.uid()) and moderation_status = 'visible'
  and festival_private.can_review_tapa(tapa_id));
create policy reviews_owner_update on festival.reviews for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()) and festival_private.can_review_tapa(tapa_id));
create policy reviews_owner_delete on festival.reviews for delete to authenticated
using (user_id = (select auth.uid()));
create policy reviews_admin_moderate on festival.reviews for update to authenticated
using ((select festival_private.is_admin())) with check ((select festival_private.is_admin()));
create policy reviews_admin_delete on festival.reviews for delete to authenticated
using ((select festival_private.is_admin()));

create policy definitions_public_read on festival.field_definitions for select to anon, authenticated
using (active and exists (
  select 1 from festival.festivals f where f.id = festival_id and f.publication_status in ('published', 'archived')
));
create policy definitions_admin_manage on festival.field_definitions for all to authenticated
using ((select festival_private.is_admin())) with check ((select festival_private.is_admin()));

create policy values_public_read on festival.field_values for select to anon, authenticated
using (exists (
  select 1 from festival.field_definitions d where d.id = field_definition_id and d.active
) and (
  (establishment_id is not null and festival_private.is_public_establishment(establishment_id))
  or (tapa_id is not null and festival_private.is_public_tapa(tapa_id))
));
create policy values_admin_manage on festival.field_values for all to authenticated
using ((select festival_private.is_admin())) with check ((select festival_private.is_admin()));

-- API schema exposure, admin appointment, and Storage remain separate approvals.
commit;
