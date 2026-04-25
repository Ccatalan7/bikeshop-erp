# Egress Optimization Handoff - 2026-04-23

## Objective
Reduce Supabase egress and startup latency by replacing broad list reads with preview-first queries, paged loading, and targeted detail hydration.

## Completed Implementation

### 1) Customer preview payload improvements
- Added auth_user_id to the customer preview projection so preview-only surfaces still have user linkage data.
- File touched:
  - lib/modules/crm/models/crm_models.dart

### 2) Messaging dialog moved off broad customer reads
- Updated new chat dialog to use preview customer loading path instead of broad getCustomers startup reads.
- Hardened async usage around context/service access in this flow.
- File touched:
  - lib/modules/messaging/widgets/new_chat_dialog.dart

### 3) Inventory preview paging + empty query guard
- Fixed empty search behavior to avoid escalating into full catalog loads.
- Added preview page loading support and state for lightweight product lists.
- Files touched:
  - lib/shared/services/inventory_service.dart
  - lib/shared/models/product.dart

### 4) Paginated DB helper now supports narrow projections
- Extended selectWithPagination to accept selectColumns so paged reads can stay preview-sized.
- File touched:
  - lib/shared/services/database_service.dart

### 5) POS startup optimization
- Replaced eager startup loads with preview-first product/customer behavior.
- Product grid uses paged preview loading.
- Cold-cache search uses debounced server search.
- Pending invoice list uses preview/detail split.
- Files touched:
  - lib/modules/pos/pages/pos_dashboard_page.dart
  - lib/modules/pos/pages/pos_payment_page.dart
  - lib/modules/sales/services/sales_service.dart

### 6) Mechanic job form customer selector optimization
- Customer selector now runs on preview customer cache + local filtering pattern.
- File touched:
  - lib/modules/bikeshop/pages/mechanic_job_form_page.dart

### 7) Sales invoice startup refactor (page + editor)
- Startup moved to preview-first customer and product loading.
- Existing invoice open path now hydrates only missing products by id.
- Barcode fallback path adjusted to avoid requiring full in-memory catalog.
- Structural and nullability issues introduced during refactor were repaired.
- Files touched:
  - lib/modules/sales/pages/invoice_form_page.dart
  - lib/modules/sales/widgets/sales_invoice_editor.dart

### 8) Asset restoration
- Restored missing diagnostics background asset in expected location.
- File touched:
  - assets/images/paseo_diagnostic_bg.png

### 9) Purchase, quick sale, workshop, and purchase PDF follow-through
- Purchase invoice form now starts from supplier + product preview rows, hydrates existing/OCR product IDs directly, and barcode/OCR lookup avoids full catalog loading.
- Quick sale barcode/payment flow no longer triggers broad product refreshes.
- Workshop customer-heavy views now use customer list previews instead of broad customer reads.
- Purchase invoice PDF generation hydrates only the products referenced by the invoice.
- Files touched:
  - lib/modules/purchases/pages/purchase_invoice_form_page.dart
  - lib/modules/purchases/pages/purchase_invoice_list_page.dart
  - lib/shared/widgets/quick_sale_panel.dart
  - lib/shared/widgets/quick_bike_finder_panel.dart
  - lib/modules/crm/pages/customer_bike_directory_page.dart
  - lib/modules/bikeshop/pages/clients_list_page.dart
  - lib/modules/bikeshop/pages/pegas_list_page.dart
  - lib/modules/bikeshop/pages/pegas_table_page.dart
  - lib/modules/bikeshop/widgets/pegas_calendar_widget.dart
  - lib/shared/widgets/ocr_upload_widget.dart

### 10) Narrower search and targeted hydration payloads
- Database search helpers now support `selectColumns`, so customer/product picker searches can request preview payloads instead of full rows.
- Customer search now uses the customer list preview projection.
- Product keyword search and exact product lookups now use the product preview projection.
- Product stock adjustments now refresh only the adjusted product row instead of reloading the full catalog.
- Sales invoice direct product hydration and mechanic package product lookups now use narrow product projections.
- Files touched:
  - lib/shared/services/database_service.dart
  - lib/modules/crm/services/customer_service.dart
  - lib/shared/services/inventory_service.dart
  - lib/modules/sales/pages/invoice_form_page.dart
  - lib/modules/sales/widgets/sales_invoice_editor.dart
  - lib/modules/bikeshop/services/bikeshop_service.dart

