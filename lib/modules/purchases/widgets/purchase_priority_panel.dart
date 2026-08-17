/// «Qué hay que comprar»: con esto abre el módulo.
///
/// La brecha más grande de alguien sin experiencia no es a qué proveedor
/// comprarle: es **no saber que hay que comprar**. Un campo de texto vacío le
/// pide justo lo que no tiene. Esta superficie se lo dice, y le dice por qué.
///
/// Cada fila lleva su razón en palabras —«Se agotó y se vendió 3 veces en los
/// últimos 120 días»—. Esa línea es la transferencia de experiencia; sin ella
/// la lista es un inventario más.
///
/// Dos decisiones que la hacen mirable y no sólo correcta:
/// - **Se agrupa por urgencia**, porque la primera pregunta de quien llega en
///   la mañana es qué es lo más apurado, no a quién comprarle.
/// - **Se corta la cola larga.** La medición sobre producción da ~100 filas
///   accionables; mostrarlas todas de golpe vuelve a ser el muro que este panel
///   existe para evitar.
library;

import 'package:flutter/material.dart';

import '../models/intelligent_purchasing_models.dart';
import 'purchase_visual_language.dart';

class PurchasePriorityPanel extends StatefulWidget {
  const PurchasePriorityPanel({
    super.key,
    required this.suggestions,
    required this.onTake,
    this.busyEntityId,
    this.loading = false,
  });

  final List<PurchasePrioritySuggestion> suggestions;
  final ValueChanged<PurchasePrioritySuggestion> onTake;
  final String? busyEntityId;
  final bool loading;

  @override
  State<PurchasePriorityPanel> createState() => _PurchasePriorityPanelState();
}

class _PurchasePriorityPanelState extends State<PurchasePriorityPanel> {
  /// Cuántas filas se ven antes de pedirlo. Lo que un ojo recorre sin barrer.
  static const int _visibleCap = 6;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final all = widget.suggestions;
    final visible = _expanded || all.length <= _visibleCap
        ? all
        : all.take(_visibleCap).toList(growable: false);
    final hidden = all.length - visible.length;

    return PurchasePanel(
      padded: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 12, 13, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Qué hay que comprar',
                  style: PurchaseType.surfaceTitle.copyWith(color: tokens.ink),
                ),
                const SizedBox(height: 3),
                Text(
                  _lead(all),
                  style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
                ),
              ],
            ),
          ),
          for (final entry in _grouped(visible)) ...[
            if (entry.header != null)
              _GroupHeader(label: entry.header!, count: entry.count),
            for (final suggestion in entry.items)
              _PriorityRow(
                key: ValueKey('purchase-priority-${suggestion.entityId}'),
                suggestion: suggestion,
                busy: widget.busyEntityId == suggestion.entityId,
                onTake: () => widget.onTake(suggestion),
              ),
          ],
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 9, 13, 11),
              child: Align(
                alignment: Alignment.centerLeft,
                child: PurchaseInlineAction(
                  key: const ValueKey('purchase-priority-expand'),
                  label: 'Ver $hidden más',
                  onPressed: () => setState(() => _expanded = true),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _lead(List<PurchasePrioritySuggestion> all) {
    if (widget.loading) return 'Revisando trabajos, quiebres y mínimos…';
    if (all.isEmpty) {
      return 'Nada urgente por ahora: ningún trabajo espera repuesto y lo que '
          'rota está cubierto.';
    }
    final workshop = all.where((item) => item.isWorkshop).length;
    final rest = all.length - workshop;
    final parts = <String>[
      if (workshop > 0)
        workshop == 1
            ? 'un trabajo esperando repuesto'
            : '$workshop trabajos esperando repuesto',
      if (rest > 0)
        rest == 1 ? 'un producto que rota' : '$rest productos que rotan',
    ];
    return '${parts.join(' y ')}. Nada de esto compra todavía.';
  }

  /// Agrupa conservando el orden de urgencia que ya trae el servidor.
  ///
  /// Con una sola familia presente no se dibuja encabezado: rotular un grupo
  /// único es ruido.
  List<({String? header, int count, List<PurchasePrioritySuggestion> items})>
      _grouped(List<PurchasePrioritySuggestion> items) {
    final groups = <({
      String? header,
      int count,
      List<PurchasePrioritySuggestion> items
    })>[];
    String? currentSource;
    var current = <PurchasePrioritySuggestion>[];
    for (final item in items) {
      if (item.source != currentSource) {
        if (current.isNotEmpty) {
          groups.add((
            header: _headerFor(currentSource!),
            count: current.length,
            items: current,
          ));
        }
        currentSource = item.source;
        current = <PurchasePrioritySuggestion>[];
      }
      current.add(item);
    }
    if (current.isNotEmpty) {
      groups.add((
        header: _headerFor(currentSource!),
        count: current.length,
        items: current,
      ));
    }
    if (groups.length == 1) {
      return [
        (header: null, count: groups.first.count, items: groups.first.items)
      ];
    }
    return groups;
  }

  static String _headerFor(String source) => switch (source) {
        'workshop' => 'Un trabajo lo está esperando',
        'stockout' => 'Se agotó y se vende',
        _ => 'Bajo el mínimo',
      };
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 8, 13, 7),
      decoration: BoxDecoration(
        color: tokens.sunken,
        border: Border(top: BorderSide(color: tokens.hair)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: PurchaseType.label.copyWith(color: tokens.inkFaint),
            ),
          ),
          Text(
            '$count',
            style: PurchaseType.label.copyWith(color: tokens.inkFaint),
          ),
        ],
      ),
    );
  }
}

class _PriorityRow extends StatelessWidget {
  const _PriorityRow({
    super.key,
    required this.suggestion,
    required this.busy,
    required this.onTake,
  });

  final PurchasePrioritySuggestion suggestion;
  final bool busy;
  final VoidCallback onTake;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.hair)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  suggestion.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: PurchaseType.rowTitle.copyWith(color: tokens.ink),
                ),
                const SizedBox(height: 2),
                // El porqué, en palabras. Nunca un puntaje.
                Text(
                  suggestion.reason,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              _quantityLabel(suggestion),
              style: PurchaseType.metricSmall.copyWith(color: tokens.ink),
            ),
          ),
          const SizedBox(width: 12),
          PurchaseInlineAction(
            label: busy ? 'Abriendo…' : 'Buscar',
            onPressed: busy ? null : onTake,
          ),
        ],
      ),
    );
  }

  static String _quantityLabel(PurchasePrioritySuggestion suggestion) {
    final quantity = suggestion.suggestedQuantity;
    final rounded = quantity == quantity.roundToDouble()
        ? quantity.toStringAsFixed(0)
        : quantity.toStringAsFixed(2);
    return suggestion.unit == 'unit' ? rounded : '$rounded ${suggestion.unit}';
  }
}
