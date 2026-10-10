import 'package:flutter/material.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_button.dart';
import '../../inventory/models/inventory_models.dart';
import '../../inventory/pages/product_form_page.dart';
import '../../inventory/widgets/product_editor_dialog.dart';
import '../widgets/premium_product_card.dart';
import 'catalog_ui_parts.dart';
import 'catalog_web_controller.dart';
import 'catalog_web_models.dart';

/// Opens the item's canonical product form on its «Tienda Online» section
/// and reads the catalog again when it saves.
Future<void> openCatalogItemEditor(
  BuildContext context,
  CatalogWebController controller,
  CatalogWebItem item, {
  ProductFormSection section = ProductFormSection.website,
}) async {
  final saved = await showProductEditorDialog(
    context: context,
    productId: item.id,
    initialProductType: item.kind == CatalogItemKind.service
        ? ProductType.service
        : ProductType.product,
    initialSection: section,
  );
  if (saved == true) await controller.load(quiet: true);
}

/// Everything about one item: where it stands, why, what fixes it and how
/// the customer sees it. The desktop pane and the phone sheet show this.
class CatalogItemDetail extends StatelessWidget {
  const CatalogItemDetail({
    super.key,
    required this.item,
    required this.controller,
    this.onClose,
  });

  final CatalogWebItem item;
  final CatalogWebController controller;
  final VoidCallback? onClose;

  Future<void> _run(
    BuildContext context,
    Future<Object?> Function() action, {
    String? done,
  }) async {
    try {
      final result = await action();
      if (!context.mounted) return;
      if (result is String) {
        showCatalogMessage(context, result);
      } else if (done != null) {
        showCatalogMessage(context, done);
      }
    } catch (error) {
      if (context.mounted)
        showCatalogMessage(context, catalogErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isConsumable = item.kind == CatalogItemKind.consumable;
    final busy = controller.busy;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CatalogThumb(item: item, size: 88),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CatalogStateBadge(item.state),
                  const SizedBox(height: 6),
                  Text(
                    item.displayName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (item.sku.isNotEmpty) item.sku,
                      if (item.hasWebName) 'en el ERP: ${item.name}',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (onClose != null)
              IconButton(
                tooltip: 'Cerrar',
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(item.reason, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 14),
        _SaleSwitch(
          item: item,
          busy: busy,
          onChanged: isConsumable
              ? null
              : (on) => _run(
                    context,
                    () async => (await controller.setWebSale([item.id], on: on))
                        .describe(on: on),
                  ),
        ),
        const SizedBox(height: 14),
        _WhyList(item: item, rules: controller.rules),
        ..._actionCards(context),
        const SizedBox(height: 16),
        _Preview(item: item),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            VbButton(
              label: 'Editar ficha',
              icon: Icons.edit_outlined,
              variant: VbButtonVariant.secondary,
              onPressed: () => openCatalogItemEditor(context, controller, item),
            ),
            if (item.state == CatalogItemState.selling ||
                item.state == CatalogItemState.soldOut)
              VbButton(
                label: 'Ver en la tienda',
                icon: Icons.open_in_new,
                variant: VbButtonVariant.text,
                onPressed: () => openCatalogStorePath(
                  context,
                  item.kind == CatalogItemKind.service
                      ? '/servicios'
                      : catalogPublicPath(item),
                ),
              ),
          ],
        ),
      ],
    );
  }

