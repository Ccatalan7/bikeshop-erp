import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:intl/intl.dart';

import '../../../shared/services/image_service.dart';
import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/utils/shop_time.dart';
import '../models/online_order_workflow_policy.dart';
import '../models/website_models.dart';

/// One action of the order's bottom bar.
class OnlineOrderSheetAction {
  const OnlineOrderSheetAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Future<void> Function() onPressed;
}

/// The payment method as the shop names it, or null when the order has none.
String? onlineOrderPaymentMethodLabel(String? paymentMethod) {
  return switch ((paymentMethod ?? '').trim().toLowerCase()) {
    '' => null,
    'mercadopago' || 'mercado_pago' => 'Mercado Pago',
    'transfer' || 'bank_transfer' || 'transferencia' => 'Transferencia',
    final other => other,
  };
}

/// An online order, read the way the shop works it (dueño, 2026-10-13, chose
/// «B» in the Claude Design canvas): a navy band answers how much and where
/// the order stands — the total, the payment, the delivery and four steps —
/// and a sheet below it carries what to pick and who gets it, then the
/// payment and the evidence. The bar at the bottom holds the next step and
/// the two ways to reach the customer, so the operator never scrolls to act.
///
/// The band keeps the chrome's own colors in light and dark ([VinabikeShellRoles]);
/// the sheet follows the page theme.
class OnlineOrderSheet extends StatefulWidget {
  const OnlineOrderSheet({
    super.key,
    required this.order,
    required this.phone,
    required this.onClose,
    required this.evidence,
    this.topInset = 0,
    this.bottomInset = 0,
    this.moreActions,
    this.primaryAction,
    this.waitingLabel,
    this.onWhatsApp,
    this.onCall,
    this.onOpenMap,
    this.onOpenSale,
    this.onShippingLabel,
  });

  final OnlineOrder order;
  final bool phone;
  final VoidCallback onClose;
  final Widget evidence;
  final double topInset;
  final double bottomInset;

  /// The order's «⋯» menu, already colored for the band.
  final Widget? moreActions;

  /// The next step of the order, or null when there is none to take.
  final OnlineOrderSheetAction? primaryAction;

  /// What the order waits for when there is no step for the shop to take.
  final String? waitingLabel;
  final VoidCallback? onWhatsApp;
  final VoidCallback? onCall;
  final VoidCallback? onOpenMap;
  final VoidCallback? onOpenSale;

  /// The printable shipping label, for an order that goes by courier.
  final VoidCallback? onShippingLabel;

  @override
  State<OnlineOrderSheet> createState() => _OnlineOrderSheetState();
}

class _OnlineOrderSheetState extends State<OnlineOrderSheet> {
  bool _busy = false;

