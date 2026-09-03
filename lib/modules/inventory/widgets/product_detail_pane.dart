import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/vb_money_text.dart';
import '../../../shared/widgets/vb_skeleton.dart';
import '../../../shared/widgets/vb_status_badge.dart';
import '../../../shared/widgets/vb_sub_tabs.dart';
import '../../../shared/widgets/vb_surface_icon_button.dart';
import '../models/inventory_models.dart';
import '../utils/product_margin.dart';
import '../utils/product_set_inventory_projection.dart';
import 'product_image_viewer.dart';

enum ProductDetailPaneTab { details, movements }

/// Panel de detalle del split pane de Productos / Servicios.
///
/// Responde, sin abrir la ficha completa, lo que el operador pregunta al
/// seleccionar una fila: cómo se identifica (SKU, código del proveedor, código
/// de barras), cuánto deja (precio, costo, margen neto), cuánto hay y dónde
/// (stock, mínimo, ubicación, valor a costo, componentes del juego), dónde se
/// vende (tienda web, Google Merchant, catálogo WhatsApp) y qué dice su ficha
/// (descripción, atributos, especificaciones, etiquetas).
///
/// La lista trae una proyección corta del producto ([product]); el host la
/// hidrata con la fila completa ([fullRecord]) para las secciones que la
/// necesitan. Mientras llega, esas secciones muestran el esqueleto `X-01`; si
/// no llega, el panel muestra lo que la lista ya sabe y no inventa el resto.
///
/// Anatomía: cabecera fija con `T-04` (Detalles · Movimientos) y cerrar `A-02`,
/// cuerpo con scroll propio y pie fijo con un solo primario, como publica
/// `O-04`. Filas de rótulo/valor de 34 con hairline, como el detalle de `T-05`.
/// Tipografía `F-02` (recordTitle, sectionTitle, label, bodyM; códigos y
/// cantidades en mono tabular), escala `F-04`, estados `E-01`, dinero `F-03`.
class ProductDetailPane extends StatefulWidget {
  const ProductDetailPane({
    super.key,
    required this.product,
    required this.fullRecord,
    required this.isLoadingFullRecord,
    required this.isServicesScope,
    required this.effectiveStock,
    required this.setAvailability,
    required this.quantityInSetByComponentId,
    required this.onClose,
    required this.onEdit,
    this.onFilterByCategory,
    this.onFilterByBrand,
    this.onFilterBySupplier,
    this.storeProductUri,
    this.onOpenUri,
    this.supplierProductUri,
    this.onOpenSupplierProduct,
    this.movementsBuilder,
  });

  static const Key paneKey = Key('product-detail-pane');
  static const Key closeKey = Key('product-detail-close');
  static const Key imageKey = Key('product-detail-image');
  static const Key editKey = Key('product-detail-edit');
  static const Key openStoreKey = Key('product-detail-open-store');
  static const Key descriptionToggleKey =
      Key('product-detail-description-toggle');
  static const Key specsToggleKey = Key('product-detail-specs-toggle');
  static const Key supplierProductLinkKey =
      Key('product-detail-supplier-product-link');
  static Key copyKey(String field) => Key('product-detail-copy-$field');
  static Key filterKey(String field) => Key('product-detail-filter-$field');
  static Key thumbnailKey(int index) => Key('product-detail-thumb-$index');

  /// Cuántas especificaciones se muestran antes de «Ver todas».
  static const int specsPreviewCount = 6;

  /// Largo a partir del cual la descripción se pliega a tres líneas.
  static const int descriptionFoldLength = 180;

  /// La fila corta que trae la lista.
  final Product product;

  /// La fila completa, cuando el host ya la trajo.
  final Product? fullRecord;
  final bool isLoadingFullRecord;
  final bool isServicesScope;

  /// Stock que la lista muestra para esta fila (juegos completos si es juego).
  final int effectiveStock;
  final ProductSetAvailabilityProjection? setAvailability;
  final Map<String, int> quantityInSetByComponentId;

  final VoidCallback onClose;
  final VoidCallback onEdit;
  final ValueChanged<String>? onFilterByCategory;
  final ValueChanged<String>? onFilterByBrand;
  final ValueChanged<String>? onFilterBySupplier;

  /// Dirección pública del producto en la tienda, si está publicado y la
  /// tienda tiene dirección configurada.
  final Uri? storeProductUri;
  final ValueChanged<Uri>? onOpenUri;

