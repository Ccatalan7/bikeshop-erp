# Supabase Daily Workflow

Use this guide for commands. The authority for environment use, release
evidence, and production safety is
`docs/runbooks/STAGING_SUPABASE.md`.

## Current environment map

- Production: `xzdvtzdqjeyqxnkqprtf`; authoritative and repository-linked.
- Staging: `bczzjhjrpmtpgwdvlbut`; policy-dormant and non-authoritative.
- Local: persistent disposable Supabase stack for the fast development loop.

Supabase may report dormant staging as `ACTIVE_HEALTHY`. That is provider
health, not permission to use it. Do not run staging queries, gates, fixtures,
or browser journeys unless the owner explicitly reactivates it. The guarded
launchers enforce this with the per-command
`VINABIKE_STAGING_REACTIVATION_CONFIRM=bczzjhjrpmtpgwdvlbut` confirmation,
which must not be persisted in `.env` or shell startup files.

## Tool boundary

| Need | Canonical path |
|---|---|
| Where an agent starts | `docs/development/AGENT_DATABASE_CONTRACT.md`, then `just db-preflight` |
| What the wrapper accepts and enforces | `bash scripts/db/query.sh --help` / `just db-help` |
| Local or hosted SQL read | `scripts/db/query.sh` or the corresponding `just` recipe |
| Authorized hosted SQL write | `scripts/db/query.sh ... --write` with the exact write confirmation |
| Local pgTAP | `scripts/db/test.sh` / `just db-test` |
| Canonical bootstrap gate | `just db-gate` |
| Production-derived compatibility tests | `scripts/db/production_validation.sh` |
| Trace, fingerprint, drift, health | Guarded recipes under `scripts/db/` |
| Project status, secrets, functions, backups | `scripts/supabase_cli.sh` with explicit project ref |
| Verified migration-history registration | `scripts/supabase_cli.sh migration repair --linked` after exact read-back |
| Authenticated REST/RLS behavior | Publishable key and a synthetic authenticated user; privileged secret key only when the test explicitly requires admin behavior |
| Production schema capture | `scripts/db/production_validation.sh prepare` / explicit `refresh` |

Do not use raw `supabase db query`, `supabase db push`, ad hoc remote `psql`, or
the Supabase SQL Editor as an agent SQL path. The database wrapper supplies the
read-only transaction, timeout, credential loading, and production identity
guards that those paths do not. On Bash/macOS/Linux, do not invoke the Supabase
binary directly for control-plane work either; use `scripts/supabase_cli.sh`.

## Session preflight

Run once at the start of a database task, not before every command:

```bash
just db-preflight
```

That single recipe runs the CLI version check, the linked-ref assertion, the
hosted control-plane project list, and `scripts/db/status.sh`. The individual
commands remain available when a step needs to be inspected on its own:

```bash
cd /Users/Claudio/Dev/bikeshop-erp

scripts/supabase_cli.sh --version
cat supabase/.temp/project-ref
scripts/supabase_cli.sh projects list --output json
bash scripts/db/status.sh
```

Expected linked production ref:

```text
xzdvtzdqjeyqxnkqprtf
```

The project-list result is a control-plane status check. `supabase status`
describes only the local Docker stack; a stopped local stack does not mean
hosted Supabase is down. `scripts/db/status.sh` also reports linked identity,
CLI authentication, API-key metadata, and each credential as
`credential-ready`, `missing`, or `inaccessible` without printing a value.

`scripts/supabase_cli.sh` forces Supabase telemetry, `DO_NOT_TRACK`, and
OpenTelemetry exporters off. This prevents trace/telemetry files from retaining
request metadata and avoids telemetry-file races and sandbox/Windows `EPERM`
failures. It also requires explicit approved project refs, rejects hosted
database shortcuts and project/storage deletion, and requires an exact
per-command confirmation for function deletion or secret removal. Run
control-plane commands sequentially.

From a PowerShell host with the repository's Git Bash available, keep the same
wrapper boundary:

```powershell
bash scripts/supabase_cli.sh projects list --output json
```

## Credentials and what each one does

No private Supabase credential is hardcoded in the repository.

| Credential | Purpose | Approved source |
|---|---|---|
| Supabase CLI access token | Management/control-plane commands | Provider login store; macOS Keychain service `Supabase CLI`, account `supabase` |
| Production database password | Guarded PostgreSQL reads, schema export, and authorized writes | macOS Keychain service `Vinabike ERP Supabase database password`, account `postgres`; CI `SUPABASE_DB_PASSWORD` |
| Local-maintenance secret key | Explicit privileged local maintenance/REST consumers | macOS Keychain service `Vinabike ERP Supabase secret key`, account `supabase`; not shared with GitHub |
| GitHub storefront SEO secret key | Storefront SEO sync and snapshot generation in the protected GitHub workflow only | Protected repository secret `SUPABASE_SECRET_KEY`; not copied to local Keychain |
| Publishable key | Public client initialization and RLS-governed requests | macOS Keychain service `Vinabike ERP Supabase publishable key`, account `supabase`; approved client/CI configuration |
| Staging ref/password | Dormant environment tooling | Keychain services `Vinabike ERP Supabase staging project ref` and `Vinabike ERP Supabase staging database password`; protected environment variables |
| Staging publishable key/E2E login | Dormant browser fixtures, only after owner reactivation | Keychain services `Vinabike ERP Supabase staging publishable key` and `Vinabike ERP staging E2E password`; protected `SUPABASE_STAGING_PUBLISHABLE_KEY` / `E2E_PASSWORD` |

The database password is not an API key. The CLI token is not a database login.
The publishable/anon key is public but does not bypass RLS. The secret key is
privileged.

The exposed modern key named `default` was revoked on 2026-07-25. Production
now has two separately validated modern secret keys: local maintenance and
GitHub storefront SEO. Keep them consumer-scoped and in their separate stores;
never recover a secret from CLI key-list output or copy one consumer's key into
the other consumer.

The legacy `service_role` JWT is compromised and still enabled only for
unmigrated consumers. Never add it to a new consumer. The legacy `anon` JWT is
public client configuration and remains active for unmigrated client builds; it
is not a privileged credential. Do not disable or rotate legacy keys in an
ordinary task; follow
`docs/development/SECURITY_REMEDIATION_2026-07-12.md` and migrate every consumer
first.

Check only whether credentials are present. Never print their values, full
connection strings, or credential-bearing commands.

## Fast local loop

```bash
just db-status
just db-start
just db-test payment_integrity_guards
just db-test stock_ledger_continuity sales_credit_note_kernel
just db-query local "select count(*) from stock_movements"
```

`db-start` reuses the running local stack when the recorded canonical-schema
hash is unchanged. It rebuilds only when the schema inputs changed, required
sentinel objects are missing, no verified hash exists, or `--reset` was
requested.

`db-test` calls `ensure_local.sh`, then runs only the selected pgTAP files.
Every ordinary pgTAP rerun reuses the already prepared local database. It does
not copy production and does not rebuild from scratch unless the canonical
schema inputs actually changed.

Run the full bootstrap gate only when `core_schema.sql` or an included schema
input changed, or at a deliberate checkpoint:

```bash
just db-gate
```

This gate drops and rebuilds the disposable local `public` schema, applies the
canonical snapshot, and runs all pgTAP files. It proves the bootstrap mirror,
not compatibility with production.

## Guarded SQL reads

```bash
bash scripts/db/query.sh local \
  --sql "select count(*) from stock_movements" \
  --format table

bash scripts/db/query.sh production \
  --sql "select now() as checked_at, current_database() as database_name" \
  --format table

bash scripts/db/query.sh production \
  --file supabase/manual_checks/diagnostics/example.sql \
  --format table
```