  Future<void> _run(OnlineOrderSheetAction action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action.onPressed();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final order = widget.order;
    final gutter = widget.phone ? 20.0 : 32.0;

    // The navy is painted once, by the order itself: the bar and the band are
    // what shows of it above the sheet, not boxes of their own. Two navy boxes
    // stacked met on a fractional pixel at the 80 % zoom and let the white
    // under them through as a hairline (2026-10-13). The white is painted
    // once too: one decorated group holds the sheet and the rest of the
    // screen below it, so a short order never shows navy under its sheet.
    return ColoredBox(
      color: roles.shell.canvas,
      child: Column(
        children: [
          _BandTopBar(
            order: order,
            phone: widget.phone,
            topInset: widget.topInset,
            gutter: gutter,
            onClose: widget.onClose,
            moreActions: widget.moreActions,
          ),
          Expanded(
            child: CustomScrollView(
              // A bounce at the top would pull the band away from the bar.
              physics: const ClampingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _BandSummary(
                    order: order,
                    phone: widget.phone,
                    gutter: gutter,
                  ),
                ),
                DecoratedSliver(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  sliver: SliverMainAxisGroup(
                    slivers: [
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(gutter, 22, gutter, 30),
                        sliver: SliverToBoxAdapter(
                          child: _SheetBody(
                            order: order,
                            roles: roles,
                            onOpenMap: widget.onOpenMap,
                            onOpenSale: widget.onOpenSale,
                            onShippingLabel: widget.onShippingLabel,
                            evidence: widget.evidence,
                          ),
                        ),
                      ),
                      // The empty child keeps the rest at zero once the
                      // order is longer than the screen: without one the
                      // remaining extent goes negative and the layout asserts.
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _ActionBar(
            phone: widget.phone,
            bottomInset: widget.bottomInset,
            busy: _busy,
            primaryAction: widget.primaryAction,
            waitingLabel: widget.waitingLabel,
            onRun: _run,
            onWhatsApp: widget.onWhatsApp,
            onCall: widget.onCall,
            onOpenSale: widget.onOpenSale,
          ),
        ],
      ),
    );
  }
}

class _BandTopBar extends StatelessWidget {
  const _BandTopBar({
    required this.order,
    required this.phone,
    required this.topInset,
    required this.gutter,
    required this.onClose,
    required this.moreActions,
  });

  final OnlineOrder order;
  final bool phone;
  final double topInset;
  final double gutter;
  final VoidCallback onClose;
  final Widget? moreActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shell = VinabikeThemeRoles.of(context).shell;
    final created = DateFormat("d MMM, HH:mm", 'es')
        .format(shopTime(order.createdAt))
        .replaceAll('.', '');
    final close = IconButton(
      onPressed: onClose,
      tooltip: phone ? 'Volver a pedidos' : 'Cerrar',
      color: shell.foreground,
      icon: Icon(phone ? Icons.arrow_back_rounded : Icons.close_rounded),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        phone ? 4 : gutter - 8,
        topInset + (phone ? 4 : 10),
        phone ? 4 : 12,
        phone ? 0 : 2,
      ),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            if (phone) close else const SizedBox(width: 8),
            const SizedBox(width: 4),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: order.orderNumber,
                      style: TextStyle(
                        color: shell.foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextSpan(
                      text: ' · $created',
                      style: TextStyle(color: shell.mutedForeground),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (moreActions != null) moreActions!,
            if (!phone) close,
          ],
        ),
      ),
    );
  }
}

class _BandSummary extends StatelessWidget {
  const _BandSummary({
    required this.order,
    required this.phone,
    required this.gutter,
  });

  final OnlineOrder order;
  final bool phone;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shell = VinabikeThemeRoles.of(context).shell;
    final steps = OnlineOrderWorkflowPolicy.progressSteps(
      status: order.status,
      deliveryType: order.deliveryType,
      paymentStatus: order.operationalPaymentStatus,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(gutter, 2, gutter, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ChileanUtils.formatCurrency(order.total),
            style: theme.textTheme.displaySmall?.copyWith(
              color: shell.foreground,
              fontSize: phone ? 40 : 44,
              fontWeight: FontWeight.w700,
              height: 1.05,
              letterSpacing: -0.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _pills(shell),
          ),
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 20),
            _Progress(steps: steps),
          ],
        ],
      ),
    );
  }

  List<Widget> _pills(VinabikeShellRoles shell) {
    final method = onlineOrderPaymentMethodLabel(order.paymentMethod);
    String withMethod(String label) =>
        method == null ? label : '$label · $method';
    final pickup = order.deliveryType.toLowerCase() == 'pickup';
    return [
      if (order.isTest)
        _BandPill(
          icon: Icons.science_outlined,
          label: 'Pedido de prueba',
          foreground: shell.mutedForeground,
          background: shell.raised,
        ),
      if (order.isCancelled)
        _BandPill(
          icon: Icons.block_rounded,
          label: 'Pedido cancelado',
          foreground: shell.attention,
          background: shell.raised,
        ),
      switch (order.operationalPaymentStatus) {
        'paid' => _BandPill(
            icon: Icons.check_rounded,
            label: withMethod('Pagado'),
            foreground: shell.positive,
            background: shell.positiveContainer,
          ),
        'refunded' => _BandPill(
            icon: Icons.undo_rounded,
            label: withMethod('Reembolsado'),
            foreground: shell.foreground,
            background: shell.raised,
          ),
        'failed' => _BandPill(
            icon: Icons.close_rounded,
            label: withMethod('Pago rechazado'),
            foreground: shell.attention,
            background: shell.raised,
          ),
        _ => _BandPill(
            icon: Icons.schedule_rounded,
            label: withMethod('Pago pendiente'),
            foreground: shell.dirty,
            background: shell.raised,
          ),
      },
      _BandPill(
        icon:
            pickup ? Icons.storefront_outlined : Icons.local_shipping_outlined,
        // Short, so it shares the line with the payment on a phone.
        label: pickup ? 'Retiro en tienda' : 'Despacho',
        foreground: shell.foreground,
        background: shell.raised,
      ),
    ];
  }
}

