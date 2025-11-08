# Stock Movements Duplicate Adjustment Records Issue

## Problem

**Symptom:** Stock movements page shows multiple manual adjustment records with identical "Stock Final" values, despite different "+X" movements.

**Example from Production:**
- Product "Prueba1" shows 10+ adjustment records
- Each shows "+4" movement
- All show "Stock Final" = 5 (same value)
- References: ADJ-J-20251104-XXXXXX format

## Root Cause Analysis

### The Trigger

The `track_product_stock_changes()` trigger automatically creates `stock_adjustments` records whenever `products.stock_quantity` changes:

```sql
-- From core_schema.sql line 849
create or replace function track_product_stock_changes()
returns trigger as $$
begin
  -- Skip if flag is set (for invoice automation)
  if current_setting('app.skip_stock_adjustment_trigger', true) = 'true' then
    return NEW;
  end if;
  
  -- Track stock changes
  if (TG_OP = 'UPDATE' and OLD.stock_quantity <> NEW.stock_quantity) then
    insert into stock_adjustments (
      tenant_id,
      product_id,
      adjustment_type,
      quantity,
      stock_before,
      stock_after,
      reason,
      created_by
    ) values (
      NEW.tenant_id,
      NEW.id,
      'manual',
      NEW.stock_quantity - OLD.stock_quantity,
      OLD.stock_quantity,
      NEW.stock_quantity,
      'Manual adjustment via product form',
      auth.uid()
    );
  end if;
  
  return NEW;
end;
$$;
```

### The Issue

**Someone (or something) is repeatedly updating the product's `stock_quantity` back to the same value (5).**

Possible causes:
1. **Flutter UI saving product form multiple times** - When editing a product, if the form saves on every change, each save triggers the stock adjustment
2. **Realtime sync conflict** - Multiple browser tabs/users causing race conditions
3. **Import/sync process** - External data import repeatedly setting stock to same value
4. **Form auto-save** - Product edit form might have auto-save that triggers on every field change

## Evidence

Looking at the screenshot:
- All adjustments show `stock_after = 5`
- All adjustments show `quantity = +4`
- This means `stock_before = 1` every time
- Pattern: Stock goes 1→5, then something resets it to 1, then manual update to 5 again

**This is NOT invoice-related** because:
- Invoice functions set `app.skip_stock_adjustment_trigger = 'true'` (verified lines 3521, 6429)
- Adjustments show `adjustment_type = 'manual'` (from trigger line 869)
- Reference format is ADJ-J-... not sales_invoice: or purchase_invoice:

## Solution

### Option 1: Fix Product Form (Recommended)

**Check if product edit form is over-saving:**

```dart
// lib/modules/inventory/pages/product_form_page.dart or similar
// Look for:
- Multiple calls to saveProduct() on the same data
- Auto-save on field changes
- Realtime sync fighting with local state
```

**Fix:** Only save when user explicitly clicks "Guardar" button, not on every field change.

### Option 2: Improve Trigger Logic

**Make trigger smarter about what counts as "manual":**

```sql
-- Only create adjustment if change is significant (> 1 unit difference)
-- OR only during specific operations (not during bulk updates)

create or replace function track_product_stock_changes()
returns trigger as $$
begin
  if current_setting('app.skip_stock_adjustment_trigger', true) = 'true' then
    return NEW;
  end if;
  
  -- NEW: Skip if stock quantity is being set to the same value repeatedly
  -- This prevents duplicate adjustments from form re-saves
  if (TG_OP = 'UPDATE' and OLD.stock_quantity <> NEW.stock_quantity) then
    -- Only log if this is truly a new adjustment (not within last 5 minutes)
    if not exists (
      select 1 from stock_adjustments
      where product_id = NEW.id
        and stock_before = OLD.stock_quantity
        and stock_after = NEW.stock_quantity
        and created_at > now() - interval '5 minutes'
    ) then
      insert into stock_adjustments (
        tenant_id,
        product_id,
        adjustment_type,
        quantity,
        stock_before,
        stock_after,
        reason,
        created_by
      ) values (
        NEW.tenant_id,
        NEW.id,
        'manual',
        NEW.stock_quantity - OLD.stock_quantity,
        OLD.stock_quantity,
        NEW.stock_quantity,
        'Manual adjustment via product form',
        auth.uid()
      );
    end if;
  end if;
  
  return NEW;
end;
$$;
```

### Option 3: Remove Trigger Entirely (NOT Recommended)

**If manual stock tracking is not needed**, you could:
- Drop the `track_product_stock_changes` trigger
- Only rely on invoice-based stock movements
- Manually create adjustments through dedicated UI (not automatic)

**Downside:** Lose audit trail of manual stock changes via product form.

## Investigation Steps

1. **Check product form saves:**
   ```bash
   grep -r "saveProduct\|updateProduct" lib/modules/inventory/pages/
   ```

2. **Check for multiple saves in form:**
   ```dart
   // Look for patterns like:
   onChanged: (_) => _saveProduct()  // BAD: saves on every keystroke
   ```

3. **Query database for recent adjustments:**
   ```sql
   select 
     sa.created_at,
     sa.quantity,
     sa.stock_before,
     sa.stock_after,
     sa.reason,
     p.name
   from stock_adjustments sa
   join products p on sa.product_id = p.id
   where p.name = 'Prueba1'
   order by sa.created_at desc
   limit 20;
   ```

4. **Check for concurrent updates:**
   ```sql
   -- See if adjustments are clustered within seconds
   select 
     created_at,
     extract(epoch from (created_at - lag(created_at) over (order by created_at))) as seconds_since_last
   from stock_adjustments
   where product_id = (select id from products where name = 'Prueba1')
   order by created_at desc
   limit 20;
   ```

## Recommended Action

1. ✅ **First: Identify the source** - Use Supabase logs or add debug logging to product form
2. ✅ **Then: Fix the root cause** - Prevent repeated saves of unchanged data
3. ✅ **Finally: Add safeguard** - Implement Option 2's duplicate detection in trigger

## Testing Checklist

After fix:
- [ ] Edit product stock once → Only ONE adjustment record created
- [ ] Save product form multiple times without changes → No duplicate adjustments
- [ ] Create sales invoice → Stock decreases, NO manual adjustment record
- [ ] Create purchase invoice → Stock increases, NO manual adjustment record
- [ ] Manually adjust stock via dedicated UI → ONE adjustment record created

## Related Files

- `supabase/sql/core_schema.sql` (lines 849-908) - Track product stock changes trigger
- `lib/modules/inventory/pages/product_form_page.dart` (or similar) - Product edit form
- `lib/modules/inventory/services/stock_movements_service.dart` - Stock movements service
