import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wrapper widget that handles the "first click selects, second click navigates" pattern.
///
/// In edit mode:
/// - First click: Selects the element (calls onSelect)
/// - Second click (when already selected): Executes the action (calls onAction)
///
/// In preview/normal mode:
/// - Single click executes the action immediately
class EditModeClickHandler extends StatefulWidget {
  final Widget child;
  final bool isEditMode;
  final bool isSelected;
  final VoidCallback? onSelect;
  final VoidCallback? onAction;
  final VoidCallback? onDoubleClick;
  final String? tooltip;
  final bool showEditHint;

  const EditModeClickHandler({
    super.key,
    required this.child,
    this.isEditMode = false,
    this.isSelected = false,
    this.onSelect,
    this.onAction,
    this.onDoubleClick,
    this.tooltip,
    this.showEditHint = true,
  });

  @override
  State<EditModeClickHandler> createState() => _EditModeClickHandlerState();
}

class _EditModeClickHandlerState extends State<EditModeClickHandler> {
  bool _isHovered = false;

  // Track if this element was tapped recently (for second-click detection)
  static String? _lastTappedElementId;
  static DateTime? _lastTappedTime;

  // Generate a unique ID for this widget instance
  late final String _elementId;

  @override
  void initState() {
    super.initState();
    _elementId = '${hashCode}_${DateTime.now().millisecondsSinceEpoch}';
  }

  void _handleTap() {
    if (!widget.isEditMode) {
      // Normal mode - execute action immediately
      widget.onAction?.call();
      return;
    }

    // Edit mode - check if this is a second tap on the same element
    final now = DateTime.now();
    final isSecondTap = widget.isSelected &&
        _lastTappedElementId == _elementId &&
        _lastTappedTime != null &&
        now.difference(_lastTappedTime!).inMilliseconds < 500;

    if (isSecondTap) {
      // Second tap - execute action
      widget.onAction?.call();
      _lastTappedElementId = null;
      _lastTappedTime = null;
    } else {
      // First tap - select element
      widget.onSelect?.call();
      _lastTappedElementId = _elementId;
      _lastTappedTime = now;
      HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isEditMode) {
      // Normal mode - just return child with action handler
      return GestureDetector(
        onTap: widget.onAction,
        child: widget.child,
      );
    }

    // Edit mode - show interactive states
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: _handleTap,
        onDoubleTap: widget.onDoubleClick,
        child: Stack(
          children: [
            // The actual content
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              decoration: BoxDecoration(
                border: Border.all(
                  color: widget.isSelected
                      ? const Color(0xFF00A09D)
                      : _isHovered
                          ? const Color(0xFF00A09D).withValues(alpha: 0.5)
                          : Colors.transparent,
                  width: widget.isSelected ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: widget.child,
            ),

            // Edit hint badge
            if (widget.showEditHint && _isHovered && !widget.isSelected)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00A09D).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.touch_app,
                          size: 12, color: Colors.white),
                      const SizedBox(width: 4),
                      Text(
                        widget.tooltip ?? 'Clic para editar',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Selected indicator with "click again to navigate" hint
            if (widget.isSelected && widget.onAction != null)
              Positioned(
                bottom: 4,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.mouse, size: 12, color: Colors.white70),
                        SizedBox(width: 4),
                        Text(
                          'Clic de nuevo para navegar',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A simpler version for menu items and buttons
/// Shows visual feedback but doesn't show the "click again" hint
class EditModeButton extends StatefulWidget {
  final Widget child;
  final bool isEditMode;
  final bool isSelected;
  final VoidCallback? onSelect;
  final VoidCallback? onNavigate;
  final String? editLabel;

  const EditModeButton({
    super.key,
    required this.child,
    this.isEditMode = false,
    this.isSelected = false,
    this.onSelect,
    this.onNavigate,
    this.editLabel,
  });

  @override
  State<EditModeButton> createState() => _EditModeButtonState();
}

class _EditModeButtonState extends State<EditModeButton> {
  bool _isHovered = false;
  bool _wasJustSelected = false;

  void _handleTap() {
    if (!widget.isEditMode) {
      // Normal mode - navigate immediately
      widget.onNavigate?.call();
      return;
    }

    // Edit mode
    if (widget.isSelected && !_wasJustSelected) {
      // Already selected and not just selected - navigate
      widget.onNavigate?.call();
    } else {
      // Not selected or just selected - select it
      widget.onSelect?.call();
      _wasJustSelected = true;
      // Reset after a short delay
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _wasJustSelected = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: _handleTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          decoration: widget.isEditMode
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: widget.isSelected
                        ? const Color(0xFF00A09D)
                        : _isHovered
                            ? const Color(0xFF00A09D).withValues(alpha: 0.4)
                            : Colors.transparent,
                    width: widget.isSelected ? 2 : 1,
                  ),
                  color: _isHovered && !widget.isSelected
                      ? const Color(0xFF00A09D).withValues(alpha: 0.1)
                      : null,
                )
              : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              widget.child,

              // Edit label on hover (edit mode only)
              if (widget.isEditMode && _isHovered && widget.editLabel != null)
                Positioned(
                  top: -20,
                  left: 0,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00A09D),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      widget.editLabel!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
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
}

/// Wrapper for navigation menu items in edit mode
class EditableMenuItem extends StatefulWidget {
  final String label;
  final bool isEditMode;
  final bool isSelected;
  final VoidCallback? onSelect;
  final VoidCallback? onNavigate;
  final ValueChanged<String>? onLabelChanged;
  final TextStyle? style;

  const EditableMenuItem({
    super.key,
    required this.label,
    this.isEditMode = false,
    this.isSelected = false,
    this.onSelect,
    this.onNavigate,
    this.onLabelChanged,
    this.style,
  });

  @override
  State<EditableMenuItem> createState() => _EditableMenuItemState();
}

class _EditableMenuItemState extends State<EditableMenuItem> {
  bool _isEditing = false;
  bool _isHovered = false;
  late TextEditingController _controller;
  late FocusNode _focusNode;
  int _tapCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.label);
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus && _isEditing) {
        _finishEditing();
      }
    });
  }

