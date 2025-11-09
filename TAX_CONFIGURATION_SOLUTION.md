# 🧾 Flexible Tax Configuration System - Implementation Plan

**Date**: November 8, 2025  
**Business Context**: Chilean bikeshop (Vinabike, Viña del Mar)  
**Tax Rate**: 19% IVA (Impuesto al Valor Agregado)  
**Status**: ✅ Phase 1 Database Schema COMPLETE

---

## 🎯 Final Design Philosophy

**Three-Layer Smart System:**
1. **Global Defaults** → Sensible starting points (card=tax, cash=no tax)
2. **Entity Defaults** → Per supplier/payment method preferences (configurable in settings)
3. **Transaction Control** → User has final say on every invoice (one clean dropdown)

**UI Principles:**
- ✅ Minimalistic & professional (no clutter in forms)
- ✅ Hints ONLY in settings module (where users configure)
- ✅ Forms are clean (just dropdowns, no explanatory text)
- ✅ Smart defaults reduce clicks by 90%
- ✅ Full flexibility for 10% edge cases

---

## 📊 Business Tax Rules

### **Core Principle: Tax INCLUDED in Price, Not Added**

When a product costs $1,000 CLP to the customer:

| Payment Method | Tax Applied? | Calculation | Net Income | Tax | Profit (if cost=$500) |
|---------------|-------------|-------------|-----------|-----|---------------------|
| 💵 **Cash** | ❌ NO | `$1,000` | $1,000 | $0 | **$500** |
| 💸 **Wire Transfer** | ❌ NO | `$1,000` | $1,000 | $0 | **$500** |
| 💳 **Card** | ✅ YES | `$1,000 ÷ 1.19` | $840 | $160 | **$340** |
| 📝 **Check** | ❓ Optional | Configurable | - | - | - |

### **Sales Tax Rules**

1. **Card Payments** → Tax INCLUDED (registered with SII)
   - Price shown to customer is FINAL
   - Split: `Net = Total ÷ 1.19`, `Tax = Total - Net`
   - Debit: Banco (1110) for full amount
   - Credit: Ventas (4101) for net + IVA Débito (2110) for tax

2. **Cash/Wire Transfer** → NO tax (not registered with SII)
   - Full amount is revenue
   - Debit: Caja/Banco (1101/1110) for full amount
   - Credit: Ventas (4101) for full amount

### **Purchase Tax Rules**

1. **Local Suppliers (with invoice)** → Tax INCLUDED (recoverable IVA Crédito)
   - Split: `Net = Total ÷ 1.19`, `Tax = Total - Net`
   - Debit: Expense + IVA Crédito (2120) for tax
   - Credit: Cuentas por Pagar (2101)

2. **AliExpress/International** → NO tax
   - Full amount is expense
   - No tax recovery

---

## 🏗️ Database Schema Changes

### **1. Add `tax_behavior` Column to `payment_methods` Table**

```sql
-- Add tax_behavior column to payment_methods
alter table payment_methods 
add column if not exists tax_behavior text not null default 'no_tax' 
check (tax_behavior in ('tax_included', 'no_tax'));

-- Add description column for clarity
alter table payment_methods 
add column if not exists description text;

comment on column payment_methods.tax_behavior is 
  'tax_included: Tax is embedded in price (divide by 1.19), no_tax: No tax applied';
```

### **2. Update Default Payment Methods**