  /// La ficha de este producto en el portal del proveedor, armada con la
  /// plantilla por código de su sonda. Con ella, el código de proveedor abre
  /// esa página en el navegador del ERP (que entra solo si la sesión venció).
  final Uri? supplierProductUri;
  final ValueChanged<Uri>? onOpenSupplierProduct;

  /// Contenido de la pestaña Movimientos; `null` la oculta (servicios).
  final WidgetBuilder? movementsBuilder;

  @override
  State<ProductDetailPane> createState() => _ProductDetailPaneState();
}

class _ProductDetailPaneState extends State<ProductDetailPane> {
  ProductDetailPaneTab _tab = ProductDetailPaneTab.details;
  int _imageIndex = 0;
  bool _showFullDescription = false;
  bool _showAllSpecs = false;

  // El cuerpo tiene scroll propio; la barra y la vista comparten el mismo
  // controlador para no depender del PrimaryScrollController del host.
  final ScrollController _bodyScroll = ScrollController();

  Product get _record => widget.fullRecord ?? widget.product;

  @override
  void dispose() {
    _bodyScroll.dispose();
    super.dispose();
  }

  List<String> get _imageUrls {
    final urls = <String>[];
    void add(String? url) {
      final value = url?.trim() ?? '';
      if (value.isNotEmpty && !urls.contains(value)) urls.add(value);
    }

    add(_record.imageUrl);
    _record.additionalImages.forEach(add);
    _record.websiteImageUrls.forEach(add);
    return urls;
  }

