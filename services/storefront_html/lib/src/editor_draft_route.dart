import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:jaspr/server.dart';

import 'editor_page_model.dart';
import 'editor_page_view.dart';
import 'home_page_model.dart';
import 'home_page_view.dart';
import 'public_reads.dart';
import 'site_layout.dart';
import 'storefront_config.dart';
import 'storefront_shell.dart';

/// `POST /editor/borrador` (phase 5b of the move to HTML): the page the
/// editor has open, drawn by the same components as the public page but
/// from the editor's draft, unsaved blocks and settings included, so the
/// ERP can show the real HTML site while the page is edited.
///
/// The body is `{page, blocks, settings}`: `page` is `{"home": true}` or
/// `{"slug", "title"}` (a page the editor creates); `blocks` the draft's
/// block rows (`id`, `block_type`, `block_data`, `is_visible`,
/// `order_index`), as `website_blocks` keeps them; `settings` the unsaved
/// `website_settings` values by key. The editor's session goes as
/// `authorization: Bearer <token>`, and only someone who may save the site
/// gets a page: the server asks `can_edit_tenant_settings` as that person.
///
/// Answers `{html}`, or `{state}`: `expired` (Supabase refused the token),
/// `forbidden` (the session may not edit the site), `unavailable` (the
/// reads failed; try again) or `invalid`. Never cached nor indexed, never
/// measured (the page is [PageContext.hidden]); the token is only sent to
/// Supabase, never kept nor logged.
const editorDraftPath = '/editor/borrador';

/// Where the ERP runs on the web: the only pages that may ask for a draft
/// from a browser. The native ERP sends no origin.
bool editorDraftOriginAllowed(String origin) {
  final uri = Uri.tryParse(origin);
  if (uri == null || uri.host.isEmpty) return false;
  if (uri.host == 'localhost' || uri.host == '127.0.0.1') return true;
  return uri.scheme == 'https' &&
      const {
        'project-vinabike.web.app',
        'project-vinabike.firebaseapp.com',
      }.contains(uri.host);
}

/// The most a draft may weigh: a page of blocks with every campaign layer is
/// well under a megabyte; photos travel as URLs.
const _draftLimit = 2 * 1024 * 1024;

Future<Response> editorDraftResponse(
  Request request, {
  required PublicReads reads,
  required StorefrontConfig config,
}) async {
  final cors = _cors(request);
  if (request.method == 'OPTIONS') {
    return Response(
      cors.isEmpty ? 403 : 204,
      headers: {
        ...cors,
        'access-control-allow-methods': 'POST',
        'access-control-allow-headers': 'authorization, content-type',
        'access-control-max-age': '600',
      },
    );
  }
  if (request.method != 'POST') {
    return Response(
      405,
      headers: {'allow': 'POST, OPTIONS', 'cache-control': 'no-store'},
    );
  }
  final watch = Stopwatch()..start();
  final token = _bearer(request);
  final body = await _body(request);
  final draft = body == null ? null : EditorDraft.tryParse(body);
  if (token == null || draft == null) {
    return _json(request, cors, 400, {'state': 'invalid'});
  }
  final HomePageReads data;
  try {
    if (!await reads.canEditSite(token)) {
      return _json(request, cors, 403, {'state': 'forbidden'});
    }
    data = await reads.draftPage(draft.pageRow, homeProductIds);
  } on CustomerSessionRefused {
    return _json(request, cors, 401, {'state': 'expired'});
  } on Object catch (error) {
    stderr.writeln(
      'editor draft read failed: '
      '${error is PublicReadException ? error.message : error.runtimeType}',
    );
    return _json(request, cors, 503, {'state': 'unavailable'});
  }
  final dataMs = watch.elapsedMilliseconds;
  final shell = <String, dynamic>{
    ...data.shell,
    'settings': {
      if (data.shell['settings'] case final Map<Object?, Object?> saved)
        for (final entry in saved.entries) entry.key.toString(): entry.value,
      ...draft.settings,
    },
  };
  final context = PageContext(
    shell: StorefrontShell.fromJson(shell, checkoutCapabilities: data.payments),
    tenantId: config.tenantId,
    fallbackOrigin: config.storeOrigin,
    path: draft.path,
    // Never indexed, never measured: the editor is not a visit.
    hidden: true,
    supabaseUrl: config.supabaseUrl,
    publishableKey: config.publishableKey,
  );
  final HomePageReads merged = (
    shell: shell,
    payments: data.payments,
    page: draft.pageRow,
    products: data.products,
    brandRows: data.brandRows,
    thumbnails: data.thumbnails,
  );
  final document = draft.slug == null
      ? homePageDocument(
          HomePageModel.build(page: context, reads: merged, draft: true),
        )
      : editorPageDocument(
          EditorPageModel.build(
            page: context,
            slug: draft.slug!,
            reads: merged,
            draft: true,
          ),
        );
  final rendered = await renderComponent(document, request: request);
  return _json(
    request,
    cors,
    200,
    {'html': utf8.decode(rendered.body)},
    timing:
        'data;dur=$dataMs, '
        'render;dur=${watch.elapsedMilliseconds - dataMs}',
  );
}