### 11) Public storefront product/catalog egress hardening
- Added tenant-scoped public product RPCs for paged product lists, fuzzy search, featured products, and category counts.
- Public storefront product RPCs return storefront-safe product columns and zero out purchase cost.
- Product catalog now loads one server-side page at a time instead of downloading the full public catalog and filtering locally.
- Category counts now come from a compact count RPC instead of requiring a full product list.
- Product detail, SKU lookup, related products, and featured products now use public storefront RPC paths.
- Public storefront preview projection no longer includes product cost; `Product.fromJson` tolerates missing cost for public payloads.
- Existing journal header totals for sales invoices were backfilled from balanced journal lines, and a trigger now keeps future journal header totals aligned with line totals.
- Public product policies were tightened to require active + published + website-visible products.
- Important production-safety note: old direct public table access was not fully removed yet, because the currently deployed frontend may still depend on it. After the updated frontend is deployed, the next DB hardening step should drop the compatibility public products table policies and rely on the storefront RPCs.
- Files touched:
  - lib/public_store/pages/product_catalog_page.dart
  - lib/public_store/services/public_inventory_service.dart
  - lib/public_store/pages/public_home_page_old.dart
  - lib/modules/website/widgets/canvas_block.dart
  - lib/modules/website/services/website_service.dart
  - lib/shared/models/product.dart
  - supabase/migrations/20260424114500_harden_public_products_and_accounting_refs.sql
  - supabase/migrations/20260424115500_backfill_sales_invoice_journal_totals.sql
  - supabase/migrations/20260424120500_add_public_store_product_rpcs.sql

### 12) Label printer and AI product search egress follow-through
- Added a bounded product preview search path to the module inventory service.
- Replaced the old `getProducts(searchTerm: ...)` hot paths that fetched all product rows before filtering.
- Label printer product search now uses the bounded preview search and debounces typing.
- AI stock keyword lookup now uses bounded preview search for each keyword query.
- Public website product blocks now consistently require published products in public render mode, while preserving editor preview behavior for selected draft items.
- Product block parsing now preserves `product_type` and `is_published` from the product payload.
- Files touched:
  - lib/modules/inventory/services/inventory_service.dart
  - lib/modules/label_printer/label_printer_page.dart
  - lib/modules/ai_assistant/services/ai_service.dart
  - lib/modules/website/widgets/website_block_renderer.dart
  - lib/public_store/widgets/editable_website.dart

## Current Runtime/Analyzer Status
- 2026-04-24 update:
  - Focused analyze passed for the modified storefront/product/website files.
  - Focused analyze also passed after the label printer + AI product search follow-through.
  - Full `/Users/Claudio/flutter/bin/flutter analyze` runs now, but still reports the repo's existing 1009 info/warning diagnostics outside this slice.
  - Live DB smoke checks passed: public product RPC returns paged rows with `cost = 0`, category counts match the public in-stock total, and journal header/line total mismatches are now 0.
- Flutter wrapper note:
  - Earlier runs in the sandbox could not complete because the SDK wrapper tried to write `/Users/Claudio/flutter/bin/cache/engine.stamp` or `lockfile`.
  - As of 2026-04-24, `/Users/Claudio/flutter/bin/flutter analyze` does run in this workspace, but the full repo still has many pre-existing diagnostics.
  - Direct Dart fallback used:
    - `HOME=$PWD/.codex-home DART_SUPPRESS_ANALYTICS=true /Users/Claudio/flutter/bin/cache/dart-sdk/bin/dart analyze ...`
- Latest focused direct-Dart analyze results:
  - `lib/shared/services/database_service.dart lib/modules/crm/services/customer_service.dart lib/shared/services/inventory_service.dart`: no issues.
  - `lib/shared/services/database_service.dart lib/shared/services/inventory_service.dart lib/modules/sales/widgets/sales_invoice_editor.dart lib/modules/sales/pages/invoice_form_page.dart lib/modules/bikeshop/services/bikeshop_service.dart`: exit 0 with info-level pre-existing lints only.
- Known remaining info-level diagnostics:
  - `use_build_context_synchronously` in sales invoice page/editor.
  - `curly_braces_in_flow_control_structures` in bikeshop service.

## Known Gotchas to Preserve
- Broad customer trap:
  - Some getCustomers paths can become effectively full-table reads on empty search/startup.
- Broad product trap:
  - Empty query product fallback can unintentionally hydrate the full catalog if not explicitly bounded.
- Safe continuation pattern:
  - Preview projection
  - Paged preview loading
  - Targeted hydration by id only when needed

## Recommended Next Small Slices
1. Apply the same preview/search pattern to remaining high-traffic module-inventory consumers, especially label printer and AI assistant keyword inventory search.
2. Decide whether admin/cleanup tools should remain full-table scans or gain explicit date/filter-backed queries.
3. Keep broad full-catalog admin pages lower priority unless query instrumentation shows they are hot.

## Verification Checklist For Next Agent
1. Run focused analyze on each touched file before and after changes.
2. Open invoice create flow and confirm fast selector readiness without full-load pause.
3. Open existing invoice with products outside preview cache and confirm missing rows hydrate by id correctly.
4. Validate barcode add flow in both invoice page and invoice editor.
5. Open POS cold and verify product preview paging works and startup remains responsive.
6. Watch query instrumentation gauge for broad read spikes during these flows.
7. Re-scan broad load call sites and pick the next smallest high-impact slice.

## Working Style Requested By User
- Keep changes small, localized, and practical.
- Do not over-engineer or redesign broad architecture in this pass.
- Preserve behavior while reducing payload width and startup egress.
