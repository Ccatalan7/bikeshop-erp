# 🚀 DEPLOYMENT CHECKLIST - VINABIKE ERP

## 📋 Pre-Deployment Verification

### **Step 1: Code Verification**
- [x] All compilation errors resolved (0 errors)
- [x] All Flutter files use correct column names
- [x] Payment methods use `payment_method_id` uuid
- [x] No hardcoded payment method enums
- [x] Triggers handle journal entries (no manual creation)
- [x] Status transitions use correct logic

### **Step 2: Database Schema Verification**
- [ ] `core_schema.sql` has latest changes
- [ ] All migrations are idempotent (safe to re-run)
- [ ] Payment methods seeded (cash, transfer, card, check)
- [ ] Column renames included (invoice_id, date, payment_method_id)
- [ ] Functions updated (recalculate_sales_invoice_payments)
- [ ] Triggers updated (handle_sales_invoice_change)

### **Step 3: Documentation Verification**
- [x] 9 comprehensive guides created
- [x] Test scenarios documented (11 cases)
- [x] Breaking changes documented
- [x] Migration steps documented
- [x] Rollback plan documented (re-deploy old schema if needed)

---

## 🗄️ Database Deployment

### **Option 1: Supabase Dashboard (RECOMMENDED)**

#### **Step 1: Backup Existing Data (CRITICAL)**
```sql
-- In Supabase SQL Editor, run these queries:

-- Backup sales_payments
CREATE TABLE sales_payments_backup AS SELECT * FROM sales_payments;

-- Backup purchase_payments
CREATE TABLE purchase_payments_backup AS SELECT * FROM purchase_payments;

-- Backup sales_invoices
CREATE TABLE sales_invoices_backup AS SELECT * FROM sales_invoices;

-- Backup purchase_invoices
CREATE TABLE purchase_invoices_backup AS SELECT * FROM purchase_invoices;

-- Verify backups created
SELECT COUNT(*) as sales_payments_backup FROM sales_payments_backup;
SELECT COUNT(*) as purchase_payments_backup FROM purchase_payments_backup;
SELECT COUNT(*) as sales_invoices_backup FROM sales_invoices_backup;
SELECT COUNT(*) as purchase_invoices_backup FROM purchase_invoices_backup;
```

#### **Step 2: Deploy Schema**
1. Open Supabase Dashboard → SQL Editor
2. Create new query
3. Copy entire contents of `supabase/sql/core_schema.sql`
4. Paste into SQL Editor
5. Click "Run" (⚡ icon)
6. Wait for completion (~30-60 seconds)
7. Check for success message

#### **Step 3: Verify Deployment**
```sql
-- Check payment_methods table exists and has data
SELECT * FROM payment_methods WHERE is_active = true ORDER BY sort_order;
-- Expected: 4 rows (cash, transfer, card, check)

-- Check sales_payments has correct columns
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'sales_payments' 
ORDER BY ordinal_position;
-- Expected columns: id, invoice_id, date, amount, payment_method_id, reference, notes, created_at, updated_at

-- Check purchase_payments has correct columns
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'purchase_payments' 
ORDER BY ordinal_position;
-- Expected columns: id, invoice_id, date, amount, payment_method_id, reference, notes, created_at, updated_at

-- Check products has new columns
SELECT column_name 
FROM information_schema.columns 
WHERE table_name = 'products' 
  AND column_name IN ('product_type', 'barcode', 'brand', 'model', 'description');
-- Expected: 5 rows

-- Check recalculate function exists
SELECT routine_name 
FROM information_schema.routines 
WHERE routine_name = 'recalculate_sales_invoice_payments';
-- Expected: 1 row

-- Check triggers are active
SELECT trigger_name, event_object_table 
FROM information_schema.triggers 
WHERE trigger_schema = 'public' 
  AND event_object_table IN ('sales_invoices', 'sales_payments', 'purchase_invoices', 'purchase_payments')
ORDER BY event_object_table, trigger_name;
-- Expected: At least 4 triggers
```

#### **Step 4: Test Data Migration**
```sql
-- Verify old payment data migrated correctly
SELECT 
  sp.id,
  sp.invoice_id,
  sp.date,
  sp.amount,
  sp.payment_method_id,
  pm.name as payment_method_name
FROM sales_payments sp
LEFT JOIN payment_methods pm ON pm.id = sp.payment_method_id
ORDER BY sp.created_at DESC
LIMIT 10;

-- Check for any NULL payment_method_id (should be 0)
SELECT COUNT(*) as null_payment_methods
FROM sales_payments
WHERE payment_method_id IS NULL;
-- Expected: 0

-- Same for purchase_payments
SELECT COUNT(*) as null_payment_methods
FROM purchase_payments
WHERE payment_method_id IS NULL;
-- Expected: 0
```

