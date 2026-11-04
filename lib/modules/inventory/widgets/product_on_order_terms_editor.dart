import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_searchable_select.dart';
import '../services/product_on_order_terms_service.dart';

/// «Cuando no hay stock» en la ficha del producto (20261103070000): según su
/// marca, se cotiza, se vende a pedido (con el proveedor que lo trae y en
/// cuántos días hábiles llega) o no se ofrece. El dueño: «no es simplemente
/// que si un producto está agotado, automáticamente se puede agregar a una
/// cotización». Se guarda con «Guardar» de la ficha; la ficha es dueña de los
/// controladores.
class ProductOnOrderTermsEditor extends StatelessWidget {
  const ProductOnOrderTermsEditor({
    super.key,
    required this.offer,
    required this.onOfferChanged,
    required this.brandName,
    required this.brandQuoted,
    required this.suppliers,
    required this.supplierId,
    required this.onSupplierChanged,
    required this.minController,
    required this.maxController,
    this.loadError,
  });

  final SoldOutOffer offer;
  final ValueChanged<SoldOutOffer> onOfferChanged;

  /// La marca elegida en la ficha (null sin marca) y si está entre las que
  /// se cotizan sin stock (Ventas › Cotizaciones › Ajustes).
  final String? brandName;
  final bool brandQuoted;

  /// Proveedores activos: id y nombre.
  final List<({String id, String name})> suppliers;
  final String? supplierId;
  final ValueChanged<String?> onSupplierChanged;
  final TextEditingController minController;
  final TextEditingController maxController;

  /// No se pudo leer lo guardado: la decisión queda quieta para no pisarla
  /// al guardar.
  final String? loadError;

  static String? validateMin(String? raw) {
    final value = int.tryParse(raw?.trim() ?? '');
    if (value == null) return 'Escribe los días.';
    if (value < 0 || value > ProductOnOrderTerms.maxLeadDaysMin) {
      return 'Entre 0 y ${ProductOnOrderTerms.maxLeadDaysMin} días.';
    }
    return null;
  }

  static String? validateMax(String? raw, String? minRaw) {
    final value = int.tryParse(raw?.trim() ?? '');
    final min = int.tryParse(minRaw?.trim() ?? '');
    if (value == null) return 'Escribe los días.';
    if (min != null && value < min) return 'No puede ser menos que el mínimo.';
    if (value > ProductOnOrderTerms.maxLeadDaysMax) {
      return 'Hasta ${ProductOnOrderTerms.maxLeadDaysMax} días.';
    }
    return null;
  }

  /// Lo que hace hoy la marca, dicho en la opción «Según la marca».
  String get _brandLine {
    final brand = brandName?.trim() ?? '';
    if (brand.isEmpty) return 'Sin marca, no se ofrece.';
    return brandQuoted
        ? '$brand se cotiza sin stock.'
        : '$brand no está entre las marcas que se cotizan sin stock '
            '(Ventas › Cotizaciones › Ajustes): no se ofrece.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final faint = theme.textTheme.bodySmall?.copyWith(
      color: roles.faintForeground,
    );
    // What each choice does is what decides it: the caveat's ink.
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final enabled = loadError == null;
    final known = supplierId == null ||
        suppliers.any((supplier) => supplier.id == supplierId);
    Widget option(SoldOutOffer value, String title, String subtitle) =>
        RadioListTile<SoldOutOffer>(
          key: ValueKey('product-sold-out-${value.name}'),
          value: value,
          enabled: enabled,
          contentPadding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          title: Text(title),
          subtitle: Text(subtitle, style: muted),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Cuando no hay stock', style: theme.textTheme.titleSmall),
        const SizedBox(height: 2),
        Text(
          loadError ?? 'Lo que la tienda hace con este producto si se agota.',
          style: loadError == null
              ? faint
              : theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
        ),
        const SizedBox(height: 6),
        RadioGroup<SoldOutOffer>(
          groupValue: offer,
          onChanged: (value) {
            if (enabled && value != null) onOfferChanged(value);
          },
          child: Column(
            children: [
              option(SoldOutOffer.byBrand, 'Según la marca', _brandLine),
              option(
                SoldOutOffer.quote,
                'Se cotiza',
                'La tienda ofrece cotizarlo y el taller confirma con sus '
                    'proveedores.',
              ),
              option(
                SoldOutOffer.onOrder,
                'Se vende a pedido',
                'Con el proveedor que lo trae y su plazo: la cotización lo '
                    'confirma sola.',
              ),
              option(
                SoldOutOffer.none,
                'No se ofrece',
                'La tienda lo muestra agotado; sólo se puede preguntar por él.',
              ),
            ],
          ),
        ),
        if (offer == SoldOutOffer.onOrder) ...[
          const SizedBox(height: 12),
          VbSearchableSelect<String>(
            key: const ValueKey('product-on-order-supplier'),
            value: known ? supplierId : null,
            label: 'Proveedor que lo trae',
            sheetTitle: 'Proveedor que lo trae',
            placeholder: 'Elegir proveedor',
            allowClear: true,
            clearLabel: 'Sin proveedor',
            helperText: supplierId == null
                ? 'Sin proveedor, el borrador de compra se arma a mano.'
                : null,
            options: [
              for (final supplier in suppliers)
                VbSearchableSelectOption(
                  value: supplier.id,
                  label: supplier.name,
                ),
            ],
            onChanged: onSupplierChanged,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final min = TextFormField(
                key: const ValueKey('product-on-order-min'),
                controller: minController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                decoration: const InputDecoration(
                  labelText: 'Llega en',
                  suffixText: 'días',
                ),
                validator: validateMin,
              );
              final max = TextFormField(
                key: const ValueKey('product-on-order-max'),
                controller: maxController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                decoration: const InputDecoration(
                  labelText: 'a',
                  suffixText: 'días hábiles',
                ),
                validator: (raw) => validateMax(raw, minController.text),
              );
              return constraints.maxWidth < 360
                  ? Column(children: [min, const SizedBox(height: 12), max])
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: min),
                        const SizedBox(width: 12),
                        Expanded(child: max),
                      ],
                    );
            },
          ),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: Listenable.merge([minController, maxController]),
            builder: (context, _) {
              final min = int.tryParse(minController.text.trim());
              final max = int.tryParse(maxController.text.trim());
              if (min == null || max == null || max < min) {
                return const SizedBox.shrink();
              }
              final terms = ProductOnOrderTerms(
                isActive: true,
                leadDaysMin: min,
                leadDaysMax: max,
              );
              return Text(
                'En la tienda: «A pedido · ${terms.leadLabel}».',
                style: faint,
              );
            },
          ),
        ],
      ],
    );
  }
}
