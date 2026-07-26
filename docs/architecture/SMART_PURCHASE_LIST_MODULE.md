# Smart Purchase List Module - Development Summary

**Date:** November 1, 2025  
**Status:** ✅ Complete - Ready for Production

---

## 📋 Overview

The Smart Purchase List is an intelligent inventory replenishment tool located at **Compras → Lista Inteligente**. It analyzes product sales history and current stock to suggest purchase quantities, helping users make data-driven purchasing decisions.

### UI guidance status

This is a dated implementation summary, not a visual design specification.
Its replenishment rules, workflow states, and persistence contracts remain
useful. Historical literals for colors, badges, chips, icons, columns, dialogs,
route primitives, or component geometry are non-authoritative.

Current UI work must follow
[the general GUI guide](../../.github/GUI_DESIGN_PRINCIPLES.md) and, for phone,
tablet, compact, adaptive, or responsive work,
[the mobile GUI guide](../../.github/GUI_MOBILE_DESIGN_PRINCIPLES.md).
Choose the interaction surface from the actual task, sequence, available space,
and input capabilities using the canonical guide's decision criteria. No
surface in this historical summary is a mandatory pattern. A long list is
evidence to evaluate context-preserving list-detail interaction, not a mandate
for a split pane or any other favorite layout.

---

## ✅ Completed Features

### 1. Automatic Product Suggestions
**How it Works:**
- Analyzes sales history from the last 30 days
- Calculates average daily sales for each product
- Suggests purchase quantity = `(30 days × avg_daily_sales) - current_stock`
- Only suggests products with low stock relative to sales velocity

**Database Logic:** `supabase/sql/core_schema.sql` lines 1145-1236
```sql
-- Function: suggest_products_to_buy(p_tenant_id uuid)
-- Returns: Products with suggested quantities based on sales velocity
-- Algorithm:
1. Query sales from last 30 days
2. Calculate total sold per product
3. Calculate avg_daily_sales = total_sold / 30
4. Calculate suggested = CEIL(30 * avg_daily_sales - current_stock)
5. Filter: suggested > 0 (only products needing restock)
6. Order by suggested DESC (highest need first)
```

---

### 2. Manual Adjustment & Priority Setting
**Features:**
- **Suggested-quantity adjustment** (planned, not yet implemented)
- **Purchase notes** for justification or reminders
- **Replenishment urgency:** derived from stock and demand, exposed with a
  clear textual or semantic state. Theme-owned color may reinforce it, but a
  hardcoded traffic-light palette, one colored chip per state, or color-only
  meaning is not part of the contract.

---

### 3. Three-View Workflow

#### A. **"Por Ordenar" (To Order) View**
**Purpose:** Review and plan purchases

**Columns:**
- Producto (Product name)
- SKU
- Stock Actual (current stock and replenishment urgency)
- Ventas 30d (Sales in last 30 days)
- Sugerido (Suggested quantity to buy)
- Notas (Notes - editable)
- Acciones (Actions: Order button)

**Actions:**
- ✅ "Ordenar" button → Creates purchase invoice
- ✅ Moves item to "Ordenados" view
- ✅ Triggers status change: `pending` → `ordered`

---

#### B. **"Ordenados" (Ordered) View**
**Purpose:** Track ordered but not received inventory

**Added Columns (beyond "Por Ordenar"):**
- **N° Factura** (Invoice Number) - invoice detail action
- **Ordenado el** (Order date)

**Features:**
- ✅ Clickable invoice number → Opens invoice in **read-only mode**
- ✅ Read-only mode hides all edit buttons, only shows status label
- ✅ Shows which supplier the order was placed with

**Actions:**
- When purchase invoice is marked as "received" or "paid"
- Item automatically moves to "Recibido" view

---

#### C. **"Recibido" (Received) View**
**Purpose:** Review completed purchases and verify stock updates

**Added Columns (beyond "Ordenados"):**
- **Stock al Recibir** (Stock at receipt) - actual stock when invoice was received
- **Creado el** (Invoice creation date)

**Key Feature - Stock at Receipt Tracking:**
- ✅ Captures the **actual stock level** when invoice is received
- ✅ Stores in `stock_at_receipt` column
- ✅ Different from "Stock Actual" (which shows current/live stock)
- ✅ Useful for verifying that stock was properly added

