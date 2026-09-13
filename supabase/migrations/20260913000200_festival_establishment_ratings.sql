-- Additive public establishment ratings. Tapa reviews and their policies remain unchanged.
begin;

create function festival_private.can_review_establishment(establishment uuid)
returns boolean language sql stable security invoker set search_path = '' as $$
  select exists (
    select 1
    from festival.establishments e
    join festival.festivals f on f.id = e.festival_id
    where e.id = establishment and e.is_published and e.participation_status = 'active'
      and f.publication_status = 'published' and f.reviews_enabled
  )
$$;

create table festival.establishment_reviews (
  id uuid primary key default gen_random_uuid(),
  establishment_id uuid not null references festival.establishments(id) on delete restrict,
  user_id uuid not null references festival.profiles(user_id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint establishment_reviews_one_per_user unique (user_id, establishment_id)
);
create index establishment_reviews_establishment_idx on festival.establishment_reviews(establishment_id);
alter table festival.establishment_reviews enable row level security;
create trigger establishment_reviews_touch_row before insert or update on festival.establishment_reviews
for each row execute function festival_private.touch_row();

create function festival_private.guard_establishment_review_update()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if (new.id, new.user_id, new.establishment_id, new.created_at)
    is distinct from (old.id, old.user_id, old.establishment_id, old.created_at)
    then raise exception 'establishment review identity and creation time are immutable' using errcode = '42501'; end if;
  if new.rating is distinct from old.rating and (
    old.user_id is distinct from (select auth.uid())
    or not festival_private.can_review_establishment(old.establishment_id)
  ) then raise exception 'establishment rating edits require the author and an eligible establishment' using errcode = '42501'; end if;
  return new;
end $$;
create trigger establishment_review_update_guard before update on festival.establishment_reviews
for each row execute function festival_private.guard_establishment_review_update();

revoke all on festival.establishment_reviews from public, anon, authenticated;
grant select on festival.establishment_reviews to anon, authenticated;
grant insert(establishment_id, user_id, rating) on festival.establishment_reviews to authenticated;
grant update(rating) on festival.establishment_reviews to authenticated;
grant delete on festival.establishment_reviews to authenticated;
grant execute on function festival_private.can_review_establishment(uuid) to authenticated;

create policy establishment_reviews_public_read on festival.establishment_reviews for select to anon, authenticated
using (festival_private.is_public_establishment(establishment_id));
create policy establishment_reviews_owner_read on festival.establishment_reviews for select to authenticated
using (user_id = (select auth.uid()));
create policy establishment_reviews_admin_read on festival.establishment_reviews for select to authenticated
using ((select festival_private.is_admin()));
create policy establishment_reviews_owner_insert on festival.establishment_reviews for insert to authenticated
with check (user_id = (select auth.uid()) and festival_private.can_review_establishment(establishment_id));
create policy establishment_reviews_owner_update on festival.establishment_reviews for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()) and festival_private.can_review_establishment(establishment_id));
create policy establishment_reviews_owner_delete on festival.establishment_reviews for delete to authenticated
using (user_id = (select auth.uid()));
create policy establishment_reviews_admin_delete on festival.establishment_reviews for delete to authenticated
using ((select festival_private.is_admin()));

create view festival.establishment_rating_stats with (security_invoker = true) as
select
  e.id as establishment_id,
  f.id as festival_id,
  count(r.id) as rating_count,
  avg(r.rating) as average_rating
from festival.establishments e
join festival.festivals f on f.id = e.festival_id
left join festival.establishment_reviews r on r.establishment_id = e.id
where e.is_published and f.publication_status in ('published', 'archived')
group by e.id, f.id;
revoke all on festival.establishment_rating_stats from public, anon, authenticated;
grant select on festival.establishment_rating_stats to anon, authenticated;

commit;
