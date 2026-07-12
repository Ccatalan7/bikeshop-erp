# Inventory and Accounting Traceability Plan

**Status:** Preventive kernel and professional correction workflows deployed; sales returns and both credit-note families are enforced for Viñabike, while purchase receiving remains in compatibility-safe shadow. Customer/supplier cash-settlement documents are installed inactive pending client rollout. 638 database and 185 Flutter assertions pass. Receipt enforcement observation and approved historical review remain.
**Priority:** Inventory correctness first; accounting parity and complete lineage are mandatory
**Scope:** Every code or database path that can change product quantity, inventory value, or inventory-linked accounting

## Goal

Make every inventory quantity reproducible and trustworthy. A single trace must connect:

`user/system action -> source document/version -> database checkpoints -> stock movement -> product balance -> journal entry/lines -> invariant result`

Reversals, retries, failures, and historical repairs must remain visible and linked to the operation that caused them.

## Definition of Done

- Every stock/accounting writer is present in the source registry and has an owner.
- Each accepted business action has one tenant-scoped operation ID and idempotency key.
- Every stock movement stores its real before/after balance and links to its source operation and document.
- Every related journal entry and reversal links to that same operation and document UUID.
- Posted-document edits apply the exact product and accounting delta once.
- `products.inventory_qty` and `products.stock_quantity` always remain equal.
- Current stock reconciles to the immutable movement ledger with no unexplained difference.
- Journal entries balance and reconcile to their source document/version.
- Retries, concurrent requests, webhook replays, and trigger recursion cannot double-post.
- Production passes the reconciliation gates for an agreed observation window before historical repair.

## Non-Negotiable Guardrails

1. Read `.github/copilot-instructions.md` and `supabase/sql/core_schema.sql` before work. Read `BIKE_WORKSHOP_MASTER_SCHEMA.md` before changing job/invoice behavior.
2. Inspect first, fix second. Production investigation is read-only and tenant-filtered; when using the SQL Editor interactively, run one query at a time.
3. Inspect the live definitions with `pg_get_functiondef`, `pg_get_triggerdef`, and `pg_trigger`; do not assume production matches the repository.
4. Treat `supabase/sql/core_schema.sql` as canonical. Mirror every migration there and keep both forms idempotent. Every standalone SQL file must state deployment status.
5. Search existing objects before adding tables, columns, functions, or triggers. Evaluate `user_activity_log`, `stock_adjustments`, `product_bulk_edit_history`, `stock_movements`, `journal_entries`, and `payment_integrity_backfill_audit` first.
6. Preserve tenant isolation and actor attribution. `SECURITY DEFINER` functions must validate tenant and role explicitly.
7. Never silently clamp stock or update only one stock column. Reject insufficient stock unless a deliberate negative-stock policy is documented and tested.
8. Services and `workshop_consumable`/non-stock products must never create stock or inventory-asset movements.
9. Never delete posted evidence to hide a mistake. Correct it with linked reversal/supersession records.
10. Do not run historical repair SQL until the new path is stable, the discrepancy is proven, and the repair preview is approved.
11. Every production incident must produce a regression test that fails before the fix and remains in the permanent suite.
12. No deployment may proceed with a red relevant test, schema-drift check, authenticated-role smoke test, or pre/post reconciliation gate.
13. Database changes must preserve a documented compatibility window for the current and previous two distributed application builds. Prefer additive changes; explicitly test old-client payloads before removing or tightening contracts.
14. If certification discovers a missing business capability, stop and register the gap. Do not fake it with a status toggle or manual SQL; design the document, accounting ownership, trace, user workflow, tests, rollout, and rollback as a first-class ERP feature.

## Mandatory Change-Safety Gate

Every schema, trigger, RPC, Edge Function, or inventory/accounting UI change must pass:

1. Clean canonical-schema bootstrap and the complete pgTAP suite.
2. Complete Flutter tests plus analyzer checks for affected modules.
3. Production-schema drift comparison for touched tables, functions, triggers, constraints, grants, and RLS.
4. Authenticated smoke tests using real employee-role semantics and N/N-1/N-2 payload contracts.
5. Retry, duplicate submission, timeout, concurrency, insufficient-stock, and partial-failure cases applicable to the change.
6. Immediate production pre/post counts and invariants, followed by a defined observation window.
7. A reversible source-specific rollback that never deletes evidence or rewrites balances blindly.

Deployment scripts and CI must block release when any required gate fails. Manual bypass requires a written incident-level justification and an immediate follow-up test.

## Missing-Capability Protocol

When an expected ERP capability is absent or only simulated by a status change:

