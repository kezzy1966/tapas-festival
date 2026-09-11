-- Public-schema boundary for the browser admin gate. It exposes only the
-- current caller's boolean membership result; festival_private remains private.
begin;

create function festival.is_current_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when (select auth.uid()) is null then false
    else festival_private.is_admin()
  end
$$;

revoke all on function festival.is_current_admin() from public, anon, authenticated;
grant execute on function festival.is_current_admin() to anon, authenticated;

commit;
