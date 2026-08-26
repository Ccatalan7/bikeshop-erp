import 'package:flutter/material.dart';

import '../models/intelligent_purchasing_models.dart';
import '../pages/intelligent_purchasing_surfaces.dart';
import 'purchase_visual_language.dart';

/// **A quién le compramos esto**, como tabla y no como párrafos.
///
/// La guía lo dice sin ambigüedad: *una etapa que pide N decisiones es una
/// tabla*, con la comparación en columnas y un control por fila. La versión
/// anterior de este bloque apilaba una frase por proveedor —«57% de lo
/// comprado · 7 de 17 líneas · $7.810 c/u · última compra hace 5 meses»— y el
/// dueño no pudo usarla: los números que existen para compararse vivían dentro
/// de oraciones distintas y ninguna columna alineaba.
///
/// Anatomía `TB-01` de la guía y geometría de `handoff-t23`: panel sin padding,
/// cabecera hundida con etiqueta mono de 9 px, filas de `9px 11px` separadas
/// por su hairline, miniatura de 38 y números comparables en mono.
///
/// La salvedad honesta —flete prorrateado, disponibilidad no afirmada— se
/// publica **una vez** al pie. Repetirla por fila es lo que convertía la tabla
/// en un muro de texto.
class SupplierConcentrationTable extends StatelessWidget {
  const SupplierConcentrationTable({
    super.key,
    required this.report,
    this.exactProducts = const <SupplyStockOption>[],
    this.requestedLabel,
    this.plannedProductIds = const <String>{},
    this.addingProductId,
    this.onAddExactProduct,
    this.onCheckExactProduct,
    this.onOpenExactSupplier,
    required this.confirmedLabelFor,
    required this.confirmedAgeFor,
    required this.confirmedDetailFor,
    required this.checkProgress,
    required this.busySupplierId,
    required this.expandedSupplierId,
    required this.onConfirm,
    required this.onExplain,
    required this.onOpenPortal,
    required this.onOpenSupplier,
    required this.basis,
    required this.onBasisChanged,
    required this.evidencePanelBuilder,
  });

  final SupplierConcentrationReport report;

  /// Productos que cumplen la ficha, aunque la migración legacy no conserve
  /// una factura. Comparten la misma superficie con los proveedores
  /// históricos; el encabezado por calce evita mezclarlos en un solo ranking.
  final List<SupplyStockOption> exactProducts;
  final String? requestedLabel;
  final Set<String> plannedProductIds;
  final String? addingProductId;
  final ValueChanged<SupplyStockOption>? onAddExactProduct;
  final ValueChanged<SupplyStockOption>? onCheckExactProduct;
  final ValueChanged<SupplyStockOption>? onOpenExactSupplier;

  /// «12 de 12» — el recuento de lo confirmado, o nulo si nunca se consultó.
  final String? Function(String supplierId) confirmedLabelFor;

  /// «hace 7 min» — la antigüedad. Un dato de disponibilidad sin su hora es
  /// historia disfrazada de confirmación.
  final String? Function(String supplierId) confirmedAgeFor;

  /// «12 de 12 disponibles hace 3 min · 2 sin stock · 1 no apareció». Lo que no
  /// cabe en la celda pero el operador necesita para decidir si reintenta.
  final String? Function(String supplierId) confirmedDetailFor;

  /// «Confirmando 3 de 12: CAMARA 29…» mientras la corrida avanza.
  final String? checkProgress;

  final String? busySupplierId;
  final String? expandedSupplierId;
  final void Function(SupplierConcentration supplier) onConfirm;
  final void Function(SupplierConcentration supplier) onExplain;
  final void Function(SupplierConcentration supplier) onOpenPortal;

  /// Abre la ficha del proveedor **dentro del bloque**. La fila entera es el
  /// blanco: un chevron que sólo funciona en sus 20 px obliga a apuntar, y lo
  /// que el operador quiere tocar es el proveedor.
  final void Function(SupplierConcentration supplier) onOpenSupplier;

  /// Con flete o sin flete. Por defecto sin: es lo que el proveedor cobra, y lo
  /// que se compara al elegir a quién pedirle.
  final PurchaseCostBasis basis;
  final ValueChanged<PurchaseCostBasis> onBasisChanged;

  final WidgetBuilder evidencePanelBuilder;

