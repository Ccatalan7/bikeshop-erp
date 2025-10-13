# 💳 PAYMENT METHODS IMPLEMENTATION — DYNAMIC & CONFIGURABLE

## 📋 Overview

This document describes the **Payment Methods System** implemented for Vinabike ERP. The system provides **dynamic, UI-configurable payment methods** that eliminate hardcoded payment logic and enable flexible multi-account management.

**Key Feature**: Payment methods are now stored in a database table (`payment_methods`) where each method is linked to a specific accounting account. This allows users to:
- ✅ Add new payment methods via UI (e.g., "Transferencia BCI", "Transferencia Santander")
- ✅ Configure which account each payment method uses
- ✅ Support multiple bank accounts without code changes
- ✅ Change account assignments without redeployment

---

## 🎯 Problem Solved

### ❌ Old Approach (Hardcoded)

**Before**: Payment methods were hardcoded with a CHECK constraint:
```sql
CREATE TABLE sales_payments (
  method text CHECK (method in ('cash','card','transfer','check','other'))
);
```

**Problems**:
- Adding a new payment method required schema changes
- Account assignment was buried in a 149-line function
- No support for multiple bank accounts
- Inflexible for growing businesses

**Old Hardcoded Logic** (from `create_sales_payment_journal_entry`):
```sql
CASE coalesce(p_payment.method, 'other')
  WHEN 'cash' THEN
    v_cash_account_code := '1101'; -- Caja General
  WHEN 'card' THEN
    v_cash_account_code := '1110'; -- Banco
  WHEN 'transfer' THEN
    v_cash_account_code := '1110'; -- Banco
  -- ... hardcoded for each method
END CASE;
```

### ✅ New Approach (Dynamic)

**Now**: Payment methods are configured in a table with account references:
```sql
CREATE TABLE payment_methods (
  id UUID PRIMARY KEY,
  code TEXT UNIQUE,
  name TEXT NOT NULL,
  account_id UUID REFERENCES accounts(id), -- ⭐ Links to accounting account
  requires_reference BOOLEAN DEFAULT FALSE,
  icon TEXT,
  sort_order INTEGER,
  is_active BOOLEAN DEFAULT TRUE
);
```

**Benefits**:
- ✅ No code changes to add/modify payment methods
- ✅ UI-driven configuration via "Métodos de Pago" management page
- ✅ Multi-bank support ("Transfer BCI", "Transfer Santander", etc.)
- ✅ Flexible account assignment (change anytime via UI)
- ✅ Consistent pattern across sales and purchases

**New Dynamic Logic**:
```sql
-- Query payment method and its account dynamically
SELECT pm.id, pm.code, pm.name, a.id as account_id, a.code, a.name
FROM payment_methods pm
JOIN accounts a ON a.id = pm.account_id
WHERE pm.id = p_payment.payment_method_id;

-- Use account_id directly in journal entry
INSERT INTO journal_lines (account_id, ...) VALUES (v_payment_method.account_id, ...);
```

---

## 🗄️ Database Schema Changes

### 1. New Table: `payment_methods`

```sql
CREATE TABLE IF NOT EXISTS payment_methods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,              -- 'cash', 'transfer', 'card', etc.
  name TEXT NOT NULL,                     -- 'Efectivo', 'Transferencia Bancaria', etc.
  account_id UUID NOT NULL REFERENCES accounts(id),  -- ⭐ Links to accounting account
  requires_reference BOOLEAN NOT NULL DEFAULT FALSE, -- Show reference field in form?
  icon TEXT,                              -- 'cash', 'bank', 'credit_card', etc.
  sort_order INTEGER NOT NULL DEFAULT 0,  -- Display order in dropdowns
  is_active BOOLEAN NOT NULL DEFAULT TRUE, -- Active/inactive toggle
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX idx_payment_methods_code ON payment_methods(code);
CREATE INDEX idx_payment_methods_sort_order ON payment_methods(sort_order);
CREATE INDEX idx_payment_methods_account_id ON payment_methods(account_id);
```

### 2. Seed Data: Default Payment Methods