class _BandPill extends StatelessWidget {
  const _BandPill({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: foreground),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.steps});

  final List<OnlineOrderProgressStep> steps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shell = VinabikeThemeRoles.of(context).shell;
    final spoken = steps
        .map((step) => switch (step.state) {
              OnlineOrderProgressState.done => '${step.label}, hecho',
              OnlineOrderProgressState.current => '${step.label}, ahora',
              OnlineOrderProgressState.upcoming => '${step.label}, después',
            })
        .join('; ');
    return Semantics(
      label: 'Avance del pedido: $spoken',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < steps.length; index++) ...[
            if (index > 0) const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: switch (steps[index].state) {
                        OnlineOrderProgressState.done => shell.positive,
                        OnlineOrderProgressState.current => shell.accent,
                        OnlineOrderProgressState.upcoming => shell.edge,
                      },
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    steps[index].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: switch (steps[index].state) {
                        OnlineOrderProgressState.done => shell.positive,
                        OnlineOrderProgressState.current => shell.foreground,
                        OnlineOrderProgressState.upcoming =>
                          shell.mutedForeground,
                      },
                      fontWeight: switch (steps[index].state) {
                        OnlineOrderProgressState.current => FontWeight.w700,
                        OnlineOrderProgressState.done => FontWeight.w600,
                        OnlineOrderProgressState.upcoming => FontWeight.w500,
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A section's name in small capitals: the sections read as one sheet, not
/// as cards (shared with the order's evidence).
class OnlineOrderSectionLabel extends StatelessWidget {
  const OnlineOrderSectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.7,
    );
    return Row(
      children: [
        Expanded(child: Text(text.toUpperCase(), style: style)),
        if (trailing != null)
          Text(
            trailing!,
            style: style?.copyWith(
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
      ],
    );
  }
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({
    required this.order,
    required this.roles,
    required this.onOpenMap,
    required this.onOpenSale,
    required this.onShippingLabel,
    required this.evidence,
  });

  final OnlineOrder order;
  final VinabikeThemeRoles roles;
  final VoidCallback? onOpenMap;
  final VoidCallback? onOpenSale;
  final VoidCallback? onShippingLabel;
  final Widget evidence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final pickup = order.deliveryType.toLowerCase() == 'pickup';
    final divider = Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Divider(height: 1, color: roles.hairline),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (order.hasPaymentProcessingAttention) ...[
          _AttentionNote(order: order, roles: roles),
          const SizedBox(height: 22),
        ],
        OnlineOrderSectionLabel(
          'Productos',
          trailing: order.items.length > 1 ? '${order.items.length}' : null,
        ),
        const SizedBox(height: 14),
        for (var index = 0; index < order.items.length; index++) ...[
          if (index > 0) const SizedBox(height: 14),
          _ItemRow(
            item: order.items[index],
            sold: order.salesInvoiceId != null,
            roles: roles,
          ),
        ],
        if (!pickup && order.shippingCost > 0) ...[
          const SizedBox(height: 12),
          _AmountLine(
            icon: Icons.local_shipping_outlined,
            label: 'Despacho a domicilio',
            amount: ChileanUtils.formatCurrency(order.shippingCost),
          ),
        ],
        if (order.discountAmount > 0) ...[
          const SizedBox(height: 8),
          _AmountLine(
            icon: Icons.sell_outlined,
            label: 'Descuento',
            amount: '−${ChileanUtils.formatCurrency(order.discountAmount)}',
          ),
        ],
        divider,
        OnlineOrderSectionLabel(pickup ? 'Retira en tienda' : 'Entregar a'),
        const SizedBox(height: 14),
        _CustomerRow(order: order, roles: roles),
        const SizedBox(height: 14),
        _DeliveryRow(
          order: order,
          pickup: pickup,
          roles: roles,
          onOpenMap: onOpenMap,
        ),
        if (order.customerNotes?.trim().isNotEmpty == true) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: roles.warning.container,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Nota: ',
                    style: TextStyle(
                      color: roles.warning.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextSpan(text: order.customerNotes!.trim()),
                ],
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: roles.warning.onContainer,
                height: 1.4,
              ),
            ),
          ),
        ],
        if (onShippingLabel != null) ...[
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onShippingLabel,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.print_outlined, size: 19),
              label: const Text('Etiqueta de despacho'),
            ),
          ),
        ],
        divider,
        const OnlineOrderSectionLabel('Pago y venta'),
        const SizedBox(height: 10),
        ..._paymentFacts(theme, muted),
        divider,
        evidence,
      ],
    );
  }

  List<Widget> _paymentFacts(ThemeData theme, Color muted) {
    final method = onlineOrderPaymentMethodLabel(order.paymentMethod);
    final paid = order.operationalPaymentStatus == 'paid';
    final hasSale = order.salesInvoiceId != null;
    final carrier = order.shippingCarrier?.trim() ?? '';
    final tracking = order.trackingNumber?.trim() ?? '';
    final reference = order.paymentReference?.trim() ?? '';
    return [
      if (method != null) _FactRow(label: 'Medio de pago', value: Text(method)),
      if (order.paidAt != null)
        _FactRow(
          label: 'Pagado el',
          value: Text(ChileanUtils.formatDateTime(shopTime(order.paidAt!))),
        ),
      if (reference.isNotEmpty)
        _FactRow(label: 'Referencia', value: SelectableText(reference)),
      if (order.refundAmount > 0)
        _FactRow(
          label: 'Reembolsado',
          value: Text(ChileanUtils.formatCurrency(order.refundAmount)),
        ),
      _FactRow(
        label: 'Venta ERP',
        value: hasSale && onOpenSale != null
            ? Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onOpenSale,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: const Text('Abrir venta'),
                ),
              )
            : Text(
                hasSale
                    ? 'Creada'
                    : paid || order.hasPaymentProcessingAttention
                        ? 'Falta crearla'
                        : 'Se crea al confirmar el pago',
                style: TextStyle(
                  color:
                      !hasSale && (paid || order.hasPaymentProcessingAttention)
                          ? roles.warning.accent
                          : muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
      if (carrier.isNotEmpty)
        _FactRow(label: 'Transportista', value: Text(carrier)),
      if (tracking.isNotEmpty)
        _FactRow(label: 'Seguimiento', value: SelectableText(tracking)),
    ];
  }
}