  @override
  Widget build(BuildContext context) {
    if (report.isEmpty && exactProducts.isEmpty) {
      return const SizedBox.shrink();
    }
    final tokens = PurchaseTokens.of(context);
    final relaxed = report.items.isNotEmpty && report.items.first.scopeRelaxed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                requestedLabel == null || requestedLabel!.trim().isEmpty
                    ? 'Proveedores para esta necesidad'
                    : 'Proveedores para ${requestedLabel!.trim()}',
                style: PurchaseType.sectionTitle.copyWith(color: tokens.ink),
              ),
            ),
            // El interruptor vive con el título del bloque: manda sobre toda
            // la tabla, no sobre una fila.
            if (!report.isEmpty)
              PurchaseCostBasisToggle(value: basis, onChanged: onBasisChanged),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          _summaryLine(report, exactProducts.length),
          style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
        ),
        const SizedBox(height: 9),
        // **Las columnas se miden contra el ancho que hay, no contra una
        // constante.** Con acciones rotuladas fijas en 172 px, «Confirmado» y
        // «Confirmar hoy» se pisaban y la fila se salía del panel. La guía ya
        // resuelve este caso: en el ancho donde el rótulo compite con la
        // evidencia, la misma orden queda como icono con tooltip y etiqueta
        // hablada.
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 600) {
              return _buildCompact(context, relaxed: relaxed);
            }
            final layout = _TableLayout.of(
              constraints.maxWidth,
              _labelledActionsWidth(context),
            );
            return PurchasePanel(
              padded: false,
              child: Column(
                key: const ValueKey('supplier-concentration-table'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    color: tokens.sunken,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                    child: Row(
                      children: [
                        // La identidad no compara: se queda con lo justo para
                        // leerse. Antes tomaba casi la mitad del ancho vacía
                        // mientras las cuatro columnas que SÍ se comparan y las
                        // acciones se apretaban contra el borde.
                        const _Head(flex: 15, label: 'Proveedor'),
                        const _Head(
                          flex: 11,
                          label: 'Calce',
                          alignEnd: true,
                        ),
                        const _Head(
                          flex: 13,
                          label: 'Costo unitario',
                          alignEnd: true,
                        ),
                        if (layout.showEvidence)
                          const _Head(
                            flex: 15,
                            label: 'Evidencia',
                            alignEnd: true,
                          ),
                        if (layout.showAvailability)
                          const _Head(
                            flex: 14,
                            label: 'Disponible hoy',
                            alignEnd: true,
                          ),
                        // Los números no tocan los botones: sin este respiro,
                        // «12 de 12» y «Confirmar hoy» se leen como una sola
                        // cosa.
                        const SizedBox(width: 28),
                        SizedBox(width: layout.actionsWidth),
                        // El hueco del chevron, para que la cabecera y las
                        // filas sigan calzando.
                        const SizedBox(width: 24),
                      ],
                    ),
                  ),
                  if (exactProducts.isNotEmpty) ...[
                    _SupplierSectionHeader(
                      label: 'Exacto · cumple la ficha técnica pedida',
                      count: exactProducts.length,
                    ),
                    for (final product in exactProducts)
                      _ExactSupplierRow(
                        product: product,
                        layout: layout,
                        adding: addingProductId == product.productId,
                        alreadyInPlan:
                            plannedProductIds.contains(product.productId),
                        anyBusy:
                            busySupplierId != null || addingProductId != null,
                        onAdd: onAddExactProduct == null
                            ? null
                            : () => onAddExactProduct!(product),
                        onCheck: onCheckExactProduct == null
                            ? null
                            : () => onCheckExactProduct!(product),
                        onOpenSupplier: onOpenExactSupplier == null ||
                                product.supplierId == null
                            ? null
                            : () => onOpenExactSupplier!(product),
                      ),
                  ],
                  if (report.items.isNotEmpty) ...[
                    _SupplierSectionHeader(
                      label: relaxed
                          ? 'Parecido · la búsqueda se amplió; no prueba el calce exacto'
                          : 'Comprado antes · cumple el alcance pedido',
                      count: report.items.length,
                    ),
                  ],
                  for (final supplier in report.items) ...[
                    _SupplierRow(
                      supplier: supplier,
                      confirmed: confirmedLabelFor(supplier.supplierId),
                      confirmedAge: confirmedAgeFor(supplier.supplierId),
                      confirmedDetail: confirmedDetailFor(supplier.supplierId),
                      checkProgress: checkProgress,
                      busy: busySupplierId == supplier.supplierId,
                      anyBusy: busySupplierId != null,
                      expanded: expandedSupplierId == supplier.supplierId,
                      layout: layout,
                      basis: basis,
                      onConfirm: () => onConfirm(supplier),
                      onExplain: () => onExplain(supplier),
                      onOpenPortal: () => onOpenPortal(supplier),
                      onOpenSupplier: () => onOpenSupplier(supplier),
                    ),
                    if (expandedSupplierId == supplier.supplierId)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(11, 0, 11, 11),
                        child: evidencePanelBuilder(context),
                      ),
                  ],
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        // **La salvedad va una vez.** Es la misma para todas las filas: dentro
        // de cada una convertía la comparación en prosa.
        Text(
          // La salvedad sigue al eje: publicar «con flete prorrateado»
          // mientras se muestra el neto describiría otra tabla.
          '${report.isEmpty ? '' : '${basis.footnote} '}'
          'El costo de ficha es una referencia, no una factura. Llevar al plan '
          'no compra ni reserva; la disponibilidad requiere una consulta '
          'fechada al proveedor.',
          style: PurchaseType.meta.copyWith(color: tokens.inkFaint),
        ),
      ],
    );
  }

  static String _evidenceLine(SupplierConcentrationReport report) {
    final lines = report.evidencePurchaseLines;
    final suppliers = report.supplierCount;
    final base = '$lines ${lines == 1 ? 'línea' : 'líneas'} de compra '
        'entre $suppliers ${suppliers == 1 ? 'proveedor' : 'proveedores'}';
    final widened = report.items.first.widenedLabel;
    return widened == null ? base : '$base · $widened';
  }

  static String _summaryLine(
    SupplierConcentrationReport report,
    int exactCount,
  ) {
    final parts = <String>[];
    if (exactCount > 0) {
      parts.add(
          '$exactCount ${exactCount == 1 ? 'opción exacta' : 'opciones exactas'} de catálogo');
    }
    if (report.items.isNotEmpty) {
      final suppliers = report.supplierCount;
      parts.add(report.items.first.scopeRelaxed
          ? '$suppliers ${suppliers == 1 ? 'proveedor' : 'proveedores'} con compras de productos parecidos'
          : _evidenceLine(report));
    }
    return parts.join(' · ');
  }

  Widget _buildCompact(BuildContext context, {required bool relaxed}) {
    return PurchasePanel(
      padded: false,
      child: Column(
        key: const ValueKey('supplier-concentration-table'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (exactProducts.isNotEmpty) ...[
            _SupplierSectionHeader(
              label: 'Exacto · cumple la ficha técnica pedida',
              count: exactProducts.length,
            ),
            for (final product in exactProducts)
              _CompactExactSupplierRow(
                product: product,
                adding: addingProductId == product.productId,
                alreadyInPlan: plannedProductIds.contains(product.productId),
                anyBusy: busySupplierId != null || addingProductId != null,
                onAdd: onAddExactProduct == null
                    ? null
                    : () => onAddExactProduct!(product),
                onCheck: onCheckExactProduct == null
                    ? null
                    : () => onCheckExactProduct!(product),
                onOpenSupplier:
                    onOpenExactSupplier == null || product.supplierId == null
                        ? null
                        : () => onOpenExactSupplier!(product),
              ),
          ],
          if (report.items.isNotEmpty) ...[
            _SupplierSectionHeader(
              label: relaxed
                  ? 'Parecido · no prueba el calce exacto'
                  : 'Comprado antes · mismo alcance',
              count: report.items.length,
            ),
            for (final supplier in report.items)
              _CompactHistoricalSupplierRow(
                supplier: supplier,
                confirmed: confirmedLabelFor(supplier.supplierId),
                confirmedAge: confirmedAgeFor(supplier.supplierId),
                busy: busySupplierId == supplier.supplierId,
                anyBusy: busySupplierId != null,
                basis: basis,
                onConfirm: () => onConfirm(supplier),
                onExplain: () => onExplain(supplier),
                onOpenSupplier: () => onOpenSupplier(supplier),
              ),
          ],
        ],
      ),
    );
  }
}

