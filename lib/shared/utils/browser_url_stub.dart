// Stub implementation for non-web platforms

/// Get the actual browser URL path (stub for non-web)
String getBrowserPath() {
  return '/';
}

/// Get the full browser URL (stub for non-web)
String getBrowserUrl() {
  return '/';
}

/// Get browser query string (stub for non-web)
String getBrowserQueryString() {
  return '';
}

/// Get browser hash (stub for non-web)
String getBrowserHash() {
  return '';
}

/// Check if browser is at a specific path (stub for non-web)
bool isBrowserAtPath(String expectedPath) {
  return false;
}

/// Get order ID from browser URL (stub for non-web)
String? getOrderIdFromBrowserUrl() {
  return null;
}

/// Get query parameters from browser URL (stub for non-web)
Map<String, String> getBrowserQueryParameters() {
  return {};
}
