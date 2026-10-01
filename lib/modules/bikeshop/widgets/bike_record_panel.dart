import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/vb_button.dart';
import '../../../shared/themes/vinabike_theme_roles.dart';
import '../config/bottom_bracket_canonical_data.dart';
import '../config/brake_canonical_data.dart';
import '../config/wheel_canonical_data.dart';
import '../models/bikeshop_models.dart';
import '../models/bike_fact_origin.dart';
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
    _reloadHistory();
  }

  void _handleTabChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant BikeRecordPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.snapshot, widget.snapshot)) {
      _reloadHistory();
    }
    if (oldWidget.snapshot.bike.id != widget.snapshot.bike.id) {
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
    } catch (error) {
      debugPrint('Bike record history load failed: $error');
      rethrow;
    }
  }

  void _reloadHistory() {
    _historyFuture = _loadBikeHistoryData(widget.snapshot.bike.id);
    // The history tab can be offscreen when the request finishes. Observe
    // errors now; FutureBuilder still receives them when that tab is opened.
    _historyFuture.ignore();
  }

  Widget _buildHistoryLoadFailure(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (widget.isLoading) {
      return ColoredBox(
        color: theme.colorScheme.surface,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    // We generate a beautiful dynamic color profile based on the snapshot completion status
    final isComplete = widget.snapshot.isProfileComplete;
    final isStructured = widget.snapshot.hasStructuredProfile;

    final roles = VinabikeThemeRoles.of(context);
    final Color statusColor = isComplete
        ? roles.success.accent
        : (isStructured ? roles.info.accent : roles.warning.accent);

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
                _buildTechnicalSpecsTab(theme, showInlineSystemMap: mobile),
                _buildTimelineTab(theme, showInlineSystemMap: mobile),
              ],
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // The companion map needs enough room beside the reading pane. Narrow
        // hosts retain the same map within the technical/history scroll.
        final showDesktopPreviewPane = constraints.maxWidth >= 1100;

        if (showDesktopPreviewPane) {
          return Container(
            color: theme.colorScheme.surfaceContainerLowest,
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
          color: theme.colorScheme.surfaceContainerLowest,
          child: Column(
            children: [
              _buildCompactRecordHeader(theme, statusColor: statusColor),
              Expanded(child: buildContentShell(mobile: true)),
            ],
          ),
        );
      },
    );
  }

  int get _activeTabIndex => _tabController.index;

  Widget _buildCompactRecordHeader(ThemeData theme,
      {required Color statusColor}) {
    final bike = widget.snapshot.bike;
    final identity = [bike.brand, bike.model]
        .whereType<String>()
        .where((part) => part.trim().isNotEmpty)
        .join(' ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border:
            Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              VbButton(
                label: 'Volver a bicicletas',
                variant: VbButtonVariant.text,
                icon: Icons.arrow_back,
                onPressed: widget.onClose,
              ),
              Text(
                widget.snapshot.isProfileComplete
                    ? 'Perfil completo'
                    : 'Perfil incompleto',
                style:
                    theme.textTheme.labelMedium?.copyWith(color: statusColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(identity.isEmpty ? 'Bicicleta' : identity,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(widget.ownerName,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              VbButton(
                  label: 'Editar bicicleta',
                  variant: VbButtonVariant.secondary,
                  icon: Icons.edit_outlined,
                  onPressed: widget.onEdit),
              VbButton(
                  label: 'Nuevo trabajo',
                  icon: Icons.build_outlined,
                  onPressed: widget.onNewJob),
            ],
          ),
        ],
      ),
    );
  }

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
        color: theme.colorScheme.surface,
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
            'Elige un sistema para consultar los datos conocidos de esta bicicleta.';
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
            SizedBox(
              width: double.infinity,
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  VbButton(
                    onPressed: widget.onClose,
                    icon: Icons.arrow_back,
                    label: compact ? 'Volver' : 'Volver a bicicletas',
                    variant: VbButtonVariant.secondary,
                  ),
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
            ),
            SizedBox(height: compact ? 14 : 18),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            SizedBox(height: compact ? 14 : 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: theme.colorScheme.outlineVariant),
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
                            color: theme.colorScheme.onSurfaceVariant,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          bike.model ?? 'Modelo desconocido',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        if (bike.year != null || identityLine.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            bike.year != null
                                ? '${bike.year} · Propietario: ${widget.ownerName}'
                                : 'Propietario: ${widget.ownerName}',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
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
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: theme.colorScheme.outlineVariant),
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
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: theme.colorScheme.outlineVariant),
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
            'Ficha técnica por sistema',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'El mismo mapa compartido del taller ahora sostiene la lectura técnica del registro.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Expanded(
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
              idleHintText: 'Elige un sistema para consultar su ficha.',
              selectedHintText:
                  'Haz clic en otro sistema para cambiar el panel técnico.',
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
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) return _buildHistoryLoadFailure(theme);
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
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: theme.colorScheme.outlineVariant),
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
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Observaciones, estados y trabajos ejecutados alrededor del mismo modelo técnico.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              Expanded(
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
    final roles = VinabikeThemeRoles.of(context);

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
              bgColor: theme.colorScheme.surface,
              borderColor: theme.colorScheme.outlineVariant,
              items: baseData,
              isGrid: true,
            ),
          if (widget.snapshot.warnings.isNotEmpty)
            _buildProSection(
              title: 'Advertencias / Notas Críticas',
              icon: Icons.warning_amber_rounded,
              iconColor: roles.warning.accent,
              bgColor: roles.warning.container,
              borderColor: roles.warning.border,
              items: widget.snapshot.warnings,
            ),
          if (widget.snapshot.notesLines.isNotEmpty)
            _buildProSection(
              title: 'Notas Generales',
              icon: Icons.speaker_notes_outlined,
              iconColor: Colors.blueGrey.shade700,
              bgColor: theme.colorScheme.surface,
              borderColor: theme.colorScheme.outlineVariant,
              items: widget.snapshot.notesLines,
            ),
          if (widget.snapshot.intakeLines.isNotEmpty)
            _buildProSection(
              title: 'Perfil de Recepción',
              icon: Icons.assignment_turned_in_outlined,
              iconColor: Colors.blue.shade700,
              bgColor: theme.colorScheme.surface,
              borderColor: theme.colorScheme.outlineVariant,
              items: widget.snapshot.intakeLines,
            ),
        ],
      ),
    );
  }

  Widget _buildTechnicalSpecsTab(ThemeData theme,
      {bool showInlineSystemMap = false}) {
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
              style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant, fontSize: 16),
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
          if (showInlineSystemMap) ...[
            SizedBox(
              height: 260,
              child: BikeSystemController(
                bike: widget.snapshot.bike,
                profile: widget.snapshot.profile,
                entries: _buildTechnicalControllerEntries(),
                selectedSystemKey: activeSystemKey,
                onSystemSelected: (key) =>
                    setState(() => _selectedTechnicalSystemKey = key),
                onClearSelection: () =>
                    setState(() => _selectedTechnicalSystemKey = null),
                idleHintText: 'Elige un sistema para ver su ficha.',
                selectedHintText: 'Elige otro sistema para cambiar el detalle.',
              ),
            ),
            const SizedBox(height: 18),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: theme.colorScheme.outlineVariant),
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
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Consulta los datos confirmados y lo que falta registrar en el sistema elegido.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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
              bgColor: theme.colorScheme.surface,
              borderColor: theme.colorScheme.outlineVariant,
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
          spec: bikeSystemControllerSpecFor(systemKey)!,
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

  Widget _buildTechnicalSystemCard(
    ThemeData theme,
    _BikeRecordTechnicalPanelData panel,
  ) {
    final status = _technicalSystemStatus(panel.spec.systemKey);
    final statusColor = _getSystemStatusColor(status);
    final roles = VinabikeThemeRoles.of(context);

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: theme.colorScheme.outlineVariant),
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
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      panel.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
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
                    BikeSystemOverallStatus.unknown => 'Sin datos',
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
                  color: theme.colorScheme.onSurface,
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
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            ...panel.facts.map((fact) {
              final origin =
                  bikeFactOriginCaption(fact.source, confirmed: fact.confirmed);
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              fact.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (fact.confirmed)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: roles.success.container,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'Confirmado',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: roles.success.onContainer,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        fact.value,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      if (origin != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          origin,
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
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
    final color =
        accent ? theme.primaryColor : theme.colorScheme.onSurfaceVariant;
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

  Widget _buildTimelineTab(ThemeData theme,
      {bool showInlineSystemMap = false}) {
    return FutureBuilder<_BikeRecordHistoryData>(
      future: _historyFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _buildHistoryLoadFailure(theme);
        }

        final history = snapshot.data ?? const _BikeRecordHistoryData.empty();

        if (history.isEmpty) {
          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history_toggle_off,
                      size: 48, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text(
                    'Aún no existen eventos en el historial.',
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'El historial capturará automáticamente las actualizaciones del perfil y los trabajos de taller.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          children: [
            if (showInlineSystemMap && history.hasStructuredWorkbench) ...[
              SizedBox(
                height: 260,
                child: BikeSystemController(
                  bike: widget.snapshot.bike,
                  profile: widget.snapshot.profile,
                  entries: _buildHistoryControllerEntries(history),
                  selectedSystemKey: history
                      .resolveActiveSystemKey(_selectedDiagnosisSystemKey),
                  onSystemSelected: (key) =>
                      setState(() => _selectedDiagnosisSystemKey = key),
                  onClearSelection: () =>
                      setState(() => _selectedDiagnosisSystemKey = null),
                  idleHintText: 'Elige un sistema para ver su historial.',
                  selectedHintText:
                      'Elige otro sistema para cambiar el historial.',
                ),
              ),
              const SizedBox(height: 18),
            ],
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
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: theme.colorScheme.outlineVariant),
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
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Elige un sistema para revisar su diagnóstico, trabajos y componentes instalados.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
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
    return _getSystemStatusColor(status);
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
    final roles = theme.extension<VinabikeThemeRoles>()!;
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
                  backgroundColor: roles.success.container,
                  borderColor: roles.success.border,
                  foregroundColor: roles.success.onContainer,
                ),
              if (history.installedLifecycleCount > 0)
                _buildReferencePill(
                  label:
                      '${history.installedLifecycleCount} componente${history.installedLifecycleCount == 1 ? '' : 's'} activo${history.installedLifecycleCount == 1 ? '' : 's'}',
                  backgroundColor: roles.info.container,
                  borderColor: roles.info.border,
                  foregroundColor: roles.info.onContainer,
                ),
              if (criticalCount > 0)
                _buildReferencePill(
                  label:
                      '$criticalCount crítico${criticalCount == 1 ? '' : 's'}',
                  backgroundColor: roles.danger.container,
                  borderColor: roles.danger.border,
                  foregroundColor: roles.danger.onContainer,
                ),
              if (attentionCount > 0)
                _buildReferencePill(
                  label: '$attentionCount en atención',
                  backgroundColor: roles.warning.container,
                  borderColor: roles.warning.border,
                  foregroundColor: roles.warning.onContainer,
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
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
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
                          color: theme.colorScheme.onSurface,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        series.subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
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
    // Roles del tema, no tonos fijos: `tealAccent.shade100` como texto no se
    // leía sobre la tarjeta clara del historial (Android claro, 2026-09-30).
    final roles = theme.extension<VinabikeThemeRoles>()!;
    final tone =
        intervention.interventionType == BikeInterventionType.replacement
            ? roles.success
            : roles.info;
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
                backgroundColor: tone.container,
                borderColor: tone.border,
                foregroundColor: tone.onContainer,
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
    final roles = theme.extension<VinabikeThemeRoles>()!;
    final tone = lifecycle.status == BikeComponentLifecycleStatus.installed
        ? roles.success
        : roles.warning;
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
                backgroundColor: tone.container,
                borderColor: tone.border,
                foregroundColor: tone.onContainer,
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
            expanded ? 'Historial de la bicicleta' : 'Eventos anteriores',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
            ),
          ),
          subtitle: Text(
            expanded
                ? 'Eventos de perfil, ingresos, entregas y otros hitos registrados previamente.'
                : 'Cambios de la ficha y visitas al taller.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: _buildReferencePill(
            label: '${events.length}',
            backgroundColor: theme.colorScheme.surfaceContainerLow,
            borderColor: theme.colorScheme.outlineVariant,
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
                        border: Border.all(
                            color: theme.colorScheme.surface, width: 2),
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
                              color: theme.colorScheme.onSurfaceVariant,
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
                                color: theme.colorScheme.outlineVariant,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Text(
                                event.referenceNumber!,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        event.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      if (event.summary != null &&
                          event.summary!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          event.summary!,
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.colorScheme.onSurface,
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
      'derailleur_hanger': 'Postiza de cambio',
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
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.of(context);
    switch (status) {
      case BikeSystemOverallStatus.ok:
        return roles.success.accent;
      case BikeSystemOverallStatus.attention:
        return roles.warning.accent;
      case BikeSystemOverallStatus.critical:
        return roles.danger.accent;
      case BikeSystemOverallStatus.unknown:
        return theme.colorScheme.onSurfaceVariant;
    }
  }

  Color _getSeverityColor(BikeMemorySeverity? severity) {
    final roles = VinabikeThemeRoles.of(context);
    switch (severity) {
      case BikeMemorySeverity.critical:
        return roles.danger.accent;
      case BikeMemorySeverity.warning:
        return roles.warning.accent;
      case BikeMemorySeverity.info:
        return roles.info.accent;
      case null:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  Color _getEventColor(BikeEventCategory category) {
    final roles = VinabikeThemeRoles.of(context);
    switch (category) {
      case BikeEventCategory.state:
        return roles.info.accent;
      case BikeEventCategory.visit:
        return roles.success.accent;
      case BikeEventCategory.incident:
        return roles.danger.accent;
      case BikeEventCategory.component:
        return roles.warning.accent;
      case BikeEventCategory.evidence:
        return roles.info.accent;
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
    final theme = Theme.of(context);
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
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
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
                                color: theme.colorScheme.onSurfaceVariant,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              val.isNotEmpty ? val : line,
                              style: TextStyle(
                                fontSize: 15,
                                color: theme.colorScheme.onSurface,
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
                                        color: theme.colorScheme.onSurface,
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
    final theme = Theme.of(context);
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
            color: theme.colorScheme.surface,
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
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (system.primaryNarrative != null &&
                  system.primaryNarrative!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  system.primaryNarrative!,
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10.5,
                    height: 1.45,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (measurements.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(height: 1, color: theme.colorScheme.outlineVariant),
                const SizedBox(height: 10),
                ...measurements.map(
                  (measurement) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            measurement.title,
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
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