/// Qué cabe en el ancho que hay.
///
/// Un solo lugar decide, y lo usan la cabecera y las filas: si cada una midiera
/// por su cuenta, la columna del encabezado y la del dato dejarían de calzar
/// justo al estrecharse, que es cuando más se nota.
/// El ancho de la orden rotulada **se mide, no se declara**.
///
/// Depende de la familia tipográfica y de la escala de texto del sistema. Con
/// una constante —216 px, medidos a ojo en este Mac— «Confirmar hoy» y «Por
/// qué» se salían del panel en cuanto la fuente medía distinto: la prueba de
/// widget, que usa otra fuente, desbordaba 65 px **siempre**. Un número que
/// sólo vale en una máquina no es una medida.
double _labelledActionsWidth(BuildContext context) {
  final plan = purchaseInlineActionWidth(
    context,
    const ['Llevar al plan', 'En el plan'],
  );
  final confirm = purchaseInlineActionWidth(
    context,
    const ['Consultar producto', 'Consultando…'],
  );
  final explain = purchaseInlineActionWidth(
    context,
    const ['Por qué', 'Ocultar'],
  );
  return plan + 10 + confirm + 10 + explain + 10 + _kSiteSlot;
}

/// El hueco del enlace al sitio, presente aunque el proveedor no lo tenga.
const double _kSiteSlot = 28;

