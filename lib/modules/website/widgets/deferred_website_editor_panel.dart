import 'package:flutter/material.dart';

import '../../../shared/services/deferred_load_failure.dart';
import '../../../shared/widgets/deferred_load_notice.dart';
import '../providers/website_edit_mode_provider.dart';
import 'website_block_edit_section.dart';
import 'website_editor_chrome_geometry.dart';
import 'website_editor_host_theme.dart';
import 'website_editor_panel.dart' deferred as editor;

/// «Versiones guardadas», loading the editor's library first (it stays out of
/// the storefront's first download).
Future<void> showDeferredWebsiteVersionsDialog(
  BuildContext context, {
  Future<void> Function()? onRestoreComplete,
}) async {
  await editor.loadLibrary();
  if (!context.mounted) return;
  await editor.showWebsiteVersionsDialog(
    context,
    onRestoreComplete: onRestoreComplete,
  );
}

/// The editor's library, loaded for a widget that holds its place until it
/// is there; a page older than the last deploy cannot load it and shows
/// [libraryFailure] instead (`DeferredLoadNotice`), never a spinner forever.
mixin _EditorLibrary<T extends StatefulWidget> on State<T> {
  bool libraryLoaded = false;
  DeferredLoadFailure? libraryFailure;

  @override
  void initState() {
    super.initState();
    editor.loadLibrary().then(
      (_) {
        if (mounted) setState(() => libraryLoaded = true);
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          libraryFailure =
              DeferredLoadFailure.of(error) ?? DeferredLoadFailure.unavailable;
        });
      },
    );
  }
}

class DeferredWebsiteEditorPanel extends StatefulWidget {
  final VoidCallback? onDiscard;
  final Future<void> Function()? onRestoreComplete;

  const DeferredWebsiteEditorPanel({
    super.key,
    this.onDiscard,
    this.onRestoreComplete,
  });

  @override
  State<DeferredWebsiteEditorPanel> createState() =>
      _DeferredWebsiteEditorPanelState();
}

class _DeferredWebsiteEditorPanelState extends State<DeferredWebsiteEditorPanel>
    with _EditorLibrary {
  @override
  Widget build(BuildContext context) {
    // The deferred boundary is the earliest owner of the desktop inspector.
    // Keeping its placeholder inside the same graphite theme as the loaded
    // panel prevents a host-light flash while loadLibrary() completes.
    final inspectorTheme = WebsiteEditorInspectorTheme.resolveFrom(context);
    return Theme(
      data: inspectorTheme,
      child: Material(
        color: inspectorTheme.colorScheme.surface,
        child: Builder(
          builder: (context) {
            if (!libraryLoaded) {
              final failure = libraryFailure;
              return SizedBox(
                // Same owner as the loaded panel: the placeholder must not
                // shift the layout when the deferred library finishes loading.
                width: WebsiteEditorChromeScope.maybeOf(context)?.paneWidth ??
                    WebsiteEditorChromeGeometry.inspectorWidth,
                child: failure != null
                    ? DeferredLoadNotice(failure: failure)
                    : const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
              );
            }

            return editor.WebsiteEditorPanel(
              onRestoreComplete: widget.onRestoreComplete,
              onDiscard: widget.onDiscard,
            );
          },
        ),
      ),
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
    extends State<DeferredWebsiteBlockEditSurface> with _EditorLibrary {
  @override
  Widget build(BuildContext context) {
    // O-05 owns one Material and one inspector theme around its complete
    // chrome. This deferred consumer stays transparent so loading and loaded
    // states cannot create a second surface or a light/dark seam.
    if (libraryFailure case final failure?) {
      return DeferredLoadNotice(failure: failure);
    }
    return libraryLoaded
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
          );
  }
}

/// Loads the SAME deferred editor library and mounts the «Secciones» rail at
/// the left of the canvas, in the inspector's own theme so both sides of the
/// canvas read as one tool.
class DeferredWebsiteEditorSectionsRail extends StatefulWidget {
  const DeferredWebsiteEditorSectionsRail({super.key});

  @override
  State<DeferredWebsiteEditorSectionsRail> createState() =>
      _DeferredWebsiteEditorSectionsRailState();
}

class _DeferredWebsiteEditorSectionsRailState
    extends State<DeferredWebsiteEditorSectionsRail> with _EditorLibrary {
  @override
  Widget build(BuildContext context) {
    final inspectorTheme = WebsiteEditorInspectorTheme.resolveFrom(context);
    return Theme(
      data: inspectorTheme,
      child: Material(
        color: inspectorTheme.colorScheme.surface,
        child: libraryLoaded
            ? editor.WebsiteEditorSectionsRail()
            : const SizedBox.expand(),
      ),
    );
  }
}
