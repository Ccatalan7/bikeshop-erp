import 'package:flutter/material.dart';

import '../../modules/inventory/models/product_duplicate_candidate.dart';
import 'vb_money_text.dart';
import 'vb_status_badge.dart';

/// One presentation for the cached evidence in both the batch and its picker.
/// The model's ordering score is never a measured probability.
class OcrCandidateEvidence {
  const OcrCandidateEvidence(this.label, this.tone);
  factory OcrCandidateEvidence.forCandidate(
      ProductDuplicateCandidate candidate) {
    if (candidate.isReviewOnlyFamilyScope) {
      return const OcrCandidateEvidence(
          'Revisión manual', VbStatusTone.warning);
    }
    return switch (candidate.matchTier) {
      ProductDuplicateMatchTier.exact => const OcrCandidateEvidence(
          'Coincidencia directa', VbStatusTone.success),
      ProductDuplicateMatchTier.strong =>
        const OcrCandidateEvidence('Muy parecido', VbStatusTone.warning),
      ProductDuplicateMatchTier.possible =>
        const OcrCandidateEvidence('Podría ser', VbStatusTone.neutral),
      ProductDuplicateMatchTier.ruledOut =>
        const OcrCandidateEvidence('Descartado', VbStatusTone.warning),
    };
  }
  final String label;
  final VbStatusTone tone;
}

/// Translate the provider's closed evidence vocabulary, preserving real reasons.
/// This is display formatting only; it never changes ranking or identity.
String ocrReadableEvidence(String reason) {
  const prefix = 'Evidencia de IA:';
  if (!reason.startsWith(prefix)) return reason;
  const labels = <String, String>{
    'object': 'tipo de pieza',
    'function': 'función',
    'shape': 'forma',
    'model': 'modelo',
    'spec': 'medidas',
    'manufacturer': 'fabricante',
    'image': 'fotografía',
    'name': 'nombre',
    'variant': 'variante',
    'packaging': 'presentación',
    'composition': 'componentes',
  };
  final tokens = reason
      .substring(prefix.length)
      .replaceAll(RegExp(r'[.]$'), '')
      .split(',')
      .map((value) => value.trim());
  final readable = tokens.map((value) => labels[value] ?? value).join(', ');
  return 'Comparación de $readable';
}

String ocrReviewNumber(num? value) {
  if (value == null) return '—';
  return value == value.roundToDouble()
      ? value.round().toString()
      : value.toString();
}

@immutable
class OcrReviewComponent {
  const OcrReviewComponent(
      {required this.productId,
      required this.name,
      required this.sku,
      required this.unitsPerPurchase,
      required this.totalQuantity,
      required this.role,
      required this.costRatio});
  final String productId;
  final String name;
  final String sku;
  final int unitsPerPurchase;
  final double totalQuantity;
  final String role;
  final double costRatio;
  String get roleLabel => switch (role) {
        'front' => 'delantero',
        'rear' => 'trasero',
        'left' => 'izquierdo',
        'right' => 'derecho',
        'homogeneous' => 'unidades iguales',
        'catalog_set' => 'juego del catálogo',
        _ => '',
      };
}

/// F-03 CLP presentation: distribute the display rounding remainder instead of
/// showing component totals that contradict the displayed source total.
/// This is not the purchase writer or the canonical financial allocation.
List<int>? ocrComponentDisplayCosts(
    List<OcrReviewComponent> parts, num? total) {
  if (total == null ||
      !total.isFinite ||
      total < 0 ||
      parts.isEmpty ||
      parts.any((part) => !part.costRatio.isFinite || part.costRatio <= 0)) {
    return null;
  }
  final sum = parts.fold<double>(0, (value, part) => value + part.costRatio);
  if ((sum - 1).abs() > 0.000001) return null;
  final amount = total.round();
  final raw = parts.map((part) => amount * part.costRatio / sum).toList();
  final costs = raw.map((value) => value.floor()).toList();
  final order = List<int>.generate(parts.length, (index) => index)
    ..sort((a, b) {
      final difference = (raw[b] - costs[b]).compareTo(raw[a] - costs[a]);
      return difference == 0 ? a.compareTo(b) : difference;
    });
  final remainder = amount - costs.fold<int>(0, (sum, value) => sum + value);
  for (var index = 0; index < remainder; index++) {
    costs[order[index]]++;
  }
  return costs;
}

/// Same typed composition in the line detail and candidate picker. Roles remain
/// distinct even when two components share a SKU. No parsing of display prose.
class OcrCompositionReview extends StatelessWidget {
  const OcrCompositionReview(
      {super.key,
      required this.components,
      required this.sourceQuantity,
      required this.sourceTotal});
  final List<OcrReviewComponent> components;
  final double? sourceQuantity;
  final double? sourceTotal;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final costs = ocrComponentDisplayCosts(components, sourceTotal);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(
          '${ocrReviewNumber(sourceQuantity)} compras → ${components.map((part) => '${ocrReviewNumber(part.totalQuantity)} × ${part.sku}').join(' + ')}',
          style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      Text('Las cantidades están expresadas en unidades del catálogo.',
          style: theme.textTheme.bodySmall),
      const SizedBox(height: 8),
      for (var i = 0; i < components.length; i++) ...[
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(components[i].name,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text(
                        '${components[i].sku}${components[i].roleLabel.isEmpty ? '' : ' · ${components[i].roleLabel}'}',
                        style: theme.textTheme.labelSmall),
                    const SizedBox(height: 4),
                    Text(
                        '${ocrReviewNumber(sourceQuantity)} compras × ${components[i].unitsPerPurchase} por compra = ${ocrReviewNumber(components[i].totalQuantity)} unidades',
                        key: ValueKey('ocr-composition-equation-$i'),
                        style: theme.textTheme.bodySmall),
                  ])),
              const SizedBox(width: 12),
              if (costs != null) VbMoneyText(costs[i]),
            ])),
        const Divider(height: 1),
      ],
      const SizedBox(height: 8),
      Text(
          costs == null
              ? 'El reparto del costo requiere revisión.'
              : 'Costo repartido según la composición. El total de la compra se conserva.',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    ]);
  }
}
