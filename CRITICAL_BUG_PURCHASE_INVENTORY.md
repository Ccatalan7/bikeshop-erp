# 🚨 CRITICAL BUG FOUND: Purchase Invoice Inventory Trigger Logic

## ⚠️ PROBLEM DISCOVERED

The `handle_purchase_invoice_change()` trigger treats ALL non-draft/sent/cancelled statuses as "posted", which means:

### **Current (BROKEN) Logic:**
```sql
v_non_posted := array['draft', 'sent', 'cancelled'];
v_posted := everything else  -- This includes 'confirmed', 'received', AND 'paid'!
```

**What happens:**
- Status = 'confirmed' → **Consumes inventory** ❌ WRONG!
- Status = 'received' → **Consumes inventory** ✅ CORRECT
- Status = 'paid' → **Consumes inventory** ❌ WRONG!

### **Impact on Both Models:**

#### Standard Model (prepayment_model = false)
**Expected Flow:** Draft → Sent → Confirmed → **Received** (consume inventory) → Paid

**What Actually Happens:**
1. Draft → Sent ✅ OK (no inventory change)
2. Sent → Confirmed ❌ **BUG: Inventory consumed prematurely!**
3. Confirmed → Received ❌ **Inventory consumed AGAIN** (duplicate)
4. Received → Paid ✅ OK (inventory already consumed)

**Result:** Inventory gets consumed at **BOTH** `confirmed` and `received`, effectively **DOUBLE-DEDUCTING!** 💥

#### Prepayment Model (prepayment_model = true)
**Expected Flow:** Draft → Sent → Confirmed → Paid → **Received** (consume inventory)

**What Actually Happens:**
1. Draft → Sent ✅ OK (no inventory change)
2. Sent → Confirmed ❌ **BUG: Inventory consumed prematurely!**
3. Confirmed → Paid ❌ **Inventory consumed AGAIN** (duplicate)
4. Paid → Received ❌ **Inventory consumed THIRD TIME!** (triple!)

**Result:** Inventory gets consumed at **THREE** statuses: `confirmed`, `paid`, AND `received`! **TRIPLE-DEDUCTING!** 💥💥💥

---

## 🎯 Correct Business Logic

### **For Purchase Invoices (Both Models):**
- Inventory should **ONLY** be consumed when goods are physically received
- This happens at **ONE status only: `received`**
- Does not matter if payment happened before or after
- Physical receipt = inventory increase

### **Status → Inventory Action Map:**
| Status | Standard Model | Prepayment Model | Action |
|--------|---------------|------------------|---------|
| draft | No inventory | No inventory | ✅ None |
| sent | No inventory | No inventory | ✅ None |
| confirmed | No inventory | No inventory | ✅ None |
| paid | No inventory | No inventory | ✅ None |
| **received** | **Consume** | **Consume** | ✅ **ONLY HERE** |
| cancelled | No inventory | No inventory | ✅ None |

### **Status → Journal Entry Map:**
| Status | Action | Entry Type |
|--------|--------|------------|
| draft | None | - |
| sent | None | - |
| confirmed | Create invoice entry | PINV (Debit: Inventory/Expense, Credit: AP) |
| paid | Payment journal entry | PAY (handled by payment trigger) |
| received | None (already at confirmed) | - |
| cancelled | Delete entries | - |

---

## ✅ CORRECT TRIGGER LOGIC

### **For Purchase Invoices:**
```sql
-- Inventory: ONLY at 'received' status
if OLD.status != 'received' AND NEW.status = 'received' then
  -- Transitioning TO received: consume inventory
  perform public.consume_purchase_invoice_inventory(NEW);
elsif OLD.status = 'received' AND NEW.status != 'received' then
  -- Transitioning FROM received: restore inventory
  perform public.restore_purchase_invoice_inventory(OLD);
end if;

-- Journal Entries: At 'confirmed' status
if OLD.status != 'confirmed' AND NEW.status IN ('confirmed', 'received', 'paid') then
  -- Transitioning TO confirmed (or any status after): create invoice entry
  perform public.create_purchase_invoice_journal_entry(NEW);
elsif OLD.status IN ('confirmed', 'received', 'paid') AND NEW.status IN ('draft', 'sent', 'cancelled') then
  -- Transitioning FROM confirmed (or after) back to pre-confirmed: delete entry
  perform public.delete_purchase_invoice_journal_entry(OLD.id);
elsif OLD.status IN ('confirmed', 'received', 'paid') AND NEW.status IN ('confirmed', 'received', 'paid') then
  -- Staying in post-confirmed statuses but changing: recreate entry
  perform public.delete_purchase_invoice_journal_entry(OLD.id);
  perform public.create_purchase_invoice_journal_entry(NEW);
end if;
```

