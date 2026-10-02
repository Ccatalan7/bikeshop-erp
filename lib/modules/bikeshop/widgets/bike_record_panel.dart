import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../shared/themes/vinabike_theme_roles.dart';
import '../../../shared/widgets/vb_button.dart';
import '../../../shared/widgets/vb_segmented.dart' show VbDensity;
import '../../../shared/widgets/vb_sub_tabs.dart';
import '../config/bottom_bracket_canonical_data.dart';
import '../config/brake_canonical_data.dart';
import '../config/wheel_canonical_data.dart';
import '../models/bike_fact_origin.dart';
import '../models/bikeshop_models.dart';
import '../services/bike_directory_entries.dart';
import '../services/bike_visit_history.dart';
import '../services/bikeshop_service.dart';
import '../services/job_line_systems.dart';
import 'bike_measurement_timeline.dart';
import 'bike_module_style.dart';
import 'bike_silhouette.dart';
import 'bike_system_controller.dart';

/// La ficha de una bicicleta: quién es, qué se le ha hecho y qué se sabe de
/// ella.
///
/// Rediseño aprobado por el dueño el 2026-10-02 (lienzo «Bicicletas —
/// rediseño»). Abre en el historial, armado desde los trabajos de la bici:
/// cada visita con lo que pidió el cliente y lo que se le hizo, por sistema.
/// La ficha técnica muestra todos los sistemas a la vez sobre el dibujo de la
/// bici; ya no hay que elegir un sistema para ver algo.
///
/// La sirven la página propia de la bici (`/taller/bicicletas/:id`) y la
/// pestaña Bicicletas del cliente.
class BikeRecordPanel extends StatefulWidget {
  final BikeRecordSnapshot snapshot;
  final String ownerName;
  final bool isLoading;
  final VoidCallback onEdit;
  final VoidCallback onNewJob;
  final VoidCallback onClose;

  /// Abre al dueño. Sin él (la ficha ya está dentro del cliente) el nombre
  /// no es un enlace.
  final VoidCallback? onOpenOwner;

  /// Abre un trabajo. Por defecto, su página.
  final void Function(String jobId)? onOpenJob;

  /// El texto del regreso: «Bicicletas» o «Volver a bicicletas».
  final String closeLabel;

  /// Para pruebas: el día con que se cuentan los días en el taller.
  final DateTime? today;

  /// Falso cuando el anfitrión ya dibuja el regreso (la barra del teléfono
  /// de la página propia de la bici, que además lleva «Editar»).
  final bool showBackRow;

  const BikeRecordPanel({
    super.key,
    required this.snapshot,
    required this.ownerName,
    this.isLoading = false,
    required this.onEdit,
    required this.onNewJob,
    required this.onClose,
    this.onOpenOwner,
    this.onOpenJob,
    this.closeLabel = 'Volver a bicicletas',
    this.today,
    this.showBackRow = true,
  });

  @override
  State<BikeRecordPanel> createState() => _BikeRecordPanelState();
}

enum _RecordTab { history, technical, notes }

final NumberFormat _money =
    NumberFormat.currency(symbol: r'$', decimalDigits: 0);

bool _isCancelledJob(MechanicJob job) =>
    job.status == JobStatus.cancelado ||
    job.customStatus?.code.trim().toUpperCase() == 'CANCELADO';

/// Lo que lee el historial: la memoria técnica de la bici y sus visitas.
class _RecordHistory {
  const _RecordHistory({required this.memory, required this.visits});

  const _RecordHistory.empty()
      : memory = const _BikeRecordHistoryData.empty(),
        visits = const [];

  final _BikeRecordHistoryData memory;
  final List<BikeVisit> visits;

  int get visitCount =>
      visits.where((visit) => !_isCancelledJob(visit.job)).length;

  BikeVisit? get workshopVisit {
    for (final visit in visits) {
      if (visit.inWorkshop) return visit;
    }
    return null;
  }

  DateTime? get lastVisitAt => visits.isEmpty
      ? null
      : visits
          .map((visit) => visit.date)
          .reduce((a, b) => a.isAfter(b) ? a : b);

  bool get isEmpty => visits.isEmpty && memory.isEmpty;
}

/// Un sistema en «Por sistema»: cuándo se tocó y qué dejó montado el taller.
class _SystemSummary {
  _SystemSummary(this.system);

  final JobLineSystem system;
  DateTime? lastDate;
  final List<BikeComponentLifecycle> installed = [];
}

/// Un grupo de la ficha técnica sobre el dibujo.
class _SpecGroup {
  const _SpecGroup({
    required this.number,
    required this.title,
    required this.anchor,
    required this.facts,
    required this.knownCount,
    required this.expectedCount,
    this.missingText,
  });

  final int number;
  final String title;
  final BikeSilhouetteAnchor anchor;
  final List<_BikeRecordTechnicalFact> facts;

  /// Lo que la ficha sabe, contado como lo cuenta su sistema: un líquido
  /// igual en los dos frenos se muestra una vez pero son dos datos.
  final int knownCount;
  final int expectedCount;
  final String? missingText;
}

class _BikeRecordPanelState extends State<BikeRecordPanel> {
  _RecordTab _tab = _RecordTab.history;
  late Future<_RecordHistory> _historyFuture;
  JobLineSystem? _systemFilter;

