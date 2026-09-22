-- Private user suspension state, protected moderation RPCs, and contribution enforcement.
begin;

create table if not exists festival_private.user_suspensions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  suspended_at timestamptz not null default clock_timestamp(),
  suspended_by uuid not null references auth.users(id) on delete restrict,
  reason text,
  updated_at timestamptz not null default clock_timestamp(),
  constraint user_suspensions_reason_length check (reason is null or char_length(btrim(reason)) between 1 and 240)
);

create table if not exists festival_private.user_suspension_audit (
  id bigint generated always as identity primary key,
  target_user_id uuid not null references auth.users(id) on delete cascade,
  action text not null check (action in ('suspended', 'reactivated')),
  performed_by uuid not null references auth.users(id) on delete restrict,
  reason text,
  created_at timestamptz not null default clock_timestamp(),
  constraint user_suspension_audit_reason_length check (reason is null or char_length(btrim(reason)) between 1 and 240)
);

alter table festival_private.user_suspensions enable row level security;
alter table festival_private.user_suspension_audit enable row level security;
revoke all on table festival_private.user_suspensions, festival_private.user_suspension_audit from public, anon, authenticated;

create or replace function festival_private.is_user_suspended(p_user_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select p_user_id is not null
    and exists (select 1 from festival_private.user_suspensions s where s.user_id = p_user_id)
    and not exists (select 1 from festival_private.admin_users a where a.user_id = p_user_id);
$$;

create or replace function festival.is_current_user_suspended()
returns boolean
language sql stable security definer set search_path = ''
as $$ select festival_private.is_user_suspended((select auth.uid())); $$;

create or replace function festival.suspend_user(p_account_id uuid, p_reason text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
declare actor uuid := (select auth.uid()); normalized_reason text := nullif(pg_catalog.btrim(coalesce(p_reason, '')), '');
begin
  if actor is null or not festival.is_current_admin() then raise exception 'administrator access required' using errcode = '42501'; end if;
  if p_account_id is null or not exists (select 1 from auth.users where id = p_account_id) then raise exception 'user account not found' using errcode = '22023'; end if;
  if normalized_reason is not null and char_length(normalized_reason) > 240 then raise exception 'suspension reason is too long' using errcode = '22023'; end if;
  if exists (select 1 from festival_private.admin_users where user_id = p_account_id) then raise exception 'administrator accounts cannot be suspended' using errcode = '42501'; end if;
  insert into festival_private.user_suspensions(user_id, suspended_at, suspended_by, reason, updated_at)
  values (p_account_id, clock_timestamp(), actor, normalized_reason, clock_timestamp())
  on conflict (user_id) do update set suspended_at = excluded.suspended_at, suspended_by = excluded.suspended_by, reason = excluded.reason, updated_at = excluded.updated_at;
  insert into festival_private.user_suspension_audit(target_user_id, action, performed_by, reason)
  values (p_account_id, 'suspended', actor, normalized_reason);
end;
$$;

create or replace function festival.reactivate_user(p_account_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare actor uuid := (select auth.uid());
begin
  if actor is null or not festival.is_current_admin() then raise exception 'administrator access required' using errcode = '42501'; end if;
  if p_account_id is null or not exists (select 1 from auth.users where id = p_account_id) then raise exception 'user account not found' using errcode = '22023'; end if;
  delete from festival_private.user_suspensions where user_id = p_account_id;
  if not found then raise exception 'user is not suspended' using errcode = '22023'; end if;
  insert into festival_private.user_suspension_audit(target_user_id, action, performed_by)
  values (p_account_id, 'reactivated', actor);
end;
$$;

create or replace function festival_private.can_review_tapa(tapa uuid)
returns boolean language sql stable security invoker
as $$
  select exists (
    select 1 from festival.tapas t
    join festival.establishments e on e.id = t.establishment_id
    join festival.festivals f on f.id = e.festival_id
    where t.id = tapa and t.is_published and t.participation_status = 'active'
      and e.is_published and e.participation_status = 'active'
      and f.publication_status = 'published'
      and festival_private.controls_allow_mutation(f.id)
      and (festival_private.is_admin() or not festival_private.is_user_suspended((select auth.uid())))
  );
$$;

create or replace function festival_private.can_review_establishment(establishment uuid)
returns boolean language sql stable security invoker
as $$
  select exists (
    select 1 from festival.establishments e
    join festival.festivals f on f.id = e.festival_id
    where e.id = establishment and e.is_published and e.participation_status = 'active'
      and f.publication_status = 'published'
      and festival_private.controls_allow_mutation(f.id)
      and (festival_private.is_admin() or not festival_private.is_user_suspended((select auth.uid())))
  );
$$;

create or replace function festival_private.guard_public_review_controls()
returns trigger language plpgsql security definer set search_path = '' as $$
declare c festival.festival_controls; tapa uuid := coalesce(new.tapa_id, old.tapa_id); eligible boolean; suspended boolean := festival_private.is_user_suspended((select auth.uid()));
begin
  if festival_private.is_admin() then if tg_op = 'DELETE' then return old; else return new; end if; end if;
  select * into c from festival_private.controls_for_tapa(tapa);
  if c is null then
    if suspended and tg_op <> 'DELETE' and (tg_op = 'INSERT' or new.rating is distinct from old.rating and new.rating is not null or new.review_text is distinct from old.review_text and nullif(pg_catalog.btrim(new.review_text), '') is not null) then raise exception 'suspended users cannot contribute' using errcode = '42501'; end if;
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;
  if c.public_read_only then raise exception 'public festival changes are temporarily unavailable' using errcode = '42501'; end if;
  if suspended and tg_op = 'INSERT' then raise exception 'suspended users cannot contribute' using errcode = '42501'; end if;
  select exists (select 1 from festival.tapas t join festival.establishments e on e.id = t.establishment_id where t.id = tapa and t.participation_status = 'active' and e.participation_status = 'active') into eligible;
  if tg_op = 'INSERT' and not eligible then raise exception 'withdrawn establishments cannot receive public contributions' using errcode = '42501'; end if;
  if tg_op = 'INSERT' then
    if not c.festival_active then raise exception 'public festival changes are temporarily unavailable' using errcode = '42501'; end if;
    if new.rating is not null and not c.ratings_enabled then raise exception 'ratings are temporarily disabled' using errcode = '42501'; end if;
    if nullif(pg_catalog.btrim(new.review_text), '') is not null and not c.reviews_enabled then raise exception 'reviews are temporarily disabled' using errcode = '42501'; end if;
  elsif tg_op = 'UPDATE' then
    if suspended and ((new.rating is distinct from old.rating and new.rating is not null) or (new.review_text is distinct from old.review_text and nullif(pg_catalog.btrim(new.review_text), '') is not null)) then raise exception 'suspended users cannot contribute' using errcode = '42501'; end if;
    if not eligible and ((new.rating is distinct from old.rating and new.rating is not null) or (new.review_text is distinct from old.review_text and nullif(pg_catalog.btrim(new.review_text), '') is not null)) then raise exception 'withdrawn establishments cannot receive public contributions' using errcode = '42501'; end if;
    if not c.festival_active and ((new.rating is distinct from old.rating and new.rating is not null) or (new.review_text is distinct from old.review_text and nullif(pg_catalog.btrim(new.review_text), '') is not null)) then raise exception 'public festival changes are temporarily unavailable' using errcode = '42501'; end if;
    if new.rating is distinct from old.rating and new.rating is not null and not c.ratings_enabled then raise exception 'ratings are temporarily disabled' using errcode = '42501'; end if;
    if new.review_text is distinct from old.review_text and nullif(pg_catalog.btrim(new.review_text), '') is not null and not c.reviews_enabled then raise exception 'reviews are temporarily disabled' using errcode = '42501'; end if;
  end if;
  if tg_op = 'DELETE' then return old; else return new; end if;
end $$;

create or replace function festival_private.guard_public_establishment_rating_controls()
returns trigger language plpgsql security definer set search_path = '' as $$
declare c festival.festival_controls; establishment uuid := coalesce(new.establishment_id, old.establishment_id); eligible boolean; suspended boolean := festival_private.is_user_suspended((select auth.uid()));
begin
  if festival_private.is_admin() then if tg_op = 'DELETE' then return old; else return new; end if; end if;
  select * into c from festival_private.controls_for_establishment(establishment);
  if c is null then
    if suspended and tg_op <> 'DELETE' and (tg_op = 'INSERT' or new.rating is distinct from old.rating and new.rating is not null) then raise exception 'suspended users cannot contribute' using errcode = '42501'; end if;
    if tg_op = 'DELETE' then return old; else return new; end if;
  end if;
  if c.public_read_only then raise exception 'public festival changes are temporarily unavailable' using errcode = '42501'; end if;
  if suspended and tg_op = 'INSERT' then raise exception 'suspended users cannot contribute' using errcode = '42501'; end if;
  select exists (select 1 from festival.establishments e where e.id = establishment and e.participation_status = 'active') into eligible;
  if tg_op = 'INSERT' and not eligible then raise exception 'withdrawn establishments cannot receive public contributions' using errcode = '42501'; end if;
  if tg_op = 'INSERT' and (not c.festival_active or not c.ratings_enabled) then raise exception 'ratings are temporarily disabled' using errcode = '42501'; end if;
  if tg_op = 'UPDATE' then
    if suspended and new.rating is distinct from old.rating and new.rating is not null then raise exception 'suspended users cannot contribute' using errcode = '42501'; end if;
    if not eligible and new.rating is distinct from old.rating and new.rating is not null then raise exception 'withdrawn establishments cannot receive public contributions' using errcode = '42501'; end if;
    if not c.festival_active and new.rating is not null then raise exception 'public festival changes are temporarily unavailable' using errcode = '42501'; end if;
    if new.rating is distinct from old.rating and new.rating is not null and not c.ratings_enabled then raise exception 'ratings are temporarily disabled' using errcode = '42501'; end if;
  end if;
  if tg_op = 'DELETE' then return old; else return new; end if;
end $$;

create or replace function festival.search_registered_users_with_suspension(
  p_query text default null, p_limit integer default 50, p_offset integer default 0
)
returns table (
  account_id uuid, account text, role text, registered_at timestamptz, last_festival_activity_at timestamptz,
  tapa_rating_count bigint, written_review_count bigint, bar_rating_count bigint, total_activity_count bigint,
  status text, suspended_at timestamptz, suspension_reason text, total_count bigint
)
language sql stable security definer set search_path = ''
as $$
  select r.account_id, r.account, coalesce(a.role, 'user')::text, r.registered_at, r.last_festival_activity_at,
    r.tapa_rating_count, r.written_review_count, r.bar_rating_count, r.total_activity_count,
    case when s.user_id is not null then 'Suspended' else r.status end::text,
    s.suspended_at, s.reason, r.total_count
  from festival.search_registered_users(p_query, p_limit, p_offset) r
  join auth.users u on u.id = r.account_id
  left join festival_private.admin_users a on a.user_id = r.account_id
  left join festival_private.user_suspensions s on s.user_id = r.account_id
  where (select auth.uid()) is not null and festival.is_current_admin();
$$;

revoke all on function festival_private.is_user_suspended(uuid), festival.is_current_user_suspended(), festival.suspend_user(uuid, text), festival.reactivate_user(uuid), festival.search_registered_users_with_suspension(text, integer, integer) from public, anon, authenticated;
grant execute on function festival_private.is_user_suspended(uuid) to authenticated;
grant execute on function festival.is_current_user_suspended() to authenticated;
grant execute on function festival.suspend_user(uuid, text), festival.reactivate_user(uuid), festival.search_registered_users_with_suspension(text, integer, integer) to authenticated;
grant execute on function festival_private.can_review_tapa(uuid), festival_private.can_review_establishment(uuid) to authenticated;

commit;
