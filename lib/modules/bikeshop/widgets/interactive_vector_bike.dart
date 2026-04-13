part of 'bike_record_panel.dart';

// ---------------------------------------------------------------------------
// Annotation pin positions are expressed as fractions of the image size
// (left/top from 0.0 to 1.0) so they scale perfectly with any widget size.
// These were calibrated against mtb_diagnostic_bg.png (1024x1024 square).
// ---------------------------------------------------------------------------
class _PinDef {
  final String systemKey;
  final String label;

  const _PinDef({
    required this.systemKey,
    required this.label,
  });
}

const _kPins = [
  _PinDef(systemKey: 'cockpit', label: 'Cockpit'),
  _PinDef(systemKey: 'suspension', label: 'Suspensión'),
  _PinDef(systemKey: 'front_brake', label: 'Freno Del.'),
  _PinDef(systemKey: 'wheels', label: 'Ruedas'),
  _PinDef(systemKey: 'drivetrain', label: 'Transmisión'),
  _PinDef(systemKey: 'rear_brake', label: 'Freno Tras.'),
];

// ---------------------------------------------------------------------------

class _InteractiveVectorBike extends StatefulWidget {
  final Bike bike;
  final _BikeRecordHistoryData history;
  final String? activeSystemKey;
  final ValueChanged<String> onSystemSelected;

  const _InteractiveVectorBike({
    required this.bike,
    required this.history,
    this.activeSystemKey,
    required this.onSystemSelected,
  });

  @override
  State<_InteractiveVectorBike> createState() => _InteractiveVectorBikeState();
}

