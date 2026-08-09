import 'package:flutter/material.dart';
import '../../../shared/widgets/safe_layout_builder.dart';
import '../providers/website_edit_mode_provider.dart';
import 'website_media_picker.dart';

/// A widget that displays an image with a draggable focal point crosshair.
/// Used to set where the image should be centered when cropped on mobile.
class FocalPointPicker extends StatefulWidget {
  /// The title the picker has always printed above itself.
  ///
  /// It names the phone because that is the only viewport the legacy callers
  /// ever reframed. A host that already states which viewport it is editing —
  /// and whether the value is inherited or its own — passes `label: null` and
  /// owns that sentence itself, instead of contradicting it here.
  static const String defaultLabel = 'Punto focal (móvil)';

  /// URL of the image to display
  final String? imageUrl;

  /// Current X focal point (0.0 = left, 0.5 = center, 1.0 = right)
  final double focalX;

  /// Current Y focal point (0.0 = top, 0.5 = center, 1.0 = bottom)
  final double focalY;

  /// Called when the focal point CHANGES for the host: it is the persistence
  /// callback.
  ///
  /// With [continuousUpdates] it fires on every pointer event, as it always
  /// has. Without it, it fires once per gesture — at the end — and once per
  /// discrete `Centrar`.
  final void Function(double x, double y) onChanged;

  /// Height of the picker widget
  final double height;

  /// Header title, or null for a host that owns the label itself.
  final String? label;

  /// Whether [onChanged] fires on every pointer move.
  ///
  /// True is the historical behaviour and stays the default, so no existing
  /// caller changes. False makes a drag ONE change for the host: the crosshair
  /// still follows the pointer locally — identical feedback — but the value is
  /// published when the gesture ends, and a cancelled gesture publishes
  /// nothing at all.
  final bool continuousUpdates;

  /// Live position during a drag, for a host that wants feedback without
  /// persisting. Never called when [continuousUpdates] is true, because there
  /// [onChanged] already reports every move.
  final void Function(double x, double y)? onPreview;

  /// A gesture that ended without publishing, so the host can drop whatever
  /// preview it was showing. Only reachable when [continuousUpdates] is false.
  final VoidCallback? onCancel;

  /// Exact page/block/field owner for a persisted focal edit.
  ///
  /// The arm is captured at pointer-down and returned through the binding that
  /// is live at pointer-up. A retained picker can therefore never redirect A's
  /// drag into a replacement document B with the same visible coordinates.
  final WebsiteAsyncFieldBinding? asyncBinding;

  const FocalPointPicker({
    super.key,
    this.imageUrl,
    this.focalX = 0.5,
    this.focalY = 0.5,
    required this.onChanged,
    this.height = 150,
    this.label = defaultLabel,
    this.continuousUpdates = true,
    this.onPreview,
    this.onCancel,
    this.asyncBinding,
  }) : assert(
          asyncBinding == null || !continuousUpdates,
          'An armed focal edit publishes once at pointer-up.',
        );

  @override
  State<FocalPointPicker> createState() => _FocalPointPickerState();
}

class _FocalPointPickerState extends State<FocalPointPicker> {
  late double _localX;
  late double _localY;
  bool _isDragging = false;
  WebsiteAsyncFieldArm? _arm;
  WebsiteAsyncFieldBinding? _openingBinding;

  @override
  void initState() {
    super.initState();
    _localX = widget.focalX;
    _localY = widget.focalY;
  }

  @override
  void didUpdateWidget(FocalPointPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ownerChanged =
        oldWidget.asyncBinding?.identity != widget.asyncBinding?.identity ||
            oldWidget.imageUrl != widget.imageUrl ||
            oldWidget.focalX != widget.focalX ||
            oldWidget.focalY != widget.focalY;
    if (_isDragging && ownerChanged) {
      _rejectArm();
      _isDragging = false;
      oldWidget.onCancel?.call();
    }
    if (!_isDragging) {
      _localX = widget.focalX;
      _localY = widget.focalY;
    }
  }

  bool _beginGesture() {
    final binding = widget.asyncBinding;
    final arm = binding?.capture();
    if (binding != null && arm == null) {
      widget.onCancel?.call();
      return false;
    }
    _arm = arm;
    _openingBinding = binding;
    _isDragging = true;
    return true;
  }

  /// Moves the crosshair, and reports it the way this host asked to be told.
  void _moveTo(double x, double y) {
    setState(() {
      _localX = x;
      _localY = y;
    });
    if (widget.continuousUpdates) {
      // Values are passed directly rather than read back from state, which is
      // applied asynchronously.
      widget.onChanged(x, y);
      return;
    }
    widget.onPreview?.call(x, y);
  }