```sql
-- Update seed_payment_methods_for_tenant() function
create or replace function public.seed_payment_methods_for_tenant(p_tenant_id uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cash_account_id uuid;
  v_bank_account_id uuid;
  v_count int;
begin
  -- ... existing account creation code ...

  -- Insert payment methods with tax behavior
  if not exists (select 1 from payment_methods where tenant_id = p_tenant_id and code = 'cash') then
    insert into payment_methods (
      tenant_id, code, name, account_id, 
      requires_reference, icon, sort_order, is_active,
      tax_behavior, description
    )
    values (
      p_tenant_id, 'cash', 'Efectivo', v_cash_account_id, 
      false, 'cash', 1, true,
      'no_tax', 'Pago en efectivo sin registro tributario'
    );
    v_count := v_count + 1;
  end if;

  if not exists (select 1 from payment_methods where tenant_id = p_tenant_id and code = 'transfer') then
    insert into payment_methods (
      tenant_id, code, name, account_id, 
      requires_reference, icon, sort_order, is_active,
      tax_behavior, description
    )
    values (
      p_tenant_id, 'transfer', 'Transferencia', v_bank_account_id, 
      true, 'bank', 2, true,
      'no_tax', 'Transferencia bancaria sin registro tributario'
    );
    v_count := v_count + 1;
  end if;

  if not exists (select 1 from payment_methods where tenant_id = p_tenant_id and code = 'check') then
    insert into payment_methods (
      tenant_id, code, name, account_id, 
      requires_reference, icon, sort_order, is_active,
      tax_behavior, description
    )
    values (
      p_tenant_id, 'check', 'Cheque', v_bank_account_id, 
      true, 'receipt', 3, true,
      'no_tax', 'Pago con cheque (configurable)'
    );
    v_count := v_count + 1;
  end if;

  if not exists (select 1 from payment_methods where tenant_id = p_tenant_id and code = 'card') then
    insert into payment_methods (
      tenant_id, code, name, account_id, 
      requires_reference, icon, sort_order, is_active,
      tax_behavior, description
    )
    values (
      p_tenant_id, 'card', 'Tarjeta de Crédito/Débito', v_bank_account_id, 
      false, 'credit_card', 4, true,
      'tax_included', 'Pago con tarjeta registrado en SII (IVA 19%)'
    );
    v_count := v_count + 1;
  end if;

  return format('✓ Created %s payment methods for tenant %s', v_count, p_tenant_id);
end;
$$;
```

### **3. Add `applies_tax` Column to `suppliers` Table**

```sql
-- Track which suppliers charge IVA
alter table suppliers 
add column if not exists applies_tax boolean not null default false;

comment on column suppliers.applies_tax is 
  'true: Supplier charges IVA (local Chilean suppliers), false: No tax (e.g., AliExpress)';
```

### **4. Update Invoice Tables to Store Tax Split**

Sales invoices already have `iva_amount` column. Let's add calculated fields:

```sql
-- Add net_amount column to sales_invoices (amount excluding IVA)
alter table sales_invoices 
add column if not exists net_amount decimal(15,2) default 0;

-- Add net_amount column to purchase_invoices
alter table purchase_invoices 
add column if not exists net_amount decimal(15,2) default 0;

comment on column sales_invoices.net_amount is 
  'Net amount excluding IVA (total ÷ 1.19 when tax applies)';
comment on column purchase_invoices.net_amount is 
  'Net amount excluding IVA (total ÷ 1.19 when tax applies)';
```

---

## 🔧 Flutter Model Updates

### **1. Update `PaymentMethod` Model**

