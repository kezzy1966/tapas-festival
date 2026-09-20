-- Read-only resource metrics for the trusted Superadmin Resources dashboard.
begin;

create function festival.admin_resources()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  result jsonb;
begin
  if coalesce(pg_catalog.current_setting('role', true), '') <> 'service_role' then
    raise exception 'privileged server access required' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'database_size_bytes', pg_catalog.pg_database_size(pg_catalog.current_database()),
    'schemas', coalesce((
      select jsonb_object_agg(x.schema_name, x.size_bytes)
      from (
        select n.nspname as schema_name, sum(pg_catalog.pg_total_relation_size(c.oid))::bigint as size_bytes
        from pg_catalog.pg_class c
        join pg_catalog.pg_namespace n on n.oid = c.relnamespace
        where c.relkind in ('r', 'm', 't')
          and n.nspname in ('festival', 'auth', 'storage', 'festival_private')
        group by n.nspname
      ) x
    ), '{}'::jsonb),
    'auth_users', (select count(*)::bigint from auth.users),
    'auth_identities', (select count(*)::bigint from auth.identities),
    'storage_objects', (select count(*)::bigint from storage.objects),
    'storage_bytes', (select coalesce(sum(case when o.metadata->>'size' ~ '^[0-9]+$' then (o.metadata->>'size')::bigint else 0 end), 0)::bigint from storage.objects o),
    'tables', coalesce((
      select jsonb_agg(jsonb_build_object(
        'schema_name', n.nspname,
        'table_name', c.relname,
        'estimated_rows', coalesce(s.n_live_tup, 0)::bigint,
        'size_bytes', pg_catalog.pg_total_relation_size(c.oid)
      ) order by pg_catalog.pg_total_relation_size(c.oid) desc)
      from pg_catalog.pg_class c
      join pg_catalog.pg_namespace n on n.oid = c.relnamespace
      left join pg_catalog.pg_stat_all_tables s on s.relid = c.oid
      where c.relkind = 'r'
        and n.nspname = 'festival'
        and c.relname in ('reviews', 'establishment_reviews', 'profiles', 'establishments', 'tapas', 'festivals')
    ), '[]'::jsonb),
    'storage_buckets', coalesce((
      select jsonb_agg(jsonb_build_object(
        'bucket_id', b.id,
        'name', b.name,
        'public', b.public,
        'object_count', count(o.id)::bigint,
        'bytes', coalesce(sum(case when o.metadata->>'size' ~ '^[0-9]+$' then (o.metadata->>'size')::bigint else 0 end), 0)::bigint
      ) order by b.name)
      from storage.buckets b
      left join storage.objects o on o.bucket_id = b.id
      group by b.id, b.name, b.public
    ), '[]'::jsonb),
    'activity', coalesce((
      select to_jsonb(d)
      from (
        select xact_commit, xact_rollback, tup_returned, tup_fetched, tup_inserted, tup_updated, tup_deleted, blks_read, blks_hit, stats_reset
        from pg_catalog.pg_stat_database
        where datname = pg_catalog.current_database()
      ) d
    ), '{}'::jsonb)
  ) into result;

  return result;
end
$$;

revoke all on function festival.admin_resources() from public, anon, authenticated;
grant execute on function festival.admin_resources() to service_role;

commit;
