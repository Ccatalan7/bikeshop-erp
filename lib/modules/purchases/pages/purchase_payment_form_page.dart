import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/models/payment_method.dart';
import '../../../shared/services/payment_method_service.dart';
import '../models/purchase_invoice.dart';

/// Payment Form Page for Purchase Invoices
/// Handles payment registration for both Standard and Prepayment models
/// Uses dynamic payment methods from database
class PurchasePaymentFormPage extends StatefulWidget {
  final String invoiceId;
  final PurchaseInvoice invoice;

  const PurchasePaymentFormPage({
    super.key,
    required this.invoiceId,
    required this.invoice,
  });

  @override
  State<PurchasePaymentFormPage> createState() => _PurchasePaymentFormPageState();
}

class _PurchasePaymentFormPageState extends State<PurchasePaymentFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();
  final _paymentMethodService = PaymentMethodService();

  PaymentMethod? _selectedPaymentMethod;
  DateTime _paymentDate = DateTime.now();
  bool _isSaving = false;

  List<PaymentMethod> _paymentMethods = [];
  bool _isLoadingPaymentMethods = true;

  @override
  void initState() {
    super.initState();
    // Pre-fill amount with invoice balance
    _amountController.text = widget.invoice.balance.toStringAsFixed(0);
    _loadPaymentMethods();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadPaymentMethods() async {
    try {
      await _paymentMethodService.loadPaymentMethods();
      if (mounted) {
        setState(() {
          _paymentMethods = _paymentMethodService.paymentMethods;
          // Select first payment method by default (usually "Efectivo")
          if (_paymentMethods.isNotEmpty) {
            _selectedPaymentMethod = _paymentMethods.first;
          }
          _isLoadingPaymentMethods = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingPaymentMethods = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading payment methods: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _savePayment() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedPaymentMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debe seleccionar un método de pago'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validate reference if required
    if (_selectedPaymentMethod!.requiresReference && 
        _referenceController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_selectedPaymentMethod!.name} requiere número de referencia'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text.replaceAll('.', '').replaceAll(',', '.'));
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingrese un monto válido'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (amount > widget.invoice.balance) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Monto mayor al saldo'),
          content: Text(
            'El monto ingresado (${ChileanUtils.formatCurrency(amount)}) '
            'es mayor al saldo de la factura (${ChileanUtils.formatCurrency(widget.invoice.balance)}).\n\n'
            '¿Desea continuar de todas formas?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );

      if (confirm != true) return;
    }

    setState(() => _isSaving = true);

    try {
      // Create payment record - use correct column names from core_schema.sql
      final paymentData = {
        'invoice_id': widget.invoiceId,  // Correct column name (not purchase_invoice_id)
        'date': _paymentDate.toIso8601String(),
        'amount': amount,
        'payment_method_id': _selectedPaymentMethod!.id,  // UUID foreign key
        'reference': _referenceController.text.trim().isEmpty 
            ? null 
            : _referenceController.text.trim(),
        'notes': _notesController.text.trim().isEmpty 
            ? null 
            : _notesController.text.trim(),
      };

      await Supabase.instance.client
          .from('purchase_payments')
          .insert(paymentData);

      // Trigger automatically:
      // 1. Creates journal entry via handle_purchase_payment_change()
      // 2. Updates invoice paid_amount and balance via recalculate_purchase_invoice_payments()
      // 3. Updates invoice status if fully paid

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pago registrado: ${ChileanUtils.formatCurrency(amount)}'),
            backgroundColor: Colors.green,
          ),
        );
        context.pop(true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al registrar pago: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar Pago'),
        actions: [
          if (_isSaving)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: _isLoadingPaymentMethods
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildInvoiceInfo(),
                    const SizedBox(height: 24),
                    _buildPaymentForm(),
                    const SizedBox(height: 32),
                    _buildActionButtons(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildInvoiceInfo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Factura ${widget.invoice.invoiceNumber}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (widget.invoice.supplierName != null)
              Text(
                widget.invoice.supplierName!,
                style: const TextStyle(color: Colors.grey),
              ),
            const Divider(height: 24),
            _buildInfoRow('Total', ChileanUtils.formatCurrency(widget.invoice.total)),
            _buildInfoRow('Pagado', ChileanUtils.formatCurrency(widget.invoice.paidAmount)),
            _buildInfoRow(
              'Saldo',
              ChileanUtils.formatCurrency(widget.invoice.balance),
              highlight: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
              fontSize: highlight ? 18 : 14,
              color: highlight ? Colors.blue : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentForm() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Detalles del Pago',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            // Payment Date
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today),
              title: const Text('Fecha de Pago'),
              subtitle: Text(ChileanUtils.formatDate(_paymentDate)),
              trailing: const Icon(Icons.edit),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _paymentDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now().add(const Duration(days: 1)),
                );
                if (picked != null) {
                  setState(() => _paymentDate = picked);
                }
              },
            ),
            const Divider(),

            // Payment Amount
            TextFormField(
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: 'Monto *',
                prefixText: '\$ ',
                hintText: '0',
                helperText: 'Ingrese el monto del pago',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
              ],
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'El monto es requerido';
                }
                final amount = double.tryParse(value.replaceAll('.', ''));
                if (amount == null || amount <= 0) {
                  return 'Ingrese un monto válido';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Payment Method (Dynamic from database)
            DropdownButtonFormField<PaymentMethod>(
              value: _selectedPaymentMethod,
              decoration: const InputDecoration(
                labelText: 'Método de Pago *',
                prefixIcon: Icon(Icons.payment),
              ),
              items: _paymentMethods.map((method) {
                return DropdownMenuItem<PaymentMethod>(
                  value: method,
                  child: Row(
                    children: [
                      Icon(_getPaymentMethodIcon(method.icon), size: 20),
                      const SizedBox(width: 8),
                      Text(method.name),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (value) {
                setState(() => _selectedPaymentMethod = value);
              },
              validator: (value) {
                if (value == null) {
                  return 'Seleccione un método de pago';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Reference field (conditional based on payment method)
            if (_selectedPaymentMethod?.requiresReference == true) ...[
              TextFormField(
                controller: _referenceController,
                decoration: InputDecoration(
                  labelText: 'Referencia *',
                  hintText: 'Ej: Transferencia #12345',
                  prefixIcon: const Icon(Icons.numbers),
                  helperText: 'Campo requerido para ${_selectedPaymentMethod?.name}',
                  helperStyle: const TextStyle(color: Colors.red),
                ),
                maxLength: 100,
                validator: (value) {
                  if (_selectedPaymentMethod?.requiresReference == true &&
                      (value == null || value.trim().isEmpty)) {
                    return 'La referencia es requerida para ${_selectedPaymentMethod?.name}';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
            ],
            if (_selectedPaymentMethod?.requiresReference != true) ...[
              TextFormField(
                controller: _referenceController,
                decoration: const InputDecoration(
                  labelText: 'Referencia (opcional)',
                  hintText: 'Ej: Comprobante #12345',
                  prefixIcon: Icon(Icons.numbers),
                ),
                maxLength: 100,
              ),
              const SizedBox(height: 8),
            ],

            // Notes
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notas',
                hintText: 'Observaciones adicionales',
                prefixIcon: Icon(Icons.note),
              ),
              maxLines: 3,
              maxLength: 500,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _isSaving ? null : () => context.pop(false),
            child: const Text('Cancelar'),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: _isSaving ? null : _savePayment,
            icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check),
            label: Text(_isSaving ? 'Guardando...' : 'Registrar Pago'),
          ),
        ),
      ],
    );
  }

  IconData _getPaymentMethodIcon(String? iconName) {
    switch (iconName?.toLowerCase()) {
      case 'cash':
        return Icons.money;
      case 'bank':
        return Icons.account_balance;
      case 'credit_card':
        return Icons.credit_card;
      case 'receipt':
        return Icons.receipt;
      default:
        return Icons.payment;
    }
  }
}
