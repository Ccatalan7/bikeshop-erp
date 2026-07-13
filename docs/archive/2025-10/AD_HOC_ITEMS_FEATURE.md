# 🎯 Ad-Hoc Items & Flexible Product Selection Feature

**Date:** October 31, 2025  
**Status:** Phases 1-2 Complete, Phase 3 Paused  
**Modules Affected:** Sales Invoices ✅, Mechanic Jobs ✅, POS ⏸️

---

## 📊 Implementation Status

| Phase | Module | Status | Completion Date |
|-------|--------|--------|----------------|
| 1 | Sales Invoices | ✅ Complete | Oct 30, 2025 |
| 2 | Mechanic Jobs (Pegas) | ✅ Complete | Oct 31, 2025 |
| 3 | POS | ⏸️ Paused | - |
| 4 | Backend & Accounting | 📝 TODO | - |
| 5 | Analytics & Reporting | 📝 TODO | - |
| 6 | Advanced Features | 📝 Future | - |

---

## 📋 Feature Overview

Add flexibility to allow selling/invoicing both:
1. **Official catalog products** (from products table)
2. **Ad-hoc/custom items** (typed on-the-fly, not in catalog)
3. **Custom descriptions/notes** for any line item

### User Requirements (From User Feedback)

Based on Zoho Books workflow:
- ✅ Start typing in product field → dropdown shows matching catalog products
- ✅ Select a product from dropdown → auto-fills price, SKU, stock info
- ✅ Type something not in catalog → accept as custom item
- ✅ Add notes/descriptions to official products
- ✅ Custom items get same accounting treatment as catalog products
- ✅ Works in: Sales Invoices, Pegas (Mechanic Jobs), POS

### Improvements Added

1. **Track ad-hoc items** - Flag them in database (`is_catalog_product` field)
2. **Quick product creation** - Option to "Save as new product" from ad-hoc items (future)
3. **Recent ad-hoc items** - Show recently used custom descriptions for faster reuse (future)
4. **Better UX** - Visual distinction between catalog products (with image/SKU) and ad-hoc items
5. **Accounting integrity** - Ad-hoc items still generate proper journal entries
6. **Analytics separation** - Reports can distinguish catalog vs custom sales

---

## ✅ Completed Work

### 1. Data Model Updates

**File:** `lib/modules/sales/models/sales_models.dart`

**Changes to `InvoiceItem` class:**
```dart
class InvoiceItem {
  final String? productId;           // ✅ NOW NULLABLE (null = ad-hoc item)
  final String? description;         // ✅ NEW: Custom description/notes
  final bool isCatalogProduct;       // ✅ NEW: true = catalog, false = ad-hoc
  // ... existing fields
}
```

**What this enables:**
- Can create invoice items without a `product_id` (ad-hoc items)
- Store custom descriptions for line items
- Track whether item is from catalog or custom
- Full backwards compatibility (defaults to `isCatalogProduct = true`)

---

### 2. Reusable Autocomplete Widget

**File:** `lib/shared/widgets/product_autocomplete_field.dart` (NEW)

**Features:**
- ✅ Real-time product search (name, SKU, brand)
- ✅ Dropdown with product cards (image, price, stock, SKU)
- ✅ Auto-select first match on Enter
- ✅ Accept custom items (type anything, press Enter)
- ✅ Visual distinction (catalog items have images/SKU, custom items have "+" icon)
- ✅ Stock level indicator (shows available quantity or "Sin stock")
- ✅ Clear button to reset search
- ✅ Loading state while fetching products

**Usage:**
```dart
ProductAutocompleteField(
  onProductSelected: (ProductSelection selection) {
    if (selection.isCatalogProduct) {
      // User selected official product
      final product = selection.product!;
      addProductToInvoice(product);
    } else {
      // User typed custom item
      addCustomItemToInvoice(selection.customDescription!);
    }
  },
  allowCustomItems: true, // Set to false to restrict to catalog only
  labelText: 'Artículo o servicio',
  hintText: 'Escriba para buscar o ingrese un artículo personalizado',
)
```

**ProductSelection class:**
```dart
class ProductSelection {
  final bool isCatalogProduct;
  final Product? product;              // Null if custom item
  final String displayText;
  final String? customDescription;     // For ad-hoc items
}
```

