-- Stable edition identity, intentionally independent from operational dates.
-- Run as the trusted migration owner (normally postgres), never as an API role.
begin;

alter table festival.festivals add column festival_year integer;

-- A fresh reset has no festival rows. Any populated installation must be the
-- known two-edition data set; fail closed rather than derive years from dates
-- or silently assign a year to an unexpected festival.
do $$
declare festival_count bigint;
begin
  select count(*) into festival_count from festival.festivals;

  if festival_count = 0 then
    null;
  elsif festival_count = 2
    and exists (select 1 from festival.festivals where slug = 'castellon-tapas-2025')
    and exists (select 1 from festival.festivals where slug = 'castellon-tapas-2026') then
    update festival.festivals
    set festival_year = case slug
      when 'castellon-tapas-2025' then 2025
      when 'castellon-tapas-2026' then 2026
    end
    where slug in ('castellon-tapas-2025', 'castellon-tapas-2026');
  else
    raise exception 'festival_year backfill expected exactly castellon-tapas-2025 and castellon-tapas-2026, found % festival rows', festival_count
      using errcode = '23514';
  end if;

  if exists (select 1 from festival.festivals where festival_year is null) then
    raise exception 'festival_year backfill left one or more festival rows unassigned'
      using errcode = '23514';
  end if;
end $$;

alter table festival.festivals
  alter column festival_year set not null,
  add constraint festival_year_range check (festival_year between 2000 and 2100);

commit;
