# 🚀 Flutter Integration Plan - Vinabike ERP

**Created:** October 13, 2025  
**Purpose:** Wire `core_schema.sql` structure with Flutter application code  
**Status:** Planning Phase - Awaiting User Approval

---

## 📋 Executive Summary

### Current State
- ✅ **SQL Schema**: Fully implemented with dynamic payment methods system
- ✅ **Documentation**: Complete technical guides and flow documentation
- ❌ **Flutter App**: Not synchronized with new schema structure
- ❌ **Payment Methods**: Hardcoded in Flutter (if exists), needs dynamic loading
- ❌ **Purchase Module**: Incomplete or missing prepayment model selection
- ❌ **GUI Consistency**: Sales and Purchase modules may have different navigation patterns

### Target State
- ✅ Flutter models match `core_schema.sql` exactly (column names, data types)
- ✅ Payment methods loaded dynamically from `payment_methods` table
- ✅ Purchase invoices support prepayment vs standard model selection
- ✅ Status-based button visibility (forward/backward navigation)
- ✅ Consistent GUI between Sales and Purchase modules
- ✅ Bidirectional flows trigger automatic journal entries and inventory adjustments
- ✅ Reference field appears conditionally based on `payment_methods.requires_reference`

---

## 🎯 What I Understood From Your Requirements

### 1. **Core Schema is Source of Truth**
> "if you really are sure about #file:core_schema.sql you'll probably are going to modify flutter files from now on, not the other way arround!!"

**CRITICAL RULE:**
- ✅ Modify Flutter to match `core_schema.sql`
- ❌ DO NOT modify `core_schema.sql` to accommodate Flutter
- ⚠️ Only change SQL if there's a mistake IN the SQL itself

### 2. **Payment Methods - Dynamic System**
**Requirements:**
- Payment dropdown populated from `payment_methods` table (NOT hardcoded)
- Query: `SELECT id, code, name, icon FROM payment_methods WHERE is_active = true ORDER BY sort_order`
- Reference field appears only when `requires_reference = true`
- Journal entries use the linked account (e.g., Efectivo→1101 Caja, Transferencia→1110 Bancos)

**Current Schema:**
```sql
payment_methods:
  - id (uuid primary key)
  - code (text unique) - 'cash', 'transfer', 'card', 'check'
  - name (text) - 'Efectivo', 'Transferencia', 'Tarjeta de Crédito', 'Cheque'
  - account_id (uuid) - references accounts(id)
  - requires_reference (boolean)
  - icon (text) - optional icon name
  - sort_order (integer)
  - is_active (boolean)
```

### 3. **Prepayment Model Selection**
**Requirements:**
- When creating a purchase invoice, user must choose: "¿Pago antes o después?"
  - **Standard Model** (Pago después): Draft→Sent→Confirmed→Received→Paid
  - **Prepayment Model** (Pago antes): Draft→Sent→Confirmed→Paid→Received
- Store selection in `purchase_invoices.prepayment_model` (boolean)
- Different status flows trigger different accounting logic

**Key Difference:**
- **Standard**: Inventory consumed at "Received", payment after
- **Prepayment**: Payment at "Paid" (before receiving), inventory consumed at "Received"

### 4. **Status-Based Button Visibility**
**Requirements:**
- Buttons appear/disappear based on current invoice status
- Support bidirectional navigation (go forward AND backward)
- Examples:
  - At "Draft": Show "Send" button only
  - At "Sent": Show "Confirm" and "Back to Draft" buttons
  - At "Confirmed": Show "Receive" (purchase) or "Mark Paid" (sales) and "Back to Sent" buttons
  - At "Paid": Show "Back to Confirmed" button (triggers reversal)

**Behavior:**
- Forward buttons trigger status change (backend creates journal entries/inventory movements)
- Backward buttons trigger reversal (backend deletes entries, restores inventory)

### 5. **GUI Consistency Between Modules**
**Requirements:**
- Sales and Purchase modules must have similar layout
- Same button styles and positioning
- Same list/detail/form page structure
- Same navigation patterns (drawer, breadcrumbs, etc.)
- Reusable widgets for common elements (payment form, status badges)

### 6. **Automatic Backend Triggers**
**Requirements:**
- Flutter only changes invoice status (e.g., `status = 'Confirmed'`)
- Backend triggers automatically:
  - Create/delete journal entries via `handle_sales_invoice_change()` or `handle_purchase_invoice_change()`
  - Consume/restore inventory via `consume_inventory()` or `restore_inventory()`
  - Recalculate payment amounts via `recalculate_payments()`
- Flutter does NOT manually insert into `journal_entries` or `stock_movements`

### 7. **Column Name Accuracy**
**Requirements:**
- Use exact column names from `core_schema.sql`
- Examples:
  - `payment_method_id` (NOT `method` or `payment_method`)
  - `prepayment_model` (boolean, NOT `is_prepaid` or `payment_type`)
  - `paid_amount` (numeric, NOT `amount_paid`)
  - `balance` (numeric, NOT `remaining_balance`)

---

## 🛠️ Implementation Plan - 5 Phases

### **Phase 1: Audit Current Flutter Code** ⏱️ ~30 minutes

**Objective:** Identify what exists, what's broken, what's missing

**Tasks:**
1. ✅ Read all files in `lib/modules/sales/models/`
   - Check `SalesInvoice` class fields match schema
   - Check `SalesPayment` class fields (must have `payment_method_id uuid`)
   
2. ✅ Read all files in `lib/modules/sales/services/`
   - Identify Supabase queries (check column names)
   - Check if payment methods are hardcoded
   
3. ✅ Read all files in `lib/modules/sales/pages/`
   - Identify payment form implementation
   - Check status transition logic
   
4. ✅ Read all files in `lib/modules/purchases/` (if exists)
   - Assess completeness vs requirements
   
5. ✅ Check for existing `lib/shared/services/payment_method_service.dart`
   