```sql
-- Efectivo → 1101 Caja General
INSERT INTO payment_methods (code, name, account_id, requires_reference, icon, sort_order)
SELECT 'cash', 'Efectivo', id, FALSE, 'cash', 1
FROM accounts WHERE code = '1101'
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  account_id = EXCLUDED.account_id,
  updated_at = NOW();

-- Transferencia → 1110 Bancos
INSERT INTO payment_methods (code, name, account_id, requires_reference, icon, sort_order)
SELECT 'transfer', 'Transferencia Bancaria', id, TRUE, 'bank', 2
FROM accounts WHERE code = '1110'
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  account_id = EXCLUDED.account_id,
  updated_at = NOW();

-- Tarjeta → 1110 Bancos
INSERT INTO payment_methods (code, name, account_id, requires_reference, icon, sort_order)
SELECT 'card', 'Tarjeta de Débito/Crédito', id, FALSE, 'credit_card', 3
FROM accounts WHERE code = '1110'
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  account_id = EXCLUDED.account_id,
  updated_at = NOW();

-- Cheque → 1110 Bancos
INSERT INTO payment_methods (code, name, account_id, requires_reference, icon, sort_order)
SELECT 'check', 'Cheque', id, TRUE, 'receipt', 4
FROM accounts WHERE code = '1110'
ON CONFLICT (code) DO UPDATE SET
  name = EXCLUDED.name,
  account_id = EXCLUDED.account_id,
  updated_at = NOW();
```

### 3. Updated Table: `sales_payments`

**Old Structure**:
```sql
CREATE TABLE sales_payments (
  id UUID PRIMARY KEY,
  invoice_id UUID REFERENCES sales_invoices(id),
  method TEXT CHECK (method IN ('cash','card','transfer','check','other')), -- ❌ Hardcoded
  amount NUMERIC(12,2),
  ...
);
```

**New Structure**:
```sql
CREATE TABLE sales_payments (
  id UUID PRIMARY KEY,
  invoice_id UUID REFERENCES sales_invoices(id),
  payment_method_id UUID NOT NULL REFERENCES payment_methods(id), -- ✅ Dynamic reference
  amount NUMERIC(12,2),
  date TIMESTAMP WITH TIME ZONE,
  reference TEXT,
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE,
  updated_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_sales_payments_payment_method_id ON sales_payments(payment_method_id);
```

**Migration Logic** (in `core_schema.sql`):
```sql
DO $$
DECLARE
  v_has_method_column BOOLEAN;
  v_cash_method_id UUID;
BEGIN
  -- Check if old 'method' column exists
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sales_payments' AND column_name = 'method'
  ) INTO v_has_method_column;

  IF v_has_method_column THEN
    -- Add new payment_method_id column
    ALTER TABLE sales_payments ADD COLUMN payment_method_id UUID REFERENCES payment_methods(id);
    
    -- Migrate data: map old method values to payment_method_id
    UPDATE sales_payments sp
    SET payment_method_id = pm.id
    FROM payment_methods pm
    WHERE (sp.method = 'cash' AND pm.code = 'cash')
       OR (sp.method = 'transfer' AND pm.code = 'transfer')
       OR (sp.method = 'card' AND pm.code = 'card')
       OR (sp.method = 'check' AND pm.code = 'check')
       OR (sp.method = 'other' AND pm.code = 'cash'); -- Default 'other' to cash
    
    -- Drop old method column
    ALTER TABLE sales_payments DROP CONSTRAINT sales_payments_method_check;
    ALTER TABLE sales_payments DROP COLUMN method;
    
    -- Make payment_method_id NOT NULL
    ALTER TABLE sales_payments ALTER COLUMN payment_method_id SET NOT NULL;
  END IF;
END $$;
```

### 4. New Table: `purchase_payments`

```sql
CREATE TABLE IF NOT EXISTS purchase_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id UUID NOT NULL REFERENCES purchase_invoices(id) ON DELETE CASCADE,
  invoice_reference TEXT,
  payment_method_id UUID NOT NULL REFERENCES payment_methods(id), -- ✅ Dynamic reference
  amount NUMERIC(12,2) NOT NULL DEFAULT 0,
  date TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  reference TEXT,
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_purchase_payments_invoice_id ON purchase_payments(invoice_id);
CREATE INDEX idx_purchase_payments_payment_method_id ON purchase_payments(payment_method_id);
```

---

## 🔧 Function Updates

### Updated: `create_sales_payment_journal_entry()`

**Key Change**: Function now queries `payment_methods` table to get account dynamically.

