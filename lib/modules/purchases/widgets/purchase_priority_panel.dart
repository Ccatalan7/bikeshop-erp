/// «Qué hay que comprar»: con esto abre el módulo.
///
/// La cola es una **tabla de decisiones**, no una lista de párrafos. Producto,
/// trabajo, bicicleta, fecha de ingreso y cantidad ocupan columnas comparables
/// en tablet/escritorio. En teléfono la misma información se recompone como
/// una fila vertical rotulada; nunca se encoge la tabla hasta volverla ilegible.
///
/// La selección múltiple no compra nada. Arma la canasta canónica del
/// asistente para buscar cobertura conjunta entre proveedores. Cada fila de
/// taller conserva su `supply_need` existente; las señales de stock sólo se
/// vuelven necesidades al confirmar «Buscar juntos».
library;

import 'package:flutter/material.dart';

import '../../../shared/utils/chilean_utils.dart';
import '../models/intelligent_purchasing_models.dart';
import '../pages/intelligent_purchasing_surfaces.dart';
import 'purchase_visual_language.dart';

class PurchasePriorityPanel extends StatefulWidget {
  const PurchasePriorityPanel({
    super.key,
    required this.suggestions,
    required this.onTake,
    required this.selectedEntityIds,
    required this.onSelectionChanged,
    required this.onSearchSelected,
    this.busyEntityId,
    this.searchingSelection = false,
    this.loading = false,
  });

  final List<PurchasePrioritySuggestion> suggestions;
  final ValueChanged<PurchasePrioritySuggestion> onTake;

  /// Controlled state: the workspace owns it so selection survives an
  /// adaptive recomposition between table and phone rows.
  final Set<String> selectedEntityIds;
  final ValueChanged<Set<String>> onSelectionChanged;
  final VoidCallback onSearchSelected;

  final String? busyEntityId;
  final bool searchingSelection;
  final bool loading;

  @override
  State<PurchasePriorityPanel> createState() => _PurchasePriorityPanelState();
}

class _PurchasePriorityPanelState extends State<PurchasePriorityPanel> {
  /// Cuántas filas se ven antes de pedirlo. Lo que un ojo recorre sin barrer.
  static const int _visibleCap = 6;

  /// Es también el límite transaccional del comando y de la canasta canónica.
  static const int _selectionCap = 8;

  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final all = widget.suggestions;
    final visible = _expanded || all.length <= _visibleCap
        ? all
        : all.take(_visibleCap).toList(growable: false);
    final hidden = all.length - visible.length;
    final validIds = all.map((item) => item.entityId).toSet();
    final selected = widget.selectedEntityIds.where(validIds.contains).toSet();

