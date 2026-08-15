import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../shared/models/payment_method.dart';
import '../../../shared/services/payment_method_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../../../shared/widgets/main_layout.dart';
import '../models/sales_models.dart';
import '../services/sales_service.dart';
import '../utils/payment_edit_policy.dart';

class PaymentEditPage extends StatefulWidget {
  const PaymentEditPage({super.key, required this.paymentId});

  final String paymentId;

  @override
  State<PaymentEditPage> createState() => _PaymentEditPageState();
}

class _PaymentEditPageState extends State<PaymentEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();
  final _reasonController = TextEditingController();

  Payment? _payment;
  Invoice? _invoice;
  DateTime? _date;
  bool _dateChanged = false;
  String? _paymentMethodId;
  bool _loading = true;
  bool _saving = false;
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
      _error = null;
    });
    try {
      final sales = context.read<SalesService>();
      final methods = context.read<PaymentMethodService>();
      final payment = await sales.fetchPayment(widget.paymentId, refresh: true);
      if (payment == null) {
        throw StateError('El pago no existe o ya no está activo.');
      }
      final invoice =
          await sales.fetchInvoice(payment.invoiceId, refresh: true);
      if (invoice == null) {
        throw StateError('No se encontró la factura vinculada al pago.');
      }
      await methods.loadPaymentMethods();
      await methods.loadReferencedPaymentMethods([payment.paymentMethodId]);
      if (!mounted) return;
      setState(() {
        _payment = payment;
        _invoice = invoice;
        _paymentMethodId = payment.paymentMethodId;
        _date = DateUtils.dateOnly(payment.date.toLocal());
        _dateChanged = false;
        _amountController.text = payment.amount.round().toString();
        _referenceController.text = payment.reference ?? '';
        _notesController.text = payment.notes ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Bad state: ', '');
      });
    }
  }

  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/sales/payments/${widget.paymentId}');
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
      _error = null;
    });
    try {
      final result = await context.read<SalesService>().correctSalesPayment(
            current: payment,
            paymentMethodId: methodId,
            amount: amount,
            date: date,
            reference: reference,
            notes: notes,
            reason: _reasonController.text,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.financialFieldsChanged
                ? 'Pago corregido y asiento contable actualizado.'
                : 'Datos del pago actualizados sin alterar el asiento.',
          ),
          backgroundColor: const Color(0xFF047857),
        ),
      );
      context.go('/sales/payments/${result.payment.id}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _friendlyError(e);
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
            const Icon(Icons.error_outline, size: 52, color: Color(0xFFB91C1C)),
            const SizedBox(height: 16),
            Text(
              _error ?? 'No se pudo cargar el pago.',
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

  Widget _buildForm(Payment payment, Invoice invoice) {
    final tenant = context.watch<TenantService>();
    final methods = context.watch<PaymentMethodService>();
    final canEditFinancial =
        SalesPaymentEditPolicy.canEditFinancialFields(invoice, tenant);
    final canEditReference = SalesPaymentEditPolicy.canEditReference(invoice);
    final availableMethods = _methodOptions(methods, payment);
    final maxAmount = _maximumCorrectedAmount(invoice, payment);

    return Column(
      children: [
        _FormHeader(
          paymentNumber: _paymentNumber(payment),
          onBack: _goBack,
          onSave: _saving ? null : _save,
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
                        invoice,
                        availableMethods,
                        canEditFinancial,
                        canEditReference,
                        maxAmount,
                      );
                      final evidence = _buildEvidence(payment, invoice);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!canEditFinancial) ...[
                            _PolicyNotice(
                              message: SalesPaymentEditPolicy.lockedMessage(
                                invoice,
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (_error != null) ...[
                            _ErrorNotice(message: _error!),
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
    Payment payment,
    Invoice invoice,
    List<PaymentMethod> methods,
    bool canEditFinancial,
    bool canEditReference,
    double maxAmount,
  ) {
    return _SectionCard(
      title: 'Corrección del pago',
      subtitle:
          'La factura vinculada y la clasificación tributaria no cambian.',
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            initialValue: _paymentMethodId,
            decoration: const InputDecoration(
              labelText: 'Método de pago',
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _amountController,
                  enabled: canEditFinancial,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Importe recibido',
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
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: InkWell(
                  onTap: canEditFinancial ? _pickDate : null,
                  borderRadius: BorderRadius.circular(8),
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Fecha de recepción',
                      prefixIcon: const Icon(Icons.calendar_today_outlined),
                      enabled: canEditFinancial,
                    ),
                    child: Text(
                      _date == null
                          ? 'Seleccionar'
                          : ChileanUtils.formatDate(_date!),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _referenceController,
            enabled: canEditReference,
            maxLength: 160,
            decoration: const InputDecoration(
              labelText: 'Referencia externa',
              prefixIcon: Icon(Icons.tag_outlined),
              hintText: 'Transferencia, voucher o folio bancario',
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _notesController,
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

  Widget _buildEvidence(Payment payment, Invoice invoice) {
    final balanceWithoutCurrent =
        (invoice.total - (invoice.paidAmount - payment.amount))
            .clamp(0, invoice.total);
    return Column(
      children: [
        _SectionCard(
          title: 'Documento vinculado',
          subtitle: 'Identidad inmutable',
          child: Column(
            children: [
              _ReadOnlyRow('Factura', invoice.invoiceNumber),
              _ReadOnlyRow('Cliente', invoice.customerName ?? 'Sin cliente'),
              if (invoice.customerRut?.trim().isNotEmpty == true)
                _ReadOnlyRow(
                    'RUT', ChileanUtils.formatRut(invoice.customerRut)),
              _ReadOnlyRow(
                'Origen',
                SalesPaymentEditPolicy.sourceLabel(invoice),
              ),
              _ReadOnlyRow(
                'Disponible para corregir',
                ChileanUtils.formatCurrency(balanceWithoutCurrent.toDouble()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _SectionCard(
          title: 'Espejo tributario',
          subtitle: 'Solo lectura · pertenece a la factura',
          child: Column(
            children: [
              _ReadOnlyRow(
                  'Tratamiento', _taxTreatmentLabel(payment.taxTreatment)),
              _ReadOnlyRow(
                  'Neto', ChileanUtils.formatCurrency(payment.netAmount)),
              _ReadOnlyRow(
                  'IVA', ChileanUtils.formatCurrency(payment.ivaAmount)),
              const SizedBox(height: 8),
              const Text(
                'El pago liquida cuentas por cobrar. No vuelve a reconocer '
                'ingresos, IVA, inventario ni costo de venta.',
                style: TextStyle(
                    fontSize: 12, color: Color(0xFF64748B), height: 1.4),
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
      helpText: 'Fecha de recepción del pago',
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
    Payment payment,
  ) {
    final options = [...service.incomingPaymentMethods];
    final current = service.getPaymentMethodById(payment.paymentMethodId);
    if (current != null && !options.any((item) => item.id == current.id)) {
      options.insert(0, current);
    }
    return options;
  }

  double _maximumCorrectedAmount(Invoice invoice, Payment payment) {
    final paidByOthers =
        (invoice.paidAmount - payment.amount).clamp(0, invoice.total);
    return (invoice.total - paidByOthers).clamp(0, invoice.total).toDouble();
  }

  bool _sameDate(DateTime left, DateTime right) =>
      left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('PAYMENT_STALE') ||
        text.contains('modified after this form was loaded')) {
      return 'Otra persona modificó este pago. Recarga antes de guardar.';
    }
    if (text.contains('PAYMENT_SOURCE_MANAGED') ||
        text.contains('notes-only')) {
      return 'Este cobro debe corregirse desde su flujo de origen.';
    }
    if (text.contains('PAYMENT_OVERPAYMENT') ||
        text.toLowerCase().contains('overpayment')) {
      return 'El importe corregido supera el saldo disponible de la factura.';
    }
    return text.replaceFirst('Exception: ', '');
  }

  String _paymentNumber(Payment payment) {
    final compact = (payment.id ?? '').replaceAll('-', '').toUpperCase();
    final suffix = compact.length <= 6
        ? compact.padLeft(6, '0')
        : compact.substring(compact.length - 6);
    return 'COB-$suffix';
  }

  String _taxTreatmentLabel(String treatment) {
    switch (treatment) {
      case 'tax_included':
        return 'IVA incluido';
      case 'tax_excluded':
        return 'IVA agregado';
      default:
        return 'Sin IVA';
    }
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
                Text('Editar pago',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                Text(paymentNumber,
                    style: const TextStyle(
                        color: Color(0xFF64748B), fontSize: 12)),
              ],
            ),
          ),
          OutlinedButton(
              onPressed: saving ? null : onBack, child: const Text('Cancelar')),
          const SizedBox(width: 10),
          FilledButton.icon(
            onPressed: onSave,
            icon: saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
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
          Text(title,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A))),
          const SizedBox(height: 3),
          Text(subtitle,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
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
              width: 116,
              child: Text(label,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xFF64748B)))),
          Expanded(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1E293B)))),
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
          borderRadius: BorderRadius.circular(7)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 10),
          Expanded(
              child: Text(message,
                  style: TextStyle(
                      color: foreground, fontSize: 12.5, height: 1.35))),
        ],
      ),
    );
  }
}