```sql
CREATE OR REPLACE FUNCTION public.create_sales_payment_journal_entry(p_payment public.sales_payments)
RETURNS VOID AS $$
DECLARE
  v_payment_method RECORD;
  v_cash_account_id UUID;
  v_cash_account_code TEXT;
  v_cash_account_name TEXT;
  ...
BEGIN
  -- ⭐ Get payment method and its associated account (DYNAMIC!)
  SELECT pm.id, pm.code, pm.name, 
         a.id as account_id, a.code as account_code, a.name as account_name
  INTO v_payment_method
  FROM public.payment_methods pm
  JOIN public.accounts a ON a.id = pm.account_id
  WHERE pm.id = p_payment.payment_method_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment method not found for payment %', p_payment.id;
  END IF;

  -- Use the account from payment method configuration
  v_cash_account_id := v_payment_method.account_id;
  v_cash_account_code := v_payment_method.account_code;
  v_cash_account_name := v_payment_method.account_name;

  -- Create journal entry using dynamic account
  INSERT INTO journal_lines (account_id, account_code, account_name, ...)
  VALUES (v_cash_account_id, v_cash_account_code, v_cash_account_name, ...);
  ...
END;
$$;
```

**Before vs After**:
| Aspect | Before (Hardcoded) | After (Dynamic) |
|--------|-------------------|----------------|
| Method determination | CASE statement with 5 hardcoded values | Query payment_methods table |
| Account selection | Hardcoded codes ('1101', '1110', '1190') | Read from payment_methods.account_id |
| Adding new method | Requires code change + deployment | Just insert row in payment_methods |
| Multi-bank support | Not possible | Fully supported |

### New: `create_purchase_payment_journal_entry()`

**Mirrors sales payment pattern** with purchase-specific accounts:

```sql
CREATE OR REPLACE FUNCTION public.create_purchase_payment_journal_entry(p_payment public.purchase_payments)
RETURNS VOID AS $$
DECLARE
  v_payment_method RECORD;
  v_cash_account_id UUID;
  v_payable_account_id UUID;
  ...
BEGIN
  -- Get payment method and its associated account (DYNAMIC!)
  SELECT pm.id, pm.code, pm.name, a.id as account_id, a.code, a.name
  INTO v_payment_method
  FROM public.payment_methods pm
  JOIN public.accounts a ON a.id = pm.account_id
  WHERE pm.id = p_payment.payment_method_id;

  -- Use dynamic account
  v_cash_account_id := v_payment_method.account_id;

  -- Ensure payable account
  v_payable_account_id := ensure_account('2101', 'Cuentas por Pagar Proveedores', ...);

  -- Create journal entry
  INSERT INTO journal_entries (...) VALUES (...);
  
  -- DR: Accounts Payable (reduce liability)
  INSERT INTO journal_lines (account_id, debit_amount, ...) 
  VALUES (v_payable_account_id, p_payment.amount, ...);
  
  -- CR: Cash/Bank (reduce asset) ← Account from payment_methods!
  INSERT INTO journal_lines (account_id, credit_amount, ...) 
  VALUES (v_cash_account_id, p_payment.amount, ...);
END;
$$;
```

### New: `recalculate_purchase_invoice_payments()`

```sql
CREATE OR REPLACE FUNCTION public.recalculate_purchase_invoice_payments(p_invoice_id UUID)
RETURNS VOID AS $$
DECLARE
  v_total_paid NUMERIC(12,2);
  v_balance NUMERIC(12,2);
  v_new_status TEXT;
BEGIN
  SELECT COALESCE(SUM(amount), 0) INTO v_total_paid
  FROM purchase_payments
  WHERE invoice_id = p_invoice_id;

  v_balance := invoice.total - v_total_paid;

  IF v_total_paid >= invoice.total THEN
    v_new_status := 'paid';
  ELSIF v_total_paid > 0 THEN
    v_new_status := 'received';
  ELSE
    v_new_status := invoice.status;
  END IF;

  UPDATE purchase_invoices
  SET paid_amount = v_total_paid,
      balance = v_balance,
      status = v_new_status
  WHERE id = p_invoice_id;
END;
$$;
```

### New: `handle_purchase_payment_change()`

```sql
CREATE OR REPLACE FUNCTION public.handle_purchase_payment_change()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM create_purchase_payment_journal_entry(NEW);
    PERFORM recalculate_purchase_invoice_payments(NEW.invoice_id);
  ELSIF TG_OP = 'UPDATE' THEN
    PERFORM delete_purchase_payment_journal_entry(OLD.id);
    PERFORM create_purchase_payment_journal_entry(NEW);
    PERFORM recalculate_purchase_invoice_payments(NEW.invoice_id);
  ELSIF TG_OP = 'DELETE' THEN
    PERFORM delete_purchase_payment_journal_entry(OLD.id);
    PERFORM recalculate_purchase_invoice_payments(OLD.invoice_id);
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Trigger
CREATE TRIGGER trg_purchase_payments_change
  AFTER INSERT OR UPDATE OR DELETE ON purchase_payments
  FOR EACH ROW EXECUTE PROCEDURE handle_purchase_payment_change();
```

