# Stock Movement Evidence Standard

Deployed 2026-07-11. Historical evidence is classified, never deleted or silently rewritten.

Every movement detail must answer:

1. What source document/action caused it?
2. When was it effective, and when was it recorded?
3. What exact equation was applied: `stock before + actual delta = stock after`?
4. Is the balance persisted, sourced from an adjustment, or reconstructed?
5. What accounting value was posted? If no historical journal exists, current-cost valuation is explicitly labeled an estimate.
6. Is the row verified, reconstructed, arithmetically inconsistent, ambiguously linked, or part of a known legacy duplicate/collision?

The audit read model preserves `raw_quantity` and exposes `actual_stock_delta` and `reconciled_quantity`. Exact legacy purchase-reversal/manual-adjustment timestamp collisions remain visible, but the duplicate technical footprint is excluded from summary totals so one physical stock action is not counted twice.

Production activation checks:

- Raw movements: 2,474
- Audit rows: 2,474
- Duplicate movement IDs: 0
- Rollback-only future-adjustment smoke: exact source, employee actor, `6 → 7`, verified persisted balance, zero rows committed
- Inventory and accounting business totals unchanged by activation
