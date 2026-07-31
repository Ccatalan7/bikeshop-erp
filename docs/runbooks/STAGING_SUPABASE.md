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
| Production-derived clone | Recorded per validation session | Disposable | Off-production compatibility testing against a production schema snapshot |

The repository remains linked to production for deployment metadata. Do not
relink it merely to inspect another environment.

Staging's **policy status** is dormant even if Supabase reports its provider
status as `ACTIVE_HEALTHY`. Provider health describes whether the project is
running; it does not authorize use or make its schema representative. Agents
must not query, mutate, repair, or cite staging during normal work. Only the
owner may reactivate it explicitly.

## Non-negotiable boundaries

- Production is the compatibility source of truth.
- `supabase/sql/core_schema.sql` is the required idempotent bootstrap mirror,
  not proof of the live deployed schema.
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
2. **Canonical bootstrap gate:** rebuild from `core_schema.sql` and run the full
   pgTAP suite only when the canonical schema changed or at a release/checkpoint
   boundary. This validates the bootstrap mirror, not production compatibility.
3. **Production-derived compatibility session:** for database behavior intended
   for production, restore a schema-only dump from the verified production
   project into a disposable database, apply only migrations absent from live
   history, and run affected pgTAP contracts there.
4. **Live read-only evidence:** inspect current migration history, catalogs,
   ACLs, configuration, counts, and business invariants before deployment.
5. **Live deployment and read-back:** when authorized, apply the smallest
   reviewed forward change, verify exact definitions and invariants, then
   register migration history.

A schema-only clone contains no production customer data and does not reproduce
live rows or every provider-managed behavior. Never describe it as fully
representative; pair it with live read-only evidence and post-deployment
verification.

## Reuse of a production-derived snapshot

“Fresh” means that the snapshot has known provenance and still matches the
production schema/migration identity recorded at the start of one coherent
validation session. It does **not** mean taking a new dump for every pgTAP run.

Record outside Git:

- production project ref;
- dump UTC time and SHA-256;
- PostgreSQL version;
- production migration head or equivalent schema fingerprint;
- migrations absent from production when the session started.

Reuse the same dump and prepared clone while that identity is unchanged. Rerun
pgTAP, change test selectors, reset the disposable database from the same dump,
and reapply an idempotent candidate migration without downloading production
again.

Use `scripts/db/production_validation.sh` for this cache. `prepare` performs a
cheap live read-only identity check and downloads schema only on a cache miss;
`reuse` and `test` make no production/network call. `refresh` is the explicit
forced-capture operation.

Take a new dump only when:

- production migration history or the recorded schema fingerprint changed;
- the prior dump has missing, unknown, or stale provenance;
- the dump or disposable database is corrupt or incomplete; or
- a final high-risk gate explicitly requires a newer snapshot.

Do not redump merely because a test failed, a selector changed, the candidate
SQL changed, or pgTAP is being rerun.

## Production change contract

For a production database change:

1. Inspect the intended target and relevant business evidence read-only.
2. Search for existing objects and verify the live definition before designing
   a new one.
3. Create a unique, idempotent forward migration and mirror the same
   objects/logic in `supabase/sql/core_schema.sql`.
4. Document forward behavior, recovery behavior, lock/timeout risk, and any
   backfill scope.
5. Run focused local tests during development.
6. Run the affected contracts in one production-derived validation session and
   combine them with live read-only checks.
7. Immediately before deployment, verify the production ref, migration head,
   candidate checksum, and no-PII business fingerprint.
8. Apply one smallest guarded migration at a time.
9. Read back functions, triggers, policies, grants, indexes, constraints, and
   affected business invariants before advancing.
10. Register the exact migration version only after live read-back succeeds,
    then run health checks and the relevant application smoke.

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

Only the owner may reactivate staging. Reactivation starts by rebuilding it from
a current production-derived schema and proving catalog, extension, policy,
grant, configuration, and fixture parity. Until that evidence exists, staging
tests remain diagnostic and cannot support release-readiness claims.

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
