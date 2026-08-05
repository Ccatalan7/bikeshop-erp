import 'dart:async';

import 'package:flutter/material.dart';

import '../models/website_action.dart';
import 'website_action_editor.dart';
import 'website_editor_block_sheet.dart';
import 'website_editor_chrome_geometry.dart';
import 'website_link_value_editor.dart';

/// What the contextual sheet decided when it closed.
///
/// Dismissing the sheet applies, mirroring the anchored editor's tap-outside:
/// on both hosts the only way to throw the edit away is to say so.
enum _InlineActionOutcome { applied, appliedAndOpen, discarded }

/// Edit chrome for a shared [WebsiteActionButton].
///
/// The visitor button remains the layout owner. This widget only layers an
/// outline and an editor around that child, so entering Edit cannot change the
/// button's measured size.
///
/// The editor itself has two compositions, chosen by the host and never by this
/// widget's own taste:
///
/// * **pointer host with a pane** keeps the anchored card: `O-04`-class chrome
///   in an overlay, which is what t10 assigns to a pointer host under 1050;
/// * **contextual host** opens the `O-05` sheet. The anchored card cannot live
///   there: it is placed unconditionally below the button with no viewport
///   clamp, no `viewInsets` and no knowledge of the dock, so on a phone its
///   `Presentación` control and both actions ended up behind the dock, and
///   with the keyboard up they had nowhere to go at all.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`,
/// `Website Builder Responsive Authoring` t10 — `surface_component_map` gives
/// the touch host `O-05 VbBottomSheet` (60% cap) and the pointer host
/// `O-04 VbSideSheet en overlay`; frames **10f**/**10h** are the sheet and
/// **10g** is the keyboard case.
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

  /// The `O-05` surface for the contextual host.
  @visibleForTesting
  static const Key sheetKey = Key('website-inline-action-sheet');

  /// The three fields, present the moment the sheet opens.
  @visibleForTesting
  static const Key sheetFieldsKey = Key('website-inline-action-sheet-fields');

  @visibleForTesting
  static const Key sheetApplyKey = Key('website-inline-action-sheet-apply');

  @visibleForTesting
  static const Key sheetCancelKey = Key('website-inline-action-sheet-cancel');

  @visibleForTesting
  static const Key sheetOpenKey = Key('website-inline-action-sheet-open');

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
  bool _isSheetOpen = false;
  bool _usesContextualHost = false;
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
      if (widget.openOnFirstTap) _openEditor();
      return;
    }
    _openEditor();
  }

  /// One entry point, two compositions. The host decides.
  void _openEditor() {
    if (_usesContextualHost) {
      if (_isSheetOpen) return;
      unawaited(_showContextualSheet());
      return;
    }
    if (_overlayEntry == null) _showEditor();
  }

  /// `O-05` for the contextual host, straight onto the action's own fields.
  ///
  /// The draft lives here, not in the provider: the sheet edits a local copy
  /// and the block is written exactly once, on the way out, so label,
  /// destination and presentation stay one operation and one history step —
  /// the same contract the anchored card already honours.
  Future<void> _showContextualSheet() async {
    var draft = WebsiteActionValue(
      label: _labelController.text,
      href: _hrefController.text,
      variant: _variant,
    );
    setState(() => _isSheetOpen = true);

    final outcome = await showWebsiteContextualSheet<_InlineActionOutcome>(
      context: context,
      // This caller lives inside the canvas, under the Navigator the dock
      // paints over. See `showWebsiteContextualSheet`.
      useRootNavigator: true,
      builder: (_) => _InlineActionSheet(
        initialValue: draft,
        canOpen: widget.onOpen != null,
        onDraftChanged: (value) => draft = value,
      ),
    );

    if (!mounted) return;
    setState(() {
      _isSheetOpen = false;
      _isSelected = false;
    });

    if (outcome == _InlineActionOutcome.discarded) {
      _syncFromWidget();
      return;
    }

    _labelController.text = draft.label;
    _hrefController.text = draft.href;
    _variant = draft.variant;
    widget.onChanged(draft);

    if (outcome == _InlineActionOutcome.appliedAndOpen) {
      final href = draft.href.trim();
      if (href.isNotEmpty) widget.onOpen?.call(href);
    }
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
    // Read in `build`, where an inherited dependency belongs; the tap handler
    // then acts on a value that is already current for this frame.
    _usesContextualHost =
        !(WebsiteEditorChromeScope.maybeOf(context)?.usesPane ?? true);
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

/// The contextual host's editor for one action.
///
/// It opens on the action's own three fields — `Texto del botón`, `Destino`
/// and `Presentación` — because the operator got here by tapping that
/// button. Sending them to the block inspector to hunt for it would be a
/// different, longer task than the one they started.
///
/// The fields themselves are [WebsiteActionEditor], the universal owner already
/// used by the inspector, so both hosts write the same three properties with
/// the same labels and the same options.
class _InlineActionSheet extends StatefulWidget {
  const _InlineActionSheet({
    required this.initialValue,
    required this.canOpen,
    required this.onDraftChanged,
  });

  final WebsiteActionValue initialValue;
  final bool canOpen;
  final ValueChanged<WebsiteActionValue> onDraftChanged;

  @override
  State<_InlineActionSheet> createState() => _InlineActionSheetState();
}

class _InlineActionSheetState extends State<_InlineActionSheet> {
  late WebsiteActionValue _draft = widget.initialValue;

  void _update(WebsiteActionValue value) {
    setState(() => _draft = value);
    // The owner keeps a live mirror, so dismissing the sheet by swipe or
    // barrier applies what is on screen instead of silently dropping it.
    widget.onDraftChanged(value);
  }

  void _close(_InlineActionOutcome outcome) =>
      Navigator.of(context).pop(outcome);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canOpen = widget.canOpen && _draft.href.trim().isNotEmpty;

    return WebsiteContextualSheetScaffold(
      surfaceKey: WebsiteInlineActionEditor.sheetKey,
      title: 'Botón',
      // No scope badge on purpose. `handoff-t10` declares `cta.label` and
      // `cta.destination` as `sharedOnly`, so a `Escribe en: móvil` sentence
      // here would state something the write does not do. A surface that
      // cannot state its attribution truthfully states nothing.
      footer: _InlineActionSheetFooter(
        onCancel: () => _close(_InlineActionOutcome.discarded),
        onApply: () => _close(_InlineActionOutcome.applied),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            WebsiteActionEditor(
              key: WebsiteInlineActionEditor.sheetFieldsKey,
              value: _draft,
              onChanged: _update,
              showVariant: true,
              // The sheet is already titled; a second heading over the first
              // field would name the same thing twice.
              title: '',
              // The component ships a light and a dark treatment. The sheet
              // paints on `colorScheme.surface`, so the treatment follows the
              // active theme instead of being fixed to the dark inspector's.
              darkStyle: theme.brightness == Brightness.dark,
            ),
            if (canOpen) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: WebsiteInlineActionEditor.sheetOpenKey,
                  onPressed: () => _close(_InlineActionOutcome.appliedAndOpen),
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: const Text('Abrir'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// `O-05` closes with one primary of 50; `Cancelar` stands beside it because
/// this sheet is the only place the edit can be thrown away — dismissing it
/// applies. The primary keeps the published height and the row keeps the
/// block sheet's own padding, so nothing here is a new measurement.
class _InlineActionSheetFooter extends StatelessWidget {
  const _InlineActionSheetFooter({
    required this.onCancel,
    required this.onApply,
  });

  final VoidCallback onCancel;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
      child: Row(
        children: [
          TextButton(
            key: WebsiteInlineActionEditor.sheetCancelKey,
            onPressed: onCancel,
            child: const Text('Cancelar'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: WebsiteBlockEditSheetGeometry.ctaHeight,
              child: FilledButton(
                key: WebsiteInlineActionEditor.sheetApplyKey,
                onPressed: onApply,
                child: const Text('Listo'),
              ),
            ),
          ),
        ],
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
