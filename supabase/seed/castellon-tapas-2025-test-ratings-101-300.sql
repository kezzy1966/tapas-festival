-- Additive deterministic test data for Castellón Tapas Festival 2025.
-- Creates/fetches only user101@example.test through user300@example.test, then
-- replaces only those users' ratings for this one festival. It never touches
-- user1-user100, user301+, or any non-test user.
-- Run with an authenticated, privileged development database connection.

begin;

create temporary table seed_festival (id uuid primary key) on commit drop;
insert into seed_festival (id)
select id from festival.festivals where slug = 'castellon-tapas-2025';

do $$
begin
  if (select count(*) from seed_festival) <> 1 then
    raise exception 'expected exactly one castellon-tapas-2025 festival';
  end if;
end $$;

create temporary table seed_accounts (
  number integer primary key,
  email text not null,
  user_id uuid not null
) on commit drop;

-- Password hashes are generated locally in PostgreSQL and never output. These
-- accounts are confirmed development fixtures; no client, service-role key, or
-- RLS bypass is added to the application.
insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
)
select
  '00000000-0000-0000-0000-000000000000'::uuid,
  ('c0000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  'authenticated',
  'authenticated',
  'user' || n || '@example.test',
  extensions.crypt(encode(extensions.gen_random_bytes(24), 'hex'), extensions.gen_salt('bf')),
  now(),
  jsonb_build_object('provider', 'email', 'providers', jsonb_build_array('email')),
  jsonb_build_object('display_name', 'user' || n),
  now(), now()
from generate_series(101, 300) as n
where not exists (
  select 1 from auth.users u where lower(u.email) = lower('user' || n || '@example.test')
);

-- Supabase Auth uses this identity row for email-provider accounts. Existing
-- matching identities are retained so a rerun is idempotent.
insert into auth.identities (
  id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
)
select
  gen_random_uuid(),
  u.id::text,
  u.id,
  jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true, 'phone_verified', false),
  'email',
  now(), now(), now()
from generate_series(101, 300) as fixture(number)
join auth.users u on lower(u.email) = lower('user' || fixture.number || '@example.test')
where not exists (
  select 1 from auth.identities i where i.user_id = u.id and i.provider = 'email'
);

insert into seed_accounts (number, email, user_id)
select fixture.number, u.email, u.id
from generate_series(101, 300) as fixture(number)
join auth.users u on lower(u.email) = lower('user' || fixture.number || '@example.test');

do $$
begin
  if (select count(*) from seed_accounts) <> 200 then
    raise exception 'expected 200 deterministic test accounts';
  end if;
end $$;

-- The auth.users signup trigger normally creates these rows. The insert also
-- repairs a prior interrupted local seed without modifying non-test profiles.
insert into festival.profiles (user_id, display_name)
select user_id, 'user' || number from seed_accounts
on conflict (user_id) do update set display_name = excluded.display_name;

-- Reruns replace only 101-300 fixture ratings associated with this festival,
-- preserving user1-user100, user301+, all manual/real ratings, and fixture
-- activity in other festivals.
delete from festival.reviews r
using festival.tapas t, festival.establishments e, seed_accounts u, seed_festival f
where r.user_id = u.user_id
  and r.tapa_id = t.id
  and t.establishment_id = e.id
  and e.festival_id = f.id;

delete from festival.establishment_reviews r
using festival.establishments e, seed_accounts u, seed_festival f
where r.user_id = u.user_id
  and r.establishment_id = e.id
  and e.festival_id = f.id;

