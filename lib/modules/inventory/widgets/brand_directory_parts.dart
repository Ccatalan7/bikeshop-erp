import 'package:flutter/material.dart';

import '../../../shared/services/image_service.dart';
import '../../../shared/themes/vinabike_theme_roles.dart';
import '../models/brand_directory.dart';

/// Las piezas que comparten la lista, las tarjetas y la página de una marca:
/// dos vistas de lo mismo se dibujan con las mismas piezas
/// (`.github/GUI_DESIGN_PRINCIPLES.md`, 2026-11-08).

/// «124 productos · 44 con stock».
String brandStockLine(BrandDirectoryEntry entry) {
  if (entry.products == 0) return 'Sin productos';
  return '${brandPlural(entry.products, 'producto')} · '
      '${brandCount(entry.inStock)} con stock';
}

/// El proveedor que se nombra primero, si es el representante oficial, y
/// cuántos más la traen: «Andes Industrial ✓ oficial +5».
class BrandSupplierLine extends StatelessWidget {
  const BrandSupplierLine({
    super.key,
    required this.entry,
    this.fontSize = 13.5,
    this.leading,
  });

  final BrandDirectoryEntry entry;
  final double fontSize;

  /// Un ícono antes del nombre, en las tarjetas.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final supplier = entry.supplier;
    if (supplier == null) {
      return Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          Flexible(
            child: Text(
              'Sin proveedor',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: fontSize, color: roles.faintForeground),
            ),
          ),
        ],
      );
    }
    final others = entry.otherSuppliers;
    return Semantics(
      label: [
        'Proveedor ${supplier.name}',
        if (supplier.official) 'representante oficial',
        if (others > 0) 'y ${brandPlural(others, 'proveedor', 'proveedores')} más',
      ].join(', '),
      excludeSemantics: true,
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          Flexible(
            child: Text(
              supplier.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: fontSize, color: scheme.onSurface),
            ),
          ),
          if (supplier.official) ...[
            const SizedBox(width: 6),
            Icon(Icons.check_rounded, size: 14, color: roles.success.accent),
            const SizedBox(width: 2),
            Text(
              'oficial',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: roles.success.accent,
              ),
            ),
          ],
          if (others > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
              decoration: BoxDecoration(
                color: roles.neutral.container,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '+$others',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Lo vendido en 12 meses con una barra fina contra la marca que más vendió:
/// se lee de un vistazo qué marcas mueven el taller, con la cifra en tinta.
class BrandSoldBar extends StatelessWidget {
  const BrandSoldBar({
    super.key,
    required this.sold,
    required this.max,
    this.barWidth = 64,
  });

  final num sold;
  final num max;
  final double barWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final share = max <= 0 ? 0.0 : (sold / max).clamp(0.0, 1.0).toDouble();
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        ExcludeSemantics(
          child: Container(
            width: barWidth,
            height: 4,
            decoration: BoxDecoration(
              color: roles.hairline,
              borderRadius: BorderRadius.circular(2),
            ),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: share,
              child: Container(
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 36,
          child: Text(
            brandCount(sold),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 14,
              color: sold > 0 ? scheme.onSurface : roles.faintForeground,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

/// La foto de un producto sobre su placa blanca, también en oscuro: las fotos
/// del catálogo son sobre blanco. Sin foto, el ícono deja su lugar.
class BrandProductPhoto extends StatelessWidget {
  const BrandProductPhoto({
    super.key,
    required this.url,
    this.size,
    this.semanticLabel,
  });

  final String? url;

  /// Nulo: llena lo que le den (una tarjeta pone el cuadrado).
  final double? size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final roles = VinabikeThemeRoles.of(context);
    final placeholder = Center(
      child: Icon(
        Icons.inventory_2_outlined,
        size: (size ?? 44) * 0.42,
        color: roles.faintForeground,
      ),
    );
    final image = url == null || url!.isEmpty
        ? placeholder
        : Padding(
            padding: EdgeInsets.all(size != null && size! < 48 ? 3 : 6),
            child: ImageService.buildCachedImage(
              imageUrl: url,
              width: size,
              height: size,
              fit: BoxFit.contain,
              placeholder: placeholder,
              errorWidget: placeholder,
            ),
          );
    final hasImage = url != null && url!.isNotEmpty;
    final plate = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        // La placa es blanca en los dos temas: la foto trae su fondo blanco.
        // Sin foto, el lugar queda en el tono neutro del tema.
        color: hasImage ? Colors.white : roles.neutral.container,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: roles.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      child: image,
    );
    final label = semanticLabel;
    return label == null
        ? ExcludeSemantics(child: plate)
        : Semantics(image: true, label: label, child: plate);
  }
}