---

## 📱 UI Integration

### Payment Form (Sales & Purchases)

**Payment Method Dropdown** (Dynamic):
```dart
class PaymentForm extends StatefulWidget {
  List<Map<String, dynamic>> _paymentMethods = [];
  String? _selectedMethodId;
  bool _showReferenceField = false;

  @override
  void initState() {
    super.initState();
    _loadPaymentMethods();
  }

  Future<void> _loadPaymentMethods() async {
    final response = await _supabase
      .from('payment_methods')
      .select('*, accounts!payment_methods_account_id_fkey(*)')
      .eq('is_active', true)
      .order('sort_order');

    setState(() {
      _paymentMethods = response as List<Map<String, dynamic>>;
      _selectedMethodId = _paymentMethods.first['id'];
      _updateReferenceFieldVisibility();
    });
  }

  void _updateReferenceFieldVisibility() {
    final selectedMethod = _paymentMethods.firstWhere(
      (m) => m['id'] == _selectedMethodId,
    );
    setState(() {
      _showReferenceField = selectedMethod['requires_reference'] ?? false;
    });
  }

  Widget _buildPaymentMethodDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedMethodId,
      decoration: InputDecoration(
        labelText: 'Método de Pago',
        prefixIcon: Icon(_getMethodIcon()),
      ),
      items: _paymentMethods.map((method) {
        return DropdownMenuItem(
          value: method['id'],
          child: Row(
            children: [
              Icon(_getIconForCode(method['icon'])),
              SizedBox(width: 8),
              Text(method['name']),
              Text(' → ${method['accounts']['code']}', 
                   style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          _selectedMethodId = value;
          _updateReferenceFieldVisibility();
        });
      },
    );
  }

  Widget _buildReferenceField() {
    if (!_showReferenceField) return SizedBox.shrink();
    
    return TextFormField(
      controller: _referenceController,
      decoration: InputDecoration(
        labelText: 'Referencia / Nº de Transacción',
        hintText: 'Ej: 123456789',
      ),
      validator: (value) {
        if (_showReferenceField && (value == null || value.isEmpty)) {
          return 'Este método de pago requiere una referencia';
        }
        return null;
      },
    );
  }
}
```

### Payment Methods Management Page (CRUD)

**Location**: `lib/modules/accounting/payment_methods_list_page.dart`

**Features**:
- ✅ List all payment methods
- ✅ Add new payment method
- ✅ Edit existing payment method (name, account, reference requirement, icon)
- ✅ Toggle active/inactive
- ✅ Reorder via drag-and-drop (sort_order)
- ✅ Delete payment method (with safety check: prevent deletion if used in payments)

**Navigation**: Menú Contabilidad → Métodos de Pago

---

## 🚀 Deployment Instructions

### Step 1: Backup Current Database
```bash
pg_dump -U postgres -d vinabike_erp > backup_before_payment_methods.sql
```

### Step 2: Deploy Updated Schema
```bash
psql -U postgres -d vinabike_erp -f supabase/sql/core_schema.sql
```

**What Happens**:
1. ✅ `payment_methods` table created
2. ✅ 4 default payment methods seeded (Efectivo, Transferencia, Tarjeta, Cheque)
3. ✅ `sales_payments.method` column migrated to `payment_method_id`
4. ✅ Old `method` column and constraint dropped
5. ✅ `purchase_payments` table created with `payment_method_id`
6. ✅ All functions updated to use dynamic payment methods
7. ✅ Triggers created for purchase payment processing

### Step 3: Verify Migration
```sql
-- Check payment_methods table
SELECT * FROM payment_methods ORDER BY sort_order;

-- Check sales_payments migration
SELECT 
  sp.id, 
  sp.amount, 
  pm.name as payment_method, 
  a.code as account_code
FROM sales_payments sp
JOIN payment_methods pm ON pm.id = sp.payment_method_id
JOIN accounts a ON a.id = pm.account_id
LIMIT 10;

-- Check purchase_payments table exists
\d purchase_payments
```

### Step 4: Update Flutter App
```dart
// Update payment form to load payment methods dynamically
// Update payment display to show payment method name
// Add Payment Methods management page to Contabilidad menu
```

### Step 5: Test End-to-End
1. ✅ Create sales invoice → Pay with "Efectivo" → Verify journal uses 1101
2. ✅ Create sales invoice → Pay with "Transferencia" → Verify journal uses 1110
3. ✅ Create purchase invoice → Pay with "Tarjeta" → Verify journal uses 1110
4. ✅ Add new payment method "Transfer BCI" → Verify appears in dropdown
5. ✅ Pay invoice with "Transfer BCI" → Verify journal uses correct account

