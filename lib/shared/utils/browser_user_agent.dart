/// Un WebView de Android se anuncia con el token `wv` dentro del user agent
/// («… Chrome/140.0.0.0 Mobile Safari/537.36; wv» o «Version/4.0 … wv»). Varios
/// sitios lo leen como «app embebida» y en vez de su formulario de sesión
/// sirven un panel de bloqueo o una página de respaldo — el login queda roto
/// sin ningún error visible. Quitar ese token es el remedio conocido, y no
/// disfraza al navegador de otra cosa: el resto del user agent, incluida la
/// versión real de Chrome, se conserva tal cual.
library;

final RegExp _embeddedToken = RegExp(
  r'(?:\s*;\s*wv|\s+wv)(?=\s|\)|$)',
  caseSensitive: false,
);
final RegExp _collapsibleSpaces = RegExp(r'[ \t]{2,}');
final RegExp _danglingSeparator = RegExp(r'\s*;\s*(?=\)|$)');

/// Devuelve [userAgent] sin el token de WebView embebido.
///
/// Devuelve `null` cuando no hay nada que corregir, para que quien lo llame
/// pueda dejar el user agent por defecto de la plataforma en vez de fijar uno
/// propio que envejezca.
String? sanitizeEmbeddedUserAgent(String? userAgent) {
  final source = userAgent?.trim() ?? '';
  if (source.isEmpty) return null;
  if (!_embeddedToken.hasMatch(source)) return null;

  final sanitized = source
      .replaceAll(_embeddedToken, '')
      .replaceAll(_danglingSeparator, '')
      .replaceAll(_collapsibleSpaces, ' ')
      .trim();

  return sanitized.isEmpty ? null : sanitized;
}
