# Workshop Job and Invoice ERP Ownership Standard

**Status:** Ownership enforcement activated for Viñabike on 2026-07-12 after a clean production shadow observation.
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
- The original 2026-07-10 baseline contained 117 legacy invoice/product
  movement variances across 82 jobs. A refined current-invoice audit on
  2026-07-15, after the one proven FV-00809 repair, classifies 114 remaining
  product/movement differences across 68 jobs: 90 invoice-only products, 23
  movement-only products, and one quantity mismatch. These are review
  candidates, not automatic stock instructions.

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

## Payment-terminal tax ownership and explicit repair — 2026-07-15

- `PaymentForm` is the only employee-facing control for choosing whether a
  sales invoice total includes IVA. `register_sales_payment_with_invoice_tax`
  applies that invoice-wide choice and the idempotent payment in one locked
  transaction.
- A draft/sent invoice is posted before its payment settles receivable. The
  invoice posts revenue/IVA/inventory/COGS; the payment posts only cash/bank
  against receivable. Payment-method defaults are suggestions only and cannot
  silently rewrite the document classification.
- `mechanic_jobs.tax_*`, totals, paid state and payment tax metadata are mirrors
  of invoice-owned truth. Workshop saves cannot write invoice tax directly.
- Invoice/job line synchronization preserves `mechanic_job_items.id` through
  both directions and applies a diff/upsert. It must not delete/recreate all
  items because tasks and per-bike attribution depend on those stable IDs. The
  invoice JSON is only a mirror of physical bicycle attribution: an omitted,
  blank or JSON-null `job_bike_id` preserves the existing value for that same
  stable item, while an explicit value must reference a bicycle linked to the
  same workshop job and tenant or the transaction fails.
- Active job removal is soft delete. It must never cascade-delete the linked
  invoice or its financial evidence.
- Historical repair is explicit, idempotent, audited and database-admin-only.
  The deployed commands are `apply_workshop_line_identity_backfill`,
  `apply_workshop_financial_backfill`, and
  `apply_accounting_source_identity_backfill`. The earlier broad
  `apply_workshop_invoice_backfill` proposal is intentionally absent from the
  remote database; its superseded SQL is archived under
  `supabase/manual_checks/archive/` and is intentionally absent from the active
  migration chain and `core_schema.sql`.
- Workshop tenant ownership is a separate, non-financial boundary.
  `20260715220000_enforce_workshop_tenant_graph.sql` refuses ambiguous graph
  repair, writes immutable evidence for each deterministic null-tenant item,
  and guards future job/customer/bicycle/invoice/product relationships. It does
  not change invoice totals, tax, payment, stock, or accounting records.
- The production batch repaired 18 null-tenant item rows with 18 immutable
  audit rows and left every graph-conflict metric at zero. All workshop,
  invoice, payment, stock and journal fingerprints were unchanged.
- `20260715230000_retire_rogue_job_sync_and_close_trace.sql` keeps the obsolete
  statement-level job-to-invoice sync trigger retired and closes its one exact
  historical `started` trace only after proving the source snapshots,
  job/invoice graph, compliant ownership checkpoint and zero financial effects.
  The production integrity health now has zero critical failures. Negative
  stock remains an operational warning under the authorized staff-sales policy;
  a recent negative transition is critical only when it lacks a completed
  trace operation.
- The last-50-commit audit confirmed every reviewed July 12-15 database object
  was already live. Twelve unique July 12/13 versions plus `20260715220000` and
  `20260715230000` are now registered in remote migration history without
  replaying their SQL. The ambiguous reused `20260320` prefix was deliberately
  not registered; its required rogue-trigger retirement is represented under
  the unique `20260715230000` forward version.
- `journal_entries.source_document_id` plus `source_document_type` is the
  canonical accounting link. `source_reference` and `invoice_number` are
  display/search labels only because historical invoice numbers are not unique.
  New duplicate sales invoice numbers are rejected, but existing duplicates
  remain valid historical documents and are isolated by UUID.

## Deployed workshop-mode hardening — 2026-07-16

The following migrations are represented in the canonical schema and are
deployed, registered and read back in production. Before deployment, two fresh
canonical rebuilds each passed 52 pgTAP files/1.210 assertions. The post-write
health check has zero critical failures; the 22 historical negative-stock rows
remain a known operational warning rather than an inferred repair target:

- `20260716030000_harden_quotation_approval_contract.sql` keeps quotations
  non-posting, freezes/revalidates the approved commercial snapshot and blocks
  unsafe direct mode transitions. It defines functions before requesting a
  short `ACCESS EXCLUSIVE NOWAIT` DDL window (`lock_timeout = 750ms`,
  `statement_timeout = 20s`), so contention aborts the whole transaction rather
  than waiting behind business traffic.
- `20260716035000_normalize_quotation_non_posting_candidate.sql` is the only
  data repair in this slice. Under `SHARE ROW EXCLUSIVE NOWAIT`, it accepts only
  the frozen one-row `PG-00468` fingerprint, normalizes its non-posting totals
  and appends immutable evidence. Zero candidates is a replay-safe success;
  drift aborts. It never creates or replays invoice, payment, stock or journal
  effects, and `PG-00455` is explicitly outside its candidate set.
- `20260716040000_add_mechanic_job_intake_classification_command.sql` resolves
  only `mode_needs_review` service/warranty rows through an idempotent,
  tenant-safe, append-only event. The client reuses one operation key through
  lost-ACK readback/replay. Classification itself cannot create or change an
  invoice, payment, stock movement or journal.
