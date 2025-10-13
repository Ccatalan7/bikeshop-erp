# Product Type Classification Implementation

## ✅ What Was Implemented

### 1. Database Changes
- **New Column**: `product_type` (TEXT)
- **Values**: 'product' or 'service'
- **Default**: 'product'
- **Migration File**: `supabase/sql/add_product_type_column.sql`

### 2. Model Updates
- **File**: `lib/shared/models/product.dart`
- **Changes**:
  - Added `ProductType` enum with values: `product`, `service`
  - Added `productType` field to Product class
  - Updated `fromJson`, `toJson`, and `copyWith` methods
  - Default value: `ProductType.product`

### 3. UI Updates

#### Product Form (`lib/modules/inventory/pages/product_form_page.dart`)
- Added ProductType dropdown selector
- Position: Between category and supplier fields
- Features:
  - Icon indicators (📦 for products, 🔧 for services)
  - Helper text explaining the difference
  - Default: "Producto"

#### Purchase Invoice Form (`lib/modules/purchases/pages/purchase_invoice_form_page.dart`)
- **Filtering Logic**: Only products with `productType == ProductType.product` can be selected
- Services are automatically excluded from purchase invoices
- Products can still be sold through sales invoices

---

## 🔄 Business Rules

### Products (Bienes)
- ✅ Can be **purchased** (facturas de compra)
- ✅ Can be **sold** (facturas de venta)
- ✅ Have inventory tracking
- ✅ Affect stock levels
- **Examples**: Bicycles, tires, parts, accessories

### Services (Servicios)
- ❌ **Cannot** be purchased
- ✅ Can be **sold** (facturas de venta only)
- ❌ No inventory tracking
- ❌ Don't affect stock
- **Examples**: Bike repair, tune-up, assembly, consulting

---

## 📋 Migration Steps

### 1. Run SQL Migration
```sql
-- In Supabase SQL Editor, run:
supabase/sql/add_product_type_column.sql
```

This will:
- Add `product_type` column to products table
- Set all existing products to 'product' by default
- Auto-convert items with category='services' to service type
- Create index for performance

### 2. Hot Restart Flutter App
```bash
flutter run -d windows
```

No code changes needed - everything is already implemented!

---

## 🎨 How to Use

### Creating a New Product
1. Go to **Inventario** → **+ Nuevo Producto**
2. Fill in product details
3. Select **Tipo de producto**:
   - 📦 **Producto** - For physical items you buy and sell
   - 🔧 **Servicio** - For services you only sell
4. Click **Guardar**

### Purchasing Products
1. Go to **Compras** → **+ Nueva Factura**
2. Click **Agregar producto**
3. **Only products** will appear in the list (services are filtered out)
4. Services cannot be added to purchase invoices

### Selling Products or Services
1. Go to **Ventas** → **+ Nueva Factura**
2. Click **Agregar producto**
3. **Both products AND services** will appear
4. You can sell anything

---

## 🧪 Testing Checklist

### Test 1: Create a Service
- [ ] Create new product with type "Servicio"
- [ ] Verify it saves correctly
- [ ] Check stock quantity is 0 (services don't have stock)

### Test 2: Purchase Invoice Filtering
- [ ] Open new purchase invoice
- [ ] Click "Agregar producto"
- [ ] Verify services do NOT appear in the list
- [ ] Verify only products appear

### Test 3: Sales Invoice (Both Types)
- [ ] Open new sales invoice
- [ ] Click "Agregar producto"
- [ ] Verify BOTH products and services appear
- [ ] Can add both to invoice

### Test 4: Edit Existing Product
- [ ] Edit a product
- [ ] Change type from Product → Service
- [ ] Save
- [ ] Verify it no longer appears in purchase invoices

---

## 🗄️ Database Schema

```sql
ALTER TABLE products 
ADD COLUMN product_type TEXT NOT NULL DEFAULT 'product'
CHECK (product_type IN ('product', 'service'));

CREATE INDEX idx_products_product_type ON products(product_type);
```

---

## 📊 Expected Results

After migration:
- All existing products → `product_type = 'product'`
- Items with category='services' → `product_type = 'service'`
- Purchase invoices → Only show products
- Sales invoices → Show both

---

## ⚠️ Important Notes

1. **Services cannot be purchased**: This is enforced at the UI level (filtered out)
2. **Stock tracking**: Services typically have `trackStock = false`
3. **Backward compatibility**: Default value ensures existing code works
4. **Database constraint**: Only 'product' or 'service' values allowed

---

## 🚀 Next Steps

1. Run the SQL migration
2. Hot restart the app
3. Test creating a service
4. Verify filtering works in purchase invoices
5. Continue with purchase invoice workflow testing

Everything is ready to use! 🎉
