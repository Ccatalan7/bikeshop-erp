import 'package:flutter/widgets.dart';

/// Canonical Website Builder management destinations available from contextual
/// editor controls such as CTA pickers and integrity warnings.
enum WebsiteWorkspacePanel {
  pages,
  navigation,
  destinations,
  catalogProducts,
  catalogCategories,
}

/// Connects contextual editor controls with the black Website Builder bar
/// without making those controls depend on [PublicStoreLayout].
///
/// A control may request the canonical owner for the value it is editing. The
/// layout then opens that owner full-width while the editor provider preserves
/// the selected page, block, slide, and unsaved draft.
class WebsiteWorkspaceScope extends InheritedWidget {
  const WebsiteWorkspaceScope({
    super.key,
    required this.onOpen,
    required super.child,
  });

  final ValueChanged<WebsiteWorkspacePanel> onOpen;

  static WebsiteWorkspaceScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<WebsiteWorkspaceScope>();
  }

  void open(WebsiteWorkspacePanel panel) => onOpen(panel);

  @override
  bool updateShouldNotify(WebsiteWorkspaceScope oldWidget) {
    return onOpen != oldWidget.onOpen;
  }
}
