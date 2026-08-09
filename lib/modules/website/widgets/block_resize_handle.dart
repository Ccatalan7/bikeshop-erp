import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'website_editor_control_density.dart';

/// A minimalist resize handle for website blocks in edit mode.
///
/// Appears as a subtle horizontal line at the top or bottom of the block.
/// When hovered, shows a small grab indicator. Dragging vertically
/// resizes the block height.
class BlockResizeHandle extends StatefulWidget {
  /// Current height of the block (null = auto)
  final double? currentHeight;

  /// The actual rendered height of the block (used when currentHeight is null)
  final double? actualHeight;

  /// Minimum allowed height
  final double minHeight;

  /// Maximum allowed height (null = no limit)
  final double? maxHeight;

  /// Callback when height changes during drag
  final ValueChanged<double> onHeightChanged;

  /// Arms the exact document transaction on pointer-down.
  ///
  /// Returning false rejects the gesture without exposing a stale local edit.
  final bool Function(double startHeight)? onHeightChangeStart;

  /// Callback when drag ends (final value)
  final ValueChanged<double>? onHeightChangeEnd;

  /// Cancels the armed transaction without writing.
  final VoidCallback? onHeightChangeCancel;

  /// Callback to reset height to default (null = auto)
  final VoidCallback? onResetHeight;

  /// Whether the handle is active (block is selected)
  final bool isActive;

  /// Height snap increments (e.g., 10 = snaps to 10px increments)
  final double? snapIncrement;

  /// Whether this is the top handle (affects drag direction)
  final bool isTopHandle;

  const BlockResizeHandle({
    super.key,
    this.currentHeight,
    this.actualHeight,
    this.minHeight = 100,
    this.maxHeight,
    required this.onHeightChanged,
    this.onHeightChangeStart,
    this.onHeightChangeEnd,
    this.onHeightChangeCancel,
    this.onResetHeight,
    this.isActive = false,
    this.snapIncrement,
    this.isTopHandle = false,
  });

  @override
  State<BlockResizeHandle> createState() => _BlockResizeHandleState();
}

class _BlockResizeHandleState extends State<BlockResizeHandle> {
  bool _isHovered = false;
  bool _isDragging = false;
  double _dragStartY = 0;
  double _dragStartHeight = 0;
  double? _currentDragHeight; // Track height locally during drag
  int? _activePointer;
  bool _isArmed = false;

  double get _startHeight =>
      widget.currentHeight ?? widget.actualHeight ?? widget.minHeight;

  @override
  Widget build(BuildContext context) {
    // Only show when active (block is selected)
    if (!widget.isActive) {
      return const SizedBox.shrink();
    }

    // During drag, use local drag height; otherwise use widget's currentHeight
    final displayHeight =
        _isDragging ? _currentDragHeight : widget.currentHeight;
    final showHeight = (_isHovered || _isDragging) && displayHeight != null;
    final showResetButton = _isHovered &&
        !_isDragging &&
        widget.currentHeight != null &&
        widget.onResetHeight != null;

    return Semantics(
      label: 'Ajustar altura del bloque',
      value: widget.currentHeight == null
          ? 'Automática'
          : '${widget.currentHeight!.round()} píxeles',
      increasedValue: '${_normalizedHeight(_startHeight + 10).round()} píxeles',
      decreasedValue: '${_normalizedHeight(_startHeight - 10).round()} píxeles',
      onIncrease: () => _adjustHeight(10),
      onDecrease: () => _adjustHeight(-10),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeRow,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) {
          if (!_isDragging) {
            setState(() => _isHovered = false);
          }
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: _onDragStart,
            onVerticalDragUpdate: _onDragUpdate,
            onVerticalDragEnd: _onDragEnd,
            onVerticalDragCancel: _onDragCancel,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 20,
              decoration: BoxDecoration(
                color: (_isHovered || _isDragging)
                    ? const Color(0xFF00A09D).withValues(alpha: 0.15)
                    : Colors.transparent,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // The drag handle bar
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: (_isHovered || _isDragging) ? 80 : 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: (_isHovered || _isDragging)
                          ? const Color(0xFF00A09D)
                          : const Color(0xFF00A09D).withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Height indicator (on the right)
                  if (showHeight)
                    Positioned(
                      right: 16,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 100),
                        opacity: showHeight ? 1.0 : 0.0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00A09D),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${displayHeight.toStringAsFixed(0)}px',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Reset button (on the left) - only on bottom handle
                  if (showResetButton && !widget.isTopHandle)
                    Positioned(
                      left: 16,
                      child: GestureDetector(
                        onTap: widget.onResetHeight,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 100),
                          opacity: 1.0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color: const Color(0xFF00A09D)
                                      .withValues(alpha: 0.3)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.restart_alt,
                                    size: 12, color: Color(0xFF00A09D)),
                                SizedBox(width: 3),
                                Text(
                                  'Auto',
                                  style: TextStyle(
                                    color: Color(0xFF00A09D),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null || _isArmed) return;
    final startHeight = _startHeight;
    if (!(widget.onHeightChangeStart?.call(startHeight) ?? true)) return;
    _activePointer = event.pointer;
    _isArmed = true;
    _dragStartHeight = startHeight;
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_activePointer != event.pointer || _isDragging) return;
    _cancelGesture();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_activePointer != event.pointer) return;
    _cancelGesture();
  }