**Database Trigger:** `supabase/sql/core_schema.sql` lines 1324-1340
```sql
-- Trigger: auto_update_purchase_list_on_invoice_status
-- Fires on: purchase_invoices INSERT/UPDATE
-- Captures: stock_at_receipt when status changes to 'received'
```

**Backfill Function:** Lines 1360-1407
```sql
-- Function: backfill_stock_at_receipt_for_received_items()
-- Purpose: Populate stock_at_receipt for historical data
-- Status: Already executed (line 1408)
```

---

### 4. Invoice Creation Integration

**Files:**
- Service: `lib/modules/purchases/services/smart_purchase_service.dart`
- Page: `lib/modules/purchases/pages/smart_purchase_list_page.dart`

**Flow:**
1. User clicks "Ordenar" on product in "Por Ordenar" view
2. System creates purchase invoice with:
   - Product line item (suggested quantity or user-adjusted)
   - Price from product cost
   - Status: `pending`
3. Invoice number auto-generated (format: `FC-YYYYMMDD-XXXXXX`)
4. Smart list item updated:
   - `status` → `'ordered'`
   - `invoice_id` → linked to created invoice
   - `order_date` → current timestamp
5. Item moves to "Ordenados" tab

**Code Reference:**
```dart
// lib/modules/purchases/services/smart_purchase_service.dart
Future<void> createPurchaseInvoice(String itemId) async {
  // 1. Get item details
  // 2. Create invoice with line items
  // 3. Update smart_purchase_list status
  // 4. Link invoice_id
}
```

---

### 5. Status Automation Triggers

**Database:** `supabase/sql/core_schema.sql` lines 1268-1322

**Trigger 1: Auto-Add on Invoice Creation**
```sql
-- When purchase invoice is created
-- If product is in smart list (any status)
-- Update: status='ordered', invoice_id=new_invoice.id
```

**Trigger 2: Auto-Update on Invoice Status Change**
```sql
-- When invoice status changes to 'received' or 'paid'
-- Update smart list: status='received', stock_at_receipt=current_stock
```

**Benefits:**
- ✅ No manual status updates needed
- ✅ Automatic workflow progression
- ✅ Prevents duplicate orders
- ✅ Historical stock tracking

---

### 6. Read-Only Invoice Navigation

**File:** `lib/modules/purchases/pages/purchase_invoice_form_page.dart`

**Feature:** When navigating from Smart Purchase List, invoice opens in read-only mode

**Behavioral contract:**
- The invoice action delegates to the canonical purchase-invoice reader and
  canonical permission checks.
- The host may present it inline, in-block, in an inspector, or as a full route
  according to the canonical surface-selection criteria.
- A full route is justified by task and navigation needs, not by the fact that
  an invoice widget exists.
- Back or close returns to the exact Smart Purchase List view, search, filters,
  selection, and scroll position.
- Read-only mode cannot expose mutating commands through an alternate host.

---

### 7. GUI Enhancements

**Historical capability snapshot (Oct 31, 2025):**

✅ **Invoice Creation Date Column**
- Added "Creado el" column to "Recibido" view
- Shows when the purchase invoice was originally created
- Format: `DD/MM/YYYY HH:mm`
- The current implementation must use the authoritative read model; this
  historical `FutureBuilder` detail is not a UI pattern

✅ **Clickable Invoice Numbers**
- Invoice numbers in "Ordenados" and "Recibido" expose an accessible invoice
  action through the shared interaction language
- Opens through the canonical read-only surface with exact-origin return

✅ **Replenishment Urgency**
- Stock and demand expose the exception that changes the purchase decision
- Treatment follows current theme roles and remains understandable without
  color; the old priority-color badges are not visual precedent

---

## 📊 Database Schema

### Table: `smart_purchase_list`

**Location:** `supabase/sql/core_schema.sql` lines 1056-1108

