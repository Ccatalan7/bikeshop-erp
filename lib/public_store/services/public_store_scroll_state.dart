/// Stores scroll offsets per route so list pages can restore position
/// when navigating away and back (e.g., products -> product detail -> back).
///
/// Intentionally does not notify listeners; nothing needs to rebuild when the
/// offset changes.
class PublicStoreScrollState {
  final Map<String, double> _offsetByRoute = <String, double>{};

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
}
