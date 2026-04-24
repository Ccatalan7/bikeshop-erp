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

## Current Runtime/Analyzer Status
- Flutter wrapper note:
  - In the current sandbox, `/Users/Claudio/flutter/bin/flutter analyze` cannot complete because the SDK wrapper tries to write `/Users/Claudio/flutter/bin/cache/engine.stamp` or `lockfile`.
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