/// **La geometría del icono es de la tabla, no del tema.**
///
/// `padding` y `constraints` de `IconButton` no ganan: el `iconButtonTheme` de
/// la app impone su `minimumSize` —pensado para una barra, no para una fila de
/// 20 px— y la celda de acciones desbordaba 20 px en compacto. Aquí se fija.
final ButtonStyle _kIconSlotStyle = IconButton.styleFrom(
  minimumSize: Size.zero,
  maximumSize: const Size(_kSiteSlot, _kSiteSlot),
  padding: EdgeInsets.zero,
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  visualDensity: VisualDensity.compact,
);

/// Dos iconos de 28 con sus separaciones, más el hueco del sitio.
const double _kCompactActionsWidth = 96;

/// Lo que las cinco columnas necesitan para seguir siendo comparables. Por
/// debajo, un número se parte y la tabla deja de servir para lo único que
/// existe: mirar dos filas y elegir.
const double _kFiveColumnsFloor = 700;

class _TableLayout {
  const _TableLayout({
    required this.showEvidence,
    required this.showAvailability,
    required this.compactActions,
    required this.actionsWidth,
  });

  /// Suelta en orden de menor a mayor valor comparativo: primero el **rótulo**
  /// de la orden —el icono conserva el mando y le devuelve el ancho a los
  /// números—, después «Confirmado», y sólo al final «Última compra».
  factory _TableLayout.of(double width, double labelledActions) {
    final labelsFit = width - labelledActions >= _kFiveColumnsFloor;
    return _TableLayout(
      showEvidence: width >= 760,
      showAvailability: width >= 920,
      compactActions: !labelsFit,
      actionsWidth: labelsFit ? labelledActions : _kCompactActionsWidth,
    );
  }

  final bool showEvidence;
  final bool showAvailability;

  /// Con la orden como icono, la fila conserva el mando y le devuelve el ancho
  /// a los números, que son lo que la tabla existe para comparar.
  final bool compactActions;

  final double actionsWidth;
}

class _Head extends StatelessWidget {
  const _Head({required this.flex, required this.label, this.alignEnd = false});

  final int flex;
  final String label;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label.toUpperCase(),
        textAlign: alignEnd ? TextAlign.end : TextAlign.start,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: PurchaseType.label.copyWith(
          color: PurchaseTokens.of(context).inkFaint,
        ),
      ),
    );
  }
}

