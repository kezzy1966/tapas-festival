# Festival database tests (local/disposable only)

These are SQL assertion tests, not pgTAP; no PostgreSQL extension is required.
They must not run against the live Supabase project. Each suite begins a transaction,
creates synthetic users/festival data, switches between API roles and JWT identities,
and rolls everything back. `support/setup.sql` is an include, not a standalone test.
Run on an empty disposable database with the three new migrations applied.

## In-memory runner used for Phase 1A

The runner accepts a local PGlite module path and creates `new PGlite()` without a
data directory or connection string. No environment credentials are read. It
creates a minimal `auth.users`/`auth.uid()` contract and the `anon`/`authenticated`
roles only inside that new database. This tests PostgreSQL constraints, functions,
RLS, role/column grants, profile backfill, triggers and views; it does not simulate
the hosted Auth service, OAuth, PostgREST, API schema exposure, or Storage.

An independent temporary installation was used, without changing package.json,
the lockfile or project node_modules:

```sh
npm install --prefix /tmp/tapas-festival-sql-validation --no-save --package-lock=false --ignore-scripts @electric-sql/pglite@0.5.8
node supabase/tests/run-local.mjs /tmp/tapas-festival-sql-validation/node_modules/@electric-sql/pglite/dist/index.js
```

The package is a development validation tool only, not an application dependency.
The runner prints the PostgreSQL version, migration names and assertion counts,
and exits nonzero on any unexpected SQLSTATE, false assertion, or SQL error.
Migration files are selected explicitly by this phase's timestamp/name pattern.
PGlite 0.5.8 uses PostgreSQL 18.3. The schema targets PostgreSQL 15+; run the tests on
the actual development project's version before approving production application.

## Native disposable PostgreSQL/Supabase development database

After separate approval and provisioning of a disposable development database,
the SQL suites can also be run with `psql -X -v ON_ERROR_STOP=1 -f <suite.sql>`.
Use an explicitly verified local connection as a privileged test owner. Do not
copy in production credentials. Do not use `supabase db push` for these tests.
`psql` resolves the `\ir support/setup.sql` includes relative to each suite.

Suites:

- `festival_security.sql`: anonymous public reads, ancestor visibility, withdrawals,
  private admin membership, metadata self-promotion, profile column protection,
  cross-user review attacks, voting switches, date-independent eligibility,
  moderation, immutable review columns, and administrator content permissions.
- `festival_integrity.sql`: bilingual content, defaults, prices, coordinates,
  opening hours, FK restrictions, custom types/targets/festival boundaries,
  required fields, atomic publication, select options, review bounds and account
  deletion cascades.
- `festival_ratings.sql`: zero/NULL semantics, hidden/draft data exclusion for every
  role, good/excellent percentages, live changes and withdrawal filtering.

`expect_error` accepts an explicit `|`-separated alternative SQLSTATE list only where
PostgreSQL versions differ, e.g. DELETE RESTRICT (`23503` or `23001`). It does not
accept arbitrary errors. RLS silently filtering an UPDATE/DELETE is checked through
`RETURNING` row counts, not assumed to raise an exception.

Limitations: the local runner has one database session. Real concurrent transactions,
higher transaction isolation levels, Auth service triggers/config, and PostgREST
embedding/upsert behaviour need later native development testing. The scripts are
not a substitute for checking hosted schema drift and privileges before deployment.