  @override
  void didUpdateWidget(covariant ProductDetailPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changedProduct = oldWidget.product.id != widget.product.id ||
        oldWidget.product.sku != widget.product.sku;
    if (changedProduct) {
      _tab = ProductDetailPaneTab.details;
      _imageIndex = 0;
      _showFullDescription = false;
      _showAllSpecs = false;
    }
    if (_imageIndex >= _imageUrls.length) _imageIndex = 0;
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('$label copiado')),
    );
  }

  void _openViewer() {
    final urls = _imageUrls;
    if (urls.isEmpty) return;
    ProductImageViewer.show(
      context,
      title: _record.name,
      imageUrls: urls,
      initialIndex: _imageIndex,
    );
  }

  // ---------------------------------------------------------------------------
  // Estados derivados del porqué, no del número.

  ({String label, VbStatusTone tone})? _stockState() {
    final product = widget.product;
    if (product.isService) return null;
    if (!product.tracksInventory) {
      return (label: 'Consumible de taller', tone: VbStatusTone.neutral);
    }
    if (product.isSet) {
      final availability = widget.setAvailability;
      if (availability == null || !availability.isConfigured) {
        return (label: 'Juego sin componentes', tone: VbStatusTone.danger);
      }
      if (availability.hasNegativeComponentStock) {
        return (label: 'Componentes en negativo', tone: VbStatusTone.danger);
      }
      if (availability.completeSetsAvailable <= 0) {
        return (label: 'Sin juegos completos', tone: VbStatusTone.danger);
      }
      if (availability.hasPartialStock) {
        return (label: 'Con piezas sueltas', tone: VbStatusTone.warning);
      }
      return (label: 'En stock', tone: VbStatusTone.success);
    }
    if (widget.effectiveStock <= 0) {
      return (label: 'Sin stock', tone: VbStatusTone.danger);
    }
    if (widget.effectiveStock <= product.minStockLevel) {
      return (label: 'Stock bajo', tone: VbStatusTone.warning);
    }
    return (label: 'En stock', tone: VbStatusTone.success);
  }

  ({String label, VbStatusTone tone}) _whatsappState() {
    final product = _record;
    if (!product.isWhatsappCatalog) {
      return (label: 'No incluido', tone: VbStatusTone.neutral);
    }
    return switch (product.whatsappCatalogSyncStatus) {
      'customer_visible' => (
          label: 'Sincronizado',
          tone: VbStatusTone.success,
        ),
      'under_review' => (label: 'En revisión', tone: VbStatusTone.warning),
      'rejected' => (label: 'Rechazado', tone: VbStatusTone.danger),
      'failed' => (label: 'Con error', tone: VbStatusTone.danger),
      'removed' => (label: 'Retirado', tone: VbStatusTone.neutral),
      _ => (label: 'Pendiente', tone: VbStatusTone.warning),
    };
  }

  static String formatPercent(double value) =>
      '${value.toStringAsFixed(1).replaceAll('.', ',')}%';

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final hasMovements = widget.movementsBuilder != null;
    final showingDetails =
        _tab == ProductDetailPaneTab.details || !hasMovements;

    return Container(
      key: ProductDetailPane.paneKey,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(left: BorderSide(color: roles.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(theme, roles, hasMovements),
          Expanded(
            child: showingDetails
                ? _buildDetails(theme, roles)
                : widget.movementsBuilder!(context),
          ),
          if (showingDetails) _buildFooter(theme, roles),
        ],
      ),
    );
  }

  Widget _buildHeader(
    ThemeData theme,
    VinabikeThemeRoles roles,
    bool hasMovements,
  ) {
    // T-04 pinta su propio subrayado sobre el hairline; el hairline del
    // resto de la cabecera se dibuja debajo, en la misma fila de píxeles,
    // para que no queden dos líneas bajo las pestañas.
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 1,
          child: ColoredBox(color: roles.hairline),
        ),
        Padding(
          // T-05 · cabecera del detalle sobre padding 12 (F-04).
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: VbSubTabs<ProductDetailPaneTab>(
                  tabs: [
                    const VbSubTab(
                      value: ProductDetailPaneTab.details,
                      label: 'Detalles',
                    ),
                    if (hasMovements)
                      const VbSubTab(
                        value: ProductDetailPaneTab.movements,
                        label: 'Movimientos',
                      ),
                  ],
                  value: hasMovements ? _tab : ProductDetailPaneTab.details,
                  onChanged: (tab) => setState(() => _tab = tab),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: VbSurfaceIconButton(
                  buttonKey: ProductDetailPane.closeKey,
                  icon: Icons.close,
                  tooltip: 'Cerrar panel',
                  onPressed: widget.onClose,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(ThemeData theme, VinabikeThemeRoles roles) {
    return Container(
      // O-04 · pie fijo con un solo primario. Padding 12/18 (F-04).
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: roles.hairline)),
      ),
      child: SizedBox(
        key: ProductDetailPane.editKey,
        width: double.infinity,
        child: AppButton(
          text: widget.isServicesScope ? 'Editar servicio' : 'Editar producto',
          icon: Icons.edit_outlined,
          onPressed: widget.onEdit,
        ),
      ),
    );
  }

  Widget _buildDetails(ThemeData theme, VinabikeThemeRoles roles) {
    final product = widget.product;
    final record = _record;
    final type = _PaneType(theme, roles);
    final sections = <Widget>[
      _buildImageBlock(theme, roles, type),
      const SizedBox(height: 16),
      Text(record.name, style: type.recordTitle),
      const SizedBox(height: 6),
      _buildMetaLine(theme, roles, type),
      const SizedBox(height: 8),
      _buildBadges(),
      const SizedBox(height: 16),
      _Section(
        title: 'Códigos',
        type: type,
        roles: roles,
        children: _buildCodeRows(type, roles),
      ),
      const SizedBox(height: 16),
      _Section(
        title: 'Precios',
        type: type,
        roles: roles,
        children: _buildPriceRows(type, roles),
      ),
    ];

    // Un consumible de taller ya lo dice su insignia; una sección de
    // inventario para repetirlo sería ruido.
    if (product.tracksInventory) {
      sections.addAll([
        const SizedBox(height: 16),
        _Section(
          title: 'Inventario',
          type: type,
          roles: roles,
          children: _buildInventoryRows(type, roles),
        ),
      ]);
      final components = widget.setAvailability?.components ?? const [];
      if (product.isSet && components.isNotEmpty) {
        sections.addAll([
          const SizedBox(height: 16),
          _Section(
            title: 'Componentes del juego',
            type: type,
            roles: roles,
            children: [
              for (final component in components)
                _DetailRow(
                  label: _componentLabel(component),
                  value: Text(
                    '${component.inventoryQty} un.',
                    style: type.mono,
                  ),
                ),
            ],
          ),
        ]);
      }
    }

    sections.addAll([
      const SizedBox(height: 16),
      _Section(
        title: 'Canales',
        type: type,
        roles: roles,
        children: _buildChannelRows(type, roles),
      ),
    ]);

    final ficha = _buildFichaChildren(theme, roles, type);
    if (ficha.isNotEmpty) {
      sections.addAll([
        const SizedBox(height: 16),
        _Section(
          title: 'Ficha',
          type: type,
          roles: roles,
          children: ficha,
        ),
      ]);
    }

    sections.addAll([
      const SizedBox(height: 16),
      Text.rich(
        TextSpan(
          text: 'Actualizado el ',
          style: type.faint,
          children: [
            TextSpan(
              text: ChileanUtils.formatDate(record.updatedAt),
              style: type.monoFaint,
            ),
          ],
        ),
      ),
    ]);

    return Scrollbar(
      controller: _bodyScroll,
      child: SingleChildScrollView(
        controller: _bodyScroll,
        // Cuerpo con scroll propio (O-04). Padding 16/18 (F-04).
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: sections,
        ),
      ),
    );
  }

  String _componentLabel(Product component) {
    final id = component.id;
    final quantity =
        id == null ? 1 : (widget.quantityInSetByComponentId[id] ?? 1);
    return quantity > 1 ? '$quantity× ${component.name}' : component.name;
  }

  // ---------------------------------------------------------------------------
  // Imagen

  Widget _buildImageBlock(
    ThemeData theme,
    VinabikeThemeRoles roles,
    _PaneType type,
  ) {
    final urls = _imageUrls;
    final scheme = theme.colorScheme;
    final frame = BoxDecoration(
      color: scheme.surfaceContainerLow,
      // F-04 · radio panel 10, hairline 1.
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: roles.hairline),
    );

    if (urls.isEmpty) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: DecoratedBox(
          decoration: frame,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.image_not_supported_outlined,
                  size: 28,
                  color: roles.faintForeground,
                ),
                const SizedBox(height: 6),
                Text('Sin imagen', style: type.faint),
              ],
            ),
          ),
        ),
      );
    }

    final current = urls[_imageIndex.clamp(0, urls.length - 1)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Semantics(
            button: true,
            image: true,
            label: 'Imagen de ${_record.name}. Ver imagen grande',
            excludeSemantics: true,
            child: InkWell(
              key: ProductDetailPane.imageKey,
              onTap: _openViewer,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                decoration: frame,
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      current,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          size: 28,
                          color: roles.faintForeground,
                        ),
                      ),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: IgnorePointer(
                        // Sólo afordancia: el toque lo recibe toda la imagen.
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(
                              VbSurfaceIconButton.radius,
                            ),
                            border: Border.all(color: roles.hairline),
                          ),
                          child: SizedBox(
                            width: VbSurfaceIconButton.box,
                            height: VbSurfaceIconButton.box,
                            child: Icon(
                              Icons.zoom_in,
                              size: VbSurfaceIconButton.glyph,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (urls.length > 1) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < urls.length; i++)
                ProductImageThumbnail(
                  key: ProductDetailPane.thumbnailKey(i),
                  imageUrl: urls[i],
                  selected: i == _imageIndex,
                  semanticLabel: 'Mostrar imagen ${i + 1} de ${urls.length}',
                  onTap: () => setState(() => _imageIndex = i),
                ),
            ],
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Identidad

  Widget _buildMetaLine(
    ThemeData theme,
    VinabikeThemeRoles roles,
    _PaneType type,
  ) {
    final record = _record;
    final noun = widget.isServicesScope ? 'servicios' : 'productos';
    final parts = <Widget>[];

    void addPart({
      required String text,
      required String field,
      required String? id,
      required ValueChanged<String>? onFilter,
      required String tooltip,
    }) {
      if (text.trim().isEmpty) return;
      final canFilter = id != null && id.isNotEmpty && onFilter != null;
      parts.add(
        canFilter
            ? _MetaLink(
                linkKey: ProductDetailPane.filterKey(field),
                label: text,
                tooltip: tooltip,
                style: type.link,
                onTap: () => onFilter(id),
              )
            : Text(text, style: type.meta),
      );
    }

    addPart(
      text: record.brand ?? '',
      field: 'brand',
      id: record.brandId,
      onFilter: widget.onFilterByBrand,
      tooltip: 'Ver todos los $noun de ${record.brand}',
    );
    addPart(
      text: record.categoryName ?? '',
      field: 'category',
      id: record.categoryId,
      onFilter: widget.onFilterByCategory,
      tooltip: 'Ver toda la categoría ${record.categoryName}',
    );
    addPart(
      text: record.supplierName ?? '',
      field: 'supplier',
      id: record.supplierId,
      onFilter: widget.onFilterBySupplier,
      tooltip: 'Ver todo lo de ${record.supplierName}',
    );

    if (parts.isEmpty) {
      return Text(
        widget.isServicesScope
            ? 'Sin categoría'
            : 'Sin marca, categoría ni proveedor',
        style: type.faint,
      );
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        for (var i = 0; i < parts.length; i++) ...[
          if (i > 0) Text('·', style: type.meta),
          parts[i],
        ],
      ],
    );
  }

  Widget _buildBadges() {
    final badges = <Widget>[];
    final stock = _stockState();
    if (stock != null) {
      badges.add(VbStatusBadge(label: stock.label, tone: stock.tone));
    }
    if (!widget.product.isActive) {
      badges.add(
        const VbStatusBadge(label: 'Inactivo', tone: VbStatusTone.danger),
      );
    }
    if (badges.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 6, children: badges);
  }

  // ---------------------------------------------------------------------------
  // Filas

  List<Widget> _buildCodeRows(_PaneType type, VinabikeThemeRoles roles) {
    final record = _record;
    final barcode = (record.barcode ?? '').trim().isNotEmpty
        ? record.barcode!.trim()
        : (record.gtin ?? '').trim();
    final supplierName = (record.supplierName ?? '').trim();
    return [
      _copyRow('SKU', 'sku', record.sku, type, roles),
      _copyRow(
        'Código proveedor',
        'supplier-code',
        record.supplierCode ?? '',
        type,
        roles,
        openUri: widget.supplierProductUri,
        onOpen: widget.onOpenSupplierProduct,
        openTooltip: supplierName.isEmpty
            ? 'Ver este producto en el sitio del proveedor'
            : 'Ver este producto en el sitio de $supplierName',
      ),
      _copyRow('Código de barras', 'barcode', barcode, type, roles),
      if ((record.model ?? '').trim().isNotEmpty)
        _DetailRow(
          label: 'Modelo',
          value: Text(record.model!.trim(), style: type.value),
        ),
    ];
  }

  /// Fila de código. Toda la fila copia; si además hay a dónde ir ([openUri]),
  /// el código es un enlace y copiar queda en su botón `A-02`.
  _DetailRow _copyRow(
    String label,
    String field,
    String value,
    _PaneType type,
    VinabikeThemeRoles roles, {
    Uri? openUri,
    ValueChanged<Uri>? onOpen,
    String? openTooltip,
  }) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return _DetailRow(label: label, value: Text('—', style: type.faint));
    }
    final canOpen = openUri != null && onOpen != null;
    final copyButton = VbSurfaceIconButton(
      buttonKey: canOpen ? ProductDetailPane.copyKey(field) : null,
      icon: Icons.copy_outlined,
      tooltip: 'Copiar $label',
      onPressed: () => _copy(label, trimmed),
    );
    if (canOpen) {
      return _DetailRow(
        label: label,
        value: _MetaLink(
          linkKey: ProductDetailPane.supplierProductLinkKey,
          label: '$trimmed ↗',
          tooltip: openTooltip ?? 'Abrir en el sitio del proveedor',
          style: type.monoLink,
          onTap: () => onOpen(openUri),
        ),
        trailing: copyButton,
      );
    }
    return _DetailRow(
      rowKey: ProductDetailPane.copyKey(field),
      label: label,
      tooltip: 'Copiar',
      onTap: () => _copy(label, trimmed),
      value: Text(trimmed, style: type.mono),
      trailing: copyButton,
    );
  }

  List<Widget> _buildPriceRows(_PaneType type, VinabikeThemeRoles roles) {
    final product = widget.product;
    final margin = ProductMargin.of(product);
    final websitePrice = _record.websitePrice;
    final showsWebPrice =
        websitePrice != null && (websitePrice - product.price).abs() >= 1;

    return [
      _DetailRow(label: 'Precio venta', value: VbMoneyText(product.price)),
      _DetailRow(
        label: 'Costo',
        value: product.cost > 0
            ? VbMoneyText(product.cost)
            : Text('Sin registrar', style: type.faint),
      ),
      // El dueño lee el margen como precio de venta menos costo con IVA, así
      // que el costo con IVA va a la vista y el margen es esa resta exacta.
      if (margin.hasCost)
        _DetailRow(
          label: 'Costo + IVA',
          value: VbMoneyText(margin.costWithIva),
        ),
      _DetailRow(
        label: 'Margen',
        tooltip: 'Precio de venta menos costo con IVA',
        value: !margin.hasCost
            ? Text('Sin costo registrado', style: type.faint)
            : Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (margin.isBelowCost)
                    const VbStatusBadge(
                      label: 'Bajo el costo',
                      tone: VbStatusTone.danger,
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      VbMoneyText(margin.amount),
                      Text(
                        ' · ${formatPercent(margin.percentOverCost!)}',
                        style: type.monoMuted,
                      ),
                    ],
                  ),
                ],
              ),
      ),
      if (showsWebPrice)
        _DetailRow(label: 'Precio web', value: VbMoneyText(websitePrice)),
    ];
  }

  List<Widget> _buildInventoryRows(_PaneType type, VinabikeThemeRoles roles) {
    final product = widget.product;
    final record = _record;
    final rows = <Widget>[];
    if (product.isSet) {
      rows.add(
        _DetailRow(
          label: 'Juegos completos',
          value: Text('${widget.effectiveStock}', style: type.mono),
        ),
      );
    } else {
      rows.add(
        _DetailRow(
          label: 'Stock actual',
          value: Text('${widget.effectiveStock} un.', style: type.mono),
        ),
      );
      if (product.minStockLevel > 0) {
        rows.add(
          _DetailRow(
            label: 'Stock mínimo',
            value: Text('${product.minStockLevel} un.', style: type.mono),
          ),
        );
      }
      if (widget.fullRecord != null && record.reorderQuantity > 0) {
        rows.add(
          _DetailRow(
            label: 'Reposición sugerida',
            value: Text('${record.reorderQuantity} un.', style: type.mono),
          ),
        );
      }
    }
    final location = (record.warehouseLocation ?? '').trim();
    if (location.isNotEmpty) {
      rows.add(
        _DetailRow(
            label: 'Ubicación', value: Text(location, style: type.value)),
      );
    }
    if (!product.isSet && product.inventoryQty > 0 && product.cost > 0) {
      rows.add(
        _DetailRow(
          label: 'Valor a costo',
          value: VbMoneyText(product.cost * product.inventoryQty),
        ),
      );
    }
    return rows;
  }

  List<Widget> _buildChannelRows(_PaneType type, VinabikeThemeRoles roles) {
    final record = _record;
    final whatsapp = _whatsappState();
    final storeUri = widget.storeProductUri;
    final openStore = widget.onOpenUri;
    return [
      _DetailRow(
        label: 'Tienda web',
        value: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            if (record.isPublished && storeUri != null && openStore != null)
              _MetaLink(
                linkKey: ProductDetailPane.openStoreKey,
                label: 'Abrir en la tienda ↗',
                tooltip: storeUri.toString(),
                style: type.link,
                onTap: () => openStore(storeUri),
              ),
            VbStatusBadge(
              label: record.isPublished ? 'Publicado' : 'No publicado',
              tone: record.isPublished
                  ? VbStatusTone.success
                  : VbStatusTone.neutral,
            ),
          ],
        ),
      ),
      _DetailRow(
        label: 'Google Merchant',
        value: VbStatusBadge(
          label: record.isGoogleMerchant ? 'Incluido' : 'No incluido',
          tone: record.isGoogleMerchant
              ? VbStatusTone.success
              : VbStatusTone.neutral,
        ),
      ),
      _DetailRow(
        label: 'Catálogo WhatsApp',
        tooltip: (record.whatsappCatalogSyncError ?? '').trim().isNotEmpty
            ? record.whatsappCatalogSyncError!.trim()
            : null,
        value: VbStatusBadge(label: whatsapp.label, tone: whatsapp.tone),
      ),
    ];
  }

  List<Widget> _buildFichaChildren(
    ThemeData theme,
    VinabikeThemeRoles roles,
    _PaneType type,
  ) {
    final record = _record;
    final children = <Widget>[];

    final description = (record.description ?? '').trim();
    if (description.isNotEmpty) {
      final folds =
          description.length > ProductDetailPane.descriptionFoldLength ||
              '\n'.allMatches(description).length >= 3;
      children.add(
        _PlainLine(
          text: description,
          style: type.body,
          maxLines: folds && !_showFullDescription ? 3 : null,
          trailing: folds
              ? _MetaLink(
                  linkKey: ProductDetailPane.descriptionToggleKey,
                  label: _showFullDescription ? 'Ver menos' : 'Ver más',
                  tooltip: _showFullDescription
                      ? 'Plegar la descripción'
                      : 'Leer la descripción completa',
                  style: type.link,
                  onTap: () => setState(
                    () => _showFullDescription = !_showFullDescription,
                  ),
                )
              : null,
        ),
      );
    }

    if (widget.fullRecord == null) {
      if (widget.isLoadingFullRecord) {
        // X-01 · la silueta de las filas que vienen, en su sitio.
        children.addAll([
          for (final width in const [140.0, 200.0, 110.0])
            _PlainLine(
              text: null,
              style: type.body,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: VbSkeleton.bar(width: width),
              ),
            ),
        ]);
      }
      return children;
    }

    void addAttribute(String label, String? value) {
      final trimmed = (value ?? '').trim();
      if (trimmed.isEmpty) return;
      children.add(
        _DetailRow(label: label, value: Text(trimmed, style: type.value)),
      );
    }

    addAttribute('Color', record.color);
    addAttribute('Talla', record.size);
    addAttribute('Material', record.material);
    if (record.warrantyMonths > 0) {
      addAttribute('Garantía', '${record.warrantyMonths} meses');
    }

    final specs = record.specifications.entries
        .where((entry) =>
            entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    final visibleSpecs = _showAllSpecs
        ? specs
        : specs.take(ProductDetailPane.specsPreviewCount).toList();
    for (final entry in visibleSpecs) {
      children.add(
        _DetailRow(
          label: entry.key.trim(),
          value: Text(entry.value.trim(), style: type.value),
        ),
      );
    }
    if (specs.length > ProductDetailPane.specsPreviewCount) {
      children.add(
        _PlainLine(
          text: null,
          style: type.body,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _MetaLink(
              linkKey: ProductDetailPane.specsToggleKey,
              label: _showAllSpecs
                  ? 'Ver menos'
                  : 'Ver las ${specs.length} especificaciones',
              tooltip: _showAllSpecs
                  ? 'Mostrar sólo las primeras'
                  : 'Mostrar todas las especificaciones',
              style: type.link,
              onTap: () => setState(() => _showAllSpecs = !_showAllSpecs),
            ),
          ),
        ),
      );
    }

    final tags =
        record.tags.map((tag) => tag.trim()).where((t) => t.isNotEmpty);
    if (tags.isNotEmpty) {
      children.add(
        _DetailRow(
          label: 'Etiquetas',
          value: Text(tags.join(' · '),
              style: type.value, textAlign: TextAlign.right),
        ),
      );
    }

    return children;
  }
}

