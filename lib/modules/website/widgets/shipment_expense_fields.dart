import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../models/online_order_shipment.dart';
import '../services/online_order_shipment_service.dart';

/// What the carrier charged, as the expense it becomes (owner, 2026-10-13:
/// «dejar el gasto registrado automáticamente, para no tener que agregarlo
/// de nuevo en los gastos rápidos»): to whom and on which line it lands, how
/// it was paid and whether it is a boleta or a factura. The database decides
/// the supplier and the account; the person confirms the payment and the
/// document. With [onInclude] it carries the switch that turns it on.
class ShipmentExpenseFields extends StatelessWidget {
  const ShipmentExpenseFields({
    super.key,
    required this.amount,
    required this.options,
    required this.paymentMethodId,
    required this.documentType,
    required this.documentNumber,
    required this.onPaymentMethod,
    required this.onDocumentType,
    this.include = true,
    this.onInclude,
    this.loading = false,
    this.error,
    this.compact = false,
  });

  /// What the carrier charged, in pesos; null or zero while it is unknown.
  final double? amount;
  final ShipmentExpenseOptions? options;
  final String? paymentMethodId;

  /// «receipt» (boleta) or «invoice» (factura).
  final String documentType;
  final TextEditingController documentNumber;
  final ValueChanged<String> onPaymentMethod;
  final ValueChanged<String> onDocumentType;
  final bool include;
  final ValueChanged<bool>? onInclude;
  final bool loading;
  final String? error;

  /// One column, for a phone.
  final bool compact;

  bool get _hasAmount => (amount ?? 0) > 0;

  /// Why the expense cannot be registered now, in the operator's words.
  String? get unavailableReason {
    if (loading) return null;
    if (error != null) return error;
    if (!_hasAmount) {
      return 'Escribe lo pagado al transportista para registrarlo como gasto.';
    }
    final plan = options;
    if (plan == null) return null;
    if (plan.accountId == null) {
      return 'No hay una cuenta de gastos de transporte: regístralo en Gastos.';
    }
    if (plan.paymentMethods.isEmpty) {
      return 'No hay medios de pago para gastos: regístralo en Gastos.';
    }
    return null;
  }

  bool get available =>
      !loading && options != null && unavailableReason == null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final reason = unavailableReason;
    final on = include && available;
    final plan = options;
    final where = [
      if (plan?.supplierName.isNotEmpty == true) plan!.supplierName,
      if (plan?.accountLabel.isNotEmpty == true) plan!.accountLabel,
    ].join(' · ');
    final total = (amount ?? 0).roundToDouble();
    final net = (total / 1.19).roundToDouble();

    final heading = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (onInclude != null) ...[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Switch(
              key: const ValueKey('shipment-expense-switch'),
              value: on,
              onChanged: available ? onInclude : null,
            ),
          ),
          const SizedBox(width: 10),
        ] else ...[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.receipt_long_outlined, color: muted, size: 22),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                onInclude != null
                    ? 'Registrar el gasto del envío'
                    : 'Gasto del envío',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                loading
                    ? 'Buscando la cuenta del transportista…'
                    : reason ??
                        (on || onInclude == null
                            ? where
                            : 'Lo registras después en Gastos rápidos.'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: reason != null && error != null
                      ? roles.danger.onContainer
                      : muted,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        if (_hasAmount) ...[
          const SizedBox(width: 12),
          Text(
            ChileanUtils.formatCurrency(total),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: on ? theme.colorScheme.onSurface : muted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ],
    );

    final method = DropdownMenu<String>(
      key: ValueKey('shipment-expense-method-${plan?.paymentMethods.length}'),
      initialSelection: paymentMethodId,
      expandedInsets: EdgeInsets.zero,
      label: const Text('Pagado con'),
      leadingIcon: const Icon(Icons.account_balance_wallet_outlined),
      onSelected: (id) {
        if (id != null) onPaymentMethod(id);
      },
      dropdownMenuEntries: [
        for (final option in plan?.paymentMethods ?? const [])
          DropdownMenuEntry(value: option.id, label: option.name),
      ],
    );

    final document = SegmentedButton<String>(
      key: const ValueKey('shipment-expense-document'),
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: 'receipt',
          label: Text('Boleta', key: ValueKey('shipment-expense-receipt')),
        ),
        ButtonSegment(
          value: 'invoice',
          label: Text('Factura', key: ValueKey('shipment-expense-invoice')),
        ),
      ],
      selected: {documentType},
      onSelectionChanged: (selection) => onDocumentType(selection.first),
    );

    final number = TextField(
      key: const ValueKey('shipment-expense-number'),
      controller: documentNumber,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]')),
        LengthLimitingTextInputFormatter(40),
      ],
      decoration: InputDecoration(
        labelText: documentType == 'invoice' ? 'N° de factura' : 'N° de boleta',
        prefixIcon: const Icon(Icons.tag_rounded),
      ),
    );

    final taxNote = Text(
      documentType == 'invoice'
          ? 'Factura: neto ${ChileanUtils.formatCurrency(net)} e IVA crédito '
              '${ChileanUtils.formatCurrency(total - net)}.'
          : 'Boleta: todo el monto es gasto, sin IVA crédito.',
      style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.35),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: on
            ? theme.colorScheme.surfaceContainerLow
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: roles.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          heading,
          if (on) ...[
            const SizedBox(height: 14),
            if (compact) ...[
              method,
              const SizedBox(height: 12),
              document,
              const SizedBox(height: 12),
              number,
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: method),
                  const SizedBox(width: 12),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: document,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              number,
            ],
            const SizedBox(height: 8),
            taxNote,
          ],
        ],
      ),
    );
  }
}

