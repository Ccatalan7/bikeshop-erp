# Handoff: Workshop Consumables Implementation

Date: 2026-04-01

## Scope

This handoff covers the workshop consumables implementation for purchases, product conversion, and sales behavior.

Business goal:
- Allow the same supplier invoice to contain both normal inventory items and workshop consumables.
- Keep normal inventory items as stock/assets.
- Send workshop consumables directly to expense with no stock recognition.
- Allow workshop consumables to be sold, but do it without creating fake stock movement or inventory-based COGS.

## Final Business Rules Implemented

### Purchase side

- `inventory`
  - Purchase increases stock.
  - Purchase debits inventory asset `1105`.
- `workshop_consumable`
  - Purchase does not increase stock.
  - Purchase debits workshop consumables account `5101`.

### Product behavior

- Products now have a default `purchase_treatment`.
- Services remain non-stock and force the non-stock behavior.
- Products marked as `workshop_consumable` are forced to:
  - `track_stock = false`
  - `inventory_qty = 0`
  - `stock_quantity = 0`
  - `min_stock_level = 0`
  - `max_stock_level = 0`

### Conversion behavior

- Existing stock-tracked inventory products can be converted to non-stock behavior through a guided conversion flow.
- Conversion does not silently destroy value.
- Existing stock is discharged and reclassified:
  - debit `5101 Consumibles de Taller`
  - credit `1105 Inventarios`

### Sales side

- Workshop consumables are allowed to be sold.
- Sale line keeps a snapshot of `purchase_treatment` on the invoice item.
- Selling a workshop consumable:
  - does not create stock movement
  - does not reduce stock
  - does not create `5100 Costo de Ventas`
  - does not create `1105 Inventarios` credit
  - does create the normal commercial sales entry:
    - debit `1130 Cuentas por Cobrar Comerciales`
    - credit `4100 Ingresos Operacionales`
    - plus IVA if applicable

## What Was Implemented

### Database / SQL

Canonical schema updates were made in:
- `supabase/sql/core_schema.sql`

Deployment migration was updated in:
- `supabase/migrations/20260401193000_purchase_treatment_workshop_consumables.sql`

Main database work completed:
- Added `products.purchase_treatment`.
- Added normalization/update logic for existing products.
- Added `sync_product_service_flags()` trigger logic.
- Added `convert_product_inventory_to_non_stock(...)` RPC.
- Added account bootstrap for `5101 Consumibles de Taller`.
- Updated `consume_purchase_invoice_inventory(...)`.
- Updated `restore_purchase_invoice_inventory(...)`.
- Updated `create_purchase_invoice_journal_entry(...)`.
- Updated `consume_sales_invoice_inventory(...)` to skip workshop consumables.
- Updated `create_sales_invoice_journal_entry(...)` to skip COGS/inventory legs for workshop consumables.

### Flutter / Dart

Main files updated:
- `lib/shared/models/product.dart`
- `lib/modules/inventory/models/inventory_models.dart`
- `lib/modules/inventory/pages/product_form_page.dart`
- `lib/modules/inventory/services/inventory_service.dart`
- `lib/modules/purchases/models/purchase_invoice.dart`
- `lib/modules/purchases/models/smart_purchase_list_item.dart`
- `lib/modules/purchases/pages/purchase_invoice_form_page.dart`
- `lib/modules/sales/models/sales_models.dart`
- `lib/modules/sales/pages/invoice_form_page.dart`
- `lib/modules/sales/widgets/sales_invoice_editor.dart`
- `lib/shared/widgets/quick_sale_panel.dart`
- `lib/modules/pos/services/pos_service.dart`

Main application work completed:
- Added `PurchaseTreatment` enum and DB-safe serialization/parsing.
- Added product-form control for default purchase treatment.
- Added purchase-line inheritance from selected product.
- Added purchase-line override support.
- Added guided conversion flow in product form.
- Added clearer accounting preview for conversion in Debe/Haber format.
- Updated smart purchase list parsing so joined product data can carry `purchase_treatment` safely into downstream purchase flows.
- Added sales line snapshot persistence for:
  - `purchase_treatment`
  - `is_service`
  - `cost`
