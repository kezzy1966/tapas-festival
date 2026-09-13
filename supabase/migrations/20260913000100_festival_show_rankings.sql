-- Public presentation setting. Existing and future festivals show rankings unless an administrator disables them.
alter table festival.festivals
  add column show_rankings boolean not null default true;
