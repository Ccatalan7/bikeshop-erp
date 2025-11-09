# ✅ Phase 2 COMPLETE: Flutter Models Updated for Flexible Tax System

**Date:** November 8, 2025  
**Status:** ✅ All models updated and compiling successfully

---

## 📦 Files Created/Modified

### 1. NEW: TaxTreatment Enum
**File:** `lib/shared/models/tax_treatment.dart`

```dart
enum TaxTreatment {
  noTax('no_tax'),           // Full amount = revenue/cost
  taxIncluded('tax_included') // Amount includes 19% IVA (÷1.19 for net)
}
```

**Features:**
- ✅ Matches database check constraint values
- ✅ `fromString()` method for database parsing
- ✅ `toValue()` method for database serialization

---

### 2. UPDATED: PaymentMethod Model
**File:** `lib/shared/models/payment_method.dart`

**Added Fields:**
```dart
final TaxTreatment defaultTaxTreatment; // suggested tax treatment for invoices
```

**Changes:**
- ✅ Import `tax_treatment.dart`
- ✅ Added field to constructor with default `TaxTreatment.noTax`
- ✅ Updated `fromJson()` to parse `default_tax_treatment` column
- ✅ Updated `toJson()` to serialize as `'default_tax_treatment': defaultTaxTreatment.toValue()`
- ✅ Updated `copyWith()` to include `defaultTaxTreatment` parameter

**Usage:**
```dart
// Card payment method will suggest tax_included by default
final cardMethod = PaymentMethod(
  defaultTaxTreatment: TaxTreatment.taxIncluded,
  // ... other fields
);
```

---

### 3. UPDATED: Supplier Model
**File:** `lib/modules/purchases/models/supplier.dart`

**Added Fields:**
```dart
final TaxTreatment defaultTaxTreatment; // suggested tax treatment for purchases
```

**Changes:**
- ✅ Import `tax_treatment.dart`
- ✅ Added field to constructor with default `TaxTreatment.noTax`
- ✅ Updated `fromJson()` to parse `default_tax_treatment` column
- ✅ Updated `toJson()` to serialize as `'default_tax_treatment': defaultTaxTreatment.toValue()`
- ✅ Updated `copyWith()` to include `defaultTaxTreatment` parameter

**Usage:**
```dart
// Local supplier with invoices suggests tax_included
final supplier = Supplier(
  name: 'Proveedor Local',
  defaultTaxTreatment: TaxTreatment.taxIncluded,
  // ... other fields
);
```

---

### 4. UPDATED: Invoice Model (Sales)
**File:** `lib/modules/sales/models/sales_models.dart`

**Added Fields:**
```dart
final TaxTreatment taxTreatment; // actual tax choice for this invoice
final double netAmount;          // net amount before IVA (total÷1.19 when tax_included)
```

**Changes:**
- ✅ Import `tax_treatment.dart`
- ✅ Added fields to constructor with defaults (`TaxTreatment.noTax`, `0`)
- ✅ Updated `fromJson()` to parse `tax_treatment` and `net_amount` columns
- ✅ Updated `toFirestoreMap()` to serialize both fields
- ✅ Updated `copyWith()` to include both parameters

**Usage:**
```dart
// Cash sale without tax
final invoice = Invoice(
  total: 1000,
  taxTreatment: TaxTreatment.noTax,
  netAmount: 1000, // full amount is revenue
  // ... other fields
);

// Card sale with tax included
final invoiceWithTax = Invoice(
  total: 1000,
  taxTreatment: TaxTreatment.taxIncluded,
  netAmount: 840.34,  // 1000 ÷ 1.19
  ivaAmount: 159.66,  // 1000 - 840.34
  // ... other fields
);
```

---

### 5. UPDATED: PurchaseInvoice Model
**File:** `lib/modules/purchases/models/purchase_invoice.dart`

**Added Fields:**
```dart
final TaxTreatment taxTreatment; // actual tax choice for this purchase
final double netAmount;          // net amount before IVA (total÷1.19 when tax_included)
```

**Changes:**
- ✅ Import `tax_treatment.dart`
- ✅ Added fields to constructor with defaults (`TaxTreatment.noTax`, `0`)
- ✅ Updated `fromJson()` to parse `tax_treatment` and `net_amount` columns
- ✅ Updated `toJson()` to serialize both fields
- ✅ Updated `copyWith()` to include both parameters

