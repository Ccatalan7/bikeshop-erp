# 🔧 PEGA ↔ INVOICE BIDIRECTIONAL SYNC FIX# 🔧 Pega ↔ Invoice Bi-Directional Sync Fix



## 🐛 Problem## 🚨 Problem Identified



The **bidirectional sync** between **pegas (mechanic jobs)** and **sales invoices** was broken after multi-tenant migration:The Pega (mechanic_job) and Invoice (sales_invoices) relationship was **one-way only**:

- ✅ Creating invoice from pega worked

### What Used to Work:- ❌ Changing invoice status → Pega didn't update

1. ✅ **Create pega with products** → Draft invoice created with those items- ❌ Modifying invoice items → Pega items didn't sync

2. ✅ **Edit invoice (add/remove products)** → Pega updated to reflect changes- ❌ Deleting invoice → Pega still showed "invoiced"

3. ✅ **Edit pega (add/remove items)** → Invoice updated to reflect changes- ❌ Adding/removing products in pega → Invoice didn't update



### What Was Broken:**Root cause:** No database triggers to maintain the relationship when invoice changes!

- ❌ **Invoice → Pega sync was failing** when editing an invoice

- ✅ **Pega → Invoice sync was still working** (one direction only)---



## 🔍 Root Cause## ✅ Solution Implemented



The `sync_invoice_items_to_job()` function (triggered when invoice is updated) was **missing `tenant_id`** in all INSERT statements:### 1. **New Database Functions in `core_schema.sql`:**



### Location: `supabase/sql/core_schema.sql` (lines 7171-7350)#### `sync_invoice_items_to_job(p_invoice_id)`

- **Purpose:** Syncs invoice items back to `mechanic_job_items`

**Missing tenant_id in:**- **When called:** Every time invoice is created or updated

1. ❌ INSERT into `mechanic_job_labor` (line ~7237) - for labor items without product_id- **What it does:**

2. ❌ INSERT into `mechanic_job_labor` (line ~7272) - for service product items  - Deletes old job items

3. ❌ INSERT into `mechanic_job_items` (line ~7306) - for physical parts  - Recreates them from invoice.items jsonb

  - Separates labor vs parts

### Why This Broke Sync:  - Updates job costs (labor_cost, parts_cost, total_cost, tax_amount)



When you edit an invoice in the UI and save it:#### `sync_invoice_status_to_job(p_invoice_id)`

1. Flutter calls `SalesService.saveInvoice()` → updates `sales_invoices` table- **Purpose:** Syncs invoice status & payment to job flags

2. Database trigger `trg_sales_invoices_change` fires- **When called:** Every time invoice status or payments change

3. Trigger calls `sync_invoice_items_to_job(p_invoice_id)`- **What it does:**

4. Function deletes all existing job items/labor  - Updates `mechanic_jobs.is_paid` based on invoice.status = 'paid'

5. Function attempts to INSERT new items from invoice  - Updates `mechanic_jobs.is_invoiced` = true

6. ❌ **INSERT fails** because RLS policies require `tenant_id`  - Keeps pega UI in sync with invoice reality

7. ❌ **Pega items remain empty** (deleted but not recreated)

#### `handle_invoice_deleted_for_job()`

## ✅ Solution- **Purpose:** Clears job reference when invoice is deleted

- **When called:** BEFORE invoice deletion (trigger)

Updated `sync_invoice_items_to_job()` function to include `tenant_id` in all INSERT statements:- **What it does:**

  - Sets `mechanic_jobs.invoice_id` = null

### Changes Made (5 locations in `core_schema.sql`):  - Sets `is_invoiced` = false, `is_paid` = false

  - Allows creating a new invoice for the pega

**1. Added `v_tenant_id` variable:**

```sql---

declare

  v_job_id uuid;### 2. **Updated Existing Functions:**

  v_invoice record;

  v_tenant_id uuid;  -- ⚠️ ADDED#### `handle_sales_invoice_change()`

  -- ... other variables**Added sync calls:**

begin```sql

```-- After INSERT:

perform public.sync_invoice_items_to_job(NEW.id);

**2. Get tenant_id from invoice:**perform public.sync_invoice_status_to_job(NEW.id);

```sql

-- Get invoice details-- After UPDATE:

select * into v_invoiceperform public.sync_invoice_items_to_job(NEW.id);

from sales_invoicesperform public.sync_invoice_status_to_job(NEW.id);

where id = p_invoice_id;```



-- Get tenant_id from invoice#### `recalculate_sales_invoice_payments()`

v_tenant_id := v_invoice.tenant_id;  -- ⚠️ ADDED**Replaced manual update with sync function:**

``````sql

-- OLD (manual update):

**3. Fixed INSERT into mechanic_job_labor (labor items without product_id):**update mechanic_jobs set is_paid = ... where invoice_id = ...

```sql

