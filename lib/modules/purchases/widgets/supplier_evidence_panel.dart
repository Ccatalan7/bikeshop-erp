import 'package:flutter/material.dart';

import '../models/intelligent_purchasing_models.dart';
import 'purchase_visual_language.dart';

/// **Por qué este proveedor quedó ahí**, con la evidencia mirable.
///
/// La versión anterior contestaba la pregunta en dos oraciones corridas —«15%
/// del gasto (pesa 55%) · 15% de las unidades (20%) · recencia (15%) · 1
/// producto distintos (10%)»— y listaba cada compra como otra oración con
/// puntos medios. El dueño lo llamó por su nombre: bloques de código.
///
/// Aquí el criterio se ve como criterio —cuánto pesa cada cosa y qué número
/// puso este proveedor— y las compras que lo respaldan son una tabla, porque
/// son filas comparables: producto, cantidad, costo unitario y en qué factura.
class SupplierEvidencePanel extends StatelessWidget {
  const SupplierEvidencePanel({super.key, required this.evidence});

  final SupplierEvidence evidence;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
      decoration: BoxDecoration(
        color: tokens.sunken,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.hair),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Qué lo puso ahí',
            style: PurchaseType.rowTitle.copyWith(color: tokens.ink),
          ),
          const SizedBox(height: 8),
          // Cuatro criterios con su peso: publicar el número sin decir cuánto
          // pesó deja al operador adivinando cuál mandó.
          Wrap(
            spacing: 20,
            runSpacing: 12,
            children: [
              _Criterion(
                label: 'Gasto',
                value: _percent(evidence.spendSharePercent),
                weight: 55,
              ),
              _Criterion(
                label: 'Unidades',
                value: _percent(evidence.unitsSharePercent),
                weight: 20,
              ),
              _Criterion(
                label: 'Recencia',
                value: evidence.lastPurchaseAt == null
                    ? 'sin compras'
                    : _date(evidence.lastPurchaseAt!),
                weight: 15,
                muted: evidence.lastPurchaseAt == null,
              ),
              _Criterion(
                label: 'Productos',
                value: '${evidence.distinctProducts}',
                weight: 10,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _base(evidence),
            style: PurchaseType.meta.copyWith(color: tokens.inkFaint),
          ),
          for (final need in evidence.needs) ...[
            const SizedBox(height: 12),
            Text(
              need.need,
              style: PurchaseType.meta.copyWith(
                color: tokens.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            if (need.hasPurchases)
              _EvidenceTable(
                columns: const ['Producto', 'Cantidad', 'Costo unitario',
                    'Factura'],
                rows: [
                  for (final purchase in need.purchases)
                    _EvidenceRow(
                      title: purchase.productName,
                      caption: _purchaseCaption(purchase),
                      cells: [
                        _Cell(
                          value: purchase.quantity == null
                              ? '—'
                              : _quantity(purchase.quantity!),
                          caption: purchase.quantity == null ? null : 'un',
                        ),
                        _Cell(
                          value: purchase.landedUnitCostNet == null
                              ? '—'
                              : PurchaseMoney.format(
                                  purchase.landedUnitCostNet!, 'CLP'),
                          caption: purchase.landedUnitCostNet == null
                              ? null
                              : 'c/u con flete',
                        ),
                        _Cell(
                          value: purchase.invoiceNumber ?? '—',
                          caption: purchase.purchaseDate == null
                              ? null
                              : _date(purchase.purchaseDate!),
                        ),
                      ],
                    ),
                ],
              )
            else if (need.catalog.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  'Sin compras registradas de esto. Lo que tiene catalogado:',
                  style: PurchaseType.meta.copyWith(color: tokens.inkFaint),
                ),
              ),
              _EvidenceTable(
                columns: const ['Producto', 'En bodega', 'Costo'],
                rows: [
                  for (final item in need.catalog)
                    _EvidenceRow(
                      title: item.productName,
                      caption: _catalogCaption(item),
                      cells: [
                        _Cell(
                          value: item.stock == null
                              ? '—'
                              : _quantity(item.stock!),
                          caption: item.stock == null ? null : 'unidades',
                        ),
                        _Cell(
                          value: item.costNet == null
                              ? '—'
                              : PurchaseMoney.format(item.costNet!, 'CLP'),
                          caption: item.costNet == null ? null : 'neto',
                        ),
                      ],
                    ),
                ],
              ),
            ] else
              Text(
                'Sin compras ni productos catalogados de esta línea.',
                style: PurchaseType.meta.copyWith(color: tokens.inkFaint),
              ),
          ],
        ],
      ),
    );
  }

  static String _base(SupplierEvidence evidence) {
    final facturas = evidence.purchaseInvoices;
    return 'Sobre ${evidence.purchaseLines} de ${evidence.totalPurchaseLines} '
        'líneas analizadas entre ${evidence.totalSuppliers} proveedores · '
        '$facturas ${facturas == 1 ? 'factura' : 'facturas'} · '
        '${PurchaseMoney.format(evidence.landedSpendNet, 'CLP')} aterrizado';
  }

  static String? _purchaseCaption(SupplierEvidencePurchase purchase) {
    final partes = <String>[
      if (purchase.brand != null) purchase.brand!,
      if (purchase.productSku != null) 'SKU ${purchase.productSku}',
    ];
    return partes.isEmpty ? null : partes.join(' · ');
  }

  static String? _catalogCaption(SupplierEvidenceCatalogItem item) {
    final partes = <String>[
      if (item.brand != null) item.brand!,
      if (item.productSku != null) 'SKU ${item.productSku}',
    ];
    return partes.isEmpty ? null : partes.join(' · ');
  }

  static String _percent(double value) =>
      '${value.toStringAsFixed(value >= 10 ? 0 : 1).replaceAll('.', ',')}%';

  static String _quantity(double value) =>
      value == value.roundToDouble() ? value.round().toString() : '$value';

  /// «7 abr 2026». Los meses van escritos acá y no por `intl`: el panel se
  /// dibuja dentro de una fila y una inicialización de locale que falle dejaría
  /// la evidencia en blanco justo cuando el operador la abrió.
  static const List<String> _meses = <String>[
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic',
  ];

  static String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.day} ${_meses[local.month - 1]} ${local.year}';
  }
}