6. ✅ Document findings in audit report:
   - ✅ What works correctly
   - ⚠️ What's broken (column name mismatches, hardcoded values)
   - ❌ What's missing (prepayment selection, status buttons, etc.)

**Deliverable:** Audit report with gap analysis

---

### **Phase 2: Fix Sales Invoice Flow** ⏱️ ~2-3 hours

**Objective:** Update existing sales module to match `core_schema.sql`

#### **2.1 Update Models** (~20 mins)
**File:** `lib/modules/sales/models/sales_invoice.dart`

**Changes:**
```dart
class SalesInvoice {
  final String id;  // uuid in DB
  final String? customerId;  // uuid, nullable
  final DateTime date;
  final DateTime? dueDate;  // nullable
  final String status;  // 'Draft', 'Sent', 'Confirmed', 'Paid', etc.
  final double subtotal;
  final double tax;  // IVA amount
  final double total;
  final double paidAmount;  // from DB: paid_amount
  final double balance;  // total - paid_amount
  final String? notes;
  
  // Ensure all fields match core_schema.sql columns exactly
}
```

**File:** `lib/modules/sales/models/sales_payment.dart`

**Changes:**
```dart
class SalesPayment {
  final String id;  // uuid
  final String invoiceId;  // uuid, references sales_invoices(id)
  final String? paymentMethodId;  // uuid, references payment_methods(id) - KEY CHANGE
  final double amount;
  final DateTime date;
  final String? reference;  // conditional field
  final String? notes;
  
  // Remove old 'method' field if exists
  // Add paymentMethodId
}
```

#### **2.2 Update Services** (~30 mins)
**File:** `lib/modules/sales/services/sales_service.dart`

**Changes:**
```dart
// Fix column names in queries
Future<void> updateInvoiceStatus(String id, String newStatus) async {
  await supabase
    .from('sales_invoices')
    .update({'status': newStatus})  // Trigger handles the rest
    .eq('id', id);
}

Future<void> createPayment(SalesPayment payment) async {
  await supabase.from('sales_payments').insert({
    'invoice_id': payment.invoiceId,
    'payment_method_id': payment.paymentMethodId,  // NOT 'method'
    'amount': payment.amount,
    'date': payment.date.toIso8601String(),
    'reference': payment.reference,
    'notes': payment.notes,
  });
  // Trigger automatically creates journal entry
}
```

#### **2.3 Create Payment Method Service** (~20 mins)
**File:** `lib/shared/services/payment_method_service.dart` (NEW)

**Implementation:**
```dart
class PaymentMethodService {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<PaymentMethod>? _cachedMethods;

  Future<List<PaymentMethod>> fetchActivePaymentMethods() async {
    if (_cachedMethods != null) return _cachedMethods!;
    
    final response = await _supabase
      .from('payment_methods')
      .select('id, code, name, requires_reference, icon, sort_order')
      .eq('is_active', true)
      .order('sort_order');
    
    _cachedMethods = (response as List)
      .map((json) => PaymentMethod.fromJson(json))
      .toList();
    
    return _cachedMethods!;
  }

  void clearCache() {
    _cachedMethods = null;
  }
}
```

**File:** `lib/shared/models/payment_method.dart` (NEW)

```dart
class PaymentMethod {
  final String id;
  final String code;
  final String name;
  final bool requiresReference;
  final String? icon;
  final int sortOrder;

  PaymentMethod({
    required this.id,
    required this.code,
    required this.name,
    required this.requiresReference,
    this.icon,
    required this.sortOrder,
  });

  factory PaymentMethod.fromJson(Map<String, dynamic> json) {
    return PaymentMethod(
      id: json['id'],
      code: json['code'],
      name: json['name'],
      requiresReference: json['requires_reference'] ?? false,
      icon: json['icon'],
      sortOrder: json['sort_order'] ?? 0,
    );
  }
}
```

#### **2.4 Update Payment Form** (~40 mins)
**File:** `lib/modules/sales/pages/sales_payment_form_page.dart`

**Changes:**
```dart
class SalesPaymentFormPage extends StatefulWidget {
  final String invoiceId;
  final double remainingBalance;
  
  @override
  _SalesPaymentFormPageState createState() => _SalesPaymentFormPageState();
}

class _SalesPaymentFormPageState extends State<SalesPaymentFormPage> {
  final _paymentMethodService = PaymentMethodService();
  List<PaymentMethod> _paymentMethods = [];
  PaymentMethod? _selectedMethod;
  
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  
  @override
  void initState() {
    super.initState();
    _loadPaymentMethods();
    _amountController.text = widget.remainingBalance.toStringAsFixed(2);
  }
  
  Future<void> _loadPaymentMethods() async {
    final methods = await _paymentMethodService.fetchActivePaymentMethods();
    setState(() {
      _paymentMethods = methods;
      _selectedMethod = methods.isNotEmpty ? methods.first : null;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Registrar Pago')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            // Payment Method Dropdown
            DropdownButtonFormField<PaymentMethod>(
              value: _selectedMethod,
              decoration: InputDecoration(labelText: 'Método de Pago'),
              items: _paymentMethods.map((method) {
                return DropdownMenuItem(
                  value: method,
                  child: Row(
                    children: [
                      if (method.icon != null) ...[
                        Icon(Icons.payment), // Use method.icon
                        SizedBox(width: 8),
                      ],
                      Text(method.name),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedMethod = value;
                  if (value?.requiresReference == false) {
                    _referenceController.clear();
                  }
                });
              },
            ),
            
            SizedBox(height: 16),
            
            // Amount Field
            TextFormField(
              controller: _amountController,
              decoration: InputDecoration(labelText: 'Monto'),
              keyboardType: TextInputType.number,
            ),
            
            SizedBox(height: 16),
            
            // Date Picker
            InkWell(
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (date != null) {
                  setState(() => _selectedDate = date);
                }
              },
              child: InputDecorator(
                decoration: InputDecoration(labelText: 'Fecha'),
                child: Text(DateFormat('dd/MM/yyyy').format(_selectedDate)),
              ),
            ),
            
            SizedBox(height: 16),
            
            // Reference Field (conditional)
            if (_selectedMethod?.requiresReference == true)
              TextFormField(
                controller: _referenceController,
                decoration: InputDecoration(
                  labelText: 'Referencia/Nº de Operación',
                  hintText: 'Ej: Nº de transferencia, cheque, etc.',
                ),
              ),
            
            SizedBox(height: 16),
            
            // Notes Field
            TextFormField(
              controller: _notesController,
              decoration: InputDecoration(labelText: 'Notas (opcional)'),
              maxLines: 3,
            ),
            
            Spacer(),
            
            // Save Button
            ElevatedButton(
              onPressed: _savePayment,
              child: Text('Registrar Pago'),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _savePayment() async {
    if (_selectedMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Seleccione un método de pago')),
      );
      return;
    }
    
    final payment = SalesPayment(
      id: '', // Generated by DB
      invoiceId: widget.invoiceId,
      paymentMethodId: _selectedMethod!.id,
      amount: double.parse(_amountController.text),
      date: _selectedDate,
      reference: _referenceController.text.isEmpty ? null : _referenceController.text,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
    );
    
    await SalesService().createPayment(payment);
    
    Navigator.of(context).pop(true); // Return success
  }
}
```

