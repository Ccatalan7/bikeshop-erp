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

    return editor.WebsiteEditorPanel(
      onSave: widget.onSave != null ? _handleSave : null,
      onDiscard: widget.onDiscard,
    );
  }
}