  void _onDragStart(DragStartDetails details) {
    if (!_isArmed) return;
    setState(() {
      _isDragging = true;
      _dragStartY = details.globalPosition.dy;
      _currentDragHeight = _dragStartHeight;
    });
    HapticFeedback.lightImpact();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;

    final delta = details.globalPosition.dy - _dragStartY;
    // For top handle, dragging up (negative delta) should increase height
    // For bottom handle, dragging down (positive delta) should increase height
    var newHeight = widget.isTopHandle
        ? _dragStartHeight - delta
        : _dragStartHeight + delta;

    newHeight = _normalizedHeight(newHeight);

    // Update local state only (don't trigger Provider rebuild during drag)
    setState(() {
      _currentDragHeight = newHeight;
    });

    // The callback updates only the renderer's local preview. Persistence is
    // owned by onHeightChangeEnd, once.
    widget.onHeightChanged(newHeight);
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_isDragging || !_isArmed) {
      _cancelGesture();
      return;
    }
    final finalHeight = _currentDragHeight;
    setState(() {
      _isDragging = false;
      _isHovered = false;
      _currentDragHeight = null;
    });

    _isArmed = false;
    _activePointer = null;

    if (widget.onHeightChangeEnd != null && finalHeight != null) {
      widget.onHeightChangeEnd!(finalHeight);
    }
    HapticFeedback.mediumImpact();
  }

  void _onDragCancel() => _cancelGesture();

  double _normalizedHeight(double value) {
    var result = value.clamp(
      widget.minHeight,
      widget.maxHeight ?? double.infinity,
    );
    if (widget.snapIncrement != null && widget.snapIncrement! > 0) {
      result = (result / widget.snapIncrement!).round() * widget.snapIncrement!;
    }
    return result;
  }

  void _adjustHeight(double delta) {
    final startHeight = _startHeight;
    if (!(widget.onHeightChangeStart?.call(startHeight) ?? true)) return;
    final next = _normalizedHeight(startHeight + delta);
    widget.onHeightChanged(next);
    widget.onHeightChangeEnd?.call(next);
  }

  void _cancelGesture() {
    final shouldCancel = _isArmed;
    _isArmed = false;
    _activePointer = null;
    if (mounted && (_isDragging || _currentDragHeight != null)) {
      setState(() {
        _isDragging = false;
        _isHovered = false;
        _currentDragHeight = null;
      });
    }
    if (shouldCancel) widget.onHeightChangeCancel?.call();
  }

  @override
  void dispose() {
    if (_isArmed) widget.onHeightChangeCancel?.call();
    super.dispose();
  }
}

/// A container that wraps block content with resize capability.
///
/// This is the main widget to use for resizable blocks. It manages
/// the height state and shows the resize handle when appropriate.
class ResizableBlockContainer extends StatelessWidget {
  /// The block content
  final Widget child;

  /// Current height (null = auto height based on content)
  final double? height;

  /// Minimum height when resizing
  final double minHeight;

  /// Maximum height when resizing
  final double? maxHeight;

  /// Whether resize is enabled (block is selected in edit mode)
  final bool isResizeEnabled;

  /// Callback when height changes
  final ValueChanged<double>? onHeightChanged;

  /// Callback when resize drag ends
  final ValueChanged<double>? onHeightChangeEnd;

  /// Snap to increments (e.g., 10 = snap to 10px)
  final double? snapIncrement;