---

### 3. Database Schema Updates

**File:** `supabase/sql/core_schema.sql`

**Added Product Sync Triggers:**
```sql
-- Sync category_name when category_id changes
create or replace function sync_product_category_name()
-- Sync supplier_name when supplier_id changes
-- Trigger to update all products when category name changes
-- Trigger to update all products when supplier name changes
```

**Why this matters:**
- `category_name` and `supplier_name` are real columns (not virtual)
- Triggers keep them synchronized automatically
- No need to filter them out from updates
- Faster queries (no JOINs needed)

---

## 🚧 Work In Progress

### Phase 1: Sales Invoice Form Integration ✅ COMPLETED (Oct 30, 2025)

**File modified:** `lib/modules/sales/pages/invoice_form_page.dart`

**Completed Tasks:**
- ✅ Replaced product selection modal with inline `ProductAutocompleteField`
- ✅ Updated `_InvoiceLine` class to support ad-hoc items:
  - Made `productId` nullable (null = ad-hoc item)
  - Added `description` field for custom notes
  - Added `isCatalogProduct` flag (true = catalog, false = ad-hoc)
- ✅ Updated `_InvoiceLineEntry` class:
  - Added `descriptionController` for managing description text
  - Updated `toInvoiceItem()` to include new fields (`description`, `isCatalogProduct`)
  - Updated `dispose()` to clean up description controller
- ✅ Added description/notes field to each line item card
- ✅ Visual indicators for ad-hoc vs catalog items:
  - 📦 Icon for catalog products
  - 📝 Icon for ad-hoc items
  - "Personalizado" badge for ad-hoc items
  - Different hint text for description field based on item type
- ✅ Added `_addCustomItemLine()` method for creating ad-hoc line items
- ✅ Updated `_addProductLine()` to include `isCatalogProduct: true`
- ✅ Updated `_applyInvoice()` to handle loading ad-hoc items correctly
- ✅ Removed unused `_openProductSelector()` method and `_ProductSelector` widget
- ✅ Validation: Either productId OR description must be provided (enforced by model)

**UI Changes Implemented:**
```
Compact Table Layout (Zoho Books Style):
┌────────────────────────────────────────────────────────────────────────┐
│ #  │ Artículo              │ Cantidad │ Precio Unit. │ Desc. │ Total   │
├────────────────────────────────────────────────────────────────────────┤
│ 📦1│ Cubre Cámara 26"      │   [1]    │  [$15,000]   │ [$0]  │ $15,000│❌
│    │ SKU: 19273            │          │              │       │        │
│    │ Cliente pidió negra   │          │              │       │        │
├────────────────────────────────────────────────────────────────────────┤
│ 📝2│ Ajuste de frenos      │   [1]    │  [$5,000]    │ [$0]  │ $5,000 │❌
│    │ [Custom]              │          │              │       │        │
│    │ Detalles del servicio │          │              │       │        │
├────────────────────────────────────────────────────────────────────────┤
│    │ [Buscar o escribir artículo...                ]                 │
└────────────────────────────────────────────────────────────────────────┘

Features:
- Compact single-row layout (vs. bulky cards)
- Inline editable fields (quantity, price, discount)
- Description field below each item (collapsible)
- Add new item via search field at bottom
- Visual indicators: 📦 = catalog, 📝 = custom
- Stock warnings shown inline when low
- 50% less vertical space used
```
```
┌─────────────────────────────────────────┐
│ [Agregar artículo o servicio...]        │  ← ProductAutocompleteField
│   ┌─────────────────────────────────┐   │
│   │ 📦 Cubre Cámara 26" - SKU:...  │   │  ← Catalog products
│   │ 🔧 Aceite Mineral - SKU:...    │   │
│   │ ➕ Agregar: "Servicio custom"  │   │  ← Ad-hoc option
│   └─────────────────────────────────┘   │
└─────────────────────────────────────────┘

Line Item Card Layout:
┌──────────────────────────────────────────┐
│ 📦 Cubre Cámara 26"                      │  ← Catalog item
│    SKU: 19273                            │
│                                          │
│ [Descripción/Notas (opcional)_____]     │  ← Description field
│                                          │
│ [Cant: 1] [Precio: $15,000] [Desc: $0] │
│ Total línea: $15,000 | Stock: 50        │
└──────────────────────────────────────────┘

┌──────────────────────────────────────────┐
│ � Ajuste de frenos [Personalizado]     │  ← Ad-hoc item
│                                          │
│ [Detalles del servicio..._________]     │  ← Description field
│                                          │
│ [Cant: 1] [Precio: $5,000] [Desc: $0]  │
│ Total línea: $5,000                      │
└──────────────────────────────────────────┘
```

