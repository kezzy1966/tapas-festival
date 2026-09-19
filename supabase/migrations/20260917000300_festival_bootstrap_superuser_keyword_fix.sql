-- Correct the PL/pgSQL variable name used by the existing one-time bootstrap
-- function. CREATE OR REPLACE preserves its existing EXECUTE permissions.
begin;

create or replace function festival.bootstrap_initial_superuser()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
  membership_role text;
begin
  perform festival_private.lock_admin_role_management();
  caller_id := (select auth.uid());
  if caller_id is null or not festival_private.is_admin() then
    raise exception 'administrator access required' using errcode = '42501';
  end if;
  if exists (select 1 from festival_private.admin_users a where a.role = 'superuser') then
    raise exception 'an initial superuser has already been selected' using errcode = '23514';
  end if;

  select a.role
  into membership_role
  from festival_private.admin_users a
  where a.user_id = caller_id
  for update;
  if membership_role is distinct from 'admin' then
    raise exception 'administrator membership not found' using errcode = '42501';
  end if;

  update festival_private.admin_users a
  set role = 'superuser'
  where a.user_id = caller_id;
  insert into festival_private.admin_role_audit(action, affected_user_id, previous_role, new_role, performed_by)
  values ('promoted', caller_id, 'admin', 'superuser', caller_id);
end
$$;

commit;
