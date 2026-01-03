import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'text_formatting_toolbar.dart';

/// Enhanced inline editable text widget with formatting toolbar.
/// When in edit mode, clicking on text shows a formatting toolbar
/// and allows direct text editing.
class InlineEditableTextV2 extends StatefulWidget {
  final String text;
  final TextStyle? baseStyle;
  final TextAlign textAlign;
  final int? maxLines;
  final bool isEditMode;
  final ValueChanged<String>? onTextChanged;
  final ValueChanged<TextFormatting>? onFormattingChanged;
  final ValueChanged<double>? onWidthChanged; // Callback when width is resized
  final String? placeholder;
  final TextFormatting? formatting;
  final String? fieldKey; // Unique key to identify this field
  final double? maxWidth; // Optional max width constraint for the text box

  const InlineEditableTextV2({
    super.key,
    required this.text,
    this.baseStyle,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.isEditMode = false,
    this.onTextChanged,
    this.onFormattingChanged,
    this.onWidthChanged,
    this.placeholder,
    this.formatting,
    this.fieldKey,
    this.maxWidth,
  });

  @override
  State<InlineEditableTextV2> createState() => _InlineEditableTextV2State();
}

class _InlineEditableTextV2State extends State<InlineEditableTextV2> {
  bool _isEditing = false;
  bool _isHovered = false;
  bool _isResizing = false;
  double? _currentWidth;
  late TextEditingController _controller;
  late FocusNode _focusNode;
  OverlayEntry? _toolbarEntry;
  final GlobalKey _toolbarKey = GlobalKey(); // Key to check toolbar hits
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _targetKey = GlobalKey();
  bool _toolbarPreferBelow = false;
  double _toolbarDx = 0;
  late TextFormatting _currentFormatting;
  final Object _editingGroupId = Object(); // Unique group ID for this editor

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
    _currentFormatting = widget.formatting ?? const TextFormatting();
    _currentWidth = widget.maxWidth;
  }

  @override
  void didUpdateWidget(InlineEditableTextV2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text && !_isEditing) {
      _controller.text = widget.text;
    }
    if (oldWidget.formatting != widget.formatting &&
        widget.formatting != null) {
      _currentFormatting = widget.formatting!;
    }
    if (oldWidget.maxWidth != widget.maxWidth && _currentWidth == null) {
      _currentWidth = widget.maxWidth;
    }
  }

  @override
  void dispose() {
    _hideToolbar();
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    // Don't use focus change to close - we'll use TapRegion instead
  }

  void _startEditing() {
    if (!widget.isEditMode) return;
    debugPrint('📝 [InlineText] Starting edit mode');
    setState(() => _isEditing = true);

    // Use Future.delayed to ensure we are completely out of the layout/build phase
    // and the GlobalKey reparenting is stable.
    Future.delayed(Duration.zero, () {
      if (!mounted) return;
      _focusNode.requestFocus();
      // Select all text for easy replacement
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
      _scheduleToolbarReposition();
      _showToolbar();
    });

    HapticFeedback.selectionClick();
  }

  void _finishEditing() {
    debugPrint('📝 [InlineText] Finishing edit');
    _hideToolbar();

    if (!mounted) return;

    setState(() => _isEditing = false);

    if (_controller.text != widget.text) {
      widget.onTextChanged?.call(_controller.text);
    }
  }

  void _showToolbar() {
    debugPrint('📝 [InlineText] Showing toolbar');
    if (_toolbarEntry != null) return;

    final overlayState = Overlay.maybeOf(context, rootOverlay: true);
    if (overlayState == null) return;

    _toolbarEntry = OverlayEntry(
      builder: (context) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final toolbarWidth = (screenWidth - 20).clamp(280.0, 420.0);

        return Positioned.fill(
          child: IgnorePointer(
            ignoring: !_isEditing,
            child: Stack(
              children: [
                CompositedTransformFollower(
                  link: _layerLink,
                  showWhenUnlinked: false,
                  targetAnchor: _toolbarPreferBelow
                      ? Alignment.bottomCenter
                      : Alignment.topCenter,
                  followerAnchor: _toolbarPreferBelow
                      ? Alignment.topCenter
                      : Alignment.bottomCenter,
                  offset: Offset(_toolbarDx, _toolbarPreferBelow ? 12 : -12),
                  child: Material(
                    color: Colors.transparent,
                    child: SizedBox(
                      key: _toolbarKey,
                      width: toolbarWidth,
                      child: TapRegion(
                        groupId: _editingGroupId,
                        child: TextFormattingToolbar(
                          currentFormatting: _currentFormatting,
                          baseStyle: widget.baseStyle,
                          onFormattingChanged: (formatting) {
                            setState(() => _currentFormatting = formatting);
                            widget.onFormattingChanged?.call(formatting);

                            // Keep toolbar position reasonable after style changes.
                            _scheduleToolbarReposition();

                            // Return focus to text field so user can keep typing.
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) _focusNode.requestFocus();
                            });
                          },
                          onClose: _finishEditing,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    overlayState.insert(_toolbarEntry!);
  }

  void _scheduleToolbarReposition() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isEditing) return;

      final targetContext = _targetKey.currentContext;
      final renderObject = targetContext?.findRenderObject();
      if (renderObject is! RenderBox ||
          !renderObject.attached ||
          !renderObject.hasSize) {
        return;
      }

      final position = renderObject.localToGlobal(Offset.zero);
      final size = renderObject.size;
      final screenSize = MediaQuery.sizeOf(context);

      final toolbarWidth = (screenSize.width - 20).clamp(280.0, 420.0);

      // If we are too close to the top, show the toolbar below.
      final preferBelow = position.dy < 90;

      // Clamp horizontally by nudging the follower's dx.
      final centerX = position.dx + (size.width / 2);
      final minCenterX = 10.0 + (toolbarWidth / 2);
      final maxCenterX = screenSize.width - 10.0 - (toolbarWidth / 2);
      final clampedCenterX = centerX.clamp(minCenterX, maxCenterX);
      final dx = clampedCenterX - centerX;

      if (preferBelow != _toolbarPreferBelow || (dx - _toolbarDx).abs() > 0.5) {
        setState(() {
          _toolbarPreferBelow = preferBelow;
          _toolbarDx = dx;
        });
      }
    });
  }

  void _hideToolbar() {
    final entry = _toolbarEntry;
    if (entry == null) return;
    _toolbarEntry = null;
    entry.remove();
  }

  TextStyle get _effectiveStyle {
    final baseStyle = widget.baseStyle ?? const TextStyle(fontSize: 16);
    return _currentFormatting.applyTo(baseStyle);
  }

  @override
  Widget build(BuildContext context) {
    // Avoid OverlayPortal here: it triggers a framework layout assert on iOS.
    // We manage a standard OverlayEntry in _showToolbar/_hideToolbar.
    return _buildContent();
  }

  Widget _buildContent() {
    if (!widget.isEditMode) {
      // Normal display mode - just show the text
      return Text(
        widget.text.isEmpty ? (widget.placeholder ?? '') : widget.text,
        style: widget.text.isEmpty
            ? _effectiveStyle.copyWith(
                color: _effectiveStyle.color?.withValues(alpha: 0.5),
                fontStyle: FontStyle.italic,
              )
            : _effectiveStyle,
        textAlign: widget.textAlign,
        maxLines: widget.maxLines,
        overflow: widget.maxLines != null ? TextOverflow.ellipsis : null,
      );
    }

    // Edit mode - transparent background, preserve text color
    // Wrap in Stack for resize handles when editing
    Widget textContainer = CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        cursor: _isResizing
            ? SystemMouseCursors.resizeColumn
            : SystemMouseCursors.text,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: _isEditing ? null : _startEditing,
          child: AnimatedContainer(
            key: _targetKey,
            duration: const Duration(milliseconds: 150),
            decoration: BoxDecoration(
              border: Border.all(
                color: _isEditing
                    ? const Color(0xFF00A09D)
                    : _isHovered
                        ? const Color(0xFF00A09D).withValues(alpha: 0.5)
                        : Colors.transparent,
                width: _isEditing ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(4),
              // NO background color - keep transparent
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: _isEditing ? _buildEditField() : _buildDisplayText(),
          ),
        ),
      ),
    );

    // If we have a width constraint or are editing, wrap with resize capability
    if (_currentWidth != null || _isEditing) {
      Widget content = Center(
        child: SizedBox(
          width: _currentWidth,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              textContainer,
              // Left resize handle
              if (_isEditing)
                Positioned(
                  left: -6,
                  top: 0,
                  bottom: 0,
                  child: _buildResizeHandle(isLeft: true),
                ),
              // Right resize handle
              if (_isEditing)
                Positioned(
                  right: -6,
                  top: 0,
                  bottom: 0,
                  child: _buildResizeHandle(isLeft: false),
                ),
            ],
          ),
        ),
      );

      // Wrap with TapRegion when editing to detect outside clicks
      if (_isEditing) {
        return TapRegion(
          groupId: _editingGroupId,
          onTapOutside: (event) {
            // Check if tap was on toolbar
            final toolbarBox =
                _toolbarKey.currentContext?.findRenderObject() as RenderBox?;
            if (toolbarBox != null &&
                toolbarBox.attached &&
                toolbarBox.hasSize) {
              try {
                final local = toolbarBox.globalToLocal(event.position);
                if (toolbarBox.paintBounds.contains(local)) {
                  return; // Tap was on toolbar, ignore
                }
              } catch (e) {
                // Ignore error if toolbar layout is unstable
              }
            }

            if (!_isResizing) {
              _finishEditing();
            }
          },
          child: content,
        );
      }

      return content;
    }

    // Also wrap simple case with TapRegion
    if (_isEditing) {
      return TapRegion(
        groupId: _editingGroupId,
        onTapOutside: (event) {
          // Check if tap was on toolbar
          final toolbarBox =
              _toolbarKey.currentContext?.findRenderObject() as RenderBox?;
          if (toolbarBox != null && toolbarBox.attached && toolbarBox.hasSize) {
            try {
              final local = toolbarBox.globalToLocal(event.position);
              if (toolbarBox.paintBounds.contains(local)) {
                return; // Tap was on toolbar, ignore
              }
            } catch (e) {
              // Ignore error if toolbar layout is unstable
            }
          }

          if (!_isResizing) {
            _finishEditing();
          }
        },
        child: textContainer,
      );
    }

    return textContainer;
  }

  Widget _buildResizeHandle({required bool isLeft}) {
    return GestureDetector(
      // Use behavior to capture all pointer events
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) {
        setState(() => _isResizing = true);
      },
      onPanUpdate: (details) {
        setState(() {
          final delta = isLeft ? -details.delta.dx : details.delta.dx;
          // Symmetric resize - adjust both sides equally
          final newWidth = (_currentWidth ?? 600) + (delta * 2);
          _currentWidth = newWidth.clamp(200.0, 1200.0);
        });
      },
      onPanEnd: (_) {
        _handleResizeEnd();
      },
      onPanCancel: () {
        _handleResizeEnd();
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Listener(
          onPointerDown: (_) {
            setState(() => _isResizing = true);
          },
          onPointerUp: (_) {
            // Reset resizing flag after a short delay to allow pan gestures to complete
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted && _isResizing) {
                _handleResizeEnd();
              }
            });
          },
          child: Container(
            width: 14,
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF00A09D),
              borderRadius: BorderRadius.circular(3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.drag_indicator, size: 12, color: Colors.white),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleResizeEnd() {
    setState(() => _isResizing = false);
    if (_currentWidth != null) {
      widget.onWidthChanged?.call(_currentWidth!);
    }
  }

  Widget _buildEditField() {
    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: (event) {
        // Handle keyboard shortcuts
        if (event is KeyDownEvent) {
          final isCtrlOrCmd = HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed;

          if (isCtrlOrCmd) {
            if (event.logicalKey == LogicalKeyboardKey.keyB) {
              _toggleBold();
            } else if (event.logicalKey == LogicalKeyboardKey.keyI) {
              _toggleItalic();
            } else if (event.logicalKey == LogicalKeyboardKey.keyU) {
              _toggleUnderline();
            }
          }

          // Enter to finish (unless multiline)
          if (event.logicalKey == LogicalKeyboardKey.enter &&
              widget.maxLines == 1) {
            _finishEditing();
          }

          // Escape to cancel
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            _controller.text = widget.text; // Revert
            _finishEditing();
          }
        }
      },
      child: EditableText(
        controller: _controller,
        focusNode: _focusNode,
        style: _effectiveStyle, // Keep original style including color!
        textAlign: widget.textAlign, // Keep original alignment!
        maxLines: widget.maxLines,
        cursorColor: const Color(0xFF00A09D),
        backgroundCursorColor: Colors.grey,
        selectionColor: const Color(0xFF00A09D).withValues(alpha: 0.3),
        // DON'T call onTextChanged during editing - it causes rebuild and focus loss
        // Text will be saved when editing finishes
        onChanged: (_) {},
      ),
    );
  }

  Widget _buildDisplayText() {
    final displayText = widget.text.isEmpty
        ? (widget.placeholder ?? 'Haz clic para editar')
        : widget.text;

    return Stack(
      children: [
        Text(
          displayText,
          style: widget.text.isEmpty
              ? _effectiveStyle.copyWith(
                  color: _effectiveStyle.color?.withValues(alpha: 0.5),
                  fontStyle: FontStyle.italic,
                )
              : _effectiveStyle,
          textAlign: widget.textAlign, // Keep original alignment!
          maxLines: widget.maxLines,
          overflow: widget.maxLines != null ? TextOverflow.ellipsis : null,
        ),
        // Edit hint on hover - small pencil icon
        if (_isHovered)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              padding: EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Color(0xFF00A09D),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.edit, size: 10, color: Colors.white),
            ),
          ),
      ],
    );
  }

  void _toggleBold() {
    setState(() {
      _currentFormatting = _currentFormatting.copyWith(
        isBold: !_currentFormatting.isBold,
      );
    });
    widget.onFormattingChanged?.call(_currentFormatting);
  }

  void _toggleItalic() {
    setState(() {
      _currentFormatting = _currentFormatting.copyWith(
        isItalic: !_currentFormatting.isItalic,
      );
    });
    widget.onFormattingChanged?.call(_currentFormatting);
  }

  void _toggleUnderline() {
    setState(() {
      _currentFormatting = _currentFormatting.copyWith(
        isUnderline: !_currentFormatting.isUnderline,
      );
    });
    widget.onFormattingChanged?.call(_currentFormatting);
  }
}