```dart
// lib/shared/models/payment_method.dart

class PaymentMethod {
  final String id;
  final String tenantId;
  final String code;
  final String name;
  final String accountId;
  final bool requiresReference;
  final String? icon;
  final int sortOrder;
  final bool isActive;
  final TaxBehavior taxBehavior; // NEW
  final String? description; // NEW
  final DateTime createdAt;
  final DateTime updatedAt;

  PaymentMethod({
    required this.id,
    required this.tenantId,
    required this.code,
    required this.name,
    required this.accountId,
    this.requiresReference = false,
    this.icon,
    this.sortOrder = 0,
    this.isActive = true,
    this.taxBehavior = TaxBehavior.noTax, // DEFAULT
    this.description,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: json['id']?.toString() ?? '',
      tenantId: json['tenant_id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      accountId: json['account_id']?.toString() ?? '',
      requiresReference: json['requires_reference'] == true,
      icon: json['icon']?.toString(),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] ?? true,
      taxBehavior: _parseTaxBehavior(json['tax_behavior']),
      description: json['description']?.toString(),
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'code': code,
      'name': name,
      'account_id': accountId,
      'requires_reference': requiresReference,
      'icon': icon,
      'sort_order': sortOrder,
      'is_active': isActive,
      'tax_behavior': taxBehavior.value,
      'description': description,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  static TaxBehavior _parseTaxBehavior(dynamic value) {
    if (value == 'tax_included') return TaxBehavior.taxIncluded;
    return TaxBehavior.noTax;
  }

  // Helper: Calculate tax split for a given amount
  TaxCalculation calculateTax(double totalAmount, double taxRate) {
    if (taxBehavior == TaxBehavior.noTax) {
      return TaxCalculation(
        total: totalAmount,
        netAmount: totalAmount,
        taxAmount: 0,
        taxRate: 0,
      );
    } else {
      // Tax included: split the amount
      final netAmount = totalAmount / (1 + taxRate);
      final taxAmount = totalAmount - netAmount;
      return TaxCalculation(
        total: totalAmount,
        netAmount: netAmount,
        taxAmount: taxAmount,
        taxRate: taxRate,
      );
    }
  }
}

enum TaxBehavior {
  noTax('no_tax'),
  taxIncluded('tax_included');

  final String value;
  const TaxBehavior(this.value);
}

class TaxCalculation {
  final double total;
  final double netAmount;
  final double taxAmount;
  final double taxRate;

  TaxCalculation({
    required this.total,
    required this.netAmount,
    required this.taxAmount,
    required this.taxRate,
  });
}
```

### **2. Update `SalesInvoice` Model**

```dart
// lib/modules/sales/models/sales_models.dart

class SalesInvoice {
  final String? id;
  final String tenantId;
  final String invoiceNumber;
  final DateTime date;
  final String? customerId;
  final String customerName;
  final double subtotal;
  final double ivaAmount;
  final double total;
  final double netAmount; // NEW - net excluding tax
  final String status;
  final String? notes;
  final String? paymentMethodId; // NEW - to determine tax behavior
  // ... other fields

  // Calculate net amount based on payment method tax behavior
  static double calculateNetAmount(
    double total, 
    PaymentMethod? paymentMethod, 
    double taxRate
  ) {
    if (paymentMethod == null) return total;
    
    if (paymentMethod.taxBehavior == TaxBehavior.taxIncluded) {
      return total / (1 + taxRate);
    }
    return total; // No tax - full amount is net
  }
}
```

### **3. Update `Supplier` Model**

```dart
// lib/modules/purchases/models/supplier.dart

class Supplier {
  final String id;
  final String tenantId;
  final String name;
  final String? rut;
  final String? email;
  final String? phone;
  final String? address;
  final bool appliesTax; // NEW
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Supplier({
    required this.id,
    required this.tenantId,
    required this.name,
    this.rut,
    this.email,
    this.phone,
    this.address,
    this.appliesTax = false, // DEFAULT: No tax (like AliExpress)
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory Supplier.fromJson(Map<String, dynamic> json) {
    return Supplier(
      id: json['id']?.toString() ?? '',
      tenantId: json['tenant_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      rut: json['rut']?.toString(),
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      address: json['address']?.toString(),
      appliesTax: json['applies_tax'] == true,
      isActive: json['is_active'] ?? true,
      createdAt: _parseDate(json['created_at']),
      updatedAt: _parseDate(json['updated_at']),
    );
  }
}
```

---

## 🎨 UI Changes

### **1. Sales Invoice Form - Payment Method Aware Tax Calculation**