  DateTime get _today => widget.today ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _reloadHistory();
  }

  @override
  void didUpdateWidget(covariant BikeRecordPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.snapshot, widget.snapshot)) {
      _reloadHistory();
    }
    if (oldWidget.snapshot.bike.id != widget.snapshot.bike.id) {
      _systemFilter = null;
    }
  }

  Future<_RecordHistory> _loadHistory(String? bikeId) async {
    if (bikeId == null || bikeId.isEmpty) {
      return const _RecordHistory.empty();
    }
    try {
      final bikeshop = context.read<BikeshopService>();
      final results = await Future.wait<Object?>([
        bikeshop.getBikeEvents(bikeId),
        bikeshop.getBikeObservations(bikeId),
        bikeshop.getBikeSystemStates(bikeId),
        bikeshop.getBikeInterventions(bikeId),
        bikeshop.getBikeComponentLifecycles(bikeId),
        loadBikeVisits(
          context,
          bikeId,
          bike: widget.snapshot.bike,
          ownerName: widget.ownerName,
        ),
      ]);
      return _RecordHistory(
        memory: _BikeRecordHistoryData.fromRaw(
          events: (results[0] as List<BikeEvent>?) ?? const [],
          observations: (results[1] as List<BikeObservation>?) ?? const [],
          systemStates: (results[2] as List<BikeSystemState>?) ?? const [],
          interventions: (results[3] as List<BikeIntervention>?) ?? const [],
          componentLifecycles:
              (results[4] as List<BikeComponentLifecycle>?) ?? const [],
        ),
        visits: (results[5] as List<BikeVisit>?) ?? const [],
      );
    } catch (error) {
      debugPrint('Bike record history load failed: $error');
      rethrow;
    }
  }

  void _reloadHistory() {
    _historyFuture = _loadHistory(widget.snapshot.bike.id);
    // El historial puede no estar a la vista cuando falla la lectura: se
    // observa ahora y el FutureBuilder igual recibe el error.
    _historyFuture.ignore();
  }

  void _openJob(String? jobId) {
    if (jobId == null || jobId.isEmpty) return;
    final open = widget.onOpenJob;
    if (open != null) {
      open(jobId);
    } else {
      context.push('/taller/pegas/$jobId');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.isLoading) {
      return ColoredBox(
        color: theme.colorScheme.surfaceContainer,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    return BikeModuleTheme(
      child: ColoredBox(
        color: theme.colorScheme.surfaceContainer,
        child: FutureBuilder<_RecordHistory>(
          future: _historyFuture,
          builder: (context, snapshot) {
            final loading = snapshot.connectionState == ConnectionState.waiting;
            final failed = !loading && snapshot.hasError;
            final history = (loading || failed) ? null : snapshot.data;
            return LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= _studioMinWidth &&
                    constraints.maxHeight.isFinite) {
                  return _buildStudio(
                    context,
                    constraints,
                    loading: loading,
                    failed: failed,
                    history: history,
                  );
                }
                final narrow = constraints.maxWidth < 680;
                final gutter = narrow ? 16.0 : 28.0;
                final contentWidth =
                    (constraints.maxWidth - gutter * 2).clamp(0.0, 1180.0);
                // Algunos anfitriones dan un alto holgado: la ficha igual
                // ocupa todo el alto, para que su fondo no termine a media
                // pantalla (se notaba en oscuro).
                return SizedBox(
                  width: constraints.maxWidth,
                  height: constraints.maxHeight.isFinite
                      ? constraints.maxHeight
                      : null,
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                        gutter, narrow ? 4 : 14, gutter, 48),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: contentWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (widget.showBackRow) ...[
                              _buildBackRow(context, narrow: narrow),
                              SizedBox(height: narrow ? 4 : 8),
                            ] else
                              const SizedBox(height: 12),
                            if (narrow)
                              _buildPhoneHeader(context, history)
                            else
                              _buildWideHeader(context, history,
                                  width: contentWidth),
                            const SizedBox(height: 18),
                            VbSubTabs<_RecordTab>(
                              density: VbSubTabsDensity.comfortable,
                              value: _tab,
                              onChanged: (tab) => setState(() => _tab = tab),
                              tabs: [
                                VbSubTab(
                                  value: _RecordTab.history,
                                  label:
                                      history == null || history.visitCount == 0
                                          ? 'Historial'
                                          : 'Historial · ${history.visitCount}',
                                ),
                                const VbSubTab(
                                  value: _RecordTab.technical,
                                  label: 'Ficha técnica',
                                ),
                                const VbSubTab(
                                  value: _RecordTab.notes,
                                  label: 'Notas',
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            switch (_tab) {
                              _RecordTab.history => _buildHistoryTab(
                                  context,
                                  loading: loading,
                                  failed: failed,
                                  history: history,
                                  width: contentWidth,
                                ),
                              _RecordTab.technical => _buildTechnicalTab(
                                  context,
                                  width: contentWidth),
                              _RecordTab.notes => _buildNotesTab(context),
                            },
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  // ── Escritorio ancho ─────────────────────────────────────────────────────

  /// Desde este ancho la ficha ocupa toda la página: la bici queda fija a la
  /// izquierda y el historial usa el resto (dueño, 2026-10-02: «no me gustan
  /// esas tablas en desktop que no cubren todo el ancho de la página»).
  static const double _studioMinWidth = 1180;
  static const double _identityWidth = 380;

  Widget _buildTabs(_RecordHistory? history) {
    return VbSubTabs<_RecordTab>(
      density: VbSubTabsDensity.comfortable,
      value: _tab,
      onChanged: (tab) => setState(() => _tab = tab),
      tabs: [
        VbSubTab(
          value: _RecordTab.history,
          label: history == null || history.visitCount == 0
              ? 'Historial'
              : 'Historial · ${history.visitCount}',
        ),
        const VbSubTab(value: _RecordTab.technical, label: 'Ficha técnica'),
        const VbSubTab(value: _RecordTab.notes, label: 'Notas'),
      ],
    );
  }

  Widget _buildStudio(
    BuildContext context,
    BoxConstraints constraints, {
    required bool loading,
    required bool failed,
    required _RecordHistory? history,
  }) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final workshopVisit = history?.workshopVisit;
    const pad = 28.0;
    final contentWidth = constraints.maxWidth - _identityWidth - pad * 2 - 1;
    final identity = Container(
      width: _identityWidth,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(right: BorderSide(color: roles.hairline)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showBackRow) ...[
              _buildBackRow(context, narrow: false),
              const SizedBox(height: 8),
            ] else
              const SizedBox(height: 16),
            _bikeDrawing(
              context,
              width: _identityWidth - 48,
              height: (_identityWidth - 48) * 0.62,
            ),
            const SizedBox(height: 20),
            _buildTitle(context, narrow: false),
            const SizedBox(height: 2),
            _buildOwner(context, narrow: false),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: VbButton(
                    label: 'Editar',
                    icon: Icons.edit_outlined,
                    variant: VbButtonVariant.secondary,
                    density: VbDensity.comfortable,
                    semanticLabel: 'Editar bicicleta',
                    expand: true,
                    onPressed: widget.onEdit,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: VbButton(
                    label: 'Nuevo trabajo',
                    icon: Icons.add,
                    density: VbDensity.comfortable,
                    expand: true,
                    onPressed: widget.onNewJob,
                  ),
                ),
              ],
            ),
            if (workshopVisit != null) ...[
              const SizedBox(height: 18),
              _buildWorkshopBand(context, workshopVisit, narrow: true),
            ],
            const SizedBox(height: 22),
            _buildFactList(context, _facts(history)),
          ],
        ),
      ),
    );
    return SizedBox(
      width: constraints.maxWidth,
      height: constraints.maxHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          identity,
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(pad, 20, pad, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTabs(history),
                  const SizedBox(height: 22),
                  switch (_tab) {
                    _RecordTab.history => _buildHistoryTab(
                        context,
                        loading: loading,
                        failed: failed,
                        history: history,
                        width: contentWidth,
                      ),
                    _RecordTab.technical =>
                      _buildTechnicalTab(context, width: contentWidth),
                    _RecordTab.notes => _buildNotesTab(context),
                  },
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Los datos de la bici, uno por línea, en la columna de identidad.
  Widget _buildFactList(
    BuildContext context,
    List<({String label, String? value})> facts,
  ) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < facts.length; index++)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              border: index == 0
                  ? null
                  : Border(top: BorderSide(color: roles.hairline)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                SizedBox(
                  width: 128,
                  child: Text(facts[index].label.toUpperCase(),
                      style: BikeModuleText.label(context)),
                ),
                Expanded(
                  child: Text(
                    facts[index].value ?? '—',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: facts[index].value == null
                          ? FontWeight.w500
                          : FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: facts[index].value == null
                          ? roles.faintForeground
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ── Cabecera ─────────────────────────────────────────────────────────────

  Widget _buildBackRow(BuildContext context, {required bool narrow}) {
    final theme = Theme.of(context);
    final back = TextButton.icon(
      onPressed: widget.onClose,
      icon: const Icon(Icons.chevron_left, size: 22),
      label: Text(
        widget.closeLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      style: TextButton.styleFrom(
        foregroundColor: theme.colorScheme.primary,
        minimumSize: const Size(44, 44),
        padding: const EdgeInsets.only(left: 2, right: 10),
      ),
    );
    if (!narrow) return Align(alignment: Alignment.centerLeft, child: back);
    return Row(
      children: [
        Expanded(
          child: Align(alignment: Alignment.centerLeft, child: back),
        ),
        const SizedBox(width: 8),
        IconButton.outlined(
          tooltip: 'Editar bicicleta',
          onPressed: widget.onEdit,
          icon: const Icon(Icons.edit_outlined, size: 20),
          style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
        ),
      ],
    );
  }

  String get _brand => widget.snapshot.bike.brand?.trim() ?? '';
  String get _model => widget.snapshot.bike.model?.trim() ?? '';

  String get _bikeLabel {
    final parts = [_brand, _model].where((part) => part.isNotEmpty);
    return parts.isEmpty ? 'Bicicleta sin nombre' : parts.join(' ');
  }

  String _drawingLabel() {
    final bike = widget.snapshot.bike;
    final type = bike.bikeType?.displayName ?? 'bicicleta';
    final color = bike.color?.trim();
    return color == null || color.isEmpty
        ? 'Dibujo de $type'
        : 'Dibujo de $type, ${color.toLowerCase()}';
  }

  Widget _bikeDrawing(
    BuildContext context, {
    required double width,
    required double height,
    List<BikeSilhouetteMarker> markers = const [],
  }) {
    final bike = widget.snapshot.bike;
    final photo = bike.imageUrl?.trim().isNotEmpty == true
        ? bike.imageUrl!.trim()
        : (bike.imageUrls.isNotEmpty ? bike.imageUrls.first : null);
    final drawing = BikeSilhouette(
      bikeType: bike.bikeType,
      colorText: bike.color,
      markers: markers,
      semanticLabel: _drawingLabel(),
    );
    return Container(
      width: width,
      height: height,
      padding: EdgeInsets.symmetric(
          horizontal: width * 0.06, vertical: height * 0.07),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: photo != null && markers.isEmpty
          ? Image.network(
              photo,
              fit: BoxFit.contain,
              semanticLabel: 'Foto de $_bikeLabel',
              errorBuilder: (_, __, ___) => drawing,
            )
          : drawing,
    );
  }

  Widget _buildTitle(BuildContext context, {required bool narrow}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_brand.isNotEmpty && _model.isNotEmpty)
          Text(
            _brand.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: BikeModuleText.eyebrow(context, size: narrow ? 13 : 15),
          ),
        Semantics(
          header: true,
          label: _bikeLabel,
          excludeSemantics: true,
          child: Text(
            _model.isNotEmpty
                ? _model
                : (_brand.isNotEmpty ? _brand : 'Bicicleta sin nombre'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: BikeModuleText.title(context, size: narrow ? 32 : 44),
          ),
        ),
      ],
    );
  }

  Widget _buildOwner(BuildContext context, {required bool narrow}) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final name = widget.ownerName.trim().isEmpty
        ? 'Sin dueño registrado'
        : widget.ownerName.trim();
    final open = widget.onOpenOwner;
    if (narrow) {
      return Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: open,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Dueño',
                            style: TextStyle(
                                fontSize: 12, color: roles.faintForeground)),
                        Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: open == null
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (open != null)
                    Icon(Icons.chevron_right, color: roles.faintForeground),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Dueño',
            style: TextStyle(fontSize: 14, color: roles.faintForeground)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: open == null
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.primary,
            ),
          ),
        ),
        if (open != null) ...[
          const SizedBox(width: 2),
          Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.primary),
        ],
      ],
    );
    if (open == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: label,
      );
    }
    return Tooltip(
      message: 'Abrir cliente',
      child: InkWell(
        onTap: open,
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Align(alignment: Alignment.centerLeft, child: label),
          ),
        ),
      ),
    );
  }

  List<({String label, String? value})> _facts(_RecordHistory? history) {
    final bike = widget.snapshot.bike;
    String? clean(String? value) =>
        value == null || value.trim().isEmpty ? null : value.trim();
    final color = clean(bike.color);
    return [
      (
        label: 'Color',
        value:
            color == null ? null : color[0].toUpperCase() + color.substring(1),
      ),
      (label: 'Aro', value: clean(bike.wheelSize)),
      (label: 'Tipo', value: bike.bikeType?.displayName),
      (label: 'Año', value: bike.year?.toString()),
      (label: 'N° de serie', value: clean(bike.serialNumber)),
      (
        label: 'Visitas',
        value: history == null ? null : '${history.visitCount}',
      ),
      (
        label: 'Última visita',
        value: history?.lastVisitAt == null
            ? null
            : bikeFullDate(history!.lastVisitAt!),
      ),
    ];
  }

  Widget _factCell(BuildContext context, ({String label, String? value}) fact) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(fact.label.toUpperCase(), style: BikeModuleText.label(context)),
        const SizedBox(height: 3),
        Text(
          fact.value ?? '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: fact.value == null ? FontWeight.w500 : FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: fact.value == null
                ? roles.faintForeground
                : theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildWideHeader(
    BuildContext context,
    _RecordHistory? history, {
    required double width,
  }) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final roomy = width >= 900;
    final facts = _facts(history);
    final workshopVisit = history?.workshopVisit;
    final columns = width >= 980 ? facts.length : 4;
    final cellWidth = (width - 2) / columns;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                _bikeDrawing(
                  context,
                  width: roomy ? 236 : 176,
                  height: roomy ? 150 : 112,
                ),
                const SizedBox(width: 28),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildTitle(context, narrow: false),
                      const SizedBox(height: 4),
                      _buildOwner(context, narrow: false),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  alignment: WrapAlignment.end,
                  children: [
                    VbButton(
                      label: 'Editar',
                      icon: Icons.edit_outlined,
                      variant: VbButtonVariant.secondary,
                      density: VbDensity.comfortable,
                      semanticLabel: 'Editar bicicleta',
                      onPressed: widget.onEdit,
                    ),
                    VbButton(
                      label: 'Nuevo trabajo',
                      icon: Icons.add,
                      density: VbDensity.comfortable,
                      onPressed: widget.onNewJob,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (workshopVisit != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: _buildWorkshopBand(context, workshopVisit, narrow: false),
            ),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: roles.hairline)),
            ),
            child: Wrap(
              children: [
                for (var index = 0; index < facts.length; index++)
                  Container(
                    width: cellWidth,
                    padding: const EdgeInsets.fromLTRB(24, 14, 16, 14),
                    decoration: BoxDecoration(
                      border: Border(
                        right: (index + 1) % columns == 0
                            ? BorderSide.none
                            : BorderSide(color: roles.hairline),
                        top: index >= columns
                            ? BorderSide(color: roles.hairline)
                            : BorderSide.none,
                      ),
                    ),
                    child: _factCell(context, facts[index]),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneHeader(BuildContext context, _RecordHistory? history) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final facts = _facts(history)
        .where((fact) => fact.label != 'N° de serie' || fact.value != null)
        .toList();
    final workshopVisit = history?.workshopVisit;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _bikeDrawing(context, width: 132, height: 88),
            const SizedBox(width: 16),
            Expanded(child: _buildTitle(context, narrow: true)),
          ],
        ),
        const SizedBox(height: 16),
        _buildOwner(context, narrow: true),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final half = (constraints.maxWidth - 2) / 2;
              return Wrap(
                children: [
                  for (var index = 0; index < facts.length; index++)
                    Container(
                      width: half,
                      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                      decoration: BoxDecoration(
                        border: Border(
                          right: index.isEven
                              ? BorderSide(color: roles.hairline)
                              : BorderSide.none,
                          top: index >= 2
                              ? BorderSide(color: roles.hairline)
                              : BorderSide.none,
                        ),
                      ),
                      child: _factCell(context, facts[index]),
                    ),
                ],
              );
            },
          ),
        ),
        if (workshopVisit != null) ...[
          const SizedBox(height: 12),
          _buildWorkshopBand(context, workshopVisit, narrow: true),
        ],
        const SizedBox(height: 14),
        VbButton(
          label: 'Nuevo trabajo',
          icon: Icons.add,
          expand: true,
          onPressed: widget.onNewJob,
        ),
      ],
    );
  }

  Widget _buildWorkshopBand(
    BuildContext context,
    BikeVisit visit, {
    required bool narrow,
  }) {
    final roles = VinabikeThemeRoles.of(context);
    final job = visit.job;
    final days = calendarDaysBetween(job.arrivalDate, _today);
    final since = days == 0
        ? 'En el taller desde hoy'
        : 'En el taller hace ${days == 1 ? '1 día' : '$days días'}';
    final details = Wrap(
      spacing: 14,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          since,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: roles.onSelectionContainer,
          ),
        ),
        if (job.jobNumber != null)
          Text(job.jobNumber!, style: BikeModuleText.code(context)),
        BikeJobStatusDot(
          label: jobStatusLabel(job),
          color: jobStatusColor(job),
          fontSize: 14,
        ),
        if (visit.amount > 0)
          Text(
            _money.format(visit.amount),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
    final open = VbButton(
      label: 'Abrir trabajo',
      icon: Icons.arrow_forward,
      variant: VbButtonVariant.secondary,
      density: narrow ? null : VbDensity.comfortable,
      expand: narrow,
      onPressed: job.id == null ? null : () => _openJob(job.id),
      disabledReason:
          job.id == null ? 'El trabajo todavía no se guarda.' : null,
    );
    return Semantics(
      container: true,
      child: Container(
        padding: EdgeInsets.fromLTRB(16, 12, 12, narrow ? 12 : 12),
        decoration: BoxDecoration(
          color: roles.selectionContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: roles.accentBorder),
        ),
        child: narrow
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [details, const SizedBox(height: 10), open],
              )
            : Row(
                children: [
                  Expanded(child: details),
                  const SizedBox(width: 12),
                  open,
                ],
              ),
      ),
    );
  }

  // ── Historial ────────────────────────────────────────────────────────────

  Widget _buildHistoryLoadFailure(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Semantics(
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 32, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('No pudimos cargar el historial.',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('Revisa la conexión y vuelve a intentar.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            VbButton(
              label: 'Reintentar historial',
              variant: VbButtonVariant.secondary,
              icon: Icons.refresh,
              onPressed: () => setState(_reloadHistory),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryTab(
    BuildContext context, {
    required bool loading,
    required bool failed,
    required _RecordHistory? history,
    required double width,
  }) {
    final theme = Theme.of(context);
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (failed || history == null) return _buildHistoryLoadFailure(theme);
    if (history.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            Text(
              'Esta bici todavía no tiene trabajos.',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'Cada trabajo del taller queda aquí, con lo que se le hizo.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final systems = _systemSummaries(history);
    final filter = systems.any((summary) => summary.system == _systemFilter)
        ? _systemFilter
        : null;
    final wide = width >= 960;
    final narrow = width < 640;
    final visits = filter == null
        ? history.visits
        : history.visits
            .where((visit) => visit.systems.contains(filter))
            .toList();

    final timeline = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (filter != null) ...[
          _buildSystemMemory(context, history, filter),
        ],
        for (final visit in visits)
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: _buildVisit(context, visit, filter: filter, narrow: narrow),
          ),
        if (visits.isEmpty && history.visits.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Ningún trabajo tocó este sistema.',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        if (history.memory.events.isNotEmpty)
          _buildEventsSection(context, history.memory.events),
      ],
    );

    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (systems.isNotEmpty) ...[
            _buildSystemChips(context, systems, filter),
            const SizedBox(height: 16),
          ],
          timeline,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: timeline),
        if (systems.isNotEmpty) ...[
          const SizedBox(width: 28),
          SizedBox(
            width: 300,
            child: _buildSystemRail(context, history, systems, filter),
          ),
        ],
      ],
    );
  }

  List<_SystemSummary> _systemSummaries(_RecordHistory history) {
    final bySystem = <JobLineSystem, _SystemSummary>{};
    for (final visit in history.visits) {
      if (_isCancelledJob(visit.job)) continue;
      for (final group in visit.groups) {
        final summary = bySystem.putIfAbsent(
            group.system, () => _SystemSummary(group.system));
        if (summary.lastDate == null || visit.date.isAfter(summary.lastDate!)) {
          summary.lastDate = visit.date;
        }
      }
    }
    for (final lifecycle in history.memory.componentLifecycles) {
      if (lifecycle.status != BikeComponentLifecycleStatus.installed) continue;
      final system = jobLineSystemFromKey(lifecycle.systemKey);
      if (system == null) continue;
      final summary =
          bySystem.putIfAbsent(system, () => _SystemSummary(system));
      summary.installed.add(lifecycle);
      if (summary.lastDate == null ||
          lifecycle.installedAt.isAfter(summary.lastDate!)) {
        summary.lastDate = lifecycle.installedAt;
      }
    }
    final summaries = bySystem.values.toList()
      ..sort((a, b) =>
          (b.lastDate ?? DateTime(0)).compareTo(a.lastDate ?? DateTime(0)));
    return summaries;
  }

  Widget _buildSystemRail(
    BuildContext context,
    _RecordHistory history,
    List<_SystemSummary> systems,
    JobLineSystem? filter,
  ) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    Widget option({
      required bool selected,
      required VoidCallback onTap,
      required Widget child,
      bool divider = true,
    }) {
      return Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected ? roles.selectionContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                border: divider && !selected
                    ? Border(top: BorderSide(color: roles.hairline))
                    : null,
              ),
              child: child,
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Semantics(
                header: true,
                child:
                    Text('POR SISTEMA', style: BikeModuleText.label(context)),
              ),
            ),
            option(
              selected: filter == null,
              divider: false,
              onTap: () => setState(() => _systemFilter = null),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Todo el historial',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: filter == null
                            ? roles.onSelectionContainer
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Text(
                    history.visitCount == 1
                        ? '1 visita'
                        : '${history.visitCount} visitas',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: filter == null
                          ? roles.onSelectionContainer
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            for (final summary in systems)
              option(
                selected: filter == summary.system,
                onTap: () => setState(() => _systemFilter =
                    filter == summary.system ? null : summary.system),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            summary.system.label,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: filter == summary.system
                                  ? roles.onSelectionContainer
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (summary.lastDate != null)
                          Text(
                            bikeShortDate(summary.lastDate!, today: _today),
                            style: TextStyle(
                                fontSize: 13, color: roles.faintForeground),
                          ),
                      ],
                    ),
                    for (final part in summary.installed.take(4))
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              margin: const EdgeInsets.only(top: 6, right: 8),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                part.componentLabel,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemChips(
    BuildContext context,
    List<_SystemSummary> systems,
    JobLineSystem? filter,
  ) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    Widget chip(String label, bool selected, VoidCallback onTap) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Semantics(
          button: true,
          selected: selected,
          child: Material(
            color:
                selected ? roles.selectionContainer : theme.colorScheme.surface,
            shape: StadiumBorder(
              side: BorderSide(
                color: selected
                    ? roles.accentBorder
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            child: InkWell(
              onTap: onTap,
              customBorder: const StadiumBorder(),
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? roles.onSelectionContainer
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('Todo', filter == null,
              () => setState(() => _systemFilter = null)),
          for (final summary in systems)
            chip(
              summary.system.label,
              filter == summary.system,
              () => setState(() => _systemFilter =
                  filter == summary.system ? null : summary.system),
            ),
        ],
      ),
    );
  }

  /// Lo que la memoria de la bici sabe del sistema elegido.
  Widget _buildSystemMemory(
    BuildContext context,
    _RecordHistory history,
    JobLineSystem system,
  ) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final views = history.memory.diagnosisSystems
        .where((view) => jobLineSystemFromKey(view.systemKey) == system)
        .toList();
    final installed = [
      for (final lifecycle in history.memory.componentLifecycles)
        if (lifecycle.status == BikeComponentLifecycleStatus.installed &&
            jobLineSystemFromKey(lifecycle.systemKey) == system)
          lifecycle,
    ];
    final notes = <String>[
      for (final view in views)
        if (view.state?.statusNote?.trim() case final note?
            when note.isNotEmpty)
          note,
    ];
    final series = [for (final view in views) ...view.measurementSeries];
    final observations = [
      for (final view in views) ...view.contextEntries,
    ]..sort((a, b) => b.observedAt.compareTo(a.observedAt));
    if (installed.isEmpty &&
        notes.isEmpty &&
        series.isEmpty &&
        observations.isEmpty) {
      return const SizedBox.shrink();
    }

    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title.toUpperCase(), style: BikeModuleText.label(context)),
              const SizedBox(height: 6),
              ...children,
            ],
          ),
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (installed.isNotEmpty)
            section('Montado por el taller', [
              for (final part in installed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: part.componentLabel,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(
                        text: '  desde ${bikeFullDate(part.installedAt)}'
                            '${part.payload['job_number'] != null ? ' · ${part.payload['job_number']}' : ''}',
                        style: TextStyle(color: roles.faintForeground),
                      ),
                    ]),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
            ]),
          if (notes.isNotEmpty)
            section('Estado', [
              for (final note in notes)
                Text(note, style: const TextStyle(fontSize: 14, height: 1.4)),
            ]),
          if (series.isNotEmpty)
            section('Mediciones', [
              for (final item in series)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${item.title} · ${item.latestValueLabel}',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      BikeMeasurementTimeline(
                        title: item.title,
                        unit: item.unit,
                        points: item.points,
                        accentColor: theme.colorScheme.primary,
                      ),
                    ],
                  ),
                ),
            ]),
          if (observations.isNotEmpty)
            section('Diagnósticos', [
              for (final observation in observations.take(3))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: '${bikeFullDate(observation.observedAt)}  ',
                        style: TextStyle(color: roles.faintForeground),
                      ),
                      TextSpan(
                        text: observation.summary?.trim().isNotEmpty == true
                            ? observation.summary!.trim()
                            : observation.title,
                      ),
                    ]),
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                ),
            ]),
        ],
      ),
    );
  }

  Widget _buildVisit(
    BuildContext context,
    BikeVisit visit, {
    required JobLineSystem? filter,
    required bool narrow,
  }) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final job = visit.job;
    final groups = filter == null
        ? visit.groups
        : visit.groups.where((group) => group.system == filter).toList();
    final days = visit.daysInWorkshop(_today);
    final arrival = bikeShortDate(job.arrivalDate, today: _today);
    final daysText = days == 1 ? '1 día' : '$days días';
    final meta = switch ((visit.inWorkshop, days)) {
      (true, 0) => 'Ingresó hoy',
      (true, _) => 'Ingresó el $arrival · lleva $daysText',
      (false, 0) => 'Ingresó el $arrival · salió el mismo día',
      (false, _) => 'Ingresó el $arrival · $daysText en el taller',
    };
    final cancelled = _isCancelledJob(job);

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (narrow)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      bikeFullDate(visit.date),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (job.jobNumber != null)
                      Semantics(
                        button: job.id != null,
                        label: 'Abrir trabajo ${job.jobNumber}',
                        // Sin el hijo en la semántica, la acción va aquí.
                        onTap: job.id == null ? null : () => _openJob(job.id),
                        excludeSemantics: true,
                        child: InkWell(
                          onTap: job.id == null ? null : () => _openJob(job.id),
                          borderRadius: BorderRadius.circular(6),
                          child: ConstrainedBox(
                            // En teléfono el número es un objetivo táctil.
                            constraints: BoxConstraints(
                              minHeight: narrow ? 48 : 28,
                              minWidth: narrow ? 48 : 0,
                            ),
                            child: Align(
                              widthFactor: 1,
                              heightFactor: 1,
                              child: Text(
                                job.jobNumber!,
                                style: BikeModuleText.code(context,
                                    color: theme.colorScheme.primary),
                              ),
                            ),
                          ),
                        ),
                      ),
                    BikeJobStatusDot(
                      label: jobStatusLabel(job),
                      color: jobStatusColor(job),
                      muted: cancelled,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  style: TextStyle(
                      fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            visit.amount > 0 ? _money.format(visit.amount) : '—',
            style:
                BikeModuleText.figure(context, size: narrow ? 19 : 22).copyWith(
              color: cancelled
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurface,
              decoration: cancelled ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
    );

    final request = visit.request?.trim();
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          if (request != null && request.isNotEmpty && filter == null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
              child: Text.rich(
                TextSpan(children: [
                  const TextSpan(
                    text: 'Pidió: ',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: bikeRequestAsSentence(request),
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ]),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
            ),
          if (groups.isEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: roles.hairline)),
              ),
              child: Text(
                'Sin líneas registradas para esta bici.',
                style: TextStyle(fontSize: 14, color: roles.faintForeground),
              ),
            ),
          for (final group in groups)
            Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: roles.hairline)),
              ),
              child: narrow
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(group.system.label.toUpperCase(),
                            style: BikeModuleText.label(context)),
                        const SizedBox(height: 6),
                        for (final line in group.lines)
                          _buildLine(context, line, narrow: true),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 128,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Text(
                              group.system.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final line in group.lines)
                                _buildLine(context, line, narrow: false),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          if (visit.separatePurchaseAmount > 0 && filter == null)
            Container(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: roles.hairline)),
              ),
              child: Text(
                'Además, ${_money.format(visit.separatePurchaseAmount)} en '
                'compras aparte en este trabajo.',
                style: TextStyle(fontSize: 13, color: roles.faintForeground),
              ),
            ),
        ],
      ),
    );

    if (narrow) return card;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  visit.date.toLocal().day.toString().padLeft(2, '0'),
                  style: BikeModuleText.figure(context, size: 32)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  bikeMonthYear(visit.date).toUpperCase(),
                  style: BikeModuleText.label(context),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(child: card),
      ],
    );
  }

  /// Lo que pidió el cliente en una línea: sin las viñetas con que se
  /// escribió («+Diagnóstico…») y sin puntos repetidos al unir renglones.
  Widget _buildLine(BuildContext context, BikeVisitLine line,
      {required bool narrow}) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final quantity = line.quantity == 1
        ? ''
        : ' × ${line.quantity == line.quantity.roundToDouble() ? line.quantity.toInt() : line.quantity}';
    final amount = Text(
      line.amount > 0 ? _money.format(line.amount) : '—',
      textAlign: TextAlign.end,
      style: TextStyle(
        fontSize: 14,
        fontFeatures: const [FontFeature.tabularFigures()],
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${line.name}$quantity'),
                if (line.isService && narrow)
                  TextSpan(
                    text: ' · servicio',
                    style:
                        TextStyle(fontSize: 12, color: roles.faintForeground),
                  ),
              ]),
              style: const TextStyle(fontSize: 14, height: 1.35),
            ),
          ),
          if (!narrow)
            SizedBox(
              width: 72,
              child: Text(
                line.isService ? 'Servicio' : 'Repuesto',
                style: TextStyle(fontSize: 12, color: roles.faintForeground),
              ),
            ),
          SizedBox(width: narrow ? 78 : 90, child: amount),
        ],
      ),
    );
  }

  Widget _buildEventsSection(BuildContext context, List<BikeEvent> events) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
          title: const Text(
            'Cambios de la ficha',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${events.length} registro${events.length == 1 ? '' : 's'}',
            style: TextStyle(fontSize: 13, color: roles.faintForeground),
          ),
          children: [
            for (final event in events)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(
                        bikeFullDate(event.eventDate),
                        style: TextStyle(
                          fontSize: 13,
                          color: roles.faintForeground,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            event.referenceNumber?.isNotEmpty == true
                                ? '${event.title} · ${event.referenceNumber}'
                                : event.title,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          if (event.summary?.isNotEmpty == true)
                            Text(
                              event.summary!,
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.4,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Ficha técnica ────────────────────────────────────────────────────────

  List<_SpecGroup> _specGroups() {
    final bike = widget.snapshot.bike;
    final suspension = _buildTechnicalPanelData('suspension');
    final drivetrain = _buildTechnicalPanelData('drivetrain');
    final bottomBracket = _buildTechnicalPanelData('bottom_bracket');
    final front = _buildTechnicalPanelData('front_brake');
    final rear = _buildTechnicalPanelData('rear_brake');
    final wheels = _buildTechnicalPanelData('wheels');
    final frontWheel = _buildTechnicalPanelData('front_wheel');
    final rearWheel = _buildTechnicalPanelData('rear_wheel');

    String? missing(int known, int expected, String empty, String partial) =>
        known == 0 ? empty : (known < expected ? partial : null);

    // Cuadro: la plataforma y la suspensión de la ficha, más la talla.
    final frameFacts = [
      ...suspension.facts,
      if (bike.frameSize?.trim().isNotEmpty == true)
        _BikeRecordTechnicalFact(label: 'Talla', value: bike.frameSize!.trim()),
    ];

    // Frenos: los dos frenos en un grupo; lo que comparten se dice una vez.
    final brakeFacts = <_BikeRecordTechnicalFact>[];
    final platform = front.facts.isNotEmpty ? front.facts.first : null;
    if (platform != null) brakeFacts.add(platform);
    _BikeRecordTechnicalFact? fluidOf(_BikeRecordTechnicalPanelData panel) {
      for (final fact in panel.facts) {
        if (fact.label == 'Fluido') return fact;
      }
      return null;
    }

    final frontFluid = fluidOf(front);
    final rearFluid = fluidOf(rear);
    for (final fact in front.facts.skip(1)) {
      if (fact.label != 'Fluido') brakeFacts.add(fact);
    }
    for (final fact in rear.facts.skip(1)) {
      if (fact.label != 'Fluido') brakeFacts.add(fact);
    }
    if (frontFluid != null &&
        rearFluid != null &&
        frontFluid.value == rearFluid.value) {
      brakeFacts.add(frontFluid);
    } else {
      if (frontFluid != null) {
        brakeFacts.add(_relabel(frontFluid, 'Fluido delantero'));
      }
      if (rearFluid != null) {
        brakeFacts.add(_relabel(rearFluid, 'Fluido trasero'));
      }
    }
    final brakeExpected = front.expectedCount + rear.expectedCount - 1;
    final brakeKnown =
        front.knownCount + rear.knownCount - (rear.facts.isNotEmpty ? 1 : 0);

    // Ruedas: lo de las dos y, si la ficha lo dice, el anclaje de cada rotor.
    final wheelFacts = [
      ...wheels.facts,
      for (final fact in frontWheel.facts)
        if (fact.label == 'Anclaje del rotor')
          _relabel(fact, 'Anclaje rotor delantero'),
      for (final fact in rearWheel.facts)
        if (fact.label == 'Anclaje del rotor')
          _relabel(fact, 'Anclaje rotor trasero'),
    ];

    return [
      _SpecGroup(
        number: 1,
        title: 'Cuadro y suspensión',
        anchor: BikeSilhouetteAnchor.frame,
        facts: frameFacts,
        knownCount: suspension.knownCount,
        expectedCount: suspension.expectedCount,
        missingText: suspension.missingText,
      ),
      _SpecGroup(
        number: 2,
        title: 'Transmisión',
        anchor: BikeSilhouetteAnchor.drivetrain,
        facts: drivetrain.facts,
        knownCount: drivetrain.knownCount,
        expectedCount: drivetrain.expectedCount,
        missingText: drivetrain.missingText,
      ),
      _SpecGroup(
        number: 3,
        title: 'Pedalier',
        anchor: BikeSilhouetteAnchor.bottomBracket,
        facts: bottomBracket.facts,
        knownCount: bottomBracket.knownCount,
        expectedCount: bottomBracket.expectedCount,
        missingText: bottomBracket.missingText,
      ),
      _SpecGroup(
        number: 4,
        title: 'Frenos',
        anchor: BikeSilhouetteAnchor.brakes,
        facts: brakeFacts,
        knownCount: brakeKnown,
        expectedCount: brakeExpected,
        missingText: missing(
          brakeKnown,
          brakeExpected,
          'La ficha todavía no dice qué frenos tiene.',
          'Faltan datos de los frenos; el próximo servicio los pregunta.',
        ),
      ),
      _SpecGroup(
        number: 5,
        title: 'Ruedas',
        anchor: BikeSilhouetteAnchor.wheels,
        facts: wheelFacts,
        knownCount: wheels.knownCount,
        expectedCount: wheels.expectedCount,
        missingText: wheels.missingText,
      ),
      const _SpecGroup(
        number: 6,
        title: 'Dirección y cockpit',
        anchor: BikeSilhouetteAnchor.cockpit,
        facts: [],
        knownCount: 0,
        expectedCount: 1,
        missingText: null,
      ),
    ];
  }

  _BikeRecordTechnicalFact _relabel(
          _BikeRecordTechnicalFact fact, String label) =>
      _BikeRecordTechnicalFact(
        label: label,
        value: fact.value,
        source: fact.source,
        confirmed: fact.confirmed,
      );

  Widget _buildTechnicalTab(BuildContext context, {required double width}) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final groups = _specGroups();
    final markers = [
      for (final group in groups)
        BikeSilhouetteMarker(anchor: group.anchor, label: '${group.number}'),
    ];
    final wide = width >= 900;
    final confirmedAt = widget.snapshot.lastConfirmedAt;

    final mapCard = DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) => _bikeDrawing(
                context,
                width: constraints.maxWidth,
                height: constraints.maxWidth * 0.62,
                markers: markers,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(
                  confirmedAt != null ? Icons.check : Icons.info_outline,
                  size: 18,
                  color: confirmedAt != null
                      ? theme.colorScheme.primary
                      : roles.faintForeground,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    confirmedAt != null
                        ? 'Confirmada en el taller el ${bikeFullDate(confirmedAt)}'
                        : 'Todavía nadie la confirma en el taller.',
                    style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            VbButton(
              label: 'Editar ficha',
              icon: Icons.edit_outlined,
              variant: VbButtonVariant.secondary,
              expand: true,
              onPressed: widget.onEdit,
            ),
          ],
        ),
      ),
    );

    final cards = LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1080
            ? 3
            : (constraints.maxWidth >= 620 ? 2 : 1);
        final cardWidth = (constraints.maxWidth - 16 * (columns - 1)) / columns;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final group in groups)
              SizedBox(width: cardWidth, child: _buildSpecCard(context, group)),
          ],
        );
      },
    );

    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: mapCard,
          ),
          const SizedBox(height: 16),
          cards,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 360, child: mapCard),
        const SizedBox(width: 24),
        Expanded(child: cards),
      ],
    );
  }

  Widget _buildSpecCard(BuildContext context, _SpecGroup group) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final known = group.knownCount;
    final status = known == 0
        ? 'Sin datos'
        : (known < group.expectedCount ? 'Faltan datos' : 'Completo');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${group.number}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      group.title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                Text(
                  status,
                  style:
                      TextStyle(fontSize: 12.5, color: roles.faintForeground),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (group.facts.isEmpty)
              Text(
                group.missingText ?? 'Sin datos todavía.',
                style: TextStyle(fontSize: 14, color: roles.faintForeground),
              )
            else ...[
              for (final fact in group.facts) _buildSpecRow(context, fact),
              if (group.missingText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    group.missingText!,
                    style:
                        TextStyle(fontSize: 13, color: roles.faintForeground),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSpecRow(BuildContext context, _BikeRecordTechnicalFact fact) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final origin =
        bikeFactOriginCaption(fact.source, confirmed: fact.confirmed);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: roles.hairline)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              fact.label,
              style: TextStyle(
                  fontSize: 14, color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        fact.value,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    if (fact.confirmed) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message: 'Confirmado en el taller',
                        child: Icon(Icons.check_circle,
                            size: 15, color: roles.success.accent),
                      ),
                    ],
                  ],
                ),
                if (origin != null)
                  Text(
                    origin,
                    style:
                        TextStyle(fontSize: 12, color: roles.faintForeground),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Notas ────────────────────────────────────────────────────────────────

  Widget _buildNotesTab(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    final bike = widget.snapshot.bike;
    final purchase = <String>[
      if (bike.purchaseDate != null)
        'Comprada el ${bikeFullDate(bike.purchaseDate!)}',
      if (bike.purchasePrice != null && bike.purchasePrice! > 0)
        'Precio de compra ${_money.format(bike.purchasePrice)}',
      if (bike.warrantyUntil != null)
        'Garantía hasta el ${bikeFullDate(bike.warrantyUntil!)}',
    ];
    final sections = <({String title, List<String> lines, bool warn})>[
      if (widget.snapshot.warnings.isNotEmpty)
        (title: 'Advertencias', lines: widget.snapshot.warnings, warn: true),
      if (widget.snapshot.notesLines.isNotEmpty)
        (title: 'Notas', lines: widget.snapshot.notesLines, warn: false),
      if (widget.snapshot.intakeLines.isNotEmpty)
        (title: 'Recepción', lines: widget.snapshot.intakeLines, warn: false),
      if (purchase.isNotEmpty)
        (title: 'Compra y garantía', lines: purchase, warn: false),
      if (widget.snapshot.technicalLines.isNotEmpty)
        (
          title: 'Resumen técnico anterior',
          lines: widget.snapshot.technicalLines,
          warn: false,
        ),
    ];
    if (sections.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Text(
          'Sin notas para esta bici.',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 15, color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    Widget lineOf(String line, bool warn) {
      final color =
          warn ? roles.warning.onContainer : theme.colorScheme.onSurface;
      final split = line.indexOf(': ');
      // «Plataforma: MTB hardtail» se lee como dato y valor.
      if (!warn && split > 0 && split < 32) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: roles.hairline)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  line.substring(0, split),
                  style:
                      TextStyle(fontSize: 13.5, color: roles.faintForeground),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 3,
                child: Text(
                  line.substring(split + 2),
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: color),
                ),
              ),
            ],
          ),
        );
      }
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(line,
            style: TextStyle(fontSize: 14, height: 1.4, color: color)),
      );
    }

    Widget card(({String title, List<String> lines, bool warn}) section) =>
        Container(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
          decoration: BoxDecoration(
            color: section.warn
                ? roles.warning.container
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: section.warn
                  ? roles.warning.border
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  section.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: section.warn
                        ? roles.warning.onContainer
                        : theme.colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              for (final line in section.lines) lineOf(line, section.warn),
            ],
          ),
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1000
            ? 3
            : (constraints.maxWidth >= 620 ? 2 : 1);
        final width = (constraints.maxWidth - 16 * (columns - 1)) / columns;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final section in sections)
              SizedBox(width: width, child: card(section)),
          ],
        );
      },
    );
  }

  _BikeRecordTechnicalPanelData _buildTechnicalPanelData(String systemKey) {
    final bike = widget.snapshot.bike;
    final profile = widget.snapshot.profile;
    final technicalValues =
        profile?.technicalValues ?? const <String, dynamic>{};
    final technicalSources =
        profile?.technicalSources ?? const <String, dynamic>{};
    final technicalConfirmed =
        profile?.technicalConfirmed ?? const <String, dynamic>{};

    _BikeRecordTechnicalFact? profileFact(
      String fieldKey,
      String label,
      String? value,
    ) {
      if (value == null || value.trim().isEmpty) {
        return null;
      }
      return _BikeRecordTechnicalFact(
        label: label,
        value: value,
        source: technicalSources[fieldKey]?.toString(),
        confirmed: technicalConfirmed[fieldKey] == true,
      );
    }

    // El anclaje del rotor lo pone la maza (20260928130000): se muestra si
    // la ficha lo dice, sin contarlo entre lo que falta de la rueda.
    String? rotorMount(Object? code) => code == null
        ? null
        : code == 'unknown'
            ? 'Desconocido'
            : rotorMountLabel(code);

    String? brakeTypeLabel(String? raw) {
      switch (raw) {
        case 'rim':
          return 'Llanta';
        case 'mechanical_disc':
          return 'Disco mecánico';
        case 'hydraulic_disc':
          return 'Disco hidráulico';
        case 'roller_brake':
          return 'Roller brake';
        case 'drum_brake':
          return 'Tambor';
        case 'coaster_brake':
          return 'Contrapedal';
        case 'band_brake':
          return 'Banda';
        default:
          return raw;
      }
    }

    String? rimBrakeFamilyLabel(String? raw) {
      switch (raw) {
        case 'v_brake':
          return 'V-Brake';
        case 'cantilever':
          return 'Cantilever';
        case 'road_caliper_short_reach':
          return 'Caliper ruta corto';
        case 'road_caliper_long_reach':
          return 'Caliper ruta largo';
        case 'u_brake':
          return 'U-Brake';
        case 'rod_brake':
          return 'Freno de varilla';
        case 'other':
          return 'Otro sistema de llanta';
        case 'unknown':
          return 'Sin confirmar';
        default:
          return raw;
      }
    }

    String? suspensionLabel(String? raw) {
      switch (raw) {
        case 'rigid':
          return 'Rígida';
        case 'front_suspension':
          return 'Suspensión delantera';
        case 'full_suspension':
          return 'Doble suspensión';
        case 'unknown':
          return 'Desconocida';
        default:
          return raw;
      }
    }

    String? freehubLabel(String? raw) {
      switch (raw) {
        case 'shimano_hg':
          return 'Shimano HG';
        case 'microspline':
          return 'Micro Spline';
        case 'sram_xd':
          return 'SRAM XD';
        case 'campagnolo':
          return 'Campagnolo';
        case 'threaded_freewheel':
          return 'Rueda libre roscada';
        case 'bmx_driver':
          return 'Driver BMX';
        case 'fixed_threaded':
          return 'Rosca fija / contratuerca';
        case 'coaster_hub':
          return 'Maza contrapedal';
        case 'unknown':
          return 'Desconocido';
        default:
          return raw;
      }
    }

    String? valveLabel(String? raw) {
      switch (raw) {
        case 'presta':
          return 'Presta';
        case 'schrader':
          return 'Schrader';
        case 'dunlop':
          return 'Dunlop';
        case 'other':
          return 'Otra';
        case 'unknown':
          return 'Desconocida';
        default:
          return raw;
      }
    }

    String? bottomBracketLabel(String? raw) {
      return bottomBracketFamilyLabel(raw);
    }

    String formatSpacing(double? value) {
      if (value == null) return '';
      if (value == value.roundToDouble()) {
        return '${value.toInt()} mm';
      }
      return '${value.toStringAsFixed(1)} mm';
    }

    String formatRotor(dynamic value) {
      if (value == null) return '';
      return '${value.toString()} mm';
    }

    String? formatBottomBracketMeasurement(dynamic value) {
      return bottomBracketMeasurementLabel(value);
    }

    String? brakeType = technicalValues['brakeType']?.toString();
    String? rimFamily = technicalValues['rimBrakeFamily']?.toString();

    switch (systemKey) {
      case 'suspension':
        final facts = [
          profileFact('bikeType', 'Plataforma', bike.bikeType?.displayName),
          profileFact(
            'suspensionLayout',
            'Layout de suspensión',
            suspensionLabel(technicalValues['suspensionLayout']?.toString()),
          ),
        ].whereType<_BikeRecordTechnicalFact>().toList();
        final knownCount = facts.length;
        return _BikeRecordTechnicalPanelData(
          spec: bikeSystemControllerSpecFor(systemKey)!,
          description:
              'Este sistema fija la plataforma estructural que luego condiciona diagnóstico, compatibilidad y servicios.',
          facts: facts,
          expectedCount: 2,
          knownCount: knownCount,
          missingText: knownCount == 0
              ? 'Aún no hay datos confirmados de la suspensión.'
              : knownCount < 2
                  ? 'Falta confirmar el layout de suspensión para que el perfil técnico no dependa solo del tipo visual de bici.'
                  : null,
        );
      case 'front_brake':
      case 'rear_brake':
        final rotorKey =
            systemKey == 'front_brake' ? 'frontRotorSizeMm' : 'rearRotorSizeMm';
        final rotorLabel =
            systemKey == 'front_brake' ? 'Rotor delantero' : 'Rotor trasero';
        final fluidKey = systemKey == 'front_brake'
            ? 'frontBrakeFluidType'
            : 'rearBrakeFluidType';
        final facts = [
          profileFact(
              'brakeType', 'Plataforma de freno', brakeTypeLabel(brakeType)),
          if (brakeType == 'rim')
            profileFact('rimBrakeFamily', 'Familia llanta',
                rimBrakeFamilyLabel(rimFamily)),
          if (brakeType == 'mechanical_disc' || brakeType == 'hydraulic_disc')
            profileFact(
                rotorKey, rotorLabel, formatRotor(technicalValues[rotorKey])),
          // El fluido es de cada freno (paso F.2); con freno de llanta se
          // muestra sólo si la ficha lo tiene (los hay hidráulicos).
          if (brakeType == 'hydraulic_disc' ||
              technicalValues[fluidKey] != null)
            profileFact(
              fluidKey,
              'Fluido',
              technicalValues[fluidKey] == null
                  ? null
                  : brakeFluidLabel(technicalValues[fluidKey]),
            ),
        ].whereType<_BikeRecordTechnicalFact>().toList();
        final expectedCount = switch (brakeType) {
          'hydraulic_disc' => 3,
          'rim' || 'mechanical_disc' => 2,
          _ => 1,
        };
        final knownCount = facts.length;
        return _BikeRecordTechnicalPanelData(
          spec: bikeSystemControllerSpecFor(systemKey)!,
          description:
              'Lo que la ficha ya sabe de este freno. Un servicio no vuelve a '
              'preguntar lo confirmado.',
          facts: facts,
          expectedCount: expectedCount,
          knownCount: knownCount,
          missingText: knownCount == 0
              ? 'La ficha todavía no dice qué freno tiene.'
              : knownCount < expectedCount
                  ? 'Falta completar este freno en la ficha; mientras tanto, '
                      'el próximo servicio lo pregunta.'
                  : null,
        );
      case 'drivetrain':
        final facts = [
          profileFact('drivetrainConfig', 'Configuración',
              technicalValues['drivetrainConfig']?.toString()),
          profileFact('drivetrainSpeeds', 'Velocidades',
              technicalValues['drivetrainSpeeds']?.toString()),
          profileFact('freehubType', 'Driver / freehub',
              freehubLabel(technicalValues['freehubType']?.toString())),
        ].whereType<_BikeRecordTechnicalFact>().toList();
        final knownCount = facts.length;
        return _BikeRecordTechnicalPanelData(
          spec: bikeSystemControllerSpecFor(systemKey)!,
          description:
              'Este sistema consolida la compatibilidad real de transmisión para servicio, repuestos y lectura histórica. El pedalier ya no queda escondido aquí como detalle secundario.',
          facts: facts,
          expectedCount: 3,
          knownCount: knownCount,
          missingText: knownCount == 0
              ? 'Aún no hay datos confirmados de la transmisión.'
              : knownCount < 3
                  ? 'Falta completar los datos de la transmisión.'
                  : null,
        );
      case 'front_wheel':
        final facts = [
          profileFact('wheelSize', 'Aro compartido', bike.wheelSize),
          profileFact('frontAxleInterface', 'Eje delantero',
              axleInterfaceLabel(technicalValues['frontAxleInterface'])),
          profileFact('frontHubSpacingMm', 'Maza delantera',
              formatSpacing(bike.frontHubSpacingMm)),
          profileFact('frontSpokeHoles', 'Rayos delanteros',
              technicalValues['frontSpokeHoles']?.toString()),
          profileFact('valveType', 'Válvula compartida',
              valveLabel(technicalValues['valveType']?.toString())),
        ].whereType<_BikeRecordTechnicalFact>().toList();
        final knownCount = facts.length;
        if (profileFact('frontRotorMount', 'Anclaje del rotor',
                rotorMount(technicalValues['frontRotorMount']))
            case final mount?) {
          facts.add(mount);
        }
        return _BikeRecordTechnicalPanelData(
          spec: bikeSystemControllerSpecFor(systemKey)!,
          description:
              'Eje, maza y rayos son de esta rueda; el aro y la válvula, de '
              'las dos.',
          facts: facts,
          expectedCount: 5,
          knownCount: knownCount,
          missingText: knownCount == 0
              ? 'La ficha todavía no dice nada de la rueda delantera.'
              : knownCount < 5
                  ? 'Faltan datos de la rueda delantera; el próximo servicio '
                      'los pregunta.'
                  : null,
        );
      case 'bottom_bracket':
        final bottomBracketFamily =
            technicalValues['bottomBracketFamily']?.toString();
        final usesShellDiameter =
            bottomBracketFamilyUsesShellDiameter(bottomBracketFamily);
        final facts = [
          profileFact('bottomBracketFamily', 'Familia pedalier / BB',
              bottomBracketLabel(bottomBracketFamily)),
          profileFact(
            'bbShellWidthMm',
            'Ancho caja',
            formatBottomBracketMeasurement(
              technicalValues['bbShellWidthMm'] ??
                  technicalValues['bb_shell_width_mm'],
            ),
          ),
          if (usesShellDiameter)
            profileFact(
              'bbShellDiameterMm',
              'Diametro shell / bore',
              formatBottomBracketMeasurement(
                technicalValues['bbShellDiameterMm'] ??
                    technicalValues['bb_shell_diameter_mm'],
              ),
            ),
          profileFact(
            'spindleInterface',
            'Interfaz del eje',
            bottomBracketSpindleInterfaceLabel(
              technicalValues['spindleInterface']?.toString() ??
                  technicalValues['spindle_interface']?.toString(),
            ),
          ),
        ].whereType<_BikeRecordTechnicalFact>().toList();
        final knownCount = facts.length;
        final expectedCount = 1 + 1 + (usesShellDiameter ? 1 : 0) + 1;
        return _BikeRecordTechnicalPanelData(
          spec: bikeSystemControllerSpecFor(systemKey)!,
          description:
              'El pedalier vive como sistema propio porque su estándar y sus rodamientos son relevantes para servicio, compatibilidad y memoria técnica.',
          facts: facts,
          expectedCount: expectedCount,
          knownCount: knownCount,
          missingText: knownCount == 0
              ? 'Aún no hay datos confirmados del pedalier.'
              : knownCount < expectedCount
                  ? (usesShellDiameter
                      ? 'Falta completar ancho, bore o interfaz del eje para que el pedalier no quede reducido a una familia demasiado amplia.'
                      : 'Falta completar ancho o interfaz del eje para que el pedalier no quede reducido a una familia demasiado amplia.')
                  : null,
        );
      case 'rear_wheel':
        final facts = [
          profileFact('wheelSize', 'Aro compartido', bike.wheelSize),
          profileFact('rearAxleInterface', 'Eje trasero',
              axleInterfaceLabel(technicalValues['rearAxleInterface'])),
          profileFact('rearHubSpacingMm', 'Maza trasera',
              formatSpacing(bike.rearHubSpacingMm)),
          profileFact('rearSpokeHoles', 'Rayos traseros',
              technicalValues['rearSpokeHoles']?.toString()),
          profileFact('valveType', 'Válvula compartida',
              valveLabel(technicalValues['valveType']?.toString())),
        ].whereType<_BikeRecordTechnicalFact>().toList();
        final knownCount = facts.length;
        if (profileFact('rearRotorMount', 'Anclaje del rotor',
                rotorMount(technicalValues['rearRotorMount']))
            case final mount?) {
          facts.add(mount);
        }
        return _BikeRecordTechnicalPanelData(
          spec: bikeSystemControllerSpecFor(systemKey)!,
          description:
              'Eje, maza y rayos son de esta rueda; el aro y la válvula, de '
              'las dos.',
          facts: facts,
          expectedCount: 5,
          knownCount: knownCount,
          missingText: knownCount == 0
              ? 'La ficha todavía no dice nada de la rueda trasera.'
              : knownCount < 5
                  ? 'Faltan datos de la rueda trasera; el próximo servicio '
                      'los pregunta.'
                  : null,
        );
      case 'wheels':
        final facts = [
          profileFact('wheelSize', 'Aro', bike.wheelSize),
          profileFact('frontAxleInterface', 'Eje delantero',
              axleInterfaceLabel(technicalValues['frontAxleInterface'])),
          profileFact('rearAxleInterface', 'Eje trasero',
              axleInterfaceLabel(technicalValues['rearAxleInterface'])),
          profileFact('frontHubSpacingMm', 'Maza delantera',
              formatSpacing(bike.frontHubSpacingMm)),
          profileFact('rearHubSpacingMm', 'Maza trasera',
              formatSpacing(bike.rearHubSpacingMm)),
          profileFact('frontSpokeHoles', 'Rayos delanteros',
              technicalValues['frontSpokeHoles']?.toString()),
          profileFact('rearSpokeHoles', 'Rayos traseros',
              technicalValues['rearSpokeHoles']?.toString()),
          profileFact('valveType', 'Válvula',
              valveLabel(technicalValues['valveType']?.toString())),
        ].whereType<_BikeRecordTechnicalFact>().toList();
        final knownCount = facts.length;
        return _BikeRecordTechnicalPanelData(
          // `wheels` no es un sistema del mapa antiguo: se presta el de la
          // rueda delantera, que la ficha de grupos no muestra.
          spec: bikeSystemControllerSpecFor('front_wheel')!,
          description:
              'Aro, ejes, mazas, rayos y válvula: con esto se eligen los '
              'repuestos de rueda que calzan.',
          facts: facts,
          expectedCount: 8,
          knownCount: knownCount,
          missingText: knownCount == 0
              ? 'La ficha todavía no dice nada de las ruedas.'
              : knownCount < 8
                  ? 'Faltan datos de ruedas y mazas; el próximo servicio los '
                      'pregunta.'
                  : null,
        );
      case 'cockpit':
      default:
        return _BikeRecordTechnicalPanelData(
          spec: bikeSystemControllerSpecFor(systemKey) ??
              kBikeSystemControllerSpecs.first,
          description:
              'La dirección, la tee, el manubrio y los controles forman este sistema.',
          facts: const [],
          expectedCount: 1,
          knownCount: 0,
          missingText:
              'Los datos de dirección y controles aún no están registrados.',
        );
    }
  }
}

