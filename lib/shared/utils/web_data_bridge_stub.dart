/// Stub implementation for non-web platforms (Android, iOS, Desktop)
/// Always returns null since they don't have index.html pre-fetching
Future<Object?> getPreloadedStoreDataImpl() async {
  return null;
}
