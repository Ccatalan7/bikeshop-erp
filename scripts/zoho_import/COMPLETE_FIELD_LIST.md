# Complete Zoho Product Fields - All 58 Fields

## Full Zoho Product JSON Structure

```json
{
  "item_id": "3479156000004801014",
  "name": "25pcs Cubre Cámara Media Pista Goma",
  "item_name": "25pcs Cubre Cámara Media Pista Goma",
  "category_id": "3479156000001440167",
  "category_name": "Cubre Cámara",
  "unit": "box",
  "status": "active",
  "source": "user",
  "is_combo_product": false,
  "is_linked_with_zohocrm": false,
  "zcrm_product_id": "",
  "description": "",
  "brand": "",
  "manufacturer": "",
  "rate": 15000,
  "tax_id": "",
  "tax_name": "",
  "tax_percentage": 0,
  "purchase_account_id": "3479156000000034003",
  "purchase_account_name": "Costes de productos vendidos",
  "account_id": "3479156000000000388",
  "account_name": "Ventas",
  "purchase_description": "",
  "purchase_rate": 6119,
  "can_be_sold": true,
  "can_be_purchased": true,
  "track_inventory": true,
  "item_type": "inventory",
  "product_type": "goods",
  "stock_on_hand": 2.0,
  "has_attachment": true,
  "is_returnable": true,
  "available_stock": 2.0,
  "actual_available_stock": 2.0,
  "sku": "A02776019313A",
  "upc": "",
  "ean": "",
  "isbn": "",
  "part_number": "",
  "reorder_level": 0.0,
  "image_name": "19313.jpg",
  "image_type": "jpg",
  "image_document_id": "3479156000004801021",
  "created_time": "2025-05-15T13:44:25-0400",
  "last_modified_time": "2025-05-15T15:00:20-0400",
  "cf_c_digo_proveedor": "19313",
  "cf_c_digo_proveedor_unformatted": "19313",
  "cf_aro": "700",
  "cf_aro_unformatted": "700",
  "length": "",
  "width": "",
  "height": "",
  "weight": "",
  "weight_unit": "kg",
  "dimension_unit": "cm",
  "dimensions_with_unit": "",
  "weight_with_unit": "",
  "tags": []
}
```

---

# Detailed Field-by-Field Mapping

## 1. CORE IDENTIFICATION (5 fields)

| # | Zoho Field | Type | Our Field | Mapped? | Notes |
|---|------------|------|-----------|---------|-------|
| 1 | `item_id` | string | - | ❌ No | Zoho internal ID (not needed) |
| 2 | `name` | string | `name` | ✅ Yes | Product name |
| 3 | `item_name` | string | `name` | ✅ Yes | Duplicate of `name` (fallback) |
| 4 | `sku` | string | `sku` | ✅ Yes | Unique product code |
| 5 | `item_type` | string | - | ❌ No | Always "inventory" (not useful) |

---

## 2. PRICING (8 fields)

| # | Zoho Field | Type | Our Field | Mapped? | Notes |
|---|------------|------|-----------|---------|-------|
| 6 | `rate` | number | `price` | ✅ Yes | Selling price |
| 7 | `purchase_rate` | number | `cost` | ✅ Yes | Cost price |
| 8 | `tax_id` | string | - | ❌ No | Zoho tax ID (not useful) |
| 9 | `tax_name` | string | - | ❌ No | Tax name (e.g., "IVA") |
| 10 | `tax_percentage` | number | `tax_rate` | ⚠️ **Should Map** | Tax rate (0, 19, etc.) |
| 11 | `account_id` | string | - | ❌ No | Zoho sales account ID |
| 12 | `account_name` | string | - | ❌ No | "Ventas" (not needed) |
| 13 | `purchase_account_id` | string | - | ❌ No | Zoho purchase account ID |
| 14 | `purchase_account_name` | string | - | ❌ No | "Costes de productos..." |

---

## 3. INVENTORY (10 fields)

