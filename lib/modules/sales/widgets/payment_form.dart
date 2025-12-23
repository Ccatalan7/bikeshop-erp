import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/payment_method.dart';
import '../../../shared/models/tax_treatment.dart';
import '../../../shared/services/payment_method_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../models/sales_models.dart';
import '../services/sales_service.dart';

class PaymentForm extends StatefulWidget {
  const PaymentForm({
    super.key,
    required this.invoice,
    this.onCompleted,
    this.dismissOnSubmit = true,
  });

  final Invoice invoice;
  final VoidCallback? onCompleted;
  final bool dismissOnSubmit;

  @override
  State<PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends State<PaymentForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  PaymentMethod? _selectedPaymentMethod;
  DateTime _paymentDate = DateTime.now();
  bool _isSaving = false;
  bool _isLoadingMethods = true;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.invoice.balance.toStringAsFixed(0),
    );
    _loadPaymentMethods();
  }

  Future<void> _loadPaymentMethods() async {
    final paymentMethodService = context.read<PaymentMethodService>();
    await paymentMethodService.loadPaymentMethods();
    if (mounted) {
      setState(() {
        _isLoadingMethods = false;
        // Default to first payment method (usually cash)
        if (paymentMethodService.paymentMethods.isNotEmpty) {
          _selectedPaymentMethod = paymentMethodService.paymentMethods.first;
        }
      });
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paymentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _paymentDate = picked);
    }
  }

  /// Check if there's a mismatch between invoice tax treatment and payment method
  String? _checkTaxMismatch() {
    if (_selectedPaymentMethod == null) return null;

    final invoiceHasTax =
        widget.invoice.taxTreatment == TaxTreatment.taxIncluded;
    final paymentMethodExpectsTax =
        _selectedPaymentMethod!.defaultTaxTreatment == TaxTreatment.taxIncluded;

    if (!invoiceHasTax && paymentMethodExpectsTax) {
      return 'no_tax_with_card';
    } else if (invoiceHasTax && !paymentMethodExpectsTax) {
      return 'has_tax_without_card';
    }

    return null;
  }

  /// Show warning dialog with option to fix IVA
  Future<bool> _showTaxMismatchWarning(String mismatchType) async {
    final isNoTaxWithCard = mismatchType == 'no_tax_with_card';

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          Icons.warning_amber_rounded,
          color: Colors.orange[700],
          size: 48,
        ),
        title: const Text('⚠️ Advertencia: IVA'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isNoTaxWithCard
                  ? 'Esta factura NO tiene IVA incluido, pero estás pagando con ${_selectedPaymentMethod!.name}.'
                  : 'Esta factura tiene IVA incluido, pero estás pagando con ${_selectedPaymentMethod!.name}.',
              style: const TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 12),
            Text(
              isNoTaxWithCard
                  ? 'Los pagos con tarjeta normalmente requieren factura con IVA.'
                  : 'Los pagos en efectivo/transferencia normalmente NO llevan IVA.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'proceed'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.orange[700],
            ),
            child: const Text('Pagar de Todas Formas'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, 'fix'),
            icon: const Icon(Icons.edit, size: 18),
            label: const Text('Corregir IVA y Volver'),
          ),
        ],
      ),
    );

    if (result == 'fix') {
      await _fixInvoiceTaxAndNavigate(isNoTaxWithCard);
      return false; // Don't proceed with payment
    }

    return result == 'proceed'; // True if user chose to proceed anyway
  }

  /// Revert invoice to 'sent' status, update IVA, and navigate to form
  Future<void> _fixInvoiceTaxAndNavigate(bool shouldAddTax) async {
    final salesService = context.read<SalesService>();

    try {
      // Step 1: Change status back to 'sent' (triggers journal entry deletion)
      await salesService.updateInvoiceStatus(
        widget.invoice.id!,
        InvoiceStatus.sent,
      );

      // Step 2: Update the tax treatment AND recalculate amounts
      final newTaxTreatment =
          shouldAddTax ? TaxTreatment.taxIncluded : TaxTreatment.noTax;

      // Get current invoice total
      final currentTotal = widget.invoice.total;

      // Calculate new amounts based on tax treatment
      final double newNetAmount;
      final double newIvaAmount;

      if (shouldAddTax) {
        // Adding tax: divide total by 1.19 to get net
        newNetAmount = currentTotal / 1.19;
        newIvaAmount = currentTotal - newNetAmount;
      } else {
        // Removing tax: total = net (no IVA)
        newNetAmount = currentTotal;
        newIvaAmount = 0;
      }

      await Supabase.instance.client.from('sales_invoices').update({
        'tax_treatment': newTaxTreatment.value,
        'net_amount': newNetAmount,
        'iva_amount': newIvaAmount,
      }).eq('id', widget.invoice.id!);

      // Step 3: Wait a moment for database write to complete
      await Future.delayed(const Duration(milliseconds: 100));

      // Step 4: Reload the invoice from database to get fresh data
      await salesService.loadInvoices();

      if (!mounted) return;

      // Step 4: Close payment form and show success message
      Navigator.of(context).pop(true); // Return true to signal refresh needed

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            shouldAddTax
                ? 'Factura revertida a "Enviada". Agrega IVA y confirma nuevamente.'
                : 'Factura revertida a "Enviada". Quita IVA y confirma nuevamente.',
          ),
          backgroundColor: Colors.blue,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al corregir factura: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedPaymentMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un método de pago.')),
      );
      return;
    }

    // Check for tax treatment mismatch
    final taxMismatch = _checkTaxMismatch();
    if (taxMismatch != null) {
      final shouldProceed = await _showTaxMismatchWarning(taxMismatch);
      if (!shouldProceed) {
        return; // User cancelled or went to fix IVA
      }
    }

    final rawAmount =
        _amountController.text.trim().replaceAll('.', '').replaceAll(',', '.');
    final amount = double.tryParse(rawAmount);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un monto válido.')),
      );
      return;
    }

    final balance = widget.invoice.balance;
    final amountInt = amount.round();
    final balanceInt = balance.round();
    if (amountInt - balanceInt > 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'El pago no puede exceder el saldo (${ChileanUtils.formatCurrency(balance)})')),
      );
      return;
    }

    final effectiveAmount = amount > balance ? balance : amount;

    final salesService = context.read<SalesService>();

    final tenantId = await TenantService().getTenantId();
    if (tenantId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Error: No se pudo obtener el tenant ID')),
        );
      }
      return;
    }

    setState(() => _isSaving = true);
    try {
      final payment = Payment(
        tenantId: tenantId,
        invoiceId: widget.invoice.id!,
        invoiceReference: widget.invoice.invoiceNumber.isNotEmpty
            ? widget.invoice.invoiceNumber
            : null,
        paymentMethodId: _selectedPaymentMethod!.id,
        amount: effectiveAmount,
        date: _paymentDate,
        reference: _referenceController.text.trim().isEmpty
            ? null
            : _referenceController.text.trim(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      await salesService.registerPayment(payment);
      widget.onCompleted?.call();
      if (mounted) {
        if (widget.dismissOnSubmit) {
          Navigator.of(context).pop(true);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pago registrado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('No se pudo registrar el pago: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final invoice = widget.invoice;
    final paymentMethodService = context.watch<PaymentMethodService>();

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pagar factura',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text(
            invoice.customerName ?? 'Cliente',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),

          // Invoice breakdown card
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildBreakdownRow(
                    'Subtotal:',
                    ChileanUtils.formatCurrency(invoice.netAmount),
                    context,
                  ),
                  if (invoice.taxTreatment == TaxTreatment.taxIncluded) ...[
                    const SizedBox(height: 4),
                    _buildBreakdownRow(
                      'IVA (19%):',
                      ChileanUtils.formatCurrency(invoice.ivaAmount),
                      context,
                    ),
                  ],
                  const Divider(height: 16),
                  _buildBreakdownRow(
                    'Total factura:',
                    ChileanUtils.formatCurrency(invoice.total),
                    context,
                    isBold: true,
                  ),
                  const SizedBox(height: 4),
                  _buildBreakdownRow(
                    'Saldo pendiente:',
                    ChileanUtils.formatCurrency(invoice.balance),
                    context,
                    isBold: true,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _amountController,
            decoration: const InputDecoration(
              labelText: 'Monto',
              prefixText: '\$ ',
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Ingresa el monto del pago';
              }
              final normalizedValue =
                  value.replaceAll('.', '').replaceAll(',', '.');
              final parsed = double.tryParse(normalizedValue);
              if (parsed == null || parsed <= 0) {
                return 'Monto inválido';
              }
              final parsedInt = parsed.round();
              final balanceInt = invoice.balance.round();
              if (parsedInt - balanceInt > 1) {
                return 'No puede superar el saldo';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          if (_isLoadingMethods)
            const LinearProgressIndicator()
          else if (paymentMethodService.paymentMethods.isEmpty)
            const Text(
              'No hay métodos de pago disponibles',
              style: TextStyle(color: Colors.red),
            )
          else
            DropdownButtonFormField<PaymentMethod>(
              value: _selectedPaymentMethod,
              decoration: const InputDecoration(labelText: 'Medio de pago'),
              items: paymentMethodService.paymentMethods
                  .map((method) => DropdownMenuItem(
                        value: method,
                        child: Row(
                          children: [
                            if (method.icon != null) ...[
                              Icon(_getIconForPaymentMethod(method.icon!),
                                  size: 18),
                              const SizedBox(width: 8),
                            ],
                            Text(method.name),
                          ],
                        ),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedPaymentMethod = value);
                }
              },
              validator: (value) {
                if (value == null) {
                  return 'Selecciona un método de pago';
                }
                return null;
              },
            ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _selectDate,
            borderRadius: BorderRadius.circular(8),
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Fecha de pago',
                border: OutlineInputBorder(),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event),
                  const SizedBox(width: 8),
                  Text(ChileanUtils.formatDate(_paymentDate)),
                  const Spacer(),
                  const Icon(Icons.keyboard_arrow_down),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_selectedPaymentMethod?.requiresReference == true) ...[
            TextFormField(
              controller: _referenceController,
              decoration: const InputDecoration(
                labelText: 'Referencia *',
                hintText: 'Número de transferencia, cheque, etc.',
              ),
              validator: (value) {
                if (_selectedPaymentMethod?.requiresReference == true &&
                    (value == null || value.trim().isEmpty)) {
                  return 'Este método de pago requiere una referencia';
                }
                return null;
              },
            ),
          ] else ...[
            TextFormField(
              controller: _referenceController,
              decoration: const InputDecoration(
                labelText: 'Referencia',
                hintText: 'Número de documento, comprobante, etc. (opcional)',
              ),
            ),
          ],
          const SizedBox(height: 12),
          TextFormField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Notas internas',
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _submit,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const Text('Registrar pago'),
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIconForPaymentMethod(String iconName) {
    switch (iconName.toLowerCase()) {
      case 'cash':
        return Icons.attach_money;
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

  Widget _buildBreakdownRow(
    String label,
    String value,
    BuildContext context, {
    bool isBold = false,
    Color? color,
  }) {
    final textStyle = isBold
        ? Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            )
        : Theme.of(context).textTheme.bodyLarge?.copyWith(color: color);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: textStyle),
        Text(value, style: textStyle),
      ],
    );
  }
}
