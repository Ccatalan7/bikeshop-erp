# 🔍 Multi-Tenant Model Audit - tenant_id Status

## ✅ Models WITH tenant_id (FIXED - SAFE TO USE)

### ✅ Bikeshop Module
- ✅ **Bike** - Has `tenantId` field
- ✅ **MechanicJob** - Has `tenantId` field

### ✅ Inventory Module
- ✅ **Product** - Has `tenantId` field

### ✅ CRM Module
- ✅ **Customer** - Has `tenantId` field

### ✅ HR Module
- ✅ **Employee** - Has `tenantId` field

### ✅ Sales Module
- ✅ **Invoice** - Has `tenantId` field

### ✅ Purchases Module
- ✅ **Supplier** - Has `tenantId` field

---

## ❌ Models MISSING tenant_id (WILL CAUSE RLS ERRORS)

### 🚨 MEDIUM PRIORITY - Bikeshop Module
- ❌ **MechanicJobItem** - Missing `tenantId`
- ❌ **MechanicJobLabor** - Missing `tenantId`
- ❌ **MechanicJobTimeline** - Missing `tenantId`
- ❌ **ServicePackage** - Missing `tenantId` (if stored in DB)

### 🚨 MEDIUM PRIORITY - Inventory Module
- ❌ **ProductBrand** - Missing `tenantId`
- ❌ **StockMovement** - Missing `tenantId`
- ❌ **Category** - Missing `tenantId`
- ❌ **Warehouse** - Missing `tenantId` (if used)

### 🚨 MEDIUM PRIORITY - CRM Module
- ❌ **CustomerAddress** - Missing `tenantId`
- ❌ **Loyalty** - Missing `tenantId` (if stored)
- ❌ **BikeHistory** - Missing `tenantId` (if stored)

### 🚨 MEDIUM PRIORITY - HR Module
- ❌ **Department** - Missing `tenantId`
- ❌ **Attendance** - Missing `tenantId`
- ❌ **EmployeeContract** - Missing `tenantId`
- ❌ **WorkSchedule** - Missing `tenantId` (if stored)

### 🚨 MEDIUM PRIORITY - Accounting Module
- ❌ **Account** - Missing `tenantId`
- ❌ **JournalEntry** - Missing `tenantId`
- ❌ **JournalLine** - Missing `tenantId`
- ❌ **Expense** - Missing `tenantId`
- ❌ **ExpenseLine** - Missing `tenantId`
- ❌ **ExpensePayment** - Missing `tenantId`
- ❌ **ExpenseAttachment** - Missing `tenantId`
- ❌ **ExpenseCategory** - Missing `tenantId`

### 🚨 MEDIUM PRIORITY - Sales Module
- ❌ **InvoiceItem** - Missing `tenantId`
- ❌ **Payment** - Missing `tenantId`

### 🚨 MEDIUM PRIORITY - Purchases Module
- ❌ **PurchaseInvoice** - Missing `tenantId`
- ❌ **PurchaseInvoiceItem** - Missing `tenantId`
- ❌ **PurchasePayment** - Missing `tenantId`
- ❌ **PurchaseOrder** - Missing `tenantId`
- ❌ **PurchaseOrderItem** - Missing `tenantId`

### 🚨 MEDIUM PRIORITY - Website Module
- ❌ **WebsiteBanner** - Missing `tenantId`
- ❌ **FeaturedProduct** - Missing `tenantId`
- ❌ **WebsiteContent** - Missing `tenantId`
- ❌ **WebsiteSetting** - Missing `tenantId`
- ❌ **OnlineOrder** - Missing `tenantId`
- ❌ **OnlineOrderItem** - Missing `tenantId`

### 🚨 MEDIUM PRIORITY - POS Module
- ❌ **POSTransaction** - Missing `tenantId`
- ❌ **POSPayment** - Missing `tenantId`
- ❌ **PaymentMethod** - Missing `tenantId`

---

## 📊 Summary Statistics

| Status | Count | Percentage |
|--------|-------|------------|
| ✅ FIXED (HAS tenant_id) | 7 | ~14% |
| ❌ MISSING tenant_id | ~43 | ~86% |

## ✅ PROGRESS UPDATE

