import 'package:flutter/material.dart';
import '../../../shared/widgets/safe_layout_builder.dart';

/// A widget that displays an image with a draggable focal point crosshair.
/// Used to set where the image should be centered when cropped on mobile.
class FocalPointPicker extends StatefulWidget {
  /// URL of the image to display
  final String? imageUrl;

  /// Current X focal point (0.0 = left, 0.5 = center, 1.0 = right)
  final double focalX;

  /// Current Y focal point (0.0 = top, 0.5 = center, 1.0 = bottom)
  final double focalY;

  /// Called when the focal point changes
  final void Function(double x, double y) onChanged;

  /// Height of the picker widget
  final double height;

  const FocalPointPicker({
    super.key,
    this.imageUrl,
    this.focalX = 0.5,
    this.focalY = 0.5,
    required this.onChanged,
    this.height = 150,
  });

  @override
  State<FocalPointPicker> createState() => _FocalPointPickerState();
}

class _FocalPointPickerState extends State<FocalPointPicker> {
  late double _localX;
  late double _localY;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _localX = widget.focalX;
    _localY = widget.focalY;
  }

  @override
  void didUpdateWidget(FocalPointPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging) {
      _localX = widget.focalX;
      _localY = widget.focalY;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = widget.imageUrl != null && widget.imageUrl!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label
        Row(
          children: [
            Icon(Icons.crop_free, size: 16, color: Colors.grey.shade400),
            const SizedBox(width: 6),
            Text(
              'Punto focal (móvil)',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade400,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

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
                        _isDragging = true;
                        // Calculate new values directly
                        final newX =
                            (event.localPosition.dx / constraints.maxWidth)
                                .clamp(0.0, 1.0);
                        final newY =
                            (event.localPosition.dy / constraints.maxHeight)
                                .clamp(0.0, 1.0);
                        setState(() {
                          _localX = newX;
                          _localY = newY;
                        });
                        // Pass calculated values directly (not from state which is async)
                        widget.onChanged(newX, newY);
                      },
                      onPointerMove: (event) {
                        if (_isDragging) {
                          final newX =
                              (event.localPosition.dx / constraints.maxWidth)
                                  .clamp(0.0, 1.0);
                          final newY =
                              (event.localPosition.dy / constraints.maxHeight)
                                  .clamp(0.0, 1.0);
                          setState(() {
                            _localX = newX;
                            _localY = newY;
                          });
                          widget.onChanged(newX, newY);
                        }
                      },
                      onPointerUp: (event) {
                        _isDragging = false;
                      },
                      onPointerCancel: (event) {
                        _isDragging = false;
                      },
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

        // Coordinates display
        Row(
          children: [
            _buildCoordChip('X', (_localX * 100).round()),
            const SizedBox(width: 8),
            _buildCoordChip('Y', (_localY * 100).round()),
            const Spacer(),
            // Reset button
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _localX = 0.5;
                  _localY = 0.5;
                });
                widget.onChanged(0.5, 0.5);
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