  const ResizableBlockContainer({
    super.key,
    required this.child,
    this.height,
    this.minHeight = 100,
    this.maxHeight,
    this.isResizeEnabled = false,
    this.onHeightChanged,
    this.onHeightChangeEnd,
    this.snapIncrement = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The block content with optional height constraint
        height != null
            ? SizedBox(
                height: height,
                child: ClipRect(child: child),
              )
            : child,

        // Resize handle (only when enabled)
        if (isResizeEnabled && onHeightChanged != null)
          BlockResizeHandle(
            currentHeight: height,
            minHeight: minHeight,
            maxHeight: maxHeight,
            isActive: true,
            snapIncrement: snapIncrement,
            onHeightChanged: onHeightChanged!,
            onHeightChangeEnd: onHeightChangeEnd,
          ),
      ],
    );
  }
}

/// Height preset options for quick selection
enum BlockHeightPreset {
  auto,
  small,
  medium,
  large,
  extraLarge,
  custom,
}

extension BlockHeightPresetExtension on BlockHeightPreset {
  String get label {
    switch (this) {
      case BlockHeightPreset.auto:
        return 'Auto';
      case BlockHeightPreset.small:
        return 'S';
      case BlockHeightPreset.medium:
        return 'M';
      case BlockHeightPreset.large:
        return 'L';
      case BlockHeightPreset.extraLarge:
        return 'XL';
      case BlockHeightPreset.custom:
        return 'Custom';
    }
  }

  double? getHeight(String blockType) {
    // Different block types have different preset values
    switch (this) {
      case BlockHeightPreset.auto:
        return null;
      case BlockHeightPreset.small:
        return _getSmallHeight(blockType);
      case BlockHeightPreset.medium:
        return _getMediumHeight(blockType);
      case BlockHeightPreset.large:
        return _getLargeHeight(blockType);
      case BlockHeightPreset.extraLarge:
        return _getExtraLargeHeight(blockType);
      case BlockHeightPreset.custom:
        return null; // Custom uses the manually set value
    }
  }

  double _getSmallHeight(String blockType) {
    switch (blockType) {
      case 'hero':
      case 'carousel':
        return 300;
      case 'products':
        return 350;
      default:
        return 100;
    }
  }

  double _getMediumHeight(String blockType) {
    switch (blockType) {
      case 'hero':
      case 'carousel':
        return 450;
      case 'products':
        return 450;
      default:
        return 350;
    }
  }

  double _getLargeHeight(String blockType) {
    switch (blockType) {
      case 'hero':
      case 'carousel':
        return 600;
      case 'products':
        return 550;
      default:
        return 500;
    }
  }

  double _getExtraLargeHeight(String blockType) {
    switch (blockType) {
      case 'hero':
      case 'carousel':
        return 800;
      case 'products':
        return 700;
      default:
        return 650;
    }
  }
}

/// Widget to display height presets in the editor panel
class BlockHeightPresetSelector extends StatelessWidget {
  final String blockType;
  final double? currentHeight;
  final ValueChanged<double?> onHeightChanged;

  const BlockHeightPresetSelector({
    super.key,
    required this.blockType,
    this.currentHeight,
    required this.onHeightChanged,
  });

  @override
  Widget build(BuildContext context) {
    final presets = [
      BlockHeightPreset.auto,
      BlockHeightPreset.small,
      BlockHeightPreset.medium,
      BlockHeightPreset.large,
      BlockHeightPreset.extraLarge,
    ];

    return Row(
      children: presets.map((preset) {
        final presetHeight = preset.getHeight(blockType);
        final isSelected = _isPresetSelected(preset, presetHeight);

        return Expanded(
          child: WebsiteEditorControlTarget(
            targetKey: ValueKey<String>('website-height-preset-${preset.name}'),
            semanticLabel: 'Altura ${preset.label}',
            selected: isSelected,
            onTap: () => onHeightChanged(presetHeight),
            child: SizedBox(
              width: double.infinity,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF00A09D)
                      : const Color(0xFF2D2D2D),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color:
                        isSelected ? const Color(0xFF00A09D) : Colors.white12,
                  ),
                ),
                child: Text(
                  preset.label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white54,
                    fontSize: 11,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  bool _isPresetSelected(BlockHeightPreset preset, double? presetHeight) {
    if (preset == BlockHeightPreset.auto) {
      return currentHeight == null;
    }
    if (presetHeight == null) return false;

    // Allow some tolerance for "close enough" matches
    if (currentHeight == null) return false;
    return (currentHeight! - presetHeight).abs() < 20;
  }
}