```dart
// lib/modules/sales/pages/invoice_form_page.dart

class _InvoiceFormPageState extends State<InvoiceFormPage> {
  PaymentMethod? _selectedPaymentMethod;
  static const double _ivaRate = 0.19;

  // Tax calculation based on selected payment method
  double get _subtotal => _lineItems.fold(0.0, (sum, item) => sum + item.total);
  
  double get _netAmount {
    if (_selectedPaymentMethod == null) {
      return _subtotal; // Default: no tax
    }
    
    if (_selectedPaymentMethod!.taxBehavior == TaxBehavior.taxIncluded) {
      // Tax included: calculate net
      return _subtotal / (1 + _ivaRate);
    }
    
    return _subtotal; // No tax: full amount is net
  }
  
  double get _ivaAmount {
    if (_selectedPaymentMethod == null) return 0;
    
    if (_selectedPaymentMethod!.taxBehavior == TaxBehavior.taxIncluded) {
      return _subtotal - _netAmount;
    }
    
    return 0;
  }
  
  double get _total => _subtotal; // Total is always the subtotal (tax included)

  Widget _buildTotalsCard() {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.titleMedium;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Payment method selector
            _buildPaymentMethodSelector(),
            const Divider(height: 24),
            
            // Show tax breakdown if applicable
            if (_selectedPaymentMethod?.taxBehavior == TaxBehavior.taxIncluded) ...[
              _buildSummaryRow('Subtotal', ChileanUtils.formatCurrency(_subtotal), textStyle, theme),
              const SizedBox(height: 8),
              _buildSummaryRow(
                'Neto (sin IVA)', 
                ChileanUtils.formatCurrency(_netAmount), 
                textStyle, 
                theme,
                tooltip: 'Monto neto: $_subtotal ÷ 1.19',
              ),
              const SizedBox(height: 8),
              _buildSummaryRow(
                'IVA (19%)', 
                ChileanUtils.formatCurrency(_ivaAmount), 
                textStyle, 
                theme,
                color: Colors.orange,
                tooltip: 'Impuesto incluido en el precio',
              ),
            ] else ...[
              _buildSummaryRow('Subtotal', ChileanUtils.formatCurrency(_subtotal), textStyle, theme),
              const SizedBox(height: 8),
              _buildSummaryRow(
                'IVA', 
                'No aplica', 
                textStyle, 
                theme,
                color: Colors.grey,
                tooltip: 'Método de pago sin registro tributario',
              ),
            ],
            
            const Divider(height: 24),
            _buildSummaryRow(
              'Total', 
              ChileanUtils.formatCurrency(_total), 
              theme.textTheme.headlineSmall,
              theme,
              isBold: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodSelector() {
    return DropdownButtonFormField<PaymentMethod>(
      decoration: const InputDecoration(
        labelText: 'Método de Pago',
        helperText: 'Determina si se aplica IVA',
        prefixIcon: Icon(Icons.payment),
      ),
      value: _selectedPaymentMethod,
      items: _paymentMethods.map((method) {
        return DropdownMenuItem(
          value: method,
          child: Row(
            children: [
              Icon(_getPaymentIcon(method.icon)),
              const SizedBox(width: 8),
              Expanded(child: Text(method.name)),
              if (method.taxBehavior == TaxBehavior.taxIncluded)
                Chip(
                  label: const Text('IVA', style: TextStyle(fontSize: 10)),
                  backgroundColor: Colors.orange.shade100,
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
        );
      }).toList(),
      onChanged: (value) {
        setState(() {
          _selectedPaymentMethod = value;
        });
      },
    );
  }
}
```

### **2. POS Module - Real-Time Tax Calculation**

