-- Additive operational controls. Festival switches are per festival; the
-- emergency switch is deliberately site-wide. Existing festival behaviour is
-- copied into the new controls so a missing setting never disables a feature.
begin;

create table festival.festival_controls (
  festival_id uuid primary key references festival.festivals(id) on delete restrict,
  festival_active boolean not null default true,
  ratings_enabled boolean not null default true,
  reviews_enabled boolean not null default true,
  rankings_enabled boolean not null default true,
  total_rating_counts_enabled boolean not null default true,
  want_to_try_enabled boolean not null default true,
  public_read_only boolean not null default false,
  updated_at timestamptz not null default pg_catalog.clock_timestamp()
);

create table festival.site_controls (
  singleton boolean primary key default true check (singleton),
  emergency_shutdown boolean not null default false,
  updated_at timestamptz not null default pg_catalog.clock_timestamp()
);

create table festival_private.control_audit (
  id bigint generated always as identity primary key,
  festival_id uuid references festival.festivals(id) on delete restrict,
  control text not null check (control in ('festival_active', 'ratings_enabled', 'reviews_enabled', 'rankings_enabled', 'total_rating_counts_enabled', 'want_to_try_enabled', 'public_read_only', 'emergency_shutdown')),
  previous_value boolean not null,
  new_value boolean not null,
  performed_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default pg_catalog.clock_timestamp()
);
create index control_audit_created_at_idx on festival_private.control_audit(created_at desc);
create index control_audit_festival_created_at_idx on festival_private.control_audit(festival_id, created_at desc);

-- Migrate present behaviour, including the three legacy festival flags.
insert into festival.festival_controls (festival_id, reviews_enabled, rankings_enabled, total_rating_counts_enabled)
select id, reviews_enabled, show_rankings, show_total_rating_count
from festival.festivals
on conflict (festival_id) do nothing;
insert into festival.site_controls(singleton) values (true) on conflict (singleton) do nothing;

-- Every festival, including those created after this migration, gets an explicit
-- row. Legacy flags are copied only where they already define public behaviour.
create function festival_private.create_festival_controls()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into festival.festival_controls (
    festival_id, reviews_enabled, rankings_enabled, total_rating_counts_enabled
  ) values (
    new.id, new.reviews_enabled, new.show_rankings, new.show_total_rating_count
  ) on conflict (festival_id) do nothing;
  return new;
end $$;
create trigger festival_controls_on_festival_insert
after insert on festival.festivals
for each row execute function festival_private.create_festival_controls();

alter table festival.festival_controls enable row level security;
alter table festival.site_controls enable row level security;
alter table festival_private.control_audit enable row level security;
revoke all on festival.festival_controls, festival.site_controls, festival_private.control_audit from public, anon, authenticated;
grant select on festival.festival_controls, festival.site_controls to anon, authenticated;
create policy festival_controls_public_read on festival.festival_controls for select to anon, authenticated using (true);
create policy site_controls_public_read on festival.site_controls for select to anon, authenticated using (true);

