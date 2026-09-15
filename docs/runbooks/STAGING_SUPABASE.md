# Supabase Environment and Production Validation Policy

This is the authoritative policy for Supabase environment use and
production-compatibility evidence. The executable command guide is
`docs/development/SUPABASE_WORKFLOW.md`.

## Environment authority

| Environment | Project ref | Policy status | Permitted role |
|---|---|---|---|
| Production | `xzdvtzdqjeyqxnkqprtf` | Authoritative | Current schema, migration history, provider configuration, and business invariants |
| Staging | `bczzjhjrpmtpgwdvlbut` | Dormant and non-authoritative | Explicitly approved experiments only |
| Local | Local Supabase stack | Disposable and reusable | Fast development, canonical-schema maintenance, and focused pgTAP |
| Production-derived clone | N/A | Deprecated | Never a compatibility or completion gate |

The repository remains linked to production for deployment metadata. Do not
relink it merely to inspect another environment.

Staging's **policy status** is dormant even if Supabase reports its provider
status as `ACTIVE_HEALTHY`. Provider health describes whether the project is
running; it does not authorize use or make its schema representative. Agents
must not query, mutate, repair, or cite staging during normal work. Only the
owner may reactivate it explicitly.

## Non-negotiable boundaries

- Production is the compatibility source of truth.
- `supabase/sql/core_schema.sql` is an incomplete historical and best-effort
  local reference. It is neither reproducible nor proof of the live deployed
  schema, and it is never applied to a hosted database.
- All SQL reads and writes use the guarded repository tooling described in
  `docs/development/SUPABASE_WORKFLOW.md`. Do not run raw Supabase CLI SQL or
  direct ad hoc `psql` commands against hosted environments.
- Supabase CLI use is limited to control-plane/metadata operations such as
  project status, secrets, Edge Function deployment, backup inspection, and
  post-verification migration-history registration. On Bash/macOS/Linux,
  invoke it through `scripts/supabase_cli.sh`, which disables Supabase telemetry
  and OpenTelemetry. On Windows, invoke that same wrapper through the
  repository's Git Bash; do not create a second unguarded PowerShell path.
- Production queries are read-only by default. A production write requires the
  repository write guard, exact project-identity checks, task-level
  authorization, a reviewed forward and recovery plan, and post-write
  read-back.
- Hosted reads minimize disclosure by default: a bounded row cap and a
  rejection of star projections over the tables listed in
  `scripts/db/sensitive_tables.txt`. Read personal columns by name, and use the
  documented override only when the task genuinely requires the full row. This
  limits accidental disclosure into transcripts, logs, and reports; RLS and
  grants remain the authorization boundary.
- Every guarded invocation is journaled to ignored local evidence recording
  identity and outcome only — never SQL text, result values, or credentials.
- Credentials come only from macOS Keychain, an approved Windows/CI secret
  store, or provider-authenticated tooling. Never print, copy, log, commit, or
  place private credential values in commands that will be reported.
- A public publishable/anon key identifies the API client; it does not bypass
  RLS. A secret/service-role credential is privileged and must never be used
  as an ordinary application or test identity.

## Validation ladder

Use the smallest sufficient layer while developing, then add the higher layers
required by the risk and release scope.

1. **Fast local loop:** reuse the prepared local database and run only affected
   pgTAP files. This is the default while editing.
2. **Legacy local-fixture gate:** when useful, rebuild the disposable local
   database from `core_schema.sql` and run pgTAP. This checks only the historical
   fixture's internal consistency; it cannot establish completeness or
   production compatibility.
3. **Live read-only evidence:** inspect current migration history, catalogs,
   ACLs, configuration, counts, and business invariants before deployment.
4. **Live deployment and read-back:** when authorized, apply the smallest
   reviewed forward change, verify exact definitions and invariants, then
   register migration history.

## Production-derived snapshots are deprecated

