import 'package:flutter/material.dart';

import '../models/intelligent_purchasing_models.dart';
import '../pages/intelligent_purchasing_surfaces.dart';
import 'purchase_visual_language.dart';

/// **Lo que ya está en bodega**, como tabla y no como párrafos.
///
/// Misma corrección que la tabla de proveedores: la comparación que esta
/// superficie existe para resolver —cuánto hay de cada cosa— vivía dentro de
/// frases y ninguna columna alineaba.
///
/// Geometría de `handoff-t23` para `single-stock`: fila con miniatura de 38,
/// columna de cantidad de 104 y hairline superior; la salvedad se publica una
/// vez al pie.
class StockCandidatesTable extends StatelessWidget {
  const StockCandidatesTable({
    super.key,
    required this.report,
    required this.busy,
    required this.onChoose,
  });

  final StockCandidateReport report;
  final bool busy;
  final void Function(StockCandidate item) onChoose;

  @override
  Widget build(BuildContext context) {
    if (report.isEmpty) return const SizedBox.shrink();
    final tokens = PurchaseTokens.of(context);
    final conStock = report.withStock;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          conStock > 0
              ? 'Esto ya está en bodega'
              : 'Está en el catálogo, pero sin unidades',
          style: PurchaseType.sectionTitle.copyWith(color: tokens.ink),
        ),
        const SizedBox(height: 3),
        Text(
          _lead(report),
          style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
        ),
        const SizedBox(height: 9),
        PurchasePanel(
          padded: false,
          child: Column(
            key: const ValueKey('stock-candidates-table'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: tokens.sunken,
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'EN BODEGA',
                        style: PurchaseType.label
                            .copyWith(color: tokens.inkFaint),
                      ),
                    ),
                    SizedBox(
                      width: 104,
                      child: Text(
                        'DISPONIBLE',
                        textAlign: TextAlign.end,
                        style: PurchaseType.label
                            .copyWith(color: tokens.inkFaint),
                      ),
                    ),
                    SizedBox(width: _chooseWidth(context)),
                  ],
                ),
              ),
              for (final item in report.items)
                _StockRow(item: item, busy: busy, onChoose: () => onChoose(item)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Confirmar el producto no reserva ni descuenta inventario: eso ocurre '
          'al despachar.',
          style: PurchaseType.meta.copyWith(color: tokens.inkFaint),
        ),
      ],
    );
  }

  static String _lead(StockCandidateReport report) {
    final conStock = report.withStock;
    final base = conStock > 0
        ? '$conStock de ${report.totalMatches} '
            '${report.totalMatches == 1 ? 'coincidencia' : 'coincidencias'} '
            '${conStock == 1 ? 'tiene' : 'tienen'} unidades'
        : 'Ninguna de las ${report.totalMatches} coincidencias tiene unidades';
    final widened = report.widenedLabel;
    return widened == null ? base : '$base · $widened';
  }
}

/// Igual que en la tabla de proveedores: el ancho de la orden se mide contra
/// la tipografía real, no se declara. Aquí eran 78 px.
double _chooseWidth(BuildContext context) =>
    purchaseInlineActionWidth(context, const ['Es este']);

class _StockRow extends StatelessWidget {
  const _StockRow({
    required this.item,
    required this.busy,
    required this.onChoose,
  });

  final StockCandidate item;
  final bool busy;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.hair)),
      ),
      child: Row(
        children: [
          _ProductMonogram(name: item.name),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PurchaseType.rowTitle.copyWith(color: tokens.ink),
                ),
                Text(
                  _identity(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 104,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  item.hasStock ? _quantity(item.available) : '0',
                  style: PurchaseType.metricSmall.copyWith(
                    // Sólo la excepción destaca: lo que hay se lee en el color
                    // de acción, lo que está en cero queda secundario y visible.
                    color: item.hasStock ? tokens.act : tokens.inkFaint,
                    fontFeatures: PurchaseType.tabular,
                  ),
                ),
                Text(
                  item.hasStock ? 'unidades' : 'sin unidades',
                  style: PurchaseType.meta.copyWith(color: tokens.inkFaint),
                ),
              ],
            ),
          ),
          SizedBox(
            width: _chooseWidth(context),
            child: Align(
              alignment: Alignment.centerRight,
              child: PurchaseInlineAction(
                key: ValueKey('use-stock-candidate-${item.productId}'),
                label: 'Es este',
                onPressed: busy ? null : onChoose,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _quantity(double value) =>
      value == value.roundToDouble() ? value.round().toString() : '$value';

  static String _identity(StockCandidate item) {
    final partes = <String>[
      if (item.brand != null) item.brand!,
      if (item.sku != null) 'SKU ${item.sku}',
      if (item.priceGross != null)
        PurchaseMoney.format(item.priceGross!, 'CLP'),
    ];
    return partes.isEmpty ? 'sin ficha comercial' : partes.join(' · ');
  }
}

/// Sin foto en la ficha, el contrato de imagen manda monograma sobre superficie
/// hundida, con la misma geometría para que la fila no cambie de alto.
class _ProductMonogram extends StatelessWidget {
  const _ProductMonogram({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final words = name
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
        letters,
        style: PurchaseType.label.copyWith(color: tokens.inkMuted),
      ),
    );
  }
}
