import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../shared/widgets/vb_notice.dart';
import '../../../shared/widgets/vb_status_badge.dart';
import '../../purchases/models/intelligent_purchasing_models.dart';
import '../../purchases/services/intelligent_purchasing_service.dart';
import '../models/bikeshop_models.dart';
import 'supply_need_capture_panel.dart';

/// Jobs-side trace and editor for every supply need originated by one job.
///
/// The Purchasing workspace remains the owner of stock, supplier comparison
/// and plans. This panel answers the workshop questions the global inbox
/// cannot: what was recorded here, when, for which bike, and where to correct
/// that origin data.
class JobSupplyNeedsPanel extends StatefulWidget {
  const JobSupplyNeedsPanel({
    super.key,
    required this.job,
    required this.jobBikes,
    required this.initiallyCreating,
    required this.onNeedCreated,
    required this.onNeedUpdated,
    required this.onResolve,
    this.initialJobBikeId,
    this.service,
  });

  final MechanicJob job;
  final List<MechanicJobBike> jobBikes;
  final bool initiallyCreating;
  final ValueChanged<SupplyNeed> onNeedCreated;
  final ValueChanged<SupplyNeed> onNeedUpdated;
  final ValueChanged<SupplyNeed> onResolve;
  final String? initialJobBikeId;
  final IntelligentPurchasingService? service;

  @override
  State<JobSupplyNeedsPanel> createState() => _JobSupplyNeedsPanelState();
}