#### **2.5 Update Invoice Detail Page** (~40 mins)
**File:** `lib/modules/sales/pages/sales_invoice_detail_page.dart`

**Changes:**
```dart
class SalesInvoiceDetailPage extends StatefulWidget {
  final String invoiceId;
  
  @override
  _SalesInvoiceDetailPageState createState() => _SalesInvoiceDetailPageState();
}

class _SalesInvoiceDetailPageState extends State<SalesInvoiceDetailPage> {
  SalesInvoice? _invoice;
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _loadInvoice();
  }
  
  Future<void> _loadInvoice() async {
    final invoice = await SalesService().getInvoiceById(widget.invoiceId);
    setState(() {
      _invoice = invoice;
      _isLoading = false;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    if (_isLoading) return Center(child: CircularProgressIndicator());
    if (_invoice == null) return Center(child: Text('Factura no encontrada'));
    
    return Scaffold(
      appBar: AppBar(title: Text('Factura ${_invoice!.id}')),
      body: Column(
        children: [
          // Invoice details display
          Expanded(child: _buildInvoiceDetails()),
          
          // Status-based action buttons
          _buildActionButtons(),
        ],
      ),
    );
  }
  
  Widget _buildActionButtons() {
    final status = _invoice!.status;
    
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Backward button
          if (_canGoBackward(status))
            ElevatedButton.icon(
              onPressed: () => _goBackward(status),
              icon: Icon(Icons.arrow_back),
              label: Text(_getBackwardLabel(status)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            )
          else
            SizedBox(width: 150), // Spacer
          
          // Forward button
          if (_canGoForward(status))
            ElevatedButton.icon(
              onPressed: () => _goForward(status),
              icon: Icon(Icons.arrow_forward),
              label: Text(_getForwardLabel(status)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            )
          else
            SizedBox(width: 150), // Spacer
        ],
      ),
    );
  }
  
  bool _canGoBackward(String status) {
    // Can go backward from any status except Draft and Cancelled
    return !['Draft', 'Cancelled'].contains(status);
  }
  
  bool _canGoForward(String status) {
    // Can go forward if not at final state
    return !['Paid', 'Cancelled'].contains(status);
  }
  
  String _getBackwardLabel(String status) {
    switch (status) {
      case 'Sent': return 'Volver a Borrador';
      case 'Confirmed': return 'Volver a Enviada';
      case 'Paid': return 'Desmarcar Pagada';
      default: return 'Atrás';
    }
  }
  
  String _getForwardLabel(String status) {
    switch (status) {
      case 'Draft': return 'Enviar';
      case 'Sent': return 'Confirmar';
      case 'Confirmed': return 'Registrar Pago';
      default: return 'Siguiente';
    }
  }
  
  Future<void> _goBackward(String currentStatus) async {
    final newStatus = _getPreviousStatus(currentStatus);
    await SalesService().updateInvoiceStatus(_invoice!.id, newStatus);
    await _loadInvoice(); // Reload
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Estado cambiado a $newStatus')),
    );
  }
  
  Future<void> _goForward(String currentStatus) async {
    if (currentStatus == 'Confirmed') {
      // Navigate to payment form instead of direct status change
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SalesPaymentFormPage(
            invoiceId: _invoice!.id,
            remainingBalance: _invoice!.balance,
          ),
        ),
      );
      if (result == true) await _loadInvoice();
    } else {
      final newStatus = _getNextStatus(currentStatus);
      await SalesService().updateInvoiceStatus(_invoice!.id, newStatus);
      await _loadInvoice();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Estado cambiado a $newStatus')),
      );
    }
  }
  
  String _getPreviousStatus(String current) {
    switch (current) {
      case 'Sent': return 'Draft';
      case 'Confirmed': return 'Sent';
      case 'Paid': return 'Confirmed';
      default: return current;
    }
  }
  
  String _getNextStatus(String current) {
    switch (current) {
      case 'Draft': return 'Sent';
      case 'Sent': return 'Confirmed';
      case 'Confirmed': return 'Paid'; // Usually via payment
      default: return current;
    }
  }
}
```

---

### **Phase 3: Implement Purchase Invoice Flow** ⏱️ ~3-4 hours

**Objective:** Create complete purchase module with prepayment model support

#### **3.1 Create/Update Models** (~30 mins)
**File:** `lib/modules/purchases/models/purchase_invoice.dart`

