import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/website_action.dart';
import '../providers/website_edit_mode_provider.dart';
import 'website_link_value_editor.dart';
import 'website_media_picker.dart';

/// Universal editor for a visible website button/action.
///
/// All banner, carousel, block, repeater, and canvas action controls should use
/// this widget so improvements to action labels and destinations land once.
class WebsiteActionEditor extends StatefulWidget {
  const WebsiteActionEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.title = 'Acción principal',
    this.darkStyle = true,
    this.dense = true,
    this.showVariant = false,
    this.asyncBinding,
  });

  final WebsiteActionValue value;
  final Function(WebsiteActionValue) onChanged;
  final String title;
  final bool darkStyle;
  final bool dense;
  final bool showVariant;

  /// Exact authority shared by every asynchronous child of this action.
  final WebsiteAsyncFieldBinding? asyncBinding;

  @override
  State<WebsiteActionEditor> createState() => _WebsiteActionEditorState();
}

class _WebsiteActionEditorState extends State<WebsiteActionEditor> {
  late final TextEditingController _labelController;
  final FocusNode _labelFocusNode = FocusNode();
  WebsiteContinuousFieldArm? _continuousLabelArm;
  WebsiteAsyncFieldBinding? _openingLabelBinding;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.value.label);
    _labelFocusNode.addListener(_handleLabelFocusChanged);
  }

  @override
  void didUpdateWidget(covariant WebsiteActionEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ownerChanged =
        oldWidget.asyncBinding?.identity != widget.asyncBinding?.identity;
    if (ownerChanged && _continuousLabelArm != null) {
      _cancelLabelEdit(
        liveBinding: widget.asyncBinding ?? oldWidget.asyncBinding,
      );
    }
    if (widget.value.label != _labelController.text &&
        widget.value.label != oldWidget.value.label) {
      if (_continuousLabelArm != null) {
        _cancelLabelEdit(liveBinding: widget.asyncBinding);
      }
      _labelController.value = TextEditingValue(
        text: widget.value.label,
        selection: TextSelection.collapsed(offset: widget.value.label.length),
      );
    }
  }

  @override
  void dispose() {
    _finishLabelEdit();
    _labelFocusNode
      ..removeListener(_handleLabelFocusChanged)
      ..dispose();
    _labelController.dispose();
    super.dispose();
  }

  void _handleLabelFocusChanged() {
    if (_labelFocusNode.hasFocus) {
      _beginLabelEdit();
    } else {
      _finishLabelEdit();
    }
  }

  void _beginLabelEdit() {
    if (_continuousLabelArm != null) return;
    final binding = widget.asyncBinding;
    final begin = binding?.beginContinuous;
    if (binding == null || begin == null) return;
    final arm = begin(widget.value.label);
    if (arm == null) return;
    _continuousLabelArm = arm;
    _openingLabelBinding = binding;
  }

  void _publishLabel(String label) {
    if (_continuousLabelArm == null) _beginLabelEdit();
    final arm = _continuousLabelArm;
    final binding = widget.asyncBinding;
    final update = binding?.updateContinuous;
    if (arm != null && update != null) {
      final result = update(arm, label, () {
        final callbackResult =
            widget.onChanged(widget.value.copyWith(label: label));
        return callbackResult is WebsiteInlineMutationResult
            ? callbackResult
            : WebsiteInlineMutationResult.committed;
      });
      if (!result.accepted) {
        _continuousLabelArm = null;
        _openingLabelBinding = null;
        _restoreLabel();
      }
      return;
    }
    if (widget.asyncBinding != null) return;
    widget.onChanged(widget.value.copyWith(label: label));
  }

  void _finishLabelEdit() {
    final arm = _continuousLabelArm;
    final binding = widget.asyncBinding ?? _openingLabelBinding;
    _continuousLabelArm = null;
    _openingLabelBinding = null;
    if (arm == null) return;
    final result = binding?.finishContinuous?.call(arm);
    if (result == WebsiteInlineMutationResult.rejected) _restoreLabel();
  }

  void _cancelLabelEdit({WebsiteAsyncFieldBinding? liveBinding}) {
    final arm = _continuousLabelArm;
    final binding = liveBinding ?? widget.asyncBinding ?? _openingLabelBinding;
    _continuousLabelArm = null;
    _openingLabelBinding = null;
    if (arm != null) binding?.cancelContinuous?.call(arm);
    _restoreLabel();
  }

  void _restoreLabel() {
    if (_labelController.text == widget.value.label) return;
    _labelController.value = TextEditingValue(
      text: widget.value.label,
      selection: TextSelection.collapsed(offset: widget.value.label.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final onChanged = widget.onChanged;
    final foreground = widget.darkStyle ? Colors.white70 : Colors.grey.shade700;
    final fill = widget.darkStyle
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.grey.shade100;
    final border = widget.darkStyle
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.grey.shade300;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.title.isNotEmpty) ...[
          Text(
            widget.title.toUpperCase(),
            style: TextStyle(
              color: foreground,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Focus(
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              _cancelLabelEdit();
              node.unfocus();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: TextField(
            controller: _labelController,
            focusNode: _labelFocusNode,
            style: TextStyle(
              color: widget.darkStyle ? Colors.white : Colors.grey.shade900,
              fontSize: 13,
            ),
            decoration: InputDecoration(
              labelText: 'Texto del botón',
              labelStyle: TextStyle(color: foreground, fontSize: 12),
              filled: true,
              fillColor: fill,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.primary),
              ),
            ),
            onChanged: _publishLabel,
            onEditingComplete: () => _labelFocusNode.unfocus(),
          ),
        ),
        const SizedBox(height: 12),
        WebsiteLinkValueEditor(
          label: 'Destino',
          value: value.href,
          dense: widget.dense,
          darkStyle: widget.darkStyle,
          asyncBinding: widget.asyncBinding,
          onChanged: (href) => onChanged(
            value.copyWith(href: href),
          ),
        ),
        if (widget.showVariant) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<WebsiteActionVariant>(
            initialValue: value.variant,
            dropdownColor:
                widget.darkStyle ? const Color(0xFF2D2D2D) : Colors.white,
            style: TextStyle(
              color: widget.darkStyle ? Colors.white : Colors.grey.shade900,
              fontSize: 13,
            ),
            decoration: InputDecoration(
              labelText: 'Presentación',
              labelStyle: TextStyle(color: foreground, fontSize: 12),
              filled: true,
              fillColor: fill,
              isDense: true,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide:
                    BorderSide(color: Theme.of(context).colorScheme.primary),
              ),
            ),
            items: const [
              DropdownMenuItem(
                value: WebsiteActionVariant.filled,
                child: Text('Relleno'),
              ),
              DropdownMenuItem(
                value: WebsiteActionVariant.outline,
                child: Text('Borde'),
              ),
              DropdownMenuItem(
                value: WebsiteActionVariant.text,
                child: Text('Solo texto'),
              ),
            ],
            onChanged: (variant) {
              if (variant == null) return;
              onChanged(value.copyWith(variant: variant));
            },
          ),
        ],
      ],
    );
  }
}