create temporary table seed_tapa_ratings on commit drop as
with active_tapas as (
  select
    t.id as tapa_id,
    -- A few deliberately receive no fixtures; the remainder have varied demand.
    case when get_byte(decode(md5(t.id::text), 'hex'), 0) < 8 then 0
      else 3 + (get_byte(decode(md5(t.id::text), 'hex'), 1) % 78) end as popularity,
    3.15 + get_byte(decode(md5(t.id::text), 'hex'), 2)::numeric / 255 * 1.35 as quality
  from festival.tapas t
  join festival.establishments e on e.id = t.establishment_id
  join seed_festival f on f.id = e.festival_id
  where t.is_published and t.participation_status = 'active'
    and e.is_published and e.participation_status = 'active'
), users_with_activity as (
  select u.*, case
    when get_byte(decode(md5(u.user_id::text), 'hex'), 0) % 100 < 15 then 10
    when get_byte(decode(md5(u.user_id::text), 'hex'), 0) % 100 < 92 then 55
    when get_byte(decode(md5(u.user_id::text), 'hex'), 0) % 100 < 97 then 125
    else 170 end as activity
  from seed_accounts u
), candidates as (
  select u.user_id, t.tapa_id, t.quality,
    get_byte(decode(md5(u.user_id::text || ':' || t.tapa_id::text), 'hex'), 0) as participation,
    get_byte(decode(md5(u.user_id::text || ':rating:' || t.tapa_id::text), 'hex'), 1) as rating_byte,
    get_byte(decode(md5(u.user_id::text || ':comment:' || t.tapa_id::text), 'hex'), 2) as comment_byte,
    least(95, floor(t.popularity * u.activity / 100.0))::integer as threshold
  from users_with_activity u cross join active_tapas t
)
select
  tapa_id,
  user_id,
  round(least(5.0::numeric, greatest(1.0::numeric,
    quality + ((rating_byte % 17) - 8)::numeric / 10
      - case when rating_byte < 5 then 1.20 else 0 end
      + case when rating_byte > 247 then 0.25 else 0 end
  )), 1)::numeric(2,1) as rating,
  case when comment_byte % 100 < 22 then (array[
    'Really tasty', 'Would order again', 'Excellent flavours', 'Very good',
    'Nice presentation', 'Great little tapa', 'Fresh and tasty', 'Really enjoyed this',
    'Good but quite rich', 'Lovely flavours', 'Excellent', 'Very enjoyable',
    'Nice texture', 'Good portion', 'Interesting combination', 'Could be better',
    'Not for me', 'Too salty', 'Very fresh', 'Would come back',
    'One of my favourites', 'Surprisingly good', 'Beautifully presented',
    'Good value', 'Very tasty', 'Excellent bite'
  ])[1 + (comment_byte % 26)] end as review_text,
  timestamp '2026-09-01 00:00:00+00'
    + (((get_byte(decode(md5(user_id::text || ':tapa-created:' || tapa_id::text), 'hex'), 0)::bigint * 65536
      + get_byte(decode(md5(user_id::text || ':tapa-created:' || tapa_id::text), 'hex'), 1)::bigint * 256
      + get_byte(decode(md5(user_id::text || ':tapa-created:' || tapa_id::text), 'hex'), 2)::bigint) % 1162800)
      * interval '1 second') as created_at
from candidates
where participation % 100 < threshold;

-- The normal timestamp trigger sets inserts to now(). Temporarily suppress it only
-- for these explicit fixture inserts, so Trending sees genuine new-rating times.
set local session_replication_role = replica;

insert into festival.reviews (tapa_id, user_id, rating, review_text, moderation_status, created_at, updated_at)
select tapa_id, user_id, rating, review_text, 'visible', created_at, created_at
from seed_tapa_ratings;