**Implementation:**
```dart
class PurchaseInvoice {
  final String id;  // uuid
  final String? supplierId;  // uuid, references suppliers(id)
  final DateTime date;
  final DateTime? dueDate;
  final String status;  // 'Draft', 'Sent', 'Confirmed', 'Received', 'Paid'
  final bool prepaymentModel;  // KEY FIELD - false = standard, true = prepayment
  final double subtotal;
  final double tax;  // IVA
  final double total;
  final double paidAmount;
  final double balance;
  final String? notes;
  
  PurchaseInvoice({
    required this.id,
    this.supplierId,
    required this.date,
    this.dueDate,
    required this.status,
    required this.prepaymentModel,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.paidAmount,
    required this.balance,
    this.notes,
  });
  
  factory PurchaseInvoice.fromJson(Map<String, dynamic> json) {
    return PurchaseInvoice(
      id: json['id'],
      supplierId: json['supplier_id'],
      date: DateTime.parse(json['date']),
      dueDate: json['due_date'] != null ? DateTime.parse(json['due_date']) : null,
      status: json['status'],
      prepaymentModel: json['prepayment_model'] ?? false,  // Default to standard
      subtotal: (json['subtotal'] ?? 0).toDouble(),
      tax: (json['tax'] ?? 0).toDouble(),
      total: (json['total'] ?? 0).toDouble(),
      paidAmount: (json['paid_amount'] ?? 0).toDouble(),
      balance: (json['balance'] ?? 0).toDouble(),
      notes: json['notes'],
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'supplier_id': supplierId,
      'date': date.toIso8601String(),
      'due_date': dueDate?.toIso8601String(),
      'status': status,
      'prepayment_model': prepaymentModel,
      'subtotal': subtotal,
      'tax': tax,
      'total': total,
      'paid_amount': paidAmount,
      'balance': balance,
      'notes': notes,
    };
  }
}
```

**File:** `lib/modules/purchases/models/purchase_payment.dart`

```dart
class PurchasePayment {
  final String id;
  final String invoiceId;
  final String? paymentMethodId;  // References payment_methods(id)
  final double amount;
  final DateTime date;
  final String? reference;
  final String? notes;
  
  PurchasePayment({
    required this.id,
    required this.invoiceId,
    this.paymentMethodId,
    required this.amount,
    required this.date,
    this.reference,
    this.notes,
  });
  
  factory PurchasePayment.fromJson(Map<String, dynamic> json) {
    return PurchasePayment(
      id: json['id'],
      invoiceId: json['invoice_id'],
      paymentMethodId: json['payment_method_id'],
      amount: (json['amount'] ?? 0).toDouble(),
      date: DateTime.parse(json['date']),
      reference: json['reference'],
      notes: json['notes'],
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'invoice_id': invoiceId,
      'payment_method_id': paymentMethodId,
      'amount': amount,
      'date': date.toIso8601String(),
      'reference': reference,
      'notes': notes,
    };
  }
}
```

#### **3.2 Create Purchase Service** (~40 mins)
**File:** `lib/modules/purchases/services/purchase_service.dart` (NEW)

```dart
class PurchaseService {
  final SupabaseClient _supabase = Supabase.instance.client;
  
  Future<List<PurchaseInvoice>> fetchInvoices({String? status}) async {
    var query = _supabase
      .from('purchase_invoices')
      .select()
      .order('date', ascending: false);
    
    if (status != null) {
      query = query.eq('status', status);
    }
    
    final response = await query;
    return (response as List)
      .map((json) => PurchaseInvoice.fromJson(json))
      .toList();
  }
  
  Future<PurchaseInvoice> getInvoiceById(String id) async {
    final response = await _supabase
      .from('purchase_invoices')
      .select()
      .eq('id', id)
      .single();
    
    return PurchaseInvoice.fromJson(response);
  }
  
  Future<void> createInvoice(PurchaseInvoice invoice) async {
    await _supabase.from('purchase_invoices').insert(invoice.toJson());
  }
  
  Future<void> updateInvoiceStatus(String id, String newStatus) async {
    await _supabase
      .from('purchase_invoices')
      .update({'status': newStatus})
      .eq('id', id);
    // Trigger handles journal entries and inventory
  }
  
  Future<void> createPayment(PurchasePayment payment) async {
    await _supabase.from('purchase_payments').insert(payment.toJson());
    // Trigger automatically creates journal entry
  }
  
  Future<List<PurchasePayment>> fetchPayments(String invoiceId) async {
    final response = await _supabase
      .from('purchase_payments')
      .select()
      .eq('invoice_id', invoiceId)
      .order('date', ascending: false);
    
    return (response as List)
      .map((json) => PurchasePayment.fromJson(json))
      .toList();
  }
}
```

#### **3.3 Create Prepayment Model Selection Dialog** (~30 mins)
**File:** `lib/modules/purchases/widgets/prepayment_selection_dialog.dart` (NEW)

```dart
class PrepaymentSelectionDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Seleccionar Modelo de Pago'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('¿Cuándo se realizará el pago?'),
          SizedBox(height: 20),
          
          // Standard Model Option
          Card(
            child: ListTile(
              leading: Icon(Icons.receipt_long, color: Colors.blue),
              title: Text('Pago Después'),
              subtitle: Text('Modelo estándar: Recibir → Pagar'),
              trailing: Icon(Icons.arrow_forward),
              onTap: () => Navigator.of(context).pop(false), // prepayment_model = false
            ),
          ),
          
          SizedBox(height: 12),
          
          // Prepayment Model Option
          Card(
            child: ListTile(
              leading: Icon(Icons.payment, color: Colors.green),
              title: Text('Pago Antes'),
              subtitle: Text('Prepago: Pagar → Recibir'),
              trailing: Icon(Icons.arrow_forward),
              onTap: () => Navigator.of(context).pop(true), // prepayment_model = true
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text('Cancelar'),
        ),
      ],
    );
  }
}
```