1. Mark that source `unsupported` or `incomplete` in the source registry.
2. Prevent ambiguous UI actions from implying accounting or inventory behavior that does not exist.
3. Define separate physical, financial, tax, and payment ownership before implementation.
4. Implement an idempotent database command and append-only trace first, then a guided user workflow.
5. Certify create/edit/void/reversal/partial/retry/concurrency/tenant cases before activation.
6. Release behind a feature flag or shadow comparison when existing production data could be affected.

## Required Deliverables

Keep these concise and update them as work advances:

| Deliverable | Required content |
|---|---|
| Source registry | UI/API entrypoint, Dart/Edge file and method, table/RPC, triggers/functions, statuses, stock owner, accounting owner, actor, idempotency, tests, known gap |
| Transition matrix | Old/new state, item-change case, expected stock delta, expected journal action, reversal behavior |
| Trace contract | Operation/checkpoint fields, allowed actions/outcomes, reversal/supersession rules, retention and RLS |
| Read-only audit pack | Dual-column drift, ledger drift, source drift, duplicates, orphans, actor gaps, journal imbalance |
| Automated tests | pgTAP database tests plus focused Flutter/Edge integration tests for every writer |
| Deployment runbook | Backup, shadow comparison, activation order, post-deploy checks, rollback, observation window |
| Repair register | Evidence, expected/actual values, confidence, proposed correction, approval, trace ID, verification |

## Phase 0 — Establish the Evidence Baseline

- [x] Record `git status`; preserve unrelated work.
- [x] Read the existing history before proposing new fixes:
  - `STOCK_MOVEMENTS_MODULE.md` (historical documentation; verify every claim against current code).
  - `supabase/migrations/20260407135500_inspect_sales_invoice_inventory_bug.sql`.
  - `supabase/migrations/20260407_inspect_stock_movements_predeploy.sql`.
  - `supabase/migrations/20260407134000_fix_sales_invoice_inventory_edit_side_effects.sql`.
  - April 2026 inventory cleanup migrations; distinguish audit-noise cleanup from quantity repair.
- [x] Compare canonical and live definitions of all inventory/accounting triggers and helpers.
- [x] Capture read-only baseline counts for the target tenant:
  - unequal stock columns;
  - product balance versus signed movement net;
  - movement rows without actor/source document;
  - duplicate or orphan movements/adjustments/journals;
  - unbalanced journal entries;
  - posted invoice/job/order quantities versus net stock effects.
- [x] Reproduce one confirmed-invoice edit and one suspicious product history locally using production-shaped fixtures.

**Gate P0:** COMPLETE on 2026-07-10. Baseline queries and regression fixtures are repeatable. No repair has run.

## Phase 1 — Build the Complete Source Registry

Search the entire repository, not only the visible modules. At minimum search for direct writes to `products`, `stock_movements`, `stock_adjustments`, invoices, orders, jobs, journal tables, inventory RPC calls, and session flags such as `app.skip_stock_adjustment_trigger`.

Certify every applicable source below:

| Source family | Cases that must be mapped |
|---|---|
| Sales invoices | Create/edit/delete; draft, sent, confirmed, paid, overdue, cancelled; payments; product/quantity/price/tax/cost changes |
| Workshop jobs | Item add/update/delete, cancellation/reopen/delete, job-to-invoice and invoice-to-job sync, late link/unlink |
| POS | Checkout, services/products/sets, split payments, timeout retry, void, refund, exchange |
| Quick sale | Right-toolbar entrypoint with a database origin distinguishable from normal POS |
| Online sales | Order creation, transfer/MercadoPago payment, webhook replay, fulfilment, cancellation/refund, invoice creation/linking |
| Purchases | Invoice and purchase-order lifecycle, receipt/partial receipt, received edits, payments, returns/credits, deletion |
| Manual stock | Product form, adjustment RPC/UI, backdated counts, damage/loss/theft/internal use/found |
| Bulk/import | Mass editor, CSV/Excel create/upsert, initial stock, retry, partial failure, undo |
| Product behavior | Sets/components, assembly/disassembly, stock-to-non-stock conversion/restore, workshop consumables |
| Logistics | Warehouses, transfers, reservations/releases, counts and returns, even if currently incomplete |
| Legacy/admin | `orders`/`order_items`, old services, direct SQL/service-role writes, seed/backfill, backup/restore, debug fixtures |
| Accounting-only | Manual journals, expenses, payment journals, taxes, and any writer that can duplicate inventory-linked postings |

For each row, identify exactly one **stock-posting owner** and one **accounting-posting owner**. POS, online orders, and jobs must not post stock again if the linked invoice is the designated owner.

