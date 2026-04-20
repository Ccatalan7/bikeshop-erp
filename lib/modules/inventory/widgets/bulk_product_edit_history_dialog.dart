import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/bulk_product_edit_models.dart';
import '../services/bulk_product_edit_service.dart';

enum _HistoryTab {
  recorded('Registrado'),
  legacy('Legado inferido');

  const _HistoryTab(this.label);
  final String label;
}

enum _LegacyVisibilityMode {
  all('Todos'),
  massOnly('Solo masivas');

  const _LegacyVisibilityMode(this.label);
  final String label;
}

enum _ItemTableSortColumn {
  executionAt,
  product,
  status,
  detail,
}

class BulkProductEditHistoryPanel extends StatefulWidget {
  const BulkProductEditHistoryPanel({
    super.key,
    required this.service,
    this.onBackToEditor,
  });

  final BulkProductEditService service;
  final VoidCallback? onBackToEditor;

  @override
  State<BulkProductEditHistoryPanel> createState() =>
      BulkProductEditHistoryPanelState();
}

class BulkProductEditHistoryPanelState
    extends State<BulkProductEditHistoryPanel>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  String? _error;
  List<BulkProductEditHistoryEntry> _recordedEntries = const [];
  List<BulkProductEditHistoryEntry> _legacyEntries = const [];
  BulkProductEditHistoryEntry? _selectedEntry;
  _LegacyVisibilityMode _legacyVisibilityMode = _LegacyVisibilityMode.all;
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadHistory();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> refresh() => _loadHistory();

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        widget.service.loadHistory(),
        widget.service.loadLegacyInferredHistory(),
      ]);
      final recordedEntries = results[0];
      final legacyEntries = results[1];
      if (!mounted) return;
      setState(() {
        _recordedEntries = recordedEntries;
        _legacyEntries = legacyEntries;
        _isLoading = false;
        if (_selectedEntry != null) {
          final sourceEntries = _selectedEntry!.isLegacyInferred
              ? _legacyEntries
              : _recordedEntries;
          final refreshed =
              sourceEntries.where((entry) => entry.id == _selectedEntry!.id);
          _selectedEntry = refreshed.isEmpty ? null : refreshed.first;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  void _openDetail(BulkProductEditHistoryEntry entry) {
    setState(() {
      _selectedEntry = entry;
    });
  }

  void _backToList() {
    setState(() {
      _selectedEntry = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_selectedEntry != null) {
      return BulkProductEditHistoryDetailPanel(
        service: widget.service,
        entry: _selectedEntry!,
        onBack: _backToList,
        onBackToEditor: widget.onBackToEditor,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Historial de ediciones masivas',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Revisa ejecuciones recientes, resultados y el detalle completo de los productos afectados sin salir del flujo de edición.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.onBackToEditor != null) ...[
              TextButton.icon(
                onPressed: widget.onBackToEditor,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Volver a edición'),
              ),
              const SizedBox(width: 8),
            ],
            IconButton(
              tooltip: 'Actualizar historial',
              onPressed: _isLoading ? null : _loadHistory,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: theme.colorScheme.surfaceContainerLowest,
          ),
          child: TabBar(
            controller: _tabController,
            tabs: _HistoryTab.values
                .map((tab) => Tab(text: tab.label))
                .toList(growable: false),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildListBody(
                theme: theme,
                tab: _HistoryTab.recorded,
                entries: _recordedEntries,
              ),
              _buildListBody(
                theme: theme,
                tab: _HistoryTab.legacy,
                entries: _legacyEntries,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildListBody({
    required ThemeData theme,
    required _HistoryTab tab,
    required List<BulkProductEditHistoryEntry> entries,
  }) {
    final visibleEntries =
        tab == _HistoryTab.legacy ? _filterLegacyEntries(entries) : entries;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'No se pudo cargar el historial.',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (visibleEntries.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.history_toggle_off_rounded,
                size: 48,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                tab == _HistoryTab.recorded
                    ? 'Todavía no hay ejecuciones registradas en este historial.'
                    : entries.isEmpty
                        ? 'No encontramos ajustes post-feature para reconstruir en esta vista.'
                        : 'No hay sesiones masivas con el filtro actual.',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                tab == _HistoryTab.recorded
                    ? 'Las ediciones masivas anteriores a esta implementación no quedaron guardadas como lotes auditables, por eso no aparecen aquí. A partir de ahora, cada nueva ejecución quedará registrada.'
                    : entries.isEmpty
                        ? 'La reconstrucción solo inspecciona ajustes manuales y regularizaciones por conteo posteriores al 08/04/2026. Si no hay filas aquí, no encontramos sesiones agrupables dentro de esa ventana.'
                        : 'Desactiva el filtro de solo masivas para ver también las sesiones singulares reconstruidas desde stock_adjustments.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tab == _HistoryTab.recorded
                      ? 'Este historial solo muestra ejecuciones guardadas desde que se habilitó la auditoría de ediciones masivas. Las operaciones antiguas no dejaron una traza de lote confiable para reconstruirlas aquí.'
                      : 'Estas sesiones se reconstruyen desde stock_adjustments posteriores al 08/04/2026. Se agrupan por mismo usuario y una ventana de hasta 30 segundos. Se marcan como masivas si tocan 3 o más productos distintos, o exactamente 2 productos dentro de una ráfaga de hasta 10 segundos; si no, quedan como singulares.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (tab == _HistoryTab.legacy) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Mostrar solo sesiones masivas',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _legacyVisibilityMode == _LegacyVisibilityMode.massOnly
                            ? '${visibleEntries.length} sesiones visibles · singulares ocultas'
                            : '${visibleEntries.length} sesiones visibles · masivas y singulares',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch.adaptive(
                  value:
                      _legacyVisibilityMode == _LegacyVisibilityMode.massOnly,
                  onChanged: (value) {
                    setState(() {
                      _legacyVisibilityMode = value
                          ? _LegacyVisibilityMode.massOnly
                          : _LegacyVisibilityMode.all;
                    });
                  },
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.35),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      _HistoryHeaderCell(
                        label: tab == _HistoryTab.legacy ? 'Sesión' : 'Fecha',
                        flex: 2,
                      ),
                      const _HistoryHeaderCell(label: 'Operación', flex: 2),
                      const _HistoryHeaderCell(label: 'Alcance', flex: 2),
                      const _HistoryHeaderCell(label: 'Ejecutado por', flex: 2),
                      const _HistoryHeaderCell(label: 'Resultado', flex: 3),
                      const _HistoryHeaderCell(label: 'Acción', flex: 1),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: visibleEntries.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.25),
                    ),
                    itemBuilder: (context, index) {
                      final entry = visibleEntries[index];
                      return InkWell(
                        onTap: () => _openDetail(entry),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              _HistoryValueCell(
                                flex: 2,
                                child: Text(
                                  _formatListDate(entry),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    height: 1.35,
                                  ),
                                ),
                              ),
                              _HistoryValueCell(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.operation.label,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (entry.isLegacyInferred) ...[
                                      const SizedBox(height: 6),
                                      _LegacySessionKindChip(
                                        kind: entry.legacySessionKind,
                                        compact: true,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              _HistoryValueCell(
                                flex: 2,
                                child: Text(
                                  _buildScopeSummary(entry),
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                              _HistoryValueCell(
                                flex: 2,
                                child: Text(
                                  _displayActor(entry),
                                  style: theme.textTheme.bodyMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              _HistoryValueCell(
                                flex: 3,
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    _StatusChip(status: entry.status),
                                    if (entry.isLegacyInferred)
                                      _HistoryOriginChip(origin: entry.origin),
                                    Text(
                                      _buildResultSummary(entry),
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              _HistoryValueCell(
                                flex: 1,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: OutlinedButton.icon(
                                    onPressed: () => _openDetail(entry),
                                    icon: const Icon(Icons.visibility_rounded,
                                        size: 16),
                                    label: const Text('Ver'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final twoDigitHour = local.hour.toString().padLeft(2, '0');
    final twoDigitMinute = local.minute.toString().padLeft(2, '0');
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year} '
        '$twoDigitHour:$twoDigitMinute';
  }

  String _buildScopeSummary(BulkProductEditHistoryEntry entry) {
    if (entry.isLegacyInferred) {
      return '${entry.scopeProductCount} productos · ${entry.enabledProductCount} movimientos';
    }
    return '${entry.scopeSource.label} · ${entry.enabledProductCount} activos';
  }

  List<BulkProductEditHistoryEntry> _filterLegacyEntries(
    List<BulkProductEditHistoryEntry> entries,
  ) {
    if (_legacyVisibilityMode == _LegacyVisibilityMode.all) {
      return entries;
    }
    return entries
        .where((entry) => entry.isLegacyMassSession)
        .toList(growable: false);
  }

  String _displayActor(BulkProductEditHistoryEntry entry) {
    final currentUser = Supabase.instance.client.auth.currentUser;
    final currentEmail = currentUser?.email?.trim();
    if (entry.createdBy != null &&
        currentUser?.id == entry.createdBy &&
        currentEmail != null &&
        currentEmail.isNotEmpty) {
      return currentEmail;
    }

    final actorName = entry.actorName?.trim();
    if (actorName != null && actorName.isNotEmpty) {
      return actorName;
    }

    if (currentEmail != null &&
        currentEmail.isNotEmpty &&
        currentUser?.id == entry.createdBy) {
      return currentEmail;
    }

    return 'Usuario actual';
  }

  String _buildResultSummary(BulkProductEditHistoryEntry entry) {
    if (entry.isLegacyInferred) {
      return '${entry.succeededProductCount} productos consolidados';
    }
    return '${entry.succeededProductCount} ok · ${entry.skippedProductCount} sin cambios · ${entry.failedProductCount} error';
  }

  String _formatListDate(BulkProductEditHistoryEntry entry) {
    final startAt = entry.createdAt.toLocal();
    final endAt = entry.endedAt?.toLocal();
    if (!entry.isLegacyInferred || endAt == null || endAt == startAt) {
      return _formatDateTime(startAt);
    }

    final sameDay = startAt.year == endAt.year &&
        startAt.month == endAt.month &&
        startAt.day == endAt.day;

    if (sameDay) {
      return '${_formatDateOnly(startAt)}\n${_formatShortTime(startAt)} → ${_formatShortTime(endAt)}';
    }

    return '${_formatDateTime(startAt)}\n→ ${_formatDateTime(endAt)}';
  }

  String _formatDateOnly(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year}';
  }

  String _formatShortTime(DateTime value) {
    final local = value.toLocal();
    final twoDigitHour = local.hour.toString().padLeft(2, '0');
    final twoDigitMinute = local.minute.toString().padLeft(2, '0');
    return '$twoDigitHour:$twoDigitMinute';
  }
}

class BulkProductEditHistoryDetailPanel extends StatefulWidget {
  const BulkProductEditHistoryDetailPanel({
    super.key,
    required this.service,
    required this.entry,
    required this.onBack,
    this.onBackToEditor,
  });

  final BulkProductEditService service;
  final BulkProductEditHistoryEntry entry;
  final VoidCallback onBack;
  final VoidCallback? onBackToEditor;

  @override
  State<BulkProductEditHistoryDetailPanel> createState() =>
      _BulkProductEditHistoryDetailPanelState();
}

class _BulkProductEditHistoryDetailPanelState
    extends State<BulkProductEditHistoryDetailPanel> {
  bool _isLoading = false;
  String? _error;
  BulkProductEditHistoryEntry? _entry;
  bool _isContextExpanded = false;
  _ItemTableSortColumn _itemsSortColumn = _ItemTableSortColumn.executionAt;
  bool _isItemsSortAscending = false;

  @override
  void initState() {
    super.initState();
    _entry = widget.entry;
    if (!widget.entry.isHydrated && !widget.entry.isLegacyInferred) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final entry = await widget.service.getHistoryById(widget.entry.id);
      if (!mounted) return;
      setState(() {
        _entry = entry ?? widget.entry;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextButton.icon(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Volver al historial'),
            ),
            const Spacer(),
            if (widget.onBackToEditor != null)
              TextButton.icon(
                onPressed: widget.onBackToEditor,
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Volver a edición'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildBody(theme)),
      ],
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      );
    }

    final entry = _entry;
    if (entry == null) {
      return Center(
        child: Text(
          'No se encontró el registro solicitado.',
          style: theme.textTheme.bodyLarge,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final hasContextDetails = _hasContextDetails(entry);
        final showContextRail =
            hasContextDetails && constraints.maxWidth >= 1280;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOverviewCard(theme, entry),
            const SizedBox(height: 12),
            if (!showContextRail && hasContextDetails) ...[
              _buildCollapsibleContextPanel(theme, entry),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: showContextRail
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 10,
                          child: _buildItemsTableCard(theme, entry),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 320,
                          child: _buildContextRail(theme, entry),
                        ),
                      ],
                    )
                  : _buildItemsTableCard(theme, entry),
            ),
          ],
        );
      },
    );
  }

  String _formatItemSummary(BulkUpdateItemResult item) {
    if (item.summary.trim().isNotEmpty) {
      return item.summary;
    }
    return 'Sin detalle adicional.';
  }

  String _formatItemExecutionAt(
    BulkUpdateItemResult item,
    BulkProductEditHistoryEntry entry,
  ) {
    return _formatExactDateTime(item.executionAt ?? entry.createdAt);
  }

  bool _hasContextDetails(BulkProductEditHistoryEntry entry) {
    return (entry.infoMessage ?? '').trim().isNotEmpty ||
        entry.filtersSnapshot.isNotEmpty ||
        entry.configSnapshot.isNotEmpty ||
        entry.errors.isNotEmpty;
  }

  Widget _buildOverviewCard(
    ThemeData theme,
    BulkProductEditHistoryEntry entry,
  ) {
    final summary = (entry.summary ?? '').trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      entry.operation.label,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    _StatusChip(status: entry.status),
                    if (entry.isLegacyInferred)
                      _HistoryOriginChip(origin: entry.origin),
                    if (entry.isLegacyInferred)
                      _LegacySessionKindChip(kind: entry.legacySessionKind),
                  ],
                ),
              ),
            ],
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              summary,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            _buildExecutionSummary(entry),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _buildSummaryMetrics(entry)
                .map(
                  (metric) => _SummaryMetricChip(
                    label: metric.label,
                    value: metric.value,
                  ),
                )
                .toList(growable: false),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsibleContextPanel(
    ThemeData theme,
    BulkProductEditHistoryEntry entry,
  ) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              setState(() {
                _isContextExpanded = !_isContextExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Contexto y metadatos',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Filtros, notas de inferencia y errores fuera de la mesa principal.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _isContextExpanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (_isContextExpanded) ...[
            Divider(
              height: 1,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: _buildContextContent(
                theme,
                entry,
                dense: true,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildContextRail(
    ThemeData theme,
    BulkProductEditHistoryEntry entry,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Scrollbar(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: _buildContextContent(theme, entry, dense: true),
        ),
      ),
    );
  }

  Widget _buildContextContent(
    ThemeData theme,
    BulkProductEditHistoryEntry entry, {
    required bool dense,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((entry.infoMessage ?? '').trim().isNotEmpty)
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(dense ? 12 : 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
              ),
            ),
            child: Text(
              entry.infoMessage!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        if ((entry.infoMessage ?? '').trim().isNotEmpty)
          SizedBox(height: dense ? 10 : 16),
        _SnapshotCard(
          title: entry.isLegacyInferred
              ? 'Señales de búsqueda'
              : 'Filtros aplicados',
          snapshot: entry.filtersSnapshot,
          emptyLabel: entry.isLegacyInferred
              ? 'No hubo filtros directos; la sesión se reconstruyó desde ajustes manuales agrupados por tiempo.'
              : 'No se aplicaron filtros adicionales.',
          dense: dense,
        ),
        SizedBox(height: dense ? 10 : 16),
        _SnapshotCard(
          title: entry.isLegacyInferred
              ? 'Metadatos de inferencia'
              : 'Configuración del lote',
          snapshot: entry.configSnapshot,
          emptyLabel: entry.isLegacyInferred
              ? 'Sin metadatos adicionales.'
              : 'Sin reglas base adicionales.',
          dense: dense,
        ),
        if (entry.errors.isNotEmpty) ...[
          SizedBox(height: dense ? 10 : 16),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(dense ? 12 : 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: theme.colorScheme.error.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Errores reportados',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 8),
                ...entry.errors.map(
                  (error) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '• $error',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildItemsTableCard(
    ThemeData theme,
    BulkProductEditHistoryEntry entry,
  ) {
    final visibleRows = entry.items.length;
    final sortedItems = _buildSortedItems(entry);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.28),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Productos y detalle de la edición',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        visibleRows == 1
                            ? '1 fila con detalle por producto'
                            : '$visibleRows filas con detalle por producto',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.end,
                  children: [
                    _SummaryMetricChip(
                      label: 'Actualizados',
                      value: '${entry.succeededProductCount}',
                    ),
                    if (entry.failedProductCount > 0)
                      _SummaryMetricChip(
                        label: 'Errores',
                        value: '${entry.failedProductCount}',
                        backgroundColor:
                            theme.colorScheme.errorContainer.withValues(
                          alpha: 0.9,
                        ),
                        foregroundColor: theme.colorScheme.onErrorContainer,
                      ),
                  ],
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.18),
            ),
            child: Row(
              children: [
                _HistoryHeaderCell(
                  label: 'Fecha ejecución',
                  flex: 2,
                  isSortable: true,
                  isActive:
                      _itemsSortColumn == _ItemTableSortColumn.executionAt,
                  ascending: _isItemsSortAscending,
                  onTap: () =>
                      _toggleItemsSort(_ItemTableSortColumn.executionAt),
                ),
                _HistoryHeaderCell(
                  label: 'Producto',
                  flex: 3,
                  isSortable: true,
                  isActive: _itemsSortColumn == _ItemTableSortColumn.product,
                  ascending: _isItemsSortAscending,
                  onTap: () => _toggleItemsSort(_ItemTableSortColumn.product),
                ),
                _HistoryHeaderCell(
                  label: 'Estado',
                  flex: 1,
                  isSortable: true,
                  isActive: _itemsSortColumn == _ItemTableSortColumn.status,
                  ascending: _isItemsSortAscending,
                  onTap: () => _toggleItemsSort(_ItemTableSortColumn.status),
                ),
                _HistoryHeaderCell(
                  label: 'Detalle',
                  flex: 6,
                  isSortable: true,
                  isActive: _itemsSortColumn == _ItemTableSortColumn.detail,
                  ascending: _isItemsSortAscending,
                  onTap: () => _toggleItemsSort(_ItemTableSortColumn.detail),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
          Expanded(
            child: Scrollbar(
              child: ListView.separated(
                itemCount: sortedItems.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
                ),
                itemBuilder: (context, index) {
                  final item = sortedItems[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _HistoryValueCell(
                          flex: 2,
                          child: Text(
                            _formatItemExecutionAt(item, entry),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.35,
                            ),
                          ),
                        ),
                        _HistoryValueCell(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.productName,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.productSku,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _HistoryValueCell(
                          flex: 1,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _ItemStatusChip(status: item.status),
                          ),
                        ),
                        _HistoryValueCell(
                          flex: 6,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _formatItemSummary(item),
                                style: theme.textTheme.bodyMedium,
                              ),
                              if (item.error?.trim().isNotEmpty == true) ...[
                                const SizedBox(height: 6),
                                Text(
                                  item.error!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.error,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleItemsSort(_ItemTableSortColumn column) {
    setState(() {
      if (_itemsSortColumn == column) {
        _isItemsSortAscending = !_isItemsSortAscending;
        return;
      }

      _itemsSortColumn = column;
      _isItemsSortAscending =
          column == _ItemTableSortColumn.executionAt ? false : true;
    });
  }

  List<BulkUpdateItemResult> _buildSortedItems(
    BulkProductEditHistoryEntry entry,
  ) {
    final items = List<BulkUpdateItemResult>.from(entry.items);
    items.sort((left, right) {
      final comparison = switch (_itemsSortColumn) {
        _ItemTableSortColumn.executionAt => _compareDateTimes(
            left.executionAt ?? entry.createdAt,
            right.executionAt ?? entry.createdAt,
          ),
        _ItemTableSortColumn.product => _compareStrings(
            '${left.productName} ${left.productSku}',
            '${right.productName} ${right.productSku}',
          ),
        _ItemTableSortColumn.status => _compareStrings(
            left.status.label,
            right.status.label,
          ),
        _ItemTableSortColumn.detail => _compareStrings(
            _formatItemSummary(left),
            _formatItemSummary(right),
          ),
      };

      final resolvedComparison = comparison != 0
          ? comparison
          : _compareStrings(
              '${left.productName} ${left.productSku}',
              '${right.productName} ${right.productSku}',
            );

      return _isItemsSortAscending ? resolvedComparison : -resolvedComparison;
    });
    return items;
  }

  int _compareStrings(String left, String right) {
    return left.toLowerCase().compareTo(right.toLowerCase());
  }

  int _compareDateTimes(DateTime left, DateTime right) {
    return left.compareTo(right);
  }

  List<_SummaryMetricData> _buildSummaryMetrics(
    BulkProductEditHistoryEntry entry,
  ) {
    if (entry.isLegacyInferred) {
      return [
        _SummaryMetricData(
          label: 'Productos',
          value: '${entry.scopeProductCount}',
        ),
        _SummaryMetricData(
          label: 'Movimientos',
          value: '${entry.enabledProductCount}',
        ),
        _SummaryMetricData(
          label: 'Consolidados',
          value: '${entry.succeededProductCount}',
        ),
        _SummaryMetricData(
          label: 'Ventana',
          value: _formatEntryDuration(entry),
        ),
      ];
    }

    return [
      _SummaryMetricData(
        label: 'Coincidencias',
        value: '${entry.scopeProductCount}',
      ),
      _SummaryMetricData(
        label: 'Filas activas',
        value: '${entry.enabledProductCount}',
      ),
      _SummaryMetricData(
        label: 'Actualizados',
        value: '${entry.succeededProductCount}',
      ),
      _SummaryMetricData(
        label: 'Sin cambios',
        value: '${entry.skippedProductCount}',
      ),
      _SummaryMetricData(
        label: 'Errores',
        value: '${entry.failedProductCount}',
      ),
    ];
  }

  String _buildExecutionSummary(BulkProductEditHistoryEntry entry) {
    final actor = _displayActor(entry);
    if (entry.endedAt == null) {
      return 'Ejecutado por $actor · ${_formatDateTime(entry.createdAt)}';
    }

    final startAt = _effectiveStartAt(entry);
    final endAt = _effectiveEndAt(entry);
    if (startAt == endAt) {
      return 'Ejecutado por $actor · ${_formatDateTime(startAt)}';
    }

    return 'Ejecutado por $actor · ${_formatDateTime(startAt)} · hasta ${_formatShortTime(endAt)}';
  }

  String _displayActor(BulkProductEditHistoryEntry entry) {
    final currentUser = Supabase.instance.client.auth.currentUser;
    final currentEmail = currentUser?.email?.trim();
    if (entry.createdBy != null &&
        currentUser?.id == entry.createdBy &&
        currentEmail != null &&
        currentEmail.isNotEmpty) {
      return currentEmail;
    }

    final actorName = entry.actorName?.trim();
    if (actorName != null && actorName.isNotEmpty) {
      return actorName;
    }

    if (currentEmail != null &&
        currentEmail.isNotEmpty &&
        currentUser?.id == entry.createdBy) {
      return currentEmail;
    }

    return 'Usuario actual';
  }

  String _formatEntryDuration(BulkProductEditHistoryEntry entry) {
    final endAt = entry.endedAt;
    if (endAt == null) return '—';

    final duration =
        _effectiveEndAt(entry).difference(_effectiveStartAt(entry));
    if (duration.inSeconds <= 0) return '0s';
    if (duration.inMinutes < 1) return '${duration.inSeconds}s';
    if (duration.inHours < 1) {
      final secondsRemainder = duration.inSeconds % 60;
      return secondsRemainder == 0
          ? '${duration.inMinutes}m'
          : '${duration.inMinutes}m ${secondsRemainder}s';
    }
    final minutesRemainder = duration.inMinutes % 60;
    return minutesRemainder == 0
        ? '${duration.inHours}h'
        : '${duration.inHours}h ${minutesRemainder}m';
  }

  DateTime _effectiveStartAt(BulkProductEditHistoryEntry entry) {
    final endedAt = entry.endedAt;
    if (endedAt != null && endedAt.isBefore(entry.createdAt)) {
      return endedAt;
    }
    return entry.createdAt;
  }

  DateTime _effectiveEndAt(BulkProductEditHistoryEntry entry) {
    final endedAt = entry.endedAt;
    if (endedAt == null) return entry.createdAt;
    if (endedAt.isBefore(entry.createdAt)) {
      return entry.createdAt;
    }
    return endedAt;
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    final twoDigitHour = local.hour.toString().padLeft(2, '0');
    final twoDigitMinute = local.minute.toString().padLeft(2, '0');
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year} '
        '$twoDigitHour:$twoDigitMinute';
  }

  String _formatExactDateTime(DateTime value) {
    final local = value.toLocal();
    final twoDigitHour = local.hour.toString().padLeft(2, '0');
    final twoDigitMinute = local.minute.toString().padLeft(2, '0');
    final twoDigitSecond = local.second.toString().padLeft(2, '0');
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year} '
        '$twoDigitHour:$twoDigitMinute:$twoDigitSecond';
  }

  String _formatShortTime(DateTime value) {
    final local = value.toLocal();
    final twoDigitHour = local.hour.toString().padLeft(2, '0');
    final twoDigitMinute = local.minute.toString().padLeft(2, '0');
    return '$twoDigitHour:$twoDigitMinute';
  }
}

class _HistoryHeaderCell extends StatelessWidget {
  const _HistoryHeaderCell({
    required this.label,
    required this.flex,
    this.onTap,
    this.isSortable = false,
    this.isActive = false,
    this.ascending = true,
  });

  final String label;
  final int flex;
  final VoidCallback? onTap;
  final bool isSortable;
  final bool isActive;
  final bool ascending;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isActive
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              if (isSortable) ...[
                const SizedBox(width: 6),
                Icon(
                  isActive
                      ? (ascending
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded)
                      : Icons.unfold_more_rounded,
                  size: 15,
                  color: isActive
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryValueCell extends StatelessWidget {
  const _HistoryValueCell({
    required this.flex,
    required this.child,
  });

  final int flex;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Expanded(flex: flex, child: child);
  }
}

class _SummaryMetricData {
  const _SummaryMetricData({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;
}

class _SummaryMetricChip extends StatelessWidget {
  const _SummaryMetricChip({
    required this.label,
    required this.value,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String label;
  final String value;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedBackground = backgroundColor ??
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7);
    final resolvedForeground = foregroundColor ?? theme.colorScheme.onSurface;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: resolvedBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodySmall?.copyWith(color: resolvedForeground),
          children: [
            TextSpan(
              text: '$value ',
              style: theme.textTheme.labelLarge?.copyWith(
                color: resolvedForeground,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(text: label),
          ],
        ),
      ),
    );
  }
}

class _SnapshotCard extends StatelessWidget {
  const _SnapshotCard({
    required this.title,
    required this.snapshot,
    required this.emptyLabel,
    this.dense = false,
  });

  final String title;
  final Map<String, dynamic> snapshot;
  final String emptyLabel;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.all(dense ? 12 : 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: dense ? 10 : 12),
          if (snapshot.isEmpty)
            Text(
              emptyLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...snapshot.entries.map(
              (entry) => Padding(
                padding: EdgeInsets.only(bottom: dense ? 6 : 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: dense ? 110 : 130,
                      child: Text(
                        entry.key,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _formatSnapshotValue(entry.value),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatSnapshotValue(dynamic value) {
    if (value == null) return 'Vacío';
    if (value is bool) return value ? 'Sí' : 'No';
    if (value is num) return value.toString();
    if (value is DateTime) return value.toIso8601String();
    if (value is List) {
      return value.map(_formatSnapshotValue).join(' · ');
    }
    if (value is Map) {
      return value.entries
          .map((entry) => '${entry.key}: ${_formatSnapshotValue(entry.value)}')
          .join(' · ');
    }
    final text = value.toString().trim();
    return text.isEmpty ? 'Vacío' : text;
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final BulkProductEditHistoryStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = switch (status) {
      BulkProductEditHistoryStatus.completed => (
          theme.colorScheme.primaryContainer,
          theme.colorScheme.onPrimaryContainer,
        ),
      BulkProductEditHistoryStatus.partial => (
          Colors.orange.shade100,
          Colors.orange.shade900,
        ),
      BulkProductEditHistoryStatus.failed => (
          theme.colorScheme.errorContainer,
          theme.colorScheme.onErrorContainer,
        ),
      BulkProductEditHistoryStatus.skipped => (
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.onSurfaceVariant,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.$1,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: palette.$2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _HistoryOriginChip extends StatelessWidget {
  const _HistoryOriginChip({required this.origin});

  final BulkProductEditHistoryOrigin origin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = switch (origin) {
      BulkProductEditHistoryOrigin.recorded => (
          theme.colorScheme.secondaryContainer,
          theme.colorScheme.onSecondaryContainer,
        ),
      BulkProductEditHistoryOrigin.legacyInferred => (
          theme.colorScheme.tertiaryContainer,
          theme.colorScheme.onTertiaryContainer,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.$1,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        origin.label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: palette.$2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _LegacySessionKindChip extends StatelessWidget {
  const _LegacySessionKindChip({
    required this.kind,
    this.compact = false,
  });

  final BulkLegacySessionKind kind;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = switch (kind) {
      BulkLegacySessionKind.mass => (
          theme.colorScheme.primary.withValues(alpha: 0.045),
          theme.colorScheme.primary.withValues(alpha: 0.16),
          theme.colorScheme.onSurface,
          theme.colorScheme.primary.withValues(alpha: 0.75),
        ),
      BulkLegacySessionKind.singular => (
          theme.colorScheme.surfaceContainerLowest,
          theme.colorScheme.outlineVariant.withValues(alpha: 0.85),
          theme.colorScheme.onSurfaceVariant,
          theme.colorScheme.outline,
        ),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 9,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: palette.$1,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: palette.$2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 5 : 6,
            height: compact ? 5 : 6,
            decoration: BoxDecoration(
              color: palette.$4,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            kind.label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: palette.$3,
              fontWeight: FontWeight.w700,
              letterSpacing: compact ? 0.1 : 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _ItemStatusChip extends StatelessWidget {
  const _ItemStatusChip({required this.status});

  final BulkUpdateItemStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = switch (status) {
      BulkUpdateItemStatus.updated => (
          theme.colorScheme.primaryContainer,
          theme.colorScheme.onPrimaryContainer,
        ),
      BulkUpdateItemStatus.skipped => (
          theme.colorScheme.surfaceContainerHighest,
          theme.colorScheme.onSurfaceVariant,
        ),
      BulkUpdateItemStatus.failed => (
          theme.colorScheme.errorContainer,
          theme.colorScheme.onErrorContainer,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: palette.$1,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: palette.$2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