```dart
// lib/modules/pos/pages/pos_dashboard_page.dart

class _POSDashboardPageState extends State<POSDashboardPage> {
  PaymentMethod? _selectedPaymentMethod;
  
  void _showPaymentDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Pago'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Payment method selector
            DropdownButtonFormField<PaymentMethod>(
              decoration: const InputDecoration(
                labelText: 'Método de Pago',
                prefixIcon: Icon(Icons.payment),
              ),
              items: _paymentMethods.map((method) {
                return DropdownMenuItem(
                  value: method,
                  child: Row(
                    children: [
                      Icon(_getPaymentIcon(method.icon)),
                      const SizedBox(width: 8),
                      Text(method.name),
                      if (method.taxBehavior == TaxBehavior.taxIncluded)
                        const Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Icon(Icons.receipt_long, size: 16, color: Colors.orange),
                        ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedPaymentMethod = value;
                });
              },
            ),
            const SizedBox(height: 16),
            
            // Tax breakdown
            if (_selectedPaymentMethod != null) ...[
              const Divider(),
              _buildTaxBreakdown(_selectedPaymentMethod!),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: _selectedPaymentMethod != null ? _processPayment : null,
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  Widget _buildTaxBreakdown(PaymentMethod paymentMethod) {
    final total = _cartTotal;
    final taxCalc = paymentMethod.calculateTax(total, 0.19);
    
    return Column(
      children: [
        _buildRow('Total', ChileanUtils.formatCurrency(taxCalc.total)),
        if (paymentMethod.taxBehavior == TaxBehavior.taxIncluded) ...[
          _buildRow('Neto', ChileanUtils.formatCurrency(taxCalc.netAmount)),
          _buildRow('IVA 19%', ChileanUtils.formatCurrency(taxCalc.taxAmount)),
        ] else
          const Text(
            'Sin IVA',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
      ],
    );
  }
}
```

### **3. Purchase Invoice Form - Supplier Tax Behavior**

```dart
// lib/modules/purchases/pages/purchase_invoice_form_page.dart

class _PurchaseInvoiceFormPageState extends State<PurchaseInvoiceFormPage> {
  Supplier? _selectedSupplier;
  
  double get _subtotal => _lineItems.fold(0.0, (sum, item) => sum + item.total);
  
  double get _netAmount {
    if (_selectedSupplier == null || !_selectedSupplier!.appliesTax) {
      return _subtotal; // No tax: full amount is cost
    }
    
    // Tax included: calculate net
    return _subtotal / 1.19;
  }
  
  double get _ivaAmount {
    if (_selectedSupplier == null || !_selectedSupplier!.appliesTax) {
      return 0;
    }
    
    return _subtotal - _netAmount;
  }
  
  Widget _buildSupplierSelector() {
    return Autocomplete<Supplier>(
      displayStringForOption: (supplier) => supplier.name,
      optionsBuilder: (textEditingValue) {
        return _suppliers.where((supplier) =>
          supplier.name.toLowerCase().contains(textEditingValue.text.toLowerCase())
        );
      },
      onSelected: (supplier) {
        setState(() {
          _selectedSupplier = supplier;
        });
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: 'Proveedor',
            prefixIcon: const Icon(Icons.business),
            suffixIcon: _selectedSupplier?.appliesTax == true
                ? Tooltip(
                    message: 'Este proveedor emite facturas con IVA',
                    child: Icon(Icons.receipt_long, color: Colors.orange),
                  )
                : Tooltip(
                    message: 'Sin IVA (ej: AliExpress)',
                    child: Icon(Icons.public, color: Colors.grey),
                  ),
          ),
        );
      },
    );
  }
}
```

### **4. Settings - Payment Method Configuration**

```dart
// lib/modules/settings/pages/payment_methods_config_page.dart

class PaymentMethodsConfigPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurar Métodos de Pago'),
      ),
      body: ListView.builder(
        itemCount: paymentMethods.length,
        itemBuilder: (context, index) {
          final method = paymentMethods[index];
          return Card(
            child: ListTile(
              leading: Icon(_getPaymentIcon(method.icon)),
              title: Text(method.name),
              subtitle: Text(method.description ?? ''),
              trailing: DropdownButton<TaxBehavior>(
                value: method.taxBehavior,
                items: [
                  DropdownMenuItem(
                    value: TaxBehavior.noTax,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.money_off, size: 16),
                        SizedBox(width: 4),
                        Text('Sin IVA'),
                      ],
                    ),
                  ),
                  DropdownMenuItem(
                    value: TaxBehavior.taxIncluded,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.receipt_long, size: 16, color: Colors.orange),
                        SizedBox(width: 4),
                        Text('IVA Incluido'),
                      ],
                    ),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _updatePaymentMethodTax(method.id, value);
                  }
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
```

