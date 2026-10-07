import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:vinabike_public_core/public_store/models/public_policy_content.dart';
import 'package:vinabike_public_core/public_store/seo/storefront_seo_route.dart';

import '../models/website_editor_mode_route_binding.dart';
import '../providers/website_edit_mode_provider.dart' show WebsiteEditorMode;

/// The page on the editor's screen, as the store's HTML server draws it from
/// the unsaved draft (`POST /_html/editor/borrador`, phase 5b of the move to
/// HTML): the «Vista HTML» shows the real site while it is edited, from the
/// home to the catalog, a category or a product page.
///
/// The request carries the editor's own session; the server only answers
/// someone who may save the site (`can_edit_tenant_settings`).
class WebsiteHtmlDraftClient {
  WebsiteHtmlDraftClient({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const path = '/_html/editor/borrador';

  /// Asks [storeOrigin]'s server for [body] (see [websiteHtmlDraftBody]).
  Future<WebsiteHtmlDraftAnswer> draw({
    required Uri storeOrigin,
    required String accessToken,
    required String body,
  }) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri(
              scheme: storeOrigin.scheme,
              host: storeOrigin.host,
              port: storeOrigin.hasPort ? storeOrigin.port : null,
              path: path,
            ),
            headers: {
              'authorization': 'Bearer $accessToken',
              'content-type': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 20));
    } on Object {
      return const WebsiteHtmlDraftAnswer.state(
          WebsiteHtmlDraftState.unavailable);
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      decoded = null;
    }
    if (decoded is Map && decoded['html'] is String) {
      return WebsiteHtmlDraftAnswer.html(decoded['html'] as String);
    }
    final state = decoded is Map ? decoded['state']?.toString() : null;
    return WebsiteHtmlDraftAnswer.state(switch (state) {
      'expired' => WebsiteHtmlDraftState.expired,
      'forbidden' => WebsiteHtmlDraftState.forbidden,
      'invalid' => WebsiteHtmlDraftState.invalid,
      _ => WebsiteHtmlDraftState.unavailable,
    });
  }

  void close() => _client.close();
}

enum WebsiteHtmlDraftState { expired, forbidden, invalid, unavailable }

class WebsiteHtmlDraftAnswer {
  const WebsiteHtmlDraftAnswer.html(String this.html) : state = null;
  const WebsiteHtmlDraftAnswer.state(WebsiteHtmlDraftState this.state)
      : html = null;

  final String? html;
  final WebsiteHtmlDraftState? state;

  /// What the operator reads when there is no page, in the editor's words.
  String? get message => switch (state) {
        null => null,
        WebsiteHtmlDraftState.expired =>
          'Tu sesión venció. Vuelve a entrar al ERP para ver la vista HTML.',
        WebsiteHtmlDraftState.forbidden =>
          'Tu usuario no puede editar el sitio, así que no puede ver su '
              'borrador en HTML.',
        WebsiteHtmlDraftState.invalid =>
          'Esta página no se puede dibujar en HTML todavía.',
        WebsiteHtmlDraftState.unavailable =>
          'La tienda no respondió a tiempo. Reintentando con el próximo '
              'cambio.',
      };
}

/// The public path the HTML view draws for the editor's [location] (the
/// store as the ERP mounts it: `/tienda/productos` is `/productos`), with
/// its query but without the editor's own flags (`edit`, `preview`), or
/// null when the server draws no page there: the cart, the checkout, an
/// order or the customer's account stay on the canvas.
String? websiteHtmlDraftPath(Uri location) {
  location = projectWebsiteEditorModeOntoUri(
    location,
    WebsiteEditorMode.public,
  );
  final path = normalizeStorefrontSeoPath(location.path);
  final segments = path.split('/').where((s) => s.isNotEmpty).toList();
  final page = segments.isEmpty ||
      (segments.length <= 3 &&
          const {'productos', 'servicios', 'producto', 'pagina'}
              .contains(segments.first)) ||
      (segments.length == 1 &&
          (segments.first == 'contacto' ||
              publicPolicySlugs.contains(segments.first)));
  if (!page) return null;
  return Uri(
    path: path,
    query: location.query.isEmpty ? null : location.query,
  ).toString();
}

/// The open document as the server names it: the home, a page by its slug,
/// or none (a slug the server would refuse).
Map<String, Object?>? _document(String? pageId, String? pageSlug) {
  if (pageId == null) return {'home': true};
  final slug = (pageSlug ?? '').trim().toLowerCase();
  if (!RegExp(r'^[a-z0-9][a-z0-9-]{0,199}$').hasMatch(slug)) return null;
  return {'slug': slug};
}

/// The request body: the public [path] on screen, the open page with its
/// draft blocks in their order (as `replace_page_blocks` would save them)
/// and the unsaved site settings.
String websiteHtmlDraftBody({
  required String path,
  required String? pageId,
  required String? pageSlug,
  required List<Map<String, dynamic>> blocks,
  required Map<String, String> settings,
}) {
  return jsonEncode(
    {
      'path': path,
      'page': _document(pageId, pageSlug),
      'blocks': [
        for (final (index, block) in blocks.indexed)
          {
            'id': switch (block['id']?.toString().trim()) {
              final id? when id.isNotEmpty => id,
              _ => 'draft-$index',
            },
            'block_type':
                (block['block_type'] ?? block['type'] ?? '').toString(),
            'block_data': switch (block['block_data'] ?? block['data']) {
              final Map<Object?, Object?> data => data,
              _ => const <String, Object?>{},
            },
            'is_visible': block['is_visible'] ?? block['isVisible'] ?? true,
            'order_index': index,
          },
      ],
      'settings': settings,
    },
    // A draft value that is not JSON (it never should be) travels as text
    // rather than failing the whole view.
    toEncodable: (value) => value.toString(),
  );
}
