import 'package:flutter/material.dart';

import '../models/customer_portal_presentation.dart';
import 'customer_bike_drawing.dart';
import 'customer_portal_style.dart';

/// Una bici del cliente como un catálogo muestra un producto: el dibujo de
/// su tipo sobre el gris, el tipo en una etiqueta, el nombre en mayúsculas y
/// debajo cuántas veces pasó por el taller.
class CustomerBikeCard extends StatelessWidget {
  const CustomerBikeCard({
    super.key,
    required this.bike,
    required this.onTap,
    this.compact = false,
  });

  final Map<String, dynamic> bike;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final title = CustomerWorkshopPresentation.bikeTitle(bike);
    final type = customerBikeTypeLabel(bike['bike_type']);
    final details = _detailsWithoutType(bike);
    final services = customerBikeServiceSummary(bike);
    final image = customerBikeImage(bike);

    return Semantics(
      button: true,
      label: [title, if (type != null) type, services].join(', '),
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              PortalWell(
                height: compact ? 200 : 250,
                topLeft: type == null ? null : PortalTag(label: type),
                child: image == null
                    ? CustomerBikeDrawing(
                        silhouette: customerBikeSilhouette(bike['bike_type']),
                        width: compact ? 220 : 260,
                        color: style.ink,
                      )
                    : PortalProductImage(
                        url: image,
                        fallback: CustomerBikeDrawing(
                          silhouette: customerBikeSilhouette(bike['bike_type']),
                          width: compact ? 220 : 260,
                          color: style.ink,
                        ),
                      ),
              ),
              const SizedBox(height: 16),
              Text(
                title.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: style.itemTitle(compact: compact),
              ),
              if (details.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(details, style: style.body(15, color: style.inkSecondary)),
              ],
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: style.line)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          services,
                          style: style.body(14, weight: FontWeight.w500),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.arrow_forward, size: 18, color: style.ink),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Color, aro y año: el tipo ya va en la etiqueta.
  static String _detailsWithoutType(Map<String, dynamic> bike) {
    final withoutType = Map<String, dynamic>.from(bike)..remove('bike_type');
    return customerBikeDetails(withoutType);
  }
}

/// La foto del taller (la que el dueño elige en el editor) con el acceso a
/// servicios y precios, el texto abajo a la izquierda. Sin foto, la baldosa
/// va en el color de texto.
class CustomerWorkshopTile extends StatelessWidget {
  const CustomerWorkshopTile({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final style = PortalStyle.of(context);
    final image = style.site.customerPortalWorkshopImage;
    final hasImage = image.isNotEmpty;
    final foreground = hasImage ? Colors.white : style.onBand;
    final background = ColoredBox(color: style.band);
    return Semantics(
      button: true,
      label: 'Servicios y precios del taller',
      excludeSemantics: true,
      child: Material(
        color: style.band,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 360),
            child: Stack(
              alignment: AlignmentDirectional.bottomStart,
              children: [
                Positioned.fill(
                  child: hasImage
                      ? Image.network(
                          image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => background,
                        )
                      : background,
                ),
                if (hasImage)
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Color(0xDB0A0B0B),
                            Color(0x590A0B0B),
                            Color(0x0D0A0B0B),
                          ],
                          stops: [0, 0.55, 1],
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TALLER',
                        style: style.eyebrow.copyWith(
                          color: foreground.withValues(alpha: 0.86),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'SERVICIOS Y PRECIOS',
                        style: style.heading(30).copyWith(color: foreground),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Mantenciones y reparaciones para tu próxima visita.',
                        style: style.body(
                          15,
                          color: foreground.withValues(alpha: 0.88),
                        ),
                      ),
                      const SizedBox(height: 18),
                      IgnorePointer(
                        child: PortalButton(
                          label: 'Ver servicios',
                          kind: PortalButtonKind.onPhoto,
                          arrow: true,
                          onPressed: onTap,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// La ficha de una bici: tipo, color y aro, su paso por el taller, la
/// garantía y los datos que el taller anotó.
Future<void> showCustomerBikeDetail(
  BuildContext context, {
  required Map<String, dynamic> bike,
  required ValueChanged<String> onNavigate,
}) {
  final warranty = portalParseDate(bike['warranty_until']);
  final purchased = portalParseDate(bike['purchase_date']);
  final count = (bike['service_count'] as num?)?.toInt() ?? 0;
  String? text(String key) {
    final value = (bike[key] ?? '').toString().trim();
    return value.isEmpty ? null : value;
  }

  final warrantyActive = warranty != null &&
      !warranty.isBefore(DateUtils.dateOnly(DateTime.now()));
  final details = customerBikeDetails(bike);

  return showPortalDetail(
    context,
    title: CustomerWorkshopPresentation.bikeTitle(bike),
    subtitle: details.isEmpty ? null : details,
    status: warranty == null
        ? null
        : Align(
            alignment: Alignment.centerLeft,
            child: PortalTag(
              label: warrantyActive
                  ? 'Garantía hasta el ${portalDate(warranty)}'
                  : 'Garantía vencida el ${portalDate(warranty)}',
              kind:
                  warrantyActive ? PortalTagKind.success : PortalTagKind.quiet,
            ),
          ),
    body: PortalFacts(
      facts: [
        ('Taller', customerBikeServiceSummary(bike)),
        ('Talla de cuadro', text('frame_size')),
        ('Número de serie', text('serial_number')),
        ('Comprada', purchased == null ? null : portalDate(purchased)),
        ('Notas', text('notes')),
      ],
    ),
    actions: [
      if (count > 0)
        Builder(
          builder: (buttonContext) => PortalButton(
            label: 'Ver sus trabajos de taller',
            arrow: true,
            onPressed: () {
              Navigator.of(buttonContext).pop();
              onNavigate('/cuenta/servicios?bike_id=${bike['id']}');
            },
          ),
        ),
    ],
  );
}