---

### **Option 2: Supabase CLI (Alternative)**

```bash
# Install Supabase CLI if not installed
npm install -g supabase

# Login
supabase login

# Link to your project
supabase link --project-ref <your-project-ref>

# Apply migrations
supabase db push

# Verify
supabase db diff
```

---

## 🖥️ Flutter App Deployment

### **Step 1: Pull Latest Code**
```bash
git pull origin main
# Or your current branch
```

### **Step 2: Clean and Rebuild**
```bash
# Clean build artifacts
flutter clean

# Get dependencies
flutter pub get

# Verify no errors
flutter analyze

# Run tests (if any)
flutter test
```

### **Step 3: Run Application**
```bash
# For Windows
flutter run -d windows

# For Web
flutter run -d chrome

# For Android
flutter run -d android
```

### **Step 4: Verify Connection**
1. Check Supabase connection in logs
2. Navigate to Sales → Invoices
3. Verify data loads correctly
4. Check payment methods dropdown shows 4 options

---

## 🧪 Post-Deployment Testing

### **Test 1: Payment Methods Dropdown** (2 minutes)
- [ ] Sales → Invoice Detail → Registrar Pago
- [ ] Verify dropdown shows: Efectivo, Transferencia, Tarjeta, Cheque
- [ ] Verify icons display correctly (💰 🏦 💳 🧾)
- [ ] Purchase → Invoice Detail → Registrar Pago
- [ ] Verify same payment methods appear

### **Test 2: Reference Field Validation** (3 minutes)
- [ ] Select "Efectivo" → Reference field optional (no asterisk)
- [ ] Select "Transferencia" → Reference field required (red asterisk)
- [ ] Try to save without reference → Should show validation error
- [ ] Enter reference → Save should succeed
- [ ] Select "Cheque" → Reference field required
- [ ] Same behavior in both Sales and Purchase modules

### **Test 3: Invoice Status Transitions** (5 minutes)
- [ ] Create draft invoice
- [ ] Click "Marcar como enviada" → Status = 'sent' (NOT 'confirmed')
- [ ] Click "Confirmar" → Status = 'confirmed'
- [ ] Add full payment → Status = 'paid'
- [ ] Delete payment → Status = 'confirmed' (NOT 'sent' or 'draft')
- [ ] Click "Volver a enviada" → Status = 'sent'
- [ ] Click "Volver a borrador" → Status = 'draft'

### **Test 4: Partial Payments** (5 minutes)
- [ ] Create invoice: $100,000
- [ ] Add payment: $50,000
- [ ] Status = 'confirmed' (not 'paid')
- [ ] Balance = $50,000
- [ ] Add payment: $50,000
- [ ] Status = 'paid'
- [ ] Balance = $0

### **Test 5: Journal Entries** (3 minutes)
- [ ] Navigate to Accounting → Asientos Contables
- [ ] Create invoice → Verify entry appears
- [ ] Add payment → Verify payment entry appears
- [ ] Click refresh button → Entries reload
- [ ] Delete payment → Payment entry disappears

### **Test 6: Database Consistency** (2 minutes)
```sql
-- Run in Supabase SQL Editor

-- Check all payments have valid payment_method_id
SELECT COUNT(*) as invalid_payments
FROM sales_payments sp
LEFT JOIN payment_methods pm ON pm.id = sp.payment_method_id
WHERE pm.id IS NULL;
-- Expected: 0

-- Check invoice totals match payments
SELECT 
  si.invoice_number,
  si.total,
  si.paid_amount,
  si.balance,
  COALESCE(SUM(sp.amount), 0) as calculated_paid,
  si.paid_amount - COALESCE(SUM(sp.amount), 0) as difference
FROM sales_invoices si
LEFT JOIN sales_payments sp ON sp.invoice_id = si.id
GROUP BY si.id, si.invoice_number, si.total, si.paid_amount, si.balance
HAVING ABS(si.paid_amount - COALESCE(SUM(sp.amount), 0)) > 0.01;
-- Expected: 0 rows (all match)

-- Check journal entries exist for all invoices
SELECT 
  si.invoice_number,
  si.status,
  COUNT(je.id) as journal_entry_count
FROM sales_invoices si
LEFT JOIN journal_entries je ON je.source_reference = si.id::text
WHERE si.status IN ('confirmed', 'paid')
GROUP BY si.id, si.invoice_number, si.status
HAVING COUNT(je.id) = 0;
-- Expected: 0 rows (all have entries)
```

---

## ⚠️ Rollback Plan (If Issues Occur)