**Gate P1:** Every repository write path is classified as authoritative, delegated, intentionally no-op, legacy-to-remove, or unresolved.

**Gate P1 result:** Active writers are mapped in the source registry. POS/Quick Sale use one atomic checkout command; imports use a durable absolute-stock command; conversions and mass edits carry parent/child operation lineage; the legacy order writer is disabled; ledger-only factory reset is refused. Transfers/reservations are explicitly absent capabilities, not hidden stock sources.

## Phase 2 — Define and Run Integrity Checks

Create read-only queries/tests for these invariants:

- `inventory_qty = stock_quantity` for every stock-tracked product.
- `stock_before + signed_delta = stock_after` for each movement.
- Consecutive movement balances form an unbroken per-tenant/product chain.
- Current product stock equals the last persisted balance and the opening balance plus net movements.
- Every automatic movement has an operation, document UUID/version, actor/system identity, and source channel.
- Every reversal identifies the original movement/checkpoint/journal it reverses.
- Every posted source version has exactly the expected product deltas.
- Every inventory-linked document has the expected journal, and every journal is balanced.
- No source/journal/movement crosses tenant boundaries, including duplicate invoice numbers or SKUs across tenants.

Classify historical findings as `verified`, `inferred`, or `legacy_unresolved`; never present inferred lineage as original evidence.

**Gate P2:** The audit produces a reproducible discrepancy register with expected and actual values, severity, evidence, and no mutations.

## Phase 3 — Design the Minimal Trace Kernel

Extend existing structures where practical; add schema only for capabilities that cannot be represented safely.

Required operation metadata:

- operation/correlation ID, tenant ID, actor and executor identity;
- source channel, action, document type/UUID/version and optional line identity;
- request/idempotency key, business timestamp, recorded timestamp;
- old/new status plus before/after snapshots or stable hashes;
- outcome (`started`, `completed`, `failed`, `reversed`, `superseded`) and error details;
- parent operation, retry-of, reversal-of, movement IDs, adjustment IDs, and journal IDs.

Required ordered checkpoints:

1. `accepted`
2. `source_snapshotted`
3. `inventory_planned`
4. `inventory_applied`
5. `movement_recorded`
6. `accounting_planned`
7. `journal_posted`
8. `invariants_verified`
9. `completed`

Rules:

- Business writes must flow through tenant-aware database commands/RPCs; the client must not coordinate several independent writes.
- Propagate the operation context through nested triggers/functions without trusting client-supplied tenant or actor values.
- Movement and journal evidence is append-only after posting. Corrections append linked reversals.
- Persist true movement before/after balances at write time under a product row lock; the UI must not reconstruct history backward from current stock.
- A log written inside a failed transaction also rolls back. Record durable failure outcome from the caller/out-of-transaction path, and reconcile abandoned `started` operations.
- Add only the constraints/indexes required for tenant lookup, operation lookup, source-document lookup, idempotency, and reversal integrity.

**Gate P3:** One tenant-safe query reconstructs a complete action from request through stock, accounting, reconciliation, reversal, or failure.

**Production progress:** The shared operation/checkpoint kernel covers invoices, payments, POS/Quick Sale, structured adjustments, bulk parent/child rows, imports, conversions, online cancellation, and manual online transfer confirmation. Workshop ownership is certified in shadow mode. Receipt shadow mode now appends compatibility evidence for every legacy status writer, so enforcement can be evidence-gated without changing current routing. Existing anomalies were not repaired. Optional future transfers/reservations, the receipt observation window/enforcement decision, and historical review remain open.

Payment extension: sales/purchase payment create, ±1 CLP edit, partial/full transitions, hard/soft undo, related invoice status, linked job paid state, current/legacy payment journal replacement, and the invariant that payment-only actions create zero stock movements are now connected locally. Ambiguous legacy journal duplicates block instead of silently double-posting. Multi-bike job payments are certified as one shared invoice/job balance; per-bike payment allocation does not exist.

## Phase 4 — Implement the Transaction Kernel

For every stock command, use this order in one database transaction:

1. Resolve tenant/actor and claim the idempotency key.
2. Lock the source document and affected products deterministically.
3. Snapshot the previous posted version and aggregate old/new quantities by real product, including set components.
4. Calculate the exact delta; skip services and non-stock treatments.
5. Validate available stock and accounting inputs. Never silently clamp.
6. Update both product stock columns to the same value.
7. Append movements with operation, source version, signed delta, and persisted before/after balances.
8. Append/reverse the related journal entries with the same operation and document UUID.
9. Run invariants; mark the operation complete only after they pass.
10. Roll back every business side effect on error, then persist the failure outcome safely outside that failed transaction.

