# ✅ Phase 1 Complete: SQL Functions for Financial Reports

**Status**: Ready for deployment to Supabase

---

## 📦 What Was Added

I've added **10 PostgreSQL functions** to `core_schema.sql` that power all financial reporting. These functions are optimized, secure, and follow Chilean accounting standards.

---

## 🔧 Functions Created

### **Core Balance Functions**

#### 1. `get_account_balance(account_id, start_date, end_date)`
**Purpose**: Get the balance of a single account for a specific period

**Returns**: `NUMERIC(14,2)` - Account balance in CLP

**Logic**:
- Assets/Expenses: Debit - Credit (normal debit balance)
- Liabilities/Equity/Income: Credit - Debit (normal credit balance)
- Only includes POSTED journal entries

**Example Usage**:
```sql
-- Get cash account balance for October 2025
SELECT get_account_balance(
  '550e8400-e29b-41d4-a716-446655440000', 
  '2025-10-01'::timestamp, 
  '2025-10-31'::timestamp
);
-- Returns: 5000000.00 (CLP $5,000,000)
```

---

#### 2. `get_balances_by_type(account_type, start_date, end_date)`
**Purpose**: Get all accounts of a specific type with balances

**Parameters**:
- `account_type`: 'asset', 'liability', 'equity', 'income', 'expense', 'tax'

**Returns**: Table with columns:
- `account_id`, `account_code`, `account_name`, `account_category`
- `parent_id`, `debit_total`, `credit_total`, `balance`

**Example Usage**:
```sql
-- Get all income accounts for Q3 2025
SELECT * FROM get_balances_by_type(
  'income', 
  '2025-07-01'::timestamp, 
  '2025-09-30'::timestamp
);
```

---

#### 3. `get_balances_by_category(account_category, start_date, end_date)`
**Purpose**: Get accounts by granular category (more specific than type)

**Categories**: 
- `currentAsset`, `fixedAsset`, `currentLiability`, `longTermLiability`
- `operatingIncome`, `nonOperatingIncome`, `costOfGoodsSold`
- `operatingExpense`, `financialExpense`, `taxExpense`

**Example Usage**:
```sql
-- Get all operating expenses for September 2025
SELECT * FROM get_balances_by_category(
  'operatingExpense', 
  '2025-09-01'::timestamp, 
  '2025-09-30'::timestamp
);
```

---

### **Report-Specific Functions**

#### 4. `get_trial_balance(start_date, end_date)`
**Purpose**: Generate trial balance (all accounts with activity)

**Returns**: Table with:
- `account_code`, `account_name`, `account_type`, `account_category`
- `debit_total`, `credit_total`, `balance`

**Key Feature**: Only includes accounts with activity (non-zero balances)

**Example Usage**:
```sql
-- Trial balance for October 2025
SELECT * FROM get_trial_balance(
  '2025-10-01'::timestamp, 
  '2025-10-31'::timestamp
)
ORDER BY account_code;
```

---

#### 5. `calculate_net_income(start_date, end_date)`
**Purpose**: Calculate bottom line for Income Statement

**Formula**: Total Income - Total Expenses = Net Income

**Returns**: `NUMERIC(14,2)` - Net profit/loss

**Example Usage**:
```sql
-- Net income for 2025
SELECT calculate_net_income(
  '2025-01-01'::timestamp, 
  '2025-12-31'::timestamp
);
-- Returns: 15000000.00 (CLP $15M profit)
-- Negative = loss
```

---

### **Balance Sheet Functions**

#### 6. `get_cumulative_balance(account_id, as_of_date)`
**Purpose**: Get account balance from beginning of time up to a date

**Key Difference**: Unlike period balance, this is CUMULATIVE
- Used for Balance Sheet (point-in-time snapshot)
- Not just a period range

**Example Usage**:
```sql
-- Cash balance as of December 31, 2025
SELECT get_cumulative_balance(
  '550e8400-e29b-41d4-a716-446655440000', 
  '2025-12-31'::timestamp
);
```

---

#### 7. `get_cumulative_balances_by_type(account_type, as_of_date)`
**Purpose**: Get all accounts of a type with cumulative balances

**Example Usage**:
```sql
-- All asset balances as of today
SELECT * FROM get_cumulative_balances_by_type(
  'asset', 
  now()
);
```

---

### **Validation Functions**

#### 8. `verify_accounting_equation(as_of_date)`
**Purpose**: Verify that Assets = Liabilities + Equity

**Returns**: Table with:
- `is_balanced` (boolean) - TRUE if equation holds
- `total_assets`, `total_liabilities`, `total_equity`
- `difference` - How far off (should be < $1 CLP)

**Tolerance**: Considers balanced if difference < 1.00 CLP (rounding tolerance)

**Example Usage**:
```sql
-- Check if books are balanced as of today
SELECT * FROM verify_accounting_equation(now());

-- Expected output:
-- is_balanced | total_assets | total_liabilities | total_equity | difference
-- TRUE        | 50000000.00  | 25000000.00       | 25000000.00  | 0.00
```

---

### **Report Data Functions**

#### 9. `get_income_statement_data(start_date, end_date)`
**Purpose**: Get pre-formatted data for Income Statement report

**Returns**: Table with:
- `category`, `category_label` (Spanish labels)
- `account_code`, `account_name`, `amount`

**Categories Returned**:
- Ingresos Operacionales
- Ingresos No Operacionales
- Costo de Ventas
- Gastos Operacionales
- Gastos Financieros
- Impuestos

**Sorting**: Automatically orders by Income → Expenses

**Example Usage**:
```sql
-- Income statement data for October 2025
SELECT * FROM get_income_statement_data(
  '2025-10-01'::timestamp, 
  '2025-10-31'::timestamp
);
```

---

