import 'package:flutter/material.dart';

import '../../modules/website/models/website_models.dart';
import '../../shared/utils/chilean_utils.dart';
import '../models/customer_portal_presentation.dart';
import 'customer_portal_style.dart';

/// Un pedido en una fila: foto, número, qué se compró y cuándo; a la derecha
/// el total y su estado. Lo usan el resumen y «Pedidos».
class CustomerOrderRow extends StatelessWidget {
  const CustomerOrderRow({
    super.key,
    required this.order,
    required this.imageUrl,
    required this.compact,
    required this.onTap,
  });

  final OnlineOrder order;
  final String? imageUrl;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final presentation = CustomerOrderPresentation.of(order);
    final total = ChileanUtils.formatCurrency(order.total);
    final pill = PortalStatusPill(
      label: presentation.label,
      tone: presentation.tone,
    );
    final summary = CustomerOrderPresentation.itemsSummary(order);
    final date = portalDate(order.createdAt);
    final nextStep = presentation.needsCustomer ? presentation.nextStep : null;
    return PortalRow(
      leading: PortalThumb(
        imageUrl: imageUrl,
        fallbackIcon: Icons.shopping_bag_outlined,
      ),
      title: summary,
      meta: compact
          ? '$total · $date · ${order.orderNumber}'
          : 'Pedido ${order.orderNumber} · $date',
      semanticsLabel:
          'Pedido ${order.orderNumber}, ${presentation.label}, $total',
      footer: compact
          ? PortalStatusLine(pill: pill, nextStep: nextStep)
          : nextStep == null
              ? null
              : Text(nextStep, style: style.nextStep),
      trailing:
          compact ? null : PortalTrailingColumns(pill: pill, figure: total),
      onTap: onTap,
    );
  }
}