/// El corte visual responde al calce, que es la primera pregunta del operador.
/// La procedencia vive en las celdas; no vuelve a partir la pantalla en una
/// tarjeta de producto y otra tabla de proveedores.
class _SupplierSectionHeader extends StatelessWidget {
  const _SupplierSectionHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: tokens.sunken,
        border: Border(top: BorderSide(color: tokens.hair)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: PurchaseType.label.copyWith(color: tokens.inkMuted),
            ),
          ),
          Text(
            '$count',
            style: PurchaseType.label.copyWith(color: tokens.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _ExactSupplierRow extends StatelessWidget {
  const _ExactSupplierRow({
    required this.product,
    required this.layout,
    required this.adding,
    required this.alreadyInPlan,
    required this.anyBusy,
    required this.onAdd,
    required this.onCheck,
    required this.onOpenSupplier,
  });

  final SupplyStockOption product;
  final _TableLayout layout;
  final bool adding;
  final bool alreadyInPlan;
  final bool anyBusy;
  final VoidCallback? onAdd;
  final VoidCallback? onCheck;
  final VoidCallback? onOpenSupplier;

  bool get _canCheck =>
      product.automaticAvailabilityEnabled &&
      product.supplierCode != null &&
      onCheck != null;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final supplier = product.supplierName?.trim();
    final supplierLabel = supplier == null || supplier.isEmpty
        ? 'Proveedor sin identificar'
        : supplier;
    final fresh = product.availabilityFresh;
    final available = fresh && product.availabilityStatus == 'available';
    final outOfStock = fresh && product.availabilityStatus == 'out_of_stock';
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 15,
          child: Row(
            children: [
              _SupplierMonogram(name: supplierLabel),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      supplierLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PurchaseType.rowTitle.copyWith(color: tokens.ink),
                    ),
                    Text(
                      [
                        product.name,
                        if (product.sku != null) 'SKU ${product.sku}',
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const _Metric(
          flex: 11,
          value: 'Exacto',
          caption: 'ficha técnica',
          numeric: false,
        ),
        _Metric(
          flex: 13,
          value: PurchaseMoney.format(
            product.catalogCostNet,
            product.catalogCostCurrency,
          ),
          caption: product.catalogCostNet == null
              ? 'sin costo en ficha'
              : 'de ficha, no pagado',
        ),
        if (layout.showEvidence)
          _Metric(
            flex: 15,
            value: 'Catálogo legacy',
            caption: product.purchaseCount == 0
                ? 'sin compras en este ERP'
                : '${product.purchaseCount} compras ERP',
            numeric: false,
          ),
        if (layout.showAvailability)
          _Metric(
            flex: 14,
            value: available
                ? 'Disponible'
                : outOfStock
                    ? 'Sin stock'
                    : '—',
            caption: fresh
                ? 'revisado ${supplySourcingDateLabel(product.availabilityCheckedAt)}'
                : _canCheck
                    ? 'sin consultar'
                    : 'sin consulta automática',
            emphasis: available,
            numeric: false,
          ),
        const SizedBox(width: 28),
        SizedBox(
          width: layout.actionsWidth,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: layout.compactActions
                ? _compactActions(context, supplierLabel)
                : _labelledActions(context, supplierLabel),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Icon(
            Icons.chevron_right,
            size: 18,
            color:
                onOpenSupplier == null ? Colors.transparent : tokens.inkFaint,
          ),
        ),
      ],
    );
    if (onOpenSupplier == null) {
      return _PlainSupplierRow(child: content);
    }
    return _HoverRow(
      onTap: onOpenSupplier!,
      semanticLabel: 'Abrir la ficha de $supplierLabel',
      child: content,
    );
  }

  List<Widget> _compactActions(BuildContext context, String supplierLabel) => [
        IconButton(
          key: ValueKey('add-catalog-plan-${product.productId}'),
          onPressed: anyBusy || alreadyInPlan ? null : onAdd,
          icon: adding
              ? const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  alreadyInPlan
                      ? Icons.playlist_add_check
                      : Icons.playlist_add_outlined,
                  size: 16,
                ),
          style: _kIconSlotStyle,
          tooltip: alreadyInPlan
              ? '${product.name} ya está en el plan'
              : 'Llevar ${product.name} al plan',
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: _canCheck
              ? 'Consultar este producto en el portal de $supplierLabel'
              : '$supplierLabel todavía no tiene consulta automática para este producto',
          child: IconButton(
            key: ValueKey('check-catalog-product-${product.productId}'),
            onPressed: anyBusy || !_canCheck ? null : onCheck,
            icon: const Icon(Icons.fact_check_outlined, size: 16),
            style: _kIconSlotStyle,
          ),
        ),
      ];

  List<Widget> _labelledActions(BuildContext context, String supplierLabel) => [
        PurchaseInlineAction(
          key: ValueKey('add-catalog-plan-${product.productId}'),
          label: adding
              ? 'Agregando…'
              : alreadyInPlan
                  ? 'En el plan'
                  : 'Llevar al plan',
          onPressed: anyBusy || alreadyInPlan ? null : onAdd,
        ),
        const SizedBox(width: 10),
        Tooltip(
          message: _canCheck
              ? 'Consulta únicamente ${product.name}'
              : '$supplierLabel todavía no tiene consulta automática para este producto',
          child: PurchaseInlineAction(
            key: ValueKey('check-catalog-product-${product.productId}'),
            label: 'Consultar producto',
            onPressed: anyBusy || !_canCheck ? null : onCheck,
          ),
        ),
      ];
}

class _PlainSupplierRow extends StatelessWidget {
  const _PlainSupplierRow({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.hair)),
      ),
      child: child,
    );
  }
}

class _CompactExactSupplierRow extends StatelessWidget {
  const _CompactExactSupplierRow({
    required this.product,
    required this.adding,
    required this.alreadyInPlan,
    required this.anyBusy,
    required this.onAdd,
    required this.onCheck,
    required this.onOpenSupplier,
  });