Formats are `table`, `csv`, and `json`. Hosted reads run in a read-only
transaction with a 30-second timeout. The wrapper rejects transaction escape
statements. Batch related read-only evidence into one query/file where that
reduces repeated connections and remains reviewable.

Two further defaults apply to hosted reads, and to hosted reads only. The local
stack holds synthetic data and is unrestricted; a write is already gated by
explicit confirmation and task authorization.

**Row cap.** A single-statement `SELECT`/`WITH` hosted read returns at most 200
rows. The cap is announced on stderr, so a truncated result is never mistaken
for a complete one. Multi-statement input and `--file` are not capped.

```bash
bash scripts/db/query.sh production --max-rows 2000 \
  --sql "select id, status from operations where created_at >= now() - interval '7 days'"

bash scripts/db/query.sh production --max-rows 0 \
  --sql "select count(*) over () from stock_movements"
```

**Sensitive-column guard.** A star projection (`select *`, `select t.*`) that
reads `from`/`join` a table listed in `scripts/db/sensitive_tables.txt` is
rejected. Name the columns the task needs. `count(*)`, aggregates, and explicit
column lists are unaffected, including on those tables.

```bash
# rejected: dumps every personal column of every matched customer
bash scripts/db/query.sh production --sql "select * from customers limit 50"

# correct
bash scripts/db/query.sh production \
  --sql "select id, tenant_id, is_active from customers limit 50"
```

`--allow-pii` overrides the guard when the task genuinely needs the whole row.
It is recorded in the journal. Keep the result out of committed files and
reports. Extend `sensitive_tables.txt` whenever a table starts storing personal
data; the guard limits accidental disclosure and is not an access-control
boundary, which remains RLS and grants.

**Audit journal.** Every invocation appends one line to `.tmp/db/journal.jsonl`
with timestamp, environment, read/write mode, SQL SHA-256, source, format, caps,
duration, and exit status. It never contains SQL text, result values, or
credentials. It is git-ignored local evidence: cite it when reconstructing what
a session did against production, and do not treat it as a deliverable.

Useful guarded diagnostics:

```bash
just db-trace production operation 00000000-0000-4000-8000-000000000000
just db-trace production product 00000000-0000-4000-8000-000000000000
just db-trace production tenant 00000000-0000-4000-8000-000000000000
just db-fingerprint production
just db-drift local production
just db-health production
```

Full manifests and verbose output stay under ignored `.tmp/db/`.

## Authorized production writes

Production writes must already be in task scope and satisfy the policy
contract. Preview the live state read-only, then execute the smallest
idempotent migration:

```bash
VINABIKE_DB_WRITE_CONFIRM=production \
  bash scripts/db/query.sh production \
  --write \
  --file supabase/migrations/YYYYMMDDHHMMSS_change_name.sql
```

Immediately run guarded read-back and business-invariant queries. Only after
the deployed definition passes verification, register the exact version as
applied:

```bash
VINABIKE_DB_WRITE_CONFIRM=production \
  scripts/supabase_cli.sh migration repair \
  --linked \
  --status applied \
  YYYYMMDDHHMMSS
```

Read `supabase_migrations.schema_migrations` back through
`scripts/db/query.sh` and confirm the one exact version. Migration repair is a
history-metadata operation, not a schema deployment path. Never run the entire
`core_schema.sql` against production.

Every schema change needs both:

1. a unique, idempotent forward migration under `supabase/migrations/`; and
2. the same final objects/logic mirrored in idempotent
   `supabase/sql/core_schema.sql`.

The migration file must state its deployment status and verification. A local
pass is not a production deployment.

Historical migrations are not a replayable baseline, so CLI migrations are
intentionally disabled in `supabase/config.toml`. Until a clean forward
migration stream is enabled, deploy the reviewed standalone file through the
guarded wrapper and repair/register migration history only after exact live
read-back. `supabase db push` is not the deployment path.

## Production-derived validation session

Use this layer for SQL/schema behavior intended for production. Follow the
reuse and redump rules in `docs/runbooks/STAGING_SUPABASE.md`.

