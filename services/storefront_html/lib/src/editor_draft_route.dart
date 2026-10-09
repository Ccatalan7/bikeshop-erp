import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:jaspr/server.dart';

import 'package:vinabike_public_core/public_store/models/public_policy_content.dart';
import 'package:vinabike_public_core/public_store/seo/public_guide.dart';

import 'editor_draft_reads.dart';
import 'editor_draft_view.dart';
import 'order_summary_pdf_route.dart';
import 'public_reads.dart';
import 'storefront_config.dart';
import 'storefront_handler.dart';

/// `POST /editor/borrador` (phase 5b of the move to HTML): a public page as
/// it will be once the editor's draft is saved, unsaved blocks and settings
/// included, so the ERP can show the real HTML site while it is edited.
/// It is drawn by the handler that serves visits ([storefrontHandler] with
/// `draft`), through reads that carry the draft ([EditorDraftReads]): the
/// home, an editor page, an information page, the catalog, a category or a
/// product page, each exactly as a visitor will get it.
///
/// The body is `{path, page, blocks, settings}`: `path` is the public path
/// (and query) on screen, `/` when absent; `page` the page the editor has
/// open, `{"home": true}` or `{"slug", "title"}` (`null` while it has
/// none, as on a catalog page opened directly); `blocks` that page's draft
/// block rows (`id`, `block_type`, `block_data`, `is_visible`,
/// `order_index`), as `website_blocks` keeps them; `settings` the unsaved
/// `website_settings` values by key; `footer_navigation`, when the footer's
/// menu has unsaved changes, all of it as drafted (`website_navigation`
/// rows). The editor's session goes as
/// `authorization: Bearer <token>`, and only someone who may save the site
/// gets a page: the server asks `can_edit_tenant_settings` as that person.
///
/// Answers `{html, status}` (the page and the status a visitor would get),
/// or `{state}`: `expired` (Supabase refused the token), `forbidden` (the
/// session may not edit the site), `unavailable` (the reads failed; try
/// again) or `invalid` (including a path that is not a page). Never cached
/// nor indexed, never measured (the page is drawn hidden); the token is
/// only sent to Supabase, never kept nor logged.
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
  required OrderSummaryFonts fonts,
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
  // The session first: nobody without one gets the server to read up to two
  // megabytes of body for them (Codex review, 2026-10-07).
  final token = _bearer(request);
  if (token == null) return _json(request, cors, 400, {'state': 'invalid'});
  try {
    if (!await reads.canEditSite(token)) {
      return _json(request, cors, 403, {'state': 'forbidden'});
    }
  } on CustomerSessionRefused {
    return _json(request, cors, 401, {'state': 'expired'});
  } on Object catch (error) {
    stderr.writeln(
      'editor draft check failed: '
      '${error is PublicReadException ? error.message : error.runtimeType}',
    );
    return _json(request, cors, 503, {'state': 'unavailable'});
  }
  final body = await _body(request);
  final draft = body == null ? null : EditorDraft.tryParse(body);
  if (draft == null) return _json(request, cors, 400, {'state': 'invalid'});
  final handler = storefrontHandler(
    config: config,
    reads: EditorDraftReads(
      reads,
      home: draft.home,
      document: draft.slug,
      title: draft.title,
      template: draft.template,
      blocks: draft.blocks,
      settings: draft.settings,
      footerNavigation: draft.footerNavigation,
    ),
    orderSummaryFonts: fonts,
    draft: true,
    draftShowsHidden: !draft.preview,
  );
  final origin = Uri.parse(config.storeOrigin);
  var target = draft.path;
  // A path the store moves (a renamed category, an old product link) is
  // drawn where it lands, as the visitor's browser would follow it.
  for (var hop = 0; ; hop++) {
    final Response page;
    try {
      page = await handler(
        Request(
          'GET',
          origin.replace(
            path: '$hiddenRoutePrefix${target.path}',
            query: target.query.isEmpty ? null : target.query,
          ),
        ),
      );
    } on Object catch (error) {
      stderr.writeln('editor draft render failed: ${error.runtimeType}');
      return _json(request, cors, 503, {'state': 'unavailable'});
    }
    final location = page.headers['location'];
    if (page.statusCode >= 300 && page.statusCode < 400 && location != null) {
      final next = EditorDraft.publicPath(
        location.startsWith(hiddenRoutePrefix)
            ? location.substring(hiddenRoutePrefix.length)
            : location,
      );
      if (hop >= 3 || next == null) {
        return _json(request, cors, 400, {'state': 'invalid'});
      }
      target = next;
      continue;
    }
    final html = await page.readAsString();
    if (page.statusCode >= 500 || !html.contains('</body>')) {
      return _json(request, cors, 503, {'state': 'unavailable'});
    }
    final end = html.lastIndexOf('</body>');
    return _json(request, cors, 200, {
      'html': html.replaceRange(end, end, draftExtrasHtml),
      'status': page.statusCode,
    }, timing: 'total;dur=${watch.elapsedMilliseconds}');
  }
}

