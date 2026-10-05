/// Resolves a saved social value that may be a handle **or** a full URL.
///
/// Owners type both forms interchangeably, so the renderer must accept both
/// and produce one valid destination. An unset network returns `null` and the
/// caller omits the icon entirely — it never falls back to another tenant's
/// account.
///
/// [keepAtPrefix] is required by YouTube, whose canonical handle URL is
/// `youtube.com/@handle`; stripping the `@` there produced a dead link.
String? normalizeSocialUrl(
  String raw,
  String baseUrl, {
  bool keepAtPrefix = false,
}) {
  var value = raw.trim();
  if (value.isEmpty) return null;

  // Already absolute: accept only real web schemes so a saved `javascript:`
  // or `mailto:` value can never become a footer link.
  final parsed = Uri.tryParse(value);
  if (parsed != null && parsed.hasScheme) {
    if (!parsed.isScheme('http') && !parsed.isScheme('https')) return null;
    return parsed.host.isEmpty ? null : value;
  }

  // Scheme-less absolute form, e.g. `www.instagram.com/tienda`.
  if (value.startsWith('www.') || value.contains('/')) {
    final host = Uri.tryParse('https://$value');
    if (host != null && host.host.contains('.')) return 'https://$value';
  }

  // Plain handle.
  while (value.startsWith('/')) {
    value = value.substring(1);
  }
  final withoutAt = value.startsWith('@') ? value.substring(1) : value;
  if (withoutAt.isEmpty) return null;
  return '$baseUrl${keepAtPrefix ? '@$withoutAt' : withoutAt}';
}
