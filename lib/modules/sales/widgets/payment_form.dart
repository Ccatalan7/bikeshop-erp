import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

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
  final String _idempotencyKey = const Uuid().v4();
  late final TextEditingController _amountController;
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  PaymentMethod? _selectedPaymentMethod;
  DateTime _paymentDate = DateTime.now();
  bool _isSaving = false;
  bool _isLoadingMethods = true;
  bool _includesIva = false;

  bool get _taxChoiceIsLocked => widget.invoice.paidAmount > 0.01;

  int? _parseWholePesoAmount(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'[\s$]'), '');
    if (normalized.isEmpty || normalized.contains(',')) {
      return null;
    }
    if (normalized.contains('.')) {
      final thousandsPattern = RegExp(r'^\d{1,3}(\.\d{3})+$');
      if (!thousandsPattern.hasMatch(normalized)) {
        return null;
      }
      return int.tryParse(normalized.replaceAll('.', ''));
    }
    return int.tryParse(normalized);
  }

  /// Effective balance: always compute from total - paidAmount for consistency.
  /// The raw DB `balance` field can be stale if the invoice total was changed
  /// after a payment was recorded, causing it to disagree with paid_amount.
  double get _effectiveBalance {
    final calculated = (widget.invoice.total - widget.invoice.paidAmount)
        .clamp(0.0, widget.invoice.total);
    return calculated.abs() < 1 ? 0 : calculated;
  }

  @override
  void initState() {
    super.initState();
    _includesIva = widget.invoice.taxTreatment == TaxTreatment.taxIncluded;
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
        if (paymentMethodService.incomingPaymentMethods.isNotEmpty) {
          _selectedPaymentMethod =
              paymentMethodService.incomingPaymentMethods.first;
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
    if (_isSaving) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_selectedPaymentMethod == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un método de pago.')),
      );
      return;
    }

    final amountPesos = _parseWholePesoAmount(_amountController.text);
    if (amountPesos == null || amountPesos <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ingresa un monto en pesos enteros.')),
      );
      return;
    }

    final balance = _effectiveBalance;
    final balancePesos = balance.round();
    if (amountPesos > balancePesos) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'El pago no puede exceder el saldo (${ChileanUtils.formatCurrency(balance)})')),
      );
      return;
    }

    final salesService = context.read<SalesService>();

    setState(() => _isSaving = true);
    try {
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

      final payment = Payment(
        tenantId: tenantId,
        invoiceId: widget.invoice.id!,
        invoiceReference: widget.invoice.invoiceNumber.isNotEmpty
            ? widget.invoice.invoiceNumber
            : null,
        paymentMethodId: _selectedPaymentMethod!.id,
        idempotencyKey: _idempotencyKey,
        amount: amountPesos.toDouble(),
        date: _paymentDate,
        reference: _referenceController.text.trim().isEmpty
            ? null
            : _referenceController.text.trim(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        taxTreatment: _includesIva ? 'tax_included' : 'no_tax',
      );

      await salesService.registerPaymentWithInvoiceTax(
        payment,
        _includesIva ? TaxTreatment.taxIncluded : TaxTreatment.noTax,
      );
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
            'Pago y documento tributario',
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
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Ingresa el monto del pago';
              }
              final parsed = _parseWholePesoAmount(value);
              if (parsed == null || parsed <= 0) {
                return 'Ingresa pesos enteros, sin decimales';
              }
              if (parsed > _effectiveBalance.round()) {
                return 'No puede superar el saldo';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          if (_isLoadingMethods)
            const LinearProgressIndicator()
          else if (paymentMethodService.incomingPaymentMethods.isEmpty)
            const Text(
              'No hay métodos de pago disponibles',
              style: TextStyle(color: Colors.red),
            )
          else
            DropdownButtonFormField<PaymentMethod>(
              initialValue: _selectedPaymentMethod,
              decoration: const InputDecoration(labelText: 'Medio de pago'),
              items: paymentMethodService.incomingPaymentMethods
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

          // The terminal owns the tax choice for the whole invoice. Payments
          // only settle accounts receivable; they never recognize IVA twice.
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Factura incluye IVA (19%)'),
            subtitle: Text(
              _includesIva
                  ? 'El total ya incluye IVA; se separará neto e impuesto.'
                  : 'El total completo se registrará sin IVA.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            value: _includesIva,
            onChanged: _taxChoiceIsLocked
                ? null
                : (value) => setState(() => _includesIva = value),
            secondary: Icon(
              _includesIva ? Icons.receipt_long : Icons.receipt_outlined,
              color:
                  _includesIva ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
          if (_taxChoiceIsLocked)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'El documento tributario quedó fijado con el primer pago. '
                'Para cambiarlo se requiere una corrección auditada.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),

          // Show the invoice classification using the full document total, not
          // only the partial payment amount.
          if (_includesIva) ...[
            Builder(builder: (context) {
              final invoiceTotal = widget.invoice.total.roundToDouble();
              final net = (invoiceTotal / 1.19).roundToDouble();
              final iva = invoiceTotal - net;
              return Card(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.3),
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
                      _buildBreakdownRow('Total factura:',
                          ChileanUtils.formatCurrency(invoiceTotal), context,
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
