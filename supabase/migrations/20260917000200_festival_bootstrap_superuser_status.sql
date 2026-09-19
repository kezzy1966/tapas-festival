-- Browser-safe bootstrap eligibility boundary. It exposes no account or
-- membership data and never changes state.
begin;

create function festival.can_bootstrap_initial_superuser()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when (select auth.uid()) is null then false
    else festival_private.is_admin()
      and not exists (
        select 1
        from festival_private.admin_users a
        where a.role = 'superuser'
      )
  end
$$;

revoke all on function festival.can_bootstrap_initial_superuser() from public, anon, authenticated;
grant execute on function festival.can_bootstrap_initial_superuser() to authenticated;

commit;
