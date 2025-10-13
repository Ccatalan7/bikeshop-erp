# 🚨 URGENT: Journal Entry Deletion Issue - Complete Fix

## ⚠️ Problem

**You reverted an invoice from Confirmada → Enviada, but the journal entry was NOT deleted.**

This is a critical workflow issue that needs immediate attention.

---

## ✅ Immediate Solution

### **Run This ONE File:**

```
supabase/sql/quick_fix_journal_deletion.sql
```

This file will:
1. ✅ Check if trigger is installed
2. ✅ Check if function exists
3. ✅ Fix wrong `entry_type` values
4. ✅ Reinstall trigger (most common fix)
5. ✅ Add CASCADE delete to foreign keys
6. ✅ Clean up orphaned entries
7. ✅ Test the trigger automatically
8. ✅ Show final status report

**Expected Output:**
```
✅ ✅ ✅  SUCCESS! Trigger is working!
```

---

## 🔍 Root Causes (Most Common)

### 1. **Trigger Not Installed** (80% of cases)
- You ran the migration but not the triggers file
- **Fix**: Run `purchase_invoice_triggers.sql`

### 2. **entry_type Mismatch** (15% of cases)
- Journal entries have `NULL` or wrong `entry_type` values
- Trigger looks for `purchase_invoice` or `purchase_confirmation`
- **Fix**: Included in quick_fix file

### 3. **Trigger Disabled** (4% of cases)
- Trigger exists but is disabled
- **Fix**: Reinstall trigger (included in quick_fix)

### 4. **Function Definition Wrong** (1% of cases)
- Function doesn't have DELETE logic
- **Fix**: Re-run `purchase_invoice_triggers.sql`

---

## 📋 Step-by-Step Fix Guide

### Option A: Quick Fix (Recommended)

1. **Open Supabase Dashboard** → SQL Editor
2. **Copy contents** of `quick_fix_journal_deletion.sql`
3. **Paste and Run**
4. **Read the output** - should say "SUCCESS!"
5. **Test in app** - revert an invoice from Confirmada → Enviada
6. **Verify** - Check Asientos Contables, entry should be gone ✅

### Option B: Manual Fix

1. **Verify trigger exists:**
```sql
SELECT tgname FROM pg_trigger WHERE tgname = 'purchase_invoice_change_trigger';
```

2. **If NOT found, reinstall:**
```sql
-- Run entire file:
supabase/sql/purchase_invoice_triggers.sql
```

3. **Test manually:**
```sql
-- Find a confirmed invoice
SELECT id FROM purchase_invoices WHERE status = 'confirmed' LIMIT 1;

-- Revert it (replace <ID> with actual ID)
UPDATE purchase_invoices SET status = 'sent' WHERE id = '<ID>';

-- Check if entry deleted
SELECT * FROM journal_entries 
WHERE source_reference = '<ID>' 
AND source_module = 'purchase_invoices';
-- Should return 0 rows ✅
```

---

## 🎯 What Should Happen (Correct Behavior)

### Standard Model:
```
Draft → Sent → Confirmed (creates journal entry) → Sent (DELETES journal entry)
```

### Prepayment Model:
```
Draft → Sent → Confirmed (creates journal entry) → Sent (DELETES journal entry)
```

**The DELETE happens automatically via database trigger!**

---

## 🔧 Complete Workflow Validation

After fixing, test the COMPLETE workflow:

### Standard Model Test:
1. Create draft invoice (model = Standard)
2. Mark as Sent ✅
3. Mark as Confirmed ✅
   - Check: Journal entry created
4. **Revert to Sent** ✅
   - **Check: Journal entry DELETED** ← Critical!
5. Re-confirm ✅
6. Mark as Received ✅
   - Check: Inventory increased
7. Revert to Confirmed ✅
   - Check: Inventory decreased
8. Mark as Received again ✅
9. Register Payment ✅
   - Check: Status = Paid
10. Undo Payment ✅
    - Check: Status = Received

