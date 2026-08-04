import 'package:flutter/material.dart';

import '../providers/website_edit_mode_provider.dart';
import 'website_block_edit_section.dart';
import 'website_editor_chrome_geometry.dart';
import 'website_editor_panel.dart' deferred as editor;

/// The chrome the reused inspector controls were built against.
///
/// UNSOURCED — legacy, and marked here at its line as the sync contract
/// requires. `_EditBlockTab` and every control below it paint white on this
/// canvas with literal values that predate the palette contract. The
/// contextual sheet reuses those controls verbatim instead of restyling five
/// thousand lines in a round that must not redesign, so it must also reuse the
/// canvas they are legible on. t10 frame 10f puts the sheet body on the
/// `surface` role; that gap is real debt and it closes when the inspector
/// controls migrate to `VinabikeThemeRoles`.
const Color websiteEditorLegacyInspectorCanvas = Color(0xFF1E1E1E);

class DeferredWebsiteEditorPanel extends StatefulWidget {
  final VoidCallback? onDiscard;
  final Future<void> Function()? onSave;
  final Future<void> Function()? onRestoreComplete;

  const DeferredWebsiteEditorPanel({
    super.key,
    this.onDiscard,
    this.onSave,
    this.onRestoreComplete,
  });

  @override
  State<DeferredWebsiteEditorPanel> createState() =>
      _DeferredWebsiteEditorPanelState();
}

class _DeferredWebsiteEditorPanelState
    extends State<DeferredWebsiteEditorPanel> {
  bool _libraryLoaded = false;

  @override
  void initState() {
    super.initState();
    editor.loadLibrary().then((_) {
      if (mounted) {
        setState(() {
          _libraryLoaded = true;
        });
      }
    });
  }

  Future<void> _handleSave() async {
    final onSave = widget.onSave;
    if (onSave != null) {
      await onSave();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_libraryLoaded) {
      return SizedBox(
        // Same owner as the loaded panel: the placeholder must not shift the
        // layout when the deferred library finishes loading.
        width: WebsiteEditorChromeScope.maybeOf(context)?.paneWidth ??
            WebsiteEditorChromeGeometry.inspectorWidth,
        child: const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return editor.WebsiteEditorPanel(
      onSave: widget.onSave != null ? _handleSave : null,
      onRestoreComplete: widget.onRestoreComplete,
      onDiscard: widget.onDiscard,
    );
  }
}

/// Loads the SAME deferred editor library and mounts only the selected
/// block's controls.
///
/// The contextual sheet cannot pull `WebsiteEditorPanel`: that widget is the
/// whole panel — header, backups, Página/Tema/Google and a second `Guardar`.
/// It mounts [editor.WebsiteBlockEditSurface] instead, which is the pane's own
/// `_EditBlockTab` without the frame.
class DeferredWebsiteBlockEditSurface extends StatefulWidget {
  const DeferredWebsiteBlockEditSurface({
    super.key,
    required this.editProvider,
    required this.section,
  });

  final WebsiteEditModeProvider editProvider;
  final WebsiteBlockEditSection section;

  @override
  State<DeferredWebsiteBlockEditSurface> createState() =>
      _DeferredWebsiteBlockEditSurfaceState();
}

class _DeferredWebsiteBlockEditSurfaceState
    extends State<DeferredWebsiteBlockEditSurface> {
  bool _libraryLoaded = false;

  @override
  void initState() {
    super.initState();
    editor.loadLibrary().then((_) {
      if (mounted) setState(() => _libraryLoaded = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    // The legacy inspector canvas is applied by this owner, so the loading
    // placeholder and the loaded controls sit on the same surface and the
    // sheet does not flash a different colour when the library resolves.
    return ColoredBox(
      color: websiteEditorLegacyInspectorCanvas,
      child: _libraryLoaded
          ? editor.WebsiteBlockEditSurface(
              editProvider: widget.editProvider,
              section: widget.section,
            )
          : const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
    );
  }
}