/// The editor's draft as the request carries it, checked.
class EditorDraft {
  EditorDraft._({
    required this.home,
    required this.slug,
    required this.title,
    required this.path,
    required this.blocks,
    required this.settings,
    required this.footerNavigation,
    this.template,
    this.preview = false,
  });

  /// The open page's template as the editor has it (`blog` for a guide);
  /// null when the editor does not say.
  final String? template;

  /// «Vista previa» (as the customer sees it): blocks the store hides stay
  /// out instead of being drawn veiled.
  final bool preview;

  /// The page the editor has open: the home, a page by its [slug], or none.
  final bool home;
  final String? slug;
  final String title;

  /// The public path (and query) to draw.
  final Uri path;
  final List<Map<String, dynamic>> blocks;
  final Map<String, String> settings;

  /// The footer's menu as drafted, or null when it has no unsaved change.
  final List<Map<String, dynamic>>? footerNavigation;

  static final _slug = RegExp(r'^[a-z0-9][a-z0-9-]{0,199}$');
  static final _template = RegExp(r'^[a-z][a-z-]{0,39}$');

  /// The first segments of the paths a draft draws: pages, never a cart, a
  /// checkout, an order or an account.
  static const _pages = {
    'productos',
    'servicios',
    'producto',
    'pagina',
    'guias',
  };

  /// [raw] as a public page's path and query, or null when it is not one.
  static Uri? publicPath(String raw) {
    final text = raw.trim();
    if (text.isEmpty || text.length > 1000) return null;
    if (!text.startsWith('/') || text.startsWith('//')) return null;
    final uri = Uri.tryParse(text);
    if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final page =
        segments.isEmpty ||
        (segments.length <= 3 && _pages.contains(segments.first)) ||
        (segments.length == 1 &&
            (segments.first == 'contacto' ||
                publicPolicySlugs.contains(segments.first)));
    if (!page) return null;
    return Uri(
      path: '/${segments.join('/')}',
      query: uri.query.isEmpty ? null : uri.query,
    );
  }

  static EditorDraft? tryParse(Map<String, Object?> body) {
    final page = body['page'];
    final blocks = body['blocks'];
    final settings = body['settings'] ?? const <String, Object?>{};
    if (page is! Map? || blocks is! List || settings is! Map) return null;
    if (blocks.length > 300 || settings.length > 2000) return null;
    final String? slug;
    if (page == null || page['home'] == true) {
      slug = null;
    } else {
      final raw = page['slug']?.toString().trim().toLowerCase() ?? '';
      if (!_slug.hasMatch(raw)) return null;
      slug = raw;
    }
    final List<Map<String, dynamic>>? footer;
    switch (body['footer_navigation']) {
      case null:
        footer = null;
      case final List<Object?> rows when rows.length <= 500:
        footer = [];
        for (final row in rows) {
          if (row is! Map || row['id'] is! String) return null;
          footer.add({
            ...Map<String, dynamic>.from(row),
            'menu_location': 'footer',
          });
        }
      default:
        return null;
    }
    final template = switch (page?['template']) {
      final String value when _template.hasMatch(value) => value,
      _ => null,
    };
    final path = switch (body['path']) {
      null => Uri(
        path: slug == null
            ? '/'
            : slug == websiteGuidesIndexSlug
            ? websiteGuidesIndexPath
            : template == websiteGuideTemplate
            ? websiteGuidePath(slug)
            : '/pagina/$slug',
      ),
      final raw => publicPath(raw.toString()),
    };
    if (path == null) return null;
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
      home: page?['home'] == true,
      slug: slug,
      title: page?['title']?.toString() ?? '',
      template: template,
      path: path,
      blocks: rows,
      footerNavigation: footer,
      settings: {
        for (final entry in settings.entries)
          if (entry.value != null)
            entry.key.toString(): entry.value is String
                ? entry.value as String
                : jsonEncode(entry.value),
      },
      preview: body['preview'] == true,
    );
  }
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
