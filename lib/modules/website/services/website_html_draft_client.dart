import 'dart:convert';

import 'package:http/http.dart' as http;

/// The page the editor has open, as the store's HTML server draws it from
/// the unsaved draft (`POST /_html/editor/borrador`, phase 5b of the move to
/// HTML): the «Vista HTML» shows the real site while the page is edited.
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

/// Whether the HTML view can draw the open document: the home
/// ([pageId] null) or a page the editor creates. The catalog's and the
/// product's templates come in a later stage.
bool websiteHtmlDraftSupports({
  required String? pageId,
  required String? pageSlug,
  required bool catalogCanvas,
}) {
  if (catalogCanvas) return false;
  if (pageId == null) return true;
  final slug = pageSlug?.trim() ?? '';
  return slug.isNotEmpty && !slug.startsWith('@');
}

/// The request body: the open page, its draft blocks in their order (as
/// `replace_page_blocks` would save them) and the unsaved site settings.
String websiteHtmlDraftBody({
  required String? pageId,
  required String? pageSlug,
  required List<Map<String, dynamic>> blocks,
  required Map<String, String> settings,
}) {
  return jsonEncode(
    {
      'page': pageId == null
          ? {'home': true}
          : {'slug': (pageSlug ?? '').trim().toLowerCase()},
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
