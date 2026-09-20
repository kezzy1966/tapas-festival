-- Add opaque account IDs to existing Admin reporting RPC results for trusted Nitro enrichment.
begin;
create or replace function festival.admin_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if (select auth.uid()) is null or not festival.is_current_admin() then
    raise exception 'administrator access required' using errcode = '42501';
  end if;

  return (
    with clock as (
      select pg_catalog.clock_timestamp() as now_at
    ),
    review_summary as (
      select
        count(*) filter (where r.rating is not null)::bigint as tapa_ratings_total,
        count(*) filter (where r.rating is not null and r.created_at >= c.now_at - interval '24 hours')::bigint as tapa_ratings_24h,
        count(*) filter (where nullif(pg_catalog.btrim(r.review_text), '') is not null)::bigint as written_reviews_total,
        count(*) filter (where nullif(pg_catalog.btrim(r.review_text), '') is not null and r.created_at >= c.now_at - interval '24 hours')::bigint as written_reviews_24h,
        count(*) filter (where r.moderation_status = 'hidden' and nullif(pg_catalog.btrim(r.review_text), '') is not null)::bigint as hidden_reviews
      from festival.reviews r
      cross join clock c
    ),
    bar_summary as (
      select
        count(*)::bigint as bar_ratings_total,
        count(*) filter (where r.created_at >= c.now_at - interval '24 hours')::bigint as bar_ratings_24h
      from festival.establishment_reviews r
      cross join clock c
    ),
    active_users as (
      select count(distinct activity.user_id)::bigint as active_users_24h
      from (
        select r.user_id
        from festival.reviews r
        cross join clock c
        where r.created_at >= c.now_at - interval '24 hours'
        union
        select r.user_id
        from festival.establishment_reviews r
        cross join clock c
        where r.created_at >= c.now_at - interval '24 hours'
      ) activity
    ),
    content_summary as (
      select
        (select count(*)::bigint from festival.establishments) as establishments_total,
        (select count(*)::bigint from festival.tapas) as tapas_total,
        (select count(*)::bigint from festival.tapas where is_published and participation_status = 'active') as active_tapas_total,
        (select count(*)::bigint from festival.tapas where participation_status = 'withdrawn') as withdrawn_tapas_total,
        (select count(*)::bigint from festival.establishments where opening_hours is null or opening_hours = '{}'::jsonb) as bars_missing_hours,
        (select count(*)::bigint from festival.establishments where nullif(pg_catalog.btrim(photo_path), '') is null) as bars_missing_photos,
        (select count(*)::bigint from festival.tapas where nullif(pg_catalog.btrim(photo_path), '') is null) as tapas_missing_photos
    ),
    recent_activity as (
      select *
      from (
        select
          r.created_at as activity_at,
          'Tapa rating' as activity_type,
          r.user_id,
          e.name as establishment_name,
          coalesce(t.name_en, t.name_es) as tapa_name,
          r.rating
        from festival.reviews r
        join festival.tapas t on t.id = r.tapa_id
        join festival.establishments e on e.id = t.establishment_id
        where r.rating is not null
        union all
        select
          r.created_at,
          'Written review',
          r.user_id,
          e.name,
          coalesce(t.name_en, t.name_es),
          r.rating
        from festival.reviews r
        join festival.tapas t on t.id = r.tapa_id
        join festival.establishments e on e.id = t.establishment_id
        where nullif(pg_catalog.btrim(r.review_text), '') is not null
        union all
        select
          r.created_at,
          'Bar rating',
          r.user_id,
          e.name,
          null,
          r.rating
        from festival.establishment_reviews r
        join festival.establishments e on e.id = r.establishment_id
      ) activity
      order by activity_at desc
      limit 15
    ),
    recent_activity_json as (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'time', a.activity_at,
            'type', a.activity_type,
            'user_id', a.user_id,
            'user', case
              when u.email is null or pg_catalog.strpos(u.email, '@') = 0 then 'User'
              else pg_catalog.left(pg_catalog.split_part(u.email, '@', 1), 6)
                || pg_catalog.repeat('?', greatest(pg_catalog.char_length(pg_catalog.split_part(u.email, '@', 1)) - 6, 0))
                || '@'
                || pg_catalog.left(pg_catalog.split_part(u.email, '@', 2), 6)
                || pg_catalog.repeat('?', greatest(pg_catalog.char_length(pg_catalog.split_part(u.email, '@', 2)) - 6, 0))
            end,
            'establishment', a.establishment_name,
            'tapa', a.tapa_name,
            'rating', a.rating
          ) order by a.activity_at desc
        ),
        '[]'::jsonb
      ) as items
      from recent_activity a
      join auth.users u on u.id = a.user_id
    ),
    active_tapas as (
      select
        r.tapa_id,
        count(*)::bigint as new_rating_count
      from festival.reviews r
      cross join clock c
      where r.rating is not null
        and r.created_at >= c.now_at - interval '24 hours'
      group by r.tapa_id
      order by new_rating_count desc, r.tapa_id
      limit 5
    ),
    active_tapas_json as (
      select coalesce(
        jsonb_agg(
          jsonb_build_object(
            'tapa', coalesce(t.name_en, t.name_es),
            'establishment', e.name,
            'new_ratings', a.new_rating_count
          ) order by a.new_rating_count desc, a.tapa_id
        ),
        '[]'::jsonb
      ) as items
      from active_tapas a
      join festival.tapas t on t.id = a.tapa_id
      join festival.establishments e on e.id = t.establishment_id
    )
    select jsonb_build_object(
      'headline', jsonb_build_object(
        'registered_users', (select count(*)::bigint from auth.users),
        'tapa_ratings_total', (select tapa_ratings_total from review_summary),
        'tapa_ratings_24h', (select tapa_ratings_24h from review_summary),
        'written_reviews_total', (select written_reviews_total from review_summary),
        'written_reviews_24h', (select written_reviews_24h from review_summary),
        'bar_ratings_total', (select bar_ratings_total from bar_summary),
        'bar_ratings_24h', (select bar_ratings_24h from bar_summary),
        'active_users_24h', (select active_users_24h from active_users)
      ),
      'content', jsonb_build_object(
        'establishments', (select establishments_total from content_summary),
        'tapas', (select tapas_total from content_summary),
        'active_tapas', (select active_tapas_total from content_summary),
        'withdrawn_tapas', (select withdrawn_tapas_total from content_summary),
        'hidden_reviews', (select hidden_reviews from review_summary),
        'bars_missing_hours', (select bars_missing_hours from content_summary),
        'bars_missing_photos', (select bars_missing_photos from content_summary),
        'tapas_missing_photos', (select tapas_missing_photos from content_summary)
      ),
      'recent_activity', (select items from recent_activity_json),
      'most_active_tapas', (select items from active_tapas_json)
    )
  );
