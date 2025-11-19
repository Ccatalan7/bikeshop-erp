# Simplify Pega Items - Remove Labor/Items Split

## Problem
- Unnecessary distinction between `mechanic_job_items` and `mechanic_job_labor`
- Hourly rate logic that nobody uses (services are fixed price)
- Complex trigger chains that fail during cascade deletes
- Confusing UX with separate "Products" and "Services" sections

## Solution
**Everything becomes a simple line item in `mechanic_job_items`:**

### Item Types
```typescript
type JobItem = {
  id: uuid;
  job_id: uuid;
  product_id?: uuid;  // NULL for ad-hoc/custom items
  product_name: string;
  quantity: number;
  unit_price: number;
  total_price: number;
  item_type: 'product' | 'service' | 'adhoc';  // NEW: Track what kind of item
  notes?: string;
}
```

### Migration Steps

1. **Add `item_type` column to mechanic_job_items**
```sql
ALTER TABLE mechanic_job_items 
  ADD COLUMN IF NOT EXISTS item_type text 
  CHECK (item_type IN ('product', 'service', 'adhoc')) 
  DEFAULT 'product';
```

2. **Migrate existing labor to items**
```sql
INSERT INTO mechanic_job_items (
  tenant_id,
  job_id,
  product_id,
  product_name,
  quantity,
  unit_price,
  total_price,
  item_type
)
SELECT 
  tenant_id,
  job_id,
  service_product_id,
  COALESCE(description, 'Servicio'),
  1,
  total_cost,
  total_cost,
  'service'
FROM mechanic_job_labor;
```

3. **Drop labor table and related triggers**
```sql
DROP TABLE mechanic_job_labor CASCADE;
```

4. **Update Flutter models**
- Remove `MechanicJobLabor` model
- Add `itemType` field to `MechanicJobItem` model
- Remove `BikeshopService.createJobLabor()` 
- Remove `BikeshopService.deleteJobLabor()`
- Everything uses `createJobItem()` / `deleteJobItem()`

5. **Simplify UI**
- Single "+ Add Item" button (no separate Products/Services)
- Item picker shows all: products (with stock), services (fixed price), or ad-hoc (custom)
- Tasks tab shows unified list of items with subtasks underneath

6. **Simplify triggers**
- Remove all `mechanic_job_labor` triggers
- Single cost calculation: `SUM(mechanic_job_items.total_price)`
- Single invoice sync: Build invoice from `mechanic_job_items` only

## Benefits
- ✅ Simpler data model (1 table instead of 2)
- ✅ No hourly rate confusion (everything is fixed price)
- ✅ Easier cascade deletes (fewer tables to worry about)
- ✅ Cleaner UX (one unified list)
- ✅ Easier invoice sync (one source of truth)
- ✅ Less trigger depth (fewer cascades)

## What About Products with Stock?
- Still tracked via `product_id` link
- When `item_type = 'product'` AND `product_id IS NOT NULL` → track stock
- When `item_type = 'service'` OR `product_id IS NULL` → no stock tracking

## What About Services from Product Catalog?
- Services are products with `product_type = 'service'`
- When added to pega: `item_type = 'service'`, `product_id = service.id`
- No stock deduction, just price

## Migration Timeline
1. **Deploy schema changes** (add column, migrate data)
2. **Update Flutter code** (remove labor references)
3. **Test thoroughly** (create/edit/delete pegas)
4. **Drop labor table** (after confirming everything works)