create or replace function festival_private.controls_allow_mutation(p_festival_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((select c.festival_active and not c.public_read_only from festival.festival_controls c where c.festival_id = p_festival_id), true)
$$;

create or replace function festival_private.controls_for_tapa(p_tapa_id uuid)
returns festival.festival_controls language sql stable security definer set search_path = '' as $$
  select c.* from festival.festival_controls c
  join festival.establishments e on e.festival_id = c.festival_id
  join festival.tapas t on t.establishment_id = e.id
  where t.id = p_tapa_id
$$;

create or replace function festival_private.controls_for_establishment(p_establishment_id uuid)
returns festival.festival_controls language sql stable security definer set search_path = '' as $$
  select c.* from festival.festival_controls c
  join festival.establishments e on e.festival_id = c.festival_id
  where e.id = p_establishment_id
$$;

-- The old eligibility helpers remain the RLS gate; detailed feature checks are
-- performed in triggers so rating and review fields can be controlled separately.
create or replace function festival_private.can_review_tapa(tapa uuid)
returns boolean language sql stable security invoker set search_path = '' as $$
  select exists (
    select 1 from festival.tapas t
    join festival.establishments e on e.id = t.establishment_id
    join festival.festivals f on f.id = e.festival_id
    where t.id = tapa and t.is_published and e.is_published
      and t.participation_status = 'active' and e.participation_status = 'active'
      and f.publication_status = 'published'
      and festival_private.controls_allow_mutation(f.id)
  )
$$;
create or replace function festival_private.can_review_establishment(establishment uuid)
returns boolean language sql stable security invoker set search_path = '' as $$
  select exists (
    select 1 from festival.establishments e
    join festival.festivals f on f.id = e.festival_id
    where e.id = establishment and e.is_published and e.participation_status = 'active'
      and f.publication_status = 'published'
      and festival_private.controls_allow_mutation(f.id)
  )
$$;

create or replace function festival_private.guard_public_review_controls()
returns trigger language plpgsql security definer set search_path = '' as $$
declare c festival.festival_controls; tapa uuid := coalesce(new.tapa_id, old.tapa_id);
begin
  if festival_private.is_admin() then if tg_op = 'DELETE' then return old; else return new; end if; end if;
  select * into c from festival_private.controls_for_tapa(tapa);
  -- No row means a pre-migration/missing configuration: retain legacy behaviour.
  if c is null then if tg_op = 'DELETE' then return old; else return new; end if; end if;
  if c.public_read_only then
    raise exception 'public festival changes are temporarily unavailable' using errcode = '42501';
  end if;
  if tg_op = 'INSERT' then
    if not c.festival_active then raise exception 'public festival changes are temporarily unavailable' using errcode = '42501'; end if;
    if new.rating is not null and not c.ratings_enabled then raise exception 'ratings are temporarily disabled' using errcode = '42501'; end if;
    if nullif(pg_catalog.btrim(new.review_text), '') is not null and not c.reviews_enabled then raise exception 'reviews are temporarily disabled' using errcode = '42501'; end if;
  elsif tg_op = 'UPDATE' then
    if not c.festival_active and (
      (new.rating is distinct from old.rating and new.rating is not null)
      or (new.review_text is distinct from old.review_text and nullif(pg_catalog.btrim(new.review_text), '') is not null)
    ) then raise exception 'public festival changes are temporarily unavailable' using errcode = '42501'; end if;
    if new.rating is distinct from old.rating and new.rating is not null and not c.ratings_enabled then raise exception 'ratings are temporarily disabled' using errcode = '42501'; end if;
    if new.review_text is distinct from old.review_text and nullif(pg_catalog.btrim(new.review_text), '') is not null and not c.reviews_enabled then raise exception 'reviews are temporarily disabled' using errcode = '42501'; end if;
  end if;
  if tg_op = 'DELETE' then return old; else return new; end if;
end $$;

create or replace function festival_private.guard_public_establishment_rating_controls()
returns trigger language plpgsql security definer set search_path = '' as $$
declare c festival.festival_controls; establishment uuid := coalesce(new.establishment_id, old.establishment_id);
begin
  if festival_private.is_admin() then if tg_op = 'DELETE' then return old; else return new; end if; end if;
  select * into c from festival_private.controls_for_establishment(establishment);
  if c is null then if tg_op = 'DELETE' then return old; else return new; end if; end if;
  if c.public_read_only then raise exception 'public festival changes are temporarily unavailable' using errcode = '42501'; end if;
  if tg_op = 'INSERT' and (not c.festival_active or not c.ratings_enabled) then raise exception 'ratings are temporarily disabled' using errcode = '42501'; end if;
  if tg_op = 'UPDATE' then
    if not c.festival_active and new.rating is not null then raise exception 'public festival changes are temporarily unavailable' using errcode = '42501'; end if;
    if new.rating is distinct from old.rating and new.rating is not null and not c.ratings_enabled then raise exception 'ratings are temporarily disabled' using errcode = '42501'; end if;
  end if;
  if tg_op = 'DELETE' then return old; else return new; end if;
end $$;

create trigger reviews_public_controls_guard before insert or update or delete on festival.reviews
for each row execute function festival_private.guard_public_review_controls();
create trigger establishment_reviews_public_controls_guard before insert or update or delete on festival.establishment_reviews
for each row execute function festival_private.guard_public_establishment_rating_controls();

-- Existing update guards and RLS policies used can_review_* as a blanket gate.
-- Replace that blanket gate so an owner can remove existing content while a
-- festival is inactive; the control trigger above still blocks every new or
-- changed participation value, and RLS retains ownership/public-content checks.
create or replace function festival_private.guard_review_update()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if (new.id, new.user_id, new.tapa_id, new.created_at)
    is distinct from (old.id, old.user_id, old.tapa_id, old.created_at)
    then raise exception 'review identity and creation time are immutable' using errcode = '42501'; end if;
  if new.moderation_status is distinct from old.moderation_status and not festival_private.is_admin()
    then raise exception 'only an administrator can moderate reviews' using errcode = '42501'; end if;
  if (new.rating, new.review_text) is distinct from (old.rating, old.review_text)
    and old.user_id is distinct from (select auth.uid())
    then raise exception 'review edits require the author' using errcode = '42501'; end if;
  return new;
end $$;
create or replace function festival_private.guard_establishment_review_update()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if (new.id, new.user_id, new.establishment_id, new.created_at)
    is distinct from (old.id, old.user_id, old.establishment_id, old.created_at)
    then raise exception 'establishment review identity and creation time are immutable' using errcode = '42501'; end if;
  if new.rating is distinct from old.rating and old.user_id is distinct from (select auth.uid())
    then raise exception 'establishment rating edits require the author' using errcode = '42501'; end if;
  return new;
end $$;
drop policy reviews_owner_update on festival.reviews;
create policy reviews_owner_update on festival.reviews for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()) and festival_private.is_public_tapa(tapa_id));
drop policy establishment_reviews_owner_update on festival.establishment_reviews;
create policy establishment_reviews_owner_update on festival.establishment_reviews for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()) and festival_private.is_public_establishment(establishment_id));