---

## 📊 Accounting Module Integration

### **Updated Journal Entry Creation**

```sql
-- Update create_sales_invoice_journal_entry function
create or replace function create_sales_invoice_journal_entry(p_invoice sales_invoices)
returns uuid
language plpgsql
security definer
as $$
declare
  v_entry_id uuid;
  v_tenant_id uuid;
  v_receivable_account_id uuid;
  v_sales_account_id uuid;
  v_iva_debito_account_id uuid;
  v_payment_method payment_methods;
  v_net_amount decimal(15,2);
  v_iva_amount decimal(15,2);
begin
  v_tenant_id := p_invoice.tenant_id;
  
  -- Get payment method to determine tax behavior
  select * into v_payment_method
  from payment_methods
  where id = p_invoice.payment_method_id
    and tenant_id = v_tenant_id;
  
  -- Get required accounts
  select id into v_receivable_account_id from accounts 
  where tenant_id = v_tenant_id and code = '1130' limit 1;
  
  select id into v_sales_account_id from accounts 
  where tenant_id = v_tenant_id and code = '4101' limit 1;
  
  select id into v_iva_debito_account_id from accounts 
  where tenant_id = v_tenant_id and code = '2110' limit 1;
  
  -- Calculate net and tax amounts based on payment method
  if v_payment_method.tax_behavior = 'tax_included' then
    v_net_amount := p_invoice.total / 1.19;
    v_iva_amount := p_invoice.total - v_net_amount;
  else
    v_net_amount := p_invoice.total;
    v_iva_amount := 0;
  end if;
  
  -- Create journal entry
  insert into journal_entries (
    tenant_id, entry_number, date, description, 
    total, status, source_type, source_id
  )
  values (
    v_tenant_id, 
    'INV-' || p_invoice.invoice_number,
    p_invoice.date,
    'Venta: ' || p_invoice.customer_name,
    p_invoice.total,
    'posted',
    'sales_invoice',
    p_invoice.id
  )
  returning id into v_entry_id;
  
  -- DEBIT: Accounts Receivable (full amount)
  insert into journal_entry_lines (
    tenant_id, entry_id, account_id, debit, credit, description
  )
  values (
    v_tenant_id, v_entry_id, v_receivable_account_id, 
    p_invoice.total, 0, 
    'Cuenta por cobrar'
  );
  
  -- CREDIT: Sales Revenue (net amount)
  insert into journal_entry_lines (
    tenant_id, entry_id, account_id, debit, credit, description
  )
  values (
    v_tenant_id, v_entry_id, v_sales_account_id, 
    0, v_net_amount, 
    'Venta de productos'
  );
  
  -- CREDIT: IVA Débito (tax amount, only if tax applies)
  if v_iva_amount > 0 then
    insert into journal_entry_lines (
      tenant_id, entry_id, account_id, debit, credit, description
    )
    values (
      v_tenant_id, v_entry_id, v_iva_debito_account_id, 
      0, v_iva_amount, 
      'IVA Débito Fiscal 19%'
    );
  end if;
  
  return v_entry_id;
end;
$$;
```

---

## 🎯 Implementation Roadmap

### **Phase 1: Database Schema (2 hours)**
1. ✅ Add `tax_behavior` column to `payment_methods`
2. ✅ Add `description` column to `payment_methods`
3. ✅ Add `applies_tax` column to `suppliers`
4. ✅ Add `net_amount` column to `sales_invoices` and `purchase_invoices`
5. ✅ Update `seed_payment_methods_for_tenant()` function
6. ✅ Update `create_sales_invoice_journal_entry()` function
7. ✅ Update `create_purchase_invoice_journal_entry()` function
8. ✅ Deploy to Supabase

