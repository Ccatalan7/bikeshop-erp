/// Cierre del plan: totales y el paso final, ambos del `spec.json` del t23.
///
/// Faltaban los dos en `lib/`. El resumen que abrió este trabajo decía que
/// quedaban «fuera del recorte de las imágenes de Design»; es falso — el spec
/// los define completos en `frames[plan].with_lines`, con sus tres totales, la
/// etiqueta exacta del paso final y sus tres filas de confirmación.
///
/// Dos reglas del contrato de datos que esta superficie hace cumplir:
/// - **CLP y USD no se suman.** Viajan en subtotales separados y el de USD se
///   rotula como no sumado; sin fuente FX autorizada no hay conversión.
/// - **Sin precio de venta vigente el margen es «sin base», nunca cero.**
library;

import 'package:flutter/material.dart';

import '../models/intelligent_purchasing_models.dart';
import 'purchase_visual_language.dart';

/// Totales del plan, separados por moneda, y el paso final inline.
class PurchasePlanClose extends StatefulWidget {
  const PurchasePlanClose({
    super.key,
    required this.lines,
    required this.supplierCount,
    required this.missingCount,
  });

  final List<PurchasePlanLine> lines;
  final int supplierCount;

  /// Lo que queda fuera: faltantes y líneas que requieren precisión.
  final int missingCount;

  @override
  State<PurchasePlanClose> createState() => _PurchasePlanCloseState();
}

class _PurchasePlanCloseState extends State<PurchasePlanClose> {
  bool _confirming = false;
  bool _done = false;

  /// Subtotal por moneda. Nunca se mezclan.
  Map<String, double> get _subtotals {
    final totals = <String, double>{};
    for (final line in widget.lines) {
      final cost = line.landedUnitCostNet;
      if (cost == null) continue;
      totals[line.currency] =
          (totals[line.currency] ?? 0) + cost * line.quantity;
    }
    return totals;
  }

  /// Margen ponderado por valor de línea, sólo sobre lo que tiene base.
  ///
  /// `null` significa «sin base»: ninguna línea trae precio de venta vigente.
  /// Devolver cero ahí sería afirmar que no hay margen, que es otra cosa.
  ({double ratio, int covered})? get _margin {
    var weighted = 0.0;
    var weight = 0.0;
    var covered = 0;
    for (final line in widget.lines) {
      final ratio = line.projectedGrossMarginRatio;
      final cost = line.landedUnitCostNet;
      if (ratio == null || cost == null) continue;
      final value = cost * line.quantity;
      weighted += ratio * value;
      weight += value;
      covered += 1;
    }
    if (weight <= 0) return null;
    return (ratio: weighted / weight, covered: covered);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final subtotals = _subtotals;
    final margin = _margin;
    final currencies = subtotals.keys.toList()..sort();

    return PurchasePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final currency in currencies)
            _TotalRow(
              label: 'SUBTOTAL $currency',
              value: _money(currency, subtotals[currency]!),
              // El spec rotula el segundo como no sumado: son dos totales, no
              // uno partido en dos.
              note: currency == currencies.first ? null : 'no se suma',
            ),
          _TotalRow(
            label: 'MARGEN PROYECTADO',
            value: margin == null
                ? 'sin base'
                : '${(margin.ratio * 100).toStringAsFixed(1)} %',
            note: margin == null
                ? 'ninguna línea tiene precio de venta vigente'
                : margin.covered == widget.lines.length
                    ? null
                    : 'sobre ${margin.covered} de ${widget.lines.length} líneas',
          ),
          const SizedBox(height: 11),
          if (_done)
            Text(
              'Listo · no se creó ninguna compra',
              key: const ValueKey('plan-close-done'),
              style: PurchaseType.body.copyWith(color: tokens.inkMuted),
            )
          else if (!_confirming)
            Align(
              alignment: Alignment.centerLeft,
              child: PurchasePrimaryButton(
                key: const ValueKey('plan-prepare-documents'),
                label: 'Preparar documentos de compra',
                onPressed: widget.lines.isEmpty
                    ? null
                    : () => setState(() => _confirming = true),
              ),
            )
          else ...[
            // Paso de confirmación **inline**, al pie del plan. El spec lo
            // prohíbe como modal, y este módulo no admite velo.
            Container(
              key: const ValueKey('plan-close-confirm'),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: tokens.sunken,
                borderRadius:
                    BorderRadius.circular(PurchaseMetrics.fieldRadius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ConfirmRow(
                    label: 'PROVEEDORES',
                    value: '${widget.supplierCount}',
                  ),
                  _ConfirmRow(
                    label: 'LÍNEAS',
                    value: '${widget.lines.length}',
                  ),
                  _ConfirmRow(
                    label: 'QUEDA FUERA',
                    value: widget.missingCount == 0
                        ? 'nada'
                        : '${widget.missingCount}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: PurchaseMetrics.actionsTopGap),
            Row(
              children: [
                PurchasePrimaryButton(
                  key: const ValueKey('plan-close-confirm-action'),
                  label: 'Preparar',
                  onPressed: () => setState(() {
                    _confirming = false;
                    _done = true;
                  }),
                ),
                const SizedBox(width: PurchaseMetrics.actionsGap),
                PurchaseInlineAction(
                  label: 'Cancelar',
                  onPressed: () => setState(() => _confirming = false),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Preparar deja los documentos listos para revisar. No compra, no '
            'reserva stock y no emite nada.',
            style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
          ),
        ],
      ),
    );
  }

  static String _money(String currency, double value) =>
      '$currency ${value.toStringAsFixed(0)}';
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.note});

  final String label;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(label,
              style: PurchaseType.label.copyWith(color: tokens.inkFaint)),
          if (note != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                note!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
              ),
            ),
          ] else
            const Spacer(),
          const SizedBox(width: 8),
          Text(
            value,
            style: PurchaseType.metricSmall.copyWith(color: tokens.ink),
          ),
        ],
      ),
    );
  }
}

class _ConfirmRow extends StatelessWidget {
  const _ConfirmRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Text(label,
              style: PurchaseType.label.copyWith(color: tokens.inkFaint)),
          const Spacer(),
          Text(
            value,
            style: PurchaseType.metricSmall.copyWith(color: tokens.ink),
          ),
        ],
      ),
    );
  }
}
