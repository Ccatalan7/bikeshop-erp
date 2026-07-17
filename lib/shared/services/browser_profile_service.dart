import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Owns the native embedded-browser profile for the lifetime of the app.
///
/// WebKit and Android WebView use their platform default persistent data
/// stores. Windows needs an explicit writable user-data folder; reusing the
/// same [WebViewEnvironment] also lets every browser workspace share cookies,
/// cache and renderer processes.
class BrowserProfileService {
  BrowserProfileService._();

  static final Map<String, Future<WebViewEnvironment?>> _windowsEnvironments =
      {};
  static final Map<String, Future<void>> _clearWebsiteDataFutures = {};

  static Future<WebViewEnvironment?> environmentForUser(
    String? userId,
  ) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
      return Future.value(null);
    }

    final identity = _safeIdentity(userId);
    return _windowsEnvironments.putIfAbsent(
      identity,
      () => _createWindowsEnvironment(identity),
    );
  }

  static Future<WebViewEnvironment?> _createWindowsEnvironment(
    String identity,
  ) async {
    final runtimeVersion = await WebViewEnvironment.getAvailableVersion();
    if (runtimeVersion == null) return null;

    final supportDirectory = await getApplicationSupportDirectory();
    final userDataDirectory = path.join(
      supportDirectory.path,
      'browser_profiles',
      identity,
      'webview2',
    );

    return WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(
        allowSingleSignOnUsingOSPrimaryAccount: true,
        userDataFolder: userDataDirectory,
      ),
    );
  }

  /// Clears website-owned state when the ERP account explicitly signs out.
  /// App-owned history, bookmarks and tab-session records are user-scoped and
  /// intentionally remain available to that same ERP user.
  static Future<void> clearWebsiteData({String? userId}) {
    final identity = _safeIdentity(userId);
    final pending = _clearWebsiteDataFutures[identity];
    if (pending != null) return pending;

    final operation = _clearWebsiteData(identity);
    _clearWebsiteDataFutures[identity] = operation;
    return operation.whenComplete(() {
      if (identical(_clearWebsiteDataFutures[identity], operation)) {
        _clearWebsiteDataFutures.remove(identity);
      }
    });
  }

  static Future<void> _clearWebsiteData(String identity) async {
    if (kIsWeb) return;
    try {
      await InAppWebViewController.clearAllCache(includeDiskFiles: true);
      if (defaultTargetPlatform == TargetPlatform.windows) {
        final environmentFuture = _windowsEnvironments[identity];
        final environment =
            environmentFuture == null ? null : await environmentFuture;
        await CookieManager.instance(webViewEnvironment: environment)
            .deleteAllCookies();
      } else {
        await CookieManager.instance().deleteAllCookies();
      }
      await WebStorageManager.instance().deleteAllData();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('🌐 Embedded browser cleanup skipped: $error');
      }
    }
  }

  static String _safeIdentity(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized.isEmpty) return 'anonymous';
    return normalized.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  }
}
