import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
  bool _includesIva = false; // Payment-level IVA toggle

  /// Effective balance: use DB balance when > 0; fall back to total - paidAmount.
  /// Guards against cases where the DB `balance` trigger hasn't updated yet.
  double get _effectiveBalance {
    final b = widget.invoice.balance;
    if (b > 0) return b;
    return (widget.invoice.total - widget.invoice.paidAmount)
        .clamp(0.0, widget.invoice.total);
  }

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: _effectiveBalance.toStringAsFixed(0),
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
          // Set IVA based on payment method's default
          _includesIva = _selectedPaymentMethod?.defaultTaxTreatment ==
              TaxTreatment.taxIncluded;
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

    final rawAmount =
        _amountController.text.trim().replaceAll('.', '').replaceAll(',', '.');
    final amount = double.tryParse(rawAmount);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un monto válido.')),
      );
      return;
    }

    final balance = _effectiveBalance;
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
        taxTreatment: _includesIva ? 'tax_included' : 'no_tax',
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
                    'Total factura:',
                    ChileanUtils.formatCurrency(invoice.total),
                    context,
                  ),
                  const Divider(height: 16),
                  const SizedBox(height: 4),
                  _buildBreakdownRow(
                    'Saldo pendiente:',
                    ChileanUtils.formatCurrency(_effectiveBalance),
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
              final balanceInt = _effectiveBalance.round();
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
                  setState(() {
                    _selectedPaymentMethod = value;
                    // Auto-set IVA toggle based on payment method default
                    _includesIva =
                        value.defaultTaxTreatment == TaxTreatment.taxIncluded;
                  });
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

          // IVA toggle - payment-level tax treatment
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Incluye IVA (19%)'),
            subtitle: Text(
              _includesIva
                  ? 'El pago incluye impuesto'
                  : 'Pago sin boleta/factura electrónica',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            value: _includesIva,
            onChanged: (value) => setState(() => _includesIva = value),
            secondary: Icon(
              _includesIva ? Icons.receipt_long : Icons.receipt_outlined,
              color:
                  _includesIva ? Theme.of(context).colorScheme.primary : null,
            ),
          ),

          // Show IVA breakdown when toggle is on
          if (_includesIva) ...[
            Builder(builder: (context) {
              final rawAmount = _amountController.text
                  .trim()
                  .replaceAll('.', '')
                  .replaceAll(',', '.');
              final amount = double.tryParse(rawAmount) ?? 0;
              final net = (amount / 1.19).roundToDouble();
              final iva = amount - net;
              return Card(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withOpacity(0.3),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      _buildBreakdownRow(
                          'Neto:', ChileanUtils.formatCurrency(net), context),
                      const SizedBox(height: 4),
                      _buildBreakdownRow('IVA (19%):',
                          ChileanUtils.formatCurrency(iva), context),
                      const Divider(height: 12),
                      _buildBreakdownRow('Total:',
                          ChileanUtils.formatCurrency(amount), context,
                          isBold: true),
                    ],
                  ),
                ),
              );
            }),
          ],
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
