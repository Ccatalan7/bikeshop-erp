import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';

import '../models/bikeshop_models.dart';
import '../services/bikeshop_service.dart';

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
  String? _hoveredDiagnosisSystemKey;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _historyFuture = _loadBikeHistoryData(widget.snapshot.bike.id);
  }

  @override
  void didUpdateWidget(covariant BikeRecordPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot.bike.id != widget.snapshot.bike.id) {
      _historyFuture = _loadBikeHistoryData(widget.snapshot.bike.id);
      _selectedDiagnosisSystemKey = null;
      _hoveredDiagnosisSystemKey = null;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<_BikeRecordHistoryData> _loadBikeHistoryData(String? bikeId) async {
    if (bikeId == null || bikeId.isEmpty) {
      return const _BikeRecordHistoryData.empty();
    }

    final bikeshopService = context.read<BikeshopService>();
    final results = await Future.wait<Object?>([
      bikeshopService.getBikeEvents(bikeId),
      bikeshopService.getBikeObservations(bikeId),
      bikeshopService.getBikeSystemStates(bikeId),
    ]);

    return _BikeRecordHistoryData.fromRaw(
      events: (results[0] as List<BikeEvent>?) ?? const [],
      observations: (results[1] as List<BikeObservation>?) ?? const [],
      systemStates: (results[2] as List<BikeSystemState>?) ?? const [],
    );
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
    final bike = widget.snapshot.bike;

    // We generate a beautiful dynamic color profile based on the snapshot completion status
    final isComplete = widget.snapshot.isProfileComplete;
    final isStructured = widget.snapshot.hasStructuredProfile;

    final Color statusColor = isComplete
        ? Colors.teal
        : (isStructured ? Colors.blue.shade600 : Colors.amber.shade700);

    return Container(
      color: Colors.grey.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // PRO HEADER (Cover + Avatar + Main actions)
          _buildCoverAndIdentity(theme, statusColor, bike),

          // TAB BAR
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: theme.primaryColor,
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: theme.primaryColor,
              indicatorWeight: 3,
              labelStyle:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              tabs: const [
                Tab(text: 'General y Notas'),
                Tab(text: 'Ficha Técnica'),
                Tab(text: 'Historial'),
              ],
            ),
          ),

          const Divider(height: 1, thickness: 1),

          // CONTENT
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildGeneralTab(theme),
                _buildTechnicalSpecsTab(theme),
                _buildTimelineTab(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoverAndIdentity(ThemeData theme, Color statusColor, Bike bike) {
    // Determine the main bike image
    String? mainImageUrl;
    String? coverImageUrl;

    if (bike.imageUrl != null && bike.imageUrl!.isNotEmpty) {
      mainImageUrl = bike.imageUrl;
    } else if (bike.imageUrls.isNotEmpty) {
      mainImageUrl = bike.imageUrls.first;
    }

    if (bike.imageUrls.length > 1) {
      coverImageUrl = bike.imageUrls.last;
    } else {
      coverImageUrl = mainImageUrl;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 1. Cover Photo / Pattern (Adventurous Look)
        Container(
          height: 180,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF263238), // Dark sleek color
            image: coverImageUrl != null
                ? DecorationImage(
                    image: CachedNetworkImageProvider(coverImageUrl),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                      Colors.black.withOpacity(0.4),
                      BlendMode.darken,
                    ),
                  )
                : null,
          ),
          child: coverImageUrl == null
              ? Opacity(
                  opacity: 0.1,
                  child: Image.network(
                    'https://images.unsplash.com/photo-1517649763962-0c623066013b?q=80&w=2000&auto=format&fit=crop',
                    fit: BoxFit.cover,
                  ),
                )
              : null,
        ),

        // Action Buttons at the very top (Close / Edit / New)
        Positioned(
          top: 12,
          left: 16,
          right: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              FilledButton.icon(
                onPressed: widget.onClose,
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Volver a bicicletas'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.92),
                  foregroundColor: Colors.black87,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: widget.onEdit,
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Editar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.9),
                      foregroundColor: Colors.black87,
                      elevation: 0,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: widget.onNewJob,
                    icon: const Icon(Icons.build, size: 16),
                    label: const Text('Nuevo Trabajo'),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Bottom section with Bike Image and Core Identity
        Container(
          margin: const EdgeInsets.only(top: 140),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Circular avatar offset upwards
              Transform.translate(
                offset: const Offset(0, -40),
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                    border: Border.all(color: Colors.white, width: 4),
                  ),
                  child: ClipOval(
                    child: mainImageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: mainImageUrl,
                            fit: BoxFit.cover,
                          )
                        : Icon(
                            Icons.pedal_bike,
                            size: 60,
                            color: Colors.grey.shade300,
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 20),

              // Identity Specs
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tag for completion state
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: statusColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.snapshot.isProfileComplete
                                ? Icons.check_circle
                                : Icons.pending_actions,
                            size: 14,
                            color: statusColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.snapshot.isProfileComplete
                                ? 'Perfil Completo'
                                : 'Perfil Incompleto',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: statusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Brand & Model explicit split
                    Row(
                      children: [
                        Text(
                          (bike.brand ?? 'Sin Marca').toUpperCase(),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          (bike.year != null) ? '(${bike.year})' : '',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      bike.model ?? 'Modelo Desconocido',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.person_outline,
                            size: 16, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                          'Propietario: ',
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 14),
                        ),
                        Text(
                          widget.ownerName,
                          style: const TextStyle(
                            color: Colors.black87,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
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
    if (widget.snapshot.technicalLines.isEmpty) {
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: _buildProSection(
        title: 'Especificaciones Técnicas',
        icon: Icons.settings_suggest_outlined,
        iconColor: Colors.purple.shade700,
        bgColor: Colors.white,
        borderColor: Colors.grey.shade200,
        items: widget.snapshot.technicalLines,
        isGrid: true,
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
            if (history.hasDiagnosisMemory)
              _buildDiagnosisWorkbench(theme, history)
            else
              _buildLegacyEventsSection(
                theme,
                history.events,
                expanded: true,
              ),
            if (history.hasDiagnosisMemory && history.events.isNotEmpty) ...[
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
    final wideLayout = MediaQuery.of(context).size.width > 1280;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mapa de diagnóstico',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Navega por los sistemas desde el esquema de la bici y revisa mediciones, diagnósticos y trabajos relacionados sin mezclar todo en una sola lista.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.grey.shade600,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 18),
        if (wideLayout)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child:
                    _buildSystemExplorerCard(theme, history, activeSystemKey),
              ),
              const SizedBox(width: 18),
              Expanded(
                flex: 7,
                child: _buildSystemDetailCard(theme, history, activeSystem),
              ),
            ],
          )
        else ...[
          _buildSystemExplorerCard(theme, history, activeSystemKey),
          const SizedBox(height: 18),
          _buildSystemDetailCard(theme, history, activeSystem),
        ],
      ],
    );
  }

  Widget _buildSystemExplorerCard(
    ThemeData theme,
    _BikeRecordHistoryData history,
    String? activeSystemKey,
  ) {
    final latestDate = history.latestDiagnosisDate;
    final criticalCount = history.diagnosisSystems
        .where((system) =>
            system.overallStatus == BikeSystemOverallStatus.critical)
        .length;
    final attentionCount = history.diagnosisSystems
        .where((system) =>
            system.overallStatus == BikeSystemOverallStatus.attention)
        .length;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
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
                      'Esquema interactivo',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      latestDate != null
                          ? 'Última lectura: ${DateFormat('dd/MM/yyyy').format(latestDate)}'
                          : 'Sin fecha de lectura registrada.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              if (history.latestDiagnosisJobNumber != null)
                _buildReferencePill(
                  label: history.latestDiagnosisJobNumber!,
                  backgroundColor: const Color(0xFFEAF2FF),
                  borderColor: const Color(0xFFBED2FF),
                  foregroundColor: const Color(0xFF2457C5),
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
                backgroundColor: const Color(0xFFF3F6FA),
                borderColor: const Color(0xFFE1E7EF),
                foregroundColor: Colors.blueGrey.shade700,
              ),
              if (criticalCount > 0)
                _buildReferencePill(
                  label:
                      '$criticalCount crítico${criticalCount == 1 ? '' : 's'}',
                  backgroundColor: const Color(0xFFFFF0F0),
                  borderColor: const Color(0xFFFFD2D2),
                  foregroundColor: Colors.red.shade700,
                ),
              if (attentionCount > 0)
                _buildReferencePill(
                  label: '$attentionCount en atención',
                  backgroundColor: const Color(0xFFFFF7ED),
                  borderColor: const Color(0xFFFED7AA),
                  foregroundColor: Colors.orange.shade700,
                ),
            ],
          ),
          const SizedBox(height: 18),
          _buildBikeSchemaNavigator(theme, history, activeSystemKey),
          if (history.overviewNarrativeObservation?.summary != null &&
              history.overviewNarrativeObservation!.summary!
                  .trim()
                  .isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              'Narrativa original de la orden',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade900,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFE6ECF3)),
              ),
              child: Text(
                history.overviewNarrativeObservation!.summary!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade700,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBikeSchemaNavigator(
    ThemeData theme,
    _BikeRecordHistoryData history,
    String? activeSystemKey,
  ) {
    final highlightedSystemKey = _hoveredDiagnosisSystemKey ?? activeSystemKey;

    return Container(
      height: 300,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF8FBFF), Color(0xFFF3F6FB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE0E7F1)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _BikeSchemaPainter(
                    lineColor: const Color(0xFFB8C5D6),
                    baseWheelColor: const Color(0xFFD8E0EA),
                    highlightSystemKey: highlightedSystemKey,
                    highlightColor: const Color(0xFF1F6FEB),
                  ),
                ),
              ),
              ...history.diagnosisSystems.map(
                (system) => _buildSchemaNode(
                  theme,
                  system,
                  constraints,
                  activeSystemKey == system.systemKey,
                  highlightedSystemKey == system.systemKey,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSchemaNode(
    ThemeData theme,
    _BikeDiagnosisSystemView system,
    BoxConstraints constraints,
    bool isSelected,
    bool isHighlighted,
  ) {
    final placement = _schemaPlacementFor(system.systemKey, constraints);
    final accentColor = _getSystemStatusColor(system.overallStatus);

    return Positioned(
      left: placement.dx,
      top: placement.dy,
      child: MouseRegion(
        onEnter: (_) {
          setState(() {
            _hoveredDiagnosisSystemKey = system.systemKey;
          });
        },
        onExit: (_) {
          if (_hoveredDiagnosisSystemKey == system.systemKey) {
            setState(() {
              _hoveredDiagnosisSystemKey = null;
            });
          }
        },
        child: GestureDetector(
          onTap: () {
            setState(() {
              _selectedDiagnosisSystemKey = system.systemKey;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: placement.width,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected || isHighlighted
                  ? accentColor.withOpacity(0.12)
                  : Colors.white.withOpacity(0.92),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected || isHighlighted
                    ? accentColor.withOpacity(0.7)
                    : const Color(0xFFD6DEE8),
                width: isSelected ? 1.6 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isSelected ? 0.08 : 0.04),
                  blurRadius: isSelected ? 16 : 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        system.displayName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    Icon(
                      _systemIconFor(system.systemKey),
                      size: 16,
                      color: accentColor,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _buildReferencePill(
                      label: system.overallStatus.displayName,
                      backgroundColor: accentColor.withOpacity(0.10),
                      borderColor: accentColor.withOpacity(0.22),
                      foregroundColor: accentColor,
                    ),
                    if (system.latestMeasureLabel != null) ...[
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          system.latestMeasureLabel!,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSystemDetailCard(
    ThemeData theme,
    _BikeRecordHistoryData history,
    _BikeDiagnosisSystemView? system,
  ) {
    if (system == null) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selecciona un sistema',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Haz clic sobre un sistema del esquema para ver diagnósticos, mediciones y trabajos relacionados.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade600,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 20,
            offset: const Offset(0, 8),
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
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.10),
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
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        _buildReferencePill(
                          label: system.overallStatus.displayName,
                          backgroundColor: accentColor.withOpacity(0.10),
                          borderColor: accentColor.withOpacity(0.22),
                          foregroundColor: accentColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      system.subheadline,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.grey.shade600,
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
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE6ECF3)),
              ),
              child: Text(
                system.primaryNarrative!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade800,
                  height: 1.5,
                ),
              ),
            ),
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
            _buildMiniSectionLabel(
                theme, 'Diagnósticos y trabajos relacionados'),
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
        color: Colors.grey.shade900,
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3E8EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      series.title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
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
                backgroundColor: accentColor.withOpacity(0.10),
                borderColor: accentColor.withOpacity(0.18),
                foregroundColor: accentColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 46,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final points = series.points;
                final maxWidth = constraints.maxWidth;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      top: 18,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDCE4ED),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    for (int index = 0; index < points.length; index++)
                      Positioned(
                        left: points.length == 1
                            ? (maxWidth / 2) - 7
                            : (maxWidth - 14) * (index / (points.length - 1)),
                        top: 11,
                        child: Tooltip(
                          message:
                              '${DateFormat('dd/MM/yyyy').format(points[index].observedAt)} • ${_formatObservationValue(points[index].valueNumeric)} ${points[index].unit ?? ''} • ${points[index].payload['job_number'] ?? 'Sin orden'}',
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: index == points.length - 1
                                  ? accentColor
                                  : Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: accentColor,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          Row(
            children: [
              Text(
                series.firstDateLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade500,
                ),
              ),
              const Spacer(),
              Text(
                series.lastDateLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade500,
                ),
              ),
            ],
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE3E8EF)),
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
                    color: Colors.black87,
                  ),
                ),
              ),
              if (jobNumber != null && jobNumber.isNotEmpty)
                _buildReferencePill(
                  label: jobNumber,
                  backgroundColor: const Color(0xFFF3F6FA),
                  borderColor: const Color(0xFFE1E7EF),
                  foregroundColor: Colors.blueGrey.shade700,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            observation.summary?.trim().isNotEmpty == true
                ? observation.summary!
                : observation.statusValue ?? 'Sin resumen detallado.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.grey.shade700,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                DateFormat('dd/MM/yyyy').format(observation.observedAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (observation.severity != null) ...[
                const SizedBox(width: 8),
                _buildReferencePill(
                  label: _formatSeverityLabel(observation.severity),
                  backgroundColor: accentColor.withOpacity(0.10),
                  borderColor: accentColor.withOpacity(0.18),
                  foregroundColor: accentColor,
                ),
              ],
            ],
          ),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade200),
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
              color: Colors.black87,
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
                            color: Colors.black.withOpacity(0.1),
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

  String _formatObservationValue(double? value) {
    if (value == null) return 'Sin dato';
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    if (value.abs() >= 10) {
      return value.toStringAsFixed(1);
    }
    return value.toStringAsFixed(2);
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

  IconData _systemIconFor(String systemKey) {
    switch (systemKey) {
      case 'front_brake':
      case 'rear_brake':
      case 'brakes':
        return Icons.album_outlined;
      case 'drivetrain':
        return Icons.settings_outlined;
      case 'front_wheel':
      case 'rear_wheel':
      case 'wheels':
        return Icons.trip_origin;
      default:
        return Icons.tune;
    }
  }

  _SchemaPlacement _schemaPlacementFor(
    String systemKey,
    BoxConstraints constraints,
  ) {
    final width = constraints.maxWidth;
    switch (systemKey) {
      case 'rear_brake':
        return _SchemaPlacement(dx: 14, dy: 18, width: width * 0.36);
      case 'front_brake':
        return _SchemaPlacement(dx: width * 0.58, dy: 18, width: width * 0.34);
      case 'drivetrain':
        return _SchemaPlacement(dx: width * 0.31, dy: 212, width: width * 0.38);
      default:
        return _SchemaPlacement(dx: width * 0.34, dy: 112, width: width * 0.3);
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
                  color: iconColor.withOpacity(0.1),
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
                    color: Colors.black.withOpacity(0.02),
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

class _BikeRecordHistoryData {
  final List<BikeEvent> events;
  final List<BikeObservation> diagnosisObservations;
  final List<BikeSystemState> diagnosisStates;
  final List<_BikeDiagnosisSystemView> diagnosisSystems;
  final BikeObservation? overviewNarrativeObservation;

  const _BikeRecordHistoryData({
    required this.events,
    required this.diagnosisObservations,
    required this.diagnosisStates,
    required this.diagnosisSystems,
    required this.overviewNarrativeObservation,
  });

  const _BikeRecordHistoryData.empty()
      : events = const [],
        diagnosisObservations = const [],
        diagnosisStates = const [],
        diagnosisSystems = const [],
        overviewNarrativeObservation = null;

  factory _BikeRecordHistoryData.fromRaw({
    required List<BikeEvent> events,
    required List<BikeObservation> observations,
    required List<BikeSystemState> systemStates,
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

    final filteredStates = systemStates
        .where(
            (state) => state.payload['source']?.toString() == 'diagnosis_sheet')
        .toList()
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
    };

    final diagnosisSystems = systemKeys.map((systemKey) {
      final matchingState = filteredStates
          .where((state) => state.systemKey == systemKey)
          .toList();
      final matchingObservations = filteredObservations
          .where((observation) => observation.systemKey == systemKey)
          .toList()
        ..sort((a, b) => b.observedAt.compareTo(a.observedAt));

      return _BikeDiagnosisSystemView(
        systemKey: systemKey,
        state: matchingState.isNotEmpty ? matchingState.first : null,
        observations: matchingObservations,
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
      diagnosisSystems: diagnosisSystems,
      overviewNarrativeObservation: overviewNarrativeObservation,
    );
  }

  bool get isEmpty =>
      events.isEmpty &&
      diagnosisObservations.isEmpty &&
      diagnosisStates.isEmpty;

  bool get hasDiagnosisMemory =>
      diagnosisSystems.isNotEmpty || overviewNarrativeObservation != null;

  DateTime? get latestDiagnosisDate {
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

    if (observationDate == null) return stateDate;
    if (stateDate == null) return observationDate;
    return observationDate.isAfter(stateDate) ? observationDate : stateDate;
  }

  String? get latestDiagnosisJobNumber {
    for (final system in diagnosisSystems) {
      if (system.latestJobNumber != null) {
        return system.latestJobNumber;
      }
    }

    for (final observation in diagnosisObservations) {
      final jobNumber = observation.payload['job_number']?.toString();
      if (jobNumber != null && jobNumber.isNotEmpty) {
        return jobNumber;
      }
    }

    for (final state in diagnosisStates) {
      final jobNumber = state.payload['job_number']?.toString();
      if (jobNumber != null && jobNumber.isNotEmpty) {
        return jobNumber;
      }
    }

    return null;
  }

  String? resolveActiveSystemKey(String? preferred) {
    if (preferred != null &&
        diagnosisSystems.any((system) => system.systemKey == preferred)) {
      return preferred;
    }
    return diagnosisSystems.isNotEmpty
        ? diagnosisSystems.first.systemKey
        : null;
  }

  _BikeDiagnosisSystemView? systemFor(String? systemKey) {
    if (systemKey == null) return null;
    for (final system in diagnosisSystems) {
      if (system.systemKey == systemKey) return system;
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

  const _BikeDiagnosisSystemView({
    required this.systemKey,
    required this.state,
    required this.observations,
  });

  String get displayName {
    const labels = {
      'drivetrain': 'Transmisión',
      'front_brake': 'Freno delantero',
      'rear_brake': 'Freno trasero',
      'brakes': 'Frenos',
      'front_wheel': 'Rueda delantera',
      'rear_wheel': 'Rueda trasera',
      'wheels': 'Ruedas',
    };
    return labels[systemKey] ?? systemKey;
  }

  BikeSystemOverallStatus get overallStatus =>
      state?.overallStatus ?? BikeSystemOverallStatus.unknown;

  DateTime? get latestDate {
    final observationDate =
        observations.isNotEmpty ? observations.first.observedAt : null;
    final stateDate = state?.lastReviewedAt;
    if (observationDate == null) return stateDate;
    if (stateDate == null) return observationDate;
    return observationDate.isAfter(stateDate) ? observationDate : stateDate;
  }

  String get subheadline {
    final date = latestDate;
    final dateText = date != null
        ? DateFormat('dd/MM/yyyy').format(date)
        : 'sin fecha registrada';
    final jobNumber = latestJobNumber;
    if (jobNumber != null && jobNumber.isNotEmpty) {
      return 'Último registro $dateText · $jobNumber';
    }
    return 'Último registro $dateText';
  }

  String? get latestJobNumber {
    for (final observation in observations) {
      final jobNumber = observation.payload['job_number']?.toString();
      if (jobNumber != null && jobNumber.isNotEmpty) {
        return jobNumber;
      }
    }
    return state?.payload['job_number']?.toString();
  }

  String? get primaryNarrative {
    for (final observation in assessmentObservations) {
      final summary = observation.summary?.trim();
      if (summary != null && summary.isNotEmpty) {
        return summary;
      }
    }
    final note = state?.statusNote?.trim();
    return (note == null || note.isEmpty) ? null : note;
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

class _SchemaPlacement {
  final double dx;
  final double dy;
  final double width;

  const _SchemaPlacement({
    required this.dx,
    required this.dy,
    required this.width,
  });
}

class _BikeSchemaPainter extends CustomPainter {
  final String? highlightSystemKey;
  final Color highlightColor;
  final Color lineColor;
  final Color baseWheelColor;

  const _BikeSchemaPainter({
    required this.highlightSystemKey,
    required this.highlightColor,
    required this.lineColor,
    required this.baseWheelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rearWheel = Offset(size.width * 0.28, size.height * 0.66);
    final frontWheel = Offset(size.width * 0.72, size.height * 0.66);
    final crank = Offset(size.width * 0.5, size.height * 0.58);
    final seat = Offset(size.width * 0.42, size.height * 0.34);
    final head = Offset(size.width * 0.62, size.height * 0.34);

    final highlightPaint = Paint()
      ..color = highlightColor.withOpacity(0.10)
      ..style = PaintingStyle.fill;

    switch (highlightSystemKey) {
      case 'front_brake':
        canvas.drawCircle(frontWheel, size.width * 0.14, highlightPaint);
        break;
      case 'rear_brake':
        canvas.drawCircle(rearWheel, size.width * 0.14, highlightPaint);
        break;
      case 'drivetrain':
        canvas.drawOval(
          Rect.fromCenter(
            center: crank,
            width: size.width * 0.26,
            height: size.height * 0.18,
          ),
          highlightPaint,
        );
        break;
    }

    final wheelPaint = Paint()
      ..color = baseWheelColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;
    final accentPaint = Paint()
      ..color = highlightColor.withOpacity(0.75)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.5;

    canvas.drawCircle(rearWheel, size.width * 0.12, wheelPaint);
    canvas.drawCircle(frontWheel, size.width * 0.12, wheelPaint);

    canvas.drawLine(rearWheel, crank, linePaint);
    canvas.drawLine(seat, crank, linePaint);
    canvas.drawLine(seat, head, linePaint);
    canvas.drawLine(crank, head, linePaint);
    canvas.drawLine(head, frontWheel, linePaint);
    canvas.drawLine(
        seat, Offset(seat.dx, seat.dy - size.height * 0.07), linePaint);
    canvas.drawLine(
        head,
        Offset(head.dx + size.width * 0.05, head.dy - size.height * 0.04),
        linePaint);

    if (highlightSystemKey == 'drivetrain') {
      canvas.drawCircle(crank, size.width * 0.045, accentPaint);
    }
    if (highlightSystemKey == 'front_brake') {
      canvas.drawLine(
        Offset(frontWheel.dx - size.width * 0.02,
            frontWheel.dy - size.height * 0.11),
        Offset(frontWheel.dx + size.width * 0.03,
            frontWheel.dy - size.height * 0.02),
        accentPaint,
      );
    }
    if (highlightSystemKey == 'rear_brake') {
      canvas.drawLine(
        Offset(rearWheel.dx + size.width * 0.02,
            rearWheel.dy - size.height * 0.11),
        Offset(rearWheel.dx - size.width * 0.03,
            rearWheel.dy - size.height * 0.02),
        accentPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BikeSchemaPainter oldDelegate) {
    return oldDelegate.highlightSystemKey != highlightSystemKey ||
        oldDelegate.highlightColor != highlightColor ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.baseWheelColor != baseWheelColor;
  }
}
