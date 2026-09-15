import 'package:flutter/material.dart';

import '../models/purchase_order_summary.dart';
import '../pages/intelligent_purchasing_surfaces.dart';
import '../models/supplier_catalog.dart';
import 'supplier_open_orders_strip.dart';
import 'purchase_visual_language.dart';

/// **La ficha del proveedor, dentro del bloque.**
///
/// Se llega tocando su fila en «A quién le compramos algo así». No es una ruta:
/// la tabla y esta ficha se turnan en el mismo panel, así que volver no pierde
/// el análisis ni la necesidad seleccionada. Salir del bloque para mirar un
/// proveedor y tener que rehacer el camino es lo que hace que nadie lo mire.
///
/// Arriba, quién es y qué le compramos. Abajo, todo lo suyo, con lo comprado
/// separado de lo sólo catalogado —porque un costo de ficha no es un precio
/// pagado— y cada línea con la orden de sumarla al pedido.
class SupplierWorkspaceView extends StatelessWidget {
  const SupplierWorkspaceView({
    super.key,
    required this.page,
    required this.loadingMore,
    required this.searchController,
    required this.addedProductIds,
    this.highlightedProductIds,
    required this.onBack,
    required this.onSearch,
    required this.onLoadMore,
    required this.onToggleLine,
    required this.onOpenPortal,
    required this.onAddPhoto,
    required this.basis,
    required this.onBasisChanged,
    required this.openOrders,
    required this.activeOrderId,
    required this.onResumeOrder,
  });

  /// Con flete o sin flete. Manda en la columna de costo **y** en lo que se
  /// propone al agregar una línea al pedido.
  final PurchaseCostBasis basis;
  final ValueChanged<PurchaseCostBasis> onBasisChanged;

  /// Lo que ya existe con este proveedor. Va arriba, antes del catálogo:
  /// retomar un pedido a medio armar gana a empezar otro.
  final List<PurchaseOrderSummary> openOrders;
  final String? activeOrderId;
  final ValueChanged<PurchaseOrderSummary> onResumeOrder;

  final SupplierCatalogPage page;
  final bool loadingMore;
  final TextEditingController searchController;

  /// Lo que ya está en el pedido. La misma orden sirve para sumar y para
  /// sacar: obligar a buscar el borrador para quitar una línea es exactamente
  /// «navegar a otra parte para arreglar algo».
  final Set<String> addedProductIds;

  final VoidCallback onBack;
  final ValueChanged<String> onSearch;
  final VoidCallback onLoadMore;
  final ValueChanged<SupplierCatalogItem> onToggleLine;
  final VoidCallback onOpenPortal;
  final VoidCallback onAddPhoto;

