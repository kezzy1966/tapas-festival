-- Pending explicit approval: a public image bucket with administrator-only writes.
begin;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('festival-images', 'festival-images', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'festival_images_admin_insert') then
    create policy festival_images_admin_insert on storage.objects for insert to authenticated
      with check (bucket_id = 'festival-images' and (select festival.is_current_admin()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'festival_images_admin_update') then
    create policy festival_images_admin_update on storage.objects for update to authenticated
      using (bucket_id = 'festival-images' and (select festival.is_current_admin()))
      with check (bucket_id = 'festival-images' and (select festival.is_current_admin()));
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'festival_images_admin_delete') then
    create policy festival_images_admin_delete on storage.objects for delete to authenticated
      using (bucket_id = 'festival-images' and (select festival.is_current_admin()));
  end if;
end $$;

commit;
