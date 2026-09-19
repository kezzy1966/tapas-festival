-- Allow Superadmins to add an already-selected registered account to the
-- administrator membership without exposing its email to the browser.
begin;

create function festival.list_promotable_registered_users(p_account_ids uuid[])
returns table (account_id uuid)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  perform festival_private.require_superuser();

  return query
  select distinct requested.account_id
  from unnest(coalesce(p_account_ids, '{}'::uuid[])) as requested(account_id)
  join auth.users u on u.id = requested.account_id
  where not exists (
    select 1
    from festival_private.admin_users a
    where a.user_id = requested.account_id
  );
end
$$;

create function festival.add_administrator_by_account_id(
  p_account_id uuid,
  p_role text default 'admin'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller_id uuid;
begin
  perform festival_private.lock_admin_role_management();
  caller_id := festival_private.require_superuser();

  if p_role not in ('admin', 'superuser') then
    raise exception 'role must be admin or superuser' using errcode = '22023';
  end if;
  if p_account_id is null or not exists (
    select 1
    from auth.users u
    where u.id = p_account_id
  ) then
    raise exception 'registered user not found' using errcode = 'P0002';
  end if;
  if exists (
    select 1
    from festival_private.admin_users a
    where a.user_id = p_account_id
  ) then
    raise exception 'this user is already an administrator' using errcode = '23505';
  end if;

  insert into festival_private.admin_users(user_id, role)
  values (p_account_id, p_role);
  insert into festival_private.admin_role_audit(action, affected_user_id, previous_role, new_role, performed_by)
  values ('added', p_account_id, null, p_role, caller_id);
end
$$;

revoke all on function festival.list_promotable_registered_users(uuid[]) from public, anon, authenticated;
revoke all on function festival.add_administrator_by_account_id(uuid, text) from public, anon, authenticated;
grant execute on function festival.list_promotable_registered_users(uuid[]) to authenticated;
grant execute on function festival.add_administrator_by_account_id(uuid, text) to authenticated;

commit;
