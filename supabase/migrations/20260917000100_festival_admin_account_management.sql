-- Additive administrator role management. This migration intentionally keeps
-- festival_private.admin_users private; browser access is limited to the RPCs
-- in the festival schema below.
begin;

alter table festival_private.admin_users
  add column role text not null default 'admin',
  add constraint admin_users_role_check check (role in ('admin', 'superuser'));

-- Preserve every existing administrator as an Admin. A specifically chosen
-- authenticated existing Admin must invoke festival.bootstrap_initial_superuser()
-- after this migration; no account is selected by creation date or otherwise.


create table festival_private.admin_role_audit (
  id bigint generated always as identity primary key,
  action text not null check (action in ('added', 'promoted', 'demoted', 'removed')),
  affected_user_id uuid not null,
  previous_role text check (previous_role in ('admin', 'superuser')),
  new_role text check (new_role in ('admin', 'superuser')),
  performed_by uuid not null,
  created_at timestamptz not null default pg_catalog.clock_timestamp(),
  constraint admin_role_audit_role_change_check check (
    (action = 'added' and previous_role is null and new_role in ('admin', 'superuser')) or
    (action = 'promoted' and previous_role = 'admin' and new_role = 'superuser') or
    (action = 'demoted' and previous_role = 'superuser' and new_role = 'admin') or
    (action = 'removed' and previous_role in ('admin', 'superuser') and new_role is null)
  )
);
create index admin_role_audit_affected_user_created_at_idx
  on festival_private.admin_role_audit(affected_user_id, created_at desc);

alter table festival_private.admin_role_audit enable row level security;
revoke all on table festival_private.admin_role_audit from public, anon, authenticated;

create function festival_private.is_superuser()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from festival_private.admin_users a
    where a.user_id = (select auth.uid())
      and a.role = 'superuser'
  )
$$;

-- This lock serializes role removals and demotions. It must be acquired before
-- authorisation and final-Superuser checks, because either may change in a
-- concurrent administrator-management transaction.
create function festival_private.lock_admin_role_management()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_catalog.pg_advisory_xact_lock(74621, 2);
end
$$;

create function festival_private.require_superuser()
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid := (select auth.uid());
begin
  if caller_id is null or not festival_private.is_superuser() then
    raise exception 'superuser access required' using errcode = '42501';
  end if;
  return caller_id;
end
$$;

create function festival.is_current_superuser()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when (select auth.uid()) is null then false
    else festival_private.is_superuser()
  end
$$;

-- One-time bootstrap: an existing Admin can promote only their own authenticated
-- membership, and only while no Superuser exists. This never reads or returns
-- auth.users data to the browser.
create function festival.bootstrap_initial_superuser()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  current_role text;
begin
  perform festival_private.lock_admin_role_management();
  caller_id := (select auth.uid());
  if caller_id is null or not festival_private.is_admin() then
    raise exception 'administrator access required' using errcode = '42501';
  end if;
  if exists (select 1 from festival_private.admin_users a where a.role = 'superuser') then
    raise exception 'an initial superuser has already been selected' using errcode = '23514';
  end if;

  select a.role into current_role
  from festival_private.admin_users a
  where a.user_id = caller_id
  for update;
  if current_role <> 'admin' then
    raise exception 'administrator membership not found' using errcode = 'P0002';
  end if;

  update festival_private.admin_users a
  set role = 'superuser'
  where a.user_id = caller_id;
  insert into festival_private.admin_role_audit(action, affected_user_id, previous_role, new_role, performed_by)
  values ('promoted', caller_id, 'admin', 'superuser', caller_id);
end
$$;