create temporary table seed_bar_ratings on commit drop as
with active_establishments as (
  select
    e.id as establishment_id,
    3 + (get_byte(decode(md5(e.id::text), 'hex'), 1) % 78) as popularity,
    3.10 + get_byte(decode(md5(e.id::text), 'hex'), 2)::numeric / 255 * 1.40 as quality
  from festival.establishments e
  join seed_festival f on f.id = e.festival_id
  where e.is_published and e.participation_status = 'active'
), users_with_activity as (
  select u.*, case
    when get_byte(decode(md5(u.user_id::text || ':bar'), 'hex'), 0) % 100 < 15 then 10
    when get_byte(decode(md5(u.user_id::text || ':bar'), 'hex'), 0) % 100 < 92 then 55
    when get_byte(decode(md5(u.user_id::text || ':bar'), 'hex'), 0) % 100 < 97 then 125
    else 170 end as activity
  from seed_accounts u
), candidates as (
  select u.user_id, e.establishment_id, e.quality,
    get_byte(decode(md5(u.user_id::text || ':' || e.establishment_id::text), 'hex'), 0) as participation,
    get_byte(decode(md5(u.user_id::text || ':rating:' || e.establishment_id::text), 'hex'), 1) as rating_byte,
    least(95, floor(e.popularity * u.activity / 100.0))::integer as threshold
  from users_with_activity u cross join active_establishments e
),
sampled as (
  select
    establishment_id,
    user_id,
    round(least(5.0::numeric, greatest(1.0::numeric,
      quality + ((rating_byte % 17) - 8)::numeric / 10
        - case when rating_byte < 5 then 1.20 else 0 end
        + case when rating_byte > 247 then 0.25 else 0 end
    )), 1)::numeric(2,1) as rating,
    timestamp '2026-09-01 00:00:00+00'
      + (((get_byte(decode(md5(user_id::text || ':bar-created:' || establishment_id::text), 'hex'), 0)::bigint * 65536
        + get_byte(decode(md5(user_id::text || ':bar-created:' || establishment_id::text), 'hex'), 1)::bigint * 256
        + get_byte(decode(md5(user_id::text || ':bar-created:' || establishment_id::text), 'hex'), 2)::bigint) % 1162800)
        * interval '1 second') as created_at
  from candidates
  where participation % 100 < threshold
), fallback as (
  -- Every participating venue gets at least one deterministic fixture rating.
  select
    e.establishment_id,
    u.user_id,
    round(least(5.0::numeric, greatest(1.0::numeric,
      e.quality + ((get_byte(decode(md5(u.user_id::text || ':rating:' || e.establishment_id::text), 'hex'), 1) % 17) - 8)::numeric / 10
    )), 1)::numeric(2,1) as rating,
    timestamp '2026-09-01 00:00:00+00'
      + (((get_byte(decode(md5(u.user_id::text || ':bar-created:' || e.establishment_id::text), 'hex'), 0)::bigint * 65536
        + get_byte(decode(md5(u.user_id::text || ':bar-created:' || e.establishment_id::text), 'hex'), 1)::bigint * 256
        + get_byte(decode(md5(u.user_id::text || ':bar-created:' || e.establishment_id::text), 'hex'), 2)::bigint) % 1162800)
        * interval '1 second') as created_at
  from active_establishments e
  cross join lateral (
    select user_id
    from users_with_activity
    order by md5(e.establishment_id::text || user_id::text)
    limit 1
  ) u
  where not exists (
    select 1 from sampled s where s.establishment_id = e.establishment_id
  )
)
select * from sampled
union all
select * from fallback;

insert into festival.establishment_reviews (establishment_id, user_id, rating, created_at, updated_at)
select establishment_id, user_id, rating, created_at, created_at
from seed_bar_ratings;

set local session_replication_role = origin;

-- Concise deterministic verification, without emitting user identities or secrets.
-- All activity timestamps are deterministic seconds from 1 September through
-- 14 September 2026 10:59:59 UTC, avoiding future-dated fixture activity.
select
  (select count(*) from seed_accounts) as test_users_created_or_found,
  (select count(*) from seed_tapa_ratings) as tapa_ratings_created,
  (select count(*) from seed_tapa_ratings where review_text is not null) as written_reviews_created,
  (select count(*) from seed_bar_ratings) as bar_ratings_created,
  (select count(distinct tapa_id) from seed_tapa_ratings) as tapas_with_ratings,
  (select count(distinct establishment_id) from seed_bar_ratings) as establishments_with_ratings;

commit;