// -----------------------------------------------------------------------------
// Piezas

/// `F-02` en el panel. Familias: Poppins titula, Plex Sans lee, Plex Mono
/// cuenta; los colores son roles.
class _PaneType {
  _PaneType(ThemeData theme, VinabikeThemeRoles roles)
      : recordTitle = GoogleFonts.poppins(
          fontSize: 21,
          fontWeight: FontWeight.w600,
          height: 1.2,
          color: theme.colorScheme.onSurface,
        ),
        sectionTitle = GoogleFonts.ibmPlexSans(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface,
        ),
        label = GoogleFonts.ibmPlexSans(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        value = GoogleFonts.ibmPlexSans(
          fontSize: 12.5,
          fontWeight: FontWeight.w400,
          height: 1.45,
          color: theme.colorScheme.onSurface,
        ),
        body = GoogleFonts.ibmPlexSans(
          fontSize: 12.5,
          fontWeight: FontWeight.w400,
          height: 1.45,
          color: theme.colorScheme.onSurface,
        ),
        meta = GoogleFonts.ibmPlexSans(
          fontSize: 12.5,
          fontWeight: FontWeight.w400,
          height: 1.45,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        link = GoogleFonts.ibmPlexSans(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          height: 1.45,
          color: theme.colorScheme.primary,
        ),
        faint = GoogleFonts.ibmPlexSans(
          fontSize: 12.5,
          fontWeight: FontWeight.w400,
          height: 1.45,
          color: roles.faintForeground,
        ),
        mono = GoogleFonts.ibmPlexMono(
          fontSize: 12.5,
          fontWeight: FontWeight.w400,
          color: theme.colorScheme.onSurface,
        ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        monoMuted = GoogleFonts.ibmPlexMono(
          fontSize: 12.5,
          fontWeight: FontWeight.w400,
          color: theme.colorScheme.onSurfaceVariant,
        ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        monoLink = GoogleFonts.ibmPlexMono(
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
          color: theme.colorScheme.primary,
        ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        monoFaint = GoogleFonts.ibmPlexMono(
          fontSize: 12.5,
          fontWeight: FontWeight.w400,
          color: roles.faintForeground,
        ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  final TextStyle recordTitle;
  final TextStyle sectionTitle;
  final TextStyle label;
  final TextStyle value;
  final TextStyle body;
  final TextStyle meta;
  final TextStyle link;
  final TextStyle faint;
  final TextStyle mono;
  final TextStyle monoMuted;
  final TextStyle monoLink;
  final TextStyle monoFaint;
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.type,
    required this.roles,
    required this.children,
  });

  final String title;
  final _PaneType type;
  final VinabikeThemeRoles roles;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: type.sectionTitle),
        const SizedBox(height: 4),
        for (var i = 0; i < children.length; i++)
          DecoratedBox(
            decoration: BoxDecoration(
              border: i < children.length - 1
                  ? Border(bottom: BorderSide(color: roles.hairline))
                  : null,
            ),
            child: children[i],
          ),
      ],
    );
  }
}