-- Only returns data needed for the management screen. account_id is an opaque
-- action handle; no auth.users table is exposed to PostgREST.
create function festival.list_administrators()
returns table (
  account_id uuid,
  account text,
  role text,
  added_at timestamptz,
  status text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform festival_private.require_superuser();

  return query
  select
    a.user_id,
    case
      when u.email is null or pg_catalog.strpos(u.email, '@') = 0 then 'Account'
      else pg_catalog.left(pg_catalog.split_part(u.email, '@', 1), 2) || '***@' || pg_catalog.split_part(u.email, '@', 2)
    end,
    a.role,
    a.created_at,
    'Active'::text
  from festival_private.admin_users a
  join auth.users u on u.id = a.user_id
  order by (a.role = 'superuser') desc, a.created_at, a.user_id;
end
$$;

create function festival.add_administrator(p_email text, p_role text default 'admin')
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  target_id uuid;
  normalized_email text := pg_catalog.lower(pg_catalog.btrim(p_email));
begin
  perform festival_private.lock_admin_role_management();
  caller_id := festival_private.require_superuser();

  if p_role not in ('admin', 'superuser') then
    raise exception 'role must be admin or superuser' using errcode = '22023';
  end if;
  if normalized_email is null or normalized_email = '' then
    raise exception 'enter a registered user email address' using errcode = '22023';
  end if;

  select u.id into target_id
  from auth.users u
  where pg_catalog.lower(u.email) = normalized_email;

  if target_id is null then
    raise exception 'This user must create an account before they can be made an administrator.' using errcode = 'P0001';
  end if;
  if exists (select 1 from festival_private.admin_users a where a.user_id = target_id) then
    raise exception 'this user is already an administrator' using errcode = '23505';
  end if;

  insert into festival_private.admin_users(user_id, role)
  values (target_id, p_role);
  insert into festival_private.admin_role_audit(action, affected_user_id, previous_role, new_role, performed_by)
  values ('added', target_id, null, p_role, caller_id);
end
$$;

create function festival.set_administrator_role(p_account_id uuid, p_new_role text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  previous_role text;
  superuser_count bigint;
begin
  perform festival_private.lock_admin_role_management();
  caller_id := festival_private.require_superuser();

  if p_new_role not in ('admin', 'superuser') then
    raise exception 'role must be admin or superuser' using errcode = '22023';
  end if;

  select a.role into previous_role
  from festival_private.admin_users a
  where a.user_id = p_account_id
  for update;
  if previous_role is null then
    raise exception 'administrator membership not found' using errcode = 'P0002';
  end if;
  if previous_role = p_new_role then
    raise exception 'administrator already has that role' using errcode = '22023';
  end if;
  if previous_role = 'admin' and p_new_role <> 'superuser' then
    raise exception 'admins can only be promoted to superuser' using errcode = '22023';
  end if;
  if previous_role = 'superuser' and p_new_role <> 'admin' then
    raise exception 'superusers can only be demoted to admin' using errcode = '22023';
  end if;

  if previous_role = 'superuser' then
    select count(*) into superuser_count
    from festival_private.admin_users a
    where a.role = 'superuser';
    if superuser_count <= 1 then
      raise exception 'cannot demote the final superuser' using errcode = '23514';
    end if;
  end if;

  update festival_private.admin_users a
  set role = p_new_role
  where a.user_id = p_account_id;
  insert into festival_private.admin_role_audit(action, affected_user_id, previous_role, new_role, performed_by)
  values (
    case when p_new_role = 'superuser' then 'promoted' else 'demoted' end,
    p_account_id, previous_role, p_new_role, caller_id
  );
end
$$;

create function festival.remove_administrator(p_account_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  previous_role text;
  superuser_count bigint;
begin
  perform festival_private.lock_admin_role_management();
  caller_id := festival_private.require_superuser();

  select a.role into previous_role
  from festival_private.admin_users a
  where a.user_id = p_account_id
  for update;
  if previous_role is null then
    raise exception 'administrator membership not found' using errcode = 'P0002';
  end if;
  if previous_role = 'superuser' then
    select count(*) into superuser_count
    from festival_private.admin_users a
    where a.role = 'superuser';
    if superuser_count <= 1 then
      raise exception 'cannot remove the final superuser' using errcode = '23514';
    end if;
  end if;

  delete from festival_private.admin_users a where a.user_id = p_account_id;
  insert into festival_private.admin_role_audit(action, affected_user_id, previous_role, new_role, performed_by)
  values ('removed', p_account_id, previous_role, null, caller_id);
end
$$;

revoke all on function festival_private.is_superuser(), festival_private.lock_admin_role_management(), festival_private.require_superuser() from public, anon, authenticated;
revoke all on function festival.is_current_superuser(), festival.bootstrap_initial_superuser(), festival.list_administrators(), festival.add_administrator(text, text), festival.set_administrator_role(uuid, text), festival.remove_administrator(uuid) from public, anon, authenticated;
grant execute on function festival.is_current_superuser(), festival.bootstrap_initial_superuser(), festival.list_administrators(), festival.add_administrator(text, text), festival.set_administrator_role(uuid, text), festival.remove_administrator(uuid) to authenticated;

commit;