  List<Widget> _actionCards(BuildContext context) {
    final cards = <Widget>[];
    final busy = controller.busy;
    final issues = item.issues.toSet();

    if (item.kind == CatalogItemKind.consumable) {
      final sold = item.soldCounter12m;
      cards.add(_ActionCard(
        tone: _Tone.workshop,
        title: sold > 0
            ? 'Se vendió $sold ${sold == 1 ? 'vez' : 'veces'} al mesón en 12 meses'
            : 'Sólo se usa en el taller',
        body: sold > 0
            ? 'Venderlo al mesón está bien. Si además lo quieres en la web, conviértelo en producto de venta: empieza a llevar stock y costo, y el cambio queda registrado.'
            : 'Está bien así: no se vende online y su compra va a gasto.'
                '${item.usedJobs12m > 0 ? ' Se usó ${item.usedJobs12m} ${item.usedJobs12m == 1 ? 'vez' : 'veces'} en trabajos este año.' : ''}',
        actions: [
          if (sold > 0)
            VbButton(
              label: 'Convertir en producto de venta',
              busy: busy,
              onPressed: () => _run(
                context,
                () => controller.convertItem(item.id, toConsumable: false),
                done:
                    'Ahora es producto de venta. Cuenta su stock para venderlo en la web.',
              ),
            ),
          if (sold > 0 && issues.contains('counter_consumable'))
            VbButton(
              label: 'Dejar como consumible',
              variant: VbButtonVariant.text,
              onPressed: () => _run(
                context,
                () => controller.dismissIssue(item.id, 'counter_consumable'),
                done: 'Queda como consumible del taller.',
              ),
            ),
        ],
      ));
    }

    if (item.block == 'below_cost') {
      final min = item.minWebPrice;
      cards.add(_ActionCard(
        tone: _Tone.warning,
        title: min == null
            ? 'Se vende bajo el costo con IVA'
            : 'Precio mínimo sin pérdida: ${catalogMoney(min)}',
        body: min == null
            ? 'Cada venta perdería plata.'
            : 'Hoy cada venta pierde ${catalogMoney(min - item.webPrice)} antes de cualquier gasto. Si es a propósito, márcalo como liquidación con fecha de término.',
        actions: [
          VbButton(
            label: 'Cambiar precio',
            onPressed: () => openCatalogItemEditor(context, controller, item),
          ),
          VbButton(
            label: 'Liquidar 30 días',
            variant: VbButtonVariant.secondary,
            busy: busy,
            onPressed: () => _run(
              context,
              () => controller.setClearance(
                item.id,
                DateUtils.dateOnly(DateTime.now())
                    .add(const Duration(days: 30)),
              ),
              done:
                  'En liquidación por 30 días: sale a la venta bajo el costo.',
            ),
          ),
        ],
      ));
    }

    if (item.onClearance) {
      final until = item.clearanceUntil!;
      cards.add(_ActionCard(
        tone: _Tone.info,
        title:
            'En liquidación hasta el ${until.day}/${until.month}/${until.year}',
        body:
            'Se vende aunque quede bajo el costo. Al terminar, vuelve la regla.',
        actions: [
          VbButton(
            label: 'Quitar liquidación',
            variant: VbButtonVariant.secondary,
            busy: busy,
            onPressed: () => _run(
              context,
              () => controller.setClearance(item.id, null),
              done: 'Liquidación quitada.',
            ),
          ),
        ],
      ));
    }

    if (item.block == 'missing_image' ||
        item.block == 'missing_web_name' ||
        item.block == 'missing_description' ||
        item.block == 'missing_brand' ||
        item.block == 'missing_price') {
      cards.add(_ActionCard(
        tone: _Tone.warning,
        title: CatalogReasons.block(item.block),
        body: item.sellable > 0
            ? 'Tiene ${item.sellable} en stock: en cuanto se complete, sale a la venta.'
            : 'Se completa en la ficha, sección «Tienda Online».',
        actions: [
          VbButton(
            label: item.block == 'missing_image'
                ? 'Subir foto'
                : 'Completar ficha',
            onPressed: () => openCatalogItemEditor(context, controller, item),
          ),
        ],
      ));
    }

    if (issues.contains('missing_tax')) {
      cards.add(_ActionCard(
        tone: _Tone.warning,
        title: 'Sin clasificación de IVA',
        body: 'El checkout lo rechaza y Google Merchant no lo recibe.',
        actions: [
          VbButton(
            label: 'Afecto IVA 19 %',
            busy: busy,
            onPressed: () => _run(
              context,
              () => controller.classifyTax([item.id], rate: 19),
              done: 'Clasificado como afecto a IVA.',
            ),
          ),
          VbButton(
            label: 'Exento',
            variant: VbButtonVariant.secondary,
            onPressed: () => _run(
              context,
              () => controller.classifyTax([item.id], rate: 0),
              done: 'Clasificado como exento.',
            ),
          ),
        ],
      ));
    }

    if (issues.contains('gtin_in_sku')) {
      cards.add(_ActionCard(
        tone: _Tone.info,
        title: 'El SKU ${item.sku} es un código de barras',
        body:
            'Copiarlo al GTIN ayuda a Google a mostrarlo junto a los demás vendedores. No cambia el SKU.',
        actions: [
          VbButton(
            label: 'Copiar a GTIN',
            busy: busy,
            onPressed: () => _run(
              context,
              () => controller.copySkuToGtin([item.id]),
              done: 'Código de barras copiado al GTIN.',
            ),
          ),
          VbButton(
            label: 'No es código de barras',
            variant: VbButtonVariant.text,
            busy: busy,
            onPressed: () => _run(
              context,
              () => controller.dismissIssue(item.id, 'gtin_in_sku'),
              done: 'Anotado: el SKU no se copia al GTIN.',
            ),
          ),
        ],
      ));
    }

    if (issues.contains('bulk_pack')) {
      cards.add(_ActionCard(
        tone: _Tone.info,
        title: 'Es un paquete del taller',
        body:
            '¿Se vende así, o es insumo del taller? Si es insumo, pasa a consumible: su stock pasa a gasto y sale de la web.',
        actions: [
          VbButton(
            label: 'Se vende así',
            variant: VbButtonVariant.secondary,
            onPressed: () => _run(
              context,
              () => controller.dismissIssue(item.id, 'bulk_pack'),
              done: 'Queda a la venta como paquete.',
            ),
          ),
          VbButton(
            label: 'Es insumo del taller',
            variant: VbButtonVariant.secondary,
            busy: busy,
            onPressed: () => _run(
              context,
              () => controller.convertItem(item.id, toConsumable: true),
              done: 'Ahora es consumible del taller y salió de la web.',
            ),
          ),
        ],
      ));
    }

    if (item.kind == CatalogItemKind.service) {
      cards.add(_ActionCard(
        tone: _Tone.info,
        title: 'Cómo se muestra el precio',
        body: switch (item.priceMode) {
          CatalogPriceMode.exact =>
            'Se muestra ${catalogMoney(item.webPrice)}.',
          CatalogPriceMode.from =>
            'Se muestra «Desde ${catalogMoney(item.webPrice)}»: depende del caso.',
          CatalogPriceMode.quote =>
            'Se muestra «A cotizar»: el cliente pregunta por WhatsApp.',
        },
        actions: [
          SegmentedButton<CatalogPriceMode>(
            showSelectedIcon: false,
            segments: [
              for (final mode in CatalogPriceMode.values)
                ButtonSegment(value: mode, label: Text(mode.label)),
            ],
            selected: {item.priceMode},
            onSelectionChanged: busy
                ? null
                : (selection) => _run(
                      context,
                      () => controller.setPriceMode(item.id, selection.first),
                      done: 'Precio: ${selection.first.label.toLowerCase()}.',
                    ),
          ),
        ],
      ));
    }

    if (issues.contains('empty_record')) {
      cards.add(_ActionCard(
        tone: _Tone.info,
        title: 'No es un producto',
        body:
            'Está activo, a \$0, sin costo ni stock, y nunca se vendió ni se compró. Archivarlo lo saca de los buscadores del ERP.',
        actions: [
          VbButton(
            label: 'Archivar',
            variant: VbButtonVariant.secondary,
            busy: busy,
            onPressed: () => _run(
              context,
              () => controller.archiveEmptyRecords([item.id]),
              done: 'Archivado.',
            ),
          ),
        ],
      ));
    }

    return [
      for (final card in cards) ...[const SizedBox(height: 12), card],
    ];
  }
}