#### 10. `get_balance_sheet_data(as_of_date)`
**Purpose**: Get pre-formatted data for Balance Sheet report

**Returns**: Table with:
- `account_type`, `type_label` (ACTIVOS, PASIVOS, PATRIMONIO)
- `category`, `category_label` (Spanish labels)
- `account_code`, `account_name`, `amount`

**Categories Returned**:
- **ACTIVOS**: Activos Circulantes, Activos Fijos, Otros Activos
- **PASIVOS**: Pasivos Circulantes, Pasivos Largo Plazo
- **PATRIMONIO**: Capital, Utilidades Retenidas

**Sorting**: Automatically orders by Assets → Liabilities → Equity

**Example Usage**:
```sql
-- Balance sheet data as of Dec 31, 2025
SELECT * FROM get_balance_sheet_data(
  '2025-12-31'::timestamp
);
```

---

## 🔐 Security Features

All functions use:
- `SECURITY DEFINER` - Run with creator's privileges (safe database access)
- `SET search_path = public` - Prevents SQL injection via search path
- Input validation - Checks for null account IDs, invalid dates
- Type safety - Explicit NUMERIC(14,2) for all monetary values

---

## ⚡ Performance Optimizations

### Existing Indexes Used:
- `idx_journal_lines_entry_id` - Fast join with journal_entries
- `idx_journal_entries_date` - Fast date range filtering
- `idx_journal_entries_entry_number` - Quick lookups

### Query Patterns:
- Uses LEFT JOIN for accounts with no activity
- Filters by `status = 'posted'` to exclude drafts
- Groups at database level (faster than app-level grouping)
- Uses COALESCE to handle nulls efficiently

---

## 🧪 Testing the Functions

### Test Script (run in Supabase SQL Editor):

```sql
-- Test 1: Get cash account balance for current month
SELECT get_account_balance(
  (SELECT id FROM accounts WHERE code = '1101'), 
  date_trunc('month', now()),
  now()
) as cash_balance;

-- Test 2: Get all income accounts with balances
SELECT * FROM get_balances_by_type(
  'income',
  date_trunc('month', now()),
  now()
);

-- Test 3: Calculate current month net income
SELECT calculate_net_income(
  date_trunc('month', now()),
  now()
) as net_income;

-- Test 4: Verify books are balanced
SELECT * FROM verify_accounting_equation(now());

-- Test 5: Preview Income Statement data
SELECT 
  category_label,
  account_code,
  account_name,
  to_char(amount, 'FM$999,999,999') as formatted_amount
FROM get_income_statement_data(
  date_trunc('month', now()),
  now()
)
ORDER BY category, account_code;

-- Test 6: Preview Balance Sheet data
SELECT 
  type_label,
  category_label,
  account_code,
  account_name,
  to_char(amount, 'FM$999,999,999') as formatted_amount
FROM get_balance_sheet_data(now())
ORDER BY account_type, category, account_code;
```

---

## 📊 Chilean Accounting Compliance

### Account Type Logic:
✅ **Normal Debit Balances**: Assets, Expenses
- Formula: Debit - Credit
- Example: Cash = $5,000 debit - $1,000 credit = $4,000 balance

✅ **Normal Credit Balances**: Liabilities, Equity, Income
- Formula: Credit - Debit
- Example: Sales = $10,000 credit - $500 credit note = $9,500 balance

### IVA Treatment:
- IVA Crédito Fiscal (2150): Counted as Asset
- IVA Débito Fiscal (2160): Counted as Liability
- Net IVA = Débito - Crédito (monthly settlement)

### Posted Entries Only:
- Functions only count journal entries with `status = 'posted'`
- Drafts and pending entries are excluded
- Ensures audit trail integrity

---

## 🚀 Next Steps

Now that the SQL foundation is complete, we can move to **Phase 2**:

### Phase 2A: Flutter Models
Create these files:
1. `lib/modules/accounting/models/financial_report.dart` (base class)
2. `lib/modules/accounting/models/report_line.dart` (display model)
3. `lib/modules/accounting/models/income_statement.dart`
4. `lib/modules/accounting/models/balance_sheet.dart`

### Phase 2B: Service Layer
Create:
1. `lib/modules/accounting/services/financial_reports_service.dart`
   - Calls SQL functions
   - Transforms data into models
   - Calculates subtotals and ratios

### Phase 2C: Widgets
Create:
1. `lib/modules/accounting/widgets/report_header_widget.dart`
2. `lib/modules/accounting/widgets/report_line_widget.dart`
3. `lib/modules/accounting/widgets/date_range_selector.dart`

---

## 📝 Deployment Instructions

### To deploy these functions to Supabase:

1. **Open Supabase Dashboard** → Your project → SQL Editor

2. **Copy entire `core_schema.sql` file**

3. **Click "New Query"** and paste the file

4. **Run the query** (this is idempotent - safe to run multiple times)

5. **Verify deployment**:
   ```sql
   -- Check that functions exist
   SELECT routine_name, routine_type
   FROM information_schema.routines
   WHERE routine_schema = 'public'
     AND routine_name LIKE '%balance%'
        OR routine_name LIKE '%income%'
        OR routine_name LIKE '%accounting%'
   ORDER BY routine_name;
   ```

6. **Test functions** (use test script above)

---

## ✅ Checklist

- [x] 10 SQL functions created
- [x] Security definer mode enabled
- [x] Chilean accounting logic implemented
- [x] Period vs cumulative balance distinction
- [x] Trial balance function
- [x] Net income calculation
- [x] Accounting equation verification
- [x] Pre-formatted report data functions
- [x] Documentation complete
- [x] Test script provided

**Ready for deployment!** 🎉

---

**Would you like me to proceed with Phase 2 (Flutter models and service layer)?**
