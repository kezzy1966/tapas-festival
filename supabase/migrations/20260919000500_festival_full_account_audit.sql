-- Read-only, server-mediated account audit for Admin Users.
begin;

create function festival.full_account_audit(p_account_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  audit_result jsonb;
begin
  if coalesce(pg_catalog.current_setting('role', true), '') <> 'service_role' then
    raise exception 'privileged server access required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'account_id', u.id,
    'account', case
      when u.email is null or pg_catalog.strpos(u.email, '@') = 0 then 'Account'
      else pg_catalog.left(pg_catalog.split_part(u.email, '@', 1), 6)
        || pg_catalog.repeat('?', greatest(pg_catalog.char_length(pg_catalog.split_part(u.email, '@', 1)) - 6, 0))
        || '@'
        || pg_catalog.left(pg_catalog.split_part(u.email, '@', 2), 6)
        || pg_catalog.repeat('?', greatest(pg_catalog.char_length(pg_catalog.split_part(u.email, '@', 2)) - 6, 0))
    end,
    'role', coalesce(a.role, 'user'),
    'created_at', u.created_at,
    'updated_at', u.updated_at,
    'email_confirmed_at', u.email_confirmed_at,
    'last_sign_in_at', u.last_sign_in_at,
    'providers', coalesce((
      select jsonb_agg(p.provider order by p.provider)
      from (select distinct i.provider from auth.identities i where i.user_id = u.id) p
    ), '[]'::jsonb),
    'email_password_available', (u.encrypted_password is not null and pg_catalog.length(u.encrypted_password) > 0),
    'status', case
      when u.deleted_at is not null then 'Deleted'
      when u.banned_until is not null and u.banned_until > pg_catalog.now() then 'Banned'
      when u.email_confirmed_at is null then 'Email not confirmed'
      else 'Active'
    end,
    'last_festival_activity_at', activity_stats.last_activity_at,
    'activity_summary', jsonb_build_object(
      'tapa_ratings', activity_stats.tapa_rating_count,
      'written_reviews', activity_stats.written_review_count,
      'bar_ratings', activity_stats.bar_rating_count,
      'total_activity', activity_stats.tapa_rating_count + activity_stats.written_review_count + activity_stats.bar_rating_count
    ),
    'role_history', coalesce((
      select jsonb_agg(h.item order by h.created_at desc, h.id desc)
      from (
        select ar.id, ar.created_at,
          jsonb_build_object(
            'action', ar.action,
            'previous_role', ar.previous_role,
            'new_role', ar.new_role,
            'performed_by', case
              when pu.email is null or pg_catalog.strpos(pu.email, '@') = 0 then 'Administrator'
              else pg_catalog.left(pg_catalog.split_part(pu.email, '@', 1), 6)
                || pg_catalog.repeat('?', greatest(pg_catalog.char_length(pg_catalog.split_part(pu.email, '@', 1)) - 6, 0))
                || '@'
                || pg_catalog.left(pg_catalog.split_part(pu.email, '@', 2), 6)
                || pg_catalog.repeat('?', greatest(pg_catalog.char_length(pg_catalog.split_part(pu.email, '@', 2)) - 6, 0))
            end,
            'created_at', ar.created_at
          ) as item
        from festival_private.admin_role_audit ar
        left join auth.users pu on pu.id = ar.performed_by
        where ar.affected_user_id = u.id
        order by ar.created_at desc, ar.id desc
        limit 50
      ) h
    ), '[]'::jsonb),
    'password_reset_history', coalesce((
      select jsonb_agg(h.item order by h.created_at desc, h.id desc)
      from (
        select pa.id, pa.created_at,
          jsonb_build_object(
            'created_at', pa.created_at,
            'target_role', pa.target_role,
            'requesting_administrator', case
              when pu.email is null or pg_catalog.strpos(pu.email, '@') = 0 then 'Administrator'
              else pg_catalog.left(pg_catalog.split_part(pu.email, '@', 1), 6)
                || pg_catalog.repeat('?', greatest(pg_catalog.char_length(pg_catalog.split_part(pu.email, '@', 1)) - 6, 0))
                || '@'
                || pg_catalog.left(pg_catalog.split_part(pu.email, '@', 2), 6)
                || pg_catalog.repeat('?', greatest(pg_catalog.char_length(pg_catalog.split_part(pu.email, '@', 2)) - 6, 0))
            end
          ) as item
        from festival_private.admin_password_reset_audit pa
        left join auth.users pu on pu.id = pa.requesting_admin_id
        where pa.target_user_id = u.id
        order by pa.created_at desc, pa.id desc
        limit 50
      ) h
    ), '[]'::jsonb),
    'review_moderation_history', coalesce((
      select jsonb_agg(h.item order by h.created_at desc, h.id desc)
      from (
        select ma.id, ma.created_at,
          jsonb_build_object(
            'review_id', ma.review_id,
            'action', ma.action,
            'created_at', ma.created_at,
            'establishment', e.name,
            'tapa', coalesce(t.name_en, t.name_es),
            'review_text', r.review_text
          ) as item
        from festival_private.review_moderation_audit ma
        join festival.reviews r on r.id = ma.review_id
        join festival.tapas t on t.id = r.tapa_id
        join festival.establishments e on e.id = t.establishment_id
        where r.user_id = u.id
        order by ma.created_at desc, ma.id desc
        limit 50
      ) h
    ), '[]'::jsonb),
    'activity', coalesce((
      select jsonb_agg(x.item order by x.activity_at desc)
      from (
        select activity_at, jsonb_build_object(
          'activity_kind', case
            when r.rating is not null and nullif(pg_catalog.btrim(r.review_text), '') is not null then 'Tapa rating and review'
            when r.rating is not null then 'Tapa rating'
            else 'Written review'
          end,
          'establishment', e.name,
          'tapa', coalesce(t.name_en, t.name_es),
          'rating', r.rating,
          'review_text', nullif(pg_catalog.btrim(r.review_text), ''),
          'activity_at', r.updated_at
        ) as item
        from festival.reviews r
        join festival.tapas t on t.id = r.tapa_id
        join festival.establishments e on e.id = t.establishment_id
        where r.user_id = u.id
        union all
        select activity_at, jsonb_build_object(
          'activity_kind', 'Bar rating',
          'establishment', e.name,
          'tapa', null,
          'rating', r.rating,
          'review_text', null,
          'activity_at', r.updated_at
        ) as item
        from festival.establishment_reviews r
        join festival.establishments e on e.id = r.establishment_id
        where r.user_id = u.id
        order by activity_at desc
        limit 50
      ) x
    ), '[]'::jsonb)
  )
  into audit_result
  from auth.users u
  left join lateral (
    select a.role
    from festival_private.admin_users a
    where a.user_id = u.id
    limit 1
  ) a on true
  left join lateral (
    select
      count(*) filter (where r.rating is not null)::bigint as tapa_rating_count,
      count(*) filter (where nullif(pg_catalog.btrim(r.review_text), '') is not null)::bigint as written_review_count,
      max(r.updated_at) as last_tapa_activity
    from festival.reviews r
    where r.user_id = u.id
  ) tapa_stats on true
  left join lateral (
    select count(*)::bigint as bar_rating_count, max(r.updated_at) as last_bar_activity
    from festival.establishment_reviews r
    where r.user_id = u.id
  ) bar_stats on true
  left join lateral (
    select
      tapa_stats.tapa_rating_count,
      tapa_stats.written_review_count,
      bar_stats.bar_rating_count,
      case
        when tapa_stats.last_tapa_activity is null then bar_stats.last_bar_activity
        when bar_stats.last_bar_activity is null then tapa_stats.last_tapa_activity
        when tapa_stats.last_tapa_activity >= bar_stats.last_bar_activity then tapa_stats.last_tapa_activity
        else bar_stats.last_bar_activity
      end as last_activity_at
  ) activity_stats on true
  where u.id = p_account_id;

  if audit_result is null then
    raise exception 'user account not found' using errcode = 'P0002';
  end if;
  return audit_result;
end
$$;

revoke all on function festival.full_account_audit(uuid) from public, anon, authenticated;
grant execute on function festival.full_account_audit(uuid) to service_role;

commit;
