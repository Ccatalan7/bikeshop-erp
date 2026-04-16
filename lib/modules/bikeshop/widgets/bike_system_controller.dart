import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/bikeshop_models.dart';
import 'bike_diagram_illustration.dart';

class BikeSystemControllerSpec {
  final String systemKey;
  final String label;
  final IconData icon;
  final String diagnosisSubtitle;
  final bool supportsStructuredDiagnosis;

  const BikeSystemControllerSpec({
    required this.systemKey,
    required this.label,
    required this.icon,
    required this.diagnosisSubtitle,
    this.supportsStructuredDiagnosis = false,
  });
}

const List<BikeSystemControllerSpec> kBikeSystemControllerSpecs = [
  BikeSystemControllerSpec(
    systemKey: 'cockpit',
    label: 'Cockpit',
    icon: Icons.tune,
    diagnosisSubtitle: 'Mandos, manillar y puesto de conduccion.',
  ),
  BikeSystemControllerSpec(
    systemKey: 'suspension',
    label: 'Suspensión',
    icon: Icons.waves_outlined,
    diagnosisSubtitle: 'Horquilla, amortiguacion y soporte del sistema.',
  ),
  BikeSystemControllerSpec(
    systemKey: 'front_brake',
    label: 'Freno delantero',
    icon: Icons.radio_button_checked,
    diagnosisSubtitle:
        'Pastillas o zapatas, actuacion y soporte de frenado delantero.',
    supportsStructuredDiagnosis: true,
  ),
  BikeSystemControllerSpec(
    systemKey: 'wheels',
    label: 'Ruedas',
    icon: Icons.trip_origin,
    diagnosisSubtitle: 'Llantas, neumaticos y rodado.',
  ),
  BikeSystemControllerSpec(
    systemKey: 'drivetrain',
    label: 'Transmisión',
    icon: Icons.settings_input_component_outlined,
    diagnosisSubtitle: 'Cadena, cassette y tren motriz.',
    supportsStructuredDiagnosis: true,
  ),
  BikeSystemControllerSpec(
    systemKey: 'rear_brake',
    label: 'Freno trasero',
    icon: Icons.adjust,
    diagnosisSubtitle:
        'Pastillas o zapatas, actuacion y soporte de frenado trasero.',
    supportsStructuredDiagnosis: true,
  ),
];

BikeSystemControllerSpec? bikeSystemControllerSpecFor(String? systemKey) {
  if (systemKey == null || systemKey.isEmpty) {
    return null;
  }
  for (final spec in kBikeSystemControllerSpecs) {
    if (spec.systemKey == systemKey) {
      return spec;
    }
  }
  return null;
}

String bikeSystemControllerLabelFor(String systemKey) {
  const fallbackLabels = {
    'brakes': 'Frenos',
    'front_wheel': 'Rueda delantera',
    'rear_wheel': 'Rueda trasera',
    'general': 'General',
  };
  return bikeSystemControllerSpecFor(systemKey)?.label ??
      fallbackLabels[systemKey] ??
      systemKey;
}

class BikeSystemControllerEntry {
  final BikeSystemControllerSpec spec;
  final BikeSystemOverallStatus status;
  final bool selectable;

  const BikeSystemControllerEntry({
    required this.spec,
    required this.status,
    this.selectable = true,
  });
}

class BikeSystemControllerOverlayLayout {
  final BoxConstraints constraints;
  final BikeDiagramPinPlacement placement;
  final double imageOffsetX;
  final double imageOffsetY;
  final double imageSize;

  const BikeSystemControllerOverlayLayout({
    required this.constraints,
    required this.placement,
    required this.imageOffsetX,
    required this.imageOffsetY,
    required this.imageSize,
  });
}

typedef BikeSystemControllerOverlayBuilder = Widget? Function(
  BuildContext context,
  BikeSystemControllerEntry entry,
  BikeSystemControllerOverlayLayout layout,
);

class BikeSystemController extends StatefulWidget {
  final Bike? bike;
  final BikeDiagramVariant? variant;
  final List<BikeSystemControllerEntry> entries;
  final String? selectedSystemKey;
  final ValueChanged<String> onSystemSelected;
  final String idleHintText;
  final String selectedHintText;
  final BikeSystemControllerOverlayBuilder? overlayBuilder;

  const BikeSystemController({
    super.key,
    required this.bike,
    required this.entries,
    required this.selectedSystemKey,
    required this.onSystemSelected,
    this.variant,
    this.idleHintText =
        'Pasa el cursor para previsualizar · Haz clic para fijar',
    this.selectedHintText = 'Haz clic en otro componente para cambiar la vista',
    this.overlayBuilder,
  });

  @override
  State<BikeSystemController> createState() => _BikeSystemControllerState();
}

