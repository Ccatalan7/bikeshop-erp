/// Resolves whether a customer-chat timeline is genuinely in the foreground.
///
/// `StatefulShellRoute.indexedStack` keeps inactive branches mounted, but
/// disables their [TickerMode]. [ModalRoute.isCurrent] additionally prevents a
/// covered page in the active branch from claiming visibility.
bool isCustomerChatHostVisible({
  required bool tickerEnabled,
  required bool routeIsCurrent,
}) {
  return tickerEnabled && routeIsCurrent;
}