  final SupplyStockOption product;
  final bool adding;
  final bool alreadyInPlan;
  final bool anyBusy;
  final VoidCallback? onAdd;
  final VoidCallback? onCheck;
  final VoidCallback? onOpenSupplier;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final supplier = product.supplierName ?? 'Proveedor sin identificar';
    final canCheck = product.automaticAvailabilityEnabled &&
        product.supplierCode != null &&
        onCheck != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.hair)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(supplier,
              style: PurchaseType.rowTitle.copyWith(color: tokens.ink)),
          const SizedBox(height: 2),
          Text(
            '${product.name}${product.sku == null ? '' : ' · SKU ${product.sku}'}',
            style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
          ),
          const SizedBox(height: 4),
          Text(
            '${PurchaseMoney.format(product.catalogCostNet, product.catalogCostCurrency)} · '
            '${product.catalogCostNet == null ? 'sin costo en ficha' : 'de ficha, no pagado'} · '
            'sin compras en este ERP',
            style: PurchaseType.body.copyWith(color: tokens.ink),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(
                key: ValueKey('add-catalog-plan-${product.productId}'),
                onPressed: anyBusy || alreadyInPlan ? null : onAdd,
                child: Text(adding
                    ? 'Agregando…'
                    : alreadyInPlan
                        ? 'En el plan'
                        : 'Llevar al plan'),
              ),
              Tooltip(
                message: canCheck
                    ? 'Consulta únicamente ${product.name}'
                    : '$supplier todavía no tiene consulta automática para este producto',
                child: TextButton(
                  key: ValueKey('check-catalog-product-${product.productId}'),
                  onPressed: anyBusy || !canCheck ? null : onCheck,
                  child: const Text('Consultar producto'),
                ),
              ),
              if (onOpenSupplier != null)
                PurchaseInlineAction(
                  label: 'Ver proveedor',
                  onPressed: onOpenSupplier,
                ),
            ],
          ),
          Text(
            'Llevar al plan no compra ni reserva.',
            style: PurchaseType.meta.copyWith(color: tokens.inkFaint),
          ),
        ],
      ),
    );
  }
}

class _CompactHistoricalSupplierRow extends StatelessWidget {
  const _CompactHistoricalSupplierRow({
    required this.supplier,
    required this.confirmed,
    required this.confirmedAge,
    required this.busy,
    required this.anyBusy,
    required this.basis,
    required this.onConfirm,
    required this.onExplain,
    required this.onOpenSupplier,
  });