#### **3.4 Create Purchase Invoice Form** (~1 hour)
**File:** `lib/modules/purchases/pages/purchase_invoice_form_page.dart` (NEW)

```dart
class PurchaseInvoiceFormPage extends StatefulWidget {
  final PurchaseInvoice? invoice;  // null = new, non-null = edit
  
  PurchaseInvoiceFormPage({this.invoice});
  
  @override
  _PurchaseInvoiceFormPageState createState() => _PurchaseInvoiceFormPageState();
}

class _PurchaseInvoiceFormPageState extends State<PurchaseInvoiceFormPage> {
  final _formKey = GlobalKey<FormState>();
  
  String? _supplierId;
  DateTime _date = DateTime.now();
  DateTime? _dueDate;
  bool? _prepaymentModel;  // Will be set by dialog
  final _notesController = TextEditingController();
  
  @override
  void initState() {
    super.initState();
    if (widget.invoice != null) {
      // Edit mode
      _supplierId = widget.invoice!.supplierId;
      _date = widget.invoice!.date;
      _dueDate = widget.invoice!.dueDate;
      _prepaymentModel = widget.invoice!.prepaymentModel;
      _notesController.text = widget.invoice!.notes ?? '';
    } else {
      // New invoice - show prepayment selection dialog
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showPrepaymentDialog();
      });
    }
  }
  
  Future<void> _showPrepaymentDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PrepaymentSelectionDialog(),
    );
    
    if (result == null) {
      // User cancelled
      Navigator.of(context).pop();
      return;
    }
    
    setState(() {
      _prepaymentModel = result;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    if (_prepaymentModel == null && widget.invoice == null) {
      // Waiting for prepayment selection
      return Scaffold(
        appBar: AppBar(title: Text('Nueva Factura de Compra')),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.invoice == null ? 'Nueva Factura de Compra' : 'Editar Factura'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(16),
          children: [
            // Payment Model Badge (read-only, shown at top)
            Card(
              color: _prepaymentModel! ? Colors.green[50] : Colors.blue[50],
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(
                      _prepaymentModel! ? Icons.payment : Icons.receipt_long,
                      color: _prepaymentModel! ? Colors.green : Colors.blue,
                    ),
                    SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Modelo de Pago',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        Text(
                          _prepaymentModel! ? 'Prepago (Pagar antes)' : 'Estándar (Pagar después)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            SizedBox(height: 16),
            
            // Supplier dropdown (implement similar to customer dropdown in sales)
            // ... supplier selection widget
            
            // Date picker
            // ... date selection widget
            
            // Due date picker
            // ... due date selection widget
            
            // Invoice items (products, quantities, prices)
            // ... items list widget
            
            // Notes
            TextFormField(
              controller: _notesController,
              decoration: InputDecoration(labelText: 'Notas'),
              maxLines: 3,
            ),
            
            SizedBox(height: 24),
            
            // Save button
            ElevatedButton(
              onPressed: _saveInvoice,
              child: Text('Guardar Factura'),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _saveInvoice() async {
    if (!_formKey.currentState!.validate()) return;
    
    final invoice = PurchaseInvoice(
      id: widget.invoice?.id ?? '', // Generated by DB if new
      supplierId: _supplierId,
      date: _date,
      dueDate: _dueDate,
      status: 'Draft',
      prepaymentModel: _prepaymentModel!,
      subtotal: 0, // Calculate from items
      tax: 0, // Calculate from items
      total: 0, // Calculate from items
      paidAmount: 0,
      balance: 0,
      notes: _notesController.text.isEmpty ? null : _notesController.text,
    );
    
    if (widget.invoice == null) {
      await PurchaseService().createInvoice(invoice);
    } else {
      // Update existing invoice
    }
    
    Navigator.of(context).pop(true);
  }
}
```

#### **3.5 Create Purchase Invoice Detail Page** (~1 hour)
**File:** `lib/modules/purchases/pages/purchase_invoice_detail_page.dart` (NEW)

**Similar to Sales Invoice Detail Page but with:**
- Different status transitions based on `prepayment_model`
- Standard model: Draft→Sent→Confirmed→Received→Paid
- Prepayment model: Draft→Sent→Confirmed→Paid→Received
- Status-based button logic that checks `prepayment_model` field

```dart
String _getNextStatus(String current, bool isPrepayment) {
  if (isPrepayment) {
    // Prepayment flow
    switch (current) {
      case 'Draft': return 'Sent';
      case 'Sent': return 'Confirmed';
      case 'Confirmed': return 'Paid';  // Payment before receipt
      case 'Paid': return 'Received';  // Receive after payment
      default: return current;
    }
  } else {
    // Standard flow
    switch (current) {
      case 'Draft': return 'Sent';
      case 'Sent': return 'Confirmed';
      case 'Confirmed': return 'Received';  // Receive first
      case 'Received': return 'Paid';  // Pay after receipt
      default: return current;
    }
  }
}
```

#### **3.6 Create Purchase Invoice List Page** (~30 mins)
**File:** `lib/modules/purchases/pages/purchase_invoice_list_page.dart` (NEW)

- Display invoices in DataTable or ListView
- Show prepayment badge in list
- Status filters (Draft, Sent, Confirmed, Received, Paid)
- Search by supplier name or invoice number
- Navigate to detail page on tap

#### **3.7 Create Purchase Payment Form** (~30 mins)
**File:** `lib/modules/purchases/pages/purchase_payment_form_page.dart` (NEW)

**Can reuse the same payment form widget from sales** (see Phase 4)

---

### **Phase 4: Create Shared Components** ⏱️ ~1 hour

**Objective:** Reduce code duplication, ensure consistency

#### **4.1 Reusable Payment Form Widget** (~40 mins)
**File:** `lib/shared/widgets/payment_form_widget.dart` (NEW)

