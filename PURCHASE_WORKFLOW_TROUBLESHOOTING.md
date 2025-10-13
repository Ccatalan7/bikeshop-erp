# 🔍 Purchase Invoice Workflow Testing & Verification

## Issue Reported

**Problem**: When reverting invoice from **Confirmada → Enviada**, the journal entry is **NOT being deleted**.

**Expected**: The database trigger should automatically DELETE the journal entry when status changes from `confirmed` to `sent`.

---

## 🧪 Diagnostic Steps

### Step 1: Run Verification Script

Run this SQL file in Supabase SQL Editor:
```
supabase/sql/verify_purchase_invoice_triggers.sql
```

This will:
1. ✅ Check if trigger is installed
2. ✅ Check if function exists  
3. ✅ Test the Confirmada → Enviada reversal
4. ✅ Show journal entry count before/after
5. ✅ Verify entry_type values match

---

## 🔧 Possible Causes & Solutions

### Cause 1: Trigger Not Installed

**Symptoms:**
- Verification script shows: ❌ Trigger NOT FOUND
- No automatic deletions happening

**Solution:**
```bash
# Run the trigger installation SQL
supabase/sql/purchase_invoice_triggers.sql
```

---

### Cause 2: entry_type Mismatch

**Symptoms:**
- Trigger exists but entries not deleted
- Verification shows different `entry_type` values

**Problem:**
The trigger deletes entries where:
```sql
entry_type IN ('purchase_invoice', 'purchase_confirmation')
```

But if your entries have different `entry_type` values (like `NULL`, `'manual'`, `'purchase'`), they won't be deleted.

**Solution:**
Update the trigger to match your actual `entry_type` values, or update existing entries:

```sql
-- Check what entry_type values you actually have
SELECT DISTINCT entry_type, COUNT(*)
FROM journal_entries
WHERE source_module = 'purchase_invoices'
GROUP BY entry_type;

-- If they're NULL or different, update them:
UPDATE journal_entries
SET entry_type = 'purchase_invoice'
WHERE source_module = 'purchase_invoices'
  AND entry_type IS NULL;
```

---

### Cause 3: Trigger Disabled

**Symptoms:**
- Trigger shows as existing but not firing
- No log messages in Supabase logs

**Solution:**
```sql
-- Check trigger status
SELECT 
  tgname, 
  tgenabled,
  CASE tgenabled
    WHEN 'O' THEN 'Enabled'
    WHEN 'D' THEN 'Disabled'
    ELSE 'Unknown'
  END AS status
FROM pg_trigger
WHERE tgname = 'purchase_invoice_change_trigger';

-- If disabled, re-create it:
DROP TRIGGER IF EXISTS purchase_invoice_change_trigger ON purchase_invoices;

CREATE TRIGGER purchase_invoice_change_trigger
  AFTER UPDATE OF status
  ON purchase_invoices
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION handle_purchase_invoice_change();
```

---

### Cause 4: Foreign Key CASCADE Not Working

**Symptoms:**
- Journal entry exists
- Journal lines not deleted when entry is deleted

**Solution:**
```sql
-- Check foreign key constraint
SELECT
  tc.constraint_name,
  tc.table_name,
  kcu.column_name,
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name,
  rc.delete_rule
FROM information_schema.table_constraints AS tc
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
JOIN information_schema.referential_constraints AS rc
  ON tc.constraint_name = rc.constraint_name
WHERE tc.table_name = 'journal_lines'
  AND kcu.column_name = 'journal_entry_id';

-- If delete_rule is not CASCADE, fix it:
ALTER TABLE journal_lines
DROP CONSTRAINT IF EXISTS journal_lines_journal_entry_id_fkey;

ALTER TABLE journal_lines
ADD CONSTRAINT journal_lines_journal_entry_id_fkey
FOREIGN KEY (journal_entry_id) REFERENCES journal_entries(id) ON DELETE CASCADE;
```

---

## 📋 Complete Workflow Test

### Test A: Standard Model (Pago Después)

```sql
-- 1. Create test invoice
INSERT INTO purchase_invoices (id, invoice_number, status, prepayment_model, total, subtotal, iva_amount, supplier_id)
VALUES (gen_random_uuid(), 'TEST-001', 'draft', false, 119000, 100000, 19000, (SELECT id FROM suppliers LIMIT 1))
RETURNING id;

-- Note the ID returned, use it below as <INVOICE_ID>

-- 2. Draft → Sent
UPDATE purchase_invoices SET status = 'sent', sent_date = NOW() WHERE id = '<INVOICE_ID>';

-- 3. Sent → Confirmed (should create journal entry)
UPDATE purchase_invoices SET status = 'confirmed', confirmed_date = NOW() WHERE id = '<INVOICE_ID>';

-- 4. Check journal entry was created
SELECT * FROM journal_entries 
WHERE source_reference = '<INVOICE_ID>'
  AND entry_type = 'purchase_invoice';
-- Should return 1 row ✅

-- 5. Confirmed → Sent (should DELETE journal entry)
UPDATE purchase_invoices SET status = 'sent' WHERE id = '<INVOICE_ID>';

-- 6. Check journal entry was deleted
SELECT * FROM journal_entries 
WHERE source_reference = '<INVOICE_ID>'
  AND entry_type = 'purchase_invoice';
-- Should return 0 rows ✅

-- 7. Clean up
DELETE FROM purchase_invoices WHERE id = '<INVOICE_ID>';
```