  final SupplierConcentration supplier;
  final String? confirmed;
  final String? confirmedAge;
  final bool busy;
  final bool anyBusy;
  final PurchaseCostBasis basis;
  final VoidCallback onConfirm;
  final VoidCallback onExplain;
  final VoidCallback onOpenSupplier;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final cost = basis.includesFreight
        ? supplier.averageLandedUnitCostNet
        : supplier.averageBaseUnitCostNet ?? supplier.averageLandedUnitCostNet;
    final share = supplier.spendSharePercent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.hair)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(supplier.supplierName,
              style: PurchaseType.rowTitle.copyWith(color: tokens.ink)),
          const SizedBox(height: 2),
          Text(
            '${supplier.scopeRelaxed ? 'Parecido' : 'Exacto'} · '
            '${PurchaseMoney.format(cost, 'CLP')} promedio · '
            '${share.toStringAsFixed(share >= 10 ? 0 : 1).replaceAll('.', ',')}% de '
            '${supplier.evidencePurchaseLines} líneas',
            style: PurchaseType.body.copyWith(color: tokens.ink),
          ),
          Text(
            [
              if (supplier.lastPurchaseLabel != null)
                'última compra ${supplier.lastPurchaseLabel}',
              confirmed == null
                  ? 'disponibilidad sin consultar'
                  : '$confirmed${confirmedAge == null ? '' : ' · $confirmedAge'}',
            ].join(' · '),
            style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              PurchaseInlineAction(
                label: busy ? 'Consultando…' : 'Consultar portal',
                onPressed: anyBusy ? null : onConfirm,
              ),
              PurchaseInlineAction(label: 'Por qué', onPressed: onExplain),
              PurchaseInlineAction(
                label: 'Ver proveedor',
                onPressed: onOpenSupplier,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SupplierRow extends StatelessWidget {
  const _SupplierRow({
    required this.supplier,
    required this.confirmed,
    required this.confirmedAge,
    required this.confirmedDetail,
    required this.checkProgress,
    required this.busy,
    required this.anyBusy,
    required this.expanded,
    required this.layout,
    required this.basis,
    required this.onConfirm,
    required this.onExplain,
    required this.onOpenPortal,
    required this.onOpenSupplier,
  });

  final SupplierConcentration supplier;
  final String? confirmed;
  final String? confirmedAge;
  final String? confirmedDetail;
  final String? checkProgress;
  final bool busy;
  final bool anyBusy;
  final bool expanded;
  final _TableLayout layout;
  final PurchaseCostBasis basis;
  final VoidCallback onConfirm;
  final VoidCallback onExplain;
  final VoidCallback onOpenPortal;
  final VoidCallback onOpenSupplier;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final share = supplier.spendSharePercent;
    return _HoverRow(
      onTap: onOpenSupplier,
      // El rótulo hablado nombra al proveedor y dice qué pasa al tocar: una
      // fila de tabla sin esto se anuncia como su contenido y no como una
      // puerta.
      semanticLabel: 'Abrir la ficha de ${supplier.supplierName}',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 15,
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Cuando la celda ya no hospeda tile e identidad, gana la
                // identidad: la miniatura es apoyo, no el dato.
                final showTile = constraints.maxWidth >=
                    PurchaseSurfaceGeometry.mediaTableRow + 96;
                return Row(
                  children: [
                    if (showTile) ...[
                      _SupplierMonogram(name: supplier.supplierName),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            supplier.supplierName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PurchaseType.rowTitle
                                .copyWith(color: tokens.ink),
                          ),
                          Text(
                            _identity(supplier),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PurchaseType.meta
                                .copyWith(color: tokens.inkMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          _Metric(
            flex: 11,
            value: supplier.scopeRelaxed ? 'Parecido' : 'Exacto',
            caption: supplier.scopeRelaxed
                ? 'búsqueda ampliada'
                : 'historial del mismo alcance',
            numeric: false,
          ),
          () {
            // El eje elegido manda. Sin flete es lo que el proveedor cobró;
            // con flete, lo que salió puesto en bodega.
            final costo = basis.includesFreight
                ? supplier.averageLandedUnitCostNet
                : (supplier.averageBaseUnitCostNet ??
                    supplier.averageLandedUnitCostNet);
            return _Metric(
              flex: 13,
              value: costo == null ? '—' : PurchaseMoney.format(costo, 'CLP'),
              caption: '${supplier.purchaseInvoices} '
                  '${supplier.purchaseInvoices == 1 ? 'factura' : 'facturas'}',
            );
          }(),
          if (layout.showEvidence)
            _Metric(
              flex: 15,
              value:
                  '${share >= 10 ? share.round() : share.toStringAsFixed(1).replaceAll('.', ',')}%',
              caption: [
                '${supplier.purchaseLines} de ${supplier.evidencePurchaseLines} líneas',
                if (supplier.lastPurchaseLabel != null)
                  supplier.lastPurchaseLabel!,
              ].join(' · '),
              numeric: false,
            ),
          if (layout.showAvailability)
            _Metric(
              flex: 14,
              // Nunca se consultó ≠ se consultó y no hay. Un guion dice lo
              // primero sin insinuar lo segundo.
              value: confirmed ?? '—',
              // Una consulta de 30 s con un spinner mudo se lee como colgada.
              caption: busy
                  ? (checkProgress ?? 'consultando…')
                  : (confirmedAge ?? 'sin consultar'),
              emphasis: confirmed != null,
              detail: confirmedDetail,
            ),
          const SizedBox(width: 28),
          SizedBox(
            width: layout.actionsWidth,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (layout.compactActions) ...[
                  // Misma orden, sin rótulo. El tooltip y la etiqueta hablada
                  // nombran al proveedor: cuatro iconos iguales no identifican
                  // su sujeto ni para un lector de pantalla ni para una prueba.
                  IconButton(
                    key: ValueKey('confirm-supplier-${supplier.supplierId}'),
                    onPressed: anyBusy ? null : onConfirm,
                    icon: busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.fact_check_outlined, size: 16),
                    style: _kIconSlotStyle,
                    tooltip: 'Consultar el portal de ${supplier.supplierName}',
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    key: ValueKey('explain-supplier-${supplier.supplierId}'),
                    onPressed: onExplain,
                    icon: Icon(
                      expanded ? Icons.expand_less : Icons.help_outline_rounded,
                      size: 16,
                    ),
                    style: _kIconSlotStyle,
                    tooltip: expanded
                        ? 'Ocultar el detalle de ${supplier.supplierName}'
                        : 'Por qué ${supplier.supplierName} quedó acá',
                  ),
                ] else ...[
                  PurchaseInlineAction(
                    key: ValueKey('confirm-supplier-${supplier.supplierId}'),
                    label: busy ? 'Consultando…' : 'Consultar portal',
                    onPressed: anyBusy ? null : onConfirm,
                  ),
                  const SizedBox(width: 10),
                  PurchaseInlineAction(
                    key: ValueKey('explain-supplier-${supplier.supplierId}'),
                    label: expanded ? 'Ocultar' : 'Por qué',
                    onPressed: onExplain,
                  ),
                ],
                SizedBox(width: layout.compactActions ? 4 : 10),
                // **El hueco del sitio es el mismo ancho con o sin icono.**
                // Antes la fila sin sitio ponía un espacio suelto al final y,
                // con el contenido alineado a la derecha, corría sus botones
                // diez píxeles: Vittal quedaba desalineada de las otras tres.
                // Un contenedor de ancho fijo que a veces va vacío mantiene la
                // columna quieta.
                SizedBox(
                  width: 28,
                  height: 28,
                  child: supplier.supplierWebsite == null
                      ? null
                      : IconButton(
                          key: ValueKey('open-supplier-${supplier.supplierId}'),
                          onPressed: onOpenPortal,
                          icon: const Icon(Icons.open_in_new, size: 16),
                          style: _kIconSlotStyle,
                          // Un icono repetido por fila no identifica su
                          // sujeto: sin esto, un lector de pantalla oye
                          // «abrir» cuatro veces.
                          tooltip: supplier.hasPortalAccount
                              ? 'Entrar al portal de ${supplier.supplierName}'
                              : 'Abrir el sitio de ${supplier.supplierName}',
                        ),
                ),
              ],
            ),
          ),
          // **El chevron es lo que dice que la fila lleva a alguna parte.**
          // Sin él, una fila que abre una ficha se ve igual que una que no
          // hace nada y nadie la toca. Va al final, después de las órdenes,
          // porque es el destino y no una acción más.
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Icon(
              Icons.chevron_right,
              size: 18,
              color: tokens.inkFaint,
            ),
          ),
        ],
      ),
    );
  }

  static String _identity(SupplierConcentration supplier) {
    final partes = <String>[
      if (supplier.brands != null) supplier.brands!,
      if (supplier.supplierCity != null) supplier.supplierCity!,
      if (supplier.hasPortalAccount) 'con cuenta',
    ];
    return partes.isEmpty ? 'sin marcas registradas' : partes.join(' · ');
  }
}