**Usage:**
```dart
// AliExpress purchase without tax
final purchase = PurchaseInvoice(
  total: 5000,
  taxTreatment: TaxTreatment.noTax,
  netAmount: 5000, // full amount is cost
  // ... other fields
);

// Local supplier purchase with IVA Crédito
final purchaseWithTax = PurchaseInvoice(
  total: 5000,
  taxTreatment: TaxTreatment.taxIncluded,
  netAmount: 4201.68, // 5000 ÷ 1.19
  ivaAmount: 798.32,  // recoverable tax credit
  // ... other fields
);
```

---

## ✅ Verification

**Compilation Status:**
```bash
$ flutter analyze lib/shared/models/payment_method.dart lib/shared/models/tax_treatment.dart \
  lib/modules/purchases/models/supplier.dart lib/modules/sales/models/sales_models.dart \
  lib/modules/purchases/models/purchase_invoice.dart

No issues found! (ran in 0.2s)
```

---

## 🎯 Three-Layer Smart System

### Layer 1: Global Defaults (Database)
```sql
-- Smart defaults for new tenants (already deployed)
INSERT INTO payment_methods (code, name, default_tax_treatment) VALUES
  ('cash', 'Efectivo', 'no_tax'),           -- Cash: typically no SII registration
  ('transfer', 'Transferencia', 'no_tax'),  -- Transfer: typically no SII registration
  ('check', 'Cheque', 'no_tax'),           -- Check: typically no SII registration
  ('card', 'Tarjeta', 'tax_included');     -- Card: typically registered with SII
```

### Layer 2: Entity Defaults (Models)
```dart
// Payment Method suggests tax behavior
final paymentMethod = PaymentMethod(
  code: 'card',
  name: 'Tarjeta de Crédito',
  defaultTaxTreatment: TaxTreatment.taxIncluded, // ← Suggestion
);

// Supplier suggests tax behavior
final supplier = Supplier(
  name: 'Proveedor Local',
  defaultTaxTreatment: TaxTreatment.taxIncluded, // ← Suggestion
);
```

### Layer 3: Transaction Control (Final Authority)
```dart
// Invoice stores ACTUAL choice (user can override)
final invoice = Invoice(
  customerId: '...',
  total: 1000,
  taxTreatment: TaxTreatment.taxIncluded, // ← User's actual choice
  netAmount: 840.34,                       // ← Calculated based on choice
  ivaAmount: 159.66,
);
```

---

## 📝 Next Steps

### Phase 3: Sales Invoice Form (NEXT)
- Add IVA dropdown to `invoice_form_page.dart`
- Auto-set default from selected payment method
- Real-time calculation of net/tax/total when dropdown changes
- Clean, professional UI (no hints in form)

### Phase 4: Purchase Invoice Form
- Add IVA dropdown to `purchase_invoice_form_page.dart`
- Auto-set default from selected supplier
- Real-time calculation for IVA Crédito

### Phase 5: POS Module
- Add tax control to checkout flow
- Update receipt generation with tax breakdown

### Phase 6: Settings UI
- Payment methods config page (show default tax with hint)
- Suppliers config page (show default tax with hint)

### Phase 7: Accounting Triggers
- Update `create_sales_invoice_journal_entry()` function
- Update `create_purchase_invoice_journal_entry()` function
- Use `invoices.tax_treatment` instead of assuming

### Phase 8: Testing
- Test card sale with tax (1000 → 840.34 net + 159.66 IVA)
- Test cash sale without tax (1000 → 1000 revenue)
- Test override scenarios
- Verify journal entries balance

---

## 🧮 Tax Calculation Reference

### When `taxTreatment = TaxTreatment.taxIncluded`:
```
Chilean IVA Rate: 19%
Divisor: 1.19

Given total = $1000:
  net_amount = 1000 ÷ 1.19 = 840.34
  iva_amount = 1000 - 840.34 = 159.66
  
Verification: 840.34 × 1.19 = 1000 ✓
```

### When `taxTreatment = TaxTreatment.noTax`:
```
Given total = $1000:
  net_amount = 1000 (full amount)
  iva_amount = 0
  
Revenue/Cost = $1000 (no tax split)
```

---

## 🚀 Deployment Notes

**Database Schema:**
- Already deployed in Phase 1 (`core_schema.sql` modified)
- All tables have new columns with safe defaults
- Backward compatible migrations included

**Flutter Models:**
- All models updated and compiling ✓
- No breaking changes (all new fields have defaults)
- Existing code will continue to work
- New forms will use the tax fields

**Ready for Phase 3:** Start implementing invoice form UI with tax dropdown.
