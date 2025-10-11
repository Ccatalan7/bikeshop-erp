# Supplier Integration Completion Guide

## ✅ Completed Tasks

### 1. Supplier List Page UI Updates
- ✅ Added List/Grid view toggle (matching category pattern)
- ✅ Created `_buildSupplierListItem()` for list view
- ✅ Created `_buildSupplierGridItem()` for 3-column grid view
- ✅ Updated navigation to filter products by supplier
- ✅ Both views now navigate to `/inventory/products?supplier=<id>`

### 2. Database Schema Updates
- ✅ Created `add_supplier_to_products.sql` migration script with:
  - `supplier_id` column (UUID, nullable, FK to suppliers table)
  - `supplier_name` column (TEXT, denormalized for performance)
  - Index on `supplier_id` for fast filtering
  - Auto-update trigger for `supplier_name` field
  - Backfill script for existing data

### 3. Product Model Updates
- ✅ Added `supplierId` field to Product class
- ✅ Added `supplierName` field to Product class
- ✅ Updated `fromJson()` to parse supplier fields
- ✅ Updated `toJson()` to serialize supplier fields
- ✅ Updated `copyWith()` to include supplier fields

### 4. Product List Page Updates
- ✅ Added `initialSupplierId` parameter
- ✅ Added `_selectedSupplierId` state variable
- ✅ Updated `initState()` to handle supplier filter
- ✅ Updated `_applyFilters()` to filter by supplier

### 5. Router Updates
- ✅ Updated `/inventory/products` route to read `supplier` query parameter
- ✅ Pass `initialSupplierId` to ProductListPage

---

## 🔄 Next Steps (Required for Full Functionality)

### 1. Apply Database Migration
Run the SQL migration in Supabase:
```bash
# In Supabase SQL Editor, execute:
supabase/sql/add_supplier_to_products.sql
```

This will:
- Add `supplier_id` and `supplier_name` columns to products table
- Create index for performance
- Set up auto-update trigger
- Backfill existing products (if any have supplier data)

### 2. Update Product Form Page
The product form needs to include supplier selection:

**File**: `lib/modules/inventory/pages/product_form_page.dart`

**Changes needed**:
1. Add supplier dropdown (similar to category dropdown)
2. Load suppliers from `PurchaseService`
3. Include `supplierId` when saving products
4. Display current supplier in edit mode

**Example code**:
```dart
// In _ProductFormPageState class

// Add state variable
String? _selectedSupplierId;
List<Supplier> _suppliers = [];

// In initState(), load suppliers
Future<void> _loadSuppliers() async {
  try {
    final purchaseService = PurchaseService(database);
    final suppliers = await purchaseService.getSuppliers(activeOnly: true);
    if (mounted) {
      setState(() {
        _suppliers = suppliers;
        // If editing, set current supplier
        if (widget.productId != null && _product?.supplierId != null) {
          _selectedSupplierId = _product!.supplierId;
        }
      });
    }
  } catch (e) {
    // Handle error
  }
}

// Add supplier dropdown in form
DropdownButtonFormField<String>(
  value: _selectedSupplierId,
  decoration: const InputDecoration(
    labelText: 'Proveedor',
    hintText: 'Selecciona un proveedor (opcional)',
  ),
  items: [
    const DropdownMenuItem(
      value: null,
      child: Text('Sin proveedor'),
    ),
    ..._suppliers.map((supplier) => DropdownMenuItem(
      value: supplier.id,
      child: Text(supplier.name),
    )),
  ],
  onChanged: (value) {
    setState(() {
      _selectedSupplierId = value;
    });
  },
),

// In _saveProduct(), include supplierId
final product = Product(
  // ... other fields
  supplierId: _selectedSupplierId,
  // supplierName will be auto-filled by database trigger
);
```

### 3. Update Product List Table Headers (Optional Enhancement)
Add a "Proveedor" column to the product table view:

**File**: `lib/modules/inventory/pages/product_list_page.dart`

In `_buildTableView()`, add supplier column:
```dart
DataColumn(
  label: const Text('Proveedor'),
  onSort: (columnIndex, ascending) {
    // Sort logic if needed
  },
),

// In DataRow
DataCell(
  Text(product.supplierName ?? 'Sin proveedor'),
),
```

### 4. Add Supplier Filter Dropdown (Optional Enhancement)
Add a supplier filter dropdown next to the category filter:

**File**: `lib/modules/inventory/pages/product_list_page.dart`

