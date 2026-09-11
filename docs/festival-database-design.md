# Tapas Festival database foundation — Phase 1A

Status: approved architecture implemented as repository migrations only. Applying
migrations, appointing admins, exposing the API schema, committing, deploying, and
application/UI work require separate approval. No live schema inspection or
migration execution is implied by this document.

## Scope and baseline

The free, non-commercial `tapas-festival` application initially serves Castellón,
approximately 60 establishments and 120+ tapas. Its purpose is to help visitors find
good/excellent tapas while voting is open. Retain Nuxt 4, Vue 3, Pinia, Supabase Auth,
Leaflet, and Vercel. No new application infrastructure is required.

The existing `supabase/schema.sql` defines `tastemap.places` and
`tastemap.comparisons`. These are personal, user-owned records protected by ownership
RLS. The app stores binary-insertion ranks and guests load sample JSON. Google OAuth
and email/password login already exist. The new shared model does not import or
reinterpret those ranks/comparisons. Keep the old schema, setup file, code, config,
and Pinia patch intact as the rollback/reference baseline.

## Migration inventory

Apply in this order only after approval, as a trusted migration owner (normally
`postgres`). PostgreSQL 15+ is required for security-invoker views.

1. `supabase/migrations/20260911000100_festival_core.sql`: schemas, tables,
   constraints, indexes, timestamps, opening-hours/custom-field validators, RLS
   enabled with no client access yet.
2. `supabase/migrations/20260911000200_festival_security.sql`: explicit grants,
   RLS, private admin helper, review edit guard, profile backfill and signup trigger.
3. `supabase/migrations/20260911000300_festival_ratings.sql`: read-only aggregate view.

Each migration is transactional. These are ordered one-time migrations, not
idempotent setup scripts. Existing `festival`/`festival_private` schemas cause the
core migration to fail rather than silently adopt unrelated objects. Do not rerun
the Tastemap setup script or replace its exposed-schema list. These migrations do
not alter PostgREST configuration, Storage, the Tastemap schema, or Auth providers.
The only future change on `auth.users` is the additive profile signup trigger;
existing users are read to create their independent festival profiles.

## Tables and relationships

All entity IDs are generated UUID primary keys except profiles/admin membership,
whose user UUID is the primary key. All public tables have `created_at` and
`updated_at` timestamptz columns. A trigger sets creation/update times and preserves
creation time on updates. Admin membership has `created_at` only.

| Table | Columns beyond ID and timestamps |
| --- | --- |
| `festival.festivals` | `slug text UNIQUE`, `name_en/name_es text`, `description_en/description_es text`, `start_date/end_date date`, `default_tapa_price numeric(8,2)`, `currency_code text DEFAULT 'EUR'`, `city text`, `timezone text DEFAULT 'Europe/Madrid'`, `default_language text DEFAULT 'en'`, `publication_status text DEFAULT 'draft'`, `reviews_enabled boolean DEFAULT false` |
| `festival.establishments` | `festival_id uuid FK`, `name text`, bilingual descriptions, `address text`, `latitude/longitude double precision`, `phone/whatsapp/facebook_url/website_url text`, `opening_hours jsonb`, bilingual `hours_notes`, `photo_path text`, `is_published boolean DEFAULT false`, `participation_status text DEFAULT 'active'`, `closure_status text DEFAULT 'normal'`, bilingual `status_note`, `sort_order integer DEFAULT 0` |
| `festival.tapas` | `establishment_id uuid FK`, bilingual names/descriptions, `price_override numeric(8,2)`, `photo_path text`, `is_published boolean DEFAULT false`, `participation_status text DEFAULT 'active'`, bilingual `status_note`, `festival_number integer`, `sort_order integer DEFAULT 0` |
| `festival.profiles` | `user_id uuid PK/FK auth.users`, `display_name text DEFAULT 'Festival visitor'`, `avatar_url text` |
| `festival.reviews` | `tapa_id uuid FK`, `user_id uuid FK profiles`, `rating smallint`, `review_text text`, `moderation_status text DEFAULT 'visible'`, UNIQUE `(user_id,tapa_id)` |
| `festival_private.admin_users` | `user_id uuid PK/FK auth.users` |
| `festival.field_definitions` | `festival_id uuid FK`, `key text`, bilingual labels/descriptions, `field_type text`, `applies_to text`, `options jsonb`, `required boolean DEFAULT false`, `sort_order integer DEFAULT 0`, `active boolean DEFAULT true` |
| `festival.field_values` | `field_definition_id uuid FK`, `establishment_id uuid FK NULL`, `tapa_id uuid FK NULL`, `value jsonb NOT NULL` |

