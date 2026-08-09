import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../shared/widgets/vb_segmented.dart';
import '../models/website_block_definition.dart';
import '../providers/website_edit_mode_provider.dart';
import 'website_editor_chrome_geometry.dart';
import 'website_editor_control_density.dart';

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

  /// Minimum editor hit target. This may exceed [currentSpacing] only when the
  /// caller overlays the handle instead of letting it own page layout.
  final double minimumInteractiveExtent;

  const BlockSpacerHandle({
    super.key,
    required this.currentSpacing,
    this.minSpacing = 0,
    this.maxSpacing = 200,
    required this.onSpacingChanged,
    this.onSpacingChangeEnd,
    this.isActive = false,
    this.snapIncrement = 4,
    this.minimumInteractiveExtent = 0,
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
  int? _activePointer;
  bool _isArmed = false;
  bool _usesFallbackCommit = false;
  WebsiteEditModeProvider? _leaseProvider;
  WebsiteInlineManipulationLease? _lease;

  @override
  Widget build(BuildContext context) {
    if (!widget.isActive) {
      // Not in edit mode - just show the spacing
      return SizedBox(height: widget.currentSpacing);
    }

    // During drag, use local spacing; otherwise use widget's spacing
    final displaySpacing = _isDragging
        ? (_localDragSpacing ?? widget.currentSpacing)
        : widget.currentSpacing;
    final showControls = _isHovered || _isDragging;
    // The gap handle exists in the pointer composition. Contextual/touch hosts
    // edit the same value through O-05, whose controls are 48 px. A standalone
    // host with no editor geometry preserves the historical pointer contract.
    final density =
        WebsiteEditorControlDensityScope.maybeOf(context)?.density ??
            WebsiteEditorChromeScope.maybeOf(context)?.density ??
            VbDensity.compact;
    final interactiveExtent = density.isTouch
        ? density.controlHeight
        : widget.minimumInteractiveExtent;

    // Editor chrome must not change persisted page geometry. Small gaps keep
    // their exact height; the controls may paint beyond that box while active.
    final containerHeight =
        displaySpacing < interactiveExtent ? interactiveExtent : displaySpacing;

    return Semantics(
      label: 'Espacio después del bloque',
      value: '${displaySpacing.round()} píxeles',
      increasedValue:
          '${_normalizedSpacing(displaySpacing + 4).round()} píxeles',
      decreasedValue:
          '${_normalizedSpacing(displaySpacing - 4).round()} píxeles',
      onIncrease: () => _setSpacing(displaySpacing + 4),
      onDecrease: () => _setSpacing(displaySpacing - 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeRow,
        onEnter: (_) {
          if (!_isHovered) setState(() => _isHovered = true);
        },
        onExit: (_) {
          if (!_isDragging && _isHovered) {
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
            onVerticalDragCancel: _cancelInteraction,
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
                      padding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: density.isTouch ? 0 : 2,
                      ),
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
                            semanticLabel: 'Sin espacio',
                            targetExtent:
                                density.isTouch ? density.controlHeight : 24,
                            isSelected: displaySpacing == 0,
                            onTap: () => _setSpacing(0),
                          ),
                          const SizedBox(width: 4),
                          _QuickSpacingButton(
                            label: 'S',
                            semanticLabel: 'Espacio pequeño, 16 píxeles',
                            targetExtent:
                                density.isTouch ? density.controlHeight : 24,
                            isSelected:
                                displaySpacing > 0 && displaySpacing <= 16,
                            onTap: () => _setSpacing(16),
                          ),
                          const SizedBox(width: 4),
                          _QuickSpacingButton(
                            label: 'M',
                            semanticLabel: 'Espacio mediano, 32 píxeles',
                            targetExtent:
                                density.isTouch ? density.controlHeight : 24,
                            isSelected:
                                displaySpacing > 16 && displaySpacing <= 32,
                            onTap: () => _setSpacing(32),
                          ),
                          const SizedBox(width: 4),
                          _QuickSpacingButton(
                            label: 'L',
                            semanticLabel: 'Espacio grande, 64 píxeles',
                            targetExtent:
                                density.isTouch ? density.controlHeight : 24,
                            isSelected:
                                displaySpacing > 32 && displaySpacing <= 64,
                            onTap: () => _setSpacing(64),
                          ),
                          const SizedBox(width: 4),
                          _QuickSpacingButton(
                            label: 'XL',
                            semanticLabel: 'Espacio extra grande, 96 píxeles',
                            targetExtent:
                                density.isTouch ? density.controlHeight : 24,
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
                          const Icon(Icons.height,
                              size: 12, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            displaySpacing.toInt() == 0
                                ? '0'
                                : '${displaySpacing.toInt()}px',
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
        ),
      ),
    );
  }

  void _setSpacing(double spacing) {
    if (!_isArmed) _armInteraction();
    if (!_isArmed) return;
    _completeInteraction(_normalizedSpacing(spacing));
    HapticFeedback.selectionClick();
  }

  WebsiteEditModeProvider? _maybeProvider() {
    try {
      return Provider.of<WebsiteEditModeProvider>(context, listen: false);
    } on ProviderNotFoundException {
      return null;
    }
  }

  void _armInteraction() {
    if (_isArmed) return;
    _isArmed = true;
    _usesFallbackCommit = true;
    final provider = _maybeProvider();
    if (provider == null) return;

    final generation = provider.prepareInlineManipulationArm(
      WebsiteInlineManipulationProperty.fromSchema(
        WebsiteBlockMetaFields.spacingAfter,
      ),
    );
    if (generation == null) return;

    // PageComposition's legacy callback is the only owner of the block id.
    // The provider consumes this exact same-value call as a target handshake;
    // it cannot dirty the page or add history.
    widget.onSpacingChanged(widget.currentSpacing);
    final lease = provider.inlineManipulationSession;
    if (lease?.generation != generation ||
        lease?.target.properties.length != 1 ||
        lease?.target.properties.first.canonicalKey !=
            WebsiteBlockMetaFields.spacingAfter.key) {
      provider.abandonPreparedInlineManipulationArm(generation);
      return;
    }
    _usesFallbackCommit = false;
    _leaseProvider = provider;
    _lease = lease;
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    _armInteraction();
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_activePointer != event.pointer) return;
    _activePointer = null;
    if (_isDragging) return;
    // Tap recognizers (the preset buttons) resolve after raw pointer-up. Give
    // them the same event turn to consume the arm before treating this as a
    // cancelled drag.
    Future<void>.microtask(() {
      if (mounted && _isArmed && !_isDragging) _cancelInteraction();
    });
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_activePointer != event.pointer) return;
    _cancelInteraction();
  }

  void _onDragStart(DragStartDetails details) {
    if (!_isArmed) return;
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

    newSpacing = _normalizedSpacing(newSpacing);

    setState(() {
      _localDragSpacing = newSpacing;
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final finalSpacing = _localDragSpacing ?? widget.currentSpacing;

    _completeInteraction(finalSpacing);
    HapticFeedback.mediumImpact();
  }

  double _normalizedSpacing(double spacing) {
    var result = spacing.clamp(widget.minSpacing, widget.maxSpacing);
    if (widget.snapIncrement != null && widget.snapIncrement! > 0) {
      result = (result / widget.snapIncrement!).round() * widget.snapIncrement!;
    }
    return result;
  }

  void _completeInteraction(double spacing) {
    final lease = _lease;
    final provider = _leaseProvider;
    final fallback = _usesFallbackCommit;
    _clearInteractionState();
    if (lease != null && provider != null) {
      provider.commitInlineManipulation(
        lease,
        <String, Object?>{
          WebsiteBlockMetaFields.spacingAfter.key: spacing,
        },
      );
    } else if (fallback) {
      widget.onSpacingChanged(spacing);
    }
    widget.onSpacingChangeEnd?.call(spacing);
  }

  void _cancelInteraction() {
    final lease = _lease;
    final provider = _leaseProvider;
    _clearInteractionState();
    if (lease != null && provider != null) {
      provider.cancelInlineManipulation(lease);
    }
  }

  void _clearInteractionState() {
    _lease = null;
    _leaseProvider = null;
    _usesFallbackCommit = false;
    _isArmed = false;
    _activePointer = null;
    if (!mounted) return;
    setState(() {
      _isDragging = false;
      _isHovered = false;
      _localDragSpacing = null;
    });
  }

  @override
  void dispose() {
    final lease = _lease;
    final provider = _leaseProvider;
    _lease = null;
    if (lease != null && provider != null) {
      provider.cancelInlineManipulation(lease);
    }
    super.dispose();
  }
}

/// Quick spacing preset button
class _QuickSpacingButton extends StatelessWidget {
  final String label;
  final String semanticLabel;
  final double targetExtent;
  final bool isSelected;
  final VoidCallback onTap;

  const _QuickSpacingButton({
    required this.label,
    required this.semanticLabel,
    required this.targetExtent,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: semanticLabel,
      child: GestureDetector(
        key: ValueKey<String>('website-spacing-preset-$label'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: targetExtent,
          height: targetExtent < 20 ? 20 : targetExtent,
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
      ),
    );
  }
}
