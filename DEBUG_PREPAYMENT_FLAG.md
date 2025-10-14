# 🔍 DEBUG: Prepayment Flag Investigation

## 📋 Issue Status

**User Report**: "The problem persists, I select prepayment and it still creates a regular invoice"  
**Date**: 2025-10-13  
**Status**: 🔍 INVESTIGATING with debug logs

---

## 🧪 Debug Logging Added

### 1. Route Parameter Logging (`app_router.dart` line 353)

```dart
GoRoute(
  path: '/purchases/new',
  pageBuilder: (context, state) {
    final prepaymentParam = state.uri.queryParameters['prepayment'];
    final isPrepayment = prepaymentParam == 'true';
    print('🔍 DEBUG: prepayment param = "$prepaymentParam", isPrepayment = $isPrepayment');
    return _buildPageWithNoTransition(
      context,
      state,
      PurchaseInvoiceFormPage(isPrepayment: isPrepayment),
    );
  },
),
```

**Expected Output:**
- User selects "Prepayment Model" → should see: `🔍 DEBUG: prepayment param = "true", isPrepayment = true`
- User selects "Standard Model" → should see: `🔍 DEBUG: prepayment param = "false", isPrepayment = false`

### 2. Form Initialization Logging (`purchase_invoice_form_page.dart` line 62)

```dart
@override
void initState() {
  super.initState();
  print('🔍 DEBUG Form: isPrepayment = ${widget.isPrepayment}');
  ...
}
```

**Expected Output:**
- Should match the route parameter value
- `🔍 DEBUG Form: isPrepayment = true` (for prepayment)
- `🔍 DEBUG Form: isPrepayment = false` (for standard)

### 3. Save Operation Logging (`purchase_invoice_form_page.dart` line 392)

```dart
// Set prepayment model when creating new invoice
prepaymentModel: _loadedInvoice != null 
    ? _loadedInvoice!.prepaymentModel 
    : widget.isPrepayment,
);

print('🔍 DEBUG Save: prepaymentModel = ${invoice.prepaymentModel}');
print('🔍 DEBUG Save: invoice toJson = ${invoice.toJson()}');
```

**Expected Output:**
- `🔍 DEBUG Save: prepaymentModel = true` (for prepayment)
- `🔍 DEBUG Save: invoice toJson = {..., "prepayment_model": true, ...}`

---

## 🧪 Testing Steps

### Step 1: Create Prepayment Invoice

1. **Click** "New Purchase Invoice" button
2. **Select** "Pago Anticipado (Prepago)" option (orange, with payment icon)
3. **Click** "Continuar"
4. **Check Console** - Look for:
   ```
   🔍 DEBUG: prepayment param = "true", isPrepayment = true
   🔍 DEBUG Form: isPrepayment = true
   ```

5. **Fill Form**:
   - Supplier: Any
   - Items: Add at least one product
   - Amounts: Verify calculations

6. **Click** "Guardar" (Save)
7. **Check Console** - Look for:
   ```
   🔍 DEBUG Save: prepaymentModel = true
   🔍 DEBUG Save: invoice toJson = {..., "prepayment_model": true, ...}
   ```

8. **Check Database** (Supabase):
   ```sql
   SELECT id, invoice_number, prepayment_model, status
   FROM purchase_invoices
   ORDER BY created_at DESC
   LIMIT 1;
   ```
   - Should show: `prepayment_model = true`

### Step 2: Create Standard Invoice

1. **Click** "New Purchase Invoice" button
2. **Select** "Pago Después de Recibir (Modelo Estándar)" (blue, with shipping icon)
3. **Click** "Continuar"
4. **Check Console** - Look for:
   ```
   🔍 DEBUG: prepayment param = "false", isPrepayment = false
   🔍 DEBUG Form: isPrepayment = false
   ```

5. **Fill Form and Save**
6. **Check Console** - Look for:
   ```
   🔍 DEBUG Save: prepaymentModel = false
   🔍 DEBUG Save: invoice toJson = {..., "prepayment_model": false, ...}
   ```

7. **Check Database**:
   - Should show: `prepayment_model = false`

---

## 🔍 Possible Issues to Identify