  @override
  void didUpdateWidget(EditableMenuItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.label != widget.label && !_isEditing) {
      _controller.text = widget.label;
    }
    // Reset tap count when selection changes
    if (oldWidget.isSelected != widget.isSelected && !widget.isSelected) {
      _tapCount = 0;
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!widget.isEditMode) {
      widget.onNavigate?.call();
      return;
    }

    _tapCount++;

    if (_tapCount == 1) {
      // First tap - select
      widget.onSelect?.call();
      // Reset tap count after delay
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _tapCount == 1) {
          _tapCount = 0;
        }
      });
    } else if (_tapCount == 2) {
      // Second tap - start inline editing
      _startEditing();
      _tapCount = 0;
    } else if (_tapCount >= 3) {
      // Third tap - navigate
      widget.onNavigate?.call();
      _tapCount = 0;
    }
  }

  void _startEditing() {
    setState(() => _isEditing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  void _finishEditing() {
    setState(() => _isEditing = false);
    if (_controller.text != widget.label && _controller.text.isNotEmpty) {
      widget.onLabelChanged?.call(_controller.text);
    } else {
      _controller.text = widget.label;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: _handleTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: widget.isEditMode
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: widget.isSelected || _isEditing
                        ? const Color(0xFF00A09D)
                        : _isHovered
                            ? const Color(0xFF00A09D).withValues(alpha: 0.4)
                            : Colors.transparent,
                    width: widget.isSelected ? 2 : 1,
                  ),
                  color: _isEditing
                      ? Colors.white.withValues(alpha: 0.95)
                      : _isHovered
                          ? const Color(0xFF00A09D).withValues(alpha: 0.1)
                          : null,
                )
              : null,
          child: _isEditing
              ? IntrinsicWidth(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    style: widget.style?.copyWith(color: Colors.black87),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _finishEditing(),
                  ),
                )
              : Text(
                  widget.label,
                  style: widget.style,
                ),
        ),
      ),
    );
  }
}
