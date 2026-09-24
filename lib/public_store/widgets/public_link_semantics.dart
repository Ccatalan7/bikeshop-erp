import 'package:flutter/widgets.dart';

/// Declara que [child] lleva a [href], para que el árbol de accesibilidad lo
/// exponga como enlace.
///
/// Con la semántica activa (rastreadores, ver `enableSemanticsForCrawlers`)
/// el motor web lo dibuja como `<a href>`: es lo que Google sigue para
/// descubrir páginas y lo que usa como texto del enlace. Sin semántica no
/// cambia nada. Cuando [enabled] es falso (Edit del editor) o el destino no
/// es una página navegable, se devuelve [child] tal cual.
class PublicLinkSemantics extends StatelessWidget {
  const PublicLinkSemantics({
    super.key,
    required this.href,
    required this.child,
    this.enabled = true,
    this.label,
  });

  final String? href;
  final Widget child;
  final bool enabled;

  /// Texto del enlace cuando [child] no tiene texto propio (un logo).
  final String? label;

  @override
  Widget build(BuildContext context) {
    final uri = enabled ? publicLinkUri(href) : null;
    if (uri == null) return child;
    final text = label?.trim() ?? '';
    return Semantics(
      container: true,
      link: true,
      linkUrl: uri,
      label: text.isEmpty ? null : text,
      child: child,
    );
  }
}

/// Sólo rutas de la tienda y páginas web: `tel:`, `mailto:`, anclas y
/// valores vacíos no son páginas que un rastreador deba seguir.
Uri? publicLinkUri(String? href) {
  final value = href?.trim() ?? '';
  if (value.isEmpty || value.startsWith('#')) return null;
  final uri = Uri.tryParse(value);
  if (uri == null) return null;
  if (uri.hasScheme && uri.scheme != 'http' && uri.scheme != 'https') {
    return null;
  }
  if (!uri.hasScheme && !value.startsWith('/')) return null;
  return uri;
}
