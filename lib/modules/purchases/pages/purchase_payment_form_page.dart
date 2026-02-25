import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/models/payment_method.dart';
import '../../../shared/services/payment_method_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../models/purchase_invoice.dart';
import '../models/purchase_payment.dart';
import '../services/purchase_service.dart';

class PurchasePaymentFormPage extends StatefulWidget {
  final String invoiceId;

  const PurchasePaymentFormPage({
    super.key,
    required this.invoiceId,
  });

  @override
  State<PurchasePaymentFormPage> createState() =>
      _PurchasePaymentFormPageState();
}

class _PurchasePaymentFormPageState extends State<PurchasePaymentFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();

  PaymentMethod? _selectedPaymentMethod;
  DateTime _paymentDate = DateTime.now();
  bool _isSaving = false;
  bool _isLoading = true;
  bool _isLoadingMethods = true;
  PurchaseInvoice? _invoice;

  /// Effective balance: guards against cases where the DB trigger hasn't updated yet or was negative
  double get _effectiveBalance {
    if (_invoice == null) return 0;
    final b = _invoice!.balance;
    if (b > 0) return b;
    double calculated = (_invoice!.total - _invoice!.paidAmount);
    if (calculated < 0) calculated = 0;
    return calculated;
  }

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController();
    _loadInvoice();
    _loadPaymentMethods();
  }

  Future<void> _loadInvoice() async {
    try {
      final purchaseService = context.read<PurchaseService>();
      final invoices =
          await purchaseService.getPurchaseInvoices(forceRefresh: true);
      final invoice = invoices.firstWhere((inv) => inv.id == widget.invoiceId);

      if (mounted) {
        setState(() {
          _invoice = invoice;
          _isLoading = false;
          _amountController.text = _effectiveBalance.toStringAsFixed(0);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar factura: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadPaymentMethods() async {
    final paymentMethodService = context.read<PaymentMethodService>();
    await paymentMethodService.loadPaymentMethods();
    if (mounted) {
      setState(() {
        _isLoadingMethods = false;
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

  void _returnToInvoice({bool refresh = false}) {
    if (refresh) {
      GoRouter.of(context).pop(true);
    } else {
      GoRouter.of(context).pop();
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

    final purchaseService = context.read<PurchaseService>();
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
      final payment = PurchasePayment(
        tenantId: tenantId,
        invoiceId: widget.invoiceId,
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

      await purchaseService.createPayment(payment);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pago registrado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
        _returnToInvoice(refresh: true);
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
    return MainLayout(
      child: _isLoading
          ? const Center(child: BrandedLoading())
          : _invoice == null
              ? _buildNotFound()
              : _buildContent(context, _invoice!),
    );
  }

  Widget _buildNotFound() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.receipt_long, size: 64),
          const SizedBox(height: 16),
          const Text('Factura no encontrada'),
          const SizedBox(height: 16),
          AppButton(
            text: 'Volver',
            onPressed: _returnToInvoice,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, PurchaseInvoice invoice) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        final padding =
            isMobile ? const EdgeInsets.all(16) : const EdgeInsets.all(24);

        return SingleChildScrollView(
          padding: padding,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: isMobile ? double.infinity : 560,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: _returnToInvoice,
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Volver',
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              invoice.invoiceNumber.isNotEmpty
                                  ? 'Factura ${invoice.invoiceNumber}'
                                  : 'Factura',
                              style: theme.textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              invoice.supplierName ?? 'Proveedor',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildFormContents(context, invoice),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFormContents(BuildContext context, PurchaseInvoice invoice) {
    final paymentMethodService = context.watch<PaymentMethodService>();
    final theme = Theme.of(context);

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Registrar pago a proveedor',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // Invoice breakdown card
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
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
                  const SizedBox(height: 4),
                  _buildBreakdownRow(
                    'Pagado:',
                    ChileanUtils.formatCurrency(invoice.paidAmount),
                    context,
                  ),
                  const Divider(height: 16),
                  const SizedBox(height: 4),
                  _buildBreakdownRow(
                    'Saldo pendiente:',
                    ChileanUtils.formatCurrency(_effectiveBalance),
                    context,
                    isBold: true,
                    color: theme.colorScheme.primary,
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
