# Inventory and Accounting Release Runbook

**Release:** 2026-07-12 preventive kernel and inactive professional documents
**Rule:** schema installation, client distribution, tenant activation, and historical repair are four separate approvals.

Current Viñabike modes: workshop invoice ownership, purchase credit note, sales return, sales credit note, customer refund, supplier refund, and purchase receipt `enforce`. Purchase receipt temporarily allows old-client status receiving only on invoices untouched by the professional receipt ledger.

The direct-product writer compatibility boundary is always active for application/service-role traffic. It is not a tenant mode: supported commands bypass it with their server-controlled posting context, while unknown/old payloads are atomically traced instead of silently changing stock.

## Installed Production Baseline

Immediately before and after the atomic schema transaction:

| Check | Result |
|---|---:|
| Products / movements / adjustments | 1,655 / 2,474 / 1,205 |
| Journals / sales invoices / purchase invoices | 2,137 / 775 / 75 |
| Active sales / purchase payments | 732 / 71 |
| Stock-column drift | 0 |
| Posting-ledger continuity breaks | 0 |
| Current stock vs latest ledger drift | 0 |
| Unbalanced journals | 0 |
| Pre-existing negative tracked products | 20, unchanged |
| New workflow control rows / documents | 0 / 0 |
| New journal supersession evidence rows at install | 0 |

The 2026-07-12 direct-writer installation preserved the later live baseline exactly at 1,654 products, 2,471 movements, 1,203 adjustments, 2,136 journals, 771 sales invoices, 74 purchase invoices, 732 active sales payments, 71 active purchase payments, and 45 completed operations. An authenticated rollback-only smoke created exactly one temporary operation/adjustment/movement/journal and passed all checkpoints, then left zero rows after rollback. All seven quantity/accounting invariants remained zero.

Client release evidence: the deployed web `main.dart.js` SHA-256 is `aada0784427123dd68410da909879e6e2c2cd6c195ac2227e7c8f27c321bf9cc`, identical locally and on Firebase with `max-age=0, must-revalidate`. GitHub Actions run `29184183654` independently passed the canonical DB suite, analyzer baseline, all Flutter tests, ERP web compilation, and Windows build, then published `windows-v1.0.1_3-40` from commit `61d6f0b5`; the Windows zip SHA-256 is `294d0778fb1a34a9c7a068c0b891f3cf76e707c59d2f80be7f7c65232ac19a7d`.

The pre-release schema snapshot is `/tmp/bikeshop-erp-pre-inventory-release-20260711.sql` on the deployment workstation. No historical correction was executed.

## Release Gates

1. `bash scripts/reset_local_supabase.sh` must pass the clean canonical bootstrap and all pgTAP files.
2. `flutter test`, analyzer, and the ERP release web build must pass.
3. Confirm the production counts and five invariants above before and after every rollout step.
4. The verified web client and Windows build 40 were distributed. For purchase receipts, previous clients remain temporarily compatible only on invoices with no professional receipt evidence; update every workstation before retiring that bridge.
5. Activate one tenant and one source family at a time. Record `activated_at` and `activated_by`; never activate all controls in one unobserved change.
6. Exercise create, retry, partial, void, insufficient-stock, and read-back trace cases with supervised business documents.
7. Observe operations, checkpoints, movement chains, settlement balances, and journals before expanding activation.

## Control Tables

- `purchase_receipt_control_settings`
- `purchase_receipt_compatibility_events` (append-only shadow/enforced-rollout evidence)
- `purchase_credit_note_control_settings`
- `sales_return_control_settings`
- `sales_credit_note_control_settings`
- `sales_customer_refund_control_settings`
- `purchase_supplier_refund_control_settings`

Allowed modes are `disabled`, `shadow`, and `enforce`. Absence of a row is disabled. Only `enforce` routes current clients to the new command. `legacy_untouched_compatibility=true` is a temporary purchase-receipt rollout bridge, never a second writer for an invoice that has professional receipt evidence.

## Safe Rollback

- Before any posted receipt: changing purchase receipt back to `shadow` restores legacy routing for all clients without removing schema. After any professional receipt exists, keep mixed-route protection in force and correct through receipt/void commands rather than bypassing ownership.
- After a posted receipt/return/credit: do not delete tables, movements, operations, or journals. Void through its command, verify the linked reversal, then disable routing.
- For POS/Quick Sale client failure: roll the client back to the previous build. The additive database schema remains compatible; never remove a checkout that already committed.
- Posted invoices cannot be deleted. Draft deletion remains available; posted corrections use cancellation, return, credit note, payment reversal, or document void. Legacy journal replacement first writes immutable header-and-line evidence.
- For the sales negative-stock guard: investigate the rejected source. Do not disable it merely to force a sale; use a proven receipt or traced adjustment.
- For the direct-product compatibility boundary: first stop the legacy writer. Emergency rollback drops `trg_prepare_direct_product_stock_trace`, `trg_00_restore_direct_product_stock_trace`, and `zz_finalize_direct_product_stock_trace`, then restores `trg_track_product_stock_changes` to `after insert or update of stock_quantity`; do not drop operation/movement/journal evidence already committed. Supported adjustment/import/invoice commands are independent of this boundary.
- Historical repair is never part of operational rollback. It requires a separately approved discrepancy register.

## Observation Queries

Use the read-only baseline scripts under `supabase/manual_checks/`, plus the production checks for dual-column drift, posting-ledger continuity, current-vs-latest ledger balance, negative tracked stock, unbalanced journals, failed/abandoned operations, and control/document counts. A changed business count must be explained by a named source operation.

Receipt compatibility retirement requires 7-14 clean operating days in `purchase_receipt_compatibility_events` after every receipt-capable workstation is updated. Any enforced-mode row proves that an old client still used direct invoice-status receiving; identify/update it and restart the window. The observer itself never changes invoice status, stock, movements, or journals. When the reviewed window is clean, set `legacy_untouched_compatibility=false` in one checked transaction; do not change `control_mode='enforce'`.

The 2026-07-12 gradual-receipt activation changed only its control row. The follow-up checkpoint-contract installation passed an authenticated rollback smoke proving exact stock/movement, full ordered phases, and an explicit zero-journal decision because purchase-invoice accounting already owns inventory value/AP/tax. Before and after: 1,654 products, 2,471 movements, 1,203 adjustments, 2,136 journals, 74 purchase invoices, zero professional receipts, and zero compatibility events. Stock-column drift, ledger arithmetic/continuity, current/latest drift, incomplete operations, and unbalanced journals were all zero.

The professional-correction contract view `professional_correction_trace_contract_view` exposes the first-occurrence phase sequence and expected sequence for every supplier/customer return, quarantine resolution, credit note, and cash refund. Reversal journal rows are classified as `journal_reversed`; physical-return value journals post before invariants. Production rollback smoke covered eight purchase/sales create/void operations, with eight complete contracts, zero unbalanced journals, exact restored stock, and no surviving test data.
