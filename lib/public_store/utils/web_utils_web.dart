import 'dart:html' as html;

/// Web implementation
class WebUtils {
  static void replaceHistoryState(String url) {
    html.window.history.replaceState(null, 'Checkout', url);
  }

  static void openUrl(String url) {
    html.window.open(url, '_self');
  }
}