### **Phase 2: Flutter Models (1 hour)**
1. ✅ Add `TaxBehavior` enum
2. ✅ Add `TaxCalculation` class
3. ✅ Update `PaymentMethod` model
4. ✅ Update `Supplier` model
5. ✅ Update `SalesInvoice` model
6. ✅ Update `PurchaseInvoice` model

### **Phase 3: Sales Invoice Form (2 hours)**
1. ✅ Add payment method selector
2. ✅ Update tax calculation logic
3. ✅ Update totals display with conditional tax breakdown
4. ✅ Add tooltips explaining tax behavior
5. ✅ Test with card vs cash payments

### **Phase 4: POS Module (1.5 hours)**
1. ✅ Add payment method selector to checkout
2. ✅ Show real-time tax breakdown
3. ✅ Update receipt generation with tax split
4. ✅ Test card vs cash transactions

### **Phase 5: Purchase Invoice Form (1.5 hours)**
1. ✅ Add supplier tax indicator
2. ✅ Update tax calculation based on supplier
3. ✅ Show IVA Crédito when applicable
4. ✅ Test with AliExpress vs local supplier

### **Phase 6: Settings UI (1 hour)**
1. ✅ Create payment method configuration page
2. ✅ Allow toggling tax behavior per payment method
3. ✅ Create supplier configuration page
4. ✅ Allow toggling tax for suppliers

### **Phase 7: Reports & Analytics (2 hours)**
1. ✅ Update profit reports to show net vs gross
2. ✅ Create tax summary report (IVA Débito vs Crédito)
3. ✅ Update accounting reports with tax breakdown
4. ✅ Add tax liability calculator

### **Phase 8: Testing (2 hours)**
1. ✅ Test all payment methods in sales
2. ✅ Test supplier tax behavior in purchases
3. ✅ Verify journal entries are correct
4. ✅ Verify profit calculations
5. ✅ Test edge cases (zero tax, mixed transactions)

**Total Estimated Time: 13 hours**

---

## 🧪 Test Scenarios

### **Test 1: Card Payment Sale**
- Product: $10,000 CLP (cost: $5,000)
- Payment: Card
- Expected:
  - Net: $8,403 CLP
  - IVA: $1,597 CLP
  - Profit: $3,403 CLP ($8,403 - $5,000)

### **Test 2: Cash Payment Sale**
- Product: $10,000 CLP (cost: $5,000)
- Payment: Cash
- Expected:
  - Net: $10,000 CLP
  - IVA: $0
  - Profit: $5,000 CLP ($10,000 - $5,000)

### **Test 3: AliExpress Purchase**
- Product: $5,000 CLP
- Supplier: AliExpress (applies_tax = false)
- Expected:
  - Cost: $5,000 CLP
  - IVA Crédito: $0

### **Test 4: Local Supplier Purchase**
- Product: $5,000 CLP
- Supplier: Local (applies_tax = true)
- Expected:
  - Net Cost: $4,202 CLP
  - IVA Crédito: $798 CLP (recoverable)

---

## 💡 Key Benefits

1. ✅ **Flexible**: Each payment method can have different tax behavior
2. ✅ **Accurate Profit**: System calculates net profit correctly
3. ✅ **Tax Compliance**: Proper IVA tracking for SII reporting
4. ✅ **User-Friendly**: Visual indicators show when tax applies
5. ✅ **Supplier-Aware**: Handles international vs local purchases
6. ✅ **Configurable**: Business can change tax rules per payment method
7. ✅ **Audit-Ready**: Journal entries show exact tax split

---

## 🚨 Important Notes

1. **Tax is ALWAYS included in price**, never added on top
2. **Default behavior**: No tax (safe for cash/wire transfers)
3. **Card payments**: Only method with tax by default
4. **Suppliers**: AliExpress and international suppliers default to no tax
5. **Reports must show**: Gross revenue vs net revenue vs tax
6. **User education**: Tooltips and help text explain tax behavior

---

**End of Document**
