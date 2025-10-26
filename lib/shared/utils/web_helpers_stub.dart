// Stub for non-web platforms
// These functions do nothing on desktop/mobile

/// Replace browser history state (stub for non-web platforms)
void replaceHistoryState(String title, String url) {
  // No-op: Browser history not available on desktop/mobile
}

/// Open URL in browser window (stub for non-web platforms)
void openInWindow(String url, String target) {
  // No-op: Use url_launcher instead on desktop/mobile
}
