// Web-specific browser utilities
// This file exports functions that only work on web platform

import 'dart:html' as html;

/// Replace browser history state (web only)
void replaceHistoryState(String title, String url) {
  html.window.history.replaceState(null, title, url);
}

/// Open URL in browser window (web only)
void openInWindow(String url, String target) {
  html.window.open(url, target);
}