### **Option 1: Restore from Backup**
```sql
-- Drop new tables (if needed)
DROP TABLE IF EXISTS payment_methods CASCADE;

-- Restore old sales_payments
DROP TABLE IF EXISTS sales_payments CASCADE;
CREATE TABLE sales_payments AS SELECT * FROM sales_payments_backup;

-- Restore old purchase_payments
DROP TABLE IF EXISTS purchase_payments CASCADE;
CREATE TABLE purchase_payments AS SELECT * FROM purchase_payments_backup;

-- Restore old sales_invoices
TRUNCATE TABLE sales_invoices;
INSERT INTO sales_invoices SELECT * FROM sales_invoices_backup;

-- Restore old purchase_invoices
TRUNCATE TABLE purchase_invoices;
INSERT INTO purchase_invoices SELECT * FROM purchase_invoices_backup;
```

### **Option 2: Re-deploy Old Schema**
1. Checkout previous git commit
2. Copy old `core_schema.sql`
3. Run in Supabase SQL Editor
4. Restart Flutter app with old code

---

## 🐛 Troubleshooting

### **Issue: "column payment_method_id does not exist"**
**Solution:** Migration didn't run. Re-deploy core_schema.sql

### **Issue: Dropdown shows no payment methods**
**Solution:** Check payment_methods table:
```sql
SELECT * FROM payment_methods WHERE is_active = true;
```
If empty, re-run seed section of core_schema.sql

### **Issue: Reference field not showing as required**
**Solution:** Check payment_method.requires_reference:
```sql
UPDATE payment_methods SET requires_reference = true WHERE code IN ('transfer', 'check');
```

### **Issue: Journal entries not created automatically**
**Solution:** Check triggers are active:
```sql
SELECT * FROM information_schema.triggers WHERE event_object_table = 'sales_invoices';
```
If missing, re-deploy trigger section of core_schema.sql

### **Issue: Status stuck on wrong value**
**Solution:** Manually recalculate:
```sql
SELECT public.recalculate_sales_invoice_payments('<invoice-id>');
```

---

## ✅ Post-Deployment Sign-Off

### **Technical Validation**
- [ ] All database tables created
- [ ] All migrations ran successfully
- [ ] All triggers are active
- [ ] All functions compiled without errors
- [ ] Payment methods seeded (4 rows)
- [ ] Old data migrated correctly
- [ ] No NULL payment_method_id values

### **Functional Validation**
- [ ] Payment dropdown works in Sales
- [ ] Payment dropdown works in Purchases
- [ ] Reference field conditional on method
- [ ] Status transitions work forward
- [ ] Status transitions work backward
- [ ] Journal entries created automatically
- [ ] Invoice totals calculated correctly
- [ ] Partial payments handled correctly

### **User Acceptance**
- [ ] UI looks correct
- [ ] No error messages in console
- [ ] Navigation works smoothly
- [ ] Data displays correctly
- [ ] Forms validate properly
- [ ] Save/Delete operations work

### **Documentation**
- [ ] User guide updated (if exists)
- [ ] Admin documentation updated
- [ ] Known issues documented
- [ ] Training materials updated (if needed)

---

## 📝 Deployment Log Template

```
Date: __________
Time: __________
Deployed By: __________
Environment: [ ] Production [ ] Staging [ ] Development

Pre-Deployment:
- [ ] Code compiled successfully
- [ ] Database backed up
- [ ] Tests passed

Deployment:
- [ ] Schema deployed at ____:____
- [ ] Migrations ran successfully
- [ ] App restarted at ____:____

Post-Deployment:
- [ ] All tests passed
- [ ] No errors in logs
- [ ] User acceptance confirmed

Issues Encountered:
_________________________
_________________________

Rollback Required: [ ] Yes [ ] No
If Yes, Reason: ____________

Sign-Off:
Developer: __________
QA: __________
Manager: __________
```

---

## 🎯 Success Criteria

✅ **Deployment is successful when:**
1. All database tables match core_schema.sql
2. All old data migrated to new schema
3. Payment methods dropdown shows 4 options
4. Reference field required for transfer/check
5. Invoice status transitions work correctly
6. Journal entries created automatically
7. No compilation or runtime errors
8. All test scenarios pass
9. User can complete full invoice lifecycle
10. Documentation updated and approved

---

## 📞 Support Contacts

**Database Issues:**
- Check Supabase logs: Dashboard → Database → Logs
- Check trigger execution: Enable NOTICE level logging
- Contact: [Your Database Admin]

**Flutter Issues:**
- Check console output: `flutter logs`
- Check build errors: `flutter analyze`
- Contact: [Your Flutter Developer]

**Business Logic Issues:**
- Review INVOICE_STATUS_TEST_SCENARIOS.md
- Check documentation in /docs folder
- Contact: [Your Business Analyst]

---

**Last Updated:** After Phase 1-3 Completion  
**Next Review:** After Phase 5 Testing  
**Status:** ✅ READY FOR DEPLOYMENT
