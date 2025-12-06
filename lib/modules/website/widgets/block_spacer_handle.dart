import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A minimalist spacer handle between website blocks in edit mode.
/// 
/// Appears as a subtle horizontal divider between blocks.
/// When hovered, shows resize controls. Dragging vertically
/// resizes the gap between blocks (can go to 0).
class BlockSpacerHandle extends StatefulWidget {
  /// Current spacing height (gap between blocks)
  final double currentSpacing;
  
  /// Minimum allowed spacing (can be 0)
  final double minSpacing;
  
  /// Maximum allowed spacing
  final double maxSpacing;
  
  /// Callback when spacing changes during drag
  final ValueChanged<double> onSpacingChanged;
  
  /// Callback when drag ends (final value)
  final ValueChanged<double>? onSpacingChangeEnd;
  
  /// Whether the handle is active (edit mode)
  final bool isActive;
  
  /// Spacing snap increments (e.g., 4 = snaps to 4px increments)
  final double? snapIncrement;

  const BlockSpacerHandle({
    super.key,
    required this.currentSpacing,
    this.minSpacing = 0,
    this.maxSpacing = 200,
    required this.onSpacingChanged,
    this.onSpacingChangeEnd,
    this.isActive = false,
    this.snapIncrement = 4,
  });

  @override
  State<BlockSpacerHandle> createState() => _BlockSpacerHandleState();
}

class _BlockSpacerHandleState extends State<BlockSpacerHandle> {
  bool _isHovered = false;
  bool _isDragging = false;
  double _dragStartY = 0;
  double _dragStartSpacing = 0;
  double? _localDragSpacing;

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      // Not in edit mode - just show the spacing
      return SizedBox(height: widget.currentSpacing);
    }

    // During drag, use local spacing; otherwise use widget's spacing
    final displaySpacing = _isDragging ? (_localDragSpacing ?? widget.currentSpacing) : widget.currentSpacing;
    final showControls = _isHovered || _isDragging;
    
    // Simple fix: always have a minimum height for hit testing (16px)
    // This is the ACTUAL container height - no tricks with positioned elements
    const minInteractiveHeight = 16.0;
    final containerHeight = displaySpacing < minInteractiveHeight ? minInteractiveHeight : displaySpacing;
    
    return MouseRegion(
      cursor: SystemMouseCursors.resizeRow,
      onEnter: (_) {
        if (!_isHovered) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (!_isDragging && _isHovered) {
          setState(() => _isHovered = false);
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: _onDragStart,
        onVerticalDragUpdate: _onDragUpdate,
        onVerticalDragEnd: _onDragEnd,
        child: Container(
          height: containerHeight,
          decoration: BoxDecoration(
            color: showControls 
                ? const Color(0xFF00A09D).withValues(alpha: 0.1) 
                : Colors.transparent,
          ),
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none, // Allow controls to overflow
            children: [
              // Center line indicator - always visible when not showing controls
              if (!showControls)
                Container(
                  width: 50,
                  height: 2,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00A09D).withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              // Controls row - centered, all in one row
              if (showControls)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00A09D).withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Quick spacing buttons
                      _QuickSpacingButton(
                        label: '0',
                        isSelected: displaySpacing == 0,
                        onTap: () => _setSpacing(0),
                      ),
                      const SizedBox(width: 4),
                      _QuickSpacingButton(
                        label: 'S',
                        isSelected: displaySpacing > 0 && displaySpacing <= 16,
                        onTap: () => _setSpacing(16),
                      ),
                      const SizedBox(width: 4),
                      _QuickSpacingButton(
                        label: 'M',
                        isSelected: displaySpacing > 16 && displaySpacing <= 32,
                        onTap: () => _setSpacing(32),
                      ),
                      const SizedBox(width: 4),
                      _QuickSpacingButton(
                        label: 'L',
                        isSelected: displaySpacing > 32 && displaySpacing <= 64,
                        onTap: () => _setSpacing(64),
                      ),
                      const SizedBox(width: 4),
                      _QuickSpacingButton(
                        label: 'XL',
                        isSelected: displaySpacing > 64,
                        onTap: () => _setSpacing(96),
                      ),
                      // Divider
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        width: 1,
                        height: 16,
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                      // Spacing value indicator
                      const Icon(Icons.height, size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        displaySpacing.toInt() == 0 ? '0' : '${displaySpacing.toInt()}px',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _setSpacing(double spacing) {
    widget.onSpacingChanged(spacing);
    widget.onSpacingChangeEnd?.call(spacing);
    HapticFeedback.selectionClick();
  }

  void _onDragStart(DragStartDetails details) {
    setState(() {
      _isDragging = true;
      _dragStartY = details.globalPosition.dy;
      _dragStartSpacing = widget.currentSpacing;
      _localDragSpacing = widget.currentSpacing;
    });
    HapticFeedback.lightImpact();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;

    final delta = details.globalPosition.dy - _dragStartY;
    var newSpacing = _dragStartSpacing + delta;

    // Apply min/max constraints
    newSpacing = newSpacing.clamp(widget.minSpacing, widget.maxSpacing);

    // Apply snap increment if specified
    if (widget.snapIncrement != null && widget.snapIncrement! > 0) {
      newSpacing = (newSpacing / widget.snapIncrement!).round() * widget.snapIncrement!;
    }

    setState(() {
      _localDragSpacing = newSpacing;
    });
    
    widget.onSpacingChanged(newSpacing);
  }

  void _onDragEnd(DragEndDetails details) {
    final finalSpacing = _localDragSpacing ?? widget.currentSpacing;
    
    setState(() {
      _isDragging = false;
      _isHovered = false;
      _localDragSpacing = null;
    });
    
    widget.onSpacingChangeEnd?.call(finalSpacing);
    HapticFeedback.mediumImpact();
  }
}

/// Quick spacing preset button
class _QuickSpacingButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _QuickSpacingButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 20,
        decoration: BoxDecoration(
          color: isSelected 
              ? const Color(0xFF00A09D)
              : Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected 
                ? const Color(0xFF00A09D)
                : const Color(0xFF00A09D).withValues(alpha: 0.3),
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF00A09D),
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
