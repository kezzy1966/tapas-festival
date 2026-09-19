-- Server-side Admin dashboard aggregates.
begin;

create function festival.admin_dashboard()
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

revoke all on function festival.admin_dashboard() from public, anon, authenticated;
grant execute on function festival.admin_dashboard() to authenticated;

commit;