| # | Zoho Field | Type | Our Field | Mapped? | Notes |
|---|------------|------|-----------|---------|-------|
| 15 | `stock_on_hand` | number | `stock_quantity` | ✅ Yes | Current stock |
| 16 | `stock_on_hand` | number | `inventory_qty` | ✅ Yes | Same (both columns) |
| 17 | `available_stock` | number | - | ❌ No | Same as stock_on_hand |
| 18 | `actual_available_stock` | number | - | ❌ No | Same as stock_on_hand |
| 19 | `reorder_level` | number | `min_stock_level` | ✅ Yes | Minimum stock |
| 20 | `reorder_level * 3` | calc | `max_stock_level` | ✅ Yes | Calculated max |
| 21 | `track_inventory` | boolean | `track_stock` | ⚠️ **Should Map** | Whether to track stock |
| 22 | `unit` | string | `unit` | ⚠️ **Should Map** | "box", "pcs", "unit" |
| 23 | `can_be_sold` | boolean | - | ❌ No | Always true (not useful) |
| 24 | `can_be_purchased` | boolean | - | ❌ No | Always true (not useful) |

---

## 4. CATEGORIZATION (4 fields)

| # | Zoho Field | Type | Our Field | Mapped? | Notes |
|---|------------|------|-----------|---------|-------|
| 25 | `category_id` | string | - | ❌ No | Zoho category ID (different system) |
| 26 | `category_name` | string | `category_name` | ⚠️ **Could Map** | "Cubre Cámara" (need lookup for category_id) |
| 27 | `brand` | string | `brand` | ✅ Yes | Brand name |
| 28 | `manufacturer` | string | `manufacturer` | ⚠️ **Could Map** | Usually empty |

---

## 5. PRODUCT CODES (5 fields)

| # | Zoho Field | Type | Our Field | Mapped? | Notes |
|---|------------|------|-----------|---------|-------|
| 29 | `upc` | string | `gtin` | ⚠️ **Should Map** | Universal Product Code |
| 30 | `ean` | string | `gtin` | ⚠️ **Should Map** | European Article Number |
| 31 | `isbn` | string | `gtin` | ⚠️ **Should Map** | For books (rare in bike shop) |
| 32 | `part_number` | string | `manufacturer_sku` | ⚠️ **Should Map** | Manufacturer part number |
| 33 | `hs_code` | string | `hs_code` | ⚠️ **Could Map** | Harmonized System code (customs) |

---

## 6. DIMENSIONS & WEIGHT (8 fields)

| # | Zoho Field | Type | Our Field | Mapped? | Notes |
|---|------------|------|-----------|---------|-------|
| 34 | `length` | string | `dimensions.length` | ⚠️ **Should Map** | Length in cm |
| 35 | `width` | string | `dimensions.width` | ⚠️ **Should Map** | Width in cm |
| 36 | `height` | string | `dimensions.height` | ⚠️ **Should Map** | Height in cm |
| 37 | `dimension_unit` | string | `dimensions.unit` | ⚠️ **Should Map** | "cm" usually |
| 38 | `dimensions_with_unit` | string | - | ❌ No | Formatted string (not needed) |
| 39 | `weight` | string | `weight` | ⚠️ **Should Map** | Weight value |
| 40 | `weight_unit` | string | - | ⚠️ **Should Map** | "kg" usually (store in dimensions?) |
| 41 | `weight_with_unit` | string | - | ❌ No | Formatted string (not needed) |

---

## 7. IMAGES (4 fields)

| # | Zoho Field | Type | Our Field | Mapped? | Notes |
|---|------------|------|-----------|---------|-------|
| 42 | `image_name` | string | - | ❌ No | Filename "19313.jpg" |
| 43 | `image_type` | string | - | ❌ No | Extension "jpg" |
| 44 | `image_document_id` | string | - | ❌ No | Used to download (other script) |
| 45 | `has_attachment` | boolean | - | ❌ No | Whether has image |

---

## 8. STATUS & FLAGS (5 fields)

