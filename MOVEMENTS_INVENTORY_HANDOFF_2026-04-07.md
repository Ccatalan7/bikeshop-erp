# Movements / Inventory Tracking Handoff - 2026-04-07

## Scope

This handoff covers:

- the stock movements / inventory tracking refactor context leading into today
- the production investigation and cleanup work performed on 2026-04-07
- the database migrations and app-layer changes created today
- what is confirmed fixed
- what remains suspicious or worth further investigation
- the exact gotchas encountered during cleanup

Primary tenant investigated throughout: `5443b130-cc28-45af-a420-cd500b288890` (Viñabike production).

## Executive Summary

There were two distinct phantom-manual-adjustment classes contaminating `stock_adjustments` / `stock_movements`:

1. **Sales-invoice trigger leak**
   - Editing an already-posted sales invoice could recreate inventory side effects and generate bogus manual adjustments near real `sales_invoice:*` OUT movements.
   - These rows were audit noise only. They did **not** require product stock reversal because the real inventory mutation belonged to the sales flow itself.

2. **Standalone product-form sync noise caused by `inventory_qty` / `stock_quantity` drift**
   - Legacy drift between the two product stock columns meant a plain product save could look like a stock change to `track_product_stock_changes()`.
   - This emitted fake manual adjustments and fake manual stock movements.
   - The forward fix was applied in SQL and in app code so both columns are now kept in sync more consistently.

After retroactive cleanup of those two classes, a final audit of surviving manual adjustments found:

- **124 rows** created by `vinabikechile@gmail.com` that look like real operator stock corrections and were intentionally kept.
- **26 rows** with `created_by IS NULL` that were anomalous.

Those 26 rows were then cleaned. Their stock deltas were reversed on `products`, the paired movement rows were deleted, and the bad adjustment rows were deleted.

One cleanup gotcha occurred: the first version of the null-user cleanup updated `products`, which caused `trg_track_product_stock_changes` to emit new manual rows for the reversal itself. Those new rows were later cleaned by an ad hoc orphan movement delete query, and the migration file was corrected to disable the trigger around the reversal update.

## Current State

### Confirmed good

- The two known phantom classes have been retroactively cleaned.
- The null-user anomaly bucket has been cleaned.
- Latest verification observed during the session:
  - `remaining_null_user_adjustments = 0`
  - `orphaned_manual_movements = 0`
  - `stock_column_drift_rows = 0`
- After the ad hoc orphan cleanup query, `orphaned_remaining = 0`.
- The surviving **124 manual adjustments** are currently treated as legitimate admin corrections.

### Important nuance

The stock movements screen may still show manual adjustments after cleanup. That is **not automatically a bug** now, because the audit concluded that 124 remaining rows are genuine operator-created adjustments. Any screen still showing manual entries must be correlated against DB rows before assuming the cleanup failed.

## Main Findings / Root Causes

### 1. Sales invoice posted->posted edit side effect

Root cause pattern:

- posted sales invoice edited
- inventory side effects replayed or restored incorrectly
- real sale movement existed (`reference like 'sales_invoice:%'`, `type = 'OUT'`)
- a bogus manual adjustment and a synced manual movement appeared nearby in time

This class was identified by proximity to real sales OUT rows for the same product within 30 seconds.

### 2. Product form save drift between `inventory_qty` and `stock_quantity`

Root cause pattern:

- `products.inventory_qty` and `products.stock_quantity` were not always equal
- a product save could rewrite both columns consistently
- `track_product_stock_changes()` used the stale `OLD.stock_quantity` / `NEW.stock_quantity` delta as if it were a real stock edit
- fake `stock_adjustments` rows were created with reason `Manual adjustment via product form` or `Ajuste Manual`
- corresponding fake manual rows were synced into `stock_movements`

Forward fix:

- if legacy column drift existed and the save merely rewrote both columns to the same real value, the trigger now measures from the correct baseline
- if the effective delta is `0`, the trigger returns early and emits nothing