create function festival.get_admin_controls(p_festival_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if not festival.is_current_admin() then raise exception 'administrator access required' using errcode = '42501'; end if;
  if not exists (select 1 from festival.festivals f where f.id = p_festival_id) then raise exception 'festival not found' using errcode = '22023'; end if;
  return jsonb_build_object(
    'festival', (select to_jsonb(f) from festival.festivals f where f.id = p_festival_id),
    'controls', coalesce((select to_jsonb(c) from festival.festival_controls c where c.festival_id = p_festival_id), '{}'::jsonb),
    'site', (select jsonb_build_object('emergency_shutdown', s.emergency_shutdown, 'updated_at', s.updated_at) from festival.site_controls s where s.singleton)
  );
end $$;

create function festival.set_festival_control(p_festival_id uuid, p_control text, p_value boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare old_value boolean; caller uuid := (select auth.uid());
begin
  if caller is null or not festival.is_current_admin() then raise exception 'administrator access required' using errcode = '42501'; end if;
  if p_control not in ('festival_active', 'ratings_enabled', 'reviews_enabled', 'rankings_enabled', 'total_rating_counts_enabled', 'want_to_try_enabled', 'public_read_only') then raise exception 'invalid festival control' using errcode = '22023'; end if;
  insert into festival.festival_controls(festival_id) values (p_festival_id) on conflict (festival_id) do nothing;
  execute format('select %I from festival.festival_controls where festival_id = $1', p_control) into old_value using p_festival_id;
  if old_value is distinct from p_value then
    execute format('update festival.festival_controls set %I = $1, updated_at = pg_catalog.clock_timestamp() where festival_id = $2', p_control) using p_value, p_festival_id;
    insert into festival_private.control_audit(festival_id, control, previous_value, new_value, performed_by) values (p_festival_id, p_control, old_value, p_value, caller);
  end if;
end $$;

create function festival.set_emergency_shutdown(p_value boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare old_value boolean; caller uuid := festival_private.require_superuser();
begin
  select emergency_shutdown into old_value from festival.site_controls where singleton;
  if old_value is distinct from p_value then
    update festival.site_controls set emergency_shutdown = p_value, updated_at = pg_catalog.clock_timestamp() where singleton;
    insert into festival_private.control_audit(festival_id, control, previous_value, new_value, performed_by) values (null, 'emergency_shutdown', old_value, p_value, caller);
  end if;
end $$;

create function festival.list_control_audit(p_festival_id uuid default null, p_limit integer default 30)
returns table(created_at timestamptz, administrator text, control text, previous_value boolean, new_value boolean, festival_id uuid)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not festival.is_current_admin() then raise exception 'administrator access required' using errcode = '42501'; end if;
  return query select a.created_at, coalesce(u.email, 'Administrator'), a.control, a.previous_value, a.new_value, a.festival_id
  from festival_private.control_audit a join auth.users u on u.id = a.performed_by
  where (p_festival_id is null and a.festival_id is null) or a.festival_id = p_festival_id
  order by a.created_at desc limit greatest(1, least(coalesce(p_limit, 30), 100));
end $$;

revoke all on function festival.get_admin_controls(uuid), festival.set_festival_control(uuid, text, boolean), festival.set_emergency_shutdown(boolean), festival.list_control_audit(uuid, integer) from public, anon, authenticated;
grant execute on function festival.get_admin_controls(uuid), festival.set_festival_control(uuid, text, boolean), festival.set_emergency_shutdown(boolean), festival.list_control_audit(uuid, integer) to authenticated;
-- This helper only returns the same active/read-only eligibility reflected in
-- public control rows. Authenticated RLS policies require it during writes.
revoke all on function festival_private.controls_allow_mutation(uuid), festival_private.controls_for_tapa(uuid), festival_private.controls_for_establishment(uuid), festival_private.create_festival_controls(), festival_private.guard_public_review_controls(), festival_private.guard_public_establishment_rating_controls() from public, anon, authenticated;
grant execute on function festival_private.controls_allow_mutation(uuid) to authenticated;

commit;