| # | Zoho Field | Type | Our Field | Mapped? | Notes |
|---|------------|------|-----------|---------|-------|
| 46 | `status` | string | `is_active` | ✅ Yes | "active" → true |
| 47 | `product_type` | string | `product_type` | ⚠️ **Could Map** | "goods" or "service" |
| 48 | `is_returnable` | boolean | - | ❌ No | Always true (not useful) |
| 49 | `is_combo_product` | boolean | - | ❌ No | Bundle product flag |
| 50 | `source` | string | - | ❌ No | "user" (not useful) |

---

## 9. EXTERNAL INTEGRATIONS (2 fields)

| # | Zoho Field | Type | Our Field | Mapped? | Notes |
|---|------------|------|-----------|---------|-------|
| 51 | `is_linked_with_zohocrm` | boolean | - | ❌ No | CRM integration |
| 52 | `zcrm_product_id` | string | - | ❌ No | Zoho CRM ID |

---

## 10. DESCRIPTIONS (2 fields)

| # | Zoho Field | Type | Our Field | Mapped? | Notes |
|---|------------|------|-----------|---------|-------|
| 53 | `description` | string | `description` | ✅ Yes | Usually empty |
| 54 | `purchase_description` | string | - | ❌ No | Purchase notes (usually empty) |

---

## 11. TIMESTAMPS (2 fields)

| # | Zoho Field | Type | Our Field | Mapped? | Notes |
|---|------------|------|-----------|---------|-------|
| 55 | `created_time` | string | `created_at` | ✅ Yes | ISO timestamp |
| 56 | `last_modified_time` | string | `updated_at` | ✅ Yes | ISO timestamp |

---

## 12. CUSTOM FIELDS (4 fields)

| # | Zoho Field | Type | Our Field | Mapped? | Notes |
|---|------------|------|-----------|---------|-------|
| 57 | `cf_c_digo_proveedor` | string | `supplier_reference` | ⚠️ **Should Map** | Supplier code |
| 58 | `cf_c_digo_proveedor_unformatted` | string | - | ❌ No | Duplicate |
| 59 | `cf_aro` | string | `specifications.aro` | ⚠️ **Should Map** | Wheel size (700, 26, etc.) |
| 60 | `cf_aro_unformatted` | string | - | ❌ No | Duplicate |

---

## 13. TAGS (1 field)

| # | Zoho Field | Type | Our Field | Mapped? | Notes |
|---|------------|------|-----------|---------|-------|
| 61 | `tags` | array | `tags` | ⚠️ **Should Map** | Product tags array |

---

# SUMMARY

## ✅ Currently Mapped (12 fields)
- name, sku, price, cost, stock_quantity, inventory_qty, min_stock_level, max_stock_level, brand, is_active, created_at, updated_at

## ⚠️ SHOULD Map (High Priority - 15 fields)
1. `tax_percentage` → `tax_rate` ⭐
2. `track_inventory` → `track_stock` ⭐
3. `unit` → `unit` ⭐
4. `upc`/`ean`/`isbn` → `gtin` ⭐
5. `part_number` → `manufacturer_sku` ⭐
6. `length` → `dimensions.length` ⭐
7. `width` → `dimensions.width` ⭐
8. `height` → `dimensions.height` ⭐
9. `dimension_unit` → `dimensions.unit` ⭐
10. `weight` → `weight` ⭐
11. `weight_unit` → (store in dimensions jsonb) ⭐
12. `cf_c_digo_proveedor` → `supplier_reference` ⭐
13. `cf_aro` → `specifications.aro` ⭐
14. `tags` → `tags` ⭐
15. `product_type` → `product_type` ⭐

## 🤔 Could Map (Optional - 4 fields)
- `category_name` → `category_name` (need lookup for category_id)
- `manufacturer` → `manufacturer` (usually empty)
- `hs_code` → `hs_code` (for customs/imports)

## ❌ Don't Need (30 fields)
- Zoho internal IDs, account names, formatted strings, duplicates, CRM fields, always-true booleans

---

# YOUR DECISION NEEDED 🎯

**Which of the 15 "SHOULD Map" fields do you want me to add?**

All of them? Some? Just the critical ones (tax, unit, dimensions, custom fields)?