### 3. Null-user anomaly bucket

After removing the two known phantom classes, 26 suspicious rows remained with `created_by IS NULL`.

They split into three sub-buckets:

1. **2025-12-09 batch (13 rows)**
   - included service / non-stock products
   - definitively bogus because `track_product_stock_changes()` explicitly skips service or `track_stock = false`

2. **2026-01-16 batch family (9 rows)**
   - null creator
   - massive resets like `100 -> 1`, `-99`, `-297`
   - looked like script / migration damage rather than operator activity

3. **2026-02-13 batch (4 rows)**
   - null creator
   - small physical deltas
   - borderline, but included in cleanup per explicit operator approval during session

## What Was Already in Flight Before Today

This is the broader refactor context that predates the final audit/cleanup steps today:

- stock movement rendering bug fix where UI needed async product lookup handled safely
- purchase invoice detail UI improvement
- typed movement refactor introducing stronger movement categorization / view mode concepts
- "Últimos" ordering fix so latest movements are actually ordered correctly
- stock movement references / view tuning work in SQL

Relevant earlier movement-related migrations already present in the repo:

- `supabase/migrations/20260407123000_fix_stock_movements_view_ordering.sql`
- `supabase/migrations/20260407_fix_stock_movements_view_references.sql`
- `supabase/migrations/20260407_inspect_stock_movements_predeploy.sql`
- `supabase/migrations/20260407_stamp_sales_invoice_sources.sql`

## What Was Implemented Today

### A. Production SQL investigation / cleanup workflow

The following migrations were created during today’s investigation.

#### Sales-invoice phantom investigation and cleanup

- `supabase/migrations/20260407134500_audit_suspicious_sales_invoice_manual_adjustments.sql`
  - broadened suspicious-manual detection to include both known labels:
    - `Manual adjustment via product form`
    - `Ajuste Manual`

- `supabase/migrations/20260407135500_inspect_sales_invoice_inventory_bug.sql`
  - inspection queries for the sales-invoice-trigger leak

- `supabase/migrations/20260407143000_cleanup_confirmed_sales_invoice_manual_adjustment_noise.sql`
  - cleanup for a first confirmed invoice subset

- `supabase/migrations/20260407144000_preview_sales_invoice_manual_adjustment_cleanup_scope.sql`
  - read-only preview of the broader sales-linked cleanup scope

- `supabase/migrations/20260407145000_cleanup_historical_sales_invoice_manual_adjustment_noise.sql`
  - cleanup for the broader confirmed historical invoice set

- `supabase/migrations/20260407145500_verify_historical_sales_invoice_manual_adjustment_cleanup.sql`
  - post-cleanup verifier

#### Product-form sync-noise forward fix and retroactive cleanup

- `supabase/migrations/20260407150000_fix_product_form_sync_manual_adjustment_noise.sql`
  - **forward fix** to `track_product_stock_changes()`
  - also cleaned a small exact-ID set of already-confirmed phantom rows

- `supabase/migrations/20260407151000_cleanup_remaining_product_form_sync_noise.sql`
  - cleaned a second exact-ID set

- `supabase/migrations/20260407151500_verify_remaining_product_form_sync_noise_cleanup.sql`
  - verifier for that second exact-ID cleanup

- `supabase/migrations/20260407152000_preview_retroactive_product_form_sync_noise.sql`
  - read-only whole-history anomaly detector for standalone product-form sync noise

- `supabase/migrations/20260407153000_preview_retroactive_product_form_sync_noise_classified.sql`
  - classified candidate rows into:
    - `high_confidence_non_stock`
    - `high_confidence_negative_to_zero`
    - `review_needed`

- `supabase/migrations/20260407153500_cleanup_retroactive_product_form_sync_noise_high_confidence.sql`
  - removed the high-confidence classes

- `supabase/migrations/20260407154000_verify_retroactive_product_form_sync_noise_high_confidence_cleanup.sql`
  - verifier after high-confidence cleanup