end
$$;
drop function if exists festival.tapa_rating_detail(uuid);
create function festival.tapa_rating_detail(p_tapa_id uuid)
returns table (
  programme_number integer,
  establishment_name text,
  tapa_name text,
  total_rating_count bigint,
  average_rating numeric,
  rating_1_19_count bigint,
  rating_2_29_count bigint,
  rating_3_39_count bigint,
  rating_4_44_count bigint,
  rating_45_50_count bigint,
  user_id uuid,
  user_label text,
  rating numeric,
  review_text text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not festival.is_current_admin() then
    raise exception 'administrator access required' using errcode = '42501';
  end if;

  return query
  with target as (
    select t.id, t.festival_number, e.name as establishment_name,
      coalesce(t.name_en, t.name_es) as tapa_name
    from festival.tapas t
    join festival.establishments e on e.id = t.establishment_id
    where t.id = p_tapa_id
  ), summary as (
    select
      count(r.rating)::bigint as total_rating_count,
      avg(r.rating) as average_rating,
      count(r.rating) filter (where r.rating >= 1.0 and r.rating < 2.0)::bigint as rating_1_19_count,
      count(r.rating) filter (where r.rating >= 2.0 and r.rating < 3.0)::bigint as rating_2_29_count,
      count(r.rating) filter (where r.rating >= 3.0 and r.rating < 4.0)::bigint as rating_3_39_count,
      count(r.rating) filter (where r.rating >= 4.0 and r.rating < 4.5)::bigint as rating_4_44_count,
      count(r.rating) filter (where r.rating >= 4.5 and r.rating <= 5.0)::bigint as rating_45_50_count
    from festival.reviews r
    where r.tapa_id = p_tapa_id
  )
  select
    target.festival_number,
    target.establishment_name,
    target.tapa_name,
    summary.total_rating_count,
    summary.average_rating,
    summary.rating_1_19_count,
    summary.rating_2_29_count,
    summary.rating_3_39_count,
    summary.rating_4_44_count,
    summary.rating_45_50_count,
    r.user_id,
    case when u.email is null or position('@' in u.email) = 0 then 'User'
      else left(split_part(u.email, '@', 1), 6)
        || repeat('?', greatest(char_length(split_part(u.email, '@', 1)) - 6, 0))
        || '@'
        || left(split_part(u.email, '@', 2), 6)
        || repeat('?', greatest(char_length(split_part(u.email, '@', 2)) - 6, 0))
    end,
    r.rating,
    r.review_text,
    r.created_at
  from target
  cross join summary
  left join festival.reviews r on r.tapa_id = target.id
  left join auth.users u on u.id = r.user_id
  order by r.created_at desc nulls last;
end
$$;

drop function if exists festival.list_review_moderation(text, text, integer, integer);
create function festival.list_review_moderation(
  p_query text default '',
  p_status text default 'all',
  p_limit integer default 25,
  p_offset integer default 0
)
returns table (
  review_id uuid,
  user_id uuid,
  created_at timestamptz,
  user_label text,
  establishment_name text,
  tapa_name text,
  rating numeric(2,1),
  review_text text,
  status text,
  total_count bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  safe_query text := pg_catalog.btrim(coalesce(p_query, ''));
  like_query text;
  page_size integer := case
    when coalesce(p_limit, 25) < 1 then 1
    when p_limit > 25 then 25
    else coalesce(p_limit, 25)
  end;
  page_offset integer := case
    when coalesce(p_offset, 0) < 0 then 0
    else coalesce(p_offset, 0)
  end;
begin
  if not festival.is_current_admin() then
    raise exception 'administrator access required' using errcode = '42501';
  end if;
  if p_status not in ('all', 'visible', 'hidden') then
    raise exception 'status must be all, visible, or hidden' using errcode = '22023';
  end if;

  like_query := '%' ||
    pg_catalog.replace(
      pg_catalog.replace(
        pg_catalog.replace(safe_query, E'\\', E'\\\\'),
        '%', E'\\%'
      ),
      '_', E'\\_'
    ) || '%';

  return query
  with matching as (
    select
      r.id,
      r.created_at,
      r.user_id,
      r.tapa_id,
      r.rating,
      r.review_text,
      r.moderation_status
    from festival.reviews r
    join festival.tapas t on t.id = r.tapa_id
    join festival.establishments e on e.id = t.establishment_id
    join auth.users u on u.id = r.user_id
    where nullif(pg_catalog.btrim(r.review_text), '') is not null
      and (p_status = 'all' or r.moderation_status = p_status)
      and (
        safe_query = ''
        or u.email ilike like_query escape E'\\'
        or e.name ilike like_query escape E'\\'
        or coalesce(t.name_en, '') ilike like_query escape E'\\'
        or coalesce(t.name_es, '') ilike like_query escape E'\\'
        or r.review_text ilike like_query escape E'\\'
      )
  )
  select
    m.id,
    m.user_id,
    m.created_at,
    case
      when u.email is null or pg_catalog.strpos(u.email, '@') = 0 then 'User'
      else pg_catalog.left(pg_catalog.split_part(u.email, '@', 1), 6)
        || pg_catalog.repeat('?', greatest(pg_catalog.char_length(pg_catalog.split_part(u.email, '@', 1)) - 6, 0))
        || '@'
        || pg_catalog.left(pg_catalog.split_part(u.email, '@', 2), 6)
        || pg_catalog.repeat('?', greatest(pg_catalog.char_length(pg_catalog.split_part(u.email, '@', 2)) - 6, 0))
    end,
    e.name,
    coalesce(t.name_en, t.name_es),
    m.rating,
    m.review_text,
    m.moderation_status,
    count(*) over ()::bigint
  from matching m
  join festival.tapas t on t.id = m.tapa_id
  join festival.establishments e on e.id = t.establishment_id
  join auth.users u on u.id = m.user_id
  order by m.created_at desc, m.id desc
  limit page_size offset page_offset;
end
$$;

drop function if exists festival.user_rating_activity(uuid);
create function festival.user_rating_activity(p_festival_id uuid default null)
returns table (
  festival_id uuid,
  user_id uuid,
  user_label text,
  tapa_rating_count bigint,
  bar_rating_count bigint,
  total_rating_count bigint,
  tapa_ratings jsonb,
  bar_ratings jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not festival.is_current_admin() then
    raise exception 'administrator access required' using errcode = '42501';
  end if;

  return query
  with tapa_activity as (
    select
      e.festival_id,
      r.user_id,
      count(*)::bigint as rating_count,
      jsonb_agg(
        jsonb_build_object(
          'establishment_name', e.name,
          'tapa_name', coalesce(t.name_en, t.name_es),
          'rating', r.rating
        ) order by r.updated_at desc
      ) as ratings
    from festival.reviews r
    join festival.tapas t on t.id = r.tapa_id
    join festival.establishments e on e.id = t.establishment_id
    where r.rating is not null
      and (p_festival_id is null or e.festival_id = p_festival_id)
    group by e.festival_id, r.user_id
  ), bar_activity as (
    select
      e.festival_id,
      r.user_id,
      count(*)::bigint as rating_count,
      jsonb_agg(
        jsonb_build_object(
          'establishment_name', e.name,
          'rating', r.rating
        ) order by r.updated_at desc
      ) as ratings
    from festival.establishment_reviews r
    join festival.establishments e on e.id = r.establishment_id
    where p_festival_id is null or e.festival_id = p_festival_id
    group by e.festival_id, r.user_id
  ), report_users as (
    select ta.festival_id, ta.user_id from tapa_activity ta
    union
    select ba.festival_id, ba.user_id from bar_activity ba
  )
  select
    ru.festival_id,
    ru.user_id,
    case when u.email is null or position('@' in u.email) = 0 then 'User'
      else left(split_part(u.email, '@', 1), 6)
        || repeat('?', greatest(char_length(split_part(u.email, '@', 1)) - 6, 0))
        || '@'
        || left(split_part(u.email, '@', 2), 6)
        || repeat('?', greatest(char_length(split_part(u.email, '@', 2)) - 6, 0))
    end as user_label,
    coalesce(ta.rating_count, 0),
    coalesce(ba.rating_count, 0),
    coalesce(ta.rating_count, 0) + coalesce(ba.rating_count, 0),
    coalesce(ta.ratings, '[]'::jsonb),
    coalesce(ba.ratings, '[]'::jsonb)
  from report_users ru
  join auth.users u on u.id = ru.user_id
  left join tapa_activity ta on ta.festival_id = ru.festival_id and ta.user_id = ru.user_id
  left join bar_activity ba on ba.festival_id = ru.festival_id and ba.user_id = ru.user_id
  order by 5 desc, 2;
end
$$;


create or replace function festival.full_account_audit(p_account_id uuid)
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
            'performed_by_id', ar.performed_by,
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
            'requesting_admin_id', pa.requesting_admin_id,
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
            'moderator_id', ma.performed_by,
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
        select r.updated_at as activity_at, jsonb_build_object(
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
        select r.updated_at as activity_at, jsonb_build_object(
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


revoke all on function festival.admin_dashboard() from public, anon, authenticated;
grant execute on function festival.admin_dashboard() to authenticated;
revoke all on function festival.user_rating_activity(uuid) from public, anon, authenticated;
grant execute on function festival.user_rating_activity(uuid) to authenticated;
revoke all on function festival.tapa_rating_detail(uuid) from public, anon, authenticated;
grant execute on function festival.tapa_rating_detail(uuid) to authenticated;
revoke all on function festival.list_review_moderation(text, text, integer, integer) from public, anon, authenticated;
grant execute on function festival.list_review_moderation(text, text, integer, integer) to authenticated;
revoke all on function festival.full_account_audit(uuid) from public, anon, authenticated;
grant execute on function festival.full_account_audit(uuid) to service_role;
commit;