class _BikeRecordTechnicalPanelData {
  final BikeSystemControllerSpec spec;
  final String description;
  final List<_BikeRecordTechnicalFact> facts;
  final int expectedCount;
  final int knownCount;
  final String? missingText;

  const _BikeRecordTechnicalPanelData({
    required this.spec,
    required this.description,
    required this.facts,
    required this.expectedCount,
    required this.knownCount,
    this.missingText,
  });
}

class _BikeRecordTechnicalFact {
  final String label;
  final String value;
  final String? source;
  final bool confirmed;

  const _BikeRecordTechnicalFact({
    required this.label,
    required this.value,
    this.source,
    this.confirmed = false,
  });
}

class _BikeRecordHistoryData {
  final List<BikeEvent> events;
  final List<BikeObservation> diagnosisObservations;
  final List<BikeSystemState> diagnosisStates;
  final List<BikeIntervention> interventions;
  final List<BikeComponentLifecycle> componentLifecycles;
  final List<_BikeDiagnosisSystemView> diagnosisSystems;
  final BikeObservation? overviewNarrativeObservation;

  const _BikeRecordHistoryData({
    required this.events,
    required this.diagnosisObservations,
    required this.diagnosisStates,
    required this.interventions,
    required this.componentLifecycles,
    required this.diagnosisSystems,
    required this.overviewNarrativeObservation,
  });

