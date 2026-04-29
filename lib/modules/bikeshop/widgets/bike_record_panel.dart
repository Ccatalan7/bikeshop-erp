import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../config/bottom_bracket_canonical_data.dart';
import '../models/bikeshop_models.dart';
import '../services/bikeshop_service.dart';
import 'bike_diagram_illustration.dart';
import 'bike_system_controller.dart';
import 'bike_measurement_timeline.dart';

class BikeRecordPanel extends StatefulWidget {
  final BikeRecordSnapshot snapshot;
  final String ownerName;
  final bool isLoading;
  final VoidCallback onEdit;
  final VoidCallback onNewJob;
  final VoidCallback onClose;

  const BikeRecordPanel({
    super.key,
    required this.snapshot,
    required this.ownerName,
    this.isLoading = false,
    required this.onEdit,
    required this.onNewJob,
    required this.onClose,
  });

  @override
  State<BikeRecordPanel> createState() => _BikeRecordPanelState();
}

class _BikeRecordPanelState extends State<BikeRecordPanel>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Future<_BikeRecordHistoryData> _historyFuture;
  String? _selectedDiagnosisSystemKey;
  String? _selectedTechnicalSystemKey;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)
      ..addListener(_handleTabChanged);
    _historyFuture = _loadBikeHistoryData(widget.snapshot.bike.id);
  }

  void _handleTabChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant BikeRecordPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.bike.id != widget.snapshot.bike.id) {
      _historyFuture = _loadBikeHistoryData(widget.snapshot.bike.id);
      _selectedDiagnosisSystemKey = null;
      _selectedTechnicalSystemKey = null;
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  Future<_BikeRecordHistoryData> _loadBikeHistoryData(String? bikeId) async {
    if (bikeId == null || bikeId.isEmpty) {
      return const _BikeRecordHistoryData.empty();
    }

    try {
      final bikeshopService = context.read<BikeshopService>();
      final results = await Future.wait<Object?>([
        bikeshopService.getBikeEvents(bikeId),
        bikeshopService.getBikeObservations(bikeId),
        bikeshopService.getBikeSystemStates(bikeId),
        bikeshopService.getBikeInterventions(bikeId),
        bikeshopService.getBikeComponentLifecycles(bikeId),
      ]);

      return _BikeRecordHistoryData.fromRaw(
        events: (results[0] as List<BikeEvent>?) ?? const [],
        observations: (results[1] as List<BikeObservation>?) ?? const [],
        systemStates: (results[2] as List<BikeSystemState>?) ?? const [],
        interventions: (results[3] as List<BikeIntervention>?) ?? const [],
        componentLifecycles:
            (results[4] as List<BikeComponentLifecycle>?) ?? const [],
      );
    } catch (_) {
      return const _BikeRecordHistoryData.empty();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return const ColoredBox(
        color: Colors.white,
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final theme = Theme.of(context);
    final showDesktopPreviewShell = MediaQuery.sizeOf(context).width >= 1100;

    // We generate a beautiful dynamic color profile based on the snapshot completion status
    final isComplete = widget.snapshot.isProfileComplete;
    final isStructured = widget.snapshot.hasStructuredProfile;

    final Color statusColor = isComplete
        ? Colors.teal
        : (isStructured ? Colors.blue.shade600 : Colors.amber.shade700);

    Widget buildContentShell({required bool mobile}) {
      return Column(
        children: [
          _buildRecordContentHeader(theme, mobile: mobile),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildGeneralTab(theme),
                _buildTechnicalSpecsTab(theme),
                _buildTimelineTab(theme),
              ],
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 768;
        final showDesktopPreviewPane = !isMobile && showDesktopPreviewShell;

        if (showDesktopPreviewPane) {
          return Container(
            color: Colors.grey.shade50,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 4,
                  child: _buildRecordPreviewPane(
                    theme,
                    statusColor: statusColor,
                    compact: false,
                  ),
                ),
                Expanded(
                  flex: 6,
                  child: buildContentShell(mobile: false),
                ),
              ],
            ),
          );
        }

        return Container(
          color: Colors.grey.shade50,
          child: Column(
            children: [
              SizedBox(
                height: 420,
                child: _buildRecordPreviewPane(
                  theme,
                  statusColor: statusColor,
                  compact: true,
                ),
              ),
              Expanded(child: buildContentShell(mobile: true)),
            ],
          ),
        );
      },
    );
  }

  int get _activeTabIndex => _tabController.index;

  Widget _buildRecordContentHeader(ThemeData theme, {required bool mobile}) {
    final tabs = [
      (title: 'General y Notas', icon: Icons.notes_outlined),
      (title: 'Ficha Técnica', icon: Icons.tune),
      (title: 'Historial', icon: Icons.timeline_outlined),
    ];

    Widget buildTabs({required bool desktop}) {
      return Container(
        height: desktop ? 72 : 64,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(desktop ? 24 : 18),
          border: Border.all(
            color: theme.dividerColor.withValues(alpha: 0.16),
          ),
        ),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: tabs.length,
          itemBuilder: (context, index) {
            final isActive = _activeTabIndex == index;
            final tab = tabs[index];
            return InkWell(
              borderRadius: BorderRadius.circular(desktop ? 22 : 16),
              onTap: () => _tabController.animateTo(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: EdgeInsets.symmetric(
                  horizontal: desktop ? 22 : 18,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(desktop ? 22 : 16),
                  color: isActive
                      ? theme.colorScheme.primary.withValues(alpha: 0.08)
                      : Colors.transparent,
                  border: Border(
                    bottom: BorderSide(
                      color: isActive
                          ? theme.colorScheme.primary
                          : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      tab.icon,
                      size: 18,
                      color: isActive
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      tab.title,
                      style: (desktop
                              ? theme.textTheme.titleMedium
                              : theme.textTheme.titleSmall)
                          ?.copyWith(
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w500,
                        color: isActive
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      );
    }

    return Container(
      padding: EdgeInsets.fromLTRB(mobile ? 16 : 24, mobile ? 14 : 18,
          mobile ? 16 : 24, mobile ? 10 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.12),
          ),
        ),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: buildTabs(desktop: !mobile)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecordPreviewPane(
    ThemeData theme, {
    required Color statusColor,
    required bool compact,
  }) {
    final bike = widget.snapshot.bike;
    final activeTab = _activeTabIndex;

    String title;
    String subtitle;
    Widget previewSurface;

    switch (activeTab) {
      case 1:
        title = 'Ficha Técnica';
        subtitle =
            'La bicicleta sigue visible mientras cambias de sistema y lees la verdad upstream del perfil.';
        previewSurface = _buildTechnicalPreviewSurface(theme);
        break;
      case 2:
        title = 'Historial técnico';
        subtitle =
            'La memoria, los trabajos y las observaciones viven alrededor del mismo mapa técnico de la bicicleta.';
        previewSurface = _buildHistoryPreviewSurface(theme);
        break;
      default:
        title = 'Registro de bicicleta';
        subtitle =
            'La bici queda siempre a la vista para navegar datos, ficha técnica e historial sin perder contexto.';
        previewSurface = _buildStaticBikePreviewSurface(theme);
        break;
    }

    final identityLine = [
      if (bike.brand?.isNotEmpty == true) bike.brand,
      if (bike.model?.isNotEmpty == true) bike.model,
    ].whereType<String>().join(' ');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(
          right: BorderSide(
            color: theme.dividerColor.withValues(alpha: compact ? 0.0 : 0.12),
          ),
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: compact ? 0.12 : 0.0),
          ),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 18 : 22,
          compact ? 16 : 24,
          compact ? 18 : 22,
          compact ? 16 : 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: widget.onClose,
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: Text(compact ? 'Volver' : 'Volver a bicicletas'),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.snapshot.isProfileComplete
                            ? Icons.verified_outlined
                            : Icons.pending_outlined,
                        size: 14,
                        color: statusColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        widget.snapshot.isProfileComplete
                            ? 'Perfil completo'
                            : 'Perfil incompleto',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 14 : 18),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF64748B),
                height: 1.45,
              ),
            ),
            SizedBox(height: compact ? 14 : 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (bike.brand ?? 'Sin marca').toUpperCase(),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: const Color(0xFF64748B),
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          bike.model ?? 'Modelo desconocido',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                        if (bike.year != null || identityLine.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            bike.year != null
                                ? '${bike.year} · Propietario: ${widget.ownerName}'
                                : 'Propietario: ${widget.ownerName}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF475569),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'Editar bicicleta',
                    onPressed: widget.onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.all(6),
                      minimumSize: const Size(32, 32),
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.outlined(
                    tooltip: 'Nuevo trabajo',
                    onPressed: widget.onNewJob,
                    icon: const Icon(Icons.build_outlined, size: 18),
                    style: IconButton.styleFrom(
                      padding: const EdgeInsets.all(6),
                      minimumSize: const Size(32, 32),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: compact ? 12 : 16),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: KeyedSubtree(
                  key: ValueKey<int>(activeTab),
                  child: previewSurface,
                ),
              ),
            ),
            SizedBox(height: compact ? 10 : 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (bike.bikeType != null)
                  _buildTechnicalMetaChip(
                    theme,
                    icon: Icons.directions_bike_outlined,
                    label: bike.bikeType!.displayName,
                  ),
                if (bike.wheelSize?.isNotEmpty == true)
                  _buildTechnicalMetaChip(
                    theme,
                    icon: Icons.circle_outlined,
                    label: 'Aro ${bike.wheelSize}',
                  ),
                _buildTechnicalMetaChip(
                  theme,
                  icon: activeTab == 2
                      ? Icons.timeline_outlined
                      : activeTab == 1
                          ? Icons.tune
                          : Icons.visibility_outlined,
                  label: activeTab == 2
                      ? 'Vista historial'
                      : activeTab == 1
                          ? 'Vista técnica'
                          : 'Vista general',
                  accent: true,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String? _recordMainImageUrl() {
    final bike = widget.snapshot.bike;
    if (bike.imageUrl?.isNotEmpty == true) {
      return bike.imageUrl;
    }
    if (bike.imageUrls.isNotEmpty) {
      return bike.imageUrls.first;
    }
    return null;
  }

  Widget _buildStaticBikePreviewSurface(ThemeData theme) {
    final bike = widget.snapshot.bike;
    final previewImageUrl = _recordMainImageUrl();
    final variant = resolveBikeDiagramVariant(bike: bike);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: AspectRatio(
          aspectRatio: 1,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: ColoredBox(
              color: theme.colorScheme.surfaceContainerLowest,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: previewImageUrl != null
                    ? Transform.scale(
                        scale: 1.12,
                        child: CachedNetworkImage(
                          imageUrl: previewImageUrl,
                          fit: BoxFit.contain,
                        ),
                      )
                    : Transform.scale(
                        scale: 1.08,
                        child: BikeDiagramIllustration(variant: variant),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTechnicalPreviewSurface(ThemeData theme) {
    final activeSystemKey = _resolveTechnicalSystemKey();
    final activeSpec = bikeSystemControllerSpecFor(activeSystemKey) ??
        kBikeSystemControllerSpecs.first;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Kernel Técnico Upstream',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'El mismo mapa compartido del taller ahora sostiene la lectura técnica del registro.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.grey.shade500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: BikeSystemController(
                bike: widget.snapshot.bike,
                profile: widget.snapshot.profile,
                entries: _buildTechnicalControllerEntries(),
                selectedSystemKey: activeSystemKey,
                onSystemSelected: (key) {
                  setState(() {
                    _selectedTechnicalSystemKey = key;
                  });
                },
                onClearSelection: () {
                  setState(() {
                    _selectedTechnicalSystemKey = null;
                  });
                },
                idleHintText:
                    'Haz clic en un sistema para leer su verdad upstream.',
                selectedHintText:
                    'Haz clic en otro sistema para cambiar el panel técnico.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildTechnicalMetaChip(
                theme,
                icon: activeSpec.icon,
                label: 'Sistema activo: ${activeSpec.label}',
                accent: true,
              ),
              if (widget.snapshot.lastConfirmedAt != null)
                _buildTechnicalMetaChip(
                  theme,
                  icon: Icons.verified_outlined,
                  label:
                      'Confirmado ${DateFormat('dd/MM/yyyy').format(widget.snapshot.lastConfirmedAt!)}',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryPreviewSurface(ThemeData theme) {
    return FutureBuilder<_BikeRecordHistoryData>(
      future: _historyFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        final history = snapshot.data ?? const _BikeRecordHistoryData.empty();
        if (!history.hasStructuredWorkbench) {
          return _buildStaticBikePreviewSurface(theme);
        }

        final activeSystemKey =
            history.resolveActiveSystemKey(_selectedDiagnosisSystemKey);
        final activeSystem = history.systemFor(activeSystemKey);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Memoria Técnica',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Observaciones, estados y trabajos ejecutados alrededor del mismo modelo técnico.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade500,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: BikeSystemController(
                    bike: widget.snapshot.bike,
                    profile: widget.snapshot.profile,
                    entries: _buildHistoryControllerEntries(history),
                    selectedSystemKey: activeSystemKey,
                    onSystemSelected: (key) {
                      setState(() {
                        _selectedDiagnosisSystemKey = key;
                      });
                    },
                    onClearSelection: () {
                      setState(() {
                        _selectedDiagnosisSystemKey = null;
                      });
                    },
                    overlayBuilder: (context, entry, layout) {
                      final hoveredSystem =
                          history.systemFor(entry.spec.systemKey);
                      if (hoveredSystem == null) {
                        return null;
                      }
                      return _DiagnosticPopupCard(
                        system: hoveredSystem,
                        color: _historySystemStatusColor(
                          hoveredSystem.overallStatus,
                        ),
                        layout: layout,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildTechnicalMetaChip(
                    theme,
                    icon: Icons.memory_outlined,
                    label: '${history.diagnosisSystems.length} sistemas',
                  ),
                  if (history.latestMemoryDate != null)
                    _buildTechnicalMetaChip(
                      theme,
                      icon: Icons.event_outlined,
                      label:
                          'Actualizado ${DateFormat('dd/MM/yyyy').format(history.latestMemoryDate!)}',
                    ),
                  if (activeSystem != null)
                    _buildTechnicalMetaChip(
                      theme,
                      icon: Icons.radar_outlined,
                      label: 'Activo: ${activeSystem.displayName}',
                      accent: true,
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGeneralTab(ThemeData theme) {
    final bike = widget.snapshot.bike;

    final baseData = [
      if (bike.bikeType != null)
        'Tipo de Bicicleta: ${bike.bikeType!.displayName}',
      if (bike.year != null) 'Año: ${bike.year}',
      if (bike.serialNumber != null && bike.serialNumber!.isNotEmpty)
        'Número de Serie: ${bike.serialNumber}',
      if (bike.color != null && bike.color!.isNotEmpty) 'Color: ${bike.color}',
      if (bike.frameSize != null && bike.frameSize!.isNotEmpty)
        'Talla de Cuadro: ${bike.frameSize}',
      if (bike.wheelSize != null && bike.wheelSize!.isNotEmpty)
        'Tamaño de Rueda: ${bike.wheelSize}',
      if (bike.purchaseDate != null)
        'Fecha de Compra: ${DateFormat('dd/MM/yyyy').format(bike.purchaseDate!)}',
      if (bike.warrantyUntil != null)
        'Garantía Hasta: ${DateFormat('dd/MM/yyyy').format(bike.warrantyUntil!)}',
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (baseData.isNotEmpty)
            _buildProSection(
              title: 'Datos de la Bicicleta',
              icon: Icons.directions_bike_outlined,
              iconColor: theme.primaryColor,
              bgColor: Colors.white,
              borderColor: Colors.grey.shade200,
              items: baseData,
              isGrid: true,
            ),
          if (widget.snapshot.warnings.isNotEmpty)
            _buildProSection(
              title: 'Advertencias / Notas Críticas',
              icon: Icons.warning_amber_rounded,
              iconColor: Colors.deepOrange,
              bgColor: Colors.orange.shade50,
              borderColor: Colors.orange.shade200,
              items: widget.snapshot.warnings,
            ),
          if (widget.snapshot.notesLines.isNotEmpty)
            _buildProSection(
              title: 'Notas Generales',
              icon: Icons.speaker_notes_outlined,
              iconColor: Colors.blueGrey.shade700,
              bgColor: Colors.white,
              borderColor: Colors.grey.shade200,
              items: widget.snapshot.notesLines,
            ),
          if (widget.snapshot.intakeLines.isNotEmpty)
            _buildProSection(
              title: 'Perfil de Recepción',
              icon: Icons.assignment_turned_in_outlined,
              iconColor: Colors.blue.shade700,
              bgColor: Colors.white,
              borderColor: Colors.grey.shade200,
              items: widget.snapshot.intakeLines,
            ),
        ],
      ),
    );
  }

  Widget _buildTechnicalSpecsTab(ThemeData theme) {
    if (widget.snapshot.profile == null &&
        widget.snapshot.technicalLines.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.build_circle_outlined,
                size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              'Aún no hay especificaciones técnicas registradas.',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
            ),
          ],
        ),
      );
    }

    final activeSystemKey = _resolveTechnicalSystemKey();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lectura técnica por sistema',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'El mapa técnico queda fijo a la izquierda y aquí lees el detalle upstream del sistema activo sin perder la bici de vista.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _buildTechnicalSystemCard(
            theme,
            _buildTechnicalPanelData(activeSystemKey),
          ),
          if (widget.snapshot.technicalLines.isNotEmpty)
            _buildProSection(
              title: 'Resumen Técnico',
              icon: Icons.settings_suggest_outlined,
              iconColor: Colors.purple.shade700,
              bgColor: Colors.white,
              borderColor: Colors.grey.shade200,
              items: widget.snapshot.technicalLines,
              isGrid: true,
            ),
        ],
      ),
    );
  }

  String _resolveTechnicalSystemKey() {
    final preferred = _selectedTechnicalSystemKey;
    if (preferred != null && bikeSystemControllerSpecFor(preferred) != null) {
      return preferred;
    }

    const preferredOrder = <String>[
      'suspension',
      'front_brake',
      'front_wheel',
      'drivetrain',
      'bottom_bracket',
      'rear_wheel',
      'rear_brake',
      'cockpit',
    ];

    for (final key in preferredOrder) {
      if (_technicalSystemStatus(key) != BikeSystemOverallStatus.ok) {
        return key;
      }
    }

    return 'drivetrain';
  }

  List<BikeSystemControllerEntry> _buildTechnicalControllerEntries() {
    return kBikeSystemControllerSpecs
        .map(
          (spec) => BikeSystemControllerEntry(
            spec: spec,
            status: _technicalSystemStatus(spec.systemKey),
          ),
        )
        .toList();
  }

  BikeSystemOverallStatus _technicalSystemStatus(String systemKey) {
    final panel = _buildTechnicalPanelData(systemKey);
    if (panel.knownCount <= 0) {
      return BikeSystemOverallStatus.critical;
    }
    if (panel.knownCount < panel.expectedCount) {
      return BikeSystemOverallStatus.attention;
    }
    return BikeSystemOverallStatus.ok;
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

    _BikeRecordTechnicalFact? baseFact(String label, String? value) {
      if (value == null || value.trim().isEmpty) {
        return null;
      }
      return _BikeRecordTechnicalFact(
          label: label, value: value, confirmed: true);
    }

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
          baseFact('Plataforma', bike.bikeType?.displayName),
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
              ? 'Todavía no hay verdad upstream para suspensión.'
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
        final facts = [
          profileFact(
              'brakeType', 'Plataforma de freno', brakeTypeLabel(brakeType)),
          if (brakeType == 'rim')
            profileFact('rimBrakeFamily', 'Familia llanta',
                rimBrakeFamilyLabel(rimFamily)),
          if (brakeType == 'mechanical_disc' || brakeType == 'hydraulic_disc')
            profileFact(
                rotorKey, rotorLabel, formatRotor(technicalValues[rotorKey])),
        ].whereType<_BikeRecordTechnicalFact>().toList();
        final expectedCount = brakeType == 'rim' ||
                brakeType == 'mechanical_disc' ||
                brakeType == 'hydraulic_disc'
            ? 2
            : 1;
        final knownCount = facts.length;
        return _BikeRecordTechnicalPanelData(
          spec: bikeSystemControllerSpecFor(systemKey)!,
          description:
              'La plataforma de freno vive upstream y este panel muestra el refinamiento confirmado que downstream no debería re-preguntar.',
          facts: facts,
          expectedCount: expectedCount,
          knownCount: knownCount,
          missingText: knownCount == 0
              ? 'Todavía no hay verdad upstream para este sistema de freno.'
              : knownCount < expectedCount
                  ? 'Todavía falta completar el refinamiento upstream de este freno para evitar nuevas preguntas en el wizard.'
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
              ? 'La transmisión sigue sin un kernel upstream usable.'
              : knownCount < 3
                  ? 'Faltan piezas del kernel de transmisión. El registro aún no es una verdad upstream completa.'
                  : null,
        );
      case 'front_wheel':
        final facts = [
          baseFact('Aro compartido', bike.wheelSize),
          baseFact('Maza delantera', formatSpacing(bike.frontHubSpacingMm)),
          profileFact('frontSpokeHoles', 'Rayos delanteros',
              technicalValues['frontSpokeHoles']?.toString()),
          profileFact('valveType', 'Válvula compartida',
              valveLabel(technicalValues['valveType']?.toString())),
        ].whereType<_BikeRecordTechnicalFact>().toList();
        final knownCount = facts.length;
        return _BikeRecordTechnicalPanelData(
          spec: bikeSystemControllerSpecFor(systemKey)!,
          description:
              'La unidad delantera separa maza y rayado de la rueda trasera, aunque siga reutilizando el aro y la válvula como baseline upstream compartido.',
          facts: facts,
          expectedCount: 4,
          knownCount: knownCount,
          missingText: knownCount == 0
              ? 'Todavía no hay un kernel upstream confirmado para la rueda delantera.'
              : knownCount < 4
                  ? 'Faltan datos de la rueda delantera para que la lectura histórica no vuelva a caer en un wheelset genérico.'
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
              ? 'Todavía no hay un kernel upstream confirmado para el pedalier.'
              : knownCount < expectedCount
                  ? (usesShellDiameter
                      ? 'Falta completar ancho, bore o interfaz del eje para que el pedalier no quede reducido a una familia demasiado amplia.'
                      : 'Falta completar ancho o interfaz del eje para que el pedalier no quede reducido a una familia demasiado amplia.')
                  : null,
        );
      case 'rear_wheel':
        final facts = [
          baseFact('Aro compartido', bike.wheelSize),
          baseFact('Maza trasera', formatSpacing(bike.rearHubSpacingMm)),
          profileFact('rearSpokeHoles', 'Rayos traseros',
              technicalValues['rearSpokeHoles']?.toString()),
          profileFact('valveType', 'Válvula compartida',
              valveLabel(technicalValues['valveType']?.toString())),
        ].whereType<_BikeRecordTechnicalFact>().toList();
        final knownCount = facts.length;
        return _BikeRecordTechnicalPanelData(
          spec: bikeSystemControllerSpecFor(systemKey)!,
          description:
              'La unidad trasera separa maza y rayado de la rueda delantera, aunque siga reutilizando el aro y la válvula como baseline upstream compartido.',
          facts: facts,
          expectedCount: 4,
          knownCount: knownCount,
          missingText: knownCount == 0
              ? 'Todavía no hay un kernel upstream confirmado para la rueda trasera.'
              : knownCount < 4
                  ? 'Faltan datos de la rueda trasera para que la lectura histórica no vuelva a caer en un wheelset genérico.'
                  : null,
        );
      case 'wheels':
        final facts = [
          baseFact('Aro', bike.wheelSize),
          baseFact('Maza delantera', formatSpacing(bike.frontHubSpacingMm)),
          baseFact('Maza trasera', formatSpacing(bike.rearHubSpacingMm)),
          profileFact('frontSpokeHoles', 'Rayos delanteros',
              technicalValues['frontSpokeHoles']?.toString()),
          profileFact('rearSpokeHoles', 'Rayos traseros',
              technicalValues['rearSpokeHoles']?.toString()),
          profileFact('valveType', 'Válvula',
              valveLabel(technicalValues['valveType']?.toString())),
        ].whereType<_BikeRecordTechnicalFact>().toList();
        final knownCount = facts.length;
        return _BikeRecordTechnicalPanelData(
          spec: bikeSystemControllerSpecFor(systemKey)!,
          description:
              'Rodado, mazas, rayado y válvula viven aquí como base de compatibilidad de ruedas.',
          facts: facts,
          expectedCount: 6,
          knownCount: knownCount,
          missingText: knownCount == 0
              ? 'Todavía no hay un kernel upstream confirmado para ruedas.'
              : knownCount < 6
                  ? 'Faltan datos de ruedas y mazas para que el historial sea una lectura completa del kernel.'
                  : null,
        );
      case 'cockpit':
      default:
        return _BikeRecordTechnicalPanelData(
          spec: bikeSystemControllerSpecFor(systemKey) ??
              kBikeSystemControllerSpecs.first,
          description:
              'El shared controller ya reserva este sistema en la lectura histórica, pero el v1 kernel aún no define una ficha upstream dedicada para cockpit/dirección. Headset y steering siguen anclados aquí aunque todavía no tengan esquema propio.',
          facts: const [],
          expectedCount: 1,
          knownCount: 0,
          missingText:
              'Cockpit / dirección sigue como placeholder explícito hasta que exista una capa real de esquema/editor para headset, stem, manillar y controles.',
        );
    }
  }

  Widget _buildTechnicalSystemCard(
    ThemeData theme,
    _BikeRecordTechnicalPanelData panel,
  ) {
    final status = _technicalSystemStatus(panel.spec.systemKey);
    final statusColor = _getSystemStatusColor(status);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE4E9F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(panel.spec.icon, color: statusColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      panel.spec.label,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      panel.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade500,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                  border:
                      Border.all(color: statusColor.withValues(alpha: 0.25)),
                ),
                child: Text(
                  switch (status) {
                    BikeSystemOverallStatus.ok => 'Completo',
                    BikeSystemOverallStatus.attention => 'Parcial',
                    BikeSystemOverallStatus.critical => 'Vacío',
                    BikeSystemOverallStatus.unknown => 'Placeholder',
                  },
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          if (panel.missingText != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: statusColor.withValues(alpha: 0.18)),
              ),
              child: Text(
                panel.missingText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (panel.facts.isEmpty)
            Text(
              'Todavía no hay valores técnicos que mostrar en este sistema.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade500,
              ),
            )
          else
            ...panel.facts.map(
              (fact) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              fact.label,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF475569),
                              ),
                            ),
                          ),
                          if (fact.confirmed)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.teal.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'Confirmado',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.teal.shade700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        fact.value,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      if (fact.source != null && fact.source!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Fuente: ${fact.source}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTechnicalMetaChip(
    ThemeData theme, {
    required IconData icon,
    required String label,
    bool accent = false,
  }) {
    final color = accent ? theme.primaryColor : const Color(0xFF64748B);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: accent
            ? theme.primaryColor.withValues(alpha: 0.08)
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: accent
              ? theme.primaryColor.withValues(alpha: 0.2)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineTab(ThemeData theme) {
    return FutureBuilder<_BikeRecordHistoryData>(
      future: _historyFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  'Error al cargar el historial: ${snapshot.error}',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        final history = snapshot.data ?? const _BikeRecordHistoryData.empty();

        if (history.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history_toggle_off, size: 64, color: Colors.black26),
                SizedBox(height: 16),
                Text(
                  'Aún no existen eventos en el historial.',
                  style: TextStyle(color: Colors.black54, fontSize: 16),
                ),
                SizedBox(height: 8),
                Text(
                  'El historial capturará automáticamente las actualizaciones del perfil y los trabajos de taller.',
                  style: TextStyle(color: Colors.black45, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          children: [
            if (history.hasStructuredWorkbench)
              _buildDiagnosisWorkbench(theme, history)
            else
              _buildLegacyEventsSection(
                theme,
                history.events,
                expanded: true,
              ),
            if (history.hasStructuredWorkbench &&
                history.events.isNotEmpty) ...[
              const SizedBox(height: 18),
              _buildLegacyEventsSection(theme, history.events),
            ],
          ],
        );
      },
    );
  }

  Widget _buildDiagnosisWorkbench(
    ThemeData theme,
    _BikeRecordHistoryData history,
  ) {
    final activeSystemKey =
        history.resolveActiveSystemKey(_selectedDiagnosisSystemKey);
    final activeSystem = history.systemFor(activeSystemKey);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFFE4E9F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Memoria técnica centralizada',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1E293B),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'El mapa técnico permanece fijo a la izquierda y este panel concentra indicadores, detalle activo y memoria transversal.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.grey.shade500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          _buildTelemetrySection(
            theme,
            history,
            activeSystemKey,
            activeSystem,
          ),
        ],
      ),
    );
  }

  List<BikeSystemControllerEntry> _buildHistoryControllerEntries(
    _BikeRecordHistoryData history,
  ) {
    return kBikeSystemControllerSpecs
        .map(
          (spec) => BikeSystemControllerEntry(
            spec: spec,
            status: history.systemFor(spec.systemKey)?.overallStatus ??
                BikeSystemOverallStatus.unknown,
          ),
        )
        .toList();
  }

  Color _historySystemStatusColor(BikeSystemOverallStatus status) {
    switch (status) {
      case BikeSystemOverallStatus.critical:
        return const Color(0xFFFF4B4B);
      case BikeSystemOverallStatus.attention:
        return const Color(0xFFFFAB2E);
      case BikeSystemOverallStatus.ok:
        return const Color(0xFF3EFFD0);
      case BikeSystemOverallStatus.unknown:
        return const Color(0xFF94A3B8);
    }
  }

  Widget _buildTelemetrySection(
    ThemeData theme,
    _BikeRecordHistoryData history,
    String? activeSystemKey,
    _BikeDiagnosisSystemView? activeSystem,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSystemExplorerCard(theme, history, activeSystemKey),
        const SizedBox(height: 16),
        _buildSystemDetailCard(theme, history, activeSystemKey, activeSystem),
      ],
    );
  }

  Widget _buildSystemExplorerCard(
    ThemeData theme,
    _BikeRecordHistoryData history,
    String? activeSystemKey,
  ) {
    final latestDate = history.latestMemoryDate;
    final criticalCount = history.diagnosisSystems
        .where((system) =>
            system.overallStatus == BikeSystemOverallStatus.critical)
        .length;
    final attentionCount = history.diagnosisSystems
        .where((system) =>
            system.overallStatus == BikeSystemOverallStatus.attention)
        .length;
    final selectedSystem = history.systemFor(activeSystemKey);
    final selectedSystemLabel = activeSystemKey == null
        ? null
        : bikeSystemControllerSpecFor(activeSystemKey)?.label ??
            selectedSystem?.displayName;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
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
                      'Memoria técnica',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      latestDate != null
                          ? 'Última actualización: ${DateFormat('dd/MM/yyyy').format(latestDate)}'
                          : 'Sin actualizaciones registradas.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (history.latestMemoryJobNumber != null)
                _buildReferencePill(
                  label: history.latestMemoryJobNumber!,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  borderColor: theme.colorScheme.primary.withValues(alpha: 0.3),
                  foregroundColor: theme.colorScheme.primary,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildReferencePill(
                label: '${history.diagnosisSystems.length} sistemas',
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                borderColor: theme.colorScheme.outlineVariant,
                foregroundColor: theme.colorScheme.onSurfaceVariant,
              ),
              if (history.interventionCount > 0)
                _buildReferencePill(
                  label:
                      '${history.interventionCount} trabajo${history.interventionCount == 1 ? '' : 's'}',
                  backgroundColor: Colors.teal.withValues(alpha: 0.15),
                  borderColor: Colors.teal.withValues(alpha: 0.3),
                  foregroundColor: Colors.tealAccent.shade100,
                ),
              if (history.installedLifecycleCount > 0)
                _buildReferencePill(
                  label:
                      '${history.installedLifecycleCount} componente${history.installedLifecycleCount == 1 ? '' : 's'} activo${history.installedLifecycleCount == 1 ? '' : 's'}',
                  backgroundColor: Colors.lightBlue.withValues(alpha: 0.15),
                  borderColor: Colors.lightBlue.withValues(alpha: 0.3),
                  foregroundColor: Colors.lightBlueAccent.shade100,
                ),
              if (criticalCount > 0)
                _buildReferencePill(
                  label:
                      '$criticalCount crítico${criticalCount == 1 ? '' : 's'}',
                  backgroundColor: Colors.red.withValues(alpha: 0.15),
                  borderColor: Colors.red.withValues(alpha: 0.3),
                  foregroundColor: Colors.redAccent,
                ),
              if (attentionCount > 0)
                _buildReferencePill(
                  label: '$attentionCount en atención',
                  backgroundColor: Colors.orange.withValues(alpha: 0.15),
                  borderColor: Colors.orange.withValues(alpha: 0.3),
                  foregroundColor: Colors.orangeAccent,
                ),
              if (selectedSystemLabel != null)
                _buildReferencePill(
                  label: 'Activo: $selectedSystemLabel',
                  backgroundColor: theme.colorScheme.primaryContainer,
                  borderColor: theme.colorScheme.primary.withValues(alpha: 0.3),
                  foregroundColor: theme.colorScheme.primary,
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (history.overviewNarrativeObservation?.summary != null &&
              history.overviewNarrativeObservation!.summary!
                  .trim()
                  .isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              'Narrativa original de la orden',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.5)),
              ),
              child: Text(
                history.overviewNarrativeObservation!.summary!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSystemDetailCard(
    ThemeData theme,
    _BikeRecordHistoryData history,
    String? activeSystemKey,
    _BikeDiagnosisSystemView? system,
  ) {
    if (system == null) {
      final selectedLabel = activeSystemKey == null
          ? null
          : bikeSystemControllerSpecFor(activeSystemKey)?.label;
      final selectedSpec = bikeSystemControllerSpecFor(activeSystemKey);

      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              selectedLabel ?? 'Selecciona un sistema',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              selectedLabel == null
                  ? 'Haz clic sobre un sistema del esquema para ver diagnóstico, trabajos realizados y componentes que quedaron instalados.'
                  : '${selectedSpec?.diagnosisSubtitle ?? 'Sistema sin detalle estructurado.'} Aún no existen observaciones, intervenciones ni memoria técnica suficiente para este sistema en el historial de esta bicicleta.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ),
      );
    }

    final accentColor = _getSystemStatusColor(system.overallStatus);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _systemIconFor(system.systemKey),
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            system.displayName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        _buildReferencePill(
                          label: system.overallStatus.displayName,
                          backgroundColor: accentColor.withValues(alpha: 0.15),
                          borderColor: accentColor.withValues(alpha: 0.3),
                          foregroundColor: accentColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      system.subheadline,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (system.primaryNarrative != null &&
              system.primaryNarrative!.trim().isNotEmpty) ...[
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.5)),
              ),
              child: Text(
                system.primaryNarrative!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
          ],
          if (system.currentStateSummary != null) ...[
            const SizedBox(height: 20),
            _buildMiniSectionLabel(theme, 'Estado actual'),
            const SizedBox(height: 10),
            _buildCurrentStateCard(theme, system, accentColor),
          ],
          if (system.installedComponents.isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildMiniSectionLabel(theme, 'Componentes instalados'),
            const SizedBox(height: 10),
            ...system.installedComponents
                .take(4)
                .map((lifecycle) => _buildLifecycleCard(theme, lifecycle)),
          ],
          if (system.recentInterventions.isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildMiniSectionLabel(theme, 'Trabajos aplicados'),
            const SizedBox(height: 10),
            ...system.recentInterventions.take(4).map(
                (intervention) => _buildInterventionCard(theme, intervention)),
          ],
          if (system.measurementSeries.isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildMiniSectionLabel(theme, 'Mediciones'),
            const SizedBox(height: 10),
            ...system.measurementSeries
                .map((series) => _buildMeasurementTimelineRow(theme, series)),
          ],
          if (system.contextEntries.isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildMiniSectionLabel(theme, 'Diagnósticos y observaciones'),
            const SizedBox(height: 10),
            ...system.contextEntries
                .map((entry) => _buildRelatedDiagnosisCard(theme, entry)),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniSectionLabel(ThemeData theme, String label) {
    return Text(
      label,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildMeasurementTimelineRow(
    ThemeData theme,
    _BikeMeasurementSeries series,
  ) {
    final accentColor = _getSeverityColor(series.latestSeverity);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white, // Light sleek
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        series.title,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF334155),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        series.subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildReferencePill(
                  label: series.latestValueLabel,
                  backgroundColor: accentColor.withValues(alpha: 0.15),
                  borderColor: accentColor.withValues(alpha: 0.3),
                  foregroundColor: accentColor,
                ),
              ],
            ),
          ),
          BikeMeasurementTimeline(
            title: series.title,
            unit: series.unit,
            points: series.points,
            accentColor: accentColor,
          ),
        ],
      ),
    );
  }

  Widget _buildRelatedDiagnosisCard(
    ThemeData theme,
    BikeObservation observation,
  ) {
    final accentColor = _getSeverityColor(observation.severity);
    final jobNumber = observation.payload['job_number']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  observation.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (jobNumber != null && jobNumber.isNotEmpty)
                _buildReferencePill(
                  label: jobNumber,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  borderColor: theme.colorScheme.outlineVariant,
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            observation.summary?.trim().isNotEmpty == true
                ? observation.summary!
                : observation.statusValue ?? 'Sin resumen detallado.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                DateFormat('dd/MM/yyyy').format(observation.observedAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (observation.severity != null) ...[
                const SizedBox(width: 8),
                _buildReferencePill(
                  label: _formatSeverityLabel(observation.severity),
                  backgroundColor: accentColor.withValues(alpha: 0.15),
                  borderColor: accentColor.withValues(alpha: 0.3),
                  foregroundColor: accentColor,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStateCard(
    ThemeData theme,
    _BikeDiagnosisSystemView system,
    Color accentColor,
  ) {
    final updatedAt = system.currentStateUpdatedAt;
    final location = system.primaryLocation;
    final sourceLabel = system.currentStateSourceLabel;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildReferencePill(
                label: system.overallStatus.displayName,
                backgroundColor: accentColor.withValues(alpha: 0.15),
                borderColor: accentColor.withValues(alpha: 0.3),
                foregroundColor: accentColor,
              ),
              if (location != BikeMemoryLocation.none)
                _buildReferencePill(
                  label: location.displayName,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  borderColor: theme.colorScheme.outlineVariant,
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                ),
              if (sourceLabel != null && sourceLabel.isNotEmpty)
                _buildReferencePill(
                  label: sourceLabel,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  borderColor: theme.colorScheme.outlineVariant,
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
          if (system.currentStateSummary != null &&
              system.currentStateSummary!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              system.currentStateSummary!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                height: 1.45,
              ),
            ),
          ],
          if (updatedAt != null) ...[
            const SizedBox(height: 10),
            Text(
              'Actualizado el ${DateFormat('dd/MM/yyyy').format(updatedAt)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInterventionCard(
    ThemeData theme,
    BikeIntervention intervention,
  ) {
    final accentColor =
        intervention.interventionType == BikeInterventionType.replacement
            ? Colors.tealAccent.shade100
            : Colors.blueAccent.shade100;
    final jobNumber = intervention.payload['job_number']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  intervention.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              _buildReferencePill(
                label: _formatInterventionTypeLabel(
                  intervention.interventionType,
                ),
                backgroundColor: accentColor.withValues(alpha: 0.15),
                borderColor: accentColor.withValues(alpha: 0.3),
                foregroundColor: accentColor,
              ),
            ],
          ),
          if (intervention.summary != null &&
              intervention.summary!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              intervention.summary!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildReferencePill(
                label:
                    DateFormat('dd/MM/yyyy').format(intervention.performedAt),
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                borderColor: theme.colorScheme.outlineVariant,
                foregroundColor: theme.colorScheme.onSurfaceVariant,
              ),
              if (intervention.location != BikeMemoryLocation.none)
                _buildReferencePill(
                  label: intervention.location.displayName,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  borderColor: theme.colorScheme.outlineVariant,
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                ),
              if (intervention.componentSlotKey != null &&
                  intervention.componentSlotKey!.isNotEmpty)
                _buildReferencePill(
                  label: _formatComponentSlotLabel(
                    intervention.componentSlotKey,
                  ),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  borderColor: theme.colorScheme.outlineVariant,
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                ),
              if (jobNumber != null && jobNumber.isNotEmpty)
                _buildReferencePill(
                  label: jobNumber,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  borderColor: theme.colorScheme.outlineVariant,
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLifecycleCard(
    ThemeData theme,
    BikeComponentLifecycle lifecycle,
  ) {
    final accentColor =
        lifecycle.status == BikeComponentLifecycleStatus.installed
            ? Colors.tealAccent.shade100
            : Colors.orangeAccent;
    final jobNumber = lifecycle.payload['job_number']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  lifecycle.componentLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              _buildReferencePill(
                label: _formatLifecycleStatusLabel(lifecycle.status),
                backgroundColor: accentColor.withValues(alpha: 0.15),
                borderColor: accentColor.withValues(alpha: 0.3),
                foregroundColor: accentColor,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (lifecycle.componentSlotKey.isNotEmpty)
                _buildReferencePill(
                  label: _formatComponentSlotLabel(lifecycle.componentSlotKey),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  borderColor: theme.colorScheme.outlineVariant,
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                ),
              if (lifecycle.location != BikeMemoryLocation.none)
                _buildReferencePill(
                  label: lifecycle.location.displayName,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  borderColor: theme.colorScheme.outlineVariant,
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                ),
              _buildReferencePill(
                label:
                    'Instalado ${DateFormat('dd/MM/yyyy').format(lifecycle.installedAt)}',
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                borderColor: theme.colorScheme.outlineVariant,
                foregroundColor: theme.colorScheme.onSurfaceVariant,
              ),
              if (jobNumber != null && jobNumber.isNotEmpty)
                _buildReferencePill(
                  label: jobNumber,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  borderColor: theme.colorScheme.outlineVariant,
                  foregroundColor: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
          if (lifecycle.notes != null &&
              lifecycle.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              lifecycle.notes!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLegacyEventsSection(
    ThemeData theme,
    List<BikeEvent> events, {
    bool expanded = false,
  }) {
    if (events.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: expanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          title: Text(
            expanded ? 'Historial de la bicicleta' : 'Eventos legacy',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
          subtitle: Text(
            expanded
                ? 'Eventos de perfil, ingresos, entregas y otros hitos registrados previamente.'
                : 'Oculta el ruido histórico y ábrelo solo cuando necesites contexto adicional.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.grey.shade600,
            ),
          ),
          trailing: _buildReferencePill(
            label: '${events.length}',
            backgroundColor: const Color(0xFFF3F6FA),
            borderColor: const Color(0xFFE1E7EF),
            foregroundColor: Colors.blueGrey.shade700,
          ),
          children: [
            _buildEventTimelineList(theme, events),
          ],
        ),
      ),
    );
  }

  Widget _buildReferencePill({
    required String label,
    required Color backgroundColor,
    required Color borderColor,
    required Color foregroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: foregroundColor,
        ),
      ),
    );
  }

  Widget _buildEventTimelineList(ThemeData theme, List<BikeEvent> events) {
    return Column(
      children: List.generate(events.length, (index) {
        final event = events[index];
        final isLast = index == events.length - 1;

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 32,
                child: Column(
                  children: [
                    Container(
                      width: 16,
                      height: 16,
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: _getEventColor(event.eventCategory),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: Colors.grey.shade300,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            DateFormat('dd/MM/yyyy').format(event.eventDate),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          if (event.referenceNumber != null &&
                              event.referenceNumber!.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Text(
                                event.referenceNumber!,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        event.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                      if (event.summary != null &&
                          event.summary!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          event.summary!,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade800,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  String _formatSeverityLabel(BikeMemorySeverity? severity) {
    switch (severity) {
      case BikeMemorySeverity.critical:
        return 'Crítico';
      case BikeMemorySeverity.warning:
        return 'Atención';
      case BikeMemorySeverity.info:
        return 'Info';
      case null:
        return 'Dato';
    }
  }

  String _formatInterventionTypeLabel(BikeInterventionType type) {
    switch (type) {
      case BikeInterventionType.replacement:
        return 'Reemplazo';
      case BikeInterventionType.service:
        return 'Servicio';
      case BikeInterventionType.adjustment:
        return 'Ajuste';
      case BikeInterventionType.installation:
        return 'Instalación';
      case BikeInterventionType.removal:
        return 'Retiro';
      case BikeInterventionType.inspection:
        return 'Inspección';
    }
  }

  String _formatLifecycleStatusLabel(BikeComponentLifecycleStatus status) {
    switch (status) {
      case BikeComponentLifecycleStatus.installed:
        return 'Activo';
      case BikeComponentLifecycleStatus.removed:
        return 'Retirado';
      case BikeComponentLifecycleStatus.superseded:
        return 'Reemplazado';
    }
  }

  String _formatComponentSlotLabel(String? slotKey) {
    if (slotKey == null || slotKey.isEmpty) return 'Sistema';
    const labels = {
      'chain': 'Cadena',
      'cassette': 'Cassette',
      'chainring': 'Plato',
      'derailleur_hanger': 'Patilla',
      'front_rotor': 'Rotor delantero',
      'rear_rotor': 'Rotor trasero',
      'rotor': 'Rotor',
      'front_pads': 'Pastillas delanteras',
      'rear_pads': 'Pastillas traseras',
      'pads': 'Pastillas',
      'brake_pad': 'Pastillas',
      'front_tire': 'Neumático delantero',
      'rear_tire': 'Neumático trasero',
      'tire': 'Neumático',
    };

    final mapped = labels[slotKey];
    if (mapped != null) return mapped;

    return slotKey
        .split('_')
        .where((segment) => segment.isNotEmpty)
        .map((segment) =>
            '${segment[0].toUpperCase()}${segment.substring(1).toLowerCase()}')
        .join(' ');
  }

  IconData _systemIconFor(String systemKey) {
    switch (systemKey) {
      case 'front_brake':
      case 'rear_brake':
      case 'brakes':
        return Icons.album_outlined;
      case 'drivetrain':
        return Icons.settings_outlined;
      case 'bottom_bracket':
        return Icons.hub_outlined;
      case 'front_wheel':
      case 'rear_wheel':
      case 'wheels':
        return Icons.trip_origin;
      default:
        return Icons.tune;
    }
  }

  Color _getSystemStatusColor(BikeSystemOverallStatus status) {
    switch (status) {
      case BikeSystemOverallStatus.ok:
        return Colors.teal.shade700;
      case BikeSystemOverallStatus.attention:
        return Colors.orange.shade700;
      case BikeSystemOverallStatus.critical:
        return Colors.red.shade700;
      case BikeSystemOverallStatus.unknown:
        return Colors.grey.shade600;
    }
  }

  Color _getSeverityColor(BikeMemorySeverity? severity) {
    switch (severity) {
      case BikeMemorySeverity.critical:
        return Colors.red.shade700;
      case BikeMemorySeverity.warning:
        return Colors.orange.shade700;
      case BikeMemorySeverity.info:
        return Colors.blue.shade700;
      case null:
        return Colors.blueGrey.shade700;
    }
  }

  Color _getEventColor(BikeEventCategory category) {
    switch (category) {
      case BikeEventCategory.state:
        return Colors.blue.shade600;
      case BikeEventCategory.visit:
        return Colors.green.shade600;
      case BikeEventCategory.incident:
        return Colors.red.shade600;
      case BikeEventCategory.component:
        return Colors.orange.shade600;
      case BikeEventCategory.evidence:
        return Colors.purple.shade600;
    }
  }

  Widget _buildProSection({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required Color borderColor,
    required List<String> items,
    bool isGrid = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 20, color: iconColor),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ]),
            child: isGrid
                ? Wrap(
                    spacing: 24,
                    runSpacing: 16,
                    children: items.map((line) {
                      final parts = line.split(':');
                      final key = parts.first;
                      final val = parts.length > 1
                          ? parts.sublist(1).join(':').trim()
                          : '';
                      return SizedBox(
                        width: 250,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              key.toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade500,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              val.isNotEmpty ? val : line,
                              style: const TextStyle(
                                fontSize: 15,
                                color: Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: items
                        .map((line) => Padding(
                              padding: const EdgeInsets.only(bottom: 12.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        top: 6.0, right: 12.0),
                                    child: Icon(Icons.check_rounded,
                                        size: 14, color: iconColor),
                                  ),
                                  Expanded(
                                    child: Text(
                                      line,
                                      style: TextStyle(
                                        fontSize: 15,
                                        color: Colors.grey.shade800,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
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

class _DiagnosticPopupCard extends StatelessWidget {
  final _BikeDiagnosisSystemView system;
  final Color color;
  final BikeSystemControllerOverlayLayout layout;

  const _DiagnosticPopupCard({
    required this.system,
    required this.color,
    required this.layout,
  });

  @override
  Widget build(BuildContext context) {
    const cardWidth = 270.0;
    const cardHeight = 220.0;

    final pinX =
        layout.imageOffsetX + layout.placement.position.dx * layout.imageSize;
    final pinY =
        layout.imageOffsetY + layout.placement.position.dy * layout.imageSize;

    double left =
        layout.placement.labelRight ? pinX + 32 : pinX - cardWidth - 32;
    double top = pinY - 60;

    left = left.clamp(8.0, layout.constraints.maxWidth - cardWidth - 8);
    top = top.clamp(8.0, layout.constraints.maxHeight - cardHeight - 8);

    final measurements = system.measurementSeries.take(2).toList();

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: cardWidth,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: color.withValues(alpha: 0.25),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.10),
                blurRadius: 24,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    system.displayName.toUpperCase(),
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: color.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      system.overallStatus.displayName,
                      style: TextStyle(
                        color: color,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                system.subheadline,
                style: const TextStyle(
                  color: Color(0xFF1E293B),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (system.primaryNarrative != null &&
                  system.primaryNarrative!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  system.primaryNarrative!,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 10.5,
                    height: 1.45,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (measurements.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(height: 1, color: const Color(0xFFE2E8F0)),
                const SizedBox(height: 10),
                ...measurements.map(
                  (measurement) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            measurement.title,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 10,
                            ),
                          ),
                        ),
                        Text(
                          measurement.latestValueLabel,
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (system.contextEntries.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Última: ${system.contextEntries.first.jobId ?? '—'}',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 10,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
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
