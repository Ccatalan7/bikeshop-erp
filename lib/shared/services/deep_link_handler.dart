import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

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
  StreamSubscription<Uri>? _subscription;
  bool _isInitialized = false;

  /// Pending OAuth code to be processed (set when app opens from deep link)
  String? _pendingOAuthCode;
  String? _pendingOAuthProvider;

  String? get pendingOAuthCode => _pendingOAuthCode;
  String? get pendingOAuthProvider => _pendingOAuthProvider;

  /// Initialize the deep link handler and start listening
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // Handle the initial link that opened the app (cold start)
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        debugPrint('🔗 [DeepLink] Initial link: $initialUri');
        _handleDeepLink(initialUri);
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

  bool get hasPendingOAuthCallback =>
      _pendingOAuthProvider != null && _pendingOAuthCode != null;

  /// Process incoming deep link
  void _handleDeepLink(Uri uri) {
    // Expected format: vinabike://mail/oauth?provider=zoho&oauth_code=...
    // or: vinabike://mail/oauth?provider=gmail&oauth_code=...

    if (uri.scheme != 'vinabike') {
      debugPrint('🔗 [DeepLink] Ignoring non-vinabike scheme: ${uri.scheme}');
      return;
    }

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
    _subscription = null;
    _isInitialized = false;
    _instance = null;
    super.dispose();
  }
}
