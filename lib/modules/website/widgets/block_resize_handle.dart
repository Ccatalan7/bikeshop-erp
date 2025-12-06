import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  
  /// Callback when drag ends (final value)
  final ValueChanged<double>? onHeightChangeEnd;
  
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
    this.onHeightChangeEnd,
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

  @override
  Widget build(BuildContext context) {
    // Only show when active (block is selected)
    if (!widget.isActive) {
      return const SizedBox.shrink();
    }

    // During drag, use local drag height; otherwise use widget's currentHeight
    final displayHeight = _isDragging ? _currentDragHeight : widget.currentHeight;
    final showHeight = (_isHovered || _isDragging) && displayHeight != null;
    final showResetButton = _isHovered && !_isDragging && widget.currentHeight != null && widget.onResetHeight != null;

    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) {
        if (!_isDragging) {
          setState(() => _isHovered = false);
        }
      },
      child: GestureDetector(
        onVerticalDragStart: _onDragStart,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
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
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00A09D),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '${displayHeight!.toStringAsFixed(0)}px',
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
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF00A09D).withValues(alpha: 0.3)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.restart_alt, size: 12, color: Color(0xFF00A09D)),
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
    );
  }

  void _onDragStart(DragStartDetails details) {
    // Use currentHeight if set, otherwise use actualHeight (measured), otherwise minHeight
    final startHeight = widget.currentHeight ?? widget.actualHeight ?? widget.minHeight;
    setState(() {
      _isDragging = true;
      _dragStartY = details.globalPosition.dy;
      _dragStartHeight = startHeight;
      _currentDragHeight = startHeight;
    });
    // Immediately commit initial height to Provider (captures auto → explicit transition)
    widget.onHeightChanged(startHeight);
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

    // Apply min/max constraints
    newHeight = newHeight.clamp(
      widget.minHeight,
      widget.maxHeight ?? double.infinity,
    );

    // Apply snap increment if specified
    if (widget.snapIncrement != null && widget.snapIncrement! > 0) {
      newHeight = (newHeight / widget.snapIncrement!).round() * widget.snapIncrement!;
    }

    // Update local state only (don't trigger Provider rebuild during drag)
    setState(() {
      _currentDragHeight = newHeight;
    });
    
    // Still call the callback to update the actual block height in real-time
    widget.onHeightChanged(newHeight);
  }

  void _onDragEnd(DragEndDetails details) {
    final finalHeight = _currentDragHeight;
    setState(() {
      _isDragging = false;
      _isHovered = false;
      _currentDragHeight = null;
    });
    
    if (widget.onHeightChangeEnd != null && finalHeight != null) {
      widget.onHeightChangeEnd!(finalHeight);
    }
    HapticFeedback.mediumImpact();
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
        return 200;
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
          child: GestureDetector(
            onTap: () => onHeightChanged(presetHeight),
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
                  color: isSelected 
                      ? const Color(0xFF00A09D) 
                      : Colors.white12,
                ),
              ),
              child: Text(
                preset.label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.white54,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
                textAlign: TextAlign.center,
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
