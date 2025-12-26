// Web implementation using dart:html
// This file is only used on web platform

import 'dart:html' as html show window, document;

String? getInitialBrowserUrl() {
  return html.window.location.href;
}

/// Hide the HTML loading screen after Flutter has loaded
void hideHtmlLoadingScreen() {
  final loadingScreen = html.document.getElementById('loading-screen');
  loadingScreen?.classes.add('hidden');
}