  const _BikeRecordHistoryData.empty()
      : events = const [],
        diagnosisObservations = const [],
        diagnosisStates = const [],
        interventions = const [],
        componentLifecycles = const [],
        diagnosisSystems = const [],
        overviewNarrativeObservation = null;

  factory _BikeRecordHistoryData.fromRaw({
    required List<BikeEvent> events,
    required List<BikeObservation> observations,
    required List<BikeSystemState> systemStates,
    required List<BikeIntervention> interventions,
    required List<BikeComponentLifecycle> componentLifecycles,
  }) {
    final filteredObservations = observations
        .where(
          (observation) =>
              observation.source == 'job_diagnosis_sync' ||
              observation.sourceField == 'diagnosis_sheet' ||
              observation.sourceField == 'diagnosis',
        )
        .toList()
      ..sort((a, b) => b.observedAt.compareTo(a.observedAt));

    final filteredStates =
        systemStates.where((state) => state.systemKey != 'general').toList()
          ..sort((a, b) {
            final severityCompare = _statusRank(b.overallStatus)
                .compareTo(_statusRank(a.overallStatus));
            if (severityCompare != 0) return severityCompare;
            final aTime =
                a.lastReviewedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bTime =
                b.lastReviewedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bTime.compareTo(aTime);
          });

    final sortedEvents = List<BikeEvent>.from(events)
      ..sort((a, b) {
        final dateCompare = b.eventDate.compareTo(a.eventDate);
        if (dateCompare != 0) return dateCompare;
        return b.createdAt.compareTo(a.createdAt);
      });

    final sortedInterventions = List<BikeIntervention>.from(interventions)
      ..sort((a, b) {
        final dateCompare = b.performedAt.compareTo(a.performedAt);
        if (dateCompare != 0) return dateCompare;
        return b.createdAt.compareTo(a.createdAt);
      });

    final sortedLifecycles =
        List<BikeComponentLifecycle>.from(componentLifecycles)
          ..sort((a, b) {
            final aAnchor = a.removedAt ?? a.installedAt;
            final bAnchor = b.removedAt ?? b.installedAt;
            final dateCompare = bAnchor.compareTo(aAnchor);
            if (dateCompare != 0) return dateCompare;
            return b.createdAt.compareTo(a.createdAt);
          });

    BikeObservation? overviewNarrativeObservation;
    for (final observation in filteredObservations) {
      if (observation.observationKey == 'job_diagnosis_note') {
        overviewNarrativeObservation = observation;
        break;
      }
    }

    final systemKeys = <String>{
      for (final state in filteredStates)
        if (state.systemKey != 'general') state.systemKey,
      for (final observation in filteredObservations)
        if (observation.systemKey != 'general') observation.systemKey,
      for (final intervention in sortedInterventions)
        if (intervention.systemKey != 'general') intervention.systemKey,
      for (final lifecycle in sortedLifecycles)
        if (lifecycle.systemKey != 'general') lifecycle.systemKey,
    };

    final diagnosisSystems = systemKeys.map((systemKey) {
      final matchingState = filteredStates
          .where((state) => state.systemKey == systemKey)
          .toList();
      matchingState.sort((a, b) {
        final aTime =
            a.lastReviewedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime =
            b.lastReviewedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final dateCompare = bTime.compareTo(aTime);
        if (dateCompare != 0) return dateCompare;
        return _statusRank(b.overallStatus)
            .compareTo(_statusRank(a.overallStatus));
      });
      final matchingObservations = filteredObservations
          .where((observation) => observation.systemKey == systemKey)
          .toList()
        ..sort((a, b) => b.observedAt.compareTo(a.observedAt));
      final matchingInterventions = sortedInterventions
          .where((intervention) => intervention.systemKey == systemKey)
          .toList();
      final matchingLifecycles = sortedLifecycles
          .where((lifecycle) => lifecycle.systemKey == systemKey)
          .toList();

      return _BikeDiagnosisSystemView(
        systemKey: systemKey,
        state: matchingState.isNotEmpty ? matchingState.first : null,
        observations: matchingObservations,
        interventions: matchingInterventions,
        componentLifecycles: matchingLifecycles,
      );
    }).toList()
      ..sort((a, b) {
        final severityCompare = _statusRank(b.overallStatus)
            .compareTo(_statusRank(a.overallStatus));
        if (severityCompare != 0) return severityCompare;
        final aDate = a.latestDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.latestDate ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

    return _BikeRecordHistoryData(
      events: sortedEvents,
      diagnosisObservations: filteredObservations,
      diagnosisStates: filteredStates,
      interventions: sortedInterventions,
      componentLifecycles: sortedLifecycles,
      diagnosisSystems: diagnosisSystems,
      overviewNarrativeObservation: overviewNarrativeObservation,
    );
  }

  bool get isEmpty =>
      events.isEmpty &&
      diagnosisObservations.isEmpty &&
      diagnosisStates.isEmpty &&
      interventions.isEmpty &&
      componentLifecycles.isEmpty;

  bool get hasStructuredWorkbench =>
      diagnosisSystems.isNotEmpty ||
      overviewNarrativeObservation != null ||
      interventions.isNotEmpty ||
      componentLifecycles.isNotEmpty;

  DateTime? get latestMemoryDate {
    final observationDate = diagnosisObservations.isNotEmpty
        ? diagnosisObservations.first.observedAt
        : null;
    final stateDate = diagnosisStates.isNotEmpty
        ? diagnosisStates
            .map((state) => state.lastReviewedAt)
            .whereType<DateTime>()
            .fold<DateTime?>(null, (latest, current) {
            if (latest == null || current.isAfter(latest)) {
              return current;
            }
            return latest;
          })
        : null;
    final interventionDate =
        interventions.isNotEmpty ? interventions.first.performedAt : null;
    final lifecycleDate = componentLifecycles.isNotEmpty
        ? componentLifecycles
            .map((lifecycle) => lifecycle.removedAt ?? lifecycle.installedAt)
            .fold<DateTime?>(null, (latest, current) {
            if (latest == null || current.isAfter(latest)) {
              return current;
            }
            return latest;
          })
        : null;

    final candidates = <DateTime?>[
      observationDate,
      stateDate,
      interventionDate,
      lifecycleDate,
    ].whereType<DateTime>().toList();

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.compareTo(a));
    return candidates.first;
  }

  String? get latestMemoryJobNumber {
    final candidates = <MapEntry<DateTime, String>>[];

    for (final observation in diagnosisObservations) {
      final jobNumber = observation.payload['job_number']?.toString();
      if (jobNumber != null && jobNumber.isNotEmpty) {
        candidates.add(MapEntry(observation.observedAt, jobNumber));
      }
    }

    for (final state in diagnosisStates) {
      final jobNumber = state.payload['job_number']?.toString();
      final reviewedAt = state.lastReviewedAt;
      if (jobNumber != null && jobNumber.isNotEmpty && reviewedAt != null) {
        candidates.add(MapEntry(reviewedAt, jobNumber));
      }
    }

    for (final intervention in interventions) {
      final jobNumber = intervention.payload['job_number']?.toString();
      if (jobNumber != null && jobNumber.isNotEmpty) {
        candidates.add(MapEntry(intervention.performedAt, jobNumber));
      }
    }

    for (final lifecycle in componentLifecycles) {
      final jobNumber = lifecycle.payload['job_number']?.toString();
      if (jobNumber != null && jobNumber.isNotEmpty) {
        candidates.add(
          MapEntry(lifecycle.removedAt ?? lifecycle.installedAt, jobNumber),
        );
      }
    }

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.key.compareTo(a.key));
    return candidates.first.value;
  }