- Updated alternative sales flows so they also send the same snapshot data.
- Refined inventory list behavior for workshop consumables so they no longer look like broken stock rows.

## Important Bugfixes Completed During Implementation

- Fixed enum serialization mismatch that caused:
  - `Invalid target purchase_treatment: workshopConsumable`
- Root cause was camelCase vs snake_case mismatch.
- Final DB wire values are stable:
  - `inventory`
  - `workshop_consumable`

## Session Update: 2026-04-02

This session focused on the smart purchase list handoff path, inventory list UX cleanup, and repeatable cleanup tooling for test invoices.

### Additional files added or updated

- `supabase/manual_checks/execute_cleanup_workshop_consumable_test_invoices.sql`
- `lib/modules/inventory/pages/product_list_page.dart`
- `lib/modules/purchases/models/smart_purchase_list_item.dart`

### Smart purchase list follow-up

- Audited purchase-side entry paths that build purchase invoice lines from smart purchase list items and ad-hoc fallback rows.
- Confirmed `purchase_treatment` now propagates through the smart purchase list model instead of getting lost when product join data is available.
- Fixed a Dart null-safety regression in `SmartPurchaseListItem.fromJson(...)` by giving the local `purchaseTreatment` variable a safe default (`PurchaseTreatment.inventory`) before nested product parsing.
- Verified the touched Dart files are analyzer-clean after the fix.

### Inventory UI follow-up

- Adjusted the inventory products list so workshop consumables no longer show a misleading numeric `0` stock state.
- Non-stock workshop consumables now render a compact inline `N/A` stock badge, aligned with the existing table language instead of introducing a large secondary chip in the row.
- Stock summary counters and stock filter subsets now ignore products that do not track inventory, so workshop consumables do not pollute low-stock or out-of-stock totals.
- Resulting UX intent: the row should read as a valid non-stock product, not as an inventory exception.

### Cleanup tooling follow-up

- Added an execute-ready cleanup SQL file for known workshop consumable verification prefixes:
  - sales: `TEST-WC-%`
  - purchases: `TEST-WCP-%`
- The cleanup script deletes matching test invoices for tenant `5443b130-cc28-45af-a420-cd500b288890` and reports remaining counts afterward.
- File:
  - `supabase/manual_checks/execute_cleanup_workshop_consumable_test_invoices.sql`

## Verified Results

### Product conversion verified in live DB

For product:
- `ca14c728-690d-4bee-9ffc-7aad041efb77`
- SKU `136`

Verified live state:
- `purchase_treatment = workshop_consumable`
- `track_stock = false`
- `inventory_qty = 0`
- `stock_quantity = 0`
- related conversion stock adjustment exists
- related conversion journal entry exists

### Sales workflow verified in live DB

Manual verification script:
- `supabase/manual_checks/verify_workshop_consumable_sale.sql`

The script was corrected to use multiple statements because the earlier one-statement version could produce false negatives for trigger-created journal entries.

Verified result for a real test sale:
- invoice created successfully
- invoice line snapshot stored `purchase_treatment = workshop_consumable`
- no stock movements created
- stock remained zero
- journal entry created successfully
- journal lines created:
  - `1130` debit
  - `4100` credit
- no `1105` credit line
- no `5100` debit line
- journal entry balanced

Conclusion:
- The intended “healthy sale” behavior for workshop consumables is working in the database.

## Manual Verification Assets

Useful file:
- `supabase/manual_checks/verify_workshop_consumable_sale.sql`
- `supabase/manual_checks/execute_cleanup_workshop_consumable_test_invoices.sql`

What it does:
- creates a test confirmed sales invoice for the workshop consumable
- checks stock movement absence
- checks stock stays at zero
- checks journal entry existence
- checks `1130` and `4100`
- checks absence of `1105` credit and `5100` debit