class _InteractiveVectorBikeState extends State<_InteractiveVectorBike>
    with TickerProviderStateMixin {
  String? _hoveredKey;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.55, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Color _pinColor(String systemKey) {
    final sys = widget.history.diagnosisSystems
        .where((s) => s.systemKey == systemKey)
        .firstOrNull;
    if (sys == null) return const Color(0xFF3EFFD0); // teal = unknown/ok
    switch (sys.overallStatus) {
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

  _BikeDiagnosisSystemView? _systemFor(String key) =>
      widget.history.diagnosisSystems
          .where((s) => s.systemKey == key)
          .firstOrNull;

  @override
  Widget build(BuildContext context) {
    // Hover drives the POPUP inside the bike widget (preview on mouse-over).
    // widget.activeSystemKey drives only the pin's SELECTED GLOW (set on tap).
    // These are intentionally decoupled: hover ≠ selection.
    final selectedKey = widget.activeSystemKey;
    final hoveredSystem = _hoveredKey != null ? _systemFor(_hoveredKey!) : null;
    final variant = resolveBikeDiagramVariant(
      bike: widget.bike,
    );
    final hoveredPlacement = _hoveredKey == null
        ? null
        : resolveBikeDiagramPinPlacement(
            variant: variant,
            systemKey: _hoveredKey!,
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        final imgSize = math.min(constraints.maxWidth, constraints.maxHeight);
        final imgOffsetX = (constraints.maxWidth - imgSize) / 2;
        final imgOffsetY = (constraints.maxHeight - imgSize) / 2;

        return Stack(
          children: [
            // ── Bike image ────────────────────────────────────────────────
            Positioned(
              left: imgOffsetX,
              top: imgOffsetY,
              width: imgSize,
              height: imgSize,
              child: BikeDiagramIllustration(variant: variant),
            ),

            // ── Annotation pins ───────────────────────────────────────────
            ..._kPins.map((pin) {
              final placement = resolveBikeDiagramPinPlacement(
                variant: variant,
                systemKey: pin.systemKey,
              );
              if (placement == null) {
                return const SizedBox.shrink();
              }
              final color = _pinColor(pin.systemKey);
              final isHovered = _hoveredKey == pin.systemKey;
              final isSelected = selectedKey == pin.systemKey;

              final px = imgOffsetX + placement.position.dx * imgSize;
              final py = imgOffsetY + placement.position.dy * imgSize;

              return Positioned(
                left: px - 12,
                top: py - 12,
                child: _AnnotationPin(
                  label: pin.label,
                  color: color,
                  pulseAnim: _pulseAnim,
                  isHovered: isHovered,
                  isSelected: isSelected,
                  labelRight: placement.labelRight,
                  onHover: (v) =>
                      setState(() => _hoveredKey = v ? pin.systemKey : null),
                  onTap: () => widget.onSystemSelected(pin.systemKey),
                ),
              );
            }),

            // ── Hover popup card (only visible while hovering) ────────────
            if (hoveredSystem != null && hoveredPlacement != null)
              _DiagnosticPopupCard(
                system: hoveredSystem,
                color: _pinColor(_hoveredKey!),
                constraints: constraints,
                placement: hoveredPlacement,
                imgOffsetX: imgOffsetX,
                imgOffsetY: imgOffsetY,
                imgSize: imgSize,
              ),

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
                  selectedKey == null
                      ? 'Pasa el cursor para previsualizar · Haz clic para fijar'
                      : 'Haz clic en otro componente para cambiar la vista',
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

// ---------------------------------------------------------------------------
// Animated annotation pin with pulsing outer ring
// ---------------------------------------------------------------------------
class _AnnotationPin extends StatelessWidget {
  final String label;
  final Color color;
  final Animation<double> pulseAnim;
  final bool isHovered;
  final bool isSelected;
  final bool labelRight;
  final ValueChanged<bool> onHover;
  final VoidCallback onTap;

  const _AnnotationPin({
    required this.label,
    required this.color,
    required this.pulseAnim,
    required this.isHovered,
    required this.isSelected,
    required this.labelRight,
    required this.onHover,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool active = isHovered || isSelected;
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 24,
          height: 24,
          child: AnimatedBuilder(
            animation: pulseAnim,
            builder: (context, _) {
              return Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  // Outer pulsing ring (idle state)
                  if (!active)
                    Container(
                      width: 24 * pulseAnim.value,
                      height: 24 * pulseAnim.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color.withValues(
                              alpha: (1 - pulseAnim.value) * 0.8),
                          width: 1.5,
                        ),
                      ),
                    ),
                  // Active glow ring (hovered OR selected)
                  if (active)
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.20),
                        border: Border.all(
                            color: color.withValues(alpha: 0.6), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.5),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  // Selected extra ring (distinct from hover-only)
                  if (isSelected && !isHovered)
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color.withValues(alpha: 0.35),
                          width: 1,
                        ),
                      ),
                    ),
                  // Inner dot
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active ? color : color.withValues(alpha: 0.85),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: active ? 0.9 : 0.5),
                          blurRadius: active ? 10 : 4,
                          spreadRadius: active ? 2 : 0,
                        ),
                      ],
                    ),
                  ),
                  // Label pill
                  Positioned(
                    left: labelRight ? 18 : null,
                    right: labelRight ? null : 18,
                    top: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: active
                              ? color.withValues(alpha: 0.7)
                              : const Color(0xFFCBD5E1),
                          width: 1,
                        ),
                        boxShadow: active
                            ? [
                                BoxShadow(
                                    color: color.withValues(alpha: 0.20),
                                    blurRadius: 8)
                              ]
                            : [
                                const BoxShadow(
                                    color: Color(0x14000000),
                                    blurRadius: 4,
                                    offset: Offset(0, 1))
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
                              color: color,
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

// ---------------------------------------------------------------------------
// Floating diagnostic popup card
// ---------------------------------------------------------------------------
class _DiagnosticPopupCard extends StatelessWidget {
  final _BikeDiagnosisSystemView system;
  final Color color;
  final BoxConstraints constraints;
  final BikeDiagramPinPlacement placement;
  final double imgOffsetX;
  final double imgOffsetY;
  final double imgSize;

  const _DiagnosticPopupCard({
    required this.system,
    required this.color,
    required this.constraints,
    required this.placement,
    required this.imgOffsetX,
    required this.imgOffsetY,
    required this.imgSize,
  });

  @override
  Widget build(BuildContext context) {
    const cardW = 270.0;
    const cardH = 220.0;

    final pinX = imgOffsetX + placement.position.dx * imgSize;
    final pinY = imgOffsetY + placement.position.dy * imgSize;

    double left = placement.labelRight ? pinX + 32 : pinX - cardW - 32;
    double top = pinY - 60;

    // Keep card within bounds
    left = left.clamp(8.0, constraints.maxWidth - cardW - 8);
    top = top.clamp(8.0, constraints.maxHeight - cardH - 8);

    // Latest key measurements (up to 2)
    final measurements = system.measurementSeries.take(2).toList();

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              width: cardW,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: color.withValues(alpha: 0.25), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.10),
                    blurRadius: 24,
                    spreadRadius: 0,
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
                  // Header
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
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: color.withValues(alpha: 0.35)),
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
                    Container(
                      height: 1,
                      color: const Color(0xFFE2E8F0),
                    ),
                    const SizedBox(height: 10),
                    ...measurements.map((m) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  m.title,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                              Text(
                                m.latestValueLabel,
                                style: TextStyle(
                                  color: color,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        )),
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
        ),
      ),
    );
  }
}
