# Production Schema Drift Classification — 2026-07-12

**Safety:** read-only catalog and invariant queries. No production schema or data was changed.

## Verified relationship

- A fresh local database is created from `supabase/sql/core_schema.sql`.
- Lean staging received the canonical schema with unchanged tenant/product/invoice/movement/journal row counts.
- Local and staging application-owned catalogs have zero drift.
- Production contains historical module evolution that is not fully represented by the fresh canonical snapshot. The complete manifests/diffs remain ignored under `.tmp/db/`; no function bodies or business data are committed here.

## Raw production drift

| Component | Missing from production | Extra in production | Same identity, different definition |
|---|---:|---:|---:|
| Columns | 106 | 199 | 96 |
| Constraints | 47 | 109 | 24 |
| Functions | 3 | 34 | 126 |
| Indexes | 35 | 83 | 2 |
| Triggers | 1 | 16 | 0 |
| Views | 0 | 0 | 2 |

The totals include HR, analytics, spreadsheets, website and other historical modules. They are not authorization to add/drop objects automatically.

## Critical-kernel interpretation

- Core invoice status orchestrators, operation/checkpoint trace objects, payment math and movement evidence objects exist in production.
- Several production-only compatibility triggers are superseded by newer traced canonical behavior. Example: direct one-column product stock writes are now synchronized, validated, traced and journaled by the tested direct-stock writer rather than blindly copying the old trigger into staging.
- Some active production-only features still require deliberate canonicalization, including set-inventory synchronization and historical workshop labor helpers.
- `products_with_sets` differed because its original `p.*` view was created before later product columns. Migration `20260712210000_stabilize_products_with_sets_view.sql` fixes first-pass/idempotent shape locally and on staging; production promotion remains a normal reviewed release.
- `stock_movements_audit_view` differs only in selected legacy adjustment-column ordering in the inspected definition; its current integrity checks return no recent errors.

## Production invariant snapshot

At the 2026-07-12 read-only check:

- dual tracked-stock column mismatches: **0**;
- sales payment/balance mismatches: **0**;
- purchase payment/balance mismatches: **0**;
- unbalanced journal headers: **0**;
- journal header/line mismatches: **0**;
- recent stock arithmetic/ledger-source errors: **0**;
- trace operations stuck for more than five minutes: **0**;
- surfaced inventory/accounting inconsistencies: **0**.

Twenty products have negative stock. Their current quantities equal the latest reconstructed ledger balance, each has zero movement-integrity errors, and their last movements predate the new negative-stock guard. They are real historical shortages/oversells requiring operational review, not safe automatic-repair candidates.

## Rule for remaining reconciliation

Prioritize the inventory/accounting kernel. For each production-only or changed critical object: identify consumers and replacement, compare definitions, reproduce behavior locally, add a focused contract, prove on staging, then either canonicalize it or record why it is a retained legacy compatibility object. Never bulk-replace production from the raw manifest.