**Testing Needed:**
- [ ] Create invoice with only catalog products → works
- [ ] Create invoice with only ad-hoc items → works
- [ ] Create invoice with mix of catalog + ad-hoc → works
- [ ] Add description to catalog product → saves correctly
- [ ] Edit invoice with ad-hoc items → loads and saves correctly
- [ ] Delete line item (catalog) → recalculates totals
- [ ] Delete line item (ad-hoc) → recalculates totals
- [ ] Save invoice with ad-hoc items → creates invoice in database
- [ ] Load saved invoice with ad-hoc items → displays correctly

---

### Phase 2: Mechanic Jobs (Pegas) Integration ✅ COMPLETED (Oct 31, 2025)

**File modified:** `lib/modules/bikeshop/pages/mechanic_job_form_page.dart`

**Completed Tasks:**
- ✅ Updated `_JobPartItem` class to support ad-hoc items:
  - Made `product` nullable (null = ad-hoc part)
  - Added `name` field for custom part names
  - Added `isCatalogProduct` flag (true = catalog, false = ad-hoc)
  - Added `notes` field for additional information
  - Added helper getters: `displayName`, `sku`
- ✅ Created `_PartItemDialog` with `ProductAutocompleteField`:
  - Replaces old `_ProductSelectorDialog` with better UX
  - Supports both catalog products and custom items
  - Includes notes field for any part
  - Shows stock warnings for catalog products
  - Auto-fills price when catalog product selected
- ✅ Updated parts table display:
  - Visual indicators: 📦 for catalog parts, 📝 for ad-hoc/custom parts
  - "Personalizado" badge for custom items
  - Different icon colors (orange for ad-hoc, grey for catalog)
  - Shows SKU and stock only for catalog products
  - Displays notes below part name
- ✅ Updated job save method:
  - Correctly handles nullable `product_id` for ad-hoc items
  - Uses `name` field from `_JobPartItem` instead of `product.name`
  - Uses `sku` getter which returns null for ad-hoc items
- ✅ Updated job loading:
  - Correctly loads ad-hoc parts (when `productId` is null)
  - Sets `isCatalogProduct` flag based on presence of `productId`
- ✅ Labor section already supports ad-hoc services (no changes needed)

**Use Case Example:**
```
Pega #1234 - Reparación Bicicleta MTB
├─ 📦 Cubre Cámara 26" (SKU: 19273) - $15,000  ← Catalog part
│  └─ Nota: "Cliente pidió goma reforzada"
├─ 📝 Parche especial - $2,000                  ← Custom part
│  └─ Nota: "Parche de mayor tamaño"
├─ Mano de obra: Ajuste de cambios - $8,000    ← Labor (already supported ad-hoc)
└─ Total: $25,000
```

**Testing Needed:**
- [ ] Create pega with only catalog parts → works
- [ ] Create pega with only ad-hoc parts → works
- [ ] Create pega with mix of catalog + ad-hoc → works
- [ ] Add notes to catalog part → saves and displays
- [ ] Add notes to ad-hoc part → saves and displays
- [ ] Edit pega with ad-hoc items → loads and saves correctly
- [ ] Delete part (catalog) → recalculates totals
- [ ] Delete part (ad-hoc) → recalculates totals
- [ ] Generate invoice from pega with ad-hoc items → creates correct invoice items

---

### Phase 2: Mechanic Jobs (Pegas) Integration

**File to modify:** `lib/modules/bikeshop/pages/mechanic_job_form_page.dart`

**Tasks:**
- [ ] Replace parts selection with `ProductAutocompleteField`
- [ ] Allow custom services/labor descriptions
- [ ] Add notes field for each part/service
- [ ] Update parts list UI to show ad-hoc vs catalog items
- [ ] Ensure invoice generation handles ad-hoc items correctly
- [ ] Test: Pega with mix of catalog parts + custom labor → generates invoice

