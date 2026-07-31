/// Purchase authority and refresh-status policy for the public product page.
///
/// Two facts about a product page are independent and were previously
/// conflated in one boolean:
///
///  * **purchase authority** — the origin confirmed this product's price,
///    publication and availability recently enough that selling against it is
///    honest; and
///  * **refresh status** — whether the *most recent* background revalidation
///    succeeded.
///
/// The freshness monitor pulses roughly every 30 seconds, so refresh failures
/// are routine (a phone in a dead spot, a flaky café network). A failure must
/// not instantly kill a page the origin validated two seconds ago — but it
/// also must not leave "Precio y disponibilidad actualizados." with a green
/// check on screen indefinitely, which is what happened when the two facts
/// shared one flag. Authority survives refresh failures only inside a bounded
/// window; the row always tells the truth about the last refresh.
library;

/// How long last-known-good origin validation keeps purchase authority when
/// refreshes are failing. Beyond this the page stops selling and says so.
const Duration productPurchaseAuthorityWindow = Duration(minutes: 10);

/// Whether last-known-good authority survives a failed background refresh.
bool purchaseAuthoritySurvivesRefreshFailure({
  required DateTime? lastValidatedAt,
  required DateTime now,
  Duration window = productPurchaseAuthorityWindow,
}) {
  if (lastValidatedAt == null) return false;
  final age = now.difference(lastValidatedAt);
  return age >= Duration.zero && age <= window;
}

/// What the availability/status row communicates.
enum ProductAvailabilityRowState {
  /// Origin confirmed and the last refresh succeeded.
  confirmed,

  /// Origin confirmed within the authority window, but the last refresh
  /// failed: purchase stays enabled, the row says the data is last-known-good
  /// and offers a retry. Never a green check.
  staleConfirmed,

  /// No confirmed data yet; a load is in flight.
  refreshing,

  /// No purchase authority and the last attempt failed.
  unavailable,
}

ProductAvailabilityRowState productAvailabilityRowState({
  required bool validated,
  required bool refreshFailed,
}) {
  if (validated) {
    return refreshFailed
        ? ProductAvailabilityRowState.staleConfirmed
        : ProductAvailabilityRowState.confirmed;
  }
  return refreshFailed
      ? ProductAvailabilityRowState.unavailable
      : ProductAvailabilityRowState.refreshing;
}

/// Whether an asynchronous related-products response still owns the visible
/// product page.
///
/// Product revalidation may launch two requests under the same route token:
/// one from the warm navigation snapshot and another from the authoritative
/// product row. If the authoritative row moved categories, checking only the
/// route and product IDs lets the older category response overwrite the newer
/// suggestions. A monotonically increasing generation makes ownership
/// explicit.
bool relatedProductsRequestStillOwnsPage({
  required int requestGeneration,
  required int activeGeneration,
  required int routeToken,
  required int activeRouteToken,
  required String requestedProductId,
  required String? visibleProductId,
}) {
  return requestGeneration == activeGeneration &&
      routeToken == activeRouteToken &&
      requestedProductId == visibleProductId;
}