  void _endGesture({required bool cancelled}) {
    if (!_isDragging) return;
    _isDragging = false;
    if (widget.continuousUpdates) return;
    if (cancelled) {
      _rejectArm();
      setState(() {
        _localX = widget.focalX;
        _localY = widget.focalY;
      });
      widget.onCancel?.call();
      return;
    }
    final arm = _arm;
    final openingBinding = _openingBinding;
    _arm = null;
    _openingBinding = null;
    if (arm == null) {
      if (widget.asyncBinding == null) {
        widget.onChanged(_localX, _localY);
      } else {
        widget.onCancel?.call();
      }
      return;
    }
    final liveBinding = widget.asyncBinding;
    if (liveBinding == null) {
      openingBinding?.commit(
        arm,
        () => WebsiteInlineMutationResult.rejected,
      );
      widget.onCancel?.call();
      return;
    }
    final result = liveBinding.commit(arm, () {
      widget.onChanged(_localX, _localY);
      return WebsiteInlineMutationResult.committed;
    });
    if (!result.accepted) {
      setState(() {
        _localX = widget.focalX;
        _localY = widget.focalY;
      });
      widget.onCancel?.call();
    }
  }

  void _rejectArm() {
    final arm = _arm;
    final openingBinding = _openingBinding;
    _arm = null;
    _openingBinding = null;
    if (arm == null) return;
    (widget.asyncBinding ?? openingBinding)?.commit(
      arm,
      () => WebsiteInlineMutationResult.rejected,
    );
  }

  void _center() {
    final binding = widget.asyncBinding;
    final arm = binding?.capture();
    if (binding != null && arm == null) return;
    if (arm != null) {
      final result = binding!.commit(arm, () {
        widget.onChanged(0.5, 0.5);
        return WebsiteInlineMutationResult.committed;
      });
      if (!result.accepted) return;
    } else {
      widget.onChanged(0.5, 0.5);
    }
    setState(() {
      _localX = 0.5;
      _localY = 0.5;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = widget.imageUrl != null && widget.imageUrl!.isNotEmpty;
    final label = widget.label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label. The text flexes so a narrow host — the picker also opens
        // inside a repeater's indented section, where it gets about 250 px —
        // ellipsizes instead of overflowing. Same icon, gap and typography.
        if (label != null) ...[
          Row(
            children: [
              Icon(Icons.crop_free, size: 16, color: Colors.grey.shade400),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade400,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],

        // Image with focal point crosshair
        Container(
          height: widget.height,
          decoration: BoxDecoration(
            color: Colors.grey.shade800,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade700),
          ),
          clipBehavior: Clip.antiAlias,
          child: hasImage
              ? ConstraintLayoutBuilder(
                  builder: (context, constraints) {
                    return Listener(
                      onPointerDown: (event) {
                        if (!_beginGesture()) return;
                        _moveTo(
                          (event.localPosition.dx / constraints.maxWidth)
                              .clamp(0.0, 1.0),
                          (event.localPosition.dy / constraints.maxHeight)
                              .clamp(0.0, 1.0),
                        );
                      },
                      onPointerMove: (event) {
                        if (!_isDragging) return;
                        _moveTo(
                          (event.localPosition.dx / constraints.maxWidth)
                              .clamp(0.0, 1.0),
                          (event.localPosition.dy / constraints.maxHeight)
                              .clamp(0.0, 1.0),
                        );
                      },
                      onPointerUp: (event) => _endGesture(cancelled: false),
                      onPointerCancel: (event) => _endGesture(cancelled: true),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Background image
                          Image.network(
                            widget.imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _buildPlaceholder(),
                          ),

                          // Darkening overlay
                          Container(
                            color: Colors.black.withValues(alpha: 0.3),
                          ),

                          // Focal point crosshair
                          Positioned(
                            left: _localX * constraints.maxWidth - 16,
                            top: _localY * constraints.maxHeight - 16,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.add,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),

                          // Crosshair lines
                          Positioned(
                            left: _localX * constraints.maxWidth,
                            top: 0,
                            bottom: 0,
                            child: Container(
                              width: 1,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                          Positioned(
                            top: _localY * constraints.maxHeight,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 1,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),

                          // Instruction overlay
                          Positioned(
                            bottom: 8,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Arrastra para ajustar',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                )
              : _buildPlaceholder(),
        ),

        const SizedBox(height: 6),

        // Coordinates display. `Wrap` with `spaceBetween` reproduces exactly
        // what the old `Spacer` did while both halves fit on one line — chips
        // left, `Centrar` right — and lets the button drop to a second line
        // when the host is too narrow, instead of overflowing. Same chips,
        // same button, same 8 gap.
        Wrap(
          spacing: 8,
          runSpacing: 6,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildCoordChip('X', (_localX * 100).round()),
                const SizedBox(width: 8),
                _buildCoordChip('Y', (_localY * 100).round()),
              ],
            ),
            // Reset button. Discrete in both modes: one press is one change.
            TextButton.icon(
              onPressed: () {
                _center();
              },
              icon: const Icon(Icons.center_focus_strong, size: 14),
              label: const Text('Centrar'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade400,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_not_supported,
              color: Colors.grey.shade600, size: 32),
          const SizedBox(height: 8),
          Text(
            'Sin imagen',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildCoordChip(String label, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label: $value%',
        style: TextStyle(
          color: Colors.grey.shade300,
          fontSize: 11,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
