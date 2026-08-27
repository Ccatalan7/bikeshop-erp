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
| Production compatibility | Guarded direct read-only queries, then authorized deploy plus live read-back |
| Trace, fingerprint, drift, health | Guarded recipes under `scripts/db/` |
| Project status, secrets, functions, backups | `scripts/supabase_cli.sh` with explicit project ref |
| Verified migration-history registration | `scripts/supabase_cli.sh migration repair --linked` after exact read-back |
| Authenticated REST/RLS behavior | Publishable key and a synthetic authenticated user; privileged secret key only when the test explicitly requires admin behavior |
| Production schema capture | Deprecated; do not use as compatibility evidence |

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

`db-start` reuses the running local stack when the recorded historical-fixture
hash is unchanged. It rebuilds only when the fixture inputs changed, required
sentinel objects are missing, no verified hash exists, or `--reset` was
requested.

`db-test` calls `ensure_local.sh`, then runs only the selected pgTAP files.
Every ordinary pgTAP rerun reuses the already prepared local database. It does
not copy production and does not rebuild from scratch unless the local fixture
inputs actually changed.

**Trampa del seed de tenant en fixtures pgTAP (2026-08-26).** El seed de
inicialización que corre al insertar una fila en `tenants` deja
`request.jwt.claim.sub` apuntando **al id del tenant** y no lo restaura. Desde
ese punto `auth.uid()` devuelve el tenant, y cualquier trigger que capture
actor (`set_mechanic_job_created_by`, guards de identidad) escribe ese uuid
como si fuera un usuario: el síntoma es un
`mechanic_jobs_created_by_fkey violation` en un INSERT de fixture que parecía
correcto, y costó una ronda completa encontrarlo. Regla: **después de insertar
tenants y antes de cualquier otra fila**, limpia el contexto:

```sql
select set_config('request.jwt.claims', '{}', true);
select set_config('request.jwt.claim.sub', '', true);
```

Varias suites antiguas (`mechanic_job_archive`,
`ai_assistant_filtered_operational_reads`, entre otras) no lo hacen y hoy
abortan en local por esta causa, no por el cambio que estés probando: verifica
la preexistencia con teardown/reaplicación antes de atribuirte la falla.

Run the full legacy-fixture gate only when `core_schema.sql` or an included
fixture input changed, or at a deliberate checkpoint:

```bash
just db-gate
```

This gate drops and rebuilds the disposable local `public` schema, applies the
incomplete historical fixture, and runs all pgTAP files. It proves only that
the fixture remains internally usable—not completeness or compatibility with
production.

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
contract. A **standalone migration** means one immutable, uniquely versioned
`supabase/migrations/YYYYMMDDHHMMSS_slug.sql` file containing the complete
forward change. It never means a fragment copied from `core_schema.sql`, an ad
hoc SQL Editor paste, or an unversioned file under `supabase/sql/`.

Encode exact definition and business-invariant checks in one or more read-only
SQL files that fail at SQL level when the expected state is absent. Then use the
single apply → verify → stamp command:

```bash
VINABIKE_DB_WRITE_CONFIRM=production \
  scripts/db/deploy_migration.sh \
  --migration supabase/migrations/YYYYMMDDHHMMSS_change_name.sql \
  --verify supabase/manual_checks/verification/YYYYMMDDHHMMSS_change_name.sql
```

That wrapper refuses non-migration paths and duplicate/legacy version formats,
applies only the standalone file through `query.sh`, runs every verification
read-only, registers the exact version through the guarded CLI, reads the stamp
back, and writes a secondary ignored receipt under
`.tmp/db/migration-receipts/`. If deployment succeeds but verification fails,
the version intentionally remains unregistered until the live state is
diagnosed and this same idempotent path completes.

At any time, ask production—not a file comment—whether one or more candidates
are stamped:

```bash
scripts/db/migration_status.sh \
  supabase/migrations/YYYYMMDDHHMMSS_change_name.sql
```

`APPLIED` means the exact version exists in
`supabase_migrations.schema_migrations`; `NOT_APPLIED` means it does not. A
successful SQL exit without that row is an incomplete deployment, not a
finished migration. Migration repair remains a history-metadata operation, not
a schema deployment path.

Every schema change needs the unique standalone forward migration. Do not edit
an applied migration. `core_schema.sql` is merely an incomplete historical and
best-effort local reference; mirroring there is optional and never a deployment
gate. The migration file may describe intended verification, but its production
status comes only from remote migration history. A local pass is not a
production deployment.

Historical migrations are not a replayable baseline, so CLI migrations are
intentionally disabled in `supabase/config.toml`. Until a clean forward
migration stream is enabled, deploy the reviewed standalone file through the
guarded wrapper above. `supabase db push`, `migration up`, SQL Editor and
`core_schema.sql` are not deployment paths.

## Production compatibility: no schema-copy substitute

Do not run `scripts/db/production_validation.sh` as an implementation or
release gate. It is retained only so old evidence remains interpretable. Run
focused pgTAP against the disposable local database, then inspect the live
production target directly with bounded read-only queries through
`scripts/db/query.sh production`. Confirm migration history, exact signatures,
columns, dependencies, effective ACLs, reference catalogs, materialized state
and relevant invariants. A property introduced by an undeployed migration stays
explicitly unverified until authorized deploy plus executable live read-back;
never replace that gap with a schema-only restore.

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

**2026-08-14 — local Edge bundler fallback.** If a reviewed function passes
`deno check` but the wrapped deploy fails before upload with
`failed to open eszip ... output.eszip`, repeat the same wrapped command with
`--use-api`. That flag moves bundling to Supabase's API and avoids the broken
local temporary eszip path; it does not relax project identity or function
authentication. Read back the resulting active version and exercise the real
endpoint before treating the deployment as complete.

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

**2026-08-27 — legacy writes cannot own new evidence or race a decision.**
When an additive migration must keep an older client writing a shared table,
every new actor/timestamp/version column remains server-owned: the row guard
normalizes it on `INSERT` and preserves or derives it on `UPDATE`, even when
the legacy route itself stays authorized. RLS saying who may update a row does
not stop that actor from spoofing newly added audit columns. Likewise, a
read-then-write conflict check is not a concurrency guarantee. If two commands
decide ownership of the same business identities, take deterministic
transaction-scoped locks for those identities before checking and writing.
Every participating command must acquire shared business-identity locks and
row locks in the same global order; sorting only the identities inside one
helper does not prevent a cycle if another path already holds its task row.
The minimum regression must exercise a forged legacy write against a row that
provably exists and verify the lock is reached before task-row locking on every
command path that can make the decision.

## Autonomous finish checklist

Agents complete these steps themselves when they are in scope and authorized:

- environment and linked-ref preflight;
- credential-presence checks;
- local startup and affected tests;
- guarded production inspection;
- guarded deployment and migration registration;
- exact live read-back, health checks, and application smoke; and
- cleanup of disposable databases/processes while retaining ignored evidence.

Ask for human intervention only for missing provider access, billing/MFA/legal
UI, ambiguous target or authorization, destructive scope expansion, or a
failed gate requiring a business decision. Do not hand the user routine SQL,
tests, or deployment commands to run on the agent's behalf.
