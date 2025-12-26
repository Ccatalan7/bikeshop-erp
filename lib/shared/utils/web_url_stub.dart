// Stub implementation for non-web platforms
// This file is used when dart:html is not available

String? getInitialBrowserUrl() {
  // On non-web platforms, we don't have a browser URL
  return null;
}

/// Stub - no loading screen on non-web platforms
void hideHtmlLoadingScreen() {
  // No-op on non-web platforms
}
