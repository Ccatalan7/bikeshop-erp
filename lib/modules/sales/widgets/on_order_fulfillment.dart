import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_button.dart';
import '../../../shared/widgets/vb_money_text.dart';
import '../../../shared/widgets/vb_notice.dart';
import '../../../shared/widgets/vb_segmented.dart' show VbDensity;
import '../../../shared/widgets/vb_status_badge.dart';
import '../models/customer_quote.dart';
import '../services/customer_quote_service.dart';

// Lo que llega del proveedor después del pago, con o sin cotización
// (20261103010000, 20261120210000): los pedidos a proveedores como
// borradores de Compras y «Anular y devolver». La cotización y Pedidos web
// muestran estas mismas piezas; ninguna pantalla las copia.

/// Lo que pide «Anular y devolver».
class OnOrderRefundInput {
  const OnOrderRefundInput({
    required this.operationKey,
    required this.reason,
    required this.reference,
    required this.refundedAt,
  });

  final String operationKey;
  final String reason;
  final String reference;
  final DateTime refundedAt;
}

/// Primero se devuelve la plata, después se anota: la base no devuelve nada
/// sola, registra lo que el equipo ya hizo. El diálogo es dueño de sus
/// controladores. Lo usan la cotización y Pedidos web (20261120210000).
class OnOrderCancelRefundDialog extends StatefulWidget {
  const OnOrderCancelRefundDialog({
    super.key,
    required this.order,
    required this.sentPurchases,
  });

  final CustomerQuoteOrder order;
  final int sentPurchases;

  @override
  State<OnOrderCancelRefundDialog> createState() =>
      _OnOrderCancelRefundDialogState();
}

class _OnOrderCancelRefundDialogState extends State<OnOrderCancelRefundDialog> {
  final _reason = TextEditingController();
  final _reference = TextEditingController();
  // Una llave por diálogo: un reintento tras un corte no registra dos veces.
  final _operationKey = CustomerQuoteService.newOperationKey();
  DateTime _refundedAt = DateTime.now();

  @override
  void dispose() {
    _reason.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final first =
        (widget.order.paidAt ?? now).subtract(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: _refundedAt,
      firstDate: first.isAfter(now) ? now : first,
      lastDate: now,
    );
    if (picked == null || !mounted) return;
    setState(() {
      final today = DateUtils.isSameDay(picked, now);
      _refundedAt =
          today ? now : DateTime(picked.year, picked.month, picked.day, 12);
    });
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final theme = Theme.of(context);
    final canConfirm =
        _reason.text.trim().length >= 4 && _reference.text.trim().length >= 2;
    final where = order.paymentMethod == 'mercadopago'
        ? 'en Mercado Pago, desde el pago del pedido («Devolver dinero»)'
        : 'por transferencia, desde el banco';
    return AlertDialog(
      title: Text('Anular y devolver ${order.number}'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Primero devuélvele ${VbMoneyText.formatClp(order.total)} al '
                'cliente $where. Después anota aquí la referencia: el pedido '
                'se anula, lo apartado vuelve al stock y el pedido al '
                'proveedor que no se envió se anula. Al cliente le llegan el '
                'aviso de anulación y el del reembolso.',
              ),
              if (widget.sentPurchases > 0) ...[
                const SizedBox(height: 12),
                VbNotice(
                  title: widget.sentPurchases == 1
                      ? 'El pedido al proveedor ya se envió'
                      : '${widget.sentPurchases} pedidos a proveedores ya se enviaron',
                  body: 'Avísale al proveedor que no lo mande.',
                  tone: VbNoticeTone.warning,
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('customer-quote-refund-reason'),
                controller: _reason,
                autofocus: true,
                maxLength: 500,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Motivo',
                  hintText: 'Por ejemplo: el proveedor no tiene la medida',
                ),
              ),
              TextField(
                key: const ValueKey('customer-quote-refund-reference'),
                controller: _reference,
                maxLength: 120,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Referencia de la devolución',
                  hintText: 'Número de la devolución o de la transferencia',
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Devuelto el ${DateFormat("d MMM yyyy", 'es').format(_refundedAt)}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  VbButton(
                    label: 'Cambiar fecha',
                    variant: VbButtonVariant.text,
                    density: VbDensity.compact,
                    onPressed: _pickDate,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        VbButton(
          label: 'Volver',
          variant: VbButtonVariant.text,
          onPressed: () => Navigator.of(context).pop(),
        ),
        VbButton(
          label: 'Anular y registrar la devolución',
          variant: VbButtonVariant.destructive,
          onPressed: canConfirm
              ? () => Navigator.of(context).pop(OnOrderRefundInput(
                    operationKey: _operationKey,
                    reason: _reason.text.trim(),
                    reference: _reference.text.trim(),
                    refundedAt: _refundedAt,
                  ))
              : null,
        ),
      ],
    );
  }
}

/// Los pedidos a proveedores que nacieron al pagar: borradores de Compras.
/// Se mandan desde el asistente de compras, que muestra el mensaje exacto, lo
/// manda por WhatsApp y recién entonces lo marca enviado.
class OnOrderSupplierOrders extends StatelessWidget {
  const OnOrderSupplierOrders({
    super.key,
    required this.order,
    required this.onOpen,
  });