/// La fila entera como blanco, con su realce al pasar por encima.
///
/// Un chevron que sólo funciona en sus 18 px obliga a apuntar; lo que el
/// operador quiere tocar es el proveedor. El realce existe porque un cursor de
/// mano sobre una tabla no se ve: sin él, la fila parece inerte hasta que
/// alguien la toca por casualidad.
class _HoverRow extends StatefulWidget {
  const _HoverRow({
    required this.child,
    required this.onTap,
    required this.semanticLabel,
  });

  final Widget child;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  State<_HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<_HoverRow> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      button: true,
      onTap: widget.onTap,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          // El `Semantics` dueño publica la acción de la fila. Así los botones
          // hijos conservan sus propias acciones en vez de quedar absorbidos
          // por un segundo nodo de gesto con el mismo tap.
          excludeFromSemantics: true,
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: _hovering ? tokens.selected : Colors.transparent,
              border: Border(top: BorderSide(color: tokens.hair)),
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Un proveedor no tiene foto de producto. El contrato de imagen ya define el
/// sustituto: monograma de dos letras sobre superficie hundida, con la MISMA
/// geometría que la miniatura para que la fila no cambie de alto.
class _SupplierMonogram extends StatelessWidget {
  const _SupplierMonogram({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    // **Dos letras, siempre.** El contrato de imagen pide un monograma de dos
    // letras; con la inicial de cada palabra, un proveedor de nombre único
    // —«TeknoBike», «Vittal»— quedaba con una sola y la columna se veía coja.
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    final letters = switch (words.length) {
      0 => '',
      1 => words.first.length >= 2
          ? words.first.substring(0, 2).toUpperCase()
          : words.first.toUpperCase(),
      _ => '${words[0][0]}${words[1][0]}'.toUpperCase(),
    };
    return Container(
      width: PurchaseSurfaceGeometry.mediaTableRow,
      height: PurchaseSurfaceGeometry.mediaTableRow,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tokens.sunken,
        borderRadius:
            BorderRadius.circular(PurchaseSurfaceGeometry.mediaRadius),
        border: Border.all(color: tokens.border),
      ),
      child: Text(
        letters.isEmpty ? '?' : letters,
        style: PurchaseType.label.copyWith(color: tokens.inkMuted),
      ),
    );
  }
}

/// Un número comparable y su base debajo. El número va en mono para que la
/// columna alinee; la base va en secundario porque explica, no compara.
class _Metric extends StatelessWidget {
  const _Metric({
    required this.flex,
    required this.value,
    required this.caption,
    this.numeric = true,
    this.emphasis = false,
    this.detail,
  });

  final int flex;
  final String value;
  final String caption;
  final bool numeric;
  final bool emphasis;

  /// El desglose que no cabe en la celda —«2 sin stock · 1 no apareció»— sin
  /// convertir la fila en un párrafo. Se calculaba y no se mostraba en ninguna
  /// parte: el operador veía «12 de 12» y no sabía qué pasó con el resto.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final cell = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (numeric ? PurchaseType.metricSmall : PurchaseType.rowTitle)
              .copyWith(
            color: emphasis ? tokens.act : tokens.ink,
            fontFeatures: numeric ? PurchaseType.tabular : null,
          ),
        ),
        Text(
          caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: PurchaseType.meta.copyWith(color: tokens.inkFaint),
        ),
      ],
    );
    return Expanded(
      flex: flex,
      child: detail == null ? cell : Tooltip(message: detail!, child: cell),
    );
  }
}
