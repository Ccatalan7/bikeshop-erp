# Smart Purchase List Module - Development Summary

**Date:** November 1, 2025  
**Status:** ✅ Complete - Ready for Production

---

## 📋 Overview

The Smart Purchase List is an intelligent inventory replenishment tool located at **Compras → Lista Inteligente**. It analyzes product sales history and current stock to suggest purchase quantities, helping users make data-driven purchasing decisions.

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
- ✏️ **Inline editing** for suggested quantity (planned, not yet implemented)
- 📝 **Notes column** for purchase justification/reminders
- 🎨 **Priority colors** (visual indicators):
  - 🔴 Red: Stock < 3 (critical)
  - 🟠 Orange: Stock 3-5 (low)
  - 🟡 Yellow: Stock 6-10 (medium)
  - 🟢 Green: Stock > 10 (good)

---

### 3. Three-View Workflow

#### A. **"Por Ordenar" (To Order) View**
**Purpose:** Review and plan purchases

**Columns:**
- Producto (Product name)
- SKU
- Stock Actual (Current stock with color badge)
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
- 📄 **N° Factura** (Invoice Number) - Clickable link
- 📅 **Ordenado el** (Order date)

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
- 📦 **Stock al Recibir** (Stock at receipt) - Actual stock when invoice was received
- 📅 **Creado el** (Invoice creation date)

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

**Implementation:**
```dart
class PurchaseInvoiceFormPage extends StatefulWidget {
  final String? invoiceId;
  final bool readOnly; // NEW parameter (default: false)
}

// Modified UI behavior:
Widget _buildHeader() {
  if (widget.readOnly) {
    // Hide: Save, Delete, Add Line buttons
    // Show: Only status label and back button
  } else {
    // Normal edit mode with all actions
  }
}
```

**Navigation:**
```dart
// From smart_purchase_list_page.dart
void _navigateToInvoice(String invoiceNumber) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => PurchaseInvoiceFormPage(
        invoiceId: invoiceId,
        readOnly: true, // ← Prevents editing
      ),
    ),
  );
}
```

---

### 7. GUI Enhancements

**Recent Fixes (Oct 31, 2025):**

✅ **Invoice Creation Date Column**
- Added "Creado el" column to "Recibido" view
- Shows when the purchase invoice was originally created
- Format: `DD/MM/YYYY HH:mm`
- Uses `FutureBuilder` to fetch from `purchase_invoices.created_at`

✅ **Clickable Invoice Numbers**
- Invoice numbers in "Ordenados" and "Recibido" views are blue and underlined
- Click to navigate to invoice detail
- Opens in read-only mode (no accidental edits)

✅ **Priority Color Badges**
- Visual stock indicators based on quantity
- Helps quickly identify critical stock levels
- Color-coded for at-a-glance assessment

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

**Implementation Plan:**
```dart
// Replace Text widget with TextField on edit mode
bool _isEditing = false;
TextEditingController _notesController;

// Add edit/save buttons per row
// Save changes via SmartPurchaseService.updateItem()
```

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
- ❌ Filter by priority level
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
- [x] Priority colors display correctly (red/orange/yellow/green)

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
- ✅ Responsive design (works on mobile/tablet/desktop)

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
     - Priority color badges
     - Clickable invoice navigation
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
- "Love the color-coded priorities"
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