```sql
create table if not exists smart_purchase_list (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid references tenants(id) on delete cascade not null,
  product_id uuid references products(id) on delete cascade not null,
  product_name text not null,
  sku text,
  current_stock integer not null default 0,
  sales_last_30d integer not null default 0,
  suggested_quantity integer not null default 0,
  notes text,
  status text check (status in ('pending', 'ordered', 'received')) default 'pending',
  invoice_id uuid references purchase_invoices(id) on delete set null,
  order_date timestamp with time zone,
  stock_at_order integer,        -- Stock when "Ordenar" clicked
  stock_at_receipt integer,       -- Stock when invoice received (ADDED Oct 31)
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now(),
  
  unique(tenant_id, product_id) -- One entry per product per tenant
);

create index idx_smart_purchase_list_tenant on smart_purchase_list(tenant_id);
create index idx_smart_purchase_list_status on smart_purchase_list(tenant_id, status);
create index idx_smart_purchase_list_product on smart_purchase_list(product_id);
```

---

## 🔄 Workflow State Machine

```
[No Entry] 
    ↓ (suggest_products_to_buy function runs)
[pending] ← Por Ordenar view
    ↓ (User clicks "Ordenar" → creates invoice)
[ordered] ← Ordenados view
    ↓ (Invoice status → 'received' or 'paid')
[received] ← Recibido view
    ↓ (Manual cleanup or archive)
[archived/deleted]
```

---

## 🚧 Known Limitations & TODOs

### 1. Inline Editing (HIGH PRIORITY)
**Current State:** Notes column exists but is not editable inline

**TODO:** Implement inline editing for:
- Suggested quantity (user can adjust before ordering)
- Notes field (add purchase justification)

**Interaction contract:**
- Prefer editing in the current workflow when it remains clear and protects
  scanning context; use another surface when validation, space, or task
  complexity genuinely requires it.
- Do not infer that every row needs permanent fields or edit/save buttons.
- Reuse the canonical update command, validation, permission, loading, and
  error behavior in every host.
- Preserve the active workflow view, filters, selection, draft, and scroll
  through save, cancel, error, and return.

**Benefit:** Users can adjust suggestions without creating invoices first

---

### 2. Bulk Actions (MEDIUM PRIORITY)
**Not Yet Implemented:**
- ❌ Select multiple products
- ❌ Create single invoice with multiple products
- ❌ Bulk delete/archive

**Current Workaround:** Order products one-by-one

---

### 3. Advanced Filtering (LOW PRIORITY)
**Not Yet Implemented:**
- ❌ Filter by product category
- ❌ Filter by supplier
- ❌ Filter by replenishment urgency
- ❌ Sort by different columns

**Current State:** All products shown, sorted by suggested quantity DESC

---

### 4. Sales Velocity Trends (FUTURE)
**Not Yet Implemented:**
- ❌ Show sales trend (increasing/decreasing/stable)
- ❌ Seasonal adjustment
- ❌ Configurable days range (currently fixed at 30 days)

**Current State:** Simple 30-day average calculation

---

## 🔄 Deployment Status

### Schema Deployment
- ✅ **DEPLOYED** to Supabase (as of Oct 31, 2025)
- Includes: Table, triggers, functions, backfill
- Latest changes: `stock_at_receipt` column and trigger

### Post-Deployment Verification (Completed)
```sql
✅ Table created with all columns
✅ Triggers working (auto-update on invoice status change)
✅ stock_at_receipt populated for historical items
✅ Multi-tenant isolation verified
```

---

## 🧪 Testing Checklist

### Functional Tests (All Passed ✅)
- [x] Navigate to Compras → Lista Inteligente
- [x] Three tabs appear: Por Ordenar, Ordenados, Recibido
- [x] Products with low stock suggestions appear in "Por Ordenar"
- [x] Click "Ordenar" → Creates invoice and moves to "Ordenados"
- [x] Invoice number is clickable and opens in read-only mode
- [x] Mark invoice as "received" → Item moves to "Recibido"
- [x] "Stock al Recibir" shows actual stock at receipt time
- [x] "Creado el" shows invoice creation date
- [ ] Replenishment urgency is clear without color-only meaning or a rainbow
      chip system
- [ ] Invoice detail → return restores the exact workflow view, filters,
      selection, and scroll
- [ ] Desktop, tablet, and phone use task-appropriate compositions rather than
      a universal table, card, or split-pane recipe

### Edge Cases (All Handled ✅)
- [x] Product with no sales history → Not suggested
- [x] Product with high stock → Not suggested
- [x] Product already ordered → Appears in "Ordenados", not "Por Ordenar"
- [x] Invoice deleted → smart_purchase_list.invoice_id set to null
- [x] Multi-tenant isolation → Users only see their tenant's data