class _BikeSystemControllerState extends State<BikeSystemController>
    with TickerProviderStateMixin {
  String? _hoveredSystemKey;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color _statusColor(BikeSystemOverallStatus status) {
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

  BikeSystemControllerEntry? _entryFor(String? systemKey) {
    if (systemKey == null) {
      return null;
    }
    for (final entry in widget.entries) {
      if (entry.spec.systemKey == systemKey) {
        return entry;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final selectedEntry = _entryFor(widget.selectedSystemKey);
    final hoveredEntry = _entryFor(_hoveredSystemKey);
    final variant =
        widget.variant ?? resolveBikeDiagramVariant(bike: widget.bike);
    final hoveredPlacement = hoveredEntry == null
        ? null
        : resolveBikeDiagramPinPlacement(
            variant: variant,
            systemKey: hoveredEntry.spec.systemKey,
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final imageSize = math.min(constraints.maxWidth, constraints.maxHeight);
        final imageOffsetX = (constraints.maxWidth - imageSize) / 2;
        final imageOffsetY = (constraints.maxHeight - imageSize) / 2;

        return Stack(
          children: [
            Positioned(
              left: imageOffsetX,
              top: imageOffsetY,
              width: imageSize,
              height: imageSize,
              child: BikeDiagramIllustration(variant: variant),
            ),
            ...widget.entries.map((entry) {
              final placement = resolveBikeDiagramPinPlacement(
                variant: variant,
                systemKey: entry.spec.systemKey,
              );
              if (placement == null) {
                return const SizedBox.shrink();
              }

              final px = imageOffsetX + placement.position.dx * imageSize;
              final py = imageOffsetY + placement.position.dy * imageSize;
              final isHovered = _hoveredSystemKey == entry.spec.systemKey;
              final isSelected =
                  widget.selectedSystemKey == entry.spec.systemKey;

              return Positioned(
                left: px - 12,
                top: py - 12,
                child: _BikeSystemControllerPin(
                  label: entry.spec.label,
                  color: _statusColor(entry.status),
                  pulseAnimation: _pulseAnimation,
                  isHovered: isHovered,
                  isSelected: isSelected,
                  labelRight: placement.labelRight,
                  selectable: entry.selectable,
                  onHover: (value) => setState(
                    () =>
                        _hoveredSystemKey = value ? entry.spec.systemKey : null,
                  ),
                  onTap: entry.selectable
                      ? () => widget.onSystemSelected(entry.spec.systemKey)
                      : null,
                ),
              );
            }),
            if (hoveredEntry != null &&
                hoveredPlacement != null &&
                widget.overlayBuilder != null)
              widget.overlayBuilder!(
                    context,
                    hoveredEntry,
                    BikeSystemControllerOverlayLayout(
                      constraints: constraints,
                      placement: hoveredPlacement,
                      imageOffsetX: imageOffsetX,
                      imageOffsetY: imageOffsetY,
                      imageSize: imageSize,
                    ),
                  ) ??
                  const SizedBox.shrink(),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0x18FFFFFF), Colors.transparent],
                  ),
                ),
                child: Text(
                  selectedEntry == null
                      ? widget.idleHintText
                      : widget.selectedHintText,
                  style: const TextStyle(
                    color: Color(0xFFB0BEC5),
                    fontSize: 10,
                    letterSpacing: 0.3,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BikeSystemControllerPin extends StatelessWidget {
  final String label;
  final Color color;
  final Animation<double> pulseAnimation;
  final bool isHovered;
  final bool isSelected;
  final bool labelRight;
  final bool selectable;
  final ValueChanged<bool> onHover;
  final VoidCallback? onTap;

  const _BikeSystemControllerPin({
    required this.label,
    required this.color,
    required this.pulseAnimation,
    required this.isHovered,
    required this.isSelected,
    required this.labelRight,
    required this.selectable,
    required this.onHover,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = isHovered || isSelected;
    final effectiveColor = selectable ? color : color.withValues(alpha: 0.45);

    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      cursor: selectable ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 24,
          height: 24,
          child: AnimatedBuilder(
            animation: pulseAnimation,
            builder: (context, _) {
              return Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  if (!active)
                    Container(
                      width: 24 * pulseAnimation.value,
                      height: 24 * pulseAnimation.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: effectiveColor.withValues(
                            alpha: (1 - pulseAnimation.value) * 0.8,
                          ),
                          width: 1.5,
                        ),
                      ),
                    ),
                  if (active)
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: effectiveColor.withValues(alpha: 0.20),
                        border: Border.all(
                          color: effectiveColor.withValues(alpha: 0.6),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: effectiveColor.withValues(alpha: 0.5),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  if (isSelected && !isHovered)
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: effectiveColor.withValues(alpha: 0.35),
                          width: 1,
                        ),
                      ),
                    ),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active
                          ? effectiveColor
                          : effectiveColor.withValues(alpha: 0.85),
                      boxShadow: [
                        BoxShadow(
                          color: effectiveColor.withValues(
                            alpha: active ? 0.9 : 0.5,
                          ),
                          blurRadius: active ? 10 : 4,
                          spreadRadius: active ? 2 : 0,
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: labelRight ? 18 : null,
                    right: labelRight ? null : 18,
                    top: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: active
                              ? effectiveColor.withValues(alpha: 0.7)
                              : const Color(0xFFCBD5E1),
                          width: 1,
                        ),
                        boxShadow: active
                            ? [
                                BoxShadow(
                                  color: effectiveColor.withValues(alpha: 0.20),
                                  blurRadius: 8,
                                ),
                              ]
                            : [
                                const BoxShadow(
                                  color: Color(0x14000000),
                                  blurRadius: 4,
                                  offset: Offset(0, 1),
                                ),
                              ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: effectiveColor,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            label,
                            style: TextStyle(
                              color: active
                                  ? const Color(0xFF1E293B)
                                  : const Color(0xFF475569),
                              fontSize: 10,
                              fontWeight:
                                  active ? FontWeight.w700 : FontWeight.w500,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