- `supabase/migrations/20260407154500_preview_review_needed_product_form_sync_noise.sql`
  - detailed review-only inspection of the remaining ambiguous rows

- `supabase/migrations/20260407155000_cleanup_retroactive_product_form_sync_noise_remaining_review_batches.sql`
  - removed the remaining rows from the anomaly batches after manual review

- `supabase/migrations/20260407155500_verify_retroactive_product_form_sync_noise_fully_cleared.sql`
  - final verifier for that whole product-form sync-noise class
  - during session this verifier reportedly returned effectively “no rows”, i.e. the anomaly-batch detector cleared

#### Final surviving-manual-adjustment audit and null-user cleanup

- `supabase/migrations/20260407160000_audit_real_manual_adjustments.sql`
  - read-only audit that excludes the two cleaned phantom classes and shows what remains

- `supabase/migrations/20260407161000_cleanup_null_user_manual_adjustment_anomalies.sql`
  - cleanup for the 26 null-user anomaly rows
  - reverses stock on `products`
  - deletes paired manual movement rows
  - deletes the bad adjustment rows
  - current file version disables `trg_track_product_stock_changes` during the reversal update to avoid recreating noise

### B. Database trigger fix in source of truth

`supabase/sql/core_schema.sql`

`track_product_stock_changes()` was updated so that:

- service and non-stock-tracked products still return early
- when old columns had drifted, a save that rewrites both columns consistently uses the real stock baseline
- pure resyncs with effective delta `0` emit no manual adjustment
- inserted manual rows use the computed effective delta / before / after values instead of blindly using `OLD.stock_quantity` / `NEW.stock_quantity`

This is the core forward fix for the product-form sync phantom class.

### C. App-layer column-sync hardening

These app files were changed so product stock writes update **both** stock columns together:

- `lib/modules/inventory/models/inventory_models.dart`
  - reads `stock_quantity` first, then falls back to `inventory_qty`

- `lib/modules/inventory/services/inventory_service.dart`
  - updates both `inventory_qty` and `stock_quantity`

- `lib/shared/services/database_service.dart`
  - updates both stock columns in product stock operations

- `lib/modules/settings/services/factory_reset_service.dart`
  - resets both stock columns together

This is important because the DB trigger fix helps, but preventing drift at the app layer is the real long-term defense.

### D. Other non-movements code changes made in the same working period

These are not part of the stock-movements cleanup, but they were also changed today and should be part of the session handoff:

- `lib/modules/sales/services/sales_service.dart`
  - added `triggerLinkedJobSync(invoiceId)` to explicitly run invoice->job sync RPCs after linking a mechanic job to an invoice

- `lib/modules/sales/pages/invoice_form_page.dart`
  - improved preferred-bike inference / pre-assignment for invoice lines
  - calls the new job-sync trigger after writing `mechanic_jobs.invoice_id`

- `lib/modules/sales/widgets/sales_invoice_editor.dart`
  - same preferred-bike behavior and explicit invoice->job sync logic in the editor path

## What Was Actually Observed in Production Today

### Final manual-adjustment audit result

From the post-cleanup audit:

- total surviving manual-adjustment rows: **150**
- all under reason `Manual adjustment via product form`
- total quantity delta reported in that audit: **-1632**

Breakdown by creator:

- **124 rows** by `vinabikechile@gmail.com`
  - treated as legitimate manual corrections
- **26 rows** with `created_by IS NULL`
  - treated as anomalous and cleaned

### Classification of the 26 null-user rows

Confirmed during the session:

- `2025-12-09`: 13 rows, 10 service/non-stock rows -> definitively bogus
- `2026-01-16`: 9 rows, massive resets -> anomalous script/migration-like behavior
- `2026-02-13`: 4 rows, small physical deltas -> borderline, but removed by operator decision

### Cleanup verification results observed

After running the null-user cleanup migration:

