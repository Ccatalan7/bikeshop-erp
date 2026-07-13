# Supabase Staging Operating Contract — Suspended

> **Current status (2026-07-13): non-authoritative.** Live read-only
> manifests proved that this project matches the repository bootstrap but not
> the production database, including material inventory/accounting drift.
> Automated staging tests and staging-based release claims are suspended.
> Do not spend time reconciling or rebuilding staging unless the owner
> explicitly reactivates that project.

Staging exists to prevent database, trigger, RLS, Edge Function, inventory, payment, and accounting mistakes from reaching production. It stays deliberately small: one hosted schema, synthetic fixtures, critical workflow smoke checks, and no copy of production customer/business data.

## Current use

- Do not run `just e2e`, fixture resets, schema gates, or database mutation
  tests against staging as part of normal development or CI.
- Do not treat a staging pass as evidence of production behavior.
- Keep the project isolated and dormant. It may be used for explicitly labeled
  experiments, but its results are diagnostic only.
- Use affected Flutter/unit tests, application builds, targeted SQL contract
  review, and authenticated read-only production checks. Any production
  mutation still requires an independently reviewed deployment and rollback
  plan; automated tests must never mutate production.

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
- Production query helpers are read-only and do not offer a write override.

## Standard change sequence

1. Update a forward migration and mirror it in `supabase/sql/core_schema.sql`.
2. Run the affected local pgTAP files with `just db-test <name>`.
3. For schema changes, rebuild once with `just db-gate` at the phase/release boundary—not after every edit.
4. Record staging business counts before mutation.
5. Apply the smallest migration to staging. Use the complete schema gate only when establishing/recovering staging or proving canonical idempotency.
6. Run `just db-drift local staging`; application-owned drift must be zero or explicitly explained.
7. Run `just db-smoke staging` and the relevant synthetic workflow journey.
   For routed ERP smoke coverage, run `just e2e`; it builds the ERP entry point
   against staging, signs in with the synthetic staff account, and verifies the
   inventory movements, sales invoices, and purchase invoices surfaces.
8. Compare business counts and targeted inventory/accounting invariants after the change.
9. Save the commit, migration, checks, timestamp and rollback reference in the deployment record.

## Keeping staging current

- Every production database proposal must first be represented by the same commit on staging.
- Never make an undocumented SQL Editor-only change. If an emergency staging experiment succeeds, immediately encode it as a migration and canonical snapshot update, reset/reapply locally, and eliminate drift.
- Run the read-only fingerprint/drift checks after schema work. Do not repeatedly replay the 35,000-line snapshot during normal debugging.
- Staging may intentionally lead production by the pending release commit; it must never silently lag the canonical branch used for that release.

## Data rules

- Use dedicated synthetic tenant/user IDs and clearly labeled fake products, bicycles, jobs, invoices and payments.
- Tests must be rerunnable and clean up in their transaction or deterministic fixture reset.
- Never import production customer names, emails, phone numbers, invoices, messages or credentials.
- Browser automation uses a limited staging-only account, never the owner/coworker login.
- On macOS, the browser account password and staging publishable key come from
  Keychain. In CI they come only from the protected `staging` environment.
- PR previews are built against staging, never the default production Supabase
  URL embedded in the application fallback configuration.

## Evidence required for inventory/accounting work

- forward action and reversal both succeed;
- stock ledger remains continuous and current stock reconciles;
- journal entries balance debit and credit;
- payment/credit balances reconcile at CLP rounding boundaries;
- operation/checkpoint trace connects user action, source document, movement and journal;
- inconsistency view contains no unexplained new high-severity row.

Local pgTAP is the exhaustive database contract layer. Hosted staging uses fingerprints, read-only schema smoke, and selected synthetic workflows; installing a duplicate hosted pgTAP stack is not required.
