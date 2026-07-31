import 'package:flutter/material.dart';

import '../models/website_action.dart';
import 'website_link_value_editor.dart';

/// Edit chrome for a shared [WebsiteActionButton].
///
/// The visitor button remains the layout owner. This widget only layers an
/// outline and an overlay editor around that child, so entering Edit cannot
/// change the button's measured size.
class WebsiteInlineActionEditor extends StatefulWidget {
  const WebsiteInlineActionEditor({
    super.key,
    required this.action,
    required this.child,
    required this.onChanged,
    this.onOpen,
    this.openOnFirstTap = false,
  });

  final WebsiteActionValue action;
  final Widget child;
  final ValueChanged<WebsiteActionValue> onChanged;
  final ValueChanged<String>? onOpen;
  final bool openOnFirstTap;

  @override
  State<WebsiteInlineActionEditor> createState() =>
      _WebsiteInlineActionEditorState();
}

class _WebsiteInlineActionEditorState extends State<WebsiteInlineActionEditor> {
  final LayerLink _layerLink = LayerLink();
  final TextEditingController _labelController = TextEditingController();
  final TextEditingController _hrefController = TextEditingController();
  OverlayEntry? _overlayEntry;
  bool _isSelected = false;
  bool _isHovered = false;
  late WebsiteActionVariant _variant;

  @override
  void initState() {
    super.initState();
    _syncFromWidget();
  }

  @override
  void didUpdateWidget(covariant WebsiteInlineActionEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.action != widget.action && _overlayEntry == null) {
      _syncFromWidget();
    }
  }

  void _syncFromWidget() {
    _labelController.text = widget.action.label;
    _hrefController.text = widget.action.href;
    _variant = widget.action.variant;
  }

  @override
  void deactivate() {
    _removeOverlay();
    super.deactivate();
  }

  @override
  void dispose() {
    _removeOverlay();
    _labelController.dispose();
    _hrefController.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    final entry = _overlayEntry;
    _overlayEntry = null;
    if (entry?.mounted == true) entry!.remove();
  }

  void _closeEditor({required bool save}) {
    if (save) {
      widget.onChanged(
        WebsiteActionValue(
          label: _labelController.text,
          href: _hrefController.text,
          variant: _variant,
        ),
      );
    } else {
      _syncFromWidget();
    }
    _removeOverlay();
    if (mounted) setState(() => _isSelected = false);
  }

  void _handleTap() {
    if (!_isSelected) {
      setState(() => _isSelected = true);
      if (widget.openOnFirstTap) _showEditor();
      return;
    }
    if (_overlayEntry == null) _showEditor();
  }

  void _showEditor() {
    final overlay = Overlay.maybeOf(context);
    final renderObject = context.findRenderObject();
    if (overlay == null ||
        renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return;
    }

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _closeEditor(save: true),
            ),
          ),
          CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(
              (renderObject.size.width - 340) / 2,
              renderObject.size.height + 8,
            ),
            child: Material(
              color: Colors.transparent,
              child: _ActionEditorCard(
                labelController: _labelController,
                hrefController: _hrefController,
                variant: _variant,
                onVariantChanged: (value) {
                  _variant = value;
                  _overlayEntry?.markNeedsBuild();
                },
                onCancel: () => _closeEditor(save: false),
                onSave: () => _closeEditor(save: true),
                onHrefChanged: () => _overlayEntry?.markNeedsBuild(),
                onOpen:
                    widget.onOpen == null || _hrefController.text.trim().isEmpty
                        ? null
                        : () {
                            final href = _hrefController.text.trim();
                            _closeEditor(save: true);
                            widget.onOpen!(href);
                          },
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _handleTap,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              IgnorePointer(child: widget.child),
              if (_isSelected || _isHovered)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _isSelected
                              ? const Color(0xFF00A09D)
                              : const Color(0x8000A09D),
                          width: _isSelected ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              if (_isSelected)
                const Positioned(
                  right: -8,
                  top: -8,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Color(0xFF00A09D),
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.edit_outlined,
                          size: 12,
                          color: Colors.white,
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
}

class _ActionEditorCard extends StatelessWidget {
  const _ActionEditorCard({
    required this.labelController,
    required this.hrefController,
    required this.variant,
    required this.onVariantChanged,
    required this.onCancel,
    required this.onSave,
    required this.onHrefChanged,
    required this.onOpen,
  });

  final TextEditingController labelController;
  final TextEditingController hrefController;
  final WebsiteActionVariant variant;
  final ValueChanged<WebsiteActionVariant> onVariantChanged;
  final VoidCallback onCancel;
  final VoidCallback onSave;
  final VoidCallback onHrefChanged;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 340,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1F2427),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF00A09D), width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x52000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Editar acción',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: labelController,
            style: const TextStyle(color: Colors.white),
            decoration: _decoration('Rótulo'),
          ),
          const SizedBox(height: 10),
          WebsiteLinkValueEditor(
            label: 'Destino',
            value: hrefController.text,
            darkStyle: true,
            dense: true,
            onChanged: (value) {
              hrefController.text = value;
              onHrefChanged();
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<WebsiteActionVariant>(
            initialValue: variant,
            dropdownColor: const Color(0xFF2B3135),
            style: const TextStyle(color: Colors.white),
            decoration: _decoration('Variante'),
            items: WebsiteActionVariant.values
                .map(
                  (value) => DropdownMenuItem<WebsiteActionVariant>(
                    value: value,
                    child: Text(value.storageValue),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value != null) onVariantChanged(value);
            },
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (onOpen != null)
                TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Abrir'),
                ),
              TextButton(
                onPressed: onCancel,
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: onSave,
                child: const Text('Aplicar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white60),
      filled: true,
      fillColor: const Color(0xFF2B3135),
      border: const OutlineInputBorder(),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: Colors.white24),
      ),
    );
  }
}