/// Un criterio del ranking: su número y cuánto pesó, con la barra sobre 100.
///
/// La barra mide el **peso**, no el valor: es lo único comparable entre los
/// cuatro. Normalizarla al peso mayor haría ver 55% como si fuera todo.
class _Criterion extends StatelessWidget {
  const _Criterion({
    required this.label,
    required this.value,
    required this.weight,
    this.muted = false,
  });

  final String label;
  final String value;
  final int weight;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return SizedBox(
      width: 148,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: PurchaseType.label.copyWith(color: tokens.inkFaint),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PurchaseType.metricSmall.copyWith(
              color: muted ? tokens.inkFaint : tokens.ink,
              fontFeatures: PurchaseType.tabular,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: weight / 100,
                    minHeight: 3,
                    backgroundColor: tokens.hair,
                    valueColor: AlwaysStoppedAnimation<Color>(tokens.act),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'pesa $weight%',
                style: PurchaseType.meta.copyWith(color: tokens.inkFaint),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Cell {
  const _Cell({required this.value, this.caption});

  final String value;
  final String? caption;
}

class _EvidenceRow {
  const _EvidenceRow({
    required this.title,
    required this.caption,
    required this.cells,
  });

  final String title;
  final String? caption;
  final List<_Cell> cells;
}

/// Las compras que respaldan al proveedor, como tabla.
///
/// La primera columna es la identidad y se estira; el resto son números
/// comparables, alineados a la derecha para que dos filas se miren de una vez.
/// Al estrecharse cae la columna **más a la derecha** primero: la factura
/// identifica, no compara.
class _EvidenceTable extends StatelessWidget {
  const _EvidenceTable({required this.columns, required this.rows});

  final List<String> columns;
  final List<_EvidenceRow> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Cuántas columnas de número caben. Se declara en número porque es una
        // decisión de producto, no una medida de tipografía.
        final metrics = columns.length - 1;
        final visible = constraints.maxWidth >= 520
            ? metrics
            : constraints.maxWidth >= 380
                ? (metrics - 1).clamp(1, metrics)
                : 1;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Expanded(
                    flex: 24,
                    child: Text(
                      columns.first.toUpperCase(),
                      style: PurchaseType.label
                          .copyWith(color: tokens.inkFaint),
                    ),
                  ),
                  for (var i = 0; i < visible; i++)
                    Expanded(
                      flex: 15,
                      child: Text(
                        columns[i + 1].toUpperCase(),
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PurchaseType.label
                            .copyWith(color: tokens.inkFaint),
                      ),
                    ),
                ],
              ),
            ),
            for (final row in rows)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: tokens.hair)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      flex: 24,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PurchaseType.meta.copyWith(
                              color: tokens.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (row.caption != null)
                            Text(
                              row.caption!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: PurchaseType.meta
                                  .copyWith(color: tokens.inkFaint),
                            ),
                        ],
                      ),
                    ),
                    for (var i = 0; i < visible; i++)
                      Expanded(
                        flex: 15,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              row.cells[i].value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: PurchaseType.meta.copyWith(
                                color: tokens.ink,
                                fontFeatures: PurchaseType.tabular,
                              ),
                            ),
                            if (row.cells[i].caption != null)
                              Text(
                                row.cells[i].caption!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PurchaseType.meta
                                    .copyWith(color: tokens.inkFaint),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