---

## 🔧 THE FIX

### **Updated `handle_purchase_invoice_change()` function:**

```sql
create or replace function public.handle_purchase_invoice_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old_status text;
  v_new_status text;
begin
  raise notice 'handle_purchase_invoice_change: TG_OP=%', TG_OP;

  if TG_OP = 'INSERT' then
    v_new_status := NEW.status;
    raise notice 'handle_purchase_invoice_change: INSERT invoice %, status %', NEW.id, v_new_status;
    
    -- Inventory: ONLY if inserted directly as 'received' (rare)
    if v_new_status = 'received' then
      raise notice 'handle_purchase_invoice_change: INSERT at received, consuming inventory';
      perform public.consume_purchase_invoice_inventory(NEW);
    end if;
    
    -- Journal: If inserted at 'confirmed' or later
    if v_new_status IN ('confirmed', 'received', 'paid') then
      raise notice 'handle_purchase_invoice_change: INSERT at confirmed/received/paid, creating journal entry';
      perform public.create_purchase_invoice_journal_entry(NEW);
    end if;
    
    return NEW;

  elsif TG_OP = 'UPDATE' then
    v_old_status := OLD.status;
    v_new_status := NEW.status;
    
    raise notice 'handle_purchase_invoice_change: UPDATE invoice %, old status %, new status %', NEW.id, v_old_status, v_new_status;

    -- INVENTORY HANDLING: ONLY at 'received' status
    if v_old_status != 'received' AND v_new_status = 'received' then
      -- Transitioning TO received: consume inventory
      raise notice 'handle_purchase_invoice_change: transitioning TO received, consuming inventory';
      perform public.consume_purchase_invoice_inventory(NEW);
      
    elsif v_old_status = 'received' AND v_new_status != 'received' then
      -- Transitioning FROM received: restore inventory
      raise notice 'handle_purchase_invoice_change: transitioning FROM received, restoring inventory';
      perform public.restore_purchase_invoice_inventory(OLD);
      
    elsif v_old_status = 'received' AND v_new_status = 'received' then
      -- Staying at received but invoice data changed: restore old, consume new
      raise notice 'handle_purchase_invoice_change: staying at received, updating inventory';
      perform public.restore_purchase_invoice_inventory(OLD);
      perform public.consume_purchase_invoice_inventory(NEW);
    end if;

    -- JOURNAL ENTRY HANDLING: At 'confirmed' and beyond
    if v_old_status IN ('draft', 'sent', 'cancelled') AND v_new_status IN ('confirmed', 'received', 'paid') then
      -- Transitioning TO confirmed/received/paid: create journal entry
      raise notice 'handle_purchase_invoice_change: transitioning TO confirmed/received/paid, creating journal entry';
      perform public.create_purchase_invoice_journal_entry(NEW);
      
    elsif v_old_status IN ('confirmed', 'received', 'paid') AND v_new_status IN ('draft', 'sent', 'cancelled') then
      -- Transitioning FROM confirmed/received/paid to draft/sent/cancelled: delete journal entry
      raise notice 'handle_purchase_invoice_change: transitioning FROM confirmed/received/paid, deleting journal entry';
      perform public.delete_purchase_invoice_journal_entry(OLD.id);
      
    elsif v_old_status IN ('confirmed', 'received', 'paid') AND v_new_status IN ('confirmed', 'received', 'paid') AND v_old_status != v_new_status then
      -- Both in confirmed/received/paid but different: recreate journal entry
      raise notice 'handle_purchase_invoice_change: both in confirmed/received/paid, recreating journal entry';
      perform public.delete_purchase_invoice_journal_entry(OLD.id);
      perform public.create_purchase_invoice_journal_entry(NEW);
    end if;

    return NEW;

  elsif TG_OP = 'DELETE' then
    v_old_status := OLD.status;
    raise notice 'handle_purchase_invoice_change: DELETE invoice %, status %', OLD.id, v_old_status;
    
    -- Restore inventory if was received
    if v_old_status = 'received' then
      raise notice 'handle_purchase_invoice_change: deleting received invoice, restoring inventory';
      perform public.restore_purchase_invoice_inventory(OLD);
    end if;
    
    -- Delete journal entry if was confirmed or later
    if v_old_status IN ('confirmed', 'received', 'paid') then
      raise notice 'handle_purchase_invoice_change: deleting confirmed/received/paid invoice, deleting journal entry';
      perform public.delete_purchase_invoice_journal_entry(OLD.id);
    end if;
    
    return OLD;
  end if;

  return NULL;
end;
$$;
```