Cleanup helper:
- deletes workshop consumable verification invoices by known prefixes
- returns deleted sales and purchase invoices
- reports whether matching test invoices remain after cleanup

## What Is Still Left To Do

### High priority

- Delete old test invoices if they still exist in production.
- Re-run the manual verification script after any future sales/accounting trigger deployment touching `sales_invoices`.
- Verify the same behavior from the actual UI flows, not only SQL-level inserts:
  - main sales invoice form
  - quick sale panel
  - POS flow

### Medium priority

- Add automated regression coverage if the project has or will have test harness coverage for these flows.
- Add a dedicated manual verification script for purchase-side mixed invoices if repeatable QA is needed.
- Verify accounting reports that consume journal data still present the expected outcome for these consumable sales.

### Nice to have

- Add a second manual check script for the conversion RPC flow.
- Improve UI copy so users better understand the accounting consequence of changing a product from inventory to workshop consumable.

Completed from this list:
- Added a lightweight cleanup SQL file for workshop-consumable verification invoices by prefix.

## Known Notes / Risks

- This feature depends on line-level snapshot data being preserved in all sales entry points.
- If a future developer updates only one sales flow and forgets the others, behavior can diverge.
- The most important rule to preserve is:
  - workshop consumable sale lines must not generate stock movement
  - workshop consumable sale lines must not generate inventory-based COGS
- If future work touches `create_sales_invoice_journal_entry(...)` or `consume_sales_invoice_inventory(...)`, re-run the manual verification script immediately.

## Suggested Next Steps On Another Computer

### 1. Open these files first

- `WORKSHOP_CONSUMABLES_HANDOFF_2026-04-01.md`
- `supabase/manual_checks/verify_workshop_consumable_sale.sql`
- `supabase/manual_checks/execute_cleanup_workshop_consumable_test_invoices.sql`
- `supabase/migrations/20260401193000_purchase_treatment_workshop_consumables.sql`
- `supabase/sql/core_schema.sql`

### 2. Confirm deployed DB matches source of truth

- Compare `core_schema.sql` and the migration for:
  - `consume_purchase_invoice_inventory(...)`
  - `restore_purchase_invoice_inventory(...)`
  - `create_purchase_invoice_journal_entry(...)`
  - `convert_product_inventory_to_non_stock(...)`
  - `consume_sales_invoice_inventory(...)`
  - `create_sales_invoice_journal_entry(...)`

### 3. Run manual verification again before doing new changes

- Execute:
  - `supabase/manual_checks/verify_workshop_consumable_sale.sql`
- Confirm all booleans in `checks` are `true`.

### 4. If continuing development, preserve these invariants

- DB value format must remain snake_case.
- Product form, purchase invoice form, sales invoice form, quick sale panel, and POS must all agree on line payload shape.
- Workshop consumables must remain non-stock everywhere.
- Sales commercial accounting must still post normally.

### 5. If continuing QA, recommended checklist

- Create a mixed purchase invoice:
  - one inventory item
  - one workshop consumable
- Confirm:
  - only inventory line increases stock
  - purchase journal splits `1105` and `5101` correctly
- Convert an inventory product with stock to workshop consumable.
- Confirm:
  - stock discharged to zero
  - reclassification JE created
- Sell a workshop consumable from UI.
- Confirm:
  - no stock movement
  - no `1105` credit
  - no `5100` debit
  - yes `1130` and `4100`

## Suggested Cleanup SQL

Delete a specific test invoice:

```sql
delete from public.sales_invoices
where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'::uuid
  and invoice_number = 'PEGA_AQUI_EL_INVOICE_NUMBER';
```

Delete workshop-consumable verification invoices by prefix:

```sql
delete from public.sales_invoices
where tenant_id = '5443b130-cc28-45af-a420-cd500b288890'::uuid
  and invoice_number like 'TEST-WC-%';
```

## Final Status

Implementation status: substantially complete and manually verified in live DB.

Most important outcome:
- workshop consumables now behave correctly on purchases, product conversion, and sales, with accounting and stock behavior aligned to the intended ERP model.