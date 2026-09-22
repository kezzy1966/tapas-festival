-- Keep withdrawn establishments publicly visible while preventing ordinary-user participation changes.
begin;

create or replace function festival_private.guard_public_review_controls()
returns trigger language plpgsql security definer set search_path = '' as $$
declare c festival.festival_controls; tapa uuid := coalesce(new.tapa_id, old.tapa_id); eligible boolean;
begin
  if festival_private.is_admin() then if tg_op = 'DELETE' then return old; else return new; end if; end if;
  select * into c from festival_private.controls_for_tapa(tapa);
  -- No row means a pre-migration/missing configuration: retain legacy behaviour.
  if c is null then if tg_op = 'DELETE' then return old; else return new; end if; end if;
  if c.public_read_only then
    raise exception 'public festival changes are temporarily unavailable' using errcode = '42501';
  end if;
  select exists (
    select 1 from festival.tapas t
    join festival.establishments e on e.id = t.establishment_id
    where t.id = tapa
      and t.participation_status = 'active'
      and e.participation_status = 'active'
  ) into eligible;
  if tg_op = 'INSERT' and not eligible then
    raise exception 'withdrawn establishments cannot receive public contributions' using errcode = '42501';
  end if;
  if tg_op = 'INSERT' then
    if not c.festival_active then raise exception 'public festival changes are temporarily unavailable' using errcode = '42501'; end if;
    if new.rating is not null and not c.ratings_enabled then raise exception 'ratings are temporarily disabled' using errcode = '42501'; end if;
    if nullif(pg_catalog.btrim(new.review_text), '') is not null and not c.reviews_enabled then raise exception 'reviews are temporarily disabled' using errcode = '42501'; end if;
  elsif tg_op = 'UPDATE' then
    if not eligible and (
      (new.rating is distinct from old.rating and new.rating is not null)
      or (new.review_text is distinct from old.review_text and nullif(pg_catalog.btrim(new.review_text), '') is not null)
    ) then raise exception 'withdrawn establishments cannot receive public contributions' using errcode = '42501'; end if;
    if not c.festival_active and (
      (new.rating is distinct from old.rating and new.rating is not null)
      or (new.review_text is distinct from old.review_text and nullif(pg_catalog.btrim(new.review_text), '') is not null)
    ) then raise exception 'public festival changes are temporarily unavailable' using errcode = '42501'; end if;
    if new.rating is distinct from old.rating and new.rating is not null and not c.ratings_enabled then raise exception 'ratings are temporarily disabled' using errcode = '42501'; end if;
    if new.review_text is distinct from old.review_text and nullif(pg_catalog.btrim(new.review_text), '') is not null and not c.reviews_enabled then raise exception 'reviews are temporarily disabled' using errcode = '42501'; end if;
  end if;
  if tg_op = 'DELETE' then return old; else return new; end if;
end $$;

create or replace function festival_private.guard_public_establishment_rating_controls()
returns trigger language plpgsql security definer set search_path = '' as $$
declare c festival.festival_controls; establishment uuid := coalesce(new.establishment_id, old.establishment_id); eligible boolean;
begin
  if festival_private.is_admin() then if tg_op = 'DELETE' then return old; else return new; end if; end if;
  select * into c from festival_private.controls_for_establishment(establishment);
  if c is null then if tg_op = 'DELETE' then return old; else return new; end if; end if;
  if c.public_read_only then raise exception 'public festival changes are temporarily unavailable' using errcode = '42501'; end if;
  select exists (
    select 1 from festival.establishments e
    where e.id = establishment and e.participation_status = 'active'
  ) into eligible;
  if tg_op = 'INSERT' and not eligible then
    raise exception 'withdrawn establishments cannot receive public contributions' using errcode = '42501';
  end if;
  if tg_op = 'INSERT' and (not c.festival_active or not c.ratings_enabled) then raise exception 'ratings are temporarily disabled' using errcode = '42501'; end if;
  if tg_op = 'UPDATE' then
    if not eligible and new.rating is distinct from old.rating and new.rating is not null then
      raise exception 'withdrawn establishments cannot receive public contributions' using errcode = '42501';
    end if;
    if not c.festival_active and new.rating is not null then raise exception 'public festival changes are temporarily unavailable' using errcode = '42501'; end if;
    if new.rating is distinct from old.rating and new.rating is not null and not c.ratings_enabled then raise exception 'ratings are temporarily disabled' using errcode = '42501'; end if;
  end if;
  if tg_op = 'DELETE' then return old; else return new; end if;
end $$;

commit;
