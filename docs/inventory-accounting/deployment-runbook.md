# Inventory and Accounting Release Runbook

**Release:** 2026-07-12 preventive kernel and inactive professional documents
**Rule:** schema installation, client distribution, tenant activation, and historical repair are four separate approvals.

Current Viñabike modes: workshop invoice ownership, purchase credit note, sales return, sales credit note, customer refund, and supplier refund `enforce`; purchase receipt `shadow` pending legacy-client observation.

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

The pre-release schema snapshot is `/tmp/bikeshop-erp-pre-inventory-release-20260711.sql` on the deployment workstation. No historical correction was executed.

## Release Gates

1. `bash scripts/reset_local_supabase.sh` must pass the clean canonical bootstrap and all pgTAP files.
2. `flutter test`, analyzer, and the ERP release web build must pass.
3. Confirm the production counts and five invariants above before and after every rollout step.
4. The verified web client was distributed on 2026-07-11. Distribute the matching desktop build before activation; previous clients remain compatible only while the receipt/return/credit controls are disabled.
5. Activate one tenant and one source family at a time. Record `activated_at` and `activated_by`; never activate all controls in one unobserved change.
6. Exercise create, retry, partial, void, insufficient-stock, and read-back trace cases with supervised business documents.
7. Observe operations, checkpoints, movement chains, settlement balances, and journals before expanding activation.

## Control Tables

- `purchase_receipt_control_settings`
- `purchase_receipt_compatibility_events` (append-only shadow evidence)
- `purchase_credit_note_control_settings`
- `sales_return_control_settings`
- `sales_credit_note_control_settings`
- `sales_customer_refund_control_settings`
- `purchase_supplier_refund_control_settings`

Allowed modes are `disabled`, `shadow`, and `enforce`. Absence of a row is disabled. Only `enforce` routes business posting to the new command.

## Safe Rollback

- Before any posted document: set the affected tenant control back to `disabled`; previous-client routing remains available.
- After a posted receipt/return/credit: do not delete tables, movements, operations, or journals. Void through its command, verify the linked reversal, then disable routing.
- For POS/Quick Sale client failure: roll the client back to the previous build. The additive database schema remains compatible; never remove a checkout that already committed.
- Posted invoices cannot be deleted. Draft deletion remains available; posted corrections use cancellation, return, credit note, payment reversal, or document void. Legacy journal replacement first writes immutable header-and-line evidence.
- For the sales negative-stock guard: investigate the rejected source. Do not disable it merely to force a sale; use a proven receipt or traced adjustment.
- Historical repair is never part of operational rollback. It requires a separately approved discrepancy register.

## Observation Queries

Use the read-only baseline scripts under `supabase/manual_checks/`, plus the production checks for dual-column drift, posting-ledger continuity, current-vs-latest ledger balance, negative tracked stock, unbalanced journals, failed/abandoned operations, and control/document counts. A changed business count must be explained by a named source operation.

Receipt enforcement additionally requires a clean, reviewed observation window in `purchase_receipt_compatibility_events`. Any row proves that a legacy client still uses direct invoice-status receiving; update that client and restart the window. The observer itself never changes invoice status, stock, movements, or journals.