/// Fila rótulo / valor del detalle (`T-05`: alto 34, hairline entre filas).
class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.onTap,
    this.tooltip,
    this.trailing,
    this.rowKey,
  });

  static const double minHeight = 34;

  final String label;
  final Widget value;
  final VoidCallback? onTap;
  final String? tooltip;
  final Widget? trailing;
  final Key? rowKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final type = _PaneType(theme, roles);

    Widget row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: minHeight),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: type.label),
          ),
          const SizedBox(width: 12),
          Flexible(
            flex: 3,
            child: Align(
              alignment: Alignment.centerRight,
              child: DefaultTextStyle.merge(
                style: type.value,
                textAlign: TextAlign.right,
                child: value,
              ),
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap != null) {
      // El lector anuncia rótulo, valor y el tooltip («Copiar») fusionados;
      // un label propio encima los repetía.
      row = Semantics(
        button: true,
        child: InkWell(
          key: rowKey,
          onTap: onTap,
          // La fila entera es el objetivo; el ink queda plano (F-05: nada de
          // sombra nueva dentro de un panel).
          child: row,
        ),
      );
    } else if (rowKey != null) {
      row = KeyedSubtree(key: rowKey, child: row);
    }

    if (tooltip != null && tooltip!.isNotEmpty) {
      row = Tooltip(message: tooltip!, child: row);
    }
    return row;
  }
}

