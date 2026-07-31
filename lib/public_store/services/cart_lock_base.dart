abstract interface class CartLockCoordinator {
  /// Runs [action] while this storage resource is held exclusively.
  ///
  /// The web implementation coordinates every same-origin tab, window and
  /// worker through the Web Locks API. Native/test implementations coordinate
  /// every store instance in the current Dart isolate.
  Future<void> synchronized(
    String resourceName,
    Future<void> Function() action,
  );
}