Remove or delegate direct writers that bypass this kernel. Protect ledger/checkpoint tables from normal update/delete operations through grants, RLS, and guarded RPCs.

**Gate P4:** Retrying or concurrently invoking the same command produces one deterministic stock/accounting result and one connected trace.

## Phase 5 — Certify Sources in Risk Order

1. **Sales invoices first:** fix posted-to-posted product edits. Quantity changes, added/removed lines, product swaps, and set changes apply only the exact delta. Price/tax/cost-only edits change only the appropriate accounting effects.
2. **Purchases:** accounting posts at the defined accounting state; physical stock posts at receipt. Received/paid edits use the stored receipt/posting version, not an unsafe inference from the current status.
3. **Workshop jobs:** designate job or linked invoice as the single stock owner; test both synchronization directions and recursion guards.
4. **POS, Quick Sale, and online sales:** delegate to the same certified sales posting path; retain distinct origins and webhook/idempotency identities.
5. **Manual, product-form, bulk, and import paths:** record clear origin/batch/child operation identities and accounting for value-changing adjustments.
6. **Sets, transfers, returns, conversions, and legacy/admin writers:** certify, route through the kernel, or explicitly disable/remove.

Each source must pass create, edit, transition, cancellation, deletion, retry, concurrent retry, insufficient-stock, partial-failure, and tenant-isolation cases before moving to the next source.

Current certification includes invoice posted edits, sales/purchase payment back-and-forth, multi-bike job settlement, manual adjustments, POS/Quick Sale atomic checkout, receiving, supplier/customer returns, quarantine resolution, sales/purchase credit notes, sets/components, imports, conversions, bulk lineage, actor/FK behavior, and continuous-ledger presentation. The complete clean suite is the release gate; individual fixtures are not presented as proof beyond their cases.

## Phase 5A — Professional Receiving, Returns, and Credit Notes

Repository inspection on 2026-07-11 confirmed that purchase receiving is currently a full-quantity invoice status update, return enums/policies exist without an operational workflow, and sales/purchase credit notes do not exist as first-class ERP documents.

### Goods receipt

- Add immutable purchase receipt headers and lines linked to the purchase invoice, supplier, operation, actor, and source version.
- Keep payment status independent from physical receipt status. The invoice UI may launch receiving, but inventory posts from the receipt command—not from a generic invoice status toggle.
- Default each line to the remaining expected quantity and show expected, previously received, receiving now, accepted, rejected/damaged, and remaining.
- Support partial and multiple receipts. Only accepted stock-tracked quantities enter on-hand inventory exactly once.
- Record shortages, damage, rejection, over-delivery, location, evidence, and supplier-response state without inventing a loss or credit automatically.
- Three-way reconciliation must connect purchase order/expectation, supplier invoice, and goods receipts where those documents exist.

### Returns and discrepancy resolution

- Separate physical disposition from financial resolution: receive later/backorder, supplier claim, return to supplier, quarantine, verified inventory loss, or approved variance.
- A never-received shortage does not create inventory or an inventory-loss movement. A verified loss/damage after ownership uses a traced adjustment and balanced journal.
- Supplier returns remove only the quantity actually returned and reference the original receipt movement.

### Credit notes

- Add sales and purchase credit-note headers/lines that reference the original invoice and optionally its receipt/return lines.
- Support partial quantities and amounts, explicit reason codes, approval/posting/void lifecycle, immutable numbering, and append-only reversals.
- Stock effects depend on physical disposition; financial correction alone must not move stock.
- Accounting effects must reverse/adjust the original revenue, COGS, inventory, receivable/payable, and tax components using the original document context.
- Chilean tax/DTE behavior must be explicitly validated before presenting an internal document as an officially issued tax credit note.

**Gate P5A:** Partial receipts, shortages, damage, supplier returns, sales returns, and both credit-note families pass end-to-end inventory/accounting/trace tests and are available through clear guided UI.

**Deployment progress:** The receipt, supplier return, customer return/disposition, quarantine resolution, and sales/purchase credit-note commands are installed with guided UI. Physical and financial ownership are separate, retries are idempotent, limits are cumulative, sets map to exact component movements, and voids append reversals. Customer/supplier cash-settlement documents now record only externally verified money movement, preserve gross original payments, post balanced cash/AR/AP journals, and never move stock; their independent controls default disabled. Viñabike sales returns and both credit-note controls are `enforce`; purchase receipt is `shadow` until every receipt-capable desktop is updated. Activation created no document, movement, adjustment, or journal rows. Internal credit notes do not claim official SII issuance.