**Use Case Example:**
```
Pega #1234 - Reparación Bicicleta MTB
├─ 📦 Cubre Cámara 26" (SKU: 19273) - $15,000  ← Catalog part
│  └─ Nota: "Cliente pidió goma reforzada"
├─ 📝 Ajuste de cambios - $8,000                ← Custom labor
├─ 📝 Limpieza profunda cadena - $5,000         ← Custom labor
└─ Total: $28,000
```

**When "Generate Invoice" is clicked:**
- Creates `sales_invoice` with 3 line items
- Line 1: `product_id = <uuid>`, `is_catalog_product = true`, `description = "Cliente pidió..."`
- Line 2: `product_id = null`, `is_catalog_product = false`, `description = "Ajuste de cambios"`
- Line 3: `product_id = null`, `is_catalog_product = false`, `description = "Limpieza profunda..."`

---

### Phase 3: POS Integration ⏸️ PAUSED (Requires more complex refactoring)

**Files to modify:** 
- `lib/modules/pos/services/pos_service.dart`
- `lib/modules/pos/models/pos_cart_item.dart`
- `lib/modules/pos/pages/pos_dashboard_page.dart`

**Challenges Identified:**
1. POSCartItem currently requires a `Product` object
2. Need to make `product` nullable and add fields for ad-hoc items
3. POS dashboard uses product grid - need "Custom Item" button
4. Complex flow: Dashboard → Cart → Payment → Receipt
5. All steps need to handle ad-hoc items correctly

**Recommended Approach:**
1. Update `POSCartItem` model to match `_JobPartItem` pattern:
   - Make `product` nullable
   - Add `name`, `isCatalogProduct` fields
   - Add `description` field for notes
2. Update `POSService.addToCart()` to accept both Product and custom items
3. Add "Custom Item" button in POS dashboard (floating action button)
4. Create dialog with ProductAutocompleteField for quick custom items
5. Update cart display to show visual indicators (📦 vs 📝)
6. Update receipt generation to include descriptions

**Note:** This requires significant refactoring of POS module. Recommend completing Phases 1-2 testing first before tackling POS.

---

### Phase 3: POS Integration

**File to modify:** `lib/modules/pos/pages/pos_page.dart`

**Tasks:**
- [ ] Add "Custom Item" button in POS product grid
- [ ] Open dialog with `ProductAutocompleteField` when clicked
- [ ] Allow quick custom items for on-the-fly sales
- [ ] Show ad-hoc items in cart with special icon
- [ ] Ensure receipt printing shows descriptions correctly
- [ ] Test: Mixed cart (products + custom items) → complete sale

**POS UI:**
```
┌────────────────────────────────────────┐
│  CARRITO                               │
├────────────────────────────────────────┤
│ 📦 Cubre Cámara 26" (x1)    $15,000   │  ← Catalog
│ 📝 Reparación urgente (x1)   $10,000  │  ← Ad-hoc
│ 📦 Aceite (x2)                $1,000  │  ← Catalog
├────────────────────────────────────────┤
│ TOTAL:                       $26,000  │
└────────────────────────────────────────┘

[Productos] [➕ Artículo Custom] [Pagar]
```

---

### Phase 4: Backend & Accounting

**Tasks:**
- [ ] Update inventory consumption logic
  - Skip inventory deduction for ad-hoc items (productId = null)
  - Only deduct stock for catalog products
- [ ] Update journal entry creation
  - Ad-hoc items use generic "Sales" account (4101)
  - Catalog items can use category-specific accounts (if configured)
- [ ] Add validation in triggers/functions
  - Allow NULL `product_id` in `sales_invoice_items` JSONB
  - Validate: `(product_id IS NOT NULL) OR (description IS NOT NULL)`

**Database Changes Needed:**

`supabase/sql/core_schema.sql` - Update inventory consumption:
```sql
-- In consume_sales_invoice_inventory() function
for v_item in select * from jsonb_to_recordset(p_invoice.items) as (
  product_id uuid,
  is_catalog_product boolean,
  quantity numeric,
  ...
)
loop
  -- Only deduct stock for catalog products
  if v_item.is_catalog_product and v_item.product_id is not null then
    update products
    set inventory_qty = inventory_qty - v_item.quantity
    where id = v_item.product_id;
  end if;
  -- Ad-hoc items: no inventory impact
end loop;
```

