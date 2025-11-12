# Zoho to Supabase Field Mapping

## ✅ Currently Mapped (in import_one_new_product.py)

| Zoho Field | Our DB Field | Status | Notes |
|------------|--------------|--------|-------|
| `name` / `item_name` | `name` | ✅ Mapped | Fallback to item_name if name is empty |
| `sku` | `sku` | ✅ Mapped | Unique identifier |
| `rate` | `price` | ✅ Mapped | Selling price |
| `purchase_rate` | `cost` | ✅ Mapped | Cost price |
| `stock_on_hand` | `stock_quantity` | ✅ Mapped | Current stock |
| `stock_on_hand` | `inventory_qty` | ✅ Mapped | Same value (both columns) |
| `reorder_level` | `min_stock_level` | ✅ Mapped | Minimum stock threshold |
| `reorder_level * 3` | `max_stock_level` | ✅ Mapped | Calculated max |
| `brand` | `brand` | ✅ Mapped | Brand name as text |
| `status` | `is_active` | ✅ Mapped | active=true, else false |
| `created_time` | `created_at` | ✅ Mapped | ISO timestamp |
| `last_modified_time` | `updated_at` | ✅ Mapped | ISO timestamp |

## ⚠️ Available but NOT Mapped

| Zoho Field | Our DB Field | Why Not Mapped |
|------------|--------------|----------------|
| `description` | `description` | ❌ Empty in Zoho (we map but it's "") |
| `category_name` | `category_name` | ❌ Need category lookup |
| `category_id` (Zoho) | `category_id` (uuid) | ❌ Different ID systems |
| `manufacturer` | `manufacturer` | ❌ Empty in Zoho |
| `part_number` | `manufacturer_sku` | ✅ Could map |
| `upc` / `ean` / `isbn` | `gtin` | ✅ Could map (need to choose one) |
| `unit` | `unit` | ✅ Could map (box, pcs, etc.) |
| `weight` | `weight` | ✅ Could map (with weight_unit) |
| `height`, `width`, `length` | `dimensions` (jsonb) | ✅ Could map |
| `tax_percentage` | `tax_rate` | ✅ Could map |
| `tags` (array) | `tags` (array) | ✅ Could map |
| `image_document_id` | `image_url` | ❌ Need separate download (other script handles this) |
| `cf_c_digo_proveedor` | `supplier_reference` | ✅ Could map (custom field) |
| `cf_aro` | `specifications` (jsonb) | ✅ Could map (custom field) |

## 🚫 Fields We Have but Zoho Doesn't

| Our DB Field | Source | Notes |
|--------------|--------|-------|
| `barcode` | Manual input | Not in Zoho |
| `supplier_id` | FK to suppliers | Need separate lookup |
| `brand_id` | FK to product_brands | Need separate lookup |
| `color` | Product variant | Not in Zoho base |
| `size` | Product variant | Not in Zoho base |
| `material` | Product metadata | Not in Zoho base |
| `warranty_months` | Product metadata | Not in Zoho base |
| `serialized` | Tracking flag | Not in Zoho base |
| `lot_tracking` | Tracking flag | Not in Zoho base |

## 📝 Recommendations for Full Import

### Immediate Additions (Easy Wins):
```python
def map_zoho_to_supabase(zoho_product):
    return {
        # ... existing fields ...
        
        # ADD THESE:
        "unit": zoho_product.get("unit", "unit"),  # box, pcs, etc.
        "weight": float(zoho_product.get("weight", 0)) if zoho_product.get("weight") else 0,
        "tax_rate": float(zoho_product.get("tax_percentage", 0)),
        "tags": zoho_product.get("tags", []),
        "gtin": zoho_product.get("upc") or zoho_product.get("ean") or zoho_product.get("isbn") or "",
        "manufacturer_sku": zoho_product.get("part_number", ""),
        "supplier_reference": zoho_product.get("cf_c_digo_proveedor", ""),  # Custom field
        
        # Dimensions as JSONB
        "dimensions": {
            "length": zoho_product.get("length", ""),
            "width": zoho_product.get("width", ""),
            "height": zoho_product.get("height", ""),
            "unit": zoho_product.get("dimension_unit", "cm")
        } if any([zoho_product.get("length"), zoho_product.get("width"), zoho_product.get("height")]) else {},
        
        # Custom fields as specifications
        "specifications": {
            "aro": zoho_product.get("cf_aro", ""),
            "codigo_proveedor": zoho_product.get("cf_c_digo_proveedor", "")
        }
    }
```

### Needs Lookup (Harder):
- **Categories**: Need to match `category_name` from Zoho → find/create in our `product_categories` table → get `category_id`
- **Brands**: Already handled by text field, but could improve with `brand_id` lookup
- **Suppliers**: If `purchase_account_name` or custom fields contain supplier info

### Image Import (Separate Script):
The `zoho_to_supabase_import.py` already handles:
- Downloading images via `image_document_id`
- Uploading to Supabase Storage
- Setting `image_url` field

## ✅ Conclusion

**Current mapping is GOOD for basic product data:**
- ✅ Core fields (name, SKU, price, cost, stock)
- ✅ Stock management (min/max levels)
- ✅ Active status
- ✅ Timestamps

**Missing but easy to add:**
- Unit, weight, tax rate, tags, GTIN, dimensions
- Custom fields (código proveedor, aro)

**Complex (need lookup logic):**
- Categories, suppliers, brand_id

**Your call:** Do you want me to enhance the import script to include the "easy wins" fields?