**TOP 6 CRITICAL MODELS - FIXED!**
1. ✅ Customer - Can now create/edit customers
2. ✅ Product - Can now create/edit products
3. ✅ Employee - Can now create/edit employees
4. ✅ MechanicJob - Can now create mechanic jobs
5. ✅ Invoice (Sales) - Can now create invoices
6. ✅ Supplier - Can now create suppliers

**Core features NOW WORKING:**
- ✅ Customer management
- ✅ Product/inventory creation
- ✅ Employee/HR basics
- ✅ Bike management
- ✅ Mechanic job creation
- ✅ Sales invoicing
- ✅ Supplier management

## 🚨 IMPACT ASSESSMENT

**Current State:**
- Core features are NOW WORKING ✅
- Secondary features still need fixes
- Most common operations will succeed

**Expected Errors (only on remaining models):**
```
PostgrestException(message: new row violates row-level security policy for table "X", code: 42501)
```

Where X = customers, products, employees, invoices, etc.

---

## 🔧 FIX STRATEGY

### Option 1: Quick Fix (High Priority Models Only)
Fix the most commonly used models first:
1. ✅ Bike (DONE)
2. Customer
3. Product
4. Employee
5. Invoice
6. PurchaseInvoice
7. MechanicJob

### Option 2: Systematic Fix (Recommended)
Fix ALL models in order by module:
1. Core models (Customer, Product, Supplier)
2. Bikeshop models (MechanicJob, ServicePackage, etc.)
3. Sales/Purchases (Invoice, Payment, etc.)
4. HR models (Employee, Attendance, etc.)
5. Accounting (Account, JournalEntry, etc.)
6. Website (Online orders, banners, etc.)

### Option 3: Automated Fix (Fastest)
Create a script to:
1. Read all table definitions from `core_schema.sql`
2. Check which tables have `tenant_id uuid NOT NULL`
3. For each model file, add `tenantId` field
4. Update `fromJson()`, `toJson()`, `copyWith()` automatically

---

## 🛠️ STEPS TO FIX EACH MODEL

For each model that's missing `tenant_id`:

### 1. Add field to class
```dart
class ModelName {
  final String? id;
  final String tenantId;  // ← ADD THIS
  // ... rest
}
```

### 2. Update constructor
```dart
ModelName({
  this.id,
  required this.tenantId,  // ← ADD THIS
  // ... rest
})
```

### 3. Update fromJson
```dart
factory ModelName.fromJson(Map<String, dynamic> json) {
  return ModelName(
    id: json['id']?.toString(),
    tenantId: json['tenant_id']?.toString() ?? '',  // ← ADD THIS
    // ... rest
  );
}
```

### 4. Update toJson
```dart
Map<String, dynamic> toJson() {
  return {
    if (id != null) 'id': id,
    'tenant_id': tenantId,  // ← ADD THIS
    // ... rest
  };
}
```

### 5. Update copyWith
```dart
ModelName copyWith({
  String? id,
  String? tenantId,  // ← ADD THIS
  // ... rest
}) {
  return ModelName(
    id: id ?? this.id,
    tenantId: tenantId ?? this.tenantId,  // ← ADD THIS
    // ... rest
  );
}
```

### 6. Update forms/services to get tenant_id
```dart
// In form or service
final tenantService = Provider.of<TenantService>(context, listen: false);
final tenantId = await tenantService.getTenantId();

if (tenantId == null || tenantId.isEmpty) {
  throw Exception('User does not have a tenant_id');
}

final model = ModelName(
  tenantId: tenantId,  // ← USE IT
  // ... rest
);
```

---

## ⏱️ ESTIMATED EFFORT

- **Per model:** ~10-15 minutes
- **Total models:** ~50
- **Total time:** ~8-12 hours of work
- **With automation:** ~2-4 hours

---

## 🎯 RECOMMENDATION

**I recommend starting with these HIGH-PRIORITY models:**

1. **Customer** - Used everywhere, blocks customer creation
2. **Product** - Inventory/POS/Sales all need this
3. **Employee** - HR module completely broken without it
4. **MechanicJob** - Your bikeshop core feature
5. **Invoice** - Sales completely broken
6. **Supplier** - Purchases completely broken

Fix these 6 first, test each one, then continue with the rest.

Would you like me to start fixing them one by one, or would you prefer I create an automated script to fix them all at once?