  /// Los productos que el juicio compartido acepta destacar como coincidencia.
  final Set<String>? highlightedProductIds;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          profile: page.supplier,
          metrics: page.metrics,
          onBack: onBack,
          onOpenPortal: onOpenPortal,
          onAddPhoto: onAddPhoto,
        ),
        const SizedBox(height: 10),
        SupplierOpenOrdersStrip(
          orders: openOrders,
          activeOrderId: activeOrderId,
          onResume: onResumeOrder,
        ),
        Row(
          children: [
            Expanded(
              child: _SearchField(
                controller: searchController,
                total: page.total,
                onSearch: onSearch,
              ),
            ),
            const SizedBox(width: 12),
            PurchaseCostBasisToggle(value: basis, onChanged: onBasisChanged),
          ],
        ),
        const SizedBox(height: 8),
        if (page.isEmpty)
          PurchasePanel(
            child: Text(
              searchController.text.trim().isEmpty
                  ? 'No hay productos comprados ni catalogados de este '
                      'proveedor todavía.'
                  : 'Nada de este proveedor calza con '
                      '«${searchController.text.trim()}».',
              style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
            ),
          )
        else
          _CatalogTable(
            items: page.items,
            addedProductIds: addedProductIds,
            onToggleLine: onToggleLine,
            needPhrase: page.needPhrase,
            highlightedProductIds: highlightedProductIds,
            widenedLabel: page.widenedLabel,
            basis: basis,
          ),
        if (page.hasMore) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.center,
            child: loadingMore
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : PurchaseInlineAction(
                    key: const ValueKey('supplier-catalog-load-more'),
                    label: 'Ver ${page.total - page.items.length} más',
                    onPressed: onLoadMore,
                  ),
          ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.profile,
    required this.metrics,
    required this.onBack,
    required this.onOpenPortal,
    required this.onAddPhoto,
  });

  final SupplierProfile profile;
  final SupplierCatalogMetrics metrics;
  final VoidCallback onBack;
  final VoidCallback onOpenPortal;
  final VoidCallback onAddPhoto;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return PurchasePanel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Con poco ancho las métricas bajan en vez de encogerse: un número
          // partido no compara, y comparar es para lo único que están.
          final side = constraints.maxWidth >= 760;
          final identity = _Identity(
            profile: profile,
            onBack: onBack,
            onOpenPortal: onOpenPortal,
            onAddPhoto: onAddPhoto,
          );
          final numbers = _Metrics(metrics: metrics);
          if (!side) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                identity,
                const SizedBox(height: 14),
                Divider(height: 1, color: tokens.hair),
                const SizedBox(height: 12),
                numbers,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 42, child: identity),
              const SizedBox(width: 20),
              Expanded(flex: 58, child: numbers),
            ],
          );
        },
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({
    required this.profile,
    required this.onBack,
    required this.onOpenPortal,
    required this.onAddPhoto,
  });

  final SupplierProfile profile;
  final VoidCallback onBack;
  final VoidCallback onOpenPortal;
  final VoidCallback onAddPhoto;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final detalle = <String>[
      if (profile.city != null) profile.city!,
      if (profile.rut != null) profile.rut!,
      if (profile.paymentTerms != null) profile.paymentTerms!,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // La vuelta va arriba y a la izquierda, antes que nada: el operador
        // entró desde una tabla y tiene que ver la salida sin buscarla.
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: PurchaseInlineAction(
            key: const ValueKey('supplier-workspace-back'),
            label: '‹  Volver a los proveedores',
            onPressed: onBack,
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Portrait(profile: profile, onAddPhoto: onAddPhoto),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    style:
                        PurchaseType.sectionTitle.copyWith(color: tokens.ink),
                  ),
                  if (profile.legalName != null &&
                      profile.legalName != profile.name)
                    Text(
                      profile.legalName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
                    ),
                  if (detalle.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        detalle.join(' · '),
                        maxLines: 2,
                        style:
                            PurchaseType.meta.copyWith(color: tokens.inkFaint),
                      ),
                    ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (profile.salesRepName != null)
                        Text(
                          profile.salesRepName!,
                          style: PurchaseType.meta
                              .copyWith(color: tokens.inkMuted),
                        ),
                      // Por dónde se le escribe, dicho acá y no en el último
                      // paso: sólo 25 de 91 proveedores tienen teléfono, y
                      // descubrirlo al momento de enviar es descubrirlo tarde.
                      Text(
                        profile.canReceiveMessage
                            ? profile.salesRepPhone!
                            : 'sin teléfono para enviarle el pedido',
                        style: PurchaseType.meta.copyWith(
                          color: profile.canReceiveMessage
                              ? tokens.inkMuted
                              : tokens.inkFaint,
                        ),
                      ),
                      if (profile.website != null)
                        PurchaseInlineAction(
                          key: const ValueKey('supplier-workspace-portal'),
                          label: profile.hasPortalAccount
                              ? 'Entrar al portal'
                              : 'Abrir el sitio',
                          onPressed: onOpenPortal,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (profile.purchaseInstructions != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            decoration: BoxDecoration(
              color: tokens.sunken,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: tokens.hair),
            ),
            child: Text(
              profile.purchaseInstructions!,
              style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
            ),
          ),
        ],
      ],
    );
  }
}

/// El retrato del proveedor.
///
/// **Ninguno de los 91 proveedores del taller tiene imagen hoy.** Un marco
/// vacío en todas las fichas sería un defecto repetido 91 veces, así que el
/// monograma es el estado normal —las mismas dos letras de la tabla, para
/// reconocer de qué fila se vino— y agregar la foto es una orden que vive acá,
/// donde se nota que falta.
class _Portrait extends StatefulWidget {
  const _Portrait({required this.profile, required this.onAddPhoto});

  final SupplierProfile profile;
  final VoidCallback onAddPhoto;

  @override
  State<_Portrait> createState() => _PortraitState();
}