```dart
class PaymentFormWidget extends StatefulWidget {
  final String invoiceId;
  final double remainingBalance;
  final Function(Map<String, dynamic>) onSave;
  
  PaymentFormWidget({
    required this.invoiceId,
    required this.remainingBalance,
    required this.onSave,
  });
  
  @override
  _PaymentFormWidgetState createState() => _PaymentFormWidgetState();
}

class _PaymentFormWidgetState extends State<PaymentFormWidget> {
  final _paymentMethodService = PaymentMethodService();
  List<PaymentMethod> _paymentMethods = [];
  PaymentMethod? _selectedMethod;
  
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  
  @override
  void initState() {
    super.initState();
    _loadPaymentMethods();
    _amountController.text = widget.remainingBalance.toStringAsFixed(2);
  }
  
  Future<void> _loadPaymentMethods() async {
    final methods = await _paymentMethodService.fetchActivePaymentMethods();
    setState(() {
      _paymentMethods = methods;
      _selectedMethod = methods.isNotEmpty ? methods.first : null;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Payment Method Dropdown
        DropdownButtonFormField<PaymentMethod>(
          value: _selectedMethod,
          decoration: InputDecoration(labelText: 'Método de Pago'),
          items: _paymentMethods.map((method) {
            return DropdownMenuItem(
              value: method,
              child: Row(
                children: [
                  if (method.icon != null) Icon(_getIconData(method.icon!)),
                  SizedBox(width: 8),
                  Text(method.name),
                ],
              ),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedMethod = value;
              if (value?.requiresReference == false) {
                _referenceController.clear();
              }
            });
          },
        ),
        
        SizedBox(height: 16),
        
        // Amount
        TextFormField(
          controller: _amountController,
          decoration: InputDecoration(labelText: 'Monto'),
          keyboardType: TextInputType.number,
          validator: (value) {
            if (value == null || value.isEmpty) return 'Ingrese un monto';
            final amount = double.tryParse(value);
            if (amount == null || amount <= 0) return 'Monto inválido';
            return null;
          },
        ),
        
        SizedBox(height: 16),
        
        // Date Picker
        InkWell(
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: _selectedDate,
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
            );
            if (date != null) setState(() => _selectedDate = date);
          },
          child: InputDecorator(
            decoration: InputDecoration(labelText: 'Fecha'),
            child: Text(DateFormat('dd/MM/yyyy').format(_selectedDate)),
          ),
        ),
        
        SizedBox(height: 16),
        
        // Reference (conditional)
        if (_selectedMethod?.requiresReference == true)
          TextFormField(
            controller: _referenceController,
            decoration: InputDecoration(
              labelText: 'Referencia/Nº de Operación',
              hintText: 'Ej: Nº de transferencia, cheque',
            ),
            validator: (value) {
              if (_selectedMethod!.requiresReference && (value == null || value.isEmpty)) {
                return 'Este método de pago requiere referencia';
              }
              return null;
            },
          ),
        
        SizedBox(height: 16),
        
        // Notes
        TextFormField(
          controller: _notesController,
          decoration: InputDecoration(labelText: 'Notas (opcional)'),
          maxLines: 3,
        ),
        
        SizedBox(height: 24),
        
        // Save Button
        ElevatedButton(
          onPressed: () {
            if (_selectedMethod == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Seleccione un método de pago')),
              );
              return;
            }
            
            widget.onSave({
              'payment_method_id': _selectedMethod!.id,
              'amount': double.parse(_amountController.text),
              'date': _selectedDate.toIso8601String(),
              'reference': _referenceController.text.isEmpty ? null : _referenceController.text,
              'notes': _notesController.text.isEmpty ? null : _notesController.text,
            });
          },
          child: Text('Registrar Pago'),
          style: ElevatedButton.styleFrom(
            minimumSize: Size(double.infinity, 50),
          ),
        ),
      ],
    );
  }
  
  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'cash': return Icons.money;
      case 'transfer': return Icons.account_balance;
      case 'card': return Icons.credit_card;
      case 'check': return Icons.check_circle;
      default: return Icons.payment;
    }
  }
}
```

#### **4.2 Status Badge Widget** (~20 mins)
**File:** `lib/shared/widgets/status_badge_widget.dart` (NEW)

```dart
class StatusBadge extends StatelessWidget {
  final String status;
  
  StatusBadge({required this.status});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _getStatusColor(),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _getStatusText(),
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
  
  Color _getStatusColor() {
    switch (status) {
      case 'Draft': return Colors.grey;
      case 'Sent': return Colors.blue;
      case 'Confirmed': return Colors.purple;
      case 'Received': return Colors.orange;
      case 'Paid': return Colors.green;
      case 'Cancelled': return Colors.red;
      default: return Colors.grey;
    }
  }
  
  String _getStatusText() {
    switch (status) {
      case 'Draft': return 'Borrador';
      case 'Sent': return 'Enviada';
      case 'Confirmed': return 'Confirmada';
      case 'Received': return 'Recibida';
      case 'Paid': return 'Pagada';
      case 'Cancelled': return 'Cancelada';
      default: return status;
    }
  }
}
```

---

### **Phase 5: Testing & Verification** ⏱️ ~1 hour

**Objective:** Ensure all flows work end-to-end

#### **5.1 Sales Invoice Testing** (~20 mins)

**Test Scenario 1: Forward Flow**
1. ✅ Create new sales invoice (Draft status)
2. ✅ Click "Enviar" → verify status changes to Sent
3. ✅ Click "Confirmar" → verify status changes to Confirmed
4. ✅ Click "Registrar Pago" → navigate to payment form
5. ✅ Select payment method (Efectivo), enter amount, save
6. ✅ Verify invoice status changes to Paid
7. ✅ Check database: `journal_entries` table has 2 entries (invoice + payment)
8. ✅ Check database: Invoice entry DR: 1130, CR: 4101; Payment entry DR: 1101, CR: 1130

