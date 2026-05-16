import 'package:flutter/foundation.dart';

import 'workspace_manager.dart';

class SharedRouteLink {
  final String route;
  final String title;
  final Uri uri;
  final Uri? webUri;

  const SharedRouteLink({
    required this.route,
    required this.title,
    required this.uri,
    this.webUri,
  });

  String get link => webUri?.toString() ?? uri.toString();

  String get shareText {
    return 'Revisa esto en Vinabike ERP:\n'
        '$title\n'
        '$link';
  }
}

class RouteShareService {
  static const String scheme = 'vinabike';
  static const String host = 'app';
  static const String openPath = '/open';

  static const List<String> _erpRouteRoots = [
    '/dashboard',
    '/accounting',
    '/tax-reports',
    '/clientes',
    '/taller',
    '/wheel-building',
    '/inventory',
    '/sales',
    '/purchases',
    '/pos',
    '/hr',
    '/website',
    '/tienda',
    '/mail',
    '/chat',
    '/tools',
    '/settings',
    '/debug',
  ];

  static SharedRouteLink? buildForRoute({
    required String route,
    required String title,
  }) {
    final normalizedRoute = normalizeRoute(route);
    if (normalizedRoute == null) return null;

    final trimmedTitle =
        title.trim().isEmpty ? getRouteTitle(normalizedRoute) : title.trim();

    return SharedRouteLink(
      route: normalizedRoute,
      title: trimmedTitle,
      uri: Uri(
        scheme: scheme,
        host: host,
        path: openPath,
        queryParameters: {
          'route': normalizedRoute,
          'title': trimmedTitle,
        },
      ),
      webUri: _buildWebUri(normalizedRoute),
    );
  }

  static String? routeFromUri(Uri uri) {
    if (uri.scheme == scheme && uri.host == host && uri.path == openPath) {
      return normalizeRoute(uri.queryParameters['route']);
    }

    if ((uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.path.isNotEmpty) {
      return normalizeRoute(uri.toString());
    }

    return null;
  }

  static String? normalizeRoute(String? rawRoute) {
    final raw = rawRoute?.trim();
    if (raw == null || raw.isEmpty) return null;

    final parsed = Uri.tryParse(raw);
    if (parsed == null) return null;

    final path = parsed.path.isNotEmpty ? parsed.path : raw.split('?').first;
    if (!path.startsWith('/') || !_isAllowedErpPath(path)) return null;

    return Uri(
      path: path,
      query: parsed.hasQuery ? parsed.query : null,
      fragment: parsed.hasFragment ? parsed.fragment : null,
    ).toString();
  }

  static bool isShareLink(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null && routeFromUri(uri) != null;
  }

  static Uri? _buildWebUri(String route) {
    if (!kIsWeb) return null;

    final current = Uri.base;
    if (!current.hasScheme || current.host.isEmpty) return null;
    final routeUri = Uri.parse(route);
    return Uri(
      scheme: current.scheme,
      userInfo: current.userInfo,
      host: current.host,
      port: current.hasPort ? current.port : null,
      path: routeUri.path,
      query: routeUri.hasQuery ? routeUri.query : null,
      fragment: routeUri.hasFragment ? routeUri.fragment : null,
    );
  }

  static bool _isAllowedErpPath(String path) {
    for (final root in _erpRouteRoots) {
      if (path == root || path.startsWith('$root/')) return true;
    }
    return false;
  }
}
