import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_searchable_select.dart';
import '../services/product_on_order_terms_service.dart';

/// «Se vende a pedido» en la ficha del producto: el interruptor, el
/// proveedor que lo trae y en cuántos días hábiles llega. Sin stock, la
/// tienda lo ofrece así y una cotización lo confirma sola; al pagar, el
/// borrador de compra va a ese proveedor. Se guarda con «Guardar» de la
/// ficha; la ficha es dueña de los controladores.
class ProductOnOrderTermsEditor extends StatelessWidget {
  const ProductOnOrderTermsEditor({
    super.key,
    required this.active,
    required this.onActiveChanged,
    required this.suppliers,
    required this.supplierId,
    required this.onSupplierChanged,
    required this.minController,
    required this.maxController,
    this.loadError,
  });

  final bool active;
  final ValueChanged<bool>? onActiveChanged;

  /// Proveedores activos: id y nombre.
  final List<({String id, String name})> suppliers;
  final String? supplierId;
  final ValueChanged<String?> onSupplierChanged;
  final TextEditingController minController;
  final TextEditingController maxController;

  /// No se pudo leer lo guardado: el interruptor queda quieto para no
  /// pisarlo al guardar.
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final faint =
        theme.textTheme.bodySmall?.copyWith(color: roles.faintForeground);
    final known = supplierId == null ||
        suppliers.any((supplier) => supplier.id == supplierId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile.adaptive(
          key: const ValueKey('product-on-order-switch'),
          contentPadding: EdgeInsets.zero,
          value: active,
          onChanged: loadError == null ? onActiveChanged : null,
          title: const Text('Se vende a pedido'),
          subtitle: Text(
            loadError ??
                (active
                    ? 'Sin stock, la tienda lo ofrece a pedido y se cotiza con '
                        'este plazo; al pagar, se le pide al proveedor.'
                    : 'Sin stock, la tienda lo muestra agotado. Actívalo si '
                        'un proveedor lo trae.'),
            style: faint,
          ),
        ),
        if (active) ...[
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
                    value: supplier.id, label: supplier.name),
            ],
            onChanged: onSupplierChanged,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, constraints) {
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
          }),
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
              return Text('En la tienda: «A pedido · ${terms.leadLabel}».',
                  style: faint);
            },
          ),
        ],
      ],
    );
  }
}
