-- Private audit support for server-mediated administrator password-reset emails.
begin;

create table festival_private.admin_password_reset_audit (
  id bigint generated always as identity primary key,
  requesting_admin_id uuid not null,
  target_user_id uuid not null,
  target_role text not null check (target_role in ('user', 'admin', 'superuser')),
  created_at timestamptz not null default pg_catalog.clock_timestamp()
);

create index admin_password_reset_audit_target_created_at_idx
  on festival_private.admin_password_reset_audit(target_user_id, created_at desc);

alter table festival_private.admin_password_reset_audit enable row level security;
revoke all on table festival_private.admin_password_reset_audit from public, anon, authenticated;

create function festival.password_reset_target_role(p_account_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  target_role text;
begin
  if pg_catalog.coalesce(pg_catalog.current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception 'privileged server access required' using errcode = '42501';
  end if;
  select a.role into target_role
  from festival_private.admin_users a
  where a.user_id = p_account_id;
  return target_role;
end
$$;

create function festival.record_password_reset_request(
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
  if pg_catalog.coalesce(pg_catalog.current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception 'privileged server access required' using errcode = '42501';
  end if;
  select a.role into target_role
  from festival_private.admin_users a
  where a.user_id = p_target_user_id;
  insert into festival_private.admin_password_reset_audit(requesting_admin_id, target_user_id, target_role)
  values (p_requesting_admin_id, p_target_user_id, pg_catalog.coalesce(target_role, 'user'));
end
$$;

revoke all on function festival.password_reset_target_role(uuid), festival.record_password_reset_request(uuid, uuid) from public, anon, authenticated;
grant execute on function festival.password_reset_target_role(uuid), festival.record_password_reset_request(uuid, uuid) to service_role;

commit;
