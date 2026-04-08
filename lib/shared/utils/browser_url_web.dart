// Web-specific implementation using package:web
import 'package:web/web.dart' as web;

/// Get the actual browser URL path (not Uri.base which can be stale)
String getBrowserPath() {
  return web.window.location.pathname;
}

/// Get the full browser URL
String getBrowserUrl() {
  return web.window.location.href;
}

/// Get browser query string (without leading ?)
String getBrowserQueryString() {
  final search = web.window.location.search;
  return search.startsWith('?') ? search.substring(1) : search;
}

/// Get browser hash (without leading #)
String getBrowserHash() {
  final hash = web.window.location.hash;
  return hash.startsWith('#') ? hash.substring(1) : hash;
}

/// Check if browser is at a specific path
bool isBrowserAtPath(String expectedPath) {
  final currentPath = getBrowserPath();
  return currentPath == expectedPath ||
      currentPath.startsWith('$expectedPath/');
}

/// Get order ID from browser URL if it's a MercadoPago redirect
/// Returns null if not at /tienda/pedido/:id
String? getOrderIdFromBrowserUrl() {
  final path = getBrowserPath();

  // Check for /tienda/pedido/:id pattern
  final pedidoMatch = RegExp(r'^/tienda/pedido/([a-f0-9-]+)').firstMatch(path);
  if (pedidoMatch != null) {
    return pedidoMatch.group(1);
  }

  // Check for /pedido/:id pattern
  final pedidoShortMatch = RegExp(r'^/pedido/([a-f0-9-]+)').firstMatch(path);
  if (pedidoShortMatch != null) {
    return pedidoShortMatch.group(1);
  }

  return null;
}

/// Get query parameters from browser URL
Map<String, String> getBrowserQueryParameters() {
  final params = <String, String>{};
  final search = web.window.location.search;
  if (search.length > 1) {
    final queryString = search.substring(1);
    for (final pair in queryString.split('&')) {
      final parts = pair.split('=');
      if (parts.length == 2) {
        params[Uri.decodeComponent(parts[0])] = Uri.decodeComponent(parts[1]);
      }
    }
  }
  return params;
}
