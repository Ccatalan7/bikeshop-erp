import 'dart:async';
import 'dart:io' as io;

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'route_share_service.dart';

/// Preference key holding `<process id>|<link>` for the launch link this
/// process has already acted on.
const String deepLinkInitialLinkConsumedKey = 'deep_link.initial_link_consumed';

/// The marker that says "this process already acted on this launch link".
String deepLinkInitialLinkMarker(int processId, Uri uri) => '$processId|$uri';

/// The operating system hands the launch link back on every query, and a hot
/// restart runs `initialize()` again inside the same process, so the app kept
/// jumping to the last shared link on every restart (owner report,
/// 2026-09-03). A launch link is acted on once per process: a cold start has
/// a new process id and honours it again.
bool deepLinkInitialLinkAlreadyConsumed({
  required String? storedMarker,
  required int processId,
  required Uri uri,
}) =>
    storedMarker != null &&
    storedMarker == deepLinkInitialLinkMarker(processId, uri);

/// Handles deep links for OAuth callbacks and other app-specific URLs.
/// Listens for `vinabike://` scheme links and processes them accordingly.
class DeepLinkHandler extends ChangeNotifier {
  static DeepLinkHandler? _instance;
  static DeepLinkHandler get instance {
    _instance ??= DeepLinkHandler._internal();
    return _instance!;
  }

  DeepLinkHandler._internal();

  final AppLinks _appLinks = AppLinks();
  final StreamController<String> _routeLinkController =
      StreamController<String>.broadcast();
  StreamSubscription<Uri>? _subscription;
  bool _isInitialized = false;

  /// Pending OAuth code to be processed (set when app opens from deep link)
  String? _pendingOAuthCode;
  String? _pendingOAuthProvider;
  String? _pendingRoute;

  String? get pendingOAuthCode => _pendingOAuthCode;
  String? get pendingOAuthProvider => _pendingOAuthProvider;
  Stream<String> get routeLinks => _routeLinkController.stream;

  /// Initialize the deep link handler and start listening
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // Handle the initial link that opened the app (cold start)
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        if (await _consumeInitialLinkOnce(initialUri)) {
          debugPrint('🔗 [DeepLink] Initial link: $initialUri');
          _handleDeepLink(initialUri);
        } else {
          debugPrint(
            '🔗 [DeepLink] Launch link already handled by this process '
            '(hot restart); ignoring: $initialUri',
          );
        }
      }
    } catch (e) {
      debugPrint('🔗 [DeepLink] Error getting initial link: $e');
    }

    // Listen for links while the app is running (warm start)
    _subscription = _appLinks.uriLinkStream.listen(
      (Uri uri) {
        debugPrint('🔗 [DeepLink] Received link: $uri');
        _handleDeepLink(uri);
      },
      onError: (error) {
        debugPrint('🔗 [DeepLink] Stream error: $error');
      },
    );
  }

  /// True the first time this process sees the launch link; false on a hot
  /// restart of the same process. Fails open: if the marker cannot be read or
  /// written, the link is honoured as before.
  Future<bool> _consumeInitialLinkOnce(Uri uri) async {
    if (kIsWeb) return true;
    try {
      final marker = deepLinkInitialLinkMarker(io.pid, uri);
      final prefs = await SharedPreferences.getInstance();
      if (deepLinkInitialLinkAlreadyConsumed(
        storedMarker: prefs.getString(deepLinkInitialLinkConsumedKey),
        processId: io.pid,
        uri: uri,
      )) {
        return false;
      }
      await prefs.setString(deepLinkInitialLinkConsumedKey, marker);
    } catch (error) {
      debugPrint('🔗 [DeepLink] Could not record the launch link: $error');
    }
    return true;
  }

  bool get hasPendingOAuthCallback =>
      _pendingOAuthProvider != null && _pendingOAuthCode != null;

  /// Process incoming deep link
  void _handleDeepLink(Uri uri) {
    final sharedRoute = RouteShareService.routeFromUri(uri);
    if (sharedRoute != null) {
      _handleRouteLink(sharedRoute);
      return;
    }

    if (uri.scheme != 'vinabike') {
      debugPrint('🔗 [DeepLink] Ignoring non-vinabike scheme: ${uri.scheme}');
      return;
    }

    // Expected format: vinabike://mail/oauth?provider=zoho&oauth_code=...
    // or: vinabike://mail/oauth?provider=gmail&oauth_code=...
    if (uri.host == 'mail' && uri.path.contains('oauth')) {
      final provider = uri.queryParameters['provider'];
      final code = uri.queryParameters['oauth_code'] ??
          uri.queryParameters['code']; // Legacy callback compatibility.
      final error = uri.queryParameters['error'];

      if (error != null) {
        debugPrint('🔗 [DeepLink] OAuth error: $error');
        return;
      }

      if (provider != null && code != null) {
        debugPrint('🔗 [DeepLink] OAuth callback: provider=$provider');
        _handleOAuthCallback(provider, code);
      }
    }
  }

  void _handleRouteLink(String route) {
    _pendingRoute = route;
    debugPrint('🔗 [DeepLink] Stored pending route: $route');
    if (!_routeLinkController.isClosed) {
      _routeLinkController.add(route);
    }
    notifyListeners();
  }

  String? takePendingRoute() {
    final route = _pendingRoute;
    _pendingRoute = null;
    return route;
  }

  /// Store OAuth callback data so the mail page can exchange it after
  /// providers are initialized.
  void _handleOAuthCallback(String provider, String code) {
    _pendingOAuthCode = code;
    _pendingOAuthProvider = provider;
    debugPrint('🔗 [DeepLink] Stored pending OAuth callback for $provider');
    notifyListeners();
  }

  /// Clear pending OAuth data (called after mail page processes it)
  void clearPendingOAuth() {
    _pendingOAuthCode = null;
    _pendingOAuthProvider = null;
    notifyListeners();
  }

  /// Dispose of resources
  @override
  void dispose() {
    _subscription?.cancel();
    _routeLinkController.close();
    _subscription = null;
    _isInitialized = false;
    _instance = null;
    super.dispose();
  }
}
