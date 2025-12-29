// Web implementation using dart:html
// This file is only used on web platform

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html show window, document;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;

String? getInitialBrowserUrl() {
  return html.window.location.href;
}

/// Hide the HTML loading screen after Flutter has loaded
void hideHtmlLoadingScreen() {
  final loadingScreen = html.document.getElementById('app-shell');
  loadingScreen?.classes.add('hidden');
}

/// Check if Firebase should be skipped (Safari/iOS don't support FCM properly)
/// This reads the window.skipFCM flag set in index.html
bool shouldSkipFirebase() {
  try {
    final skipFCM = js.context['skipFCM'];
    return skipFCM == true;
  } catch (e) {
    return false;
  }
}
