const Set<String> _trustedMetaNotificationHosts = {
  'facebook.com',
  'www.facebook.com',
  'm.facebook.com',
  'instagram.com',
  'www.instagram.com',
};

/// Returns a Meta interaction URL only when it is safe to open outside the ERP.
///
/// The database already filters provider permalinks before persisting them. This
/// client-side allowlist is a second boundary for old, malformed, or tampered
/// notification rows.
Uri? trustedMetaNotificationUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      !uri.hasAuthority ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443) ||
      !_trustedMetaNotificationHosts.contains(uri.host.toLowerCase())) {
    return null;
  }

  return uri;
}