    return PurchasePanel(
      padded: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PriorityIntro(
            lead: _lead(all),
            selectedCount: selected.length,
            searching: widget.searchingSelection,
            onSearch: selected.length >= 2 && !widget.searchingSelection
                ? widget.onSearchSelected
                : null,
          ),
          if (visible.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                final table = constraints.maxWidth >= 600;
                final visibleIds = visible
                    .map((item) => item.entityId)
                    .toList(growable: false);
                final selectedVisible =
                    visibleIds.where(selected.contains).length;
                final bool? allValue = selectedVisible == 0
                    ? false
                    : selectedVisible == visibleIds.length
                        ? true
                        : null;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (table)
                      _PriorityTableHeader(
                        value: allValue,
                        enabled: !widget.searchingSelection,
                        onChanged: (value) => _toggleVisible(
                          visible,
                          selected,
                          value == true,
                        ),
                      )
                    else
                      _CompactSelectionBar(
                        value: allValue,
                        selectedCount: selected.length,
                        enabled: !widget.searchingSelection,
                        onChanged: (value) => _toggleVisible(
                          visible,
                          selected,
                          value == true,
                        ),
                      ),
                    for (final entry in _grouped(visible)) ...[
                      if (entry.header != null)
                        _GroupHeader(label: entry.header!, count: entry.count),
                      for (final suggestion in entry.items)
                        if (table)
                          _PriorityTableRow(
                            key: ValueKey(
                              'purchase-priority-${suggestion.entityId}',
                            ),
                            suggestion: suggestion,
                            selected: selected.contains(suggestion.entityId),
                            selectionEnabled: !widget.searchingSelection &&
                                (selected.length < _selectionCap ||
                                    selected.contains(suggestion.entityId)),
                            busy: widget.busyEntityId == suggestion.entityId ||
                                widget.searchingSelection,
                            onSelected: (value) => _toggleOne(
                              suggestion.entityId,
                              selected,
                              value,
                            ),
                            onTake: () => widget.onTake(suggestion),
                          )
                        else
                          _PriorityCompactRow(
                            key: ValueKey(
                              'purchase-priority-${suggestion.entityId}',
                            ),
                            suggestion: suggestion,
                            selected: selected.contains(suggestion.entityId),
                            selectionEnabled: !widget.searchingSelection &&
                                (selected.length < _selectionCap ||
                                    selected.contains(suggestion.entityId)),
                            busy: widget.busyEntityId == suggestion.entityId ||
                                widget.searchingSelection,
                            onSelected: (value) => _toggleOne(
                              suggestion.entityId,
                              selected,
                              value,
                            ),
                            onTake: () => widget.onTake(suggestion),
                          ),
                    ],
                  ],
                );
              },
            ),
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
          if (all.isNotEmpty && selected.length == 1)
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 0, 13, 10),
              child: Text(
                'Selecciona una fila más para buscar proveedores en conjunto.',
                key: const ValueKey('purchase-priority-selection-hint'),
                style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
              ),
            ),
        ],
      ),
    );
  }

  void _toggleOne(String entityId, Set<String> selected, bool value) {
    if (widget.searchingSelection) return;
    final next = Set<String>.from(selected);
    if (value) {
      if (next.length >= _selectionCap) return;
      next.add(entityId);
    } else {
      next.remove(entityId);
    }
    widget.onSelectionChanged(Set<String>.unmodifiable(next));
  }

  void _toggleVisible(
    List<PurchasePrioritySuggestion> visible,
    Set<String> selected,
    bool value,
  ) {
    if (widget.searchingSelection) return;
    final next = Set<String>.from(selected);
    if (value) {
      for (final suggestion in visible) {
        if (next.length >= _selectionCap) break;
        next.add(suggestion.entityId);
      }
    } else {
      next.removeAll(visible.map((item) => item.entityId));
    }
    widget.onSelectionChanged(Set<String>.unmodifiable(next));
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

class _PriorityIntro extends StatelessWidget {
  const _PriorityIntro({
    required this.lead,
    required this.selectedCount,
    required this.searching,
    required this.onSearch,
  });

  final String lead;
  final int selectedCount;
  final bool searching;
  final VoidCallback? onSearch;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final action = FilledButton.icon(
      key: const ValueKey('purchase-priority-search-selected'),
      onPressed: onSearch,
      icon: searching
          ? const SizedBox.square(
              dimension: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.manage_search, size: 18),
      label: Text(
        searching
            ? 'Preparando canasta…'
            : selectedCount == 0
                ? 'Buscar juntos'
                : 'Buscar juntos ($selectedCount)',
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 600;
          final identity = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Qué hay que comprar',
                style: PurchaseType.surfaceTitle.copyWith(color: tokens.ink),
              ),
              const SizedBox(height: 3),
              Text(
                lead,
                style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: PurchaseMetrics.actionsTopGap),
                action,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: identity),
              const SizedBox(width: PurchaseMetrics.actionsGap),
              action,
            ],
          );
        },
      ),
    );
  }
}