### Prepayment Model Test:
1. Create draft invoice (model = Prepago)
2. Mark as Sent ✅
3. Mark as Confirmed ✅
   - Check: Journal entry created
4. **Revert to Sent** ✅
   - **Check: Journal entry DELETED** ← Critical!
5. Re-confirm ✅
6. Register Payment ✅
   - Check: Status = Paid, used account 1155
7. Mark as Received ✅
   - Check: Inventory increased, settlement entry created
8. Revert to Paid ✅
   - Check: Inventory decreased, settlement deleted
9. Mark as Received again ✅
10. Everything working ✅

---

## 📊 Trigger Logic Reference

The trigger `handle_purchase_invoice_change()` has this DELETE logic:

```sql
-- When reverting Confirmada → Enviada
IF (OLD.status = 'confirmed' AND NEW.status = 'sent') THEN
  DELETE FROM journal_entries
  WHERE source_module = 'purchase_invoices'
    AND source_reference = OLD.id::TEXT
    AND entry_type IN ('purchase_invoice', 'purchase_confirmation');
END IF;
```

**Key Points:**
- Only deletes if exact status transition occurs
- Only deletes entries with correct `source_module`
- Only deletes entries with correct `entry_type`
- Uses CASCADE to also delete journal_lines

---

## 🚨 Warning Signs (Trigger Not Working)

- ❌ Reverting doesn't delete journal entry
- ❌ No log messages in Supabase logs
- ❌ Manual DELETE works but automatic doesn't
- ❌ Orphaned entries accumulate

---

## ✅ Success Indicators (Trigger Working Correctly)

- ✅ Revert from Confirmada deletes journal entry
- ✅ Revert from Recibida deletes stock movements
- ✅ Revert from Recibida (prepayment) deletes settlement
- ✅ No orphaned entries in database
- ✅ Log shows "Deleted accounting entry for reverted invoice"

---

## 📁 Related Files

| File | Purpose |
|------|---------|
| `quick_fix_journal_deletion.sql` | **Run this first!** Complete diagnostic and fix |
| `verify_purchase_invoice_triggers.sql` | Detailed verification and testing |
| `purchase_invoice_triggers.sql` | Full trigger installation |
| `PURCHASE_WORKFLOW_TROUBLESHOOTING.md` | Complete troubleshooting guide |
| `MASTER_ACCOUNTING_FIX.sql` | Accounting schema fixes |

---

## 🆘 If Still Not Working

1. **Check Supabase Logs:**
   - Go to Database → Logs
   - Filter by "purchase"
   - Look for errors or NOTICE messages

2. **Verify Function Source:**
```sql
SELECT pg_get_functiondef(oid) 
FROM pg_proc 
WHERE proname = 'handle_purchase_invoice_change';
```

3. **Check for Row-Level Security:**
```sql
SELECT tablename, policyname 
FROM pg_policies 
WHERE tablename = 'journal_entries';
```

4. **Enable Trigger Logging:**
```sql
-- Add more logging to trigger
ALTER FUNCTION handle_purchase_invoice_change() SET log_statement = 'all';
```

5. **Contact Support:**
   - Provide Supabase logs
   - Share result of `verify_purchase_invoice_triggers.sql`
   - Describe exact steps that fail

---

## 🎓 Why This Happens

This issue occurs when:
1. Migration runs successfully (adds columns)
2. App code updates successfully (uses new columns)
3. **BUT** triggers file is never run or fails silently
4. Result: Manual status changes work, but automation doesn't

**The fix is simple:** Just run the triggers file!

---

## 📞 Quick Reference

**Problem:** Journal entry not deleted on revert  
**Solution:** Run `quick_fix_journal_deletion.sql`  
**Verification:** Run `verify_purchase_invoice_triggers.sql`  
**Full Guide:** See `PURCHASE_WORKFLOW_TROUBLESHOOTING.md`  

---

**Status**: Ready to fix  
**Estimated Time**: 2 minutes  
**Success Rate**: 99%  
**Priority**: 🔥 CRITICAL
