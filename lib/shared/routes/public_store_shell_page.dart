import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../public_store/widgets/storefront_navigation_guard_scope.dart';

/// A page of the ERP-mounted store shell.
///
/// Its key keeps the page alive across navigation and query param changes on
/// the same route (e.g. `?edit=true`, `?preview=true`).
///
/// A page covered by another one in the same branch (the catalog under a
/// category, a category under a product) is not kept: it is rebuilt when the
/// operator comes back to it. The shell's navigator lives inside the store's
/// single scroll view, so its overlay is sized by the page on top and never
/// lays out a covered one. A covered page that changed twice (its data or an
/// image arriving) tripped Flutter's
/// `_debugRelayoutBoundaryAlreadyMarkedNeedsLayout` assertion inside layout,
/// which froze the debug app and grew it to 35 GB (2026-10-06).
Page<void> buildPublicStoreShellPage(String key, Widget child) {
  return CustomTransitionPage<void>(
    key: ValueKey<String>(key),
    maintainState: false,
    transitionDuration: Duration.zero,
    reverseTransitionDuration: Duration.zero,
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        child,
    child: StorefrontNavigationGuardScope.pageSwitch(child: child),
  );
}