Optional translations, descriptions, contact information, hours, notes, photos,
programme numbers and price overrides are nullable. Coordinates may both be NULL
on drafts; published establishments require valid coordinates. Essential identity,
parent references, dates, prices, statuses, switches and sort orders are NOT NULL
as specified in the migration. Descriptions need not exist in either language.

An establishment is one venue's participation in one festival. Another year uses
another row: no venue catalogue/join table is needed yet. Festival membership of
tapas is derived through establishments. Establishment festival and tapa parent
references are immutable to protect historical meaning. There is no two-tapa limit.

### Constraints and deletion

- A festival/tapa name and custom-field label must have at least one nonblank
  translation. Venue names and addresses are nonblank single-language strings.
- End date is on/after start date. Timezone must exist in `pg_timezone_names`.
- Prices are nonnegative finite fixed-precision values. EUR is a default, not a
  currency conversion system. Currency codes are three uppercase letters.
- Coordinates are paired and within latitude/longitude bounds.
- Ratings are integers stored as smallint, constrained to 1–5. Review text is
  optional and limited to 3,000 characters. Public display names are 1–80 characters.
- Programme numbers are optional positive display numbers, deliberately not unique.
  Sort order is nonnegative and need not be unique.
- Definition keys are lowercase stable identifiers, unique per festival/target.
  Exactly one field-value target is populated, with a unique value per definition
  per target enforced by partial unique indexes.
- Festival → establishments → tapas → reviews use DELETE RESTRICT. Definition →
  values and entity → values cascade on deletion. Festival → definitions restricts.
- Auth account deletion cascades to profile, reviews and administrator membership.
  This changes historical aggregates. There is no anonymized retention policy yet.

Prefer withdrawing/archiving populated content. Hard deletion of unreferenced draft
content remains possible for admins. Core entity IDs and creation timestamps cannot
be changed. Definition festival/key/target are immutable; populated field types
cannot change. Label/description changes remain editable.

### Indexes

PK/unique indexes cover identity, festival slug, review author+tapa, and definition
key. Additional indexes cover establishment festival+sort order, tapa parent+sort
order, review tapa FK, visible reviews by tapa, definition festival+target+sort
order, and field-definition references. Field-value target+definition partial unique
indexes also support target lookup/cascades. No spatial, JSON search, or materialized
ranking indexes are introduced for this scale.

## Languages and configurable default

English is the development default. `festivals.default_language` accepts `en` or
`es` and can be changed as ordinary admin configuration without migration. It is
not a constraint on which translations must exist. English-only, Spanish-only, and
bilingual names/labels are all supported, including custom text and select labels.

Future application fallback:

- English selection: nonblank English → nonblank Spanish.
- Spanish selection: nonblank Spanish → nonblank English.

Treat empty strings as missing (`NULLIF(btrim(value), '')`). Optional descriptions
may have neither translation. Venue proper names, addresses, phone numbers, URLs,
prices and coordinates have one value. Reviews stay in the author's language.
UI translations and a language switcher are outside Phase 1A.

## Publication, participation, closure and hours

Festival publication is `draft`, `published`, or `archived`. Published and archived
festivals are public; drafts are admin-only. A child is public only when its own
`is_published` flag and every parent publication condition permit it. Archived
festivals remain readable; review eligibility specifically requires `published`.

Participation is `active` or `withdrawn`. It never automatically hides a published
row. Establishment closure is `normal`, `temporarily_closed`, or
`permanently_closed`; closure also does not hide the row. Future black/cross map
markers and labels derive from these values and bilingual notes.

`opening_hours` uses ISO weekdays `1` (Monday) through `7` (Sunday). Values are arrays
of `[start,end]` strings in 24-hour `HH:MM` local time, e.g.:

```json
{"1": [], "2": [["12:00", "16:00"], ["19:00", "23:00"]], "6": [["20:00", "02:00"]]}
```

NULL, `{}`, or an omitted day means unknown hours for the relevant day. An empty
array means no opening period starts that weekday. Multiple periods support split
service. If end is earlier than start, the interval ends the next day; Saturday's
20:00–02:00 extends into Sunday. A future open-now calculation must check previous
day spillover even if the current day is empty. Equal start/end is rejected (no
ambiguous zero/24-hour interval). `24:00` is not accepted; use `00:00` next-day end.
Periods represent a union; overlap normalization, holiday schedules and daylight
saving edge-case display are application concerns for later. Unknown never means
definitely closed. Explicit closure overrides normal weekly availability in the UI.

## Reviews, moderation and profiles

Insert and substantive update require the current authenticated author, a published
festival with `reviews_enabled = true`, and published, active establishment/tapa.
No dates, scheduled opening hours, or closure status are consulted. Testing before
or after the event is allowed with the switch enabled. Turning it off blocks new
reviews and owner rating/text edits. Owners can still read and delete their reviews,
including hidden reviews or reviews whose parents have since become private.

Statuses are `visible` and `hidden`; only visible reviews are public and counted.
Owners can edit hidden reviews while eligible, but edits never unhide them. Admins
may hide/unhide/delete regardless of voting availability. Admins cannot rewrite
another person's text/rating or submit as that person. They can rate as themselves
under ordinary author eligibility rules.

Profiles contain public display name/avatar, user UUID and timestamps only. Signup
and existing-user backfill use the neutral `Festival visitor` name and no avatar.
They do not copy email or trust provider/user metadata. Users may later edit their
own display name/avatar. All profile rows are publicly readable by design; do not
add private fields to this table without revisiting grants and RLS. Profile identity
and timestamps have no client update grants. Accounts are managed through Auth,
not client profile deletion/insertion.

## Security model

All eight tables have RLS enabled. `anon` and `authenticated` receive explicit
SELECT grants on public tables; RLS filters actual rows. Authenticated content CRUD
grants are usable only by administrators through policies. No client TRUNCATE,
schema CREATE, membership table privileges, or admin-appointment RPC is granted.

`festival_private.admin_users` is the authority. `is_admin()` accepts no arguments,
uses current `auth.uid()`, is STABLE SECURITY DEFINER, and has an empty fixed
`search_path` and fully qualified references. A trusted migration owner owns it.
The private schema must never be exposed in PostgREST. Minimal schema USAGE/function
EXECUTE allows policy evaluation; it does not grant membership-table access.
Admin membership has no client policies, including for app admins. Appointment is
a later reviewed privileged operation. No initial administrator is seeded.

Visibility/eligibility helpers are SECURITY INVOKER and follow RLS. The other
SECURITY DEFINER functions are trigger-only profile creation and custom-graph
validation; API roles have no EXECUTE grant on them. All private function grants
are explicitly revoked before narrow re-grants. Do the same in future migrations:
schema-local default revokes alone cannot cancel a permissive global default.

Review insert grants cover only tapa_id, user_id, rating and text. Update grants
cover rating, text and moderation state because admins also use `authenticated`.
The update guard rejects non-admin moderation changes and any cross-author content
rewrite. Identity/creation fields remain immutable. Both RLS USING/WITH CHECK and
column/trigger controls are necessary. Frontend visibility is never authority.

## Bounded dynamic fields

Only establishment and tapa targets exist; each is a real FK. Core prices,
coordinates, statuses, and ratings remain normal columns. Definition types:

| Type | `field_values.value` | Validation |
| --- | --- | --- |
| text | `{"en":"...","es":"..."}` | Only en/es string keys; at least one nonblank translation |
| number | JSON number | JSON strings and null rejected |
| boolean | JSON true/false | Both are real values, including required false |
| select | JSON string such as `"hot"` | Must match one definition option key |

Select options use `[{"key":"hot","label_en":"Hot","label_es":"Caliente"}]`.
Keys are unique and stable; one label language is sufficient. Other field types
have NULL options. Labels can change, but removing a used key fails validation.

