// In-memory PostgreSQL only: no connection strings, environment credentials, or network clients.
// Usage: node supabase/tests/run-local.mjs /absolute/path/to/pglite/dist/index.js
import { readFile, readdir } from 'node:fs/promises';
import { dirname, isAbsolute, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const modulePath = process.argv[2];
if (!modulePath || !isAbsolute(modulePath) || process.argv.length !== 3) {
  throw new Error('Pass one absolute path to an independently installed PGlite module. See README.md.');
}
const { PGlite } = await import(pathToFileURL(modulePath).href);
const db = new PGlite();
const testsDir = dirname(fileURLToPath(import.meta.url));
const migrationsDir = resolve(testsDir, '../migrations');

async function readSql(file) {
  const sql = await readFile(file, 'utf8');
  const parts = [];
  for (const line of sql.split('\n')) {
    const include = line.match(/^\\ir ([a-zA-Z0-9_./-]+)$/);
    parts.push(include ? await readSql(resolve(dirname(file), include[1])) : line);
  }
  return parts.join('\n');
}

try {
  // Minimal Auth contract, NOT the hosted Supabase Auth service.
  // This bootstrap runs only in this new in-memory instance.
  await db.exec(`
    create role anon nologin;
    create role authenticated nologin;
    create schema auth;
    create table auth.users (
      id uuid primary key,
      email text,
      raw_user_meta_data jsonb default '{}'::jsonb
    );
    create function auth.uid() returns uuid language sql stable as $$
      select coalesce(
        nullif(current_setting('request.jwt.claim.sub', true), ''),
        nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'
      )::uuid
    $$;
    grant usage on schema auth to anon, authenticated;
    grant execute on function auth.uid() to anon, authenticated;
    insert into auth.users(id, email) values
      ('00000000-0000-0000-0000-000000000099', 'existing-private@example.invalid');
  `);
  console.log((await db.query('select version()')).rows[0].version);
  for (const name of (await readdir(migrationsDir)).filter(n => /^20260911000[123]00_festival_.*\.sql$/.test(n)).sort()) {
    await db.exec(await readSql(resolve(migrationsDir, name)));
    console.log(`Applied locally: ${name}`);
  }
  const backfill = await db.query("select display_name from festival.profiles where user_id = '00000000-0000-0000-0000-000000000099'");
  if (backfill.rows[0]?.display_name !== 'Festival visitor') throw new Error('Existing-user profile backfill failed');
  console.log('PASS: existing Auth account backfilled with a non-email display name');
  let total = 1;
  for (const name of (await readdir(testsDir)).filter(n => /^festival_.*\.sql$/.test(n)).sort()) {
    const results = await db.exec(await readSql(resolve(testsDir, name)));
    const checks = results.flatMap(r => r.rows).filter(r => 'assert_true' in r || 'expect_error' in r);
    total += checks.length;
    console.log(`PASS: ${name} (${checks.length} assertions)`);
  }
  console.log(`PASS: ${total} assertions; migrations and tests executed only in memory.`);
} catch (error) {
  console.error('LOCAL VALIDATION FAILED:', error.message);
  if (error.code) console.error('SQLSTATE:', error.code);
  if (error.where) console.error('Context:', error.where);
  if (error.position) console.error('Position:', error.position);
  process.exitCode = 1;
} finally {
  await db.close();
}