class _PortraitState extends State<_Portrait> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final url = widget.profile.imageUrl;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onAddPhoto,
        child: Tooltip(
          message: url == null
              ? 'Agregar la foto de ${widget.profile.name}'
              : 'Cambiar la foto de ${widget.profile.name}',
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: tokens.sunken,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _hovering ? tokens.act : tokens.border,
              ),
              image: url == null
                  ? null
                  : DecorationImage(
                      image: NetworkImage(url),
                      fit: BoxFit.cover,
                    ),
            ),
            alignment: Alignment.center,
            child: url != null
                ? null
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 140),
                    child: _hovering
                        ? Icon(
                            Icons.add_photo_alternate_outlined,
                            key: const ValueKey('add'),
                            size: 20,
                            color: tokens.act,
                          )
                        : Text(
                            widget.profile.monogram,
                            key: const ValueKey('monogram'),
                            style: PurchaseType.sectionTitle
                                .copyWith(color: tokens.inkMuted),
                          ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({required this.metrics});

  final SupplierCatalogMetrics metrics;

  @override
  Widget build(BuildContext context) {
    if (!metrics.hasHistory) {
      final tokens = PurchaseTokens.of(context);
      return Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Nunca le hemos comprado. Lo de abajo es lo que tiene catalogado, no '
          'historial.',
          style: PurchaseType.meta.copyWith(color: tokens.inkFaint),
        ),
      );
    }
    return Wrap(
      spacing: 22,
      runSpacing: 12,
      alignment: WrapAlignment.end,
      children: [
        _Metric(
          value: '${metrics.purchaseLines}',
          caption: metrics.purchaseLines == 1
              ? 'línea de compra'
              : 'líneas de compra',
        ),
        _Metric(
          value: '${metrics.purchaseInvoices}',
          caption: metrics.purchaseInvoices == 1 ? 'factura' : 'facturas',
        ),
        _Metric(
          value: '${metrics.distinctProducts}',
          caption: 'productos distintos',
        ),
        _Metric(
          value: PurchaseMoney.format(metrics.landedSpendNet, 'CLP'),
          caption: 'con flete prorrateado',
          emphasis: true,
        ),
        _Metric(
          value: metrics.lastPurchaseAt == null
              ? '—'
              : SupplierDates.relative(metrics.lastPurchaseAt!),
          caption: 'última compra',
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.value,
    required this.caption,
    this.emphasis = false,
  });

  final String value;
  final String caption;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: PurchaseType.metricMedium.copyWith(
            color: emphasis ? tokens.act : tokens.ink,
            fontFeatures: PurchaseType.tabular,
          ),
        ),
        Text(
          caption,
          style: PurchaseType.meta.copyWith(color: tokens.inkFaint),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.total,
    required this.onSearch,
  });

  final TextEditingController controller;
  final int total;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            onSubmitted: onSearch,
            onChanged: onSearch,
            style: PurchaseType.meta.copyWith(color: tokens.ink),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search, size: 16, color: tokens.inkFaint),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 32, minHeight: 28),
              hintText: 'Buscar en sus $total productos',
              hintStyle: PurchaseType.meta.copyWith(color: tokens.inkFaint),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
              filled: true,
              fillColor: tokens.sunken,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(7),
                borderSide: BorderSide(color: tokens.hair),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(7),
                borderSide: BorderSide(color: tokens.hair),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// El catálogo del proveedor, **encabezado por lo que se estaba buscando**.
///
/// Se entra a la ficha desde una necesidad concreta —«Cámaras 29 con válvula
/// Schrader»— y la primera versión abría con una cámara 26: ignoraba el motivo
/// por el que el operador llegó ahí y lo obligaba a buscar de nuevo a mano.
///
/// Lo que coincide va arriba, bajo su propio rótulo y con las palabras de la
/// necesidad. El resto del catálogo sigue abajo, porque a veces se entra
/// justamente a mirar qué más tiene. Y dentro de cada grupo, lo comprado antes
/// que lo sólo catalogado: un costo de ficha no es un precio pagado.
class _CatalogTable extends StatelessWidget {
  const _CatalogTable({
    required this.items,
    required this.addedProductIds,
    required this.onToggleLine,
    required this.needPhrase,
    this.highlightedProductIds,
    required this.widenedLabel,
    required this.basis,
  });

  final String? needPhrase;