class _SaleSwitch extends StatelessWidget {
  const _SaleSwitch({
    required this.item,
    required this.busy,
    required this.onChanged,
  });

  final CatalogWebItem item;
  final bool busy;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hint = item.kind == CatalogItemKind.consumable
        ? 'Un consumible del taller no se vende online'
        : !item.isActive
            ? 'El producto está inactivo'
            : item.webOn
                ? 'Encendido'
                : 'Apagado';
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: MergeSemantics(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Vender en la web',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Text(hint,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            Switch(
              value: item.webOn,
              onChanged:
                  busy || onChanged == null || !item.isActive && !item.webOn
                      ? null
                      : onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

/// The ladder, step by step, for this item.
class _WhyList extends StatelessWidget {
  const _WhyList({required this.item, required this.rules});

  final CatalogWebItem item;
  final CatalogRules rules;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final steps = <(_Check, String, String)>[];
    final isService = item.kind == CatalogItemKind.service;

    if (item.kind == CatalogItemKind.consumable) {
      steps
        ..add((
          _Check.no,
          'Consumible del taller',
          'Se compra a gasto (5101) y se gasta en los trabajos. La regla se detiene aquí.'
        ))
        ..add((_Check.skip, 'Vender en la web', 'No aplica a un consumible.'))
        ..add(
            (_Check.skip, 'Precio', '${catalogMoney(item.webPrice)} al mesón'))
        ..add((_Check.skip, 'Stock', 'Un consumible no lleva stock.'));
    } else {
      steps.add((
        _Check.yes,
        item.kind.label,
        isService ? 'Se publica en /servicios.' : 'Lleva stock y costo.'
      ));
      steps.add(!item.isActive
          ? (_Check.no, 'Producto inactivo', 'No se ve en ningún lado.')
          : item.webOn
              ? (
                  _Check.yes,
                  '«Vender en la web» encendido',
                  'Lo marcaste para la tienda.'
                )
              : (
                  _Check.no,
                  '«Vender en la web» apagado',
                  'Nadie lo ve en la tienda ni en Google.'
                ));
      if (isService) {
        final priced =
            item.webPrice > 0 || item.priceMode == CatalogPriceMode.quote;
        steps.add(priced
            ? (_Check.yes, 'Precio', item.priceLabel)
            : (
                _Check.no,
                'Sin precio',
                'Un servicio a \$0 no se publica; márcalo «a cotizar» si depende del caso.'
              ));
      } else {
        steps.add(item.hasTaxClassification
            ? (
                _Check.yes,
                'IVA clasificado',
                (item.taxRate ?? 0) > 0 ? 'Afecto 19 %' : 'Exento'
              )
            : (
                _Check.no,
                'Sin IVA clasificado',
                'El checkout y Google piden afecto 19 % o exento.'
              ));
        final min = item.minWebPrice;
        final margin = item.marginPct;
        final detail = [
          catalogMoney(item.webPrice),
          if (min != null) 'costo con IVA ${catalogMoney(min)}',
          if (margin != null) 'margen ${margin.round()} %',
        ].join(' · ');
        steps.add(item.block == 'below_cost'
            ? (_Check.no, 'Precio bajo el costo con IVA', detail)
            : item.webPrice <= 0
                ? (_Check.no, 'Sin precio', 'Un producto a \$0 no se publica.')
                : (
                    _Check.yes,
                    item.onClearance
                        ? 'Precio en liquidación'
                        : 'Precio sobre el costo',
                    detail
                  ));
        final missing = <String>[
          if (!item.hasPhoto) 'foto',
          if (!item.hasWebName) 'nombre para la tienda',
          if (rules.requireDescription && !item.hasDescription) 'descripción',
          if (rules.requireBrand && item.brandId == null) 'marca',
        ];
        final blocking = <String>[
          if (rules.requireImage && !item.hasPhoto) 'foto',
          if (rules.requireWebName && !item.hasWebName) 'nombre para la tienda',
          if (rules.requireDescription && !item.hasDescription) 'descripción',
          if (rules.requireBrand && item.brandId == null) 'marca',
        ];
        steps.add(missing.isEmpty
            ? (_Check.yes, 'Foto y nombre para la tienda', item.displayName)
            : blocking.isNotEmpty
                ? (
                    _Check.no,
                    'Falta ${blocking.join(' y ')}',
                    'La tienda lo pide para venderlo.'
                  )
                : (
                    _Check.warn,
                    'Falta ${missing.join(' y ')}',
                    'Se vende igual, pero se ve peor en la tienda y en Google.'
                  ));
        final stock = item.available;
        steps.add(stock == null
            ? (_Check.yes, 'Sin control de stock', 'Se vende siempre.')
            : stock > 0
                ? (
                    _Check.yes,
                    '$stock ${stock == 1 ? 'disponible' : 'disponibles'}',
                    'Descontando lo reservado por pedidos web.'
                  )
                : (
                    _Check.no,
                    'Sin stock',
                    'La ficha queda visible con «Agotado».'
                  ));
      }
    }

    if (item.block == 'category_hidden') {
      steps.add((
        _Check.no,
        'Su categoría no está en el menú',
        'La regla pide una categoría que se muestre.'
      ));
    }
    // The rule blocks for a step this list does not name: say it anyway.
    if (item.state == CatalogItemState.blocked &&
        !steps.any((step) => step.$1 == _Check.no)) {
      steps.add((_Check.no, item.reason, 'Es lo que hoy impide venderlo.'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'POR QUÉ ESTÁ ASÍ',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 0.8,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        for (final (check, title, detail) in steps)
          _WhyRow(check: check, title: title, detail: detail),
      ],
    );
  }
}

enum _Check { yes, no, warn, skip }

class _WhyRow extends StatelessWidget {
  const _WhyRow(
      {required this.check, required this.title, required this.detail});

  final _Check check;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final scheme = theme.colorScheme;
    final (icon, background, foreground, said) = switch (check) {
      _Check.yes => (
          Icons.check,
          roles.success.container,
          roles.success.onContainer,
          'cumple'
        ),
      _Check.no => (
          Icons.close,
          roles.warning.container,
          roles.warning.onContainer,
          'no cumple'
        ),
      _Check.warn => (
          Icons.priority_high,
          roles.info.container,
          roles.info.onContainer,
          'aviso'
        ),
      _Check.skip => (
          Icons.remove,
          scheme.surfaceContainerHigh,
          scheme.onSurfaceVariant,
          'no aplica'
        ),
    };
    return Semantics(
      label: '$said: $title. $detail',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: roles.hairline)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration:
                  BoxDecoration(color: background, shape: BoxShape.circle),
              child: Icon(icon, size: 14, color: foreground),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  Text(detail,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Tone { warning, info, workshop }

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.tone,
    required this.title,
    required this.body,
    required this.actions,
  });

  final _Tone tone;
  final String title;
  final String body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final scheme = theme.colorScheme;
    final (background, border, foreground) = switch (tone) {
      _Tone.warning => (
          roles.warning.container,
          roles.warning.border,
          roles.warning.onContainer
        ),
      _Tone.info => (
          scheme.surfaceContainerLow,
          scheme.outlineVariant,
          scheme.onSurface
        ),
      _Tone.workshop => (
          scheme.tertiaryContainer,
          scheme.tertiary.withValues(alpha: 0.35),
          scheme.onTertiaryContainer
        ),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600, color: foreground)),
          const SizedBox(height: 4),
          Text(body,
              style: theme.textTheme.bodySmall?.copyWith(color: foreground)),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ],
      ),
    );
  }
}

