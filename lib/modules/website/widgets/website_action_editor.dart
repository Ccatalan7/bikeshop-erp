import 'package:flutter/material.dart';

import '../models/website_action.dart';
import 'website_link_value_editor.dart';

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
  });

  final WebsiteActionValue value;
  final ValueChanged<WebsiteActionValue> onChanged;
  final String title;
  final bool darkStyle;
  final bool dense;
  final bool showVariant;

  @override
  State<WebsiteActionEditor> createState() => _WebsiteActionEditorState();
}

class _WebsiteActionEditorState extends State<WebsiteActionEditor> {
  late final TextEditingController _labelController;

  @override
  void initState() {
    super.initState();
    _labelController = TextEditingController(text: widget.value.label);
  }

  @override
  void didUpdateWidget(covariant WebsiteActionEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value.label != _labelController.text &&
        widget.value.label != oldWidget.value.label) {
      _labelController.value = TextEditingValue(
        text: widget.value.label,
        selection: TextSelection.collapsed(offset: widget.value.label.length),
      );
    }
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
        TextField(
          controller: _labelController,
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
          onChanged: (label) => widget.onChanged(
            widget.value.copyWith(label: label),
          ),
        ),
        const SizedBox(height: 12),
        WebsiteLinkValueEditor(
          label: 'Destino',
          value: widget.value.href,
          dense: widget.dense,
          darkStyle: widget.darkStyle,
          onChanged: (href) => widget.onChanged(
            widget.value.copyWith(href: href),
          ),
        ),
        if (widget.showVariant) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<WebsiteActionVariant>(
            initialValue: widget.value.variant,
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
              widget.onChanged(widget.value.copyWith(variant: variant));
            },
          ),
        ],
      ],
    );
  }
}