**Test Scenario 2: Backward Flow**
1. ✅ Open Paid invoice
2. ✅ Click "Desmarcar Pagada" → verify status goes back to Confirmed
3. ✅ Check database: Payment journal entry deleted
4. ✅ Click "Volver a Enviada" → verify status goes to Sent
5. ✅ Check database: Invoice journal entry deleted
6. ✅ Check database: Inventory restored (stock_movements with negative quantity)

**Test Scenario 3: Payment Methods**
1. ✅ Test payment with "Efectivo" → verify DR: 1101 Caja
2. ✅ Test payment with "Transferencia" → verify DR: 1110 Bancos
3. ✅ Verify "Transferencia" shows reference field, "Efectivo" doesn't

#### **5.2 Purchase Invoice Testing** (~30 mins)

**Test Scenario 4: Standard Model Flow**
1. ✅ Create new purchase invoice, select "Pago Después"
2. ✅ Verify `prepayment_model = false` in database
3. ✅ Progress through: Draft→Sent→Confirmed→Received
4. ✅ At Received: Verify inventory INCREASED (stock_movements positive quantity)
5. ✅ Click "Registrar Pago" → create payment
6. ✅ Verify status changes to Paid
7. ✅ Check database: Journal entries correct (Invoice: DR: 1105+1107, CR: 2101; Payment: DR: 2101, CR: payment account)

**Test Scenario 5: Prepayment Model Flow**
1. ✅ Create new purchase invoice, select "Pago Antes"
2. ✅ Verify `prepayment_model = true` in database
3. ✅ Progress through: Draft→Sent→Confirmed→Paid
4. ✅ At Paid: Verify payment recorded, inventory NOT yet increased
5. ✅ Click "Marcar como Recibida" → status changes to Received
6. ✅ Verify inventory INCREASED at this step
7. ✅ Check database: Journal entries correct

**Test Scenario 6: Purchase Backward Flow**
1. ✅ Open Paid purchase invoice (standard model)
2. ✅ Click backward → verify inventory restored
3. ✅ Verify journal entries deleted

#### **5.3 Database Verification** (~10 mins)

Run these SQL queries after testing:

```sql
-- Check payment methods are loaded
SELECT * FROM payment_methods WHERE is_active = true;

-- Check sales invoices have correct columns
SELECT id, status, paid_amount, balance FROM sales_invoices LIMIT 5;

-- Check sales payments use payment_method_id (not 'method')
SELECT sp.id, sp.invoice_id, sp.payment_method_id, pm.name
FROM sales_payments sp
JOIN payment_methods pm ON pm.id = sp.payment_method_id
LIMIT 5;

-- Check purchase invoices have prepayment_model field
SELECT id, status, prepayment_model, paid_amount, balance FROM purchase_invoices LIMIT 5;

-- Check journal entries created by triggers
SELECT * FROM journal_entries WHERE entry_type = 'SINV' ORDER BY created_at DESC LIMIT 5;
SELECT * FROM journal_entries WHERE entry_type = 'PAY' ORDER BY created_at DESC LIMIT 5;

-- Check inventory movements
SELECT * FROM stock_movements ORDER BY created_at DESC LIMIT 10;
```

---

## 📁 Complete File Tree

### Files to Create (NEW)
```
lib/
├── shared/
│   ├── models/
│   │   └── payment_method.dart                    ✅ NEW
│   ├── services/
│   │   └── payment_method_service.dart            ✅ NEW
│   └── widgets/
│       ├── payment_form_widget.dart               ✅ NEW
│       └── status_badge_widget.dart               ✅ NEW
│
└── modules/
    └── purchases/                                  ✅ NEW MODULE
        ├── models/
        │   ├── purchase_invoice.dart               ✅ NEW
        │   └── purchase_payment.dart               ✅ NEW
        ├── services/
        │   └── purchase_service.dart               ✅ NEW
        ├── pages/
        │   ├── purchase_invoice_list_page.dart     ✅ NEW
        │   ├── purchase_invoice_detail_page.dart   ✅ NEW
        │   ├── purchase_invoice_form_page.dart     ✅ NEW
        │   └── purchase_payment_form_page.dart     ✅ NEW
        └── widgets/
            └── prepayment_selection_dialog.dart    ✅ NEW
```

### Files to Modify (EXISTING)
```
lib/
└── modules/
    └── sales/
        ├── models/
        │   ├── sales_invoice.dart                  ⚠️ UPDATE (verify columns)
        │   └── sales_payment.dart                  ⚠️ UPDATE (add payment_method_id)
        ├── services/
        │   └── sales_service.dart                  ⚠️ UPDATE (fix column names)
        └── pages/
            ├── sales_invoice_list_page.dart        ⚠️ UPDATE (if needed)
            ├── sales_invoice_detail_page.dart      ⚠️ UPDATE (add status buttons)
            ├── sales_invoice_form_page.dart        ⚠️ UPDATE (if needed)
            └── sales_payment_form_page.dart        ⚠️ UPDATE (dynamic payment methods)
```

### Files to Integrate
```
lib/
├── main.dart                                       ⚠️ UPDATE (add purchases to navigation)
└── modules/
    └── dashboard/
        └── dashboard_page.dart                     ⚠️ UPDATE (add purchase shortcuts)
```

---

## ✅ Success Criteria

**After implementation, the following must work:**

1. ✅ **Payment Methods are Dynamic**
   - Dropdown loads from `payment_methods` table
   - Reference field appears/hides based on `requires_reference`
   - Journal entries use correct account (Efectivo→1101, Transferencia→1110)

2. ✅ **Sales Invoice Flow Works End-to-End**
   - Draft→Sent→Confirmed→Paid (forward)
   - Paid→Confirmed→Sent→Draft (backward with reversals)
   - Payment form uses dynamic payment methods
   - Status-based buttons appear correctly

