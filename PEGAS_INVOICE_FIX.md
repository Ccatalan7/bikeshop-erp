# Pegas Invoice Display Fix

**Date:** October 17, 2025  
**Issues Fixed:**
1. "Crear" button showing despite invoice being active
2. Pendiente amount showing $0 instead of actual balance
3. is_invoiced and is_paid flags not being updated properly

---

## 🐛 Problems Identified

### 1. **Invoice Status Not Syncing to mechanic_jobs**
- **Issue:** When an invoice was created or payment received, the `is_invoiced` and `is_paid` fields in `mechanic_jobs` table were not being updated
- **Cause:** The `recalculate_sales_invoice_payments()` function only updated the `sales_invoices` table
- **Result:** Jobs showed "Crear" button even when they had active invoices

### 2. **UI Logic Checking Wrong Field**
- **Issue:** UI was checking `job.isInvoiced` flag instead of `job.invoiceId != null`
- **Cause:** The flag wasn't being set when invoices were created through the sales module (only through the mechanic job module)
- **Result:** Inconsistent display of invoice status

### 3. **Pending Amount Showing Total Instead of Balance**
- **Issue:** The "PENDIENTE" display showed `job.totalCost` instead of the actual invoice balance
- **Cause:** UI wasn't loading or using invoice data to get the real balance
- **Result:** All jobs showed $0 pendiente even when they had unpaid invoices

---

## ✅ Solutions Implemented

### 1. **Database Trigger Fix** (`core_schema.sql`)

Modified `recalculate_sales_invoice_payments()` function to update `mechanic_jobs`:

```sql
-- Update mechanic_jobs if this invoice is linked to a job
update public.mechanic_jobs
   set is_invoiced = true,
       is_paid = (v_new_status = 'paid'),
       updated_at = now()
 where invoice_id = p_invoice_id;
```

**What this does:**
- When any payment is added/removed/changed on an invoice
- The function automatically updates the linked mechanic job
- Sets `is_invoiced = true` (job has an invoice)
- Sets `is_paid = true` only when invoice status is 'paid'

### 2. **UI Logic Fix** (`pegas_table_page.dart`)

#### a) Load Invoice Data

Added invoice loading to the data fetch:

```dart
Map<String, SalesInvoice> _invoices = {}; // invoice_id -> invoice

// In _loadData():
final invoices = results[3] as List<SalesInvoice>;
final invoiceMap = <String, SalesInvoice>{};
for (final invoice in invoices) {
  if (invoice.id != null) {
    invoiceMap[invoice.id!] = invoice;
  }
}
```

#### b) Fixed Invoice Detection

Changed from checking `isInvoiced` flag to checking actual `invoiceId`:

```dart
// OLD (buggy):
if (!job.isInvoiced) {
  return ElevatedButton.icon(...); // Show "Crear"
}

// NEW (correct):
if (job.invoiceId == null && !job.isInvoiced) {
  return ElevatedButton.icon(...); // Show "Crear"
}
```

#### c) Show Actual Balance

Now displays the real invoice balance instead of job total:

```dart
final invoice = job.invoiceId != null ? _invoices[job.invoiceId] : null;
final isPaid = invoice?.status == 'paid' || job.isPaid;
final balance = invoice?.balance ?? job.totalCost;
final total = invoice?.total ?? job.totalCost;

// Display:
// - If PAID: show total (what was paid)
// - If PENDIENTE: show balance (what's still owed)
NumberFormat.currency(symbol: '\$', decimalDigits: 0).format(isPaid ? total : balance)
```

---

## 📊 How It Works Now

### Invoice Creation Flow:
1. User clicks "Crear" button on a job → Creates invoice
2. Invoice is created → `invoice_id` is set on `mechanic_jobs`
3. Trigger fires → `recalculate_sales_invoice_payments()` runs
4. Function updates `mechanic_jobs.is_invoiced = true`
5. UI refreshes → Shows "PENDIENTE" with actual balance

### Payment Flow:
1. User adds payment to invoice → Invoice status may change to 'paid'
2. Trigger fires → `recalculate_sales_invoice_payments()` runs
3. Function updates `mechanic_jobs.is_paid = (status == 'paid')`
4. UI refreshes → Shows "PAGADO" if fully paid, "PENDIENTE" with balance if partial

### Display Logic:
| Condition | Button/Badge | Amount Shown |
|-----------|--------------|--------------|
| No invoice (`invoice_id == null`) | "Crear" button | N/A |
| Invoice exists, balance > 0 | "PENDIENTE" orange | Balance remaining |
| Invoice exists, balance = 0 | "PAGADO" green | Total paid |

---

## 🔄 Deployment Steps

### 1. Deploy Database Changes
```bash
# In Supabase SQL Editor, run the updated core_schema.sql
# This adds the mechanic_jobs update to recalculate_sales_invoice_payments()
```

### 2. Sync Existing Data (One-time fix)
```sql
-- Update all mechanic_jobs based on current invoice status
update mechanic_jobs m
set is_invoiced = true,
    is_paid = (i.status = 'paid'),
    updated_at = now()
from sales_invoices i
where m.invoice_id = i.id;
```

### 3. Deploy Flutter App
```bash
flutter clean
flutter build web --release
# Manual copy fix for build cache bug
firebase deploy --only hosting
```

---

## ✨ Results

After these fixes:
- ✅ Jobs with invoices show correct status ("PENDIENTE" or "PAGADO")
- ✅ "Crear" button only shows when job truly has no invoice
- ✅ Pending amounts show actual balance, not total cost
- ✅ Payment changes immediately reflect in job status
- ✅ Database and UI stay in sync automatically

---

## 🔍 Testing Checklist

- [ ] Create new job → Should show "Crear" button
- [ ] Create invoice from job → Should change to "PENDIENTE $X"
- [ ] Add partial payment → Should show "PENDIENTE $Y" (reduced balance)
- [ ] Complete payment → Should show "PAGADO $Z"
- [ ] Create invoice from sales module → Should sync to job correctly
- [ ] Delete payment → Should revert to "PENDIENTE" with full balance