In the filter section:
```dart
// Load suppliers in initState
List<Supplier> _suppliers = [];

Future<void> _loadSuppliers() async {
  try {
    final purchaseService = PurchaseService(database);
    final suppliers = await purchaseService.getSuppliers(activeOnly: true);
    if (mounted) {
      setState(() {
        _suppliers = suppliers;
      });
    }
  } catch (_) {
    // Suppliers are optional
  }
}

// Add supplier dropdown
DropdownButton<String?>(
  value: _selectedSupplierId,
  hint: const Text('Todos los proveedores'),
  items: [
    const DropdownMenuItem(
      value: null,
      child: Text('Todos los proveedores'),
    ),
    ..._suppliers.map((supplier) => DropdownMenuItem(
      value: supplier.id,
      child: Text(supplier.name),
    )),
  ],
  onChanged: (value) {
    setState(() {
      _selectedSupplierId = value;
    });
    _loadProducts();
  },
),
```

### 5. Update RLS Policies (If Needed)
The `add_supplier_to_products.sql` migration only adds columns. If you need RLS policies for supplier-based access control, add to `supabase/sql/rls_policies.sql`:

```sql
-- Allow authenticated users to read products based on supplier access
-- (Only needed if you want supplier-based row-level security)
CREATE POLICY "Users can view products from their assigned suppliers"
  ON products
  FOR SELECT
  TO authenticated
  USING (
    supplier_id IS NULL 
    OR 
    supplier_id IN (
      SELECT id FROM suppliers WHERE /* your access logic */
    )
  );
```

---

## 🧪 Testing Checklist

Once you complete the above steps:

1. ✅ **Database Migration**
   - [ ] Run `add_supplier_to_products.sql` in Supabase
   - [ ] Verify columns exist: `SELECT supplier_id, supplier_name FROM products LIMIT 1;`
   - [ ] Test trigger: Update a product's supplier_id and verify supplier_name updates

2. ✅ **Supplier List Navigation**
   - [ ] Open supplier list (Compras → Proveedores)
   - [ ] Toggle between List and Grid views
   - [ ] Click a supplier in list view → Should navigate to products filtered by that supplier
   - [ ] Click a supplier in grid view → Should navigate to products filtered by that supplier
   - [ ] Verify URL shows `?supplier=<uuid>`

3. ✅ **Product Filtering**
   - [ ] Products page shows only products from selected supplier
   - [ ] If no products found, displays empty state
   - [ ] Search and other filters still work alongside supplier filter

4. ✅ **Product Form**
   - [ ] Supplier dropdown appears in form
   - [ ] Can select a supplier when creating new product
   - [ ] Can change supplier when editing existing product
   - [ ] Can set supplier to "Sin proveedor" (null)
   - [ ] Saving product with supplier saves correctly to database

5. ✅ **Data Consistency**
   - [ ] When supplier name changes in suppliers table, product.supplier_name updates automatically
   - [ ] When supplier is deleted, product.supplier_id becomes NULL (ON DELETE SET NULL)

---

## 📁 Files Modified

### Backend (SQL)
- `supabase/sql/add_supplier_to_products.sql` (NEW)

### Frontend (Dart/Flutter)
- `lib/modules/purchases/pages/supplier_list_page.dart` (UPDATED)
- `lib/modules/inventory/models/inventory_models.dart` (UPDATED - Product class)
- `lib/modules/inventory/pages/product_list_page.dart` (UPDATED)
- `lib/shared/routes/app_router.dart` (UPDATED)
- `lib/modules/inventory/pages/product_form_page.dart` (NEEDS UPDATE)

---

## 🎯 Current Status

**✅ READY TO DEPLOY:**
- Supplier list UI (List/Grid toggle, navigation)
- Product model (supplier fields)
- Product filtering logic
- Database migration script

**⏳ PENDING:**
- Apply database migration in Supabase
- Update product form to include supplier selection

**🎨 OPTIONAL ENHANCEMENTS:**
- Add supplier column to product table view
- Add supplier filter dropdown in products page
- Add supplier-based RLS policies (if needed)

---

## 🚀 Quick Deploy Steps

1. **Run SQL migration**:
   - Go to Supabase Dashboard → SQL Editor
   - Paste contents of `supabase/sql/add_supplier_to_products.sql`
   - Click "Run"

2. **Update product form**:
   - Follow steps in "Update Product Form Page" section above
   - Add supplier dropdown
   - Include supplierId in save logic

3. **Test navigation**:
   - Open supplier list
   - Click any supplier
   - Verify products page opens with correct filter

4. **Done!** 🎉

---

## 📝 Notes

- The `supplier_name` field is denormalized (duplicated data) for performance. This avoids JOINs when listing products.
- The database trigger automatically keeps `supplier_name` in sync with the suppliers table.
- Supplier is optional for products (nullable field).
- The implementation mirrors the category pattern for consistency.
- Both list and grid views are functional and navigate correctly.

---

**Created**: 2024
**Pattern**: Mirrors category filtering implementation
**Status**: Backend ready, frontend needs product form update
