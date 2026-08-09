import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../../../shared/widgets/vb_segmented.dart';
import 'text_formatting_toolbar.dart';
import 'website_text_block_content.dart';

/// The complete local draft produced by one inline text session.
///
/// Text, formatting and width commit together so a single interaction can
/// never create three undo steps or leave companions half-applied.
@immutable
class InlineEditableTextCommit {
  const InlineEditableTextCommit({
    required this.text,
    required this.formatting,
    required this.maxWidth,
  });

  final String text;
  final TextFormatting formatting;
  final double? maxWidth;
}

typedef InlineEditableTextSessionStart = Object? Function();
typedef InlineEditableTextSessionCommit = bool Function(
  Object session,
  InlineEditableTextCommit value,
);
typedef InlineEditableTextSessionCancel = void Function(Object session);

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
  final TextToolbarPreset toolbarPreset;
  final bool allowWidthResize;
  final EdgeInsetsGeometry editorPadding;
  final String Function(String value)? displayTransform;
  final InlineEditableTextSessionStart? onSessionStart;
  final InlineEditableTextSessionCommit? onSessionCommit;
  final InlineEditableTextSessionCancel? onSessionCancel;

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
    this.toolbarPreset = TextToolbarPreset.full,
    this.allowWidthResize = true,
    this.editorPadding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.displayTransform,
    this.onSessionStart,
    this.onSessionCommit,
    this.onSessionCancel,
  }) : assert(
          (onSessionStart == null &&
                  onSessionCommit == null &&
                  onSessionCancel == null) ||
              (onSessionStart != null &&
                  onSessionCommit != null &&
                  onSessionCancel != null),
          'Inline text transaction callbacks must be supplied together.',
        );

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
  Object? _editSession;
  late String _initialText;
  late TextFormatting _initialFormatting;
  double? _initialWidth;
  double? _resizeStartWidth;

  void _requestToolbarRebuild() {
    // OverlayEntry is not part of this widget's build tree.
    // setState() will NOT rebuild the overlay while it's open.
    // Also: markNeedsBuild cannot be called during the framework build phase.
    final entry = _toolbarEntry;
    if (entry == null) return;

    final phase = SchedulerBinding.instance.schedulerPhase;
    final canRebuildNow = phase == SchedulerPhase.idle ||
        phase == SchedulerPhase.postFrameCallbacks;

    if (canRebuildNow) {
      entry.markNeedsBuild();
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_toolbarEntry != entry) return;
      entry.markNeedsBuild();
    });
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
    _currentFormatting = widget.formatting ?? const TextFormatting();
    _currentWidth = widget.maxWidth;
    _initialText = widget.text;
    _initialFormatting = _currentFormatting;
    _initialWidth = _currentWidth;
  }

  @override
  void didUpdateWidget(InlineEditableTextV2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If we leave edit mode while the toolbar is open (or the field is focused),
    // tear down the overlay immediately. Otherwise the OverlayEntry can outlive
    // the anchor during route transitions, which can trigger framework asserts.
    final sourceChangedWhileEditing = _isEditing &&
        (oldWidget.text != widget.text ||
            !_formattingEquals(
              oldWidget.formatting ?? const TextFormatting(),
              widget.formatting ?? const TextFormatting(),
            ) ||
            oldWidget.maxWidth != widget.maxWidth);
    if ((oldWidget.isEditMode && !widget.isEditMode) ||
        sourceChangedWhileEditing) {
      _cancelEditing(updateState: false);
    }
    if (oldWidget.text != widget.text && !_isEditing) {
      _controller.text = widget.text;
    }
    if (oldWidget.formatting != widget.formatting &&
        widget.formatting != null) {
      _currentFormatting = widget.formatting!;

      // If the toolbar is open, it must be rebuilt explicitly.
      if (_isEditing && _toolbarEntry != null) {
        _requestToolbarRebuild();
      }
    }
    if (oldWidget.maxWidth != widget.maxWidth && !_isResizing) {
      _currentWidth = widget.maxWidth;
    }
  }

  @override
  void deactivate() {
    // Defensive: during AnimatedSwitcher/route transitions this widget can be
    // temporarily deactivated while still mounted. Ensure the overlay is gone.
    _cancelEditing(updateState: false);
    super.deactivate();
  }

  @override
  void dispose() {
    final session = _editSession;
    _editSession = null;
    if (session != null) widget.onSessionCancel?.call(session);
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
    final session = widget.onSessionStart?.call();
    if (widget.onSessionStart != null && session == null) return;
    _editSession = session;
    _initialText = widget.text;
    _initialFormatting = widget.formatting ?? const TextFormatting();
    _initialWidth = widget.maxWidth;
    _controller.text = widget.text;
    _currentFormatting = _initialFormatting;
    _currentWidth = _initialWidth;
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
    _focusNode.unfocus();

    if (!mounted) return;

    final session = _editSession;
    _editSession = null;
    final commit = InlineEditableTextCommit(
      text: _controller.text,
      formatting: _currentFormatting,
      maxWidth: _currentWidth,
    );
    setState(() => _isEditing = false);

    if (session != null) {
      final accepted = widget.onSessionCommit?.call(session, commit) ?? false;
      if (!accepted) _restoreLiveValues();
      return;
    }

    // Compatibility path for standalone consumers not yet backed by a
    // provider transaction. Each value still writes only when editing ends.
    if (commit.text != _initialText) {
      widget.onTextChanged?.call(commit.text);
    }
    if (!_formattingEquals(commit.formatting, _initialFormatting)) {
      widget.onFormattingChanged?.call(commit.formatting);
    }
    if (commit.maxWidth != _initialWidth && commit.maxWidth != null) {
      widget.onWidthChanged?.call(commit.maxWidth!);
    }
  }

  void _cancelEditing({bool updateState = true}) {
    final session = _editSession;
    _editSession = null;
    if (session != null) widget.onSessionCancel?.call(session);
    _hideToolbar();
    _focusNode.unfocus();
    _restoreLiveValues();
    if (updateState && mounted) setState(() => _isEditing = false);
    if (!updateState) _isEditing = false;
  }

  void _restoreLiveValues() {
    _controller.text = widget.text;
    _currentFormatting = widget.formatting ?? const TextFormatting();
    _currentWidth = widget.maxWidth;
    _isResizing = false;
    _resizeStartWidth = null;
  }

  bool _formattingEquals(TextFormatting left, TextFormatting right) =>
      mapEquals(left.toJson(), right.toJson());

  void _handleFormattingChanged(TextFormatting formatting) {
    debugPrint(
        '📝 [InlineText] Formatting changed: bold=${formatting.isBold}, size=${formatting.fontSize}');

    setState(() => _currentFormatting = formatting);

    // Force overlay repaint so controls reflect changes immediately.
    _requestToolbarRebuild();

    // Keep toolbar position reasonable after style changes.
    _scheduleToolbarReposition();

    // Return focus to text field so user can keep typing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
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
                          preset: widget.toolbarPreset,
                          transactionIdentity: (
                            _editingGroupId,
                            _editSession,
                            widget.fieldKey,
                          ),
                          onFormattingChanged: _handleFormattingChanged,
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

        // Repaint the overlay; its builder reads _toolbarPreferBelow/_toolbarDx.
        _requestToolbarRebuild();
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

  TextAlign get _effectiveTextAlign {
    // Treat TextAlign.start as "unset" so blocks can provide their own default
    // alignment (e.g. centered hero headings) until the user explicitly changes it.
    final formattedAlign = _currentFormatting.textAlign;
    return formattedAlign == TextAlign.start
        ? widget.textAlign
        : formattedAlign;
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
        textAlign: _effectiveTextAlign,
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
          child: Stack(
            key: _targetKey,
            children: [
              Padding(
                padding: widget.editorPadding,
                child: _isEditing ? _buildEditField() : _buildDisplayText(),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedContainer(
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
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // If we have a width constraint or are editing, wrap with resize capability
    if (widget.allowWidthResize && (_currentWidth != null || _isEditing)) {
      final isTouch = VbDensity.resolve(context).isTouch;
      final handleExtent = isTouch ? 48.0 : 14.0;
      Widget content = WebsiteTextWidthFrame(
        maxWidth: _currentWidth,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: isTouch ? 48 : 0),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              textContainer,
              // Left resize handle
              if (_isEditing)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: _buildResizeHandle(
                    isLeft: true,
                    targetExtent: handleExtent,
                  ),
                ),
              // Right resize handle
              if (_isEditing)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: _buildResizeHandle(
                    isLeft: false,
                    targetExtent: handleExtent,
                  ),
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

  Widget _buildResizeHandle({
    required bool isLeft,
    required double targetExtent,
  }) {
    return Semantics(
      label: isLeft
          ? 'Ajustar ancho desde el borde izquierdo'
          : 'Ajustar ancho desde el borde derecho',
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          key: ValueKey<String>(
            'website-text-width-handle-${isLeft ? 'left' : 'right'}',
          ),
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) {
            _resizeStartWidth = _currentWidth;
            setState(() => _isResizing = true);
          },
          onPanUpdate: (details) {
            setState(() {
              final delta = isLeft ? -details.delta.dx : details.delta.dx;
              // Symmetric resize - adjust both sides equally.
              final newWidth = (_currentWidth ?? 600) + (delta * 2);
              _currentWidth = newWidth.clamp(200.0, 1200.0);
            });
          },
          onPanEnd: (_) => _handleResizeEnd(),
          onPanCancel: _cancelResize,
          child: SizedBox(
            width: targetExtent,
            child: Align(
              alignment: isLeft ? Alignment.centerLeft : Alignment.centerRight,
              child: Container(
                width: 14,
                height: 32,
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
        ),
      ),
    );
  }

  void _handleResizeEnd() {
    setState(() => _isResizing = false);
    _resizeStartWidth = null;
    if (_editSession == null && _currentWidth != null) {
      widget.onWidthChanged?.call(_currentWidth!);
    }
  }

  void _cancelResize() {
    final startWidth = _resizeStartWidth;
    _resizeStartWidth = null;
    setState(() {
      _isResizing = false;
      _currentWidth = startWidth;
    });
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
            _cancelEditing();
          }
        }
      },
      child: EditableText(
        controller: _controller,
        focusNode: _focusNode,
        style: _effectiveStyle, // Keep original style including color!
        textAlign: _effectiveTextAlign,
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
    final rawDisplayText = widget.text.isEmpty
        ? (widget.placeholder ?? 'Haz clic para editar')
        : widget.text;
    final displayText = widget.text.isEmpty
        ? rawDisplayText
        : (widget.displayTransform?.call(rawDisplayText) ?? rawDisplayText);

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
          textAlign: _effectiveTextAlign,
          maxLines: widget.maxLines,
          overflow: widget.maxLines != null ? TextOverflow.ellipsis : null,
        ),
        // Edit hint on hover - small pencil icon
        if (_isHovered)
          Positioned(
            right: -4,
            top: -4,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Color(0xFF00A09D),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.edit, size: 10, color: Colors.white),
            ),
          ),
      ],
    );
  }

  void _toggleBold() {
    _handleFormattingChanged(
      _currentFormatting.copyWith(isBold: !_currentFormatting.isBold),
    );
  }

  void _toggleItalic() {
    _handleFormattingChanged(
      _currentFormatting.copyWith(isItalic: !_currentFormatting.isItalic),
    );
  }

  void _toggleUnderline() {
    _handleFormattingChanged(
      _currentFormatting.copyWith(
        isUnderline: !_currentFormatting.isUnderline,
      ),
    );
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