  final CustomerQuoteOrder order;
  final ValueChanged<String> onOpen;

  String _assistant(String supplierId, [String? orderId]) => Uri(
        path: '/purchases/assistant',
        queryParameters: {
          'supplier': supplierId,
          if (orderId != null) 'order': orderId,
        },
      ).toString();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final faint =
        theme.textTheme.bodySmall?.copyWith(color: roles.faintForeground);
    final purchases = order.purchases;
    final missing = order.missingSupplier;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Title(purchases.length > 1
            ? 'Pedidos a ${purchases.length} proveedores'
            : 'Pedido al proveedor'),
        for (final purchase in purchases) ...[
          Builder(builder: (context) {
            final count = order.items
                .where((item) =>
                    item.onOrder && item.supplierId == purchase.supplierId)
                .fold<int>(0, (sum, item) => sum + item.quantity);
            final draft = purchase.isDraft;
            final document = purchase.purchaseInvoiceId;
            final others = purchase.orders - 1;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: draft
                    ? roles.warning.container.withValues(alpha: 0.35)
                    : theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: draft ? roles.warning.border : roles.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          purchase.supplierName ?? 'Proveedor',
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      VbStatusBadge(
                        label: document == null
                            ? 'Borrado en Compras'
                            : purchase.statusLabel,
                        tone: document == null
                            ? VbStatusTone.neutral
                            : purchase.tone,
                        dense: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (purchase.number != null) purchase.number!,
                      '${count == 1 ? '1 unidad' : '$count unidades'}'
                          '${others > 0 ? ' de esta venta' : ''}',
                      '${VbMoneyText.formatClp(purchase.total)} IVA incluido',
                    ].join(' · '),
                    style: faint?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                  // El pedido abierto del proveedor junta las ventas hasta
                  // que se envía (20261122010000).
                  if (others > 0)
                    Text(
                      others == 1
                          ? 'Va junto con otra venta: al proveedor le llega '
                              'un solo pedido.'
                          : 'Va junto con otras $others ventas: al proveedor '
                              'le llega un solo pedido.',
                      style: faint,
                    ),
                  if (purchase.sentAt != null)
                    Text(
                      'Enviado con su PDF el '
                      '${DateFormat("d MMM 'a las' HH:mm", 'es').format(purchase.sentAt!.toLocal())}',
                      style: faint,
                    ),
                  if (purchase.salesRepName != null ||
                      purchase.salesRepPhone != null)
                    Text(
                      [purchase.salesRepName, purchase.salesRepPhone]
                          .whereType<String>()
                          .join(' · '),
                      style: faint,
                    ),
                  if (purchase.supplierId != null) ...[
                    const SizedBox(height: 10),
                    if (document == null)
                      VbButton(
                        label: 'Armarlo en Compras',
                        icon: Icons.shopping_cart_outlined,
                        variant: VbButtonVariant.secondary,
                        density: VbDensity.compact,
                        onPressed: () =>
                            onOpen(_assistant(purchase.supplierId!)),
                      )
                    else if (draft)
                      VbButton(
                        label: 'Enviar al proveedor',
                        icon: Icons.send_outlined,
                        density: VbDensity.compact,
                        onPressed: () =>
                            onOpen(_assistant(purchase.supplierId!, document)),
                      )
                    else
                      VbButton(
                        label: 'Ver en Compras',
                        icon: Icons.open_in_new,
                        variant: VbButtonVariant.secondary,
                        density: VbDensity.compact,
                        onPressed: () => onOpen('/purchases/$document'),
                      ),
                  ],
                ],
              ),
            );
          }),
        ],
        if (order.isPaid && missing > 0)
          VbNotice(
            title: missing == 1
                ? 'Un producto a pedido no tiene proveedor'
                : '$missing productos a pedido no tienen proveedor',
            body: 'Pídelo en Compras con el asistente; cuando entre al stock, '
                'el pedido lo aparta solo.',
            tone: VbNoticeTone.warning,
            action: VbButton(
              label: 'Abrir Compras',
              variant: VbButtonVariant.secondary,
              density: VbDensity.compact,
              onPressed: () => onOpen('/purchases/assistant'),
            ),
          ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