/// The expense of a shipment registered without one (with a version that
/// did not offer it, or with the switch off): the same fields, one button.
Future<OnlineOrderShipment?> showShipmentExpenseDialog(
  BuildContext context, {
  required OnlineOrderShipment shipment,
  required OnlineOrderShipmentReader service,
}) {
  final phone = MediaQuery.sizeOf(context).width < 600;
  return showDialog<OnlineOrderShipment>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ShipmentExpenseDialog(
      shipment: shipment,
      service: service,
      phone: phone,
    ),
  );
}

class _ShipmentExpenseDialog extends StatefulWidget {
  const _ShipmentExpenseDialog({
    required this.shipment,
    required this.service,
    required this.phone,
  });

  final OnlineOrderShipment shipment;
  final OnlineOrderShipmentReader service;
  final bool phone;

  @override
  State<_ShipmentExpenseDialog> createState() => _ShipmentExpenseDialogState();
}

class _ShipmentExpenseDialogState extends State<_ShipmentExpenseDialog> {
  final _documentNumber = TextEditingController();
  ShipmentExpenseOptions? _options;
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String? _error;
  String? _paymentMethodId;
  String _documentType = 'receipt';

  @override
  void initState() {
    super.initState();
    // What the AI read on the receipt when the shipment was registered.
    final readType = widget.shipment.documentType;
    if (readType != null) _documentType = readType;
    _documentNumber.text = widget.shipment.documentNumber ?? '';
    _load(readType == null);
  }

  @override
  void dispose() {
    _documentNumber.dispose();
    super.dispose();
  }

  Future<void> _load(bool takeDocumentType) async {
    try {
      final options = await widget.service.expenseOptions(
        widget.shipment.carrier,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _options = options;
        _paymentMethodId =
            options.paymentMethodId ?? options.paymentMethods.firstOrNull?.id;
        if (takeDocumentType) _documentType = options.documentType;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'No se pudo preparar el gasto: $error';
      });
    }
  }

  Future<void> _save() async {
    final methodId = _paymentMethodId;
    if (methodId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final shipment = await widget.service.recordExpense(
        shipmentId: widget.shipment.id,
        expense: ShipmentExpenseDraft(
          paymentMethodId: methodId,
          documentType: _documentType,
          documentNumber: _documentNumber.text,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(shipment);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is PostgrestException ? error.message : '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final fields = ShipmentExpenseFields(
      amount: widget.shipment.cost,
      options: _options,
      loading: _loading,
      error: _loadError,
      paymentMethodId: _paymentMethodId,
      documentType: _documentType,
      documentNumber: _documentNumber,
      onPaymentMethod: (id) => setState(() => _paymentMethodId = id),
      onDocumentType: (type) => setState(() => _documentType = type),
      compact: widget.phone,
    );
    final canSave = !_saving && fields.available && _paymentMethodId != null;
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: widget.phone ? 16 : 40,
        vertical: 24,
      ),
      title: const Text('Registrar el gasto del envío'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: roles.danger.container,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: roles.danger.border),
                  ),
                  child: Text(
                    _error!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: roles.danger.onContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              fields,
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          key: const ValueKey('shipment-expense-save'),
          onPressed: canSave ? _save : null,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              : const Icon(Icons.receipt_long_rounded, size: 20),
          label: const Text('Registrar gasto'),
        ),
      ],
    );
  }
}