  int get interventionCount => interventions.length;

  int get installedLifecycleCount => componentLifecycles
      .where((lifecycle) =>
          lifecycle.status == BikeComponentLifecycleStatus.installed)
      .length;

  String? get latestDiagnosisJobNumber {
    return latestMemoryJobNumber;
  }

  DateTime? get latestDiagnosisDate {
    return latestMemoryDate;
  }

  bool get hasDiagnosisMemory => hasStructuredWorkbench;

  String? resolveActiveSystemKey(String? preferred) {
    if (preferred != null && bikeSystemControllerSpecFor(preferred) != null) {
      return preferred;
    }

    return null;
  }

  _BikeDiagnosisSystemView? systemFor(String? systemKey) {
    if (systemKey == null) return null;
    for (final system in diagnosisSystems) {
      if (system.systemKey == systemKey) return system;
    }

    if (systemKey == 'front_wheel' || systemKey == 'rear_wheel') {
      for (final system in diagnosisSystems) {
        if (system.systemKey == 'wheels') {
          return _BikeDiagnosisSystemView(
            systemKey: systemKey,
            state: system.state,
            observations: system.observations,
            interventions: system.interventions,
            componentLifecycles: system.componentLifecycles,
          );
        }
      }
    }

    return null;
  }

  static int _statusRank(BikeSystemOverallStatus status) {
    switch (status) {
      case BikeSystemOverallStatus.critical:
        return 3;
      case BikeSystemOverallStatus.attention:
        return 2;
      case BikeSystemOverallStatus.ok:
        return 1;
      case BikeSystemOverallStatus.unknown:
        return 0;
    }
  }
}