/// A simplified inline editable text for quick editing without full formatting.
/// Use this for short texts like button labels.
class SimpleInlineEditableText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final bool isEditMode;
  final ValueChanged<String>? onChanged;
  final String? placeholder;

  const SimpleInlineEditableText({
    super.key,
    required this.text,
    this.style,
    this.isEditMode = false,
    this.onChanged,
    this.placeholder,
  });

  @override
  State<SimpleInlineEditableText> createState() =>
      _SimpleInlineEditableTextState();
}

class _SimpleInlineEditableTextState extends State<SimpleInlineEditableText> {
  bool _isEditing = false;
  bool _isHovered = false;
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(SimpleInlineEditableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text && !_isEditing) {
      _controller.text = widget.text;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus && _isEditing) {
      _finishEditing();
    }
  }

  void _startEditing() {
    if (!widget.isEditMode) return;
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
    if (_controller.text != widget.text) {
      widget.onChanged?.call(_controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isEditMode) {
      return Text(
        widget.text.isEmpty ? (widget.placeholder ?? '') : widget.text,
        style: widget.style,
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.text,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: _isEditing ? null : _startEditing,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: _isEditing || _isHovered
                  ? const Color(0xFF00A09D)
                  : Colors.transparent,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: _isEditing
              ? IntrinsicWidth(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    style: widget.style,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _finishEditing(),
                  ),
                )
              : Text(
                  widget.text.isEmpty
                      ? (widget.placeholder ?? 'Editar')
                      : widget.text,
                  style: widget.text.isEmpty
                      ? widget.style?.copyWith(
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        )
                      : widget.style,
                ),
        ),
      ),
    );
  }
}
