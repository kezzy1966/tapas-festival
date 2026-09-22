-- Correct the audit RPC's administrator expression to its declared text type.
begin;

create or replace function festival.list_control_audit(p_festival_id uuid default null, p_limit integer default 30)
returns table(created_at timestamptz, administrator text, control text, previous_value boolean, new_value boolean, festival_id uuid)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not festival.is_current_admin() then raise exception 'administrator access required' using errcode = '42501'; end if;
  return query select a.created_at, coalesce(u.email, 'Administrator')::text, a.control, a.previous_value, a.new_value, a.festival_id
  from festival_private.control_audit a join auth.users u on u.id = a.performed_by
  where (p_festival_id is null and a.festival_id is null) or a.festival_id = p_festival_id
  order by a.created_at desc limit greatest(1, least(coalesce(p_limit, 30), 100));
end $$;

commit;
