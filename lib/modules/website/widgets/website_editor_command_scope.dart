import 'package:flutter/widgets.dart';

/// Publishes the one set of durable editor commands to every chrome
/// composition.
///
/// Desktop pane, compact top bar, phone dock and contextual sheets must never
/// grow their own save/discard coordinators. They consume this scope, so a
/// breakpoint change only swaps presentation while authority, retries and the
/// active document remain owned by [PersistentEditorShell].
class WebsiteEditorCommandScope extends InheritedWidget {
  const WebsiteEditorCommandScope({
    super.key,
    required this.isSaving,
    required this.onSave,
    required this.onDiscard,
    required this.onRestoreComplete,
    required super.child,
  });

  final bool isSaving;
  final Future<void> Function() onSave;
  final VoidCallback onDiscard;
  final Future<void> Function() onRestoreComplete;

  static WebsiteEditorCommandScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<WebsiteEditorCommandScope>();
  }

  @override
  bool updateShouldNotify(WebsiteEditorCommandScope oldWidget) {
    return isSaving != oldWidget.isSaving ||
        onSave != oldWidget.onSave ||
        onDiscard != oldWidget.onDiscard ||
        onRestoreComplete != oldWidget.onRestoreComplete;
  }
}
