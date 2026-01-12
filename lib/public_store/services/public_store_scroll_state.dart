import 'package:flutter/foundation.dart';

/// Stores scroll offsets per route so list pages can restore position
/// when navigating away and back (e.g., products -> product detail -> back).
///
/// Intentionally does not notify listeners; nothing needs to rebuild when the
/// offset changes.
///
/// For explicit "scroll to top" requests (logo / Inicio), a lightweight signal
/// is provided so the active scroll view can react immediately even when the
/// route does not change.
class PublicStoreScrollState {
  final ValueNotifier<int> scrollToTopSignal = ValueNotifier<int>(0);
  final ValueNotifier<int> homeRefreshSignal = ValueNotifier<int>(0);

  final Map<String, double> _offsetByRoute = <String, double>{};
  final Map<String, bool> _scrollToTopRequestByRoute = <String, bool>{};
  final Set<String> _scrollToTopRequestByPath = <String>{};

  void _bumpScrollToTopSignal() {
    scrollToTopSignal.value = scrollToTopSignal.value + 1;
  }

  void _bumpHomeRefreshSignal() {
    homeRefreshSignal.value = homeRefreshSignal.value + 1;
  }

  double getOffset(String routeKey) => _offsetByRoute[routeKey] ?? 0.0;

  void setOffset(String routeKey, double offset) {
    // Avoid churn on tiny scroll deltas.
    final prev = _offsetByRoute[routeKey];
    if (prev != null && (prev - offset).abs() < 4.0) return;
    _offsetByRoute[routeKey] = offset;
  }

  void clear(String routeKey) {
    _offsetByRoute.remove(routeKey);
  }

  /// Request that the next time [routeKey] becomes active, its scroll position
  /// is reset to the top.
  ///
  /// This is used for explicit "home" navigations (logo / Inicio) where the
  /// expected UX is to land at the top rather than restoring the prior offset.
  void requestScrollToTop(String routeKey) {
    _scrollToTopRequestByRoute[routeKey] = true;
    _bumpScrollToTopSignal();
  }

  /// Request a home page refresh (re-fetch blocks/settings, re-load featured
  /// products, etc.). This is used for the classic "logo = home" behavior.
  void requestHomeRefresh() {
    _bumpHomeRefreshSignal();
  }

  /// Same as [requestScrollToTop] but keyed by URL path only (e.g. '/',
  /// '/productos'). This is useful when navigation reaches the target by
  /// popping the stack, where query params can differ.
  void requestScrollToTopForPath(String path) {
    if (path.trim().isEmpty) return;
    _scrollToTopRequestByPath.add(path);
    _bumpScrollToTopSignal();
  }

  /// Consume (and clear) an outstanding scroll-to-top request for [routeKey].
  bool consumeScrollToTopRequest(String routeKey) {
    return _scrollToTopRequestByRoute.remove(routeKey) ?? false;
  }

  /// Consume a pending scroll-to-top request by path.
  bool consumeScrollToTopRequestForPath(String path) {
    return _scrollToTopRequestByPath.remove(path);
  }
}