insert into mechanic_job_labor (-- NEW (uses sync function):

  tenant_id,           -- ⚠️ ADDEDperform public.sync_invoice_status_to_job(p_invoice_id);

  job_id,```

  technician_name,

  description,---

  hours_worked,

  hourly_rate,### 3. **New Trigger:**

  total_cost,

  service_product_id,```sql

  work_date,create trigger trg_invoice_deleted_clear_job

  created_at,  before delete on sales_invoices

  updated_at  for each row execute procedure public.handle_invoice_deleted_for_job();

) values (```

  v_tenant_id,         -- ⚠️ ADDED

  v_job_id,---

  'Factura',

  v_product_name,## 🔄 Complete Sync Flow

  -- ... other values

);### **Pega → Invoice (Already Working)**

```1. User adds products/services to pega

2. Clicks "Create Invoice"

**4. Fixed INSERT into mechanic_job_labor (service product items):**3. `create_invoice_from_mechanic_job()` runs

```sql4. Invoice created with all items

insert into mechanic_job_labor (5. `mechanic_jobs.invoice_id` is set

  tenant_id,           -- ⚠️ ADDED

  job_id,### **Invoice → Pega (NOW FIXED!)**

  -- ... other columns

) values (#### **Invoice Status Changes:**

  v_tenant_id,         -- ⚠️ ADDED```

  v_job_id,Draft → Sent → Confirmed → Paid

  -- ... other values         ↓         ↓          ↓

);      Updates pega flags each time

``````



**5. Fixed INSERT into mechanic_job_items (physical parts):**Every status change:

```sql1. `handle_sales_invoice_change()` trigger fires

insert into mechanic_job_items (2. Calls `sync_invoice_status_to_job()`

  tenant_id,           -- ⚠️ ADDED3. Updates `is_paid` flag in pega

  job_id,4. Pega UI shows correct payment status

  product_id,

  product_name,#### **Invoice Items Modified:**

  quantity,```

  unit_price,Add product to invoice

  notes,    ↓

  created_at,Sync to mechanic_job_items

  updated_at    ↓

) values (Pega details show new product

  v_tenant_id,         -- ⚠️ ADDED```

  v_job_id,

  v_product_id,Every invoice update:

  -- ... other values1. `handle_sales_invoice_change()` trigger fires

);2. Calls `sync_invoice_items_to_job()`

```3. Deletes old job items

4. Recreates from invoice.items

## 📋 Deployment Steps5. Recalculates costs (parts, labor, tax, total)



1. **Deploy the updated schema:**#### **Invoice Deleted:**

   - Open Supabase Dashboard → SQL Editor```

   - Copy the entire `supabase/sql/core_schema.sql` fileDelete invoice

   - Execute in SQL Editor    ↓

   - Or deploy via migration scriptClear pega reference

    ↓

2. **Restart Flutter app** (to clear any cached data)User can create new invoice

```

3. **Test the sync** (see verification checklist below)

Before deletion:

## 🔄 How Bidirectional Sync Works1. `trg_invoice_deleted_clear_job` trigger fires

2. Clears `mechanic_jobs.invoice_id`

### Invoice → Pega Sync (Now Fixed ✅)3. Sets `is_invoiced = false`, `is_paid = false`

4. Pega shows "Crear" button again

**Trigger:** `trg_sales_invoices_change` on `sales_invoices` table  

**Function:** `handle_sales_invoice_change()` (lines 2928-3065)  ---

**Called:** `sync_invoice_items_to_job(NEW.id)` (lines 2972, 3031)

## 🧪 Testing Scenarios

**What it does:**

1. Finds the linked pega via `mechanic_jobs.invoice_id`### **Scenario 1: Status Flow Test**

2. Sets sync flag to prevent circular updates1. Create pega with products

3. Deletes all existing job items and labor2. Create invoice (status = draft)

4. Recreates them from invoice.items JSONB array3. **Check:** Pega shows invoice link ✅

5. Detects product type (part vs service) and creates appropriate records4. Change invoice to "Sent"

6. Recalculates job costs5. **Check:** Pega still shows link ✅

7. Clears sync flag6. Change invoice to "Confirmed"

7. **Check:** Pega still shows link ✅

### Pega → Invoice Sync (Already Working ✅)8. Add payment → status = "Paid"

9. **Check:** Pega shows `is_paid = true` ✅

**Trigger:** `trg_mechanic_job_items_sync_invoice_insert/update/delete` on `mechanic_job_items`  

**Function:** `sync_job_items_to_invoice_statement()` (lines 8217-8258)  ### **Scenario 2: Item Modification Test**

**Called:** `sync_job_to_invoice(v_job_id)` (line 8253)1. Create pega with 2 products

2. Create invoice

**What it does:**3. Go to invoice detail

1. Checks sync flag (skip if invoice→job sync in progress)4. Add 1 more product

2. Recalculates job costs from database5. **Check:** Pega details now show 3 products ✅

3. Finds the linked invoice via `mechanic_jobs.invoice_id`6. Remove 1 product from invoice

4. Builds invoice items array from job items and labor7. **Check:** Pega details now show 2 products ✅

5. Calculates subtotal, IVA, total

6. Updates the invoice with new items and totals### **Scenario 3: Invoice Deletion Test**

1. Create pega

### Circular Sync Prevention2. Create invoice

3. Delete invoice

Both functions use transaction-level flags:4. **Check:** Pega "Factura/Pago" column shows "Crear" button ✅

5. **Check:** Pega detail doesn't show invoice link ✅

```sql6. Create new invoice

-- Invoice→Job sets this flag before making changes7. **Check:** New invoice links correctly ✅

perform set_config('app.syncing_invoice_to_job', 'true', true);

### **Scenario 4: Payment Toggle Test**

-- Job→Invoice checks this flag and skips if true1. Create pega → invoice (draft)

v_syncing_flag := current_setting('app.syncing_invoice_to_job', true);2. Go back and forth: Draft ↔ Confirmed ↔ Paid

if v_syncing_flag = 'true' then3. **Check:** Pega `is_paid` toggles correctly ✅

  return;  -- Skip to prevent circular sync4. **Check:** Invoice link never breaks ✅

end if;

```---



Also checks trigger depth:## 📋 Deployment Checklist

```sql

if pg_trigger_depth() > 2 then### **To Deploy:**

  raise notice 'trigger depth too deep, skipping';

  return;1. **Stop any running instances** (optional but recommended)

end if;

```2. **Deploy the updated `core_schema.sql`:**

   ```sql

## ✅ Verification Checklist   -- Run in Supabase SQL Editor:

   -- Copy entire contents of supabase/sql/core_schema.sql

After deployment, test these scenarios:   -- Paste and execute

   ```

**Basic Sync:**

- [ ] Create pega with 2 products → Draft invoice has 2 items ✅3. **Verify triggers created:**

- [ ] Edit invoice, add 1 product → Pega now has 3 items ✅   ```sql

- [ ] Edit invoice, remove 1 product → Pega now has 2 items ✅   SELECT trigger_name, event_manipulation, event_object_table

- [ ] Edit pega, add 1 labor → Invoice now has 3 items ✅   FROM information_schema.triggers

- [ ] Edit pega, remove 1 product → Invoice now has 2 items ✅   WHERE trigger_name LIKE '%invoice%job%'

   ORDER BY event_object_table, trigger_name;

**Totals:**   ```

- [ ] Verify parts_cost matches on both sides ✅

- [ ] Verify labor_cost matches on both sides ✅   **Expected output:**

- [ ] Verify subtotal = parts + labor - discount ✅   - `trg_invoice_deleted_clear_job` on `sales_invoices`

- [ ] Verify total = subtotal + IVA ✅

4. **Test the sync functions manually:**

**Edge Cases:**   ```sql

- [ ] Create pega with service product → Appears as labor in pega ✅   -- Test 1: Find a job with invoice

- [ ] Edit invoice, change quantity → Pega quantity updates ✅   SELECT id, job_number, invoice_id, is_paid

- [ ] Edit invoice, change price → Pega price updates ✅   FROM mechanic_jobs

- [ ] Multiple rapid edits → No circular sync loops ✅   WHERE invoice_id IS NOT NULL

   LIMIT 1;

**Multi-Tenant Isolation:**

- [ ] Pega from tenant A doesn't sync to invoice from tenant B ✅   -- Test 2: Sync status

- [ ] All synced items include correct tenant_id ✅   SELECT sync_invoice_status_to_job('[invoice_id_from_above]');



## 📚 Related Functions   -- Test 3: Sync items

   SELECT sync_invoice_items_to_job('[invoice_id_from_above]');

**Sync functions:**   ```

- `sync_invoice_items_to_job()` (lines 7171-7350) - Invoice → Pega ✅ FIXED

- `sync_job_to_invoice()` (lines 7434-7554) - Pega → Invoice ✅5. **Test in the app:**

- `sync_invoice_status_to_job()` (lines 7353-7423) - Invoice status → Job status ✅   - Create a test pega

   - Create invoice from it

**Job calculation functions:**   - Modify invoice status

- `recalculate_mechanic_job_costs()` - Recalculates totals from items/labor   - Check pega updates

- `create_invoice_from_mechanic_job()` (lines 6972-7168) - Initial invoice creation   - Modify invoice items

   - Check pega items update

**Triggers:**   - Delete invoice

- `trg_sales_invoices_change` - Fires on invoice INSERT/UPDATE/DELETE   - Check pega clears reference

- `trg_mechanic_job_items_sync_invoice_insert/update/delete` - Fires on job items changes

- `trg_mechanic_job_labor_sync_invoice_insert/update/delete` - Fires on labor changes---



## 🧠 Key Takeaways## 🔍 Monitoring & Debugging



**When ANY database function creates records, it MUST include `tenant_id`:**### **Check Sync Status:**

```sql

1. ✅ Add `v_tenant_id uuid;` to function variables-- Find pegas with invoices

2. ✅ Get tenant_id from parameter or existing recordSELECT 

3. ✅ Include `tenant_id` column in ALL INSERT statements  mj.job_number,

4. ✅ Test with actual user (not service role in SQL Editor)  mj.invoice_id,

5. ✅ Redeploy schema after function fixes  mj.is_invoiced,

6. ✅ Restart Flutter app after deployment  mj.is_paid,

  si.invoice_number,

**Common mistakes to avoid:**  si.status,

- ❌ Assuming function doesn't need tenant_id (ALL tables need it)  si.total

- ❌ Testing in SQL Editor as service role (bypasses RLS)FROM mechanic_jobs mj

- ❌ Not restarting app after schema changesLEFT JOIN sales_invoices si ON si.id = mj.invoice_id

- ❌ Not checking ALL INSERT statements in a functionWHERE mj.invoice_id IS NOT NULL;

```

**See also:**

- `.github/copilot-instructions.md` → "TROUBLESHOOTING: MULTI-TENANT ISSUES"### **Check for Orphaned References:**

- `MASTER_INVOICE_FLOW_REFERENCE.md` → Invoice trigger architecture```sql

-- Pegas pointing to deleted invoices

---SELECT 

  mj.job_number,

**Issue:** Pega ↔ Invoice bidirectional sync broken    mj.invoice_id,

**Root cause:** Missing `tenant_id` in `sync_invoice_items_to_job()` INSERT statements    mj.is_invoiced

**Solution:** Added `v_tenant_id` variable and included in all 3 INSERT locations  FROM mechanic_jobs mj

**Files modified:** `supabase/sql/core_schema.sql` (lines 7171-7350)  WHERE mj.invoice_id IS NOT NULL

**Fixed by:** GitHub Copilot    AND NOT EXISTS (

**Date:** 2025-10-28      SELECT 1 FROM sales_invoices si WHERE si.id = mj.invoice_id

**Status:** ✅ READY FOR DEPLOYMENT  );

```

### **Verify Item Sync:**
```sql
-- Compare invoice items vs job items
SELECT 
  si.invoice_number,
  jsonb_array_length(si.items) as invoice_items_count,
  (SELECT COUNT(*) FROM mechanic_job_items WHERE job_id = mj.id) as job_items_count
FROM sales_invoices si
JOIN mechanic_jobs mj ON mj.invoice_id = si.id;
```

---

## 🚀 What's Next?

### **Recommended Enhancements:**

1. **Add validation:**
   - Prevent invoice deletion if pega status is "ENTREGADO"
   - Warn before unlinking invoice from pega

2. **Add audit trail:**
   - Log when sync functions run
   - Track item changes in timeline

3. **Add UI indicators:**
   - Show last sync timestamp
   - Visual indicator if data is out of sync

4. **Add sync button (manual):**
   - Allow user to force sync if needed
   - Useful for debugging

---

## ⚠️ Important Notes

### **Data Integrity:**
- Sync is **one-way**: Invoice → Pega
- If you modify pega items directly in DB, invoice won't update automatically
- Always modify through the invoice UI for proper sync

### **Performance:**
- Sync functions run on EVERY invoice update
- For large invoices (50+ items), may cause slight delay
- Monitor performance in production

### **Breaking Changes:**
- ❌ None! All changes are additive
- ✅ Existing data remains intact
- ✅ Existing invoices will sync on next update

---

## 🎉 Expected Outcomes

After deployment:

✅ **Invoice status changes immediately reflect in pega**  
✅ **Adding/removing products in invoice updates pega items**  
✅ **Deleting invoice properly clears pega reference**  
✅ **Payment status syncs correctly (is_paid flag)**  
✅ **No more "ghost" invoice references**  
✅ **Users can recreate invoices after deletion**  
✅ **Costs stay in sync (parts_cost, labor_cost, total_cost)**  

---

**Last Updated:** October 17, 2025  
**Status:** ✅ Ready for Deployment  
**Risk Level:** 🟢 Low (additive changes only)