class _AttentionNote extends StatelessWidget {
  const _AttentionNote({required this.order, required this.roles});

  final OnlineOrder order;
  final VinabikeThemeRoles roles;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 14, 11),
      decoration: BoxDecoration(
        color: roles.warning.container,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 19,
            color: roles.warning.accent,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              order.paymentProcessingRequiresRefundReview
                  ? 'El cobro requiere conciliación o reembolso antes de continuar.'
                  : 'El pago está confirmado; falta completar la venta ERP, el stock o la contabilidad.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: roles.warning.onContainer,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.sold,
    required this.roles,
  });

  final OnlineOrderItem item;
  final bool sold;
  final VinabikeThemeRoles roles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final sku = item.productSku?.trim() ?? '';
    final stock = item.productStockQuantity;
    final tracksStock = item.productContextLoaded &&
        item.productExists &&
        item.productTracksStock != false &&
        stock != null;
    // Before the sale takes the units, what is on hand is what can be picked.
    final short = tracksStock && !sold && stock < item.quantity;
    final placeholder = Icon(
      Icons.inventory_2_outlined,
      size: 24,
      color: roles.faintForeground,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 56,
            height: 56,
            color: theme.colorScheme.surfaceContainerHigh,
            alignment: Alignment.center,
            child: item.productImageUrl == null
                ? placeholder
                : ImageService.buildCachedImage(
                    imageUrl: item.productImageUrl,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    placeholder: placeholder,
                    errorWidget: placeholder,
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  item.productName,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 3),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: [
                          if (sku.isNotEmpty) sku,
                          item.quantity == 1
                              ? '1 u.'
                              : '${item.quantity} u. × '
                                  '${ChileanUtils.formatCurrency(item.unitPrice)}',
                        ].join(' · '),
                      ),
                      if (tracksStock)
                        TextSpan(
                          text: short
                              ? ' · Stock insuficiente: $stock'
                              : ' · Stock $stock',
                          style: short
                              ? TextStyle(
                                  color: roles.danger.accent,
                                  fontWeight: FontWeight.w700,
                                )
                              : null,
                        ),
                    ],
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            ChileanUtils.formatCurrency(item.subtotal),
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _AmountLine extends StatelessWidget {
  const _AmountLine({
    required this.icon,
    required this.label,
    required this.amount,
  });

  final IconData icon;
  final String label;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Icon(
            icon,
            size: 20,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: style)),
        const SizedBox(width: 12),
        Text(
          amount,
          style: style?.copyWith(
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({required this.order, required this.roles});

  final OnlineOrder order;
  final VinabikeThemeRoles roles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initials = order.customerName
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => word.characters.first.toUpperCase())
        .join();
    final phone = ChileanUtils.formatPhone(order.customerPhone);
    final contact = [
      if (phone.isNotEmpty) phone,
      if (order.customerEmail.trim().isNotEmpty) order.customerEmail.trim(),
    ].join(' · ');
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: roles.avatarSoftA,
            shape: BoxShape.circle,
          ),
          child: Text(
            initials.isEmpty ? '?' : initials,
            style: theme.textTheme.titleSmall?.copyWith(
              color: roles.avatarA,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                order.customerName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (contact.isNotEmpty) ...[
                const SizedBox(height: 2),
                SelectableText(
                  contact,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _DeliveryRow extends StatelessWidget {
  const _DeliveryRow({
    required this.order,
    required this.pickup,
    required this.roles,
    required this.onOpenMap,
  });

  final OnlineOrder order;
  final bool pickup;
  final VinabikeThemeRoles roles;
  final VoidCallback? onOpenMap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final street = [order.shippingAddressLine1, order.shippingAddressLine2]
        .map((part) => part?.trim() ?? '')
        .where((part) => part.isNotEmpty)
        .join(', ');
    final area = [order.shippingCity, order.shippingState]
        .map((part) => part?.trim() ?? '')
        .where((part) => part.isNotEmpty)
        .toSet()
        .join(' · ');
    final fallback = order.customerAddress?.trim() ?? '';
    final missing = !pickup && street.isEmpty && fallback.isEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 44,
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              pickup ? Icons.storefront_outlined : Icons.place_outlined,
              size: 21,
              color: missing ? roles.danger.accent : roles.avatarA,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: pickup
              ? Text(
                  'Lo retira en el local',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                )
              : missing
                  ? Text(
                      'Sin dirección registrada',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: roles.danger.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SelectableText(
                          street.isNotEmpty ? street : fallback,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (street.isNotEmpty && area.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          SelectableText(
                            area,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: muted,
                            ),
                          ),
                        ],
                      ],
                    ),
        ),
        if (!pickup && !missing && onOpenMap != null)
          TextButton(
            onPressed: onOpenMap,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: const Text('Mapa'),
          ),
      ],
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: DefaultTextStyle.merge(
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              child: Align(alignment: Alignment.centerRight, child: value),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.phone,
    required this.bottomInset,
    required this.busy,
    required this.primaryAction,
    required this.waitingLabel,
    required this.onRun,
    required this.onWhatsApp,
    required this.onCall,
    required this.onOpenSale,
  });

  final bool phone;
  final double bottomInset;
  final bool busy;
  final OnlineOrderSheetAction? primaryAction;
  final String? waitingLabel;
  final Future<void> Function(OnlineOrderSheetAction action) onRun;
  final VoidCallback? onWhatsApp;
  final VoidCallback? onCall;
  final VoidCallback? onOpenSale;

  static const double _height = 50;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    final action = primaryAction;
    final Widget? primary = action == null
        ? null
        : FilledButton.icon(
            onPressed: busy ? null : () => onRun(action),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, _height),
              padding: const EdgeInsets.symmetric(horizontal: 22),
              shape: shape,
              textStyle: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            icon: busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : Icon(action.icon, size: 20),
            label: Text(
              action.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
    final Widget? openSale = onOpenSale == null
        ? null
        : OutlinedButton.icon(
            onPressed: onOpenSale,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, _height),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              shape: shape,
            ),
            icon: const Icon(Icons.receipt_long_outlined, size: 19),
            label: const Text('Abrir venta ERP'),
          );
    final Widget? waiting = waitingLabel == null
        ? null
        : Text(
            waitingLabel!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          );

    final contactButtons = <Widget>[
      if (onWhatsApp != null)
        _SquareButton(
          tooltip: 'Escribir por WhatsApp',
          onPressed: onWhatsApp!,
          shape: shape,
          child: const FaIcon(FontAwesomeIcons.whatsapp, size: 21),
        ),
      if (onCall != null)
        _SquareButton(
          tooltip: 'Llamar al cliente',
          onPressed: onCall!,
          shape: shape,
          child: const Icon(Icons.call_outlined, size: 21),
        ),
    ];

    final List<Widget> children;
    if (phone) {
      // One wide slot after the contact buttons: the next step, or the sale
      // when the order has no step left, or what the order waits for.
      final slot = primary ?? openSale ?? waiting;
      children = [
        for (final button in contactButtons) ...[
          button,
          const SizedBox(width: 10),
        ],
        if (slot != null) Expanded(child: slot) else const Spacer(),
      ];
    } else {
      children = [
        for (final button in contactButtons) ...[
          button,
          const SizedBox(width: 10),
        ],
        const SizedBox(width: 6),
        Expanded(
          child: primary == null && waiting != null
              ? waiting
              : const SizedBox.shrink(),
        ),
        if (openSale != null) ...[
          const SizedBox(width: 10),
          openSale,
        ],
        if (primary != null) ...[
          const SizedBox(width: 10),
          primary,
        ],
      ];
    }
    if (contactButtons.isEmpty &&
        primary == null &&
        openSale == null &&
        waiting == null) {
      return SizedBox(height: bottomInset);
    }

    return Container(
      padding: EdgeInsets.fromLTRB(
        phone ? 16 : 32,
        12,
        phone ? 16 : 32,
        (phone ? 12 : 16) + bottomInset,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: roles.hairline)),
      ),
      child: Row(children: children),
    );
  }
}

class _SquareButton extends StatelessWidget {
  const _SquareButton({
    required this.tooltip,
    required this.onPressed,
    required this.shape,
    required this.child,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final OutlinedBorder shape;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            fixedSize: const Size.square(_ActionBar._height),
            minimumSize: const Size.square(_ActionBar._height),
            padding: EdgeInsets.zero,
            shape: shape,
            foregroundColor: theme.colorScheme.onSurface,
            side: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
          child: child,
        ),
      ),
    );
  }
}