class _BikeDiagnosisSystemView {
  final String systemKey;
  final BikeSystemState? state;
  final List<BikeObservation> observations;
  final List<BikeIntervention> interventions;
  final List<BikeComponentLifecycle> componentLifecycles;

  const _BikeDiagnosisSystemView({
    required this.systemKey,
    required this.state,
    required this.observations,
    required this.interventions,
    required this.componentLifecycles,
  });

  String get displayName {
    return bikeSystemControllerLabelFor(systemKey);
  }

  BikeSystemOverallStatus get overallStatus {
    if (state != null) return state!.overallStatus;

    for (final observation in assessmentObservations) {
      final explicitStatus = observation.statusValue?.trim();
      if (explicitStatus != null && explicitStatus.isNotEmpty) {
        return BikeSystemOverallStatus.values.firstWhere(
          (status) => status.dbValue == explicitStatus,
          orElse: () => BikeSystemOverallStatus.unknown,
        );
      }

      switch (observation.severity) {
        case BikeMemorySeverity.critical:
          return BikeSystemOverallStatus.critical;
        case BikeMemorySeverity.warning:
          return BikeSystemOverallStatus.attention;
        case BikeMemorySeverity.info:
          return BikeSystemOverallStatus.ok;
        case null:
          break;
      }
    }

    if (interventions.isNotEmpty) {
      return BikeSystemOverallStatus.ok;
    }

    return BikeSystemOverallStatus.unknown;
  }