- `20260716050000_harden_online_manual_payment_trace_linkage.sql` resolves the
  completed invoice/payment child traces by their exact deterministic operation
  keys instead of a `created_at` window. A missing or incomplete child aborts
  the parent confirmation atomically, preserving a closed trace graph even if
  the database clock is corrected backwards.
- `20260716060000_preserve_workshop_invoice_bike_attribution.sql` replaces only
  `sync_invoice_items_to_job`: it preserves stable physical `job_bike_id` when
  invoice JSON omits the mirror and rejects invalid/cross-job/cross-tenant
  explicit references. It has **no backfill** and performs no historical data
  rewrite when installed.

Deployed contract `20260716070000_harden_warranty_source_object_contract.sql`
has **no backfill**. It makes a warranty claim inherit the canonical
bicycle/component intake of its original job and rejects stale UI objects
before any covered/not-covered financial decision. It replaces a view,
functions and row guards but performs no business-row DML when installed. The
decision locks the linked invoice in the payment-integrity order: invoice paid
status, positive paid amount, or an active payment blocks entering or leaving
`covered`; an already-`not_covered` paid historical decision remains an audited
no-op and refund/reversal stays invoice-owned. It also
replaces the shared job-to-invoice sync and guarded billable-invoice command so
an existing invoice is always locked before its job. Payment validates an exact
commercial snapshot first. Once settlement starts, both job and invoice
commercial rows, payments, stock and journals are exact no-ops; ordinary saves
never become a hidden historical cleanup. This preserves legacy technical
metadata and avoids both financial rewrites and late false save failures.

Deployed contract `20260716080000_add_canonical_mechanic_job_status_transition.sql`
also has **no backfill**. It replaces client-owned status/timestamp writes with
one replay-safe server command and append-only receipt. The command locks a
linked invoice before its job, permits paid normal services to continue their
operational lifecycle, and blocks a covered-warranty status transition before
its invoice posting/reversal trigger when paid status, positive paid amount or
an active payment exists. Same-state requests are durable no-op receipts and
ordinary job saves omit lifecycle columns entirely.

Deployed contract `20260716090000_complete_non_warranty_nested_invoice_traces.sql`
closes each ordinary service/component invoice trace root created inside a job
status transition before restoring its parent context. A covered warranty
retains the child root only when an exact transaction-local tenant/job/invoice
marker identifies the explicit invoice-owned inventory/cost writer that will
complete it. The migration replaces the warranty lifecycle and trace-frame
restorer functions only and performs no business-row rewrite or historical
trace backfill.

The only backfill, `20260716035000`, matched and updated exactly PG-00468,
appended its immutable event and left PG-00455 unchanged. The before/after
business fingerprint stayed at 747 sales payments totaling CLP 18.130.590,
2.489 stock movements and 2.160 balanced journals totaling CLP 74.607.147,70
on each side. No target-job stock or journal evidence was created.

The reviewed production repairs on 2026-07-15 produced this evidence:

- line identity batch `workshop-line-identity-20260715-v1` stamped 1,023 exact
  line IDs and normalized 398 legacy `Pega` references to `Trabajo`; matcher
  refinement plus batch `workshop-line-identity-20260715-v2` stamped 13 more
  deterministic IDs across eight invoices by accepting legacy dual-populated
  service UUIDs and exact description disambiguation. The remaining 146 lines
  are all paid/delivered history (144 without a surviving candidate and two
  genuinely duplicated candidates), and every mutation has before/after audit;
- financial mirror batch `workshop-financial-20260715-v1` repaired 166 job
  mirrors, 94 payment metadata mirrors and seven invoice journals; one
  inconsistent historical pair, PG-00196 / FV-00326, remains manual review;
- accounting identity batch `accounting-source-identity-20260715-v1` assigned
  UUID ownership to 680 invoice journals and 728 payment journals and created
  two missing journals for duplicate-number invoices. Seven of the nine
  apparent orphans were later proven to be duplicate journals caused by
  zero-padded labels (`FV-000358` versus `FV-00358`); removing them corrected
  CLP 113,000 duplicated receivable/revenue and CLP 25,093 duplicated
  COGS/inventory while preserving seven immutable snapshots. Only two journals
  whose invoice rows were deleted remain unresolved;
- the known FV-00809 posted-edit gap had complete invoice, journal, product and
  movement evidence. The audited operation
  `workshop-inventory-fv00809-pedal-v1` appended its missing one-unit pedal OUT
  movement, changed SKU 4089 from 3 to 2, and required no journal change because
  the UUID-owned journal already contained the exact CLP 2,950 cost. All trace
  and stock invariants passed;
- every metadata/identity batch replayed as a no-op. Invoice truth, payment
  amounts, stock and cash fingerprints were unchanged by those batches; the
  separate FV-00809 repair changed only the one proven product balance. All
  resolvable sales/payment journals are balanced and no source UUID owns more
  than one journal.

The remaining inventory differences were not bulk-replayed. Their current
invoice/movement comparison contains 114 rows across 68 jobs; service/product
reclassification, later physical counts and deleted historical lines prevent
safe automatic interpretation. Only FV-00809 met the exact-document,
exact-cost, zero-existing-movement and no-journal-change proof threshold.

## Production Enforcement Result — 2026-07-12

- Since shadow installation, 9 jobs and 7 linked workshop invoices had real updates.
- The observer recorded zero job-owned stock or revenue-journal attempts.
- Viñabike was changed to `enforce`; rollback is the single settings change back to `shadow` and never deletes evidence.
- Activation preserved 1,654 products, 2,471 movements, 1,203 adjustments, 2,136 journals, 771 sales invoices, and 400 jobs.
- Stock-column drift, unbalanced journals, and workshop control events remained zero.
