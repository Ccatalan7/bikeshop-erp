import 'package:flutter/material.dart';

/// Inline editable text widget for Odoo-style editing.
/// When edit mode is active, clicking on text allows direct editing.
class InlineEditableText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final TextAlign textAlign;
  final int? maxLines;
  final bool isEditMode;
  final ValueChanged<String>? onChanged;
  final String? placeholder;

  const InlineEditableText({
    super.key,
    required this.text,
    this.style,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.isEditMode = false,
    this.onChanged,
    this.placeholder,
  });

  @override
  State<InlineEditableText> createState() => _InlineEditableTextState();
}

class _InlineEditableTextState extends State<InlineEditableText> {
  bool _isEditing = false;
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
  void didUpdateWidget(InlineEditableText oldWidget) {
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
    setState(() {
      _isEditing = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    });
  }

  void _finishEditing() {
    setState(() {
      _isEditing = false;
    });
    if (_controller.text != widget.text) {
      widget.onChanged?.call(_controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isEditMode) {
      // Normal display mode
      return Text(
        widget.text.isEmpty ? (widget.placeholder ?? '') : widget.text,
        style: widget.text.isEmpty
            ? widget.style?.copyWith(
                color: widget.style?.color?.withValues(alpha: 0.5),
                fontStyle: FontStyle.italic,
              )
            : widget.style,
        textAlign: widget.textAlign,
        maxLines: widget.maxLines,
        overflow: widget.maxLines != null ? TextOverflow.ellipsis : null,
      );
    }

    // Edit mode - show editable field or clickable text
    if (_isEditing) {
      return TextField(
        controller: _controller,
        focusNode: _focusNode,
        style: widget.style,
        textAlign: widget.textAlign,
        maxLines: widget.maxLines,
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Colors.blue, width: 2),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Colors.blue, width: 2),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: Colors.blue, width: 2),
          ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.9),
        ),
        onSubmitted: (_) => _finishEditing(),
        onTapOutside: (_) => _finishEditing(),
      );
    }

    // Clickable text with edit hint
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: GestureDetector(
        onTap: _startEditing,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: Colors.blue.withValues(alpha: 0.3),
              width: 1,
              strokeAlign: BorderSide.strokeAlignOutside,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(
            widget.text.isEmpty
                ? (widget.placeholder ?? 'Haz clic para editar')
                : widget.text,
            style: widget.text.isEmpty
                ? widget.style?.copyWith(
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  )
                : widget.style,
            textAlign: widget.textAlign,
            maxLines: widget.maxLines,
            overflow: widget.maxLines != null ? TextOverflow.ellipsis : null,
          ),
        ),
      ),
    );
  }
}
