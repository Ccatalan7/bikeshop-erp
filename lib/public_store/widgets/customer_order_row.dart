import 'package:flutter/material.dart';

import '../../modules/website/models/website_models.dart';
import '../../shared/utils/chilean_utils.dart';
import '../models/customer_portal_presentation.dart';
import 'customer_portal_style.dart';

/// Columnas de la tabla de pedidos en ancho: producto, número, fecha, estado
/// y total. La cabecera y las filas usan las mismas.
const double _numberColumn = 140;
const double _dateColumn = 120;
const double _statusColumn = 200;
const double _totalColumn = 110;

/// Desde este ancho los pedidos se leen como tabla.
const double customerOrderTableBreakpoint = 880;

/// Los rótulos de las columnas, sobre la línea fuerte de la tabla.
class CustomerOrderTableHeader extends StatelessWidget {
  const CustomerOrderTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    Text label(String text, {TextAlign align = TextAlign.left}) =>
        Text(text, textAlign: align, style: style.micro);
    return ExcludeSemantics(
      child: Row(
        children: [
          const SizedBox(width: 72 + 20),
          Expanded(child: label('PRODUCTO')),
          SizedBox(width: _numberColumn, child: label('PEDIDO')),
          SizedBox(width: _dateColumn, child: label('FECHA')),
          SizedBox(width: _statusColumn, child: label('ESTADO')),
          SizedBox(
            width: _totalColumn,
            child: label('TOTAL', align: TextAlign.right),
          ),
          const SizedBox(width: 18 + 16),
        ],
      ),
    );
  }
}

/// Un pedido en una fila: foto, qué se compró, número, fecha, estado y
/// total. En ancho son columnas; en teléfono se apila. Lo usan el resumen y
/// «Pedidos».
class CustomerOrderRow extends StatelessWidget {
  const CustomerOrderRow({
    super.key,
    required this.order,
    required this.imageUrl,
    required this.onTap,
  });

  final OnlineOrder order;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final presentation = CustomerOrderPresentation.of(order);
    final total = ChileanUtils.formatCurrency(order.total);
    final tag = PortalStatusTag(
      label: presentation.label,
      tone: presentation.tone,
      needsCustomer: presentation.needsCustomer,
      active: presentation.group == CustomerOrderGroup.inProgress,
    );
    final summary = CustomerOrderPresentation.itemsSummary(order);
    final date = portalDate(order.createdAt).replaceAll(' ', ' ');
    final nextStep = presentation.needsCustomer ? presentation.nextStep : null;
    final thumb = PortalThumb(
      imageUrl: imageUrl,
      fallbackIcon: Icons.shopping_bag_outlined,
      size: 72,
    );

    return Semantics(
      button: true,
      label: 'Pedido ${order.orderNumber}, ${presentation.label}, $total',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final what = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: style.rowTitle,
                    ),
                    if (nextStep != null) ...[
                      const SizedBox(height: 4),
                      Text(nextStep, style: style.nextStep),
                    ],
                  ],
                );
                if (width >= customerOrderTableBreakpoint) {
                  return Row(
                    children: [
                      thumb,
                      const SizedBox(width: 20),
                      Expanded(child: what),
                      SizedBox(
                        width: _numberColumn,
                        child: Text(
                          order.orderNumber,
                          style: style.heading(
                            14,
                            weight: FontWeight.w500,
                            color: style.inkSecondary,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: _dateColumn,
                        child: Text(date, style: style.rowMeta),
                      ),
                      SizedBox(
                        width: _statusColumn,
                        child:
                            Align(alignment: Alignment.centerLeft, child: tag),
                      ),
                      SizedBox(
                        width: _totalColumn,
                        child: Text(
                          total,
                          textAlign: TextAlign.right,
                          style: style.figure,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.arrow_forward, size: 18, color: style.ink),
                    ],
                  );
                }
                if (width >= PortalStyle.compactBreakpoint) {
                  return Row(
                    children: [
                      thumb,
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            what,
                            const SizedBox(height: 4),
                            Text(
                              '${order.orderNumber} · $date',
                              style: style.rowMeta,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(total, style: style.figure),
                          const SizedBox(height: 8),
                          tag,
                        ],
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.arrow_forward, size: 18, color: style.ink),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PortalThumb(
                      imageUrl: imageUrl,
                      fallbackIcon: Icons.shopping_bag_outlined,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          what,
                          const SizedBox(height: 4),
                          Text(
                            '${order.orderNumber} · $date',
                            style: style.rowMeta,
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                tag,
                                Text(total, style: style.figureSmall),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Un pedido que espera al cliente, en grande: la foto del producto sobre el
/// gris, el estado, lo que tiene que hacer y los datos cortos.
///
/// Con [PortalTileLayout.equalHeight] la ficha llena el alto que le dan (dos
/// fichas lado a lado dentro de un `IntrinsicHeight`) y los botones bajan al
/// pie; por eso no lleva `LayoutBuilder` adentro.
class CustomerOrderTile extends StatelessWidget {
  const CustomerOrderTile({
    super.key,
    required this.order,
    required this.imageUrl,
    required this.onOpen,
    required this.compact,
    this.layout = PortalTileLayout.stacked,
  });

  final OnlineOrder order;
  final String? imageUrl;
  final VoidCallback onOpen;
  final bool compact;
  final PortalTileLayout layout;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final presentation = CustomerOrderPresentation.of(order);
    final total = ChileanUtils.formatCurrency(order.total);
    final copy = CustomerOrderPresentation.feature(
      order,
      formattedTotal: total,
    );
    final transfer = presentation.awaitsTransfer;
    final url = imageUrl?.trim() ?? '';
    final horizontal = layout == PortalTileLayout.horizontal;
    final wellHeight = horizontal ? 300.0 : (compact ? 190.0 : 220.0);
    final units = CustomerOrderPresentation.unitCount(order);

    final actions = [
      PortalButton(
        label: transfer ? 'Datos de transferencia' : 'Ver pedido',
        kind: presentation.needsCustomer
            ? PortalButtonKind.primary
            : PortalButtonKind.secondary,
        arrow: true,
        expand: compact,
        onPressed: onOpen,
      ),
    ];

    final bag = Icon(
      Icons.shopping_bag_outlined,
      size: 56,
      color: style.inkSecondary,
    );
    final well = PortalWell(
      height: wellHeight,
      topLeft: const PortalTag(label: 'Pedido'),
      topRight: order.orderNumber,
      child: url.isEmpty ? bag : PortalProductImage(url: url, fallback: bag),
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: PortalStatusTag(
            label: presentation.label,
            tone: presentation.tone,
            needsCustomer: presentation.needsCustomer,
          ),
        ),
        const SizedBox(height: 12),
        Semantics(
          header: true,
          child: Text(
            copy.headline.toUpperCase(),
            semanticsLabel: copy.headline,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: style.featureTitle(compact: compact),
          ),
        ),
        if (copy.message != null) ...[
          const SizedBox(height: 12),
          Text(copy.message!, style: style.pageSubtitle),
        ],
        const SizedBox(height: 16),
        PortalFactStrip(
          facts: [
            ('Pedido el', portalDate(order.createdAt)),
            ('Productos', '$units'),
            ('Total', total),
          ],
        ),
        if (layout == PortalTileLayout.equalHeight)
          const Spacer()
        else
          const SizedBox(height: 4),
        const SizedBox(height: 20),
        if (compact)
          ...actions
        else
          Wrap(spacing: 12, runSpacing: 12, children: actions),
      ],
    );
    return portalTileFrame(
      well: well,
      details: details,
      layout: layout,
      compact: compact,
    );
  }
}
