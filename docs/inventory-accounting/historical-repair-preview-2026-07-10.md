# Historical Inventory and Payment Repair Preview — 2026-07-10

**Mode:** Read-only production inspection. No historical row, stock balance, invoice, payment, or journal was changed.

## Decision Summary

The migrations deployed on 2026-07-10 prevent and trace new invoice/payment/manual-adjustment inconsistencies. They do not silently rewrite legacy data.

The current historical candidate set is not safe for automatic execution yet:

| Finding | Evidence | Candidate repair | Gate |
|---|---:|---|---|
| Purchase reversal/manual-adjustment collisions | 92 distinct adjustments, 20 invoices, 77 products | Preserve legacy rows; add traced compensating movements only after product-level review | Physical-count or independent source-document confirmation |
| Negative collision rows | 91 rows, net `-223` units | Candidate `+223` units | Review all 77 affected products |
| Anomalous positive collision | 1 row, `+12` units | Do not include automatically | Manual review required |
| Duplicate purchase-payment journals | 2 payments | Post traced reversals for the proven duplicate entries; do not delete evidence | Confirm which posting is canonical |
| Missing purchase-payment journal | 1 payment | Create one traced journal from the preserved payment snapshot | Confirm payment-method account |
| Current linked job + invoice double-OUT overlap | 0 rows | No historical correction proposed | Still redesign ownership before certifying this source |

The net of all 92 colliding adjustments is `-211` units, but applying `+211` blindly would be unsafe because it mixes 91 negative rows with one materially different positive row.

## Ambiguous Inventory Row

Invoice `AE090625`, SKU `AE0292`, contains this sequence:

- purchase receipt `+4`;
- purchase reversal `-4`;
- same-transaction generic manual adjustment `+12`, claiming stock `-12 -> 0`;
- purchase receipt `+4` again.

Current recorded stock is `7`. Reversing the `+12` mechanically would produce `-5`, so this row requires a physical count and cannot be part of an automatic repair batch.

None of the 92 colliding legacy adjustments has a journal linked with `source_module = 'stock_adjustment'`. Therefore, any quantity correction must not automatically create new adjustment income/expense accounting without separately proving the inventory general-ledger effect.

## Payment Journal Cases

| Invoice | Payment | Amount (CLP) | Finding | Preserved evidence |
|---|---|---:|---|---|
| `138518` | `bebaa30b-445c-46e0-8fa4-23a47b02db2a` | 144,725 | Two journals | `AS-00147`, `AS-00148` |
| `AE010625` | `65c143a5-c990-452c-b5d6-e0103d5bdb87` | 47,135 | Two journals | `AC-01320`, `AC-01321` |
| `FC-00015` | `c9eb167e-b19f-4f58-ac50-7ca596df8d8d` | 14,900 | No recognized journal | Payment row remains active |

The repair must use reversal/creation entries linked to a `historical_repair` operation. It must not hard-delete the duplicate journals.

## Execution Gate

Before any historical mutation:

1. freeze the candidate IDs and current product balances;
2. confirm physical/source-document quantities for every affected product, especially SKU `AE0292`;
3. confirm the canonical journal in each duplicate pair and the payment-method account for `FC-00015`;
4. preview exact stock and journal rows with operation/checkpoint IDs;
5. take a fresh backup, execute one repair family, and rerun the full before/after audit.

The executable read-only evidence queries are:

- `supabase/manual_checks/inventory_accounting_historical_repair_preview.sql`
- `supabase/manual_checks/inventory_accounting_historical_repair_summary.sql`
