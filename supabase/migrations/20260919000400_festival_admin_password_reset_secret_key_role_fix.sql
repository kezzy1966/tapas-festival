-- Support current Supabase secret keys while retaining service-role-only RPC guards.
begin;

create or replace function festival.password_reset_target_role(p_account_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  target_role text;
begin
  if coalesce(pg_catalog.current_setting('role', true), '') <> 'service_role' then
    raise exception 'privileged server access required' using errcode = '42501';
  end if;
  select a.role into target_role
  from festival_private.admin_users a
  where a.user_id = p_account_id;
  return target_role;
end
$$;

create or replace function festival.record_password_reset_request(
  p_requesting_admin_id uuid,
  p_target_user_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_role text;
begin
  if coalesce(pg_catalog.current_setting('role', true), '') <> 'service_role' then
    raise exception 'privileged server access required' using errcode = '42501';
  end if;
  select a.role into target_role
  from festival_private.admin_users a
  where a.user_id = p_target_user_id;
  insert into festival_private.admin_password_reset_audit(requesting_admin_id, target_user_id, target_role)
  values (p_requesting_admin_id, p_target_user_id, coalesce(target_role, 'user'));
end
$$;

commit;
