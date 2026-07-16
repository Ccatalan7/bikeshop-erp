# Supabase Production-Representative Validation Contract

> **Current status (2026-07-13): non-authoritative.** Live read-only
> manifests proved that this project matches the repository bootstrap but not
> the production database, including material inventory/accounting drift.
> Automated staging tests and staging-based release claims are suspended.
> Do not spend time reconciling or rebuilding staging unless the owner
> explicitly reactivates that project.

## Non-negotiable source-of-truth rule

- Production project `xzdvtzdqjeyqxnkqprtf` is the compatibility source of
  truth. Staging must not be queried or mutated during normal release work and
  no staging result may be cited as production evidence.
- `supabase/sql/core_schema.sql` remains the mandatory idempotent schema mirror,
  but it is not a record of what has actually been deployed. A database rebuilt
  from it is not a valid compatibility target for production release testing.
- The valid off-production target is a disposable database restored from a
  fresh, read-only dump of the production `public` schema. Evidence must record
  the production project ref, dump time, dump SHA-256, PostgreSQL version, and
  the precise production migration versions that were absent before testing.
- Apply only those absent migrations to the disposable clone. Run focused
  pgTAP contracts there and compare the resulting functions, triggers, policies,
  grants, indexes, and constraints with the intended migration definitions.
- A schema clone contains no production customer data and is deliberately not
  described as fully representative of live data. Pair it with read-only live
  counts/invariants before deployment and exact read-back plus invariant checks
  after each production migration.
- If a test genuinely requires live data or provider behavior, it may run on
  production only with explicit owner authorization and a reviewed
  transaction-safe design. Use `BEGIN`/`ROLLBACK`, a dedicated synthetic tenant,
  fixed UUIDs, bounded locks, and proof that no trigger can cause an external or
  non-transactional side effect. Otherwise the production check stays read-only.

The old staging project is retained only as a dormant historical environment.
Its original purpose does not make its current schema representative.

## Current use

- Do not run `just e2e`, fixture resets, schema gates, or database mutation
  tests against staging as part of normal development or CI.
- Do not treat a staging pass as evidence of production behavior.
- Do not use `just db-gate` or `scripts/db/ensure_local.sh` as production
  compatibility evidence: those commands intentionally bootstrap from
  `core_schema.sql`. They remain useful only for maintaining the bootstrap
  snapshot itself.
- Keep the project isolated and dormant. It may be used for explicitly labeled
  experiments, but its results are diagnostic only.
- Use affected Flutter/unit tests, application builds, a fresh
  production-derived disposable database, targeted SQL contract review, and
  authenticated production checks. Production mutation tests require the
  explicit authorization and transaction-safety contract above; deployment
  requires an independently reviewed forward and recovery plan.

## Historical intended use (not active)

The project was originally intended for use before production when a change
affected:

- tables, columns, constraints, indexes, functions, views, triggers, RLS or migrations;
- invoice/payment/status transitions, stock movement sources, journals, returns, credit notes or receiving;
- Supabase Auth, Storage, Realtime, Edge Functions, webhooks or new API-key behavior;
- a bug that cannot be represented faithfully with local PostgreSQL alone.

Pure documentation, isolated formatting, and unit-tested UI changes do not require staging.

## Environment identity and safety

- Staging project: `bczzjhjrpmtpgwdvlbut` (`vinabike-staging-2026`, `sa-east-1`).
- Production project: `xzdvtzdqjeyqxnkqprtf`.
- The repository remains linked to production for deployment metadata. Do not relink it merely to query staging.
- `scripts/db/` reads staging credentials from macOS Keychain or approved Windows/CI environment variables and never prints them.
- Every staging mutation helper compares project refs and refuses production.
- Production queries are read-only by default. Authorized production writes
  use `scripts/db/query.sh production --write` with
  `VINABIKE_DB_WRITE_CONFIRM=production`; the helper verifies the exact linked
  production project ref before executing.

## Agent-owned production deployment

After read-only inspection proves the issue, the forward SQL is represented in
the repository, production-derived tests pass, and the user has authorized the production
change, the agent must execute the smallest reviewed migration and verify the
live result. Do not stop at a copy/paste snippet or ask the user to run the SQL.

Before execution, record the forward change and recovery approach. Prefer
additive/idempotent migrations. For an additive nullable column, recovery is to
roll back the client while leaving the compatible column in place; do not drop
stored production data merely to reverse a release.

## Standard change sequence

1. Update a forward migration and mirror it in `supabase/sql/core_schema.sql`.
2. Verify the linked production ref and read live migration history, extensions,
   relevant catalogs and business invariants in read-only mode.
3. Take a fresh schema-only production dump, record UTC time and SHA-256 outside
   Git, restore it into a disposable database, and prove its effective catalog/
   ACL baseline matches the dump. Do not apply `core_schema.sql` to this target.
4. Apply only migrations absent from live history to the disposable database,
   then run focused pgTAP contracts for every affected business boundary.
5. Run Flutter/unit/build gates and the normal employee journey against the
   intended backend. Label any synthetic or schema-only limitation explicitly.
6. When the owner authorized production testing and the SQL has no external
   side effects, apply the pending DDL inside one live `BEGIN`/`ROLLBACK` probe
   with bounded locks. Otherwise keep this step read-only.
7. Record a no-PII live business fingerprint, forward/recovery plan and exact
   migration checksum immediately before deployment.
8. Apply each smallest migration separately. Read back functions, triggers,
   policies, grants and constraints; compare the business fingerprint before
   advancing. Stop on unexplained drift.
9. Register the exact migration version only after its live read-back passes.
10. Finish with live health/invariant checks, migration history, application
    smoke and a deployment record tied to the exact client commit/artifact.

## Staging reactivation requirements

- Only the owner may reactivate staging explicitly.
- Reactivation starts by rebuilding it from a current production-derived
  schema and proving catalog, extension, policy, grant and configuration drift;
  old staging state can never be promoted or treated as a baseline.
- Until that proof is recorded, all staging experiments remain diagnostic and
  outside every production readiness claim.

## Data rules

- Use dedicated synthetic tenant/user IDs and clearly labeled fake products, bicycles, jobs, invoices and payments.
- Tests must be rerunnable and clean up in their transaction or deterministic fixture reset.
- Never import production customer names, emails, phone numbers, invoices, messages or credentials.
- Browser automation uses a dedicated synthetic account/tenant for the chosen
  backend, never a coworker's operational identity. A production journey needs
  the same explicit authorization and side-effect review as any other live
  mutation.
- Credentials come only from Keychain, protected CI environments or the
  provider's authenticated tooling; they are never copied into fixtures/logs.
- A preview may use a production-derived disposable backend. It must never be
  described as production-representative when it points to the dormant staging
  project or a `core_schema.sql` bootstrap.

## Evidence required for inventory/accounting work

- forward action and reversal both succeed;
- stock ledger remains continuous and current stock reconciles;
- journal entries balance debit and credit;
- payment/credit balances reconcile at CLP rounding boundaries;
- operation/checkpoint trace connects user action, source document, movement and journal;
- inconsistency view contains no unexplained new high-severity row.

Focused pgTAP against the fresh production-derived database is the SQL contract
layer. Live read-only evidence, optional authorized rollback probes and exact
post-deployment read-back cover the layers a schema-only clone cannot prove.