  /// Los productos que el juicio compartido acepta destacar. `null` cuando no
  /// hay ficha con que juzgar: entonces manda lo que dijo el servidor.
  final Set<String>? highlightedProductIds;
  final String? widenedLabel;
  final PurchaseCostBasis basis;
  final List<SupplierCatalogItem> items;
  final Set<String> addedProductIds;
  final ValueChanged<SupplierCatalogItem> onToggleLine;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    // **El mismo juicio que la lista de proveedores decide qué se destaca.**
    // `supplier_catalog_page_v1` marca `matchesNeed` con un criterio propio y
    // ancho; lo que no pasa la compuerta compartida no se esconde, baja al
    // resto del catálogo, que sigue accesible y paginado igual.
    final destacados = highlightedProductIds;
    final coinciden = items
        .where((item) => destacados == null
            ? item.matchesNeed
            : destacados.contains(item.productId))
        .toList();
    final resto = items.where((item) => !coinciden.contains(item)).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final medium = constraints.maxWidth >= 540;
        return PurchasePanel(
          padded: false,
          child: Column(
            key: const ValueKey('supplier-catalog-table'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: tokens.sunken,
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                child: Row(
                  children: [
                    const SizedBox(
                      width: PurchaseSurfaceGeometry.mediaTableRow + 10,
                    ),
                    Expanded(
                      flex: 34,
                      child: Text(
                        'PRODUCTO',
                        style:
                            PurchaseType.label.copyWith(color: tokens.inkFaint),
                      ),
                    ),
                    if (wide)
                      Expanded(
                        flex: 16,
                        child: Text(
                          'ÚLTIMA COMPRA',
                          textAlign: TextAlign.end,
                          style: PurchaseType.label
                              .copyWith(color: tokens.inkFaint),
                        ),
                      ),
                    Expanded(
                      flex: 16,
                      child: Text(
                        'COSTO UNITARIO',
                        textAlign: TextAlign.end,
                        style:
                            PurchaseType.label.copyWith(color: tokens.inkFaint),
                      ),
                    ),
                    if (medium)
                      Expanded(
                        flex: 12,
                        child: Text(
                          'EN BODEGA',
                          textAlign: TextAlign.end,
                          style: PurchaseType.label
                              .copyWith(color: tokens.inkFaint),
                        ),
                      ),
                    const SizedBox(width: 16),
                    SizedBox(width: _addWidth(context)),
                  ],
                ),
              ),
              if (coinciden.isNotEmpty)
                _GroupHeader(
                  label: needPhrase == null
                      ? 'COINCIDE CON LO QUE BUSCAS'
                      : 'COINCIDE CON «${needPhrase!.toUpperCase()}»',
                  // El rótulo no puede prometer una coincidencia exacta sobre
                  // un resultado ampliado.
                  note: widenedLabel,
                  first: true,
                ),
              for (final item in coinciden)
                _CatalogRow(
                  item: item,
                  added: addedProductIds.contains(item.productId),
                  wide: wide,
                  medium: medium,
                  basis: basis,
                  onToggle: () => onToggleLine(item),
                ),
              if (coinciden.isNotEmpty && resto.isNotEmpty)
                const _GroupHeader(label: 'EL RESTO DE SU CATÁLOGO'),
              for (final item in resto)
                _CatalogRow(
                  item: item,
                  added: addedProductIds.contains(item.productId),
                  wide: wide,
                  medium: medium,
                  basis: basis,
                  onToggle: () => onToggleLine(item),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// La separación entre grupos: un rótulo, no un lote aparte. El dueño lo pidió
/// así — «no las juntes todas en el mismo lote, por último una separación».
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.label,
    this.note,
    this.first = false,
  });

  final String label;
  final String? note;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(13, first ? 8 : 11, 13, 5),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: first ? tokens.hair : tokens.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PurchaseType.label.copyWith(color: tokens.inkFaint),
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Búsqueda ampliada: $note',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PurchaseType.meta.copyWith(color: tokens.inkFaint),
              ),
            ),
        ],
      ),
    );
  }
}

double _addWidth(BuildContext context) =>
    purchaseInlineActionWidth(context, const ['Agregar', 'Quitar']);

class _CatalogRow extends StatelessWidget {
  const _CatalogRow({
    required this.item,
    required this.added,
    required this.wide,
    required this.medium,
    required this.basis,
    required this.onToggle,
  });