```json
[
  {
    "remaining_null_user_adjustments": 0,
    "orphaned_manual_movements": 0,
    "stock_column_drift_rows": 0
  }
]
```

Then an additional ad hoc orphan cleanup query was run because the first execution of the migration had created new reversal rows through the stock-tracking trigger. The ad hoc verifier returned:

```json
[
  {
    "orphaned_remaining": 0
  }
]
```

## Very Important Gotcha Encountered Today

### Trigger recursion / self-generated cleanup noise

Problem encountered:

- `20260407161000_cleanup_null_user_manual_adjustment_anomalies.sql` initially reversed product stock with a plain `UPDATE public.products`
- that update fired `trg_track_product_stock_changes`
- the trigger created new manual adjustments for the reversal itself
- those new rows then created new manual `stock_movements`
- later deletion of the original adjustment rows left orphaned movement rows visible in the stock movements screen

What was done:

- an ad hoc SQL query deleted orphaned manual movement rows where no matching manual adjustment existed by `(tenant_id, product_id, created_at)`
- the migration file was then corrected to:
  - `disable trigger trg_track_product_stock_changes`
  - perform the reversal update
  - `enable trigger trg_track_product_stock_changes`

Operational implication:

- if this migration is ever rerun on another environment, use the **current** file version, not the earlier version that lacked trigger disabling

## What Is Confirmed Safe vs What Needs Caution

### Confirmed safe assumptions

- deleting the sales-linked phantom rows did **not** require product stock reversal
  - those rows were duplicate audit artifacts near real sales inventory movements

- deleting the earlier product-form sync-noise rows did **not** require product stock reversal
  - those rows documented sync noise from column drift rather than an incorrect final stock value

- deleting the **null-user** anomalies **did** require product stock reversal
  - especially the `2026-01-16` batch that looked like bogus bulk resets

### Caution

- do not assume that any manual movement still visible in the UI is wrong
  - the DB audit concluded 124 remaining rows look legitimate
- do not run stock-correction cleanups by updating `products` directly unless the stock-adjustment trigger is disabled or explicitly bypassed
- do not touch only `inventory_qty` going forward
  - always update `inventory_qty` and `stock_quantity` together

## Remaining Suspicious / Open Questions

### 1. Stock movements screen still showing manual rows after cleanup

This was reported visually after cleanup. There are several possible explanations:

1. the screen is showing the **legitimate remaining 124 admin-created manual rows**
2. the screen cached data and needs a hard refresh / app restart
3. there are still UI-level ordering/filtering issues causing confusing presentation
4. there are additional non-null-user movement rows that were never intended to be cleaned because they were judged real

This was **not conclusively resolved** during the session.

Recommended next check:

- take the top rows from the UI (timestamp + product name + delta)
- query DB directly against `stock_movements` and matching `stock_adjustments`
- verify whether those rows belong to the 124 legitimate manual corrections or are something else

### 2. Posted->posted journal entry recreation issue is still not fixed

This remains outstanding from the wider sales incident thread.

Inventory-side cleanup and movement cleanup were addressed, but the summary from the prior conversation explicitly noted:

- **posted->posted journal entry recreation still not fixed**

This should be treated as a separate unresolved accounting/business-logic issue.

### 3. Need to verify that the deployed DB function matches the edited source-of-truth SQL

`supabase/sql/core_schema.sql` was updated, but the next machine should confirm whether the production database function definition already matches that exact logic, especially if any manual SQL editor runs happened out of order.

### 4. Need to confirm no remaining historical anomaly classes outside the two known phantom classes plus null-user batch

Today’s audit concluded the remaining 124 rows were legitimate, but if more suspicious patterns emerge later, the safe approach is:

- start from read-only SQL
- inspect chronology by `created_at`
- correlate with `stock_movements`, `sales_invoices`, `products`, and creator identity
- avoid immediate delete/reversal scripts until the root cause is clear

## Recommended Next Steps On The Other Machine

