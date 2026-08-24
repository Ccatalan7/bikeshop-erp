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
    if (report.isEmpty) return const SizedBox.shrink();
    final tokens = PurchaseTokens.of(context);
    final relaxed = report.items.first.scopeRelaxed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                relaxed
                    ? 'A quién le compramos algo así'
                    : 'A quién le compramos esto',
                style: PurchaseType.sectionTitle.copyWith(color: tokens.ink),
              ),
            ),
            // El interruptor vive con el título del bloque: manda sobre toda
            // la tabla, no sobre una fila.
            PurchaseCostBasisToggle(value: basis, onChanged: onBasisChanged),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          _evidenceLine(report),
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
                          flex: 13,
                          label: 'Participación',
                          alignEnd: true,
                        ),
                        const _Head(
                          flex: 13,
                          label: 'Costo unitario',
                          alignEnd: true,
                        ),
                        if (layout.showLastPurchase)
                          const _Head(
                            flex: 13,
                            label: 'Última compra',
                            alignEnd: true,
                          ),
                        if (layout.showConfirmed)
                          const _Head(
                            flex: 14,
                            label: 'Confirmado',
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
                  for (final supplier in report.items) ...[
                    _SupplierRow(
                      supplier: supplier,
                      confirmed: confirmedLabelFor(supplier.supplierId),
                      confirmedAge: confirmedAgeFor(supplier.supplierId),
                      confirmedDetail:
                          confirmedDetailFor(supplier.supplierId),
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
          '${basis.footnote} El historial dice a quién se lo compramos; la '
          'disponibilidad de hoy sólo la confirma el proveedor.',
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
  final confirm = purchaseInlineActionWidth(
    context,
    const ['Confirmar hoy', 'Confirmando…'],
  );
  final explain = purchaseInlineActionWidth(
    context,
    const ['Por qué', 'Ocultar'],
  );
  return confirm + 10 + explain + 10 + _kSiteSlot;
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
    required this.showLastPurchase,
    required this.showConfirmed,
    required this.compactActions,
    required this.actionsWidth,
  });

  /// Suelta en orden de menor a mayor valor comparativo: primero el **rótulo**
  /// de la orden —el icono conserva el mando y le devuelve el ancho a los
  /// números—, después «Confirmado», y sólo al final «Última compra».
  factory _TableLayout.of(double width, double labelledActions) {
    final labelsFit = width - labelledActions >= _kFiveColumnsFloor;
    return _TableLayout(
      showLastPurchase: width >= 640,
      showConfirmed: width >= 820,
      compactActions: !labelsFit,
      actionsWidth: labelsFit ? labelledActions : _kCompactActionsWidth,
    );
  }

  final bool showLastPurchase;
  final bool showConfirmed;

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
                            style:
                                PurchaseType.rowTitle.copyWith(color: tokens.ink),
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
            flex: 13,
            value: '${share >= 10 ? share.round() : share.toStringAsFixed(1).replaceAll('.', ',')}%',
            caption: '${supplier.purchaseLines} de '
                '${supplier.evidencePurchaseLines} líneas',
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
              value: costo == null
                  ? '—'
                  : PurchaseMoney.format(costo, 'CLP'),
              caption: '${supplier.purchaseInvoices} '
                  '${supplier.purchaseInvoices == 1 ? 'factura' : 'facturas'}',
            );
          }(),
          if (layout.showLastPurchase)
            _Metric(
              flex: 13,
              value: supplier.lastPurchaseLabel ?? '—',
              caption: '${supplier.distinctProducts} '
                  '${supplier.distinctProducts == 1 ? 'producto' : 'productos'}',
              numeric: false,
            ),
          if (layout.showConfirmed)
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
                    tooltip: 'Confirmar hoy con ${supplier.supplierName}',
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    key: ValueKey('explain-supplier-${supplier.supplierId}'),
                    onPressed: onExplain,
                    icon: Icon(
                      expanded
                          ? Icons.expand_less
                          : Icons.help_outline_rounded,
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
                    label: busy ? 'Confirmando…' : 'Confirmar hoy',
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
      button: true,
      label: widget.semanticLabel,
      // Sin esto el rótulo del envoltorio se concatena con el de la fila
      // entera y no se encuentra ni a mano ni en una prueba.
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
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
      child: detail == null
          ? cell
          : Tooltip(message: detail!, child: cell),
    );
  }
}
