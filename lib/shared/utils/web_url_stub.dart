// Stub implementation for non-web platforms
// This file is used when dart:html is not available

String? getInitialBrowserUrl() {
  // On non-web platforms, we don't have a browser URL
  return null;
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