/// How the customer sees it: the store's own card for goods, the price
/// list's line for a service.
class _Preview extends StatelessWidget {
  const _Preview({required this.item});

  final CatalogWebItem item;

  @override
  Widget build(BuildContext context) {
    final public = item.state == CatalogItemState.selling ||
        item.state == CatalogItemState.soldOut;
    if (item.kind == CatalogItemKind.service) {
      return CatalogStorePreview(
        title:
            public ? 'Así se ve en /servicios' : 'Así se vería en /servicios',
        path: public ? '/servicios' : null,
        child: _ServiceLine(item: item),
      );
    }
    if (item.kind == CatalogItemKind.consumable) return const SizedBox.shrink();
    return CatalogStorePreview(
      title:
          public ? 'Así se ve en vinabike.cl' : 'Así se vería en vinabike.cl',
      path: public ? catalogPublicPath(item) : null,
      note: item.state == CatalogItemState.soldOut
          ? 'En la ficha dice «Agotado» y no tiene carrito.'
          : public
              ? null
              : 'Hoy no está a la venta: ${item.reason.toLowerCase()}.',
      child: Align(
        alignment: Alignment.centerLeft,
        // The card fills its cell: like the store's grid, it needs both.
        child: SizedBox(
          width: 220,
          height: 330,
          child: PremiumProductCard(
            productId: item.id,
            productSku: item.sku,
            productBrand: item.brand,
            name: item.displayName,
            price: item.webPrice,
            imageUrl: item.imageUrl,
            showBrand: item.brand != null,
            interactionsEnabled: false,
          ),
        ),
      ),
    );
  }
}

class _ServiceLine extends StatelessWidget {
  const _ServiceLine({required this.item});

  final CatalogWebItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(item.displayName,
              style:
                  theme.textTheme.bodyLarge?.copyWith(color: Colors.black87)),
        ),
        Text(
          item.webPrice <= 0 && item.priceMode != CatalogPriceMode.quote
              ? 'Consultar'
              : item.priceLabel,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }
}