/// Línea de texto corrido dentro de una sección (descripción, aviso) o un
/// hijo arbitrario con el mismo alto mínimo que una fila.
class _PlainLine extends StatelessWidget {
  const _PlainLine({
    required this.text,
    required this.style,
    this.maxLines,
    this.trailing,
    this.child,
  });

  final String? text;
  final TextStyle style;
  final int? maxLines;
  final Widget? trailing;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    if (child != null) return child!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text ?? '',
            style: style,
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis,
          ),
          if (trailing != null) ...[
            const SizedBox(height: 4),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Texto que actúa: filtro por marca/categoría/proveedor, abrir en la tienda,
/// plegar/desplegar. Subrayado sólo al pasar el puntero o con foco.
class _MetaLink extends StatefulWidget {
  const _MetaLink({
    required this.label,
    required this.tooltip,
    required this.style,
    required this.onTap,
    this.linkKey,
  });

  final String label;
  final String tooltip;
  final TextStyle style;
  final VoidCallback onTap;
  final Key? linkKey;

  @override
  State<_MetaLink> createState() => _MetaLinkState();
}

class _MetaLinkState extends State<_MetaLink> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final underline = _hovered || _focused;
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        label: widget.label,
        excludeSemantics: true,
        child: InkWell(
          key: widget.linkKey,
          onTap: widget.onTap,
          // F-04 · radio ctrl 6.
          borderRadius: BorderRadius.circular(6),
          onHover: (value) => setState(() => _hovered = value),
          onFocusChange: (value) => setState(() => _focused = value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: Text(
              widget.label,
              style: widget.style.copyWith(
                decoration:
                    underline ? TextDecoration.underline : TextDecoration.none,
                decorationColor: widget.style.color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