/// The editor's draft as the request carries it, checked.
class EditorDraft {
  EditorDraft._({
    required this.slug,
    required this.title,
    required this.blocks,
    required this.settings,
  });

  /// `null` for the home; otherwise the editor page's slug.
  final String? slug;
  final String title;
  final List<Map<String, dynamic>> blocks;
  final Map<String, String> settings;

  static final _slug = RegExp(r'^[a-z0-9][a-z0-9-]{0,199}$');

  static EditorDraft? tryParse(Map<String, Object?> body) {
    final page = body['page'];
    final blocks = body['blocks'];
    final settings = body['settings'] ?? const <String, Object?>{};
    if (page is! Map || blocks is! List || settings is! Map) return null;
    if (blocks.length > 300 || settings.length > 2000) return null;
    final String? slug;
    if (page['home'] == true) {
      slug = null;
    } else {
      final raw = page['slug']?.toString().trim().toLowerCase() ?? '';
      if (!_slug.hasMatch(raw)) return null;
      slug = raw;
    }
    final rows = <Map<String, dynamic>>[];
    for (final (index, block) in blocks.indexed) {
      if (block is! Map) return null;
      final id = block['id']?.toString() ?? '';
      final type = block['block_type']?.toString() ?? '';
      final data = block['block_data'];
      if (id.isEmpty || id.length > 200 || type.isEmpty || type.length > 80) {
        return null;
      }
      rows.add({
        'id': id,
        'block_type': type,
        'block_data': data is Map
            ? Map<String, dynamic>.from(data)
            : const <String, dynamic>{},
        'is_visible': block['is_visible'] != false,
        'order_index': (block['order_index'] as num?)?.toInt() ?? index,
      });
    }
    return EditorDraft._(
      slug: slug,
      title: page['title']?.toString() ?? '',
      blocks: rows,
      settings: {
        for (final entry in settings.entries)
          if (entry.value != null)
            entry.key.toString(): entry.value is String
                ? entry.value as String
                : jsonEncode(entry.value),
      },
    );
  }

  /// The public path the draft will have once published.
  String get path => slug == null ? '/' : '/pagina/$slug';

  /// The page as `website_pages` and its `website_blocks` give it.
  Map<String, dynamic> get pageRow => {
    'id': 'draft',
    'slug': slug ?? '',
    'title': title,
    'is_published': true,
    'website_blocks': blocks,
  };
}

Map<String, String> _cors(Request request) {
  final origin = request.headers['origin'];
  if (origin == null || !editorDraftOriginAllowed(origin)) return const {};
  return {'access-control-allow-origin': origin, 'vary': 'origin'};
}

String? _bearer(Request request) {
  final header = request.headers['authorization'] ?? '';
  if (!header.startsWith('Bearer ')) return null;
  final token = header.substring(7).trim();
  return token.length < 40 || token.length > 4096 ? null : token;
}

Future<Map<String, Object?>?> _body(Request request) async {
  try {
    final raw = await request
        .read()
        .fold<List<int>>([], (all, chunk) {
          if (all.length + chunk.length > _draftLimit) {
            throw const FormatException();
          }
          return all..addAll(chunk);
        })
        .timeout(const Duration(seconds: 15));
    final decoded = jsonDecode(utf8.decode(raw));
    return decoded is Map ? Map<String, Object?>.from(decoded) : null;
  } on Object {
    return null;
  }
}

Response _json(
  Request request,
  Map<String, String> cors,
  int status,
  Map<String, Object?> value, {
  String? timing,
}) {
  final body = utf8.encode(jsonEncode(value));
  final accepts = (request.headers['accept-encoding'] ?? '').contains('gzip');
  final gzipped = accepts && body.length > 1024 ? gzip.encode(body) : null;
  return Response(
    status,
    body: gzipped ?? body,
    headers: {
      ...cors,
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-store',
      'x-robots-tag': 'noindex',
      'vary': cors.isEmpty ? 'accept-encoding' : 'origin, accept-encoding',
      'content-encoding': ?(gzipped == null ? null : 'gzip'),
      'server-timing': ?timing,
    },
  );
}
