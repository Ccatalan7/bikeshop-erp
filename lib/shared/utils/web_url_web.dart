// Web implementation using package:web
// This file is only used on web platform

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;

String? getInitialBrowserUrl() {
  return web.window.location.href;
}

/// Hide the HTML loading screen after Flutter has loaded
void hideHtmlLoadingScreen() {
  final loadingScreen = web.document.getElementById('app-shell');
  loadingScreen?.classList.add('hidden');
}

/// Check if Firebase should be skipped (Safari/iOS don't support FCM properly)
/// This reads the window.skipFCM flag set in index.html
bool shouldSkipFirebase() {
  try {
    final skipFCM = (web.window as JSObject).getProperty('skipFCM'.toJS);
    return skipFCM.dartify() == true;
  } catch (e) {
    return false;
  }
}

// Static storage for OAuth codes (captured before router can strip them)
String? _capturedZohoCode;
String? _capturedGmailCode;

/// Check if current URL is a Zoho OAuth callback and capture the code
String? captureZohoOAuthCode() {
  try {
    final href = web.window.location.href;
    final uri = Uri.parse(href);

    if (uri.queryParameters.containsKey('zoho_code')) {
      final code = uri.queryParameters['zoho_code'];
      _capturedZohoCode = code;
      _cleanOAuthUrl();
      return code;
    }
  } catch (e) {
    // Ignore errors
  }
  return null;
}

/// Check if current URL is a Gmail OAuth callback and capture the code
String? captureGmailOAuthCode() {
  try {
    final href = web.window.location.href;
    final uri = Uri.parse(href);

    if (uri.queryParameters.containsKey('gmail_code')) {
      final code = uri.queryParameters['gmail_code'];
      _capturedGmailCode = code;
      _cleanOAuthUrl();
      return code;
    }
  } catch (e) {
    // Ignore errors
  }
  return null;
}

/// Clean OAuth query parameters from URL
void _cleanOAuthUrl() {
  try {
    final href = web.window.location.href;
    final uri = Uri.parse(href);
    final newUri = uri.replace(queryParameters: {});
    String newUrl = newUri.toString();

    if (newUrl.endsWith('?')) {
      newUrl = newUrl.substring(0, newUrl.length - 1);
    }
    newUrl = newUrl.replaceAll('?#', '#');

    web.window.history.replaceState(null, '', newUrl);
  } catch (e) {
    // Ignore errors
  }
}

/// Get the captured Zoho OAuth code (if any) - returns only once
String? getAndClearZohoOAuthCode() {
  final code = _capturedZohoCode;
  _capturedZohoCode = null;
  return code;
}

/// Get the captured Gmail OAuth code (if any) - returns only once
String? getAndClearGmailOAuthCode() {
  final code = _capturedGmailCode;
  _capturedGmailCode = null;
  return code;
}

/// Clean mail URL (remove OAuth params)
void cleanMailUrl() {
  try {
    if (web.window.location.href.contains('_code')) {
      web.window.history.replaceState(null, '', '/#/mail');
    }
  } catch (e) {
    // Ignore errors
  }
}

/// Navigate to a URL (for OAuth redirects)
void navigateToUrl(String url) {
  web.window.location.href = url;
}

/// Set location hash for anchor navigation
void setLocationHash(String hash) {
  try {
    web.window.location.hash = hash;
  } catch (_) {
    // Ignore errors
  }
}
