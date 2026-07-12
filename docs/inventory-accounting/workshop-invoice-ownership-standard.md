# Workshop Job and Invoice ERP Ownership Standard

**Status:** Shadow control deployed and verified in production on 2026-07-10; enforcement remains off.
**Rule:** The workshop job is operational. The linked sales invoice exclusively posts on-hand inventory and financial ledgers.

## Posting Ownership

| Concern | Owner | Job responsibility |
|---|---|---|
| On-hand stock deduction/reversal | Sales invoice | Identify required parts and bicycle attribution |
| Revenue, tax, receivable, COGS, inventory GL | Sales invoice | Operational costing preview only |
| Payment balance and paid/unpaid state | Invoice/payment ledger | Mirror the shared paid flag |
| Per-bicycle attribution | `mechanic_job_items.job_bike_id` | Preserve attribution through both sync directions |
| Future reservation/available quantity | Reservation ledger | Reserve/release without changing on-hand or financial accounts |

The job must never create a second stock movement or revenue journal for an effect already owned by its invoice.

## Verified Production Baseline — 2026-07-10

- 398 jobs; 396 linked to invoices.
- Zero persisted job-owned stock movements.
- Zero job-owned revenue journals.
- Zero current job/invoice dual-owner rows.
- 223 jobs currently have invoice-owned movement evidence.
- 12 multi-bike jobs use one shared invoice/payment balance.
- 117 legacy invoice/product movement variances across 82 jobs remain unresolved and untouched.

The legacy job handler contains stock/journal helpers, but its deferred posting block is currently unreachable because each operation branch returns first. The system therefore already behaves as invoice-owned; the control formalizes and monitors that fact instead of changing existing business records.

Production deployment verification preserved the exact Viñabike baseline: inventory and stock sums `1243`, movements `2468`, adjustments `1203`, journals `2128`, jobs `398`, linked jobs `396`, and zero drift, unbalanced journals, trace inconsistencies, job movements, or job journals. The control view contains 398 compliant rows; settings and event tables both started with zero rows.

Fresh pre-deployment backup: `/tmp/bikeshop-erp-pre-workshop-shadow-20260710/`. SHA-256: schema `2810aeaf83a99a42cb7b507453d1c584cf41f2bf72951f43d477bf1eff57d639`; data `2b8c3c626cf46efdd712c9110b433b62e0ac45309419f53b159aeb8c1d09e0eb`.

## Shadow Control

Migration `20260710210000_add_workshop_invoice_shadow_controls.sql`:

- adds only new control settings/events tables and a read-only ownership view;
- defaults every tenant to `shadow` when no setting row exists;
- records attempted `mechanic_job:<id>` movements or `mechanic_jobs` journals;
- attaches an ownership checkpoint to linked invoice trace operations;
- revokes direct anon/authenticated/service-role execution of legacy job stock and journal writers;
- never updates or backfills jobs, invoices, products, movements, payments, or journals.

`enforce` mode blocks a job-owned posting atomically. It is not activated in the migration and requires a separately reviewed tenant setting after a clean observation window.

## Activation Gates

1. Exact tenant-scoped business counts match before and after shadow deployment.
2. Control settings and events start empty; all existing control-view rows are compliant.
3. New job, linked invoice, multi-bike, partial-payment, edit, reopen, and cancellation tests pass.
4. Shadow observation produces no legitimate job-owned writer attempts.
5. Existing legacy variances remain baseline-only and do not block or trigger repair.
6. Enforcement activation receives its own backup, preview, and before/after audit.

Historical corrections are outside this control and require independently proven repair evidence.