---

## 🧪 Test Scenarios (MUST VERIFY)

### **Test 1: Standard Model - Forward Flow**
1. Create invoice: Draft → Inventory = 0 ✅
2. Mark as Sent → Inventory = 0 ✅
3. Confirm → Inventory = 0, Journal Entry created ✅
4. Mark as Received → **Inventory += qty** ✅
5. Add Payment → Inventory unchanged, Payment journal entry ✅

**Database Check:**
```sql
SELECT * FROM stock_movements WHERE reference LIKE 'PINV-%' ORDER BY created_at;
-- Should show ONLY ONE movement when status = 'received'
```

### **Test 2: Standard Model - Backward Flow**
1. Paid invoice (inventory already added)
2. Undo payment → Inventory unchanged ✅
3. Revert from Received to Confirmed → **Inventory -= qty (restored)** ✅
4. Revert to Sent → Journal entry deleted ✅
5. Revert to Draft → No change ✅

### **Test 3: Prepayment Model - Forward Flow**
1. Create invoice: Draft → Inventory = 0 ✅
2. Mark as Sent → Inventory = 0 ✅
3. Confirm → Inventory = 0, Journal Entry created ✅
4. Add Payment → Inventory = 0, Payment journal entry ✅
5. Mark as Received → **Inventory += qty** ✅

**Database Check:**
```sql
-- Should show inventory movement ONLY at 'received', NOT at 'paid'
SELECT 
  si.invoice_number,
  si.status,
  sm.movement_type,
  sm.quantity,
  sm.created_at
FROM purchase_invoices si
LEFT JOIN stock_movements sm ON sm.reference = 'PINV-' || si.id::text
WHERE si.prepayment_model = true
ORDER BY si.created_at, sm.created_at;
```

### **Test 4: Prepayment Model - Backward Flow**
1. Received invoice (inventory already added, payment already done)
2. Revert from Received to Paid → **Inventory -= qty (restored)** ✅
3. Undo payment → Inventory unchanged ✅
4. Revert to Confirmed → Inventory unchanged ✅

### **Test 5: Status Jump (Edge Case)**
1. Draft invoice
2. Directly update to 'received' (skip confirmed)
3. Should: Consume inventory ✅, Create journal entry ✅

---

## ⚠️ CRITICAL WARNINGS

1. **DO NOT DEPLOY** current code to production
2. **MUST FIX** `handle_purchase_invoice_change()` trigger first
3. **MUST TEST** all scenarios above before deployment
4. **CHECK** existing data for duplicate stock movements

---

## 🔍 How to Check for Existing Corruption

```sql
-- Check for duplicate stock movements per invoice
SELECT 
  reference,
  COUNT(*) as movement_count,
  SUM(quantity) as total_qty
FROM stock_movements
WHERE reference LIKE 'PINV-%'
  AND movement_type = 'purchase'
GROUP BY reference
HAVING COUNT(*) > 1;
-- If any rows returned: inventory was double/triple counted!

-- Check invoice status vs inventory movements
SELECT 
  pi.invoice_number,
  pi.status,
  COUNT(sm.id) as movement_count
FROM purchase_invoices pi
LEFT JOIN stock_movements sm ON sm.reference = 'PINV-' || pi.id::text
WHERE pi.status != 'received'
GROUP BY pi.id, pi.invoice_number, pi.status
HAVING COUNT(sm.id) > 0;
-- If any rows: inventory was consumed at wrong status!
```

---

**Status:** 🚨 **BLOCKER - MUST FIX BEFORE DEPLOYMENT**  
**Priority:** 🔴 **CRITICAL**  
**Estimated Fix Time:** 30 minutes (update trigger + test)  
**User Was Right:** YES - Good catch! 👍