---

## ✅ Testing Checklist

### Database Tests
- [ ] `payment_methods` table created with 4 default methods
- [ ] `sales_payments` migrated successfully (no `method` column, has `payment_method_id`)
- [ ] `purchase_payments` table created with correct structure
- [ ] All functions compile without errors
- [ ] Triggers fire correctly on payment insert/update/delete

### Sales Invoice Tests
- [ ] Create invoice, mark as confirmed (accounting created)
- [ ] Pay with "Efectivo" → Journal entry uses 1101 Caja
- [ ] Pay with "Transferencia" → Journal entry uses 1110 Banco
- [ ] Undo payment → Payment journal entry deleted, invoice returns to "Confirmada"

### Purchase Invoice Tests
- [ ] Create invoice, confirm, receive goods (inventory increased)
- [ ] Pay with "Efectivo" → Journal entry uses 1101 Caja, AP reduced
- [ ] Pay with "Tarjeta" → Journal entry uses 1110 Banco, AP reduced
- [ ] Undo payment → Payment journal entry deleted, invoice returns to "Recibida"

### UI Tests
- [ ] Payment form dropdown shows all active payment methods
- [ ] Reference field appears only when `requires_reference = true`
- [ ] Payment method name displayed in payment list (not just code)
- [ ] Payment Methods management page accessible from Contabilidad menu
- [ ] Can add new payment method via UI
- [ ] Can edit payment method and change its account
- [ ] Can toggle payment method active/inactive

### Multi-Bank Tests
- [ ] Add custom method "Transfer BCI" linked to account 1110-BCI
- [ ] Add custom method "Transfer Santander" linked to account 1110-SANT
- [ ] Pay invoice with "Transfer BCI" → Verify journal uses 1110-BCI
- [ ] Verify different bank accounts tracked correctly

---

## 📊 Benefits Summary

| Aspect | Before | After |
|--------|--------|-------|
| **Adding Payment Method** | Requires code change, schema migration, deployment | Just insert row in payment_methods table via UI |
| **Account Assignment** | Hardcoded in 149-line function | Dynamic: reads from payment_methods.account_id |
| **Multi-Bank Support** | Not possible | Fully supported (unlimited bank accounts) |
| **Flexibility** | Low: changes require developer + deployment | High: accountants can configure via UI |
| **Code Maintainability** | Complex CASE statements in functions | Simple query to payment_methods table |
| **User Experience** | Fixed dropdown with 5 options | Dynamic dropdown with custom methods |
| **Audit Trail** | Method stored as string ('cash', 'transfer') | Method stored as UUID with full join to payment_methods |

---

## 🔮 Future Enhancements

### Phase 2: Advanced Features
- [ ] **Payment Method Icons**: Use actual Material Icons codes in database
- [ ] **Multi-Currency Support**: Add `currency` field to payment_methods
- [ ] **Payment Fees**: Add `fee_percentage` and `fee_account_id` for card processing fees
- [ ] **Payment Gateways**: Link to payment gateway configuration (Mercado Pago, Transbank)
- [ ] **Payment Templates**: Save common payment method + amount combinations
- [ ] **Recurring Payments**: Link payment methods to subscription management

### Phase 3: Analytics
- [ ] Payment methods dashboard (most used, total by method, trends)
- [ ] Account reconciliation by payment method
- [ ] Bank account balance tracking
- [ ] Cash flow forecasting by payment method

---

## 📚 Related Documentation

- ✅ `core_schema.sql` - Updated with payment_methods table and functions
- ✅ `Invoice_status_flow.md` - Sales invoice workflow with dynamic payment methods
- ✅ `Purchase_Invoice_status_flow.md` - Purchase invoice workflow with dynamic payment methods
- ⏳ `Purchase_Invoice_Prepayment_Flow.md` - To be updated with simplified accounting
- ✅ `copilot-instructions.md` - Updated with payment methods architecture guidelines

---

## 🎯 Key Takeaways

1. **Payment methods are now data, not code** → Configure via UI, no deployments needed
2. **Account assignment is dynamic** → Read from payment_methods.account_id at runtime
3. **Multi-bank support is built-in** → Add unlimited bank accounts, each as a payment method
4. **Consistent pattern** → Same approach for sales and purchase invoices
5. **Migration is automatic** → Old `method` column data safely migrated to `payment_method_id`

**This is the foundation for a flexible, enterprise-grade payment management system!** 🚀