## Phase 6 — Required Transition Tests

Use pgTAP in `supabase/tests/` and focused Flutter/Edge integration tests.

- Sales non-posted -> non-posted: no stock/accounting posting.
- Sales non-posted -> posted: deduct and post exactly once.
- Sales posted -> posted: apply exact line delta; status/payment-only update has zero stock delta.
- Sales posted -> non-posted/cancelled/deleted: linked reversal exactly once.
- Purchase draft/sent -> confirmed: accounting once, no physical stock unless receipt is explicit.
- Purchase confirmed/paid -> received: add stock exactly once for both standard and prepayment flows.
- Purchase received -> received/paid with item edits: exact delta; non-item edits have zero stock effect.
- Purchase receipt reversal/deletion: linked stock/accounting reversal exactly once.
- Job/POS/online delegation: the source and invoice cannot both deduct the same product.
- Normal product, service, non-stock item, workshop consumable, set/component, and cross-tenant duplicate SKU/invoice-number fixtures.
- Replay after timeout, duplicate webhook, helper called twice, concurrent edits, and insufficient stock.
- Final reconciliation of quantity, inventory value, COGS, revenue, tax, receivables/payables, payments, and balanced journals.

Run at minimum: local schema reset, all pgTAP tests, affected Dart tests, analyzer on changed Dart files, and manual end-to-end checks on macOS plus affected Windows/web/mobile paths.

Current safety baseline on 2026-07-12: 638/638 pgTAP assertions across all 36 database test files and 185/185 Flutter tests pass. A clean canonical-schema rebuild, whole-repository analyzer with zero errors/warnings, focused changed-file analysis, refund-dialog lifecycle regression test, and ERP release web build also pass. The repository retains 594 pre-existing analyzer infos under the non-fatal baseline; changed critical modules introduced no analyzer issue.

**Gate P5:** All tests pass against a clean local database and production-shaped fixtures; deliberate failure tests leave no partial business effects.

## Phase 7 — Deploy Safely

- [x] Add a required CI integrity workflow covering canonical database bootstrap, all pgTAP tests, Flutter tests, affected-module analysis, and release-build compilation.
- [x] Make Firebase/desktop release jobs depend on the integrity workflow instead of deploying independently.
- [x] Add database and client-contract fixtures for disabled-schema, legacy-client, enforced-writer, and pre-schema fallback behavior.
- [x] Preserve N/N-1/N-2 database compatibility while controls are disabled; previous clients continue their current route.
- [x] Commit and distribute the verified web build and Windows build 37; migration headers record the verified production schema deployment.
- [x] Take/confirm a recoverable database backup and save pre-deploy reconciliation results.
- [x] Deploy trace capture without duplicating quantity effects; compare exact pre/post production reconciliation totals.
- [x] Activate invoice, trace-kernel, manual-adjustment, and payment source changes one migration at a time.
- [x] After each activation, check object installation, stock/movement/adjustment totals, payment integrity, and journal balance.
- [x] Keep source-specific controls disabled by default; rollback disables routing and preserves posted evidence. A pre-release production schema snapshot is retained outside the repository.
- [x] Mark migration deployment status only after production verification.
- [x] Update `.github/copilot-instructions.md`; update `BIKE_WORKSHOP_MASTER_SCHEMA.md` in the same task when job/invoice data flow changes.

**Gate P6:** No unexplained shadow/production differences during the agreed observation window.

## Phase 8 — Repair Historical Data Last

1. Freeze and preserve the pre-repair audit result.
2. Compute expected stock/accounting per source document version without writing.
3. Produce a review table containing evidence, expected/actual values, confidence, and proposed entries.
4. Obtain explicit approval for the repair set.
5. Apply corrections through the new trace kernel using source `historical_repair`; never delete ambiguous legacy evidence.
6. Link each repair to its discrepancy and original records, then rerun all invariants.
7. Leave uncertain cases as `legacy_unresolved` for manual review.

**Gate P7:** Current quantities, movement ledger, source documents, and accounting reconcile; every correction has an approved trace.

## Agent Handoff Rules

- Complete phases in order and do not bypass a gate.
- Record exact files, functions, trigger definitions, queries, and test results—not assumptions.
- Update this plan's checkboxes/status after each completed phase.
- Stop and report if live schema differs materially, an unregistered writer is found, or a proposed repair cannot be proven.
- Never call the project complete while even one active stock writer bypasses the certified transaction kernel.