### Highest priority

1. **Verify the stock movements UI rows you still distrust**
   - identify 3 to 5 top rows from the UI
   - query them directly in DB by product/timestamp
   - determine whether they map to the known-good 124 admin adjustments

2. **Check current production definition of `track_product_stock_changes()`**
   - ensure it matches the fixed logic from `20260407150000_fix_product_form_sync_manual_adjustment_noise.sql` / `core_schema.sql`

3. **Treat the journal-entry issue as separate work**
   - do not assume inventory cleanup solved the accounting side

### Good follow-up hardening

1. add a safer stock-correction utility path that bypasses the stock-adjustment trigger intentionally when doing forensic cleanup reversals
2. consider adding a DB-side helper / session flag for maintenance reversals instead of manual trigger disable/enable
3. if the movements page still feels confusing, inspect view/service ordering and caching from UI to DB

## Suggested Read-Only Query For The Next Session

Use this if the UI still shows manual rows you do not trust. Replace timestamp / product name filters from the screenshot you are investigating.

```sql
select
  sm.created_at,
  p.name as product_name,
  p.sku,
  sm.type,
  sm.movement_type,
  sm.quantity as movement_qty,
  sm.reference,
  sm.notes,
  sa.id as adjustment_id,
  sa.quantity as adjustment_qty,
  sa.stock_before,
  sa.stock_after,
  sa.reason,
  au.email as created_by_email
from public.stock_movements sm
left join public.products p
  on p.id = sm.product_id
 and p.tenant_id = sm.tenant_id
left join public.stock_adjustments sa
  on sa.tenant_id = sm.tenant_id
 and sa.product_id = sm.product_id
 and sa.created_at = sm.created_at
 and sa.adjustment_type = 'manual'
left join auth.users au
  on au.id = sa.created_by
where sm.tenant_id = '5443b130-cc28-45af-a420-cd500b288890'
  and sm.movement_type = 'manual'
order by sm.created_at desc, p.name;
```

If the suspect rows have `created_by_email = vinabikechile@gmail.com`, they are very likely from the retained set of legitimate manual adjustments unless new contradictory evidence appears.

## Files Most Relevant To Open First On The Next Machine

Database / SQL:

- `supabase/sql/core_schema.sql`
- `supabase/migrations/20260407150000_fix_product_form_sync_manual_adjustment_noise.sql`
- `supabase/migrations/20260407155500_verify_retroactive_product_form_sync_noise_fully_cleared.sql`
- `supabase/migrations/20260407160000_audit_real_manual_adjustments.sql`
- `supabase/migrations/20260407161000_cleanup_null_user_manual_adjustment_anomalies.sql`

App layer:

- `lib/modules/inventory/models/inventory_models.dart`
- `lib/modules/inventory/services/inventory_service.dart`
- `lib/shared/services/database_service.dart`
- `lib/modules/settings/services/factory_reset_service.dart`

Other same-session but separate changes:

- `lib/modules/sales/services/sales_service.dart`
- `lib/modules/sales/pages/invoice_form_page.dart`
- `lib/modules/sales/widgets/sales_invoice_editor.dart`

## Testing / Validation Notes

- No full automated Flutter test pass was run as part of this handoff.
- The production verification relied primarily on SQL inspection and the user-reported SQL Editor outputs.
- The UI screenshot at the end indicates there is still perceived confusion in the stock movements screen, but that was not fully proven to be a DB integrity issue.

## Bottom Line

As of the end of this session:

- the known phantom adjustment classes were cleaned
- the null-user anomaly bucket was cleaned and its stock effect was reversed
- stock column drift was cleared
- the trigger gotcha in reversal cleanup was discovered and documented
- the strongest unresolved item is **not** the cleaned data itself, but whether the remaining manual rows visible in UI are simply the 124 legitimate admin corrections or a separate display/data issue
- the posted->posted journal-entry recreation issue still needs its own investigation/fix