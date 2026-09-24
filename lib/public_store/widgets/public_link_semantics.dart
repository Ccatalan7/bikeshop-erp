import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../modules/website/models/website_catalog_presentation.dart';
import '../../modules/website/services/website_service.dart';

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

  /// Sólo la tienda pública (`main_store.dart`) declara enlaces. El ERP monta
  /// la misma tienda bajo `/tienda` para Edit y Preview y navega con su propia
  /// proyección de modo: ahí un `<a>` con la ruta pública sería otro destino.
  static bool publicStoreRuntime = false;

  final String? href;
  final Widget child;
  final bool enabled;

  /// Texto del enlace cuando [child] no tiene texto propio (un logo).
  final String? label;

  @override
  Widget build(BuildContext context) {
    if (!publicStoreRuntime || !enabled) return child;
    final uri = publicLinkUri(canonicalPublicHref(context, href));
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
  if (!uri.hasScheme && (!value.startsWith('/') || value.startsWith('//'))) {
    return null;
  }
  return uri;
}

const _categoryQueryKeys = ['category', 'category_id', 'cat'];

/// El destino canónico de un href escrito en el editor, el mismo al que
/// termina llegando la navegación: `/tienda/...` es la ruta montada del ERP y
/// `/productos?category=<id>` se reemplaza por la ruta de la colección. Un
/// rastreador que siguiera el href crudo llegaría a otra URL canónica.
String? canonicalPublicHref(BuildContext context, String? href) {
  final value = href?.trim() ?? '';
  final uri = Uri.tryParse(value);
  if (uri == null || uri.hasScheme || !value.startsWith('/')) return href;

  var path = uri.path;
  if (path == '/tienda') {
    path = '/';
  } else if (path.startsWith('/tienda/')) {
    path = path.substring('/tienda'.length);
  }

  final isCatalogRoot = path == '/productos' || path == '/servicios';
  final categoryId = !isCatalogRoot
      ? null
      : _categoryQueryKeys
          .map((key) => uri.queryParameters[key]?.trim() ?? '')
          .firstWhere((id) => id.isNotEmpty, orElse: () => '');
  if (categoryId != null && categoryId.isNotEmpty) {
    WebsiteCatalogPresentation? presentation;
    try {
      presentation = context
          .read<WebsiteService>()
          .catalogPresentationRegistry
          .forCategory(categoryId);
    } catch (_) {
      presentation = null;
    }
    if (presentation != null) {
      return publicCategoryPath(
        presentation: presentation,
        services: path == '/servicios',
      );
    }
  }

  return Uri(
    path: path,
    queryParameters: uri.queryParameters.isEmpty ? null : uri.queryParameters,
  ).toString();
}