class _JobSupplyNeedsPanelState extends State<JobSupplyNeedsPanel> {
  late final IntelligentPurchasingService _service;
  late bool _showEditor;
  bool _loading = true;
  String? _loadError;
  SupplyNeed? _editingNeed;
  List<SupplyNeed> _needs = const [];
  int _editorEpoch = 0;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? IntelligentPurchasingService();
    _showEditor = widget.initiallyCreating;
    _load();
  }

  Future<void> _load() async {
    final jobId = widget.job.id;
    if (jobId == null) {
      setState(() {
        _loading = false;
        _loadError = 'Este trabajo aún no tiene un vínculo persistido.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final needs = await _service.fetchJobNeeds(jobId);
      if (!mounted) return;
      setState(() {
        _needs = needs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'No se pudieron cargar los repuestos de este trabajo.';
      });
    }
  }

  void _upsert(SupplyNeed need) {
    final next = List<SupplyNeed>.from(_needs);
    final index = next.indexWhere((candidate) => candidate.id == need.id);
    if (index == -1) {
      next.insert(0, need);
    } else {
      next[index] = need;
    }
    next.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    setState(() => _needs = next);
  }

  void _create() {
    setState(() {
      _editingNeed = null;
      _showEditor = true;
      _editorEpoch += 1;
    });
  }

  void _edit(SupplyNeed need) {
    if (_isClosed(need)) {
      widget.onResolve(need);
      return;
    }
    setState(() {
      _editingNeed = need;
      _showEditor = true;
      _editorEpoch += 1;
    });
  }

  void _showList() {
    FocusScope.of(context).unfocus();
    setState(() {
      _editingNeed = null;
      _showEditor = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showEditor) {
      return SupplyNeedCapturePanel(
        key: ValueKey(
          'workshop-supply-editor-${_editingNeed?.id ?? 'new'}-$_editorEpoch',
        ),
        job: widget.job,
        jobBikes: widget.jobBikes,
        existingNeed: _editingNeed,
        initialJobBikeId: _editingNeed == null ? widget.initialJobBikeId : null,
        service: _service,
        onCreated: (need) {
          _upsert(need);
          widget.onNeedCreated(need);
        },
        onUpdated: (need) {
          _upsert(need);
          widget.onNeedUpdated(need);
        },
        onReturnToList: _showList,
        onResolve: widget.onResolve,
      );
    }

    if (_loading) {
      return Semantics(
        liveRegion: true,
        label: 'Cargando repuestos del trabajo',
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(),
            SizedBox(height: 12),
            Text('Cargando repuestos del trabajo…'),
          ],
        ),
      );
    }

    final error = _loadError;
    if (error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          VbNotice(title: error, tone: VbNoticeTone.danger),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reintentar'),
            ),
          ),
        ],
      );
    }

    if (_needs.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const VbNotice(
            title: 'Todavía no hay repuestos registrados',
            body:
                'El estado del trabajo está esperando repuestos, pero aún falta indicar qué se necesita.',
            tone: VbNoticeTone.warning,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Registrar repuesto'),
            ),
          ),
        ],
      );
    }

    final activeCount = _needs.where((need) => !_isClosed(need)).length;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                activeCount == 1
                    ? '1 pendiente de abastecimiento'
                    : '$activeCount pendientes de abastecimiento',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Añadir'),
            ),
          ],
        ),
        const Divider(),
        ..._needs.map((need) => _buildNeedRow(context, need)),
        const SizedBox(height: 4),
        Text(
          'Selecciona una necesidad activa para editarla. El icono de salida abre su resolución en Compras.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildNeedRow(BuildContext context, SupplyNeed need) {
    final theme = Theme.of(context);
    final title = need.productName?.trim().isNotEmpty == true
        ? need.productName!.trim()
        : need.description;
    final firstLine = <String>[
      if (need.productSku?.trim().isNotEmpty == true)
        'SKU ${need.productSku!.trim()}',
      '${_formatQuantity(need.quantity)} ${_unitLabel(need)}',
      _scopeLabel(need.jobBikeId),
    ].join(' · ');
    final recordedAt =
        'Registrado ${DateFormat('dd/MM/yyyy · HH:mm').format(need.createdAt.toLocal())}';
    final closed = _isClosed(need);

    return ListTile(
      key: ValueKey('workshop-supply-need-${need.id}'),
      contentPadding: EdgeInsets.zero,
      onTap: () => _edit(need),
      leading: Icon(
        need.hasConfirmedProduct
            ? Icons.inventory_2_outlined
            : Icons.manage_search_outlined,
        color: closed
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.primary,
      ),
      title: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(firstLine, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              VbStatusBadge(
                label: _stateLabel(need),
                tone: _stateTone(need),
                dense: true,
              ),
              Text(recordedAt, style: theme.textTheme.bodySmall),
            ],
          ),
        ],
      ),
      trailing: IconButton(
        tooltip: 'Abrir en Asistente de Compras',
        onPressed: () => widget.onResolve(need),
        icon: const Icon(Icons.open_in_new, size: 18),
      ),
    );
  }

  String _scopeLabel(String? jobBikeId) {
    if (jobBikeId == null) return 'Todo el trabajo';
    for (final link in widget.jobBikes) {
      if (link.id != jobBikeId) continue;
      final bike = link.bike;
      final label = <String?>[bike?.brand, bike?.model]
          .whereType<String>()
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .join(' ');
      return label.isEmpty ? 'Bicicleta ${link.orderIndex + 1}' : label;
    }
    return 'Bicicleta vinculada';
  }

  bool _isClosed(SupplyNeed need) =>
      need.supplyState == 'covered' || need.supplyState == 'cancelled';

  String _stateLabel(SupplyNeed need) {
    if (need.supplyState == 'cancelled') return 'Cancelado';
    if (need.supplyState == 'covered') return 'Cubierto';
    if (need.supplyState == 'received') return 'Recibido';
    if (need.supplyState == 'in_purchase') return 'En compra';
    if (need.supplyState == 'committed') return 'Reservado';
    if (!need.hasConfirmedProduct) return 'Por identificar';
    return 'Pendiente';
  }

  VbStatusTone _stateTone(SupplyNeed need) {
    if (need.supplyState == 'covered') return VbStatusTone.success;
    if (need.supplyState == 'cancelled') return VbStatusTone.neutral;
    if (need.supplyState == 'received') return VbStatusTone.info;
    if (need.supplyState == 'in_purchase' || need.supplyState == 'committed') {
      return VbStatusTone.info;
    }
    return need.hasConfirmedProduct
        ? VbStatusTone.warning
        : VbStatusTone.danger;
  }

  String _unitLabel(SupplyNeed need) {
    if (need.unit != 'unit') return need.unit;
    return need.quantity == 1 ? 'unidad' : 'unidades';
  }

  String _formatQuantity(double value) {
    if (value == value.truncateToDouble()) return value.toInt().toString();
    return value.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
  }
}