Prepare once for a task:

```bash
bash scripts/db/production_validation.sh prepare \
  --task expense-notifications \
  --migration supabase/migrations/YYYYMMDDHHMMSS_change_name.sql
```

`prepare` performs one cheap live read-only identity check using the production
catalog fingerprint, migration head, and PostgreSQL version. It reuses the
matching immutable local template and downloads a new schema-only capture only
on an exact cache miss. Captures exclude production rows and validate the
archive contents before use. The capture fingerprints and restores both
`public` and dependency-only `private` definitions because managed Storage/Auth
policies can reference private helpers; their post-data is deferred until both
schemas exist.

Run and rerun focused pgTAP without a production/network call:

```bash
bash scripts/db/production_validation.sh test \
  --task expense-notifications \
  --migration supabase/migrations/YYYYMMDDHHMMSS_change_name.sql \
  --test expense_notifications
```

`test` requires a prior `prepare` or `reuse`. It reuses the task scratch
database. If the local candidate file, hash, or application order changes after
it was applied to that scratch, the wrapper rebuilds only the scratch database
from the cached immutable local template; it does not redownload production.

Use the last cached baseline explicitly when offline:

```bash
bash scripts/db/production_validation.sh reuse \
  --task expense-notifications \
  --migration supabase/migrations/YYYYMMDDHHMMSS_change_name.sql
```

Inspect cache/task state or clean only the task scratch:

```bash
bash scripts/db/production_validation.sh status --task expense-notifications
bash scripts/db/production_validation.sh cleanup --task expense-notifications
```

Evidence and caches live under ignored
`.tmp/db/production-validation/`. `cleanup --task` retains immutable templates
and schema captures for later tasks. Use `refresh --task ...` only when policy
requires a forced new capture. Do not use `cleanup --all --include-templates`
as routine cleanup.

## Supabase CLI: wrapped control plane/metadata only

Examples:

```bash
scripts/supabase_cli.sh projects list --output json
scripts/supabase_cli.sh secrets list \
  --project-ref xzdvtzdqjeyqxnkqprtf
scripts/supabase_cli.sh functions deploy FUNCTION_NAME \
  --project-ref xzdvtzdqjeyqxnkqprtf
scripts/supabase_cli.sh backups list \
  --project-ref xzdvtzdqjeyqxnkqprtf
```

Use `--no-verify-jwt` only when the reviewed function intentionally implements
its own authentication, such as a verified webhook. After a function
deployment, invoke the affected path and verify logs/behavior.

For hosted outages, first compare the wrapped project-list result, project DNS,
and the Auth health endpoint. A healthy hosted project plus a failed local
status is a local Docker issue. Backup and recovery operations follow
`docs/runbooks/DATABASE_BACKUP_AND_RESTORE.md`.

## Auth, RLS, and REST checks

SQL catalog checks cannot prove an authenticated user's RLS behavior. Use a
dedicated synthetic user and tenant through the real client/REST path. A secret
key or SQL Editor session bypasses RLS and cannot be cited as proof of tenant
isolation.

Use privileged REST only when the behavior under test is explicitly an admin
consumer. Use that consumer's own approved secret (the local-maintenance key
for local agent work), load it without printing it, limit the request to the
required columns/tenant, then unset it.

## Autonomous finish checklist

Agents complete these steps themselves when they are in scope and authorized:

- environment and linked-ref preflight;
- credential-presence checks;
- local startup and affected tests;
- guarded production inspection;
- production-derived validation without repeated redumps;
- guarded deployment and migration registration;
- exact live read-back, health checks, and application smoke; and
- cleanup of disposable databases/processes while retaining ignored evidence.

Ask for human intervention only for missing provider access, billing/MFA/legal
UI, ambiguous target or authorization, destructive scope expansion, or a
failed gate requiring a business decision. Do not hand the user routine SQL,
tests, or deployment commands to run on the agent's behalf.