---

### Phase 5: Analytics & Reporting

**Tasks:**
- [ ] Update sales reports to separate catalog vs ad-hoc sales
- [ ] Add "Ad-hoc Items Report" showing most common custom descriptions
- [ ] Suggest converting frequent ad-hoc items to catalog products
- [ ] Dashboard widget: "X% of sales were custom items"
- [ ] Product performance report: exclude ad-hoc from product metrics

**New Reports:**

1. **Ad-Hoc Items Analysis**
   - Most used custom descriptions (top 20)
   - Total revenue from ad-hoc vs catalog
   - Trend: Are ad-hoc items increasing/decreasing?

2. **Catalog Gaps Report**
   - Custom items that appear frequently (>5 times)
   - Suggested to convert to official products
   - One-click "Create Product from Ad-Hoc Item"

---

### Phase 6: Advanced Features (Future)

**Quick Product Creation:**
- [ ] Button next to ad-hoc item: "💾 Save as Product"
- [ ] Pre-fill product form with description, price from invoice
- [ ] Convert future invoices to use new catalog product

**Recent Ad-Hoc Items:**
- [ ] Cache last 50 custom descriptions per tenant
- [ ] Show in autocomplete dropdown (section "Recent Custom Items")
- [ ] Faster reuse of common ad-hoc items

**Bulk Convert:**
- [ ] Admin page: List all unique ad-hoc descriptions
- [ ] Checkbox selection + "Convert to Products" bulk action
- [ ] Update historical invoices to link to new products (optional)

---

## 🔍 Testing Checklist

### Sales Invoice Form
- [ ] Create invoice with only catalog products → works
- [ ] Create invoice with only ad-hoc items → works
- [ ] Create invoice with mix → works
- [ ] Add description to catalog product → saves correctly
- [ ] Edit invoice with ad-hoc items → loads and saves correctly
- [ ] Delete line item (catalog) → recalculates totals
- [ ] Delete line item (ad-hoc) → recalculates totals
- [ ] Post invoice with ad-hoc items → creates journal entry
- [ ] Ad-hoc items do NOT deduct inventory
- [ ] Catalog items DO deduct inventory

### Mechanic Jobs (Pegas)
- [ ] Create pega with catalog parts → works
- [ ] Create pega with custom labor → works
- [ ] Generate invoice from pega with ad-hoc items → works
- [ ] Invoice shows descriptions correctly
- [ ] Delete pega with ad-hoc items → cascades correctly

### POS
- [ ] Add ad-hoc item to cart → shows in cart
- [ ] Complete sale with ad-hoc items → creates invoice
- [ ] Print receipt with ad-hoc items → shows descriptions
- [ ] Mixed cart (catalog + ad-hoc) → correct totals
- [ ] Ad-hoc items do NOT affect inventory

### Accounting
- [ ] Invoice with ad-hoc items → journal entry created
- [ ] Journal entry uses correct accounts (Sales 4101)
- [ ] Payment for invoice with ad-hoc items → works
- [ ] Balance sheet correct with ad-hoc sales

### Multi-Tenant
- [ ] Tenant A ad-hoc items don't appear for Tenant B
- [ ] Recent ad-hoc items filtered by tenant_id
- [ ] Reports show only current tenant's ad-hoc items

---

## 📦 Database Schema Changes Summary

### Existing Tables (No schema changes needed)

**sales_invoices:**
- `items` JSONB already supports flexible structure
- No schema migration required

**mechanic_jobs:**
- Similar JSONB structure for parts
- No schema migration required

### New Fields in JSONB (Application Level)

**Invoice Item Structure:**
```json
{
  "id": "uuid",
  "product_id": "uuid or null",           // ← NULL for ad-hoc
  "product_name": "string",
  "product_sku": "string or null",
  "description": "string or null",        // ← NEW
  "is_catalog_product": true,             // ← NEW
  "quantity": 1,
  "unit_price": 15000,
  "discount": 0,
  "line_total": 15000,
  "cost": 10000
}
```

