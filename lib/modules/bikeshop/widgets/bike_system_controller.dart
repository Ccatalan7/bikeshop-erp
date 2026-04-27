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
    label: 'Cockpit / dirección',
    icon: Icons.tune,
    diagnosisSubtitle: 'Headset, stem, manillar y controles.',
    supportsStructuredDiagnosis: true,
  ),
  BikeSystemControllerSpec(
    systemKey: 'suspension',
    label: 'Suspensión',
    icon: Icons.waves_outlined,
    diagnosisSubtitle: 'Horquilla, amortiguacion y soporte del sistema.',
    supportsStructuredDiagnosis: true,
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
    systemKey: 'front_wheel',
    label: 'Rueda delantera',
    icon: Icons.trip_origin,
    diagnosisSubtitle: 'Maza, aro, rayado y rodado delantero.',
    supportsStructuredDiagnosis: true,
  ),
  BikeSystemControllerSpec(
    systemKey: 'drivetrain',
    label: 'Transmisión',
    icon: Icons.settings_input_component_outlined,
    diagnosisSubtitle: 'Cadena, cassette y tren motriz.',
    supportsStructuredDiagnosis: true,
  ),
  BikeSystemControllerSpec(
    systemKey: 'bottom_bracket',
    label: 'Pedalier / BB',
    icon: Icons.hub_outlined,
    diagnosisSubtitle: 'Caja, rodamientos y soporte del eje pedalier.',
    supportsStructuredDiagnosis: true,
  ),
  BikeSystemControllerSpec(
    systemKey: 'rear_wheel',
    label: 'Rueda trasera',
    icon: Icons.trip_origin,
    diagnosisSubtitle: 'Maza, aro, rayado y rodado trasero.',
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
    'bottom_bracket': 'Pedalier / BB',
    'rear_wheel': 'Rueda trasera',
    'cockpit': 'Cockpit / dirección',
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

/// ─────────────────────────────────────────────────────────────────────────
/// BikeSystemController — single source of truth for the interactive bike map.
///
/// RULE: all behaviour of this widget lives HERE.
/// Parents must NOT replicate or second-guess internal state.
///
/// Specifically:
/// • The decision of WHEN to show an exploded detail view is internal.
///   [_BikeSystemControllerState._explicitSystemKey] tracks whether the user
///   actually tapped a pin in THIS widget. Parents have no visibility into that.
///   DO NOT conditionally pass [onClearSelection] to control the detail view —
///   that is the exact mistake that broke the bike-profile screen.
///
/// • [selectedSystemKey] is the externally-driven highlight (auto-resolved by
///   the parent from status/data). It does NOT control the detail view.
///
/// • [onClearSelection] is a notification-only callback: the parent is told
///   when the user navigated back so it can clear its own state. It NEVER
///   gates the detail view — that is the widget's job.
///
/// Any future feature that affects the shared map must be implemented here
/// and will automatically apply everywhere the widget is used.
/// ─────────────────────────────────────────────────────────────────────────
class BikeSystemController extends StatefulWidget {
  final Bike? bike;
  final BikeProfile? profile;
  final BikeDiagramVariant? variant;
  final List<BikeSystemControllerEntry> entries;

  /// Externally-driven highlight key (e.g. auto-resolved from job status).
  /// This does NOT control whether the detail view shows — see [onClearSelection].
  final String? selectedSystemKey;
  final ValueChanged<String> onSystemSelected;

  /// Called when the user taps "← Vista general" to exit the detail view.
  /// Pass this unconditionally — the widget decides when to use it.
  /// DO NOT make this conditional on whether the user explicitly tapped;
  /// that tracking is done internally via [_explicitSystemKey].
  final VoidCallback? onClearSelection;
  final String idleHintText;
  final String selectedHintText;
  final BikeSystemControllerOverlayBuilder? overlayBuilder;

  const BikeSystemController({
    super.key,
    required this.bike,
    this.profile,
    required this.entries,
    required this.selectedSystemKey,
    required this.onSystemSelected,
    this.onClearSelection,
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
  // Hover state lives in a ValueNotifier so that pin hovering never triggers
  // a parent setState — that would recreate all MouseRegion widgets and cause
  // a rapid ENTER/EXIT re-mount loop (flicker). Only the overlay rebuilds.
  final ValueNotifier<String?> _hoveredKey = ValueNotifier(null);

  // ── INTERNAL ONLY — do not expose or replicate in parent widgets ──────────
  // This is the key the user EXPLICITLY tapped inside this widget.
  // It is the sole gate for the exploded detail view.
  // The parent's selectedSystemKey (auto-resolved from status/data) is ignored
  // for this purpose so that pre-highlighted systems never auto-open the image.
  // If you are ever tempted to move this outside, read the class doc first.
  // ─────────────────────────────────────────────────────────────────────────
  String? _explicitSystemKey;

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
  void didUpdateWidget(BikeSystemController oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the parent changed selectedSystemKey to something OTHER than what the
    // user just tapped here, treat it as an external navigation and clear the
    // explicit selection so the detail view closes.
    if (widget.selectedSystemKey != oldWidget.selectedSystemKey &&
        widget.selectedSystemKey != _explicitSystemKey) {
      _explicitSystemKey = null;
    }
  }

  @override
  void dispose() {
    _hoveredKey.dispose();
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
    final variant =
        widget.variant ?? resolveBikeDiagramVariant(bike: widget.bike);

    // --- system detail view (exploded component image) ---
    // Only show when the user EXPLICITLY tapped a pin (not auto-resolved by parent).
    final detailConfig = _kSystemDetailAssets[_explicitSystemKey];
    final detailAssetPath = detailConfig?.resolveAssetPath(widget.bike, widget.profile);
    final detailLabel = _explicitSystemKey != null
        ? bikeSystemControllerLabelFor(_explicitSystemKey!)
        : '';

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      child: detailConfig != null && detailAssetPath != null
          ? _SystemDetailView(
              key: ValueKey('detail_$_explicitSystemKey'),
              assetPath: detailAssetPath,
              flipX: detailConfig.flipX,
              label: detailLabel,
              onBack: () {
                setState(() => _explicitSystemKey = null);
                widget.onClearSelection?.call();
              },
            )
          : _buildFullSchema(
              context,
              variant: variant,
              selectedEntry: selectedEntry,
            ),
    );
  }

  Widget _buildFullSchema(
    BuildContext context, {
    required BikeDiagramVariant variant,
    required BikeSystemControllerEntry? selectedEntry,
  }) {
    return LayoutBuilder(
      key: const ValueKey('full_schema'),
      builder: (context, constraints) {
        final imageSize = math.min(constraints.maxWidth, constraints.maxHeight);
        final imageOffsetX = (constraints.maxWidth - imageSize) / 2;
        final imageOffsetY = (constraints.maxHeight - imageSize) / 2;

        final baseStack = Stack(
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
              final isSelected =
                  widget.selectedSystemKey == entry.spec.systemKey;

              return Positioned(
                left: px - 12,
                top: py - 12,
                child: _BikeSystemControllerPin(
                  label: entry.spec.label,
                  color: _statusColor(entry.status),
                  pulseAnimation: _pulseAnimation,
                  isSelected: isSelected,
                  labelRight: placement.labelRight,
                  selectable: entry.selectable,
                  onHoverChanged: (isHovered) {
                    if (isHovered) {
                      _hoveredKey.value = entry.spec.systemKey;
                    } else if (_hoveredKey.value == entry.spec.systemKey) {
                      _hoveredKey.value = null;
                    }
                  },
                  onTap: entry.selectable
                      ? () {
                          setState(() {
                            _explicitSystemKey = entry.spec.systemKey;
                          });
                          widget.onSystemSelected(entry.spec.systemKey);
                        }
                      : null,
                ),
              );
            }),
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

        if (widget.overlayBuilder == null) {
          return baseStack;
        }

        return ValueListenableBuilder<String?>(
          valueListenable: _hoveredKey,
          child: baseStack,
          builder: (context, hoveredSystemKey, child) {
            final hoveredEntry = _entryFor(hoveredSystemKey);
            final hoveredPlacement = hoveredEntry == null
                ? null
                : resolveBikeDiagramPinPlacement(
                    variant: variant,
                    systemKey: hoveredEntry.spec.systemKey,
                  );
            final overlay = hoveredEntry == null || hoveredPlacement == null
                ? null
                : widget.overlayBuilder!(
                    context,
                    hoveredEntry,
                    BikeSystemControllerOverlayLayout(
                      constraints: constraints,
                      placement: hoveredPlacement,
                      imageOffsetX: imageOffsetX,
                      imageOffsetY: imageOffsetY,
                      imageSize: imageSize,
                    ),
                  );

            if (overlay == null) {
              return child!;
            }

            return Stack(
              fit: StackFit.expand,
              children: [
                child!,
                overlay,
              ],
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Registry: which system keys have an exploded detail image
// ---------------------------------------------------------------------------

class _SystemDetailConfig {
  final String? assetPath;
  final String Function(Bike? bike, BikeProfile? profile)? assetPathResolver;
  final bool flipX;

  const _SystemDetailConfig({
    this.assetPath,
    this.assetPathResolver,
    this.flipX = false,
  }) : assert(assetPath != null || assetPathResolver != null,
            'Must provide assetPath or assetPathResolver');

  String resolveAssetPath(Bike? bike, BikeProfile? profile) {
    if (assetPathResolver != null) {
      return assetPathResolver!(bike, profile);
    }
    return assetPath!;
  }
}

String _resolveBottomBracketAsset(Bike? bike, BikeProfile? profile) {
  final family = profile?.technicalValues['bottomBracketFamily']?.toString();
  if (family == 'pressfit' || family == 'bb30_pf30') {
    return 'assets/images/bottom_bracket_hollowtech_exploded.png';
  }
  return 'assets/images/bottom_bracket_sealed_exploded.png';
}

const Map<String, _SystemDetailConfig> _kSystemDetailAssets = {
  'drivetrain':
      _SystemDetailConfig(assetPath: 'assets/images/drivetrain_exploded.png'),
  'suspension':
      _SystemDetailConfig(assetPath: 'assets/images/suspension_exploded.png'),
  'rear_brake':
      _SystemDetailConfig(assetPath: 'assets/images/rear_brake_exploded.png'),
  'front_brake': _SystemDetailConfig(
      assetPath: 'assets/images/rear_brake_exploded.png', flipX: true),
  'front_wheel':
      _SystemDetailConfig(assetPath: 'assets/images/front_wheel_exploded.png'),
  'rear_wheel':
      _SystemDetailConfig(assetPath: 'assets/images/rear_wheel_exploded.png'),
  'cockpit':
      _SystemDetailConfig(assetPath: 'assets/images/headset_exploded.png'),
  'bottom_bracket': _SystemDetailConfig(
    assetPathResolver: _resolveBottomBracketAsset,
  ),
};

// ---------------------------------------------------------------------------
// Generic system exploded detail view
// ---------------------------------------------------------------------------

class _SystemDetailView extends StatelessWidget {
  final String assetPath;
  final bool flipX;
  final String label;
  final VoidCallback onBack;

  const _SystemDetailView({
    super.key,
    required this.assetPath,
    this.flipX = false,
    required this.label,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Exploded system image
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 36, 12, 12),
          child: Transform(
            alignment: Alignment.center,
            transform: flipX
                ? (Matrix4.identity()..scale(-1.0, 1.0))
                : Matrix4.identity(),
            child: Image.asset(
              assetPath,
              fit: BoxFit.contain,
            ),
          ),
        ),
        // Back chip — top-left
        Positioned(
          top: 8,
          left: 8,
          child: GestureDetector(
            onTap: onBack,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFFCBD5E1),
                    width: 1,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 10,
                      color: Color(0xFF475569),
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Vista general',
                      style: TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // System label — bottom center
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0x18FFFFFF), Colors.transparent],
              ),
            ),
            child: Text(
              '$label — componentes',
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
  }
}

class _BikeSystemControllerPin extends StatefulWidget {
  final String label;
  final Color color;
  final Animation<double> pulseAnimation;
  final bool isSelected;
  final bool labelRight;
  final bool selectable;
  final ValueChanged<bool> onHoverChanged;
  final VoidCallback? onTap;

  const _BikeSystemControllerPin({
    required this.label,
    required this.color,
    required this.pulseAnimation,
    required this.isSelected,
    required this.labelRight,
    required this.selectable,
    required this.onHoverChanged,
    required this.onTap,
  });

  @override
  State<_BikeSystemControllerPin> createState() =>
      _BikeSystemControllerPinState();
}

class _BikeSystemControllerPinState extends State<_BikeSystemControllerPin> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final active = _isHovered || widget.isSelected;
    final effectiveColor =
        widget.selectable ? widget.color : widget.color.withValues(alpha: 0.45);

    return MouseRegion(
      onEnter: (_) {
        if (!_isHovered) {
          setState(() => _isHovered = true);
        }
        widget.onHoverChanged(true);
      },
      onExit: (_) {
        if (_isHovered) {
          setState(() => _isHovered = false);
        }
        widget.onHoverChanged(false);
      },
      cursor: widget.selectable
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: 24,
          height: 24,
          child: AnimatedBuilder(
            animation: widget.pulseAnimation,
            builder: (context, _) {
              return Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  if (!active)
                    Container(
                      width: 24 * widget.pulseAnimation.value,
                      height: 24 * widget.pulseAnimation.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: effectiveColor.withValues(
                            alpha: (1 - widget.pulseAnimation.value) * 0.8,
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
                  if (widget.isSelected && !_isHovered)
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
                    left: widget.labelRight ? 18 : null,
                    right: widget.labelRight ? null : 18,
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
                            widget.label,
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
