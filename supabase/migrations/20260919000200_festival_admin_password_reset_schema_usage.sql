-- Allow the trusted server role to resolve password-reset target roles.
begin;

grant usage on schema festival to service_role;

commit;