### Function Updates Required

1. **consume_sales_invoice_inventory()** - Check `is_catalog_product` before deducting
2. **restore_sales_invoice_inventory()** - Check `is_catalog_product` before restoring
3. **create_sales_invoice_journal_entry()** - Works as-is (uses totals, not item details)

---

## 🎨 UI/UX Guidelines

### Visual Indicators

**Catalog Product:**
- Icon: 📦 (Inventory box)
- Shows: Image thumbnail, SKU, stock quantity
- Color: Default theme colors

**Ad-Hoc Item:**
- Icon: 📝 (Note/pencil)
- Shows: "(Artículo personalizado)" badge
- Color: Slightly muted or secondary color

**With Description:**
- Small note icon next to item name
- Expandable to show full description
- Gray italic text below item name

### Keyboard Shortcuts

- `Enter` on autocomplete → Select first match or create ad-hoc
- `Esc` → Close dropdown
- `Tab` → Move to next field (quantity)
- `Ctrl+K` → Focus product search field

### Mobile Considerations

- Autocomplete dropdown max height: 300px with scroll
- Touch-friendly list items (min 48px height)
- Sticky "Add Custom Item" option at bottom of dropdown
- Swipe to delete line items

---

## 🚀 Deployment Plan

### Phase 1 (MVP) - Current Sprint
1. ✅ Data model updates
2. ✅ Autocomplete widget
3. 🔄 Sales Invoice Form integration
4. Backend validation updates
5. Testing (catalog + ad-hoc items)
6. Deploy to staging

### Phase 2 - Next Sprint
1. Mechanic Jobs integration
2. POS integration
3. Inventory/accounting logic updates
4. Testing (end-to-end flows)
5. Deploy to production

### Phase 3 - Future Enhancements
1. Analytics & reporting
2. Quick product creation
3. Recent ad-hoc items cache
4. Bulk convert ad-hoc → products
5. Admin dashboard

---

## 📊 Success Metrics

**Target KPIs:**
- ✅ 100% backward compatibility (existing invoices unaffected)
- ✅ <500ms autocomplete response time
- ✅ Zero accounting discrepancies with ad-hoc items
- 📈 Reduce invoice creation time by 30% (faster custom entries)
- 📈 80% user satisfaction with flexibility (survey)
- 📊 Track ad-hoc item usage (% of total line items)

---

## 🐛 Known Issues / Considerations

1. **Inventory Reports:**
   - Ad-hoc items won't appear in "Top Selling Products" report (by design)
   - Need separate report for ad-hoc item analysis

2. **Product Search:**
   - Large catalogs (>10,000 products) may need pagination
   - Consider server-side search for better performance

3. **Historical Data:**
   - Old invoices don't have `is_catalog_product` field
   - Default to `true` for backward compatibility

4. **Duplicate Detection:**
   - No automatic detection of similar ad-hoc items
   - User must manually notice "Servicio A" vs "Servicio a"

5. **Pricing:**
   - Ad-hoc items require manual price entry every time
   - No price history (until converted to catalog product)

---

## 📚 Related Documentation

- [Sales Invoice Flow](./SALES_INVOICE_FLOW.md)
- [Mechanic Jobs (Pegas)](./MECHANIC_JOBS.md)
- [POS System](./POS_SYSTEM.md)
- [Accounting Integration](./ACCOUNTING_INTEGRATION.md)
- [Multi-Tenant Architecture](./MULTI_TENANT.md)

---

## 👥 Stakeholders

- **Developers:** Database schema, backend functions, UI implementation
- **QA:** Testing scenarios (catalog, ad-hoc, mixed)
- **Accountant:** Verify journal entries for ad-hoc items
- **End Users:** Sales team, mechanics, cashiers
- **Product Owner:** Feature prioritization, UX validation

---

## 🔗 Dependencies

- **Supabase:** JSONB support, triggers, RLS policies
- **Flutter:** Autocomplete widget, form validation
- **Accounting Module:** Journal entry generation
- **Inventory Module:** Stock deduction logic
- **Multi-Tenant:** tenant_id filtering for recent items cache

---

**Last Updated:** October 30, 2025  
**Next Review:** After Phase 1 deployment  
**Status:** 🟡 In Progress (Phase 1)
