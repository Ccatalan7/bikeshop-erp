import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/models/payment_method.dart';
import '../../../shared/services/payment_method_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/utils/purchase_payment_receipt_pdf_generator.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../models/purchase_invoice.dart';
import '../models/purchase_payment.dart';
import '../services/purchase_service.dart';

/// Full-size editor for an existing supplier payment.
///
/// This surface never writes purchase or accounting tables directly. It only
/// submits the audited `correct_purchase_payment` command through
/// [PurchaseService.correctPurchasePayment].
class PurchasePaymentEditPage extends StatefulWidget {
  const PurchasePaymentEditPage({super.key, required this.paymentId});

  final String paymentId;

  @override
  State<PurchasePaymentEditPage> createState() =>
      _PurchasePaymentEditPageState();
}

class _PurchasePaymentEditPageState extends State<PurchasePaymentEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();
  final _reasonController = TextEditingController();

  PurchasePayment? _payment;
  PurchaseInvoice? _invoice;
  DateTime? _date;
  bool _dateChanged = false;
  String? _paymentMethodId;
  double _otherActivePaidAmount = 0;
  String? _operationKey;
  String? _operationPayload;
  bool _loading = true;
  bool _saving = false;
  bool _staleConflict = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _amountController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _staleConflict = false;
      _error = null;
    });

    try {
      final purchases = context.read<PurchaseService>();
      final methods = context.read<PaymentMethodService>();
      final payment = await purchases.fetchPurchasePayment(
        widget.paymentId,
        refresh: true,
      );
      if (payment == null) {
        throw StateError('El pago no existe o ya no está activo.');
      }

      final invoice = await purchases.fetchPurchaseInvoice(
        payment.invoiceId,
        refresh: true,
      );
      if (invoice == null) {
        throw StateError('No se encontró la factura vinculada al pago.');
      }

      final activePayments =
          await purchases.getPaymentsForInvoice(payment.invoiceId);
      await methods.loadPaymentMethods();
      await methods.loadReferencedPaymentMethods([payment.paymentMethodId]);

      final otherActivePaidAmount = activePayments
          .where(
            (item) =>
                item.deletedAt == null &&
                item.id != null &&
                item.id != payment.id,
          )
          .fold<double>(0, (total, item) => total + item.amount);

      if (!mounted) return;
      setState(() {
        _payment = payment;
        _invoice = invoice;
        _paymentMethodId = payment.paymentMethodId;
        _date = DateUtils.dateOnly(payment.date.toLocal());
        _dateChanged = false;
        _otherActivePaidAmount = otherActivePaidAmount;
        _operationKey = null;
        _operationPayload = null;
        _amountController.text = payment.amount.round().toString();
        _referenceController.text = payment.reference ?? '';
        _notesController.text = payment.notes ?? '';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/purchases/payments/${widget.paymentId}');
    }
  }

  Future<void> _save() async {
    final payment = _payment;
    final invoice = _invoice;
    if (payment == null || invoice == null) return;
    if (!_formKey.currentState!.validate()) return;

    final amount = double.parse(_amountController.text);
    final date = _dateChanged ? _date! : payment.date;
    final methodId = _paymentMethodId!;
    final reference = _referenceController.text.trim();
    final notes = _notesController.text.trim();
    final reason = _reasonController.text.trim();

    final changed = amount.round() != payment.amount.round() ||
        methodId != payment.paymentMethodId ||
        (_dateChanged && !_sameDate(date, payment.date.toLocal())) ||
        reference != (payment.reference ?? '') ||
        notes != (payment.notes ?? '');
    if (!changed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay cambios para guardar.')),
      );
      return;
    }

    setState(() {
      _saving = true;
      _staleConflict = false;
      _error = null;
    });

    try {
      final operationPayload = [
        methodId,
        amount.round().toString(),
        date.toUtc().toIso8601String(),
        reference,
        notes,
        reason,
      ].join('\u001f');
      if (_operationKey == null || _operationPayload != operationPayload) {
        _operationKey = const Uuid().v4();
        _operationPayload = operationPayload;
      }
      final result =
          await context.read<PurchaseService>().correctPurchasePayment(
                current: payment,
                paymentMethodId: methodId,
                amount: amount,
                date: date,
                reference: reference.isEmpty ? null : reference,
                notes: notes.isEmpty ? null : notes,
                reason: reason,
                operationKey: _operationKey,
              );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.financialFieldsChanged
                ? 'Pago corregido y asiento de cuentas por pagar actualizado.'
                : 'Datos del pago actualizados sin alterar el asiento.',
          ),
          backgroundColor: const Color(0xFF047857),
        ),
      );
      context.go('/purchases/payments/${result.payment.id}');
    } catch (error) {
      if (!mounted) return;
      final staleConflict = _isStaleError(error);
      setState(() {
        _saving = false;
        _staleConflict = staleConflict;
        _error = _friendlyError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: _loading
          ? const Center(child: BrandedLoading())
          : _payment == null || _invoice == null
              ? _buildFailure()
              : _buildForm(_payment!, _invoice!),
    );
  }

  Widget _buildFailure() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              size: 52,
              color: Color(0xFFB91C1C),
            ),
            const SizedBox(height: 16),
            Text(
              _error ?? 'No se pudo cargar el pago a proveedor.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(PurchasePayment payment, PurchaseInvoice invoice) {
    final tenant = context.watch<TenantService>();
    final methods = context.watch<PaymentMethodService>();
    final canEditMetadata = _canEditMetadata(tenant);
    final canEditFinancial = _canEditFinancialFields(tenant);
    final availableMethods = _methodOptions(methods, payment);
    final maxAmount = _maximumCorrectedAmount(invoice);

    return Column(
      key: const ValueKey('purchase-payment-edit-form'),
      children: [
        _FormHeader(
          paymentNumber:
              PurchasePaymentReceiptPdfGenerator.paymentNumber(payment),
          onBack: _goBack,
          onSave: _saving || !canEditMetadata ? null : _save,
          saving: _saving,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Form(
                  key: _formKey,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final twoColumns = constraints.maxWidth >= 820;
                      final primary = _buildPrimaryFields(
                        payment,
                        availableMethods,
                        canEditMetadata,
                        canEditFinancial,
                        maxAmount,
                      );
                      final evidence = _buildEvidence(payment, invoice);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!canEditMetadata) ...[
                            const _PolicyNotice(
                              message:
                                  'Tu rol puede consultar este pago, pero no '
                                  'registrar correcciones. Solicita acceso de '
                                  'compras o contabilidad.',
                            ),
                            const SizedBox(height: 16),
                          ] else if (!canEditFinancial) ...[
                            const _PolicyNotice(
                              message:
                                  'Tu rol puede documentar referencia, notas y '
                                  'motivo, pero no modificar importe, fecha ni '
                                  'medio de pago. Una persona con responsabilidad '
                                  'contable debe autorizar esos cambios.',
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (_error != null) ...[
                            _ErrorNotice(message: _error!),
                            if (_staleConflict)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: _load,
                                  icon: const Icon(Icons.refresh, size: 17),
                                  label: const Text('Recargar pago'),
                                ),
                              ),
                            const SizedBox(height: 16),
                          ],
                          if (twoColumns)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 3, child: primary),
                                const SizedBox(width: 20),
                                Expanded(flex: 2, child: evidence),
                              ],
                            )
                          else ...[
                            primary,
                            const SizedBox(height: 20),
                            evidence,
                          ],
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPrimaryFields(
    PurchasePayment payment,
    List<PaymentMethod> methods,
    bool canEditMetadata,
    bool canEditFinancial,
    double maxAmount,
  ) {
    return _SectionCard(
      title: 'Corrección del pago a proveedor',
      subtitle: 'La factura, el proveedor y la identidad contable no cambian.',
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: _paymentMethodId,
            decoration: const InputDecoration(
              labelText: 'Medio de pago',
              prefixIcon: Icon(Icons.account_balance_wallet_outlined),
            ),
            items: methods
                .map(
                  (method) => DropdownMenuItem(
                    value: method.id,
                    enabled:
                        method.isActive || method.id == payment.paymentMethodId,
                    child: Text(
                      method.isActive
                          ? method.name
                          : '${method.name} (inactivo)',
                    ),
                  ),
                )
                .toList(),
            onChanged: canEditFinancial
                ? (value) => setState(() => _paymentMethodId = value)
                : null,
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final amountField = TextFormField(
                controller: _amountController,
                enabled: canEditFinancial,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Importe pagado',
                  prefixText: r'$ ',
                  helperText:
                      'Máximo permitido: ${ChileanUtils.formatCurrency(maxAmount)}',
                ),
                validator: (value) {
                  final amount = double.tryParse(value ?? '');
                  if (amount == null || amount <= 0) {
                    return 'Ingresa un importe válido.';
                  }
                  if (amount != amount.roundToDouble()) {
                    return 'El CLP no admite decimales.';
                  }
                  if (amount > maxAmount + 0.5) {
                    return 'El importe excede el saldo disponible.';
                  }
                  return null;
                },
              );
              final dateField = InkWell(
                onTap: canEditFinancial ? _pickDate : null,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Fecha de pago',
                    prefixIcon: const Icon(Icons.calendar_today_outlined),
                    enabled: canEditFinancial,
                  ),
                  child: Text(
                    _date == null
                        ? 'Seleccionar'
                        : ChileanUtils.formatDate(_date!),
                  ),
                ),
              );

              if (constraints.maxWidth < 560) {
                return Column(
                  children: [
                    amountField,
                    const SizedBox(height: 16),
                    dateField,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: amountField),
                  const SizedBox(width: 14),
                  Expanded(child: dateField),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _referenceController,
            enabled: canEditMetadata,
            maxLength: 160,
            decoration: const InputDecoration(
              labelText: 'Referencia externa',
              prefixIcon: Icon(Icons.tag_outlined),
              hintText: 'Transferencia, comprobante o folio bancario',
            ),
            validator: (value) {
              PaymentMethod? selected;
              for (final method in methods) {
                if (method.id == _paymentMethodId) {
                  selected = method;
                  break;
                }
              }
              if (selected?.requiresReference == true &&
                  (value?.trim().isEmpty ?? true)) {
                return 'Este medio de pago requiere una referencia.';
              }
              return null;
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _notesController,
            enabled: canEditMetadata,
            minLines: 3,
            maxLines: 5,
            maxLength: 1000,
            decoration: const InputDecoration(
              labelText: 'Notas internas',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
          const Divider(height: 32),
          TextFormField(
            controller: _reasonController,
            enabled: canEditMetadata,
            minLines: 2,
            maxLines: 4,
            maxLength: 500,
            decoration: const InputDecoration(
              labelText: 'Motivo de la corrección *',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.history_edu_outlined),
              helperText:
                  'Quedará guardado permanentemente en la trazabilidad.',
            ),
            validator: (value) {
              final reason = value?.trim() ?? '';
              if (reason.length < 8) {
                return 'Explica el motivo con al menos 8 caracteres.';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEvidence(
    PurchasePayment payment,
    PurchaseInvoice invoice,
  ) {
    final maxAmount = _maximumCorrectedAmount(invoice);
    return Column(
      children: [
        _SectionCard(
          title: 'Documento vinculado',
          subtitle: 'Identidad inmutable',
          child: Column(
            children: [
              _ReadOnlyRow('Factura ERP', invoice.invoiceNumber),
              if (invoice.supplierInvoiceNumber?.trim().isNotEmpty == true)
                _ReadOnlyRow(
                  'Documento proveedor',
                  invoice.supplierInvoiceNumber!.trim(),
                ),
              _ReadOnlyRow(
                'Proveedor',
                invoice.supplierName ?? 'Proveedor no identificado',
              ),
              if (invoice.supplierRut?.trim().isNotEmpty == true)
                _ReadOnlyRow(
                  'RUT',
                  ChileanUtils.formatRut(invoice.supplierRut),
                ),
              _ReadOnlyRow(
                'Otros pagos activos',
                ChileanUtils.formatCurrency(_otherActivePaidAmount),
              ),
              _ReadOnlyRow(
                'Disponible para corregir',
                ChileanUtils.formatCurrency(maxAmount),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _SectionCard(
          title: 'Límite contable',
          subtitle: 'Solo lectura · pertenece a la factura',
          child: Column(
            children: [
              _ReadOnlyRow(
                'Total factura',
                ChileanUtils.formatCurrency(invoice.total),
              ),
              _ReadOnlyRow(
                'Neto compra',
                ChileanUtils.formatCurrency(invoice.netAmount),
              ),
              _ReadOnlyRow(
                'IVA recuperable',
                ChileanUtils.formatCurrency(invoice.ivaAmount),
              ),
              const SizedBox(height: 8),
              const Text(
                'El pago liquida cuentas por pagar contra caja o banco. No '
                'vuelve a reconocer la compra, el IVA ni el inventario, y no '
                'altera la recepción física.',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'Fecha del pago a proveedor',
    );
    if (chosen != null && mounted) {
      setState(() {
        _date = chosen;
        _dateChanged = true;
      });
    }
  }

  List<PaymentMethod> _methodOptions(
    PaymentMethodService service,
    PurchasePayment payment,
  ) {
    final options = [...service.paymentMethods];
    final current = service.getPaymentMethodById(payment.paymentMethodId);
    if (current != null && !options.any((item) => item.id == current.id)) {
      options.insert(0, current);
    }
    return options;
  }

  bool _canEditFinancialFields(TenantService tenantService) {
    return tenantService.hasAnyRole(
          const ['admin', 'manager', 'accountant'],
        ) ||
        tenantService.hasPermission('access_accounting');
  }

  bool _canEditMetadata(TenantService tenantService) {
    return tenantService.hasAnyRole(
          const ['admin', 'manager', 'cashier', 'accountant'],
        ) ||
        tenantService.hasPermission('create_invoices') ||
        tenantService.hasPermission('access_accounting');
  }

  double _maximumCorrectedAmount(PurchaseInvoice invoice) {
    return (invoice.total - _otherActivePaidAmount)
        .clamp(0, invoice.total)
        .toDouble();
  }

  bool _sameDate(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  String _friendlyError(Object error) {
    final text = error.toString();
    if (_isStaleError(error)) {
      return 'Otra persona modificó este pago. Recarga antes de guardar.';
    }
    if (text.contains('PAYMENT_OVERPAYMENT') ||
        text.contains('PURCHASE_PAYMENT_OVERPAYMENT') ||
        text.toLowerCase().contains('overpayment')) {
      return 'El importe corregido supera el saldo disponible de la factura.';
    }
    if (text.contains('PAYMENT_FINANCIAL_ROLE_REQUIRED') ||
        text.contains('PURCHASE_PAYMENT_FINANCIAL_ROLE_REQUIRED') ||
        text.contains(
          'Financial purchase payment corrections require accounting '
          'authorization',
        )) {
      return 'Tu rol no autoriza cambios financieros en pagos a proveedor.';
    }
    return text.replaceFirst('Exception: ', '');
  }

  bool _isStaleError(Object error) {
    final text = error.toString();
    return text.contains('40001') ||
        text.contains('PAYMENT_STALE') ||
        text.contains('PURCHASE_PAYMENT_STALE') ||
        text.contains('modified after this form was loaded');
  }
}

class _FormHeader extends StatelessWidget {
  const _FormHeader({
    required this.paymentNumber,
    required this.onBack,
    required this.onSave,
    required this.saving,
  });

  final String paymentNumber;
  final VoidCallback onBack;
  final VoidCallback? onSave;
  final bool saving;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          IconButton(onPressed: onBack, icon: const Icon(Icons.arrow_back)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Editar pago a proveedor',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  paymentNumber,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: saving ? null : onBack,
            child: const Text('Cancelar'),
          ),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: onSave,
            icon: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined, size: 18),
            label: Text(saving ? 'Guardando…' : 'Guardar corrección'),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 20),
          child,
        ],
      ),
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicyNotice extends StatelessWidget {
  const _PolicyNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _Notice(
      icon: Icons.lock_outline,
      message: message,
      foreground: const Color(0xFF92400E),
      background: const Color(0xFFFFFBEB),
      border: const Color(0xFFFDE68A),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _Notice(
      icon: Icons.error_outline,
      message: message,
      foreground: const Color(0xFF991B1B),
      background: const Color(0xFFFEF2F2),
      border: const Color(0xFFFECACA),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.message,
    required this.foreground,
    required this.background,
    required this.border,
  });

  final IconData icon;
  final String message;
  final Color foreground;
  final Color background;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: foreground,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
