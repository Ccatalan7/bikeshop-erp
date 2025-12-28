import 'package:flutter/material.dart';

import 'website_editor_panel.dart' deferred as editor;

class DeferredWebsiteEditorPanel extends StatefulWidget {
  final VoidCallback? onDiscard;
  final Future<void> Function()? onSave;

  const DeferredWebsiteEditorPanel({
    super.key,
    this.onDiscard,
    this.onSave,
  });

  @override
  State<DeferredWebsiteEditorPanel> createState() =>
      _DeferredWebsiteEditorPanelState();
}

class _DeferredWebsiteEditorPanelState
    extends State<DeferredWebsiteEditorPanel> {
  late Future<void> _libraryFuture;

  @override
  void initState() {
    super.initState();
    _libraryFuture = editor.loadLibrary();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
        '⏳ [DeferredPanel] build called. Future status: ${_libraryFuture.toString()}');
    return FutureBuilder<void>(
      future: _libraryFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          debugPrint('⏳ [DeferredPanel] Loading library...');
          return const SizedBox(
            width: 380,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          debugPrint(
              '❌ [DeferredPanel] Error loading library: ${snapshot.error}');
          return SizedBox(
            width: 380,
            child: Center(
              child: Text(
                'Error cargando editor: ${snapshot.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        debugPrint('✅ [DeferredPanel] Library loaded. Rendering content.');

        return editor.WebsiteEditorPanel(
          onSave: widget.onSave,
          onDiscard: widget.onDiscard,
        );
      },
    );
  }
}