class _PriorityTableHeader extends StatelessWidget {
  const _PriorityTableHeader({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool? value;
  final bool enabled;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Container(
      color: tokens.sunken,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Tooltip(
              message: 'Seleccionar hasta 8 filas visibles',
              child: Checkbox(
                key: const ValueKey('purchase-priority-select-visible'),
                value: value,
                tristate: true,
                onChanged: enabled ? onChanged : null,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const _HeadCell(flex: 25, label: 'Producto'),
          const _HeadCell(flex: 10, label: 'Trabajo'),
          const _HeadCell(flex: 15, label: 'Bicicleta'),
          const _HeadCell(flex: 12, label: 'Ingresado'),
          const _HeadCell(flex: 5, label: 'Cant.', alignEnd: true),
          SizedBox(
            width: purchaseInlineActionWidth(
              context,
              const ['Buscar', 'Abriendo…'],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeadCell extends StatelessWidget {
  const _HeadCell({
    required this.flex,
    required this.label,
    this.alignEnd = false,
  });

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

class _CompactSelectionBar extends StatelessWidget {
  const _CompactSelectionBar({
    required this.value,
    required this.selectedCount,
    required this.enabled,
    required this.onChanged,
  });

  final bool? value;
  final int selectedCount;
  final bool enabled;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Container(
      color: tokens.sunken,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      child: Row(
        children: [
          SizedBox.square(
            dimension: PurchaseMetrics.touchTarget,
            child: Checkbox(
              key: const ValueKey('purchase-priority-select-visible'),
              value: value,
              tristate: true,
              onChanged: enabled ? onChanged : null,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          Expanded(
            child: Text(
              'Seleccionar visibles',
              style: PurchaseType.rowTitle.copyWith(color: tokens.ink),
            ),
          ),
          Text(
            selectedCount == 0 ? 'Máximo 8' : '$selectedCount de 8',
            style: PurchaseType.metaNumeric.copyWith(color: tokens.inkMuted),
          ),
        ],
      ),
    );
  }
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

class _PriorityTableRow extends StatelessWidget {
  const _PriorityTableRow({
    super.key,
    required this.suggestion,
    required this.selected,
    required this.selectionEnabled,
    required this.busy,
    required this.onSelected,
    required this.onTake,
  });

  final PurchasePrioritySuggestion suggestion;
  final bool selected;
  final bool selectionEnabled;
  final bool busy;
  final ValueChanged<bool> onSelected;
  final VoidCallback onTake;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    final actionWidth = purchaseInlineActionWidth(
      context,
      const ['Buscar', 'Abriendo…'],
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: selected ? tokens.selected : null,
        border: Border(
          top: BorderSide(color: tokens.hair),
          left: BorderSide(
            color: selected ? tokens.act : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 36,
            child: _PriorityCheckbox(
              suggestion: suggestion,
              selected: selected,
              enabled: selectionEnabled,
              onChanged: onSelected,
            ),
          ),
          Expanded(
            flex: 25,
            child: Row(
              children: [
                ProductMediaTile(
                  key: ValueKey(
                    'purchase-priority-media-${suggestion.entityId}',
                  ),
                  media: suggestion.media,
                  name: suggestion.title,
                  size: PurchaseSurfaceGeometry.mediaTableRow,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        suggestion.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            PurchaseType.rowTitle.copyWith(color: tokens.ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        suggestion.reason,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            PurchaseType.meta.copyWith(color: tokens.inkMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _DataCell(
            flex: 10,
            key: ValueKey('purchase-priority-job-${suggestion.entityId}'),
            value: _jobLabel(suggestion),
          ),
          _DataCell(
            flex: 15,
            key: ValueKey('purchase-priority-bike-${suggestion.entityId}'),
            value: _bikeLabel(suggestion),
          ),
          _DataCell(
            flex: 12,
            key: ValueKey('purchase-priority-entered-${suggestion.entityId}'),
            value: _enteredLabel(suggestion),
            numeric: suggestion.isWorkshop,
          ),
          Expanded(
            flex: 5,
            child: Text(
              _quantityLabel(suggestion),
              textAlign: TextAlign.end,
              style: PurchaseType.metricSmall.copyWith(
                color: tokens.ink,
                fontFeatures: PurchaseType.tabular,
              ),
            ),
          ),
          SizedBox(
            width: actionWidth,
            child: Align(
              alignment: Alignment.centerRight,
              child: PurchaseInlineAction(
                label: busy ? 'Abriendo…' : 'Buscar',
                onPressed: busy ? null : onTake,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  const _DataCell({
    super.key,
    required this.flex,
    required this.value,
    this.numeric = false,
  });

  final int flex;
  final String value;
  final bool numeric;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: (numeric ? PurchaseType.metaNumeric : PurchaseType.meta)
              .copyWith(color: tokens.inkMuted),
        ),
      ),
    );
  }
}

class _PriorityCompactRow extends StatelessWidget {
  const _PriorityCompactRow({
    super.key,
    required this.suggestion,
    required this.selected,
    required this.selectionEnabled,
    required this.busy,
    required this.onSelected,
    required this.onTake,
  });

  final PurchasePrioritySuggestion suggestion;
  final bool selected;
  final bool selectionEnabled;
  final bool busy;
  final ValueChanged<bool> onSelected;
  final VoidCallback onTake;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 9),
      decoration: BoxDecoration(
        color: selected ? tokens.selected : null,
        border: Border(
          top: BorderSide(color: tokens.hair),
          left: BorderSide(
            color: selected ? tokens.act : Colors.transparent,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProductMediaTile(
                key: ValueKey(
                  'purchase-priority-media-${suggestion.entityId}',
                ),
                media: suggestion.media,
                name: suggestion.title,
                size: PurchaseSurfaceGeometry.mediaPhoneCard,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      suggestion.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: PurchaseType.cardTitle.copyWith(color: tokens.ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      suggestion.reason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: PurchaseType.meta.copyWith(color: tokens.inkMuted),
                    ),
                  ],
                ),
              ),
              SizedBox.square(
                dimension: PurchaseMetrics.touchTarget,
                child: _PriorityCheckbox(
                  suggestion: suggestion,
                  selected: selected,
                  enabled: selectionEnabled,
                  onChanged: onSelected,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _CompactField(
                  label: 'Trabajo',
                  value: _jobLabel(suggestion),
                  valueKey: ValueKey(
                    'purchase-priority-job-${suggestion.entityId}',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _CompactField(
                  label: 'Bicicleta',
                  value: _bikeLabel(suggestion),
                  valueKey: ValueKey(
                    'purchase-priority-bike-${suggestion.entityId}',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _CompactField(
                  label: 'Ingresado',
                  value: _enteredLabel(suggestion),
                  valueKey: ValueKey(
                    'purchase-priority-entered-${suggestion.entityId}',
                  ),
                  numeric: suggestion.isWorkshop,
                ),
              ),
              const SizedBox(width: 12),
              _CompactField(
                label: 'Cantidad',
                value: _quantityLabel(suggestion),
                numeric: true,
              ),
              const Spacer(),
              PurchaseInlineAction(
                label: busy ? 'Abriendo…' : 'Buscar',
                onPressed: busy ? null : onTake,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompactField extends StatelessWidget {
  const _CompactField({
    required this.label,
    required this.value,
    this.valueKey,
    this.numeric = false,
  });

  final String label;
  final String value;
  final Key? valueKey;
  final bool numeric;

  @override
  Widget build(BuildContext context) {
    final tokens = PurchaseTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: PurchaseType.label.copyWith(color: tokens.inkFaint),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          key: valueKey,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: (numeric ? PurchaseType.metaNumeric : PurchaseType.meta)
              .copyWith(color: tokens.ink),
        ),
      ],
    );
  }
}

class _PriorityCheckbox extends StatelessWidget {
  const _PriorityCheckbox({
    required this.suggestion,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final PurchasePrioritySuggestion suggestion;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: selected
          ? 'Quitar ${suggestion.title} de la búsqueda conjunta'
          : 'Agregar ${suggestion.title} a la búsqueda conjunta',
      child: Checkbox(
        key: ValueKey('purchase-priority-select-${suggestion.entityId}'),
        value: selected,
        onChanged: enabled ? (value) => onChanged(value == true) : null,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}

String _jobLabel(PurchasePrioritySuggestion suggestion) {
  final job = suggestion.jobContext?.jobNumber.trim();
  return job == null || job.isEmpty ? 'Sin trabajo' : job;
}

String _bikeLabel(PurchasePrioritySuggestion suggestion) =>
    suggestion.jobContext?.bikeLabel ?? 'No aplica';

String _enteredLabel(PurchasePrioritySuggestion suggestion) {
  if (!suggestion.isWorkshop) return 'Automático';
  final enteredAt = suggestion.signalAt;
  if (enteredAt == null) return 'Sin fecha';
  final parts = ChileanUtils.formatDateTime(enteredAt.toLocal()).split(' ');
  return parts.length == 2 ? '${parts.first}\n${parts.last}' : parts.join(' ');
}

String _quantityLabel(PurchasePrioritySuggestion suggestion) {
  final quantity = suggestion.suggestedQuantity;
  final rounded = quantity == quantity.roundToDouble()
      ? quantity.toStringAsFixed(0)
      : quantity.toStringAsFixed(2);
  return suggestion.unit == 'unit' ? rounded : '$rounded ${suggestion.unit}';
}