  final SupplierCatalogItem item;
  final bool added;
  final bool wide;
  final bool medium;
  final PurchaseCostBasis basis;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final identidad = <String>[
      if (item.brand != null) item.brand!,
      if (item.sku != null) 'SKU ${item.sku}',
    ];
    final costo = item.suggestedUnitCostNet(withFreight: basis.includesFreight);
    final deFicha =
        item.suggestedCostIsCatalog(withFreight: basis.includesFreight);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        // Lo que ya está en el pedido se reconoce sin leer: la fila se tiñe.
        color: added ? tokens.selected : Colors.transparent,
        border: Border(top: BorderSide(color: tokens.hair)),
      ),
      child: Row(
        children: [
          _ProductThumb(item: item),
          const SizedBox(width: 10),
          Expanded(
            flex: 34,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PurchaseType.rowTitle.copyWith(color: tokens.ink),
                ),
                if (identidad.isNotEmpty)
                  Text(
                    identidad.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PurchaseType.meta.copyWith(color: tokens.inkFaint),
                  ),
              ],
            ),
          ),
          if (wide)
            _Value(
              flex: 16,
              value: item.lastPurchaseAt == null
                  ? '—'
                  : SupplierDates.relative(item.lastPurchaseAt!),
              caption: item.lastInvoiceNumber == null
                  ? (item.wasPurchased ? '' : 'sin compras')
                  : 'factura ${item.lastInvoiceNumber}',
            ),
          _Value(
            flex: 16,
            value: costo == null ? '—' : PurchaseMoney.format(costo, 'CLP'),
            // El rótulo distingue lo pagado de lo declarado. Sin esto, un costo
            // de ficha que nadie verificó se lee como precio de compra.
            caption: costo == null
                ? 'sin costo'
                : deFicha
                    ? 'de ficha, no pagado'
                    : basis.rowCaption,
            emphasis: !deFicha && costo != null,
          ),
          if (medium)
            _Value(
              flex: 12,
              value: item.available == null ? '—' : _quantity(item.available!),
              caption: (item.available ?? 0) > 0 ? 'unidades' : 'sin stock',
            ),
          const SizedBox(width: 16),
          SizedBox(
            width: _addWidth(context),
            child: Align(
              alignment: Alignment.centerRight,
              child: PurchaseInlineAction(
                key: ValueKey('supplier-catalog-add-${item.productId}'),
                label: added ? 'Quitar' : 'Agregar',
                onPressed: onToggle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _quantity(double value) =>
      value == value.roundToDouble() ? value.round().toString() : '$value';
}

class _Value extends StatelessWidget {
  const _Value({
    required this.flex,
    required this.value,
    required this.caption,
    this.emphasis = false,
  });

  final int flex;
  final String value;
  final String caption;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Expanded(
      flex: flex,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PurchaseType.metricSmall.copyWith(
              color: emphasis ? tokens.act : tokens.ink,
              fontFeatures: PurchaseType.tabular,
            ),
          ),
          if (caption.isNotEmpty)
            Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PurchaseType.meta.copyWith(color: tokens.inkFaint),
            ),
        ],
      ),
    );
  }
}

/// La foto del producto, con la misma geometría del contrato de imagen.
///
/// **Acá la foto es el caso común**: 1.365 de los 1.612 productos del taller
/// tienen una. Es al revés que la foto del proveedor, donde no hay ninguna y el
/// monograma es el estado normal. Cuando falta, el monograma ocupa exactamente
/// el mismo espacio para que la fila no cambie de alto ni la columna se corra.
class _ProductThumb extends StatelessWidget {
  const _ProductThumb({required this.item});

  final SupplierCatalogItem item;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    const side = PurchaseSurfaceGeometry.mediaTableRow;
    final radius = BorderRadius.circular(PurchaseSurfaceGeometry.mediaRadius);
    final url = item.imageUrl;
    return Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
        color: tokens.sunken,
        borderRadius: radius,
        border: Border.all(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: url == null
          ? _monogram(tokens)
          : Image.network(
              url,
              width: side,
              height: side,
              fit: BoxFit.cover,
              // Una foto que no baja no puede dejar un hueco distinto: cae al
              // monograma, que mide lo mismo.
              errorBuilder: (context, error, stack) => _monogram(tokens),
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : _monogram(tokens),
            ),
    );
  }

  Widget _monogram(PurchaseTokens tokens) {
    final words = item.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    final letters = switch (words.length) {
      0 => '?',
      1 => words.first.length >= 2
          ? words.first.substring(0, 2).toUpperCase()
          : words.first.toUpperCase(),
      _ => '${words[0][0]}${words[1][0]}'.toUpperCase(),
    };
    return Text(
      letters,
      style: PurchaseType.label.copyWith(color: tokens.inkFaint),
    );
  }
}

/// «hace 3 meses». Los meses van escritos acá y no por `intl`: la ficha se abre
/// dentro de una fila y una inicialización de locale que falle la dejaría en
/// blanco justo cuando el operador la abrió.
class SupplierDates {
  const SupplierDates._();

  static String relative(DateTime value) {
    final dias = DateTime.now().difference(value.toLocal()).inDays;
    if (dias <= 0) return 'hoy';
    if (dias == 1) return 'ayer';
    if (dias < 30) return 'hace $dias días';
    final meses = (dias / 30).floor();
    if (meses < 12) {
      return meses == 1 ? 'hace 1 mes' : 'hace $meses meses';
    }
    final anios = (dias / 365).floor();
    return anios == 1 ? 'hace 1 año' : 'hace $anios años';
  }
}
