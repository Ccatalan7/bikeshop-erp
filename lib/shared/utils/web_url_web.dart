// Web implementation using dart:html
// This file is only used on web platform

import 'dart:html' as html show window;

String? getInitialBrowserUrl() {
  return html.window.location.href;
}