  BikeObservation? get latestObservation =>
      observations.isNotEmpty ? observations.first : null;

  BikeIntervention? get latestIntervention =>
      interventions.isNotEmpty ? interventions.first : null;

  BikeComponentLifecycle? get latestLifecycle =>
      componentLifecycles.isNotEmpty ? componentLifecycles.first : null;

  BikeMemoryLocation get primaryLocation {
    if (state != null) return state!.location;
    if (latestIntervention != null) return latestIntervention!.location;
    if (latestLifecycle != null) return latestLifecycle!.location;
    if (latestObservation != null) return latestObservation!.location;
    return BikeMemoryLocation.none;
  }

  DateTime? get latestDate {
    final candidates = <DateTime?>[
      latestObservation?.observedAt,
      state?.lastReviewedAt,
      latestIntervention?.performedAt,
      latestLifecycle?.removedAt ?? latestLifecycle?.installedAt,
    ].whereType<DateTime>().toList();

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.compareTo(a));
    return candidates.first;
  }

  String get subheadline {
    final date = latestDate;
    final dateText = date != null
        ? DateFormat('dd/MM/yyyy').format(date)
        : 'sin fecha registrada';
    final jobNumber = latestJobNumber;
    if (jobNumber != null && jobNumber.isNotEmpty) {
      return 'Último movimiento $dateText · $jobNumber';
    }
    return 'Último movimiento $dateText';
  }

  String? get latestJobNumber {
    final candidates = <MapEntry<DateTime, String>>[];

    for (final observation in observations) {
      final jobNumber = observation.payload['job_number']?.toString();
      if (jobNumber != null && jobNumber.isNotEmpty) {
        candidates.add(MapEntry(observation.observedAt, jobNumber));
      }
    }

    final stateJobNumber = state?.payload['job_number']?.toString();
    if (stateJobNumber != null &&
        stateJobNumber.isNotEmpty &&
        state?.lastReviewedAt != null) {
      candidates.add(MapEntry(state!.lastReviewedAt!, stateJobNumber));
    }

    for (final intervention in interventions) {
      final jobNumber = intervention.payload['job_number']?.toString();
      if (jobNumber != null && jobNumber.isNotEmpty) {
        candidates.add(MapEntry(intervention.performedAt, jobNumber));
      }
    }

    for (final lifecycle in componentLifecycles) {
      final jobNumber = lifecycle.payload['job_number']?.toString();
      if (jobNumber != null && jobNumber.isNotEmpty) {
        candidates.add(
          MapEntry(lifecycle.removedAt ?? lifecycle.installedAt, jobNumber),
        );
      }
    }

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.key.compareTo(a.key));
    return candidates.first.value;
  }

  String? get primaryNarrative {
    for (final observation in assessmentObservations) {
      final summary = observation.summary?.trim();
      if (summary != null && summary.isNotEmpty) {
        return summary;
      }
    }
    final note = state?.statusNote?.trim();
    if (note != null && note.isNotEmpty) return note;

    final interventionSummary = latestIntervention?.summary?.trim();
    if (interventionSummary != null && interventionSummary.isNotEmpty) {
      return interventionSummary;
    }

    final interventionTitle = latestIntervention?.title.trim();
    if (interventionTitle != null && interventionTitle.isNotEmpty) {
      return interventionTitle;
    }

    final lifecycleNote = latestLifecycle?.notes?.trim();
    if (lifecycleNote != null && lifecycleNote.isNotEmpty) {
      return lifecycleNote;
    }

    return latestLifecycle?.componentLabel;
  }

  String? get currentStateSummary {
    final note = state?.statusNote?.trim();
    if (note != null && note.isNotEmpty) return note;

    final interventionSummary = latestIntervention?.summary?.trim();
    if (interventionSummary != null && interventionSummary.isNotEmpty) {
      return interventionSummary;
    }

    final interventionTitle = latestIntervention?.title.trim();
    if (interventionTitle != null && interventionTitle.isNotEmpty) {
      return interventionTitle;
    }

    final latestLifecycleLabel = latestLifecycle?.componentLabel.trim();
    if (latestLifecycleLabel != null && latestLifecycleLabel.isNotEmpty) {
      return 'Componente activo: $latestLifecycleLabel';
    }

    return null;
  }

  String? get currentStateSourceLabel {
    final derivedFrom = state?.payload['derived_from']?.toString();
    if (derivedFrom == 'intervention') {
      return 'Estado recalculado';
    }

    switch (state?.payload['source']?.toString()) {
      case 'diagnosis_sheet':
        return 'Diagnóstico estructurado';
      case 'job_diagnosis_sync':
        return 'Diagnóstico libre';
      case 'job_item_sync':
      case 'job_general_item_sync':
        return 'Trabajo ejecutado';
      default:
        break;
    }

    if (latestIntervention != null) return 'Último trabajo';
    if (latestObservation != null) return 'Último diagnóstico';
    if (latestLifecycle != null) return 'Componente vigente';
    return null;
  }

  DateTime? get currentStateUpdatedAt {
    return state?.lastReviewedAt ??
        latestIntervention?.performedAt ??
        latestDate;
  }

  String? get latestMeasureLabel {
    if (measurementSeries.isEmpty) return null;
    return measurementSeries.first.latestValueLabel;
  }

  List<BikeObservation> get assessmentObservations => observations
      .where(
        (observation) =>
            observation.observationKind ==
                BikeObservationKind.conditionAssessment ||
            observation.observationKind ==
                BikeObservationKind.diagnosisSnapshot,
      )
      .toList()
    ..sort((a, b) => b.observedAt.compareTo(a.observedAt));

  List<BikeObservation> get contextEntries =>
      assessmentObservations.take(4).toList();

  List<BikeIntervention> get recentInterventions => List<BikeIntervention>.from(
        interventions,
      )..sort((a, b) => b.performedAt.compareTo(a.performedAt));

  List<BikeComponentLifecycle> get installedComponents => componentLifecycles
      .where((lifecycle) =>
          lifecycle.status == BikeComponentLifecycleStatus.installed)
      .toList()
    ..sort((a, b) => b.installedAt.compareTo(a.installedAt));

  List<_BikeMeasurementSeries> get measurementSeries {
    final grouped = <String, List<BikeObservation>>{};

    for (final observation in observations) {
      if (observation.valueNumeric == null) continue;
      grouped
          .putIfAbsent(observation.observationKey, () => [])
          .add(observation);
    }

    final series = grouped.entries.map((entry) {
      final points = List<BikeObservation>.from(entry.value)
        ..sort((a, b) => a.observedAt.compareTo(b.observedAt));
      return _BikeMeasurementSeries(
        key: entry.key,
        title: points.last.title,
        unit: points.last.unit,
        points: points,
        subtitle: displayName,
      );
    }).toList()
      ..sort((a, b) =>
          b.points.last.observedAt.compareTo(a.points.last.observedAt));

    return series;
  }
}

class _BikeMeasurementSeries {
  final String key;
  final String title;
  final String? unit;
  final String subtitle;
  final List<BikeObservation> points;

  const _BikeMeasurementSeries({
    required this.key,
    required this.title,
    required this.unit,
    required this.subtitle,
    required this.points,
  });

  BikeMemorySeverity? get latestSeverity => points.last.severity;

  String get latestValueLabel {
    final latest = points.last;
    final value = latest.valueNumeric;
    if (value == null) return 'Sin dato';
    final formatted = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : (value.abs() >= 10
            ? value.toStringAsFixed(1)
            : value.toStringAsFixed(2));
    if (unit == null || unit!.isEmpty) return formatted;
    return '$formatted $unit';
  }

  String get firstDateLabel =>
      DateFormat('dd/MM').format(points.first.observedAt);

  String get lastDateLabel =>
      DateFormat('dd/MM').format(points.last.observedAt);
}