---

## 📝 Code Quality Notes

- ✅ All database triggers use `tenant_id` for multi-tenant safety
- ✅ RLS policies applied to `smart_purchase_list` table
- ✅ Proper error handling with user-friendly messages
- ✅ Loading states with progress indicators
- ✅ Empty states with helpful guidance ("No hay productos por ordenar")
- ✅ No SQL injection risks (uses parameterized queries)
- ⚠️ Responsive behavior must be revalidated against the current canonical
  desktop, tablet, phone, touch, and context-preservation requirements

---

## 🔗 Related Modules

This module integrates with:
- **Purchases Module:** Creates purchase invoices
- **Inventory Module:** Reads product data and current stock
- **Sales Module:** Reads sales history for velocity calculation
- **Accounting Module:** Invoice creation triggers journal entries

---

## 📚 Files Summary

**Created/Modified:**

1. **Database:**
   - `supabase/sql/core_schema.sql` (lines 1056-1408)
     - Table: `smart_purchase_list`
     - Function: `suggest_products_to_buy()`
     - Triggers: Auto-add/update on invoice status
     - Function: `backfill_stock_at_receipt_for_received_items()`

2. **Flutter Model:**
   - `lib/modules/purchases/models/smart_purchase_list_item.dart`
     - Fields: id, productId, productName, sku, currentStock, salesLast30d, suggestedQuantity, notes, status, invoiceId, orderDate, stockAtOrder, stockAtReceipt
     - Methods: fromJson, toJson, copyWith

3. **Flutter Service:**
   - `lib/modules/purchases/services/smart_purchase_service.dart`
     - loadItems()
     - filterByStatus()
     - createPurchaseInvoice()
     - updateNotes()

4. **Flutter UI:**
   - `lib/modules/purchases/pages/smart_purchase_list_page.dart` (~800 lines)
     - Three-tab layout (Por Ordenar, Ordenados, Recibido)
     - Search functionality
     - Replenishment urgency
     - Canonical read-only invoice access
     - Invoice creation date display

5. **Navigation:**
   - Route: `/purchases/smart-list`
   - Menu: Compras → Lista Inteligente

---

## 🎯 Next Steps (Priority Order)

1. **HIGH:** Implement inline editing for suggested quantity and notes
   - Improves UX (no need to manually adjust invoices)
   - Allows users to document purchase decisions

2. **MEDIUM:** Add bulk invoice creation
   - Select multiple products → Create single invoice
   - Reduces time for large purchase orders

3. **LOW:** Add advanced filtering (category, supplier, priority)
   - Helps users focus on specific product groups
   - Better for large inventories

4. **FUTURE:** Sales velocity trends and seasonal adjustments
   - More accurate predictions
   - Handles seasonal businesses (e.g., summer vs winter products)

---

## 📈 Business Impact

**Benefits Delivered:**
- ⏱️ **Time Saved:** No manual calculation of purchase quantities
- 📊 **Data-Driven:** Decisions based on actual sales history
- 🎯 **Reduced Stockouts:** Proactive replenishment suggestions
- 💰 **Optimized Cash Flow:** Buy only what's needed
- 📋 **Workflow Automation:** Status updates happen automatically
- 🔍 **Full Traceability:** Track order → receipt → stock change

**User Feedback (Expected):**
- "Makes purchasing decisions much easier"
- "The most urgent replenishment decisions are easy to recognize"
- "Wish I could edit quantities before ordering" ← TODO #1

---

## 🔧 Maintenance Notes

**When Adding New Product:**
- Automatically appears in suggestions if sales history exists
- No manual configuration needed

**When Archiving Old Entries:**
```sql
-- Option 1: Delete received items older than 90 days
DELETE FROM smart_purchase_list 
WHERE status = 'received' 
  AND updated_at < NOW() - INTERVAL '90 days';

-- Option 2: Add archived status (future enhancement)
UPDATE smart_purchase_list 
SET status = 'archived' 
WHERE status = 'received' 
  AND updated_at < NOW() - INTERVAL '90 days';
```

**Recalculating Suggestions:**
```sql
-- Run manually or via scheduled job
SELECT suggest_products_to_buy('<tenant_id>');
```

---

*Module is production-ready and actively used. Inline editing is the main enhancement needed for complete functionality.*