### Test B: Prepayment Model (Prepago)

```sql
-- 1. Create test invoice
INSERT INTO purchase_invoices (id, invoice_number, status, prepayment_model, total, subtotal, iva_amount, supplier_id)
VALUES (gen_random_uuid(), 'TEST-002', 'draft', true, 119000, 100000, 19000, (SELECT id FROM suppliers LIMIT 1))
RETURNING id;

-- Note the ID, use as <INVOICE_ID>

-- 2. Draft → Sent → Confirmed
UPDATE purchase_invoices SET status = 'sent', sent_date = NOW() WHERE id = '<INVOICE_ID>';
UPDATE purchase_invoices SET status = 'confirmed', confirmed_date = NOW() WHERE id = '<INVOICE_ID>';

-- 3. Check journal entry created with correct type
SELECT entry_type, notes FROM journal_entries 
WHERE source_reference = '<INVOICE_ID>';
-- Should show entry_type = 'purchase_confirmation' ✅

-- 4. Confirmed → Sent (should DELETE)
UPDATE purchase_invoices SET status = 'sent' WHERE id = '<INVOICE_ID>';

-- 5. Verify deletion
SELECT COUNT(*) FROM journal_entries 
WHERE source_reference = '<INVOICE_ID>';
-- Should be 0 ✅

-- 6. Clean up
DELETE FROM purchase_invoices WHERE id = '<INVOICE_ID>';
```

---

## 🚨 Manual Fix: Delete Orphaned Journal Entries

If you have journal entries that should have been deleted but weren't:

```sql
-- Find orphaned entries (invoices at 'sent' but have journal entries)
SELECT 
  pi.invoice_number,
  pi.status,
  je.entry_number,
  je.entry_type,
  je.id AS journal_entry_id
FROM purchase_invoices pi
JOIN journal_entries je ON je.source_reference = pi.id::TEXT
WHERE pi.status = 'sent'
  AND je.source_module = 'purchase_invoices'
  AND je.entry_type IN ('purchase_invoice', 'purchase_confirmation');

-- Manually delete them (if you confirm they're orphaned)
DELETE FROM journal_entries
WHERE id IN (
  SELECT je.id
  FROM purchase_invoices pi
  JOIN journal_entries je ON je.source_reference = pi.id::TEXT
  WHERE pi.status = 'sent'
    AND je.source_module = 'purchase_invoices'
    AND je.entry_type IN ('purchase_invoice', 'purchase_confirmation')
);
```

---

## ✅ Verification Checklist

After fixing, verify:

- [ ] Trigger `purchase_invoice_change_trigger` exists
- [ ] Function `handle_purchase_invoice_change` exists
- [ ] Trigger is ENABLED (not disabled)
- [ ] entry_type values match: `purchase_invoice` or `purchase_confirmation`
- [ ] Foreign key has ON DELETE CASCADE
- [ ] Test: Confirmada → Enviada deletes journal entry
- [ ] Test: Recibida → Confirmada deletes stock movements
- [ ] Test: Recibida → Pagada (prepayment) deletes settlement entry

---

## 🔍 How to Check Logs

In Supabase Dashboard:
1. Go to **Database** → **Logs**
2. Filter by: `purchase_invoice`
3. Look for NOTICE messages like:
   - ✅ "Deleted accounting entry for reverted invoice"
   - ❌ Error messages

---

## 📊 Current Trigger Logic (Summary)

| Transition | Action | Entry Type Deleted |
|------------|--------|--------------------|
| **Confirmada → Enviada** | DELETE journal entry | `purchase_invoice`, `purchase_confirmation` |
| **Recibida → Confirmada** | DELETE stock movements + inventory decrease | N/A |
| **Recibida → Pagada** (prepay) | DELETE settlement entry | `purchase_receipt` |
| **Pagada → Confirmada** (prepay) | DELETE payment entry | `payment` |

---

## 🛠️ Quick Fix Command

If everything else looks good but trigger not firing:

```sql
-- Reinstall trigger
DROP TRIGGER IF EXISTS purchase_invoice_change_trigger ON purchase_invoices;

CREATE TRIGGER purchase_invoice_change_trigger
  AFTER UPDATE OF status
  ON purchase_invoices
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION handle_purchase_invoice_change();

-- Test immediately
UPDATE purchase_invoices 
SET status = 'sent' 
WHERE status = 'confirmed' 
LIMIT 1;

-- Check result
SELECT 
  pi.invoice_number,
  pi.status,
  COUNT(je.id) AS journal_entry_count
FROM purchase_invoices pi
LEFT JOIN journal_entries je ON je.source_reference = pi.id::TEXT
WHERE pi.status = 'sent'
GROUP BY pi.id, pi.invoice_number, pi.status
HAVING COUNT(je.id) > 0;
-- Should show 0 rows (no sent invoices with journal entries)
```

---

## 📞 Next Steps

1. **Run** `verify_purchase_invoice_triggers.sql`
2. **Read** the output carefully
3. **Apply** the appropriate fix based on results
4. **Test** with a real invoice
5. **Verify** journal entry deleted
6. **Confirm** workflow works end-to-end

---

**Status**: Ready for testing  
**File Created**: `verify_purchase_invoice_triggers.sql`  
**Documentation**: This file
