// Stub implementation for non-web platforms
// This file is used when dart:html is not available

String? getInitialBrowserUrl() {
  // On non-web platforms, we don't have a browser URL
  return null;
}

/// Stub - native platforms do not expose a browser fragment.
void clearSensitiveAuthFragment() {
  // No-op on non-web platforms.
}

/// Stub - no loading screen on non-web platforms
void hideHtmlLoadingScreen() {
  // No-op on non-web platforms
}

/// Stub - never skip Firebase on native platforms
bool shouldSkipFirebase() {
  return false;
}

/// Stub - no Zoho OAuth on non-web platforms
String? captureZohoOAuthCode() {
  return null;
}

/// Stub - no Zoho OAuth on non-web platforms
String? getAndClearZohoOAuthCode() {
  return null;
}

/// Stub - no Gmail OAuth on non-web platforms
String? captureGmailOAuthCode() {
  return null;
}

/// Stub - no Gmail OAuth on non-web platforms
String? getAndClearGmailOAuthCode() {
  return null;
}

/// Stub - URL cleaning not available on non-web platforms
void cleanMailUrl() {
  // No-op on non-web platforms
}

/// Stub - direct URL navigation not available on non-web platforms
void navigateToUrl(String url) {
  // No-op on non-web platforms - mail OAuth only works on web
}

/// Stub - anchor hash navigation not available on non-web platforms
void setLocationHash(String hash) {
  // No-op on non-web platforms
}

String? getSessionStorageValue(String key) {
  return null;
}

void setSessionStorageValue(String key, String value) {
  // No-op on non-web platforms
}
