import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Shared return contract for routed detail surfaces.
///
/// A routed detail is reachable from many hosts: its own list, a dashboard
/// card, a search result, a related record, or another module. It therefore
/// must not assume which host opened it.
///
/// `context.go(<list route>)` is the wrong way to close one. It does not
/// navigate back — it *replaces* the current location, which discards the
/// history entry the host was occupying and disposes the host route along with
/// its search text, filters, scope, selection, expanded rows and scroll
/// offset. The operator lands on a freshly rebuilt list and has to reconstruct
/// the work they were doing.
///
/// Use [close] instead. It returns to whatever opened this surface and falls
/// back to [fallbackRoute] only when there is genuinely no history to return
/// to, such as a deep link opened directly in a new tab.
abstract final class ReturnNavigation {
  /// Returns to the surface that opened the current route.
  ///
  /// [fallbackRoute] is used only when nothing can be popped. Pass the route a
  /// direct deep link should reasonably resolve to, normally the entity's own
  /// list.
  static void close(
    BuildContext context, {
    required String fallbackRoute,
    Object? result,
  }) {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop(result);
      return;
    }
    router.go(fallbackRoute);
  }

  /// Whether the current route was opened by a host it can return to.
  ///
  /// Use it to label the affordance honestly: a surface reached by deep link
  /// should not promise a return that does not exist.
  static bool canReturn(BuildContext context) => GoRouter.of(context).canPop();
}