Deferred constraint triggers validate target type, same-festival membership,
value type, and publication completeness. Active required definitions must have
values for every target with its own publication flag set, even under a draft
festival/establishment. This catches errors before a parent is made public. Draft
targets may omit required values. Creating required fields on existing public
content requires backfilling values in the same transaction or enabling required
only after population. Deactivating a definition removes its completeness rule
and public visibility, but does not delete historical values.

Checks run on entity, definition and value changes and inspect the final transaction
state. At this small scale the validator scans the custom-field graph rather than
maintaining a second representation. A transaction advisory lock `(74621,1)` taken
before admin content statements serializes content graph writes at the normal
READ COMMITTED isolation level. Review writes are not serialized by this lock.
Repeatable-read content writes are rejected because their snapshots can remain
stale after waiting for the lock. Serializable writes are allowed and callers must
retry serialization failures. Native multi-session concurrency still needs validation
before deployment; PGlite tests exercise single-session transactions.

## Statistics, ranking and price

`festival.tapa_rating_stats` is a SECURITY INVOKER, non-updatable aggregate view:
`tapa_id`, `festival_id`, `rating_count` (bigint), `average_rating` (numeric),
`good_excellent_count` (bigint), `good_excellent_percentage` (numeric, 0–100).
It explicitly filters published parent content and visible reviews even for admins
or owners who can read additional base rows. Unrated/all-hidden tapas return zero
counts and NULL average/percentage. Withdrawn content retains historical statistics.

Future leaderboard queries filter active tapa and establishment participation, then
order by `average_rating DESC NULLS LAST, rating_count DESC, tapa_id ASC`. Always
show rating count. No confidence algorithm, minimum vote count, stored rank, cache,
materialized view, realtime subscription, or background worker is implemented.
The view reflects each query's transaction snapshot; frontend refresh/polling is a
later task. Underlying counts/averages support later confidence-aware ordering.

Effective price is `COALESCE(t.price_override, f.default_tapa_price)` via the
establishment join. Five euros appears only in synthetic tests, not schema defaults.
Freeze historical prices administratively if needed; price versioning is not built.

## Photos and deferred work

Nullable establishment/tapa `photo_path` values reserve a future Storage object key.
No bucket, Storage policy, signed URL, review-photo table, or upload flow is created.
Public avatars may use a normal URL; never persist expiring signed URLs.

No application types, composables, stores, pages, components, config, dependencies,
or deployment settings change in this phase. Later application work will add a
festival data layer alongside Tastemap, implement language fallback, and generate
types after the development database is approved and migrated.

## Validation and next approval boundary

See `supabase/tests/README.md`. Tests are plain transactional SQL assertions and
roll back fixtures. The included runner creates only an in-memory PGlite database,
bootstraps a minimal local Auth contract, applies the three new migrations, and
runs security, integrity and rating tests. It does not read credentials, expose
an HTTP endpoint, or connect to a Supabase project. The validator is installed
separately under `/tmp`; it is not an application dependency.

Before any real application: review live schema drift and PostgreSQL version, the
trusted owner/grants, Auth signup compatibility, PostgREST schema exposure and
native multi-session behaviour in a development environment. Back up existing
data/config. Preserve existing exposed schema entries when adding `festival`, and
never expose `festival_private`. Apply approved additive migrations in development
first, appoint a reviewed admin, and only then begin application integration.
Rollback initially means retaining the old application and schema, not dropping
new tables containing festival data. The Auth trigger remains an integration point
that must be considered explicitly in any later database rollback procedure.

Known deliberately deferred decisions: confidence-aware ranking, programme-number
uniqueness, photo management, account deletion retention alternatives, multi-account
voting abuse, and users deleting/recreating hidden reviews. One review per account
per tapa does not prove one vote per person or block recreation after deletion.

Technical references:

- [Supabase RLS and views](https://supabase.com/docs/guides/database/postgres/row-level-security)
- [Supabase column privileges](https://supabase.com/docs/guides/database/postgres/column-level-security)
- [Supabase function security](https://supabase.com/docs/guides/database/functions)
- [PostgreSQL constraint triggers](https://www.postgresql.org/docs/current/sql-createtrigger.html)