`scripts/db/production_validation.sh` remains only as historical tooling; agents
do not run it for implementation, release readiness, or completion evidence.
A schema-only restore omits the very state that repeatedly distinguishes the
live system: migration-seeded rows, materialized-view population, live history,
provider-managed behavior and real data distributions. It can therefore pass a
change that fails live or fail before the candidate SQL is reached. Local tests
and live read-only checks must be reported separately and honestly.

## Production change contract

For a production database change:

1. Inspect the intended target and relevant business evidence read-only.
2. Search for existing objects and verify the live definition before designing
   a new one.
3. Create one unique, idempotent standalone forward migration under
   `supabase/migrations/`. Updating `core_schema.sql` is optional historical
   curation and never part of the deploy gate.
4. Document forward behavior, recovery behavior, lock/timeout risk, and any
   backfill scope.
5. Run focused local tests during development.
6. Query production read-only for the live migration head, exact dependency
   definitions, ACLs, catalogs, materialized state and relevant business
   invariants. Do not claim pre-deploy proof for behavior that only the new SQL
   can provide.
7. Immediately before deployment, verify the production ref, migration head,
   candidate checksum, and no-PII business fingerprint.
8. Apply one smallest guarded migration at a time through
   `scripts/db/deploy_migration.sh`, with executable read-back assertions.
9. Read back functions, triggers, policies, grants, indexes, constraints, and
   affected business invariants before advancing.
10. Let that guarded command register the exact migration version only after
    live read-back succeeds; confirm the remote `APPLIED` stamp, then run health
    checks and the relevant application smoke.

Backfills must be scoped, idempotent, auditable, previewed, and safe to replay.
Stop on unexplained drift; never guess through a partial repair.

## Live mutating probes

An off-production test is preferred. A mutating probe on production requires
explicit owner authorization and a reviewed design that proves all of the
following:

- it runs in `BEGIN`/`ROLLBACK` with bounded statement and lock timeouts;
- it uses fixed synthetic identifiers and a dedicated test tenant;
- cleanup is deterministic; and
- no trigger or function can emit a webhook, HTTP request, message, storage
  write, or other non-transactional side effect.

If any condition cannot be proven, keep the production check read-only.

## Agent ownership and valid handoffs

Agents own routine preflight, credential-presence checks, local startup, test
execution, guarded queries, authorized deployment, migration registration,
read-back, and health checks. Do not ask the user to copy/paste SQL or run a
routine command the repository can run.

Human intervention is valid only when:

- required credentials or provider access are genuinely unavailable;
- the target environment or write authorization is ambiguous;
- an operation is destructive or expands beyond the requested scope;
- billing, MFA, legal confirmation, or another provider-only UI requires the
  account owner; or
- a safety or verification gate fails and the next action needs a business
  decision.

## Staging reactivation

Only the owner may reactivate staging. Reactivation starts by comparing it
directly with guarded live production catalogs and migration history, then
installing reviewed forward migrations and synthetic fixtures. Until live
read-back proves catalog, extension, policy, grant and configuration parity,
staging tests remain diagnostic and cannot support release-readiness claims.

Never import production customer names, emails, phone numbers, invoices,
messages, files, or credentials. Hosted browser journeys use dedicated
synthetic users and tenants.

After explicit owner reactivation, each staging command must also carry
`VINABIKE_STAGING_REACTIVATION_CONFIRM=bczzjhjrpmtpgwdvlbut`. Do not persist
that confirmation in `.env` or shell startup files. The guarded query, schema
gate, and E2E launchers reject staging without it.

## Inventory and accounting evidence

For inventory/accounting changes, also prove:

- forward action and reversal both succeed;
- stock ledger continuity and current-stock reconciliation hold;
- journals balance debit and credit;
- payment and credit balances reconcile at CLP rounding boundaries;
- operation/checkpoint trace links the action, source document, stock movement,
  and journal; and
- no unexplained high-severity inconsistency is introduced.