3. ✅ **Purchase Invoice Standard Model Works**
   - Draft→Sent→Confirmed→Received→Paid
   - Inventory increases at "Received" status
   - Payment recorded at "Paid" status
   - Backward flow restores inventory

4. ✅ **Purchase Invoice Prepayment Model Works**
   - Draft→Sent→Confirmed→Paid→Received
   - Payment recorded at "Paid" status (before receipt)
   - Inventory increases at "Received" status (after payment)
   - Different button labels based on model

5. ✅ **Prepayment Selection Dialog**
   - Appears when creating new purchase invoice
   - User chooses "Pago Antes" or "Pago Después"
   - Selection stored in `prepayment_model` field
   - Cannot be changed after creation

6. ✅ **GUI Consistency**
   - Sales and Purchase modules have similar layouts
   - Same button styles and positioning
   - Same navigation patterns
   - Reusable payment form widget

7. ✅ **Column Names Match Schema**
   - `payment_method_id` (not `method`)
   - `prepayment_model` (not `is_prepaid`)
   - `paid_amount` (not `amount_paid`)
   - All models use exact column names from `core_schema.sql`

8. ✅ **Automatic Backend Triggers Work**
   - Status changes trigger journal entries (no manual insertion)
   - Status changes trigger inventory movements (no manual insertion)
   - Payment creation triggers journal entries
   - Payment deletion triggers entry deletion

9. ✅ **Database Integrity**
   - No orphaned journal entries
   - No negative inventory (except reversals)
   - Payment amounts match invoice balances
   - Status transitions follow allowed paths

10. ✅ **User Experience**
    - Clear visual feedback for status changes
    - Confirmation dialogs for destructive actions (backward transitions)
    - Loading states during async operations
    - Error messages for validation failures

---

## 🚨 CRITICAL RULES - DO NOT VIOLATE

### **Rule 1: core_schema.sql is the Source of Truth**
- ✅ Read column names from `core_schema.sql`
- ✅ Match data types exactly (uuid = String in Dart, numeric = double, boolean = bool)
- ❌ NEVER modify `core_schema.sql` to match Flutter
- ❌ NEVER assume column names without checking

### **Rule 2: Let Backend Handle Business Logic**
- ✅ Flutter changes invoice status only
- ✅ Triggers create/delete journal entries
- ✅ Triggers consume/restore inventory
- ❌ DO NOT manually insert into `journal_entries` from Flutter
- ❌ DO NOT manually insert into `stock_movements` from Flutter

### **Rule 3: Use Dynamic Payment Methods**
- ✅ Query `payment_methods` table at runtime
- ✅ Use `payment_method_id` (uuid) foreign key
- ❌ NEVER hardcode payment methods in Flutter
- ❌ NEVER use static CASE statements

### **Rule 4: Respect Prepayment Model**
- ✅ Ask user during purchase invoice creation
- ✅ Store in `prepayment_model` boolean field
- ✅ Use different status flows based on model
- ❌ DO NOT allow changing model after creation

### **Rule 5: Maintain GUI Consistency**
- ✅ Reuse widgets across modules (payment form, status badge)
- ✅ Same button styles in sales and purchase
- ✅ Same navigation patterns
- ❌ DO NOT create one-off widgets for each module

---

## ⏱️ Time Estimates

| Phase | Description | Estimated Time |
|-------|-------------|----------------|
| Phase 1 | Audit Current Flutter Code | 30 minutes |
| Phase 2 | Fix Sales Invoice Flow | 2-3 hours |
| Phase 3 | Implement Purchase Invoice Flow | 3-4 hours |
| Phase 4 | Create Shared Components | 1 hour |
| Phase 5 | Testing & Verification | 1 hour |
| **TOTAL** | **Complete Implementation** | **7.5-9.5 hours** |

---

## 📝 Next Steps

### **Immediate Action (Do Now)**
1. ✅ User reviews this plan
2. ✅ User approves approach or requests changes
3. ✅ Begin Phase 1: Audit existing Flutter code

### **After Audit (Do Next)**
1. ✅ Document audit findings (what works, what's broken, what's missing)
2. ✅ Prioritize fixes based on severity
3. ✅ Begin Phase 2: Fix sales module (establishes patterns)

### **Questions to Address Before Starting**
1. ❓ Are there existing sales module files to update, or do we create from scratch?
2. ❓ Should we audit first, or go straight to implementation?
3. ❓ Any specific UI/UX preferences for status buttons or payment form?

---

## 🎯 Final Checklist

Before marking this task complete, verify:

- [ ] All Flutter models match `core_schema.sql` columns exactly
- [ ] Payment methods loaded dynamically from database
- [ ] Sales invoice forward/backward flows work
- [ ] Purchase invoice standard model works
- [ ] Purchase invoice prepayment model works
- [ ] Prepayment selection dialog appears correctly
- [ ] Status-based buttons show/hide appropriately
- [ ] Reference field conditional on `requires_reference`
- [ ] Journal entries created automatically by triggers
- [ ] Inventory adjusted automatically by triggers
- [ ] GUI consistent between sales and purchase modules
- [ ] All database verification queries pass
- [ ] No compilation errors
- [ ] No runtime errors during testing

---

## 📚 Reference Documents

- **core_schema.sql**: Single source of truth for database structure
- **Invoice_status_flow.md**: Sales invoice workflow and accounting logic
- **Purchase_Invoice_status_flow.md**: Purchase invoice workflow (standard model)
- **Purchase_Invoice_Prepayment_Flow.md**: Prepayment model (needs updating after Flutter work)
- **PAYMENT_METHODS_IMPLEMENTATION.md**: Technical guide for payment methods system
- **copilot-instructions.md**: Project architecture and design rules

---

**END OF PLAN**

This plan will serve as the reference guide for the entire Flutter integration process. Once approved, we'll proceed with Phase 1 (Audit) and work through each phase systematically.