### Issue A: Dialog Not Returning Correct Value

**Symptoms:**
```
🔍 DEBUG: prepayment param = "null", isPrepayment = false
```
or
```
🔍 DEBUG: prepayment param = "false", isPrepayment = false  (even when prepayment selected)
```

**Cause:** Dialog returning wrong value or navigation not passing parameter correctly

**Fix Location:** `purchase_invoice_list_page.dart` line 138-146

### Issue B: Route Not Parsing Parameter

**Symptoms:**
```
🔍 DEBUG: prepayment param = "true", isPrepayment = false
```

**Cause:** String comparison failing (maybe "true" vs "True" vs true)

**Fix Location:** `app_router.dart` line 352-353

### Issue C: Form Not Using Parameter

**Symptoms:**
```
🔍 DEBUG Form: isPrepayment = true
🔍 DEBUG Save: prepaymentModel = false
```

**Cause:** Form using wrong variable or condition in `prepaymentModel` assignment

**Fix Location:** `purchase_invoice_form_page.dart` line 387-390

### Issue D: JSON Serialization Issue

**Symptoms:**
```
🔍 DEBUG Save: prepaymentModel = true
🔍 DEBUG Save: invoice toJson = {..., "prepayment_model": false, ...}
```

**Cause:** `toJson()` method not correctly serializing the field

**Fix Location:** `purchase_invoice.dart` line 193

### Issue E: Database Column Not Updated

**Symptoms:**
- All debug logs show `true`
- But database shows `false`

**Cause:** Database schema not deployed or column doesn't exist

**Fix:** Deploy `core_schema.sql` to Supabase

---

## 📊 Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ 1. User clicks "New Purchase Invoice"                       │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. showPurchaseModelSelectionDialog(context)                │
│    User selects: "Prepayment Model"                         │
│    Returns: true                                            │
│    ⚠️ CHECK: Is this returning true?                        │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. context.push('/purchases/new?prepayment=$isPrepayment')  │
│    URL: /purchases/new?prepayment=true                      │
│    ⚠️ CHECK: Is URL correct?                                │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. GoRouter parses query parameter                          │
│    prepaymentParam = state.uri.queryParameters['prepayment']│
│    isPrepayment = prepaymentParam == 'true'                 │
│    🔍 DEBUG LOG HERE                                         │
│    ⚠️ CHECK: Is isPrepayment = true?                        │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. PurchaseInvoiceFormPage(isPrepayment: true)              │
│    🔍 DEBUG LOG HERE                                         │
│    ⚠️ CHECK: Is widget.isPrepayment = true?                 │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ 6. User fills form and clicks Save                          │
│    prepaymentModel: widget.isPrepayment                     │
│    🔍 DEBUG LOG HERE                                         │
│    ⚠️ CHECK: Is invoice.prepaymentModel = true?             │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ 7. invoice.toJson()                                         │
│    'prepayment_model': prepaymentModel                      │
│    🔍 DEBUG LOG HERE                                         │
│    ⚠️ CHECK: Is JSON['prepayment_model'] = true?            │
└─────────────────────────────────────────────────────────────┘
                           ▼
┌─────────────────────────────────────────────────────────────┐
│ 8. Supabase INSERT                                          │
│    ⚠️ CHECK: Does database show prepayment_model = true?    │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎯 Next Steps

1. ✅ **Run the app** (currently building)
2. ✅ **Follow testing steps** above
3. ✅ **Copy console output** and share with me
4. ✅ **Check database** and share the query result
5. ✅ **Identify which step fails** using the data flow diagram

---

## 📝 Information Needed

Please provide:

1. **Full console output** when creating a prepayment invoice (all 🔍 DEBUG lines)
2. **Database query result**:
   ```sql
   SELECT id, invoice_number, prepayment_model, status, tax, total
   FROM purchase_invoices
   WHERE invoice_number = 'YOUR-INVOICE-NUMBER'
   LIMIT 1;
   ```
3. **Screenshot** of the model selection dialog when you select prepayment
4. **Any error messages** in the console or UI

---

**Created**: 2025-10-13  
**Purpose**: Debug prepayment flag not saving correctly  
**Status**: Awaiting test results with debug logs
