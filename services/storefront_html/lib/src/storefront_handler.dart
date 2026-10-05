import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:shelf/shelf.dart' show Middleware;
import 'package:vinabike_public_core/modules/website/models/website_catalog_query.dart';
import 'package:vinabike_public_core/public_store/utils/product_url.dart';
import 'package:vinabike_public_core/shared/models/product.dart';

import 'catalog_page_model.dart';
import 'catalog_page_view.dart';
import 'product_page_model.dart';
import 'product_page_view.dart';
import 'public_reads.dart';
import 'site_layout.dart';
import 'storefront_config.dart';
import 'storefront_shell.dart';

/// The prefix Firebase Hosting forwards to this service for the hidden copy
/// of the store. Pages under it are never indexed nor measured; the same
/// pages answer without it once the public routes point here.
const hiddenRoutePrefix = '/_html';

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  caseSensitive: false,
);

/// Adds `x-storefront-source` to every response when the build knows its
/// source ([StorefrontConfig.source]).
Middleware storefrontSourceHeader(String? source) =>
    (Handler inner) => (Request request) async {
      final response = await inner(request);
      if (source == null) return response;
      return response.change(headers: {'x-storefront-source': source});
    };

/// Serves `/productos`, its categories and searches, and product pages,
/// built per visit from the public reads.
///
/// Pages are `private, no-cache`: the CDN never keeps a copy and the browser
/// asks again on every visit, so price and stock are as fresh as the base,
/// while the back button can still restore the page from memory.
Handler storefrontHandler({
  required StorefrontConfig config,
  required PublicReads reads,
}) {
  return (Request request) async {
    final requested = request.requestedUri;
    var path = requested.path;
    final hidden =
        path == hiddenRoutePrefix || path.startsWith('$hiddenRoutePrefix/');
    if (hidden) {
      path = path.substring(hiddenRoutePrefix.length);
      if (path.isEmpty) path = '/';
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      return Response(405, headers: {'allow': 'GET, HEAD'});
    }
    if (path == '/healthz') return Response.ok('ok');
    if (path.startsWith('/assets/') && config.assetsDir != null) {
      // Flutter publishes the asset key `assets/fonts/x.ttf` at
      // `/assets/assets/fonts/x.ttf`; the key is a path in the repository.
      return _localAsset(config.assetsDir!, path.substring('/assets/'.length));
    }

    final List<String> segments;
    try {
      segments = Uri(path: path).pathSegments
          .where((segment) => segment.isNotEmpty)
          .toList();
    } on Object {
      return _plainNotFound();
    }
    final route = _Route(
      config: config,
      reads: reads,
      request: request,
      path: path,
      hidden: hidden,
    );
    try {
      return switch (segments) {
        ['productos'] => await route.catalog(null),
        ['productos', 'categoria', final slug] => await route.catalog(slug),
        ['productos', final slug, final sku] => await route.product(slug, sku),
        ['productos', final id] => await route.legacyProduct(id),
        ['producto', final id] => await route.legacyProduct(id),
        _ => await route.notFound(),
      };
    } on PublicReadException catch (error) {
      stderr.writeln('read failed for $path: $error');
      return _readFailed();
    } on TimeoutException catch (error) {
      stderr.writeln('read timed out for $path: $error');
      return _readFailed();
    } on SocketException catch (error) {
      stderr.writeln('read failed for $path: $error');
      return _readFailed();
    }
  };
}

class _Route {
  _Route({
    required this.config,
    required this.reads,
    required this.request,
    required this.path,
    required this.hidden,
  });

  final StorefrontConfig config;
  final PublicReads reads;
  final Request request;
  final String path;
  final bool hidden;
  final _watch = Stopwatch()..start();

  Uri get _uri => request.requestedUri;

  PageContext _context(ShellReads read) => PageContext(
    shell: StorefrontShell.fromJson(
      read.shell,
      checkoutCapabilities: read.payments,
    ),
    tenantId: config.tenantId,
    fallbackOrigin: config.storeOrigin,
    path: path,
    query: _uri.query,
    hidden: hidden,
  );

  /// `/productos` or a category, with the visitor's search and filters.
  Future<Response> catalog(String? slug) async {
    final parsed = parseCatalogQuery(_uri);
    final legacy = slug == null ? _legacyCategoryValue() : null;
    if (legacy != null) return _legacyCategoryCatalog(legacy, parsed);
    if (slug == null) {
      // The listing does not depend on the shell: read both at once.
      final results = await Future.wait<Object>([
        reads.shell(),
        reads.catalog(
          catalogRequestFor(
            shell: null,
            categoryId: null,
            query: parsed.query,
          ),
        ),
      ]);
      final context = _context(results[0] as ShellReads);
      if (!context.shell.sitePublished) return _unpublished(context);
      return _catalogPage(
        context,
        null,
        parsed,
        results[1] as CatalogReads,
        dataMs: _watch.elapsedMilliseconds,
      );
    }

    final context = _context(await reads.shell());
    if (!context.shell.sitePublished) return _unpublished(context);
    final shell = context.shell;
    final resolved = shell.resolveCategorySlug(slug);
    if (resolved == null) {
      return _render(unavailableCategoryDocument(context), status: 404);
    }
    final canonical = shell.categoryPath(resolved.id);
    if (resolved.alias || canonical != path) {
      return _redirect(canonical, query: _uri.query);
    }
    final catalog = await reads.catalog(
      catalogRequestFor(
        shell: shell,
        categoryId: resolved.id,
        query: parsed.query,
      ),
    );
    return _catalogPage(
      context,
      resolved.id,
      parsed,
      catalog,
      dataMs: _watch.elapsedMilliseconds,
    );
  }

  Future<Response> _catalogPage(
    PageContext context,
    String? categoryId,
    ParsedCatalogQuery parsed,
    CatalogReads catalog, {
    required int dataMs,
  }) {
    final model = CatalogPageModel.build(
      page: context,
      uri: _uri,
      query: parsed.query,
      queryError: parsed.error,
      categoryId: categoryId,
      reads: catalog,
    );
    return _render(
      catalogPageDocument(model),
      indexable: model.meta.indexable,
      dataMs: dataMs,
    );
  }

  /// `/productos/<slug>/<sku>`. Another slug for the same SKU, or an old path
  /// kept in `product_url_aliases`, answers with a permanent redirect.
  Future<Response> product(String slug, String sku) async {
    final data = await reads.productPage(sku);
    final context = _context((shell: data.shell, payments: data.payments));
    if (!context.shell.sitePublished) return _unpublished(context);
    final read = data.page;
    if (read == null || read['product'] is! Map) {
      final target = await _aliasTarget(path);
      if (target != null) return _redirect(target, query: _uri.query);
      return _productNotFound(context);
    }
    final model = ProductPageModel.build(page: context, read: read);
    if (!_samePath(model.path, path)) {
      return _redirect(model.path, query: _uri.query);
    }
    return _render(
      productPageDocument(model),
      indexable: model.meta.indexable,
      dataMs: _watch.elapsedMilliseconds,
    );
  }

  /// `/productos/<uuid>` and `/producto/<uuid>`, the product routes before
  /// the SKU one, and any old path in `product_url_aliases`.
  Future<Response> legacyProduct(String id) async {
    String? target;
    if (_uuid.hasMatch(id)) {
      target = await _productPath(id);
    }
    target ??= await _aliasTarget(path);
    if (target != null && !_samePath(target, path)) {
      return _redirect(target, query: _uri.query);
    }
    final context = _context(await reads.shell());
    if (!context.shell.sitePublished) return _unpublished(context);
    return _productNotFound(context);
  }

  Future<Response> notFound() async {
    final context = _context(await reads.shell());
    return _render(
      _messagePage(
        context,
        title: 'No encontramos esta página',
        text: 'Puede que el enlace haya cambiado.',
      ),
      status: 404,
    );
  }

  /// The canonical path of a published product, by id.
  Future<String?> _productPath(String id) async {
    final row = await reads.productById(id);
    if (row == null) return null;
    final target = publicProductPath(Product.fromJson(row));
    return target == '/productos' ? null : target;
  }

  Future<String?> _aliasTarget(String aliasPath) async {
    final id = await reads.productIdForAlias(aliasPath);
    return id == null ? null : _productPath(id);
  }

  /// A category the old `?category=`, `?category_id=` or `?cat=` names, by
  /// id or slug, when it is published.
  /// The old `?category=`, `?category_id=` or `?cat=`, in the Flutter
  /// catalog's order of precedence (the first present wins, even empty).
  String? _legacyCategoryValue() {
    final parameters = _uri.queryParameters;
    final value =
        (parameters['category'] ??
                parameters['category_id'] ??
                parameters['cat'] ??
                '')
            .trim();
    return value.isEmpty ? null : value;
  }

  /// `/productos?category=<value>`: a published category opens at its own
  /// path; anything else that is not a UUID is searched for, unless the URL
  /// already searches, as the Flutter catalog does.
  Future<Response> _legacyCategoryCatalog(
    String value,
    ParsedCatalogQuery parsed,
  ) async {
    final context = _context(await reads.shell());
    if (!context.shell.sitePublished) return _unpublished(context);
    final id = context.shell.resolveCategorySlug(value)?.id;
    if (id != null) {
      return _redirect(
        context.shell.categoryPath(id),
        query: _withoutKeys(_uri, const {'category', 'category_id', 'cat'}),
      );
    }
    final query = !_uuid.hasMatch(value) && parsed.query.searchQuery.isEmpty
        ? (query: _withSearch(parsed.query, value), error: parsed.error)
        : parsed;
    final catalog = await reads.catalog(
      catalogRequestFor(shell: null, categoryId: null, query: query.query),
    );
    return _catalogPage(
      context,
      null,
      query,
      catalog,
      dataMs: _watch.elapsedMilliseconds,
    );
  }

  Future<Response> _productNotFound(PageContext context) => _render(
    _messagePage(
      context,
      title: 'Producto no encontrado',
      text: 'Puede que ya no esté a la venta o que el enlace haya cambiado.',
    ),
    status: 404,
  );

  Future<Response> _unpublished(PageContext context) =>
      _render(unpublishedPage(context), indexable: false);

  Response _redirect(String target, {String query = ''}) {
    final location = '${hidden ? hiddenRoutePrefix : ''}$target'
        '${query.isEmpty ? '' : '?$query'}';
    return Response(
      301,
      headers: {
        'location': location,
        'cache-control': 'public, max-age=300',
        if (hidden) 'x-robots-tag': 'noindex',
      },
    );
  }

  Future<Response> _render(
    Component document, {
    int status = 200,
    bool indexable = false,
    int? dataMs,
  }) async {
    final data = dataMs ?? _watch.elapsedMilliseconds;
    final rendered = await renderComponent(document, request: request);
    final html = rendered.body;
    // Neither Cloud Run nor Firebase Hosting compresses a proxied page
    // (measured 2026-10-05: 64 KB sent as is), so it is compressed here:
    // ~5× less to send to a slow phone and out of Cloud Run.
    final gzipped = _acceptsGzip(request) ? gzip.encode(html) : null;
    final renderMs = _watch.elapsedMilliseconds - data;
    return Response(
      status,
      body: gzipped ?? html,
      headers: {
        ..._pageHeaders(noindex: hidden || !indexable || status != 200),
        'vary': 'accept-encoding',
        'content-encoding': ?(gzipped == null ? null : 'gzip'),
        'server-timing': 'data;dur=$data, render;dur=$renderMs',
      },
    );
  }
}

/// A catalog URL's query, read the way the Flutter catalog reads it, plus
/// what a plain HTML form sends: a checkbox list repeats its name
/// (`brand=a&brand=b`) and an empty field still sends `min_price=`.
typedef ParsedCatalogQuery = ({WebsiteCatalogQuery query, String? error});

ParsedCatalogQuery parseCatalogQuery(Uri uri) {
  final merged = <String, String>{};
  uri.queryParametersAll.forEach((key, values) {
    final present = values
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    if (present.isEmpty) return;
    final listed =
        WebsiteCatalogQuery.specFilterKeyFromParameter(key) != null ||
        const {
          'brand',
          'brands',
          'brand_id',
          'brand_ids',
          'marca',
          'marcas',
        }.contains(key);
    merged[key] = listed ? present.join(',') : present.last;
  });
  // Old links used `?categoria=mtb` as a collection; Flutter searches it.
  final legacy = merged.remove('categoria');
  if (legacy != null && !merged.containsKey('q')) merged['q'] = legacy;

  final query = WebsiteCatalogQuery.tryParse(
    Uri(path: uri.path, queryParameters: merged),
  );
  if (query == null) {
    return (
      query: WebsiteCatalogQuery(),
      error: 'La URL contiene filtros de catálogo inválidos.',
    );
  }
  if (query.stock == WebsiteCatalogStockFilter.unavailable) {
    return (
      query: _withoutStock(query),
      error:
          'El filtro exclusivo de productos agotados todavía no está disponible.',
    );
  }
  return (query: query, error: null);
}

WebsiteCatalogQuery _withSearch(WebsiteCatalogQuery q, String search) =>
    WebsiteCatalogQuery(
      searchQuery: search,
      productType: q.productType,
      categoryScope: q.categoryScope,
      brandIds: q.brandIds,
      specFilters: q.specFilters,
      minPrice: q.minPrice,
      maxPrice: q.maxPrice,
      stock: q.stock,
      sort: q.sort,
      page: q.page,
      pageSize: q.pageSize,
    );

WebsiteCatalogQuery _withoutStock(WebsiteCatalogQuery q) => WebsiteCatalogQuery(
  searchQuery: q.searchQuery,
  productType: q.productType,
  categoryScope: q.categoryScope,
  brandIds: q.brandIds,
  specFilters: q.specFilters,
  minPrice: q.minPrice,
  maxPrice: q.maxPrice,
  sort: q.sort,
  page: q.page,
  pageSize: q.pageSize,
);

String _withoutKeys(Uri uri, Set<String> keys) {
  final kept = [
    for (final entry in uri.queryParametersAll.entries)
      if (!keys.contains(entry.key))
        for (final value in entry.value)
          '${Uri.encodeQueryComponent(entry.key)}='
              '${Uri.encodeQueryComponent(value)}',
  ];
  return kept.join('&');
}

/// The same product page whatever the encoding of its SKU.
bool _samePath(String canonical, String requested) {
  try {
    return _listEquals(
      Uri(path: canonical).pathSegments,
      Uri(path: requested).pathSegments,
    );
  } on Object {
    return false;
  }
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

Component _messagePage(
  PageContext context, {
  required String title,
  required String text,
}) => sitePage(
  context: context,
  meta: PageMeta(
    title: '$title · ${context.shell.storeName}',
    description: text,
    canonicalUrl: '${context.storeUrl}/productos',
    indexable: false,
  ),
  content: [
    div(classes: 'wrap notfound', [
      h1([.text(title)]),
      p([.text(text)]),
      a(classes: 'primary-link', href: '/productos', [
        .text('Ver todos los productos'),
      ]),
    ]),
  ],
);

/// `Accept-Encoding` names gzip with a weight above zero (`gzip;q=0` refuses
/// it).
bool _acceptsGzip(Request request) {
  for (final part in (request.headers['accept-encoding'] ?? '').split(',')) {
    final pieces = part.split(';');
    if (pieces.first.trim().toLowerCase() != 'gzip') continue;
    for (final parameter in pieces.skip(1)) {
      final pair = parameter.split('=');
      if (pair.length == 2 && pair.first.trim().toLowerCase() == 'q') {
        return (double.tryParse(pair.last.trim()) ?? 0) > 0;
      }
    }
    return true;
  }
  return false;
}

Map<String, String> _pageHeaders({
  required bool noindex,
  String contentType = 'text/html; charset=utf-8',
}) => {
  'content-type': contentType,
  'cache-control': 'private, no-cache',
  if (noindex) 'x-robots-tag': 'noindex',
};

Response _readFailed() => Response(
  503,
  body: utf8.encode(
    '<!DOCTYPE html><html lang="es-CL"><meta charset="utf-8">'
    '<meta name="robots" content="noindex"><title>Intenta de nuevo</title>'
    '<p>La tienda no pudo leer esta página. Intenta de nuevo en un momento.</p>',
  ),
  headers: {..._pageHeaders(noindex: true), 'retry-after': '5'},
);

Response _plainNotFound() => Response.notFound(
  utf8.encode(
    '<!DOCTYPE html><html lang="es-CL"><meta charset="utf-8">'
    '<meta name="robots" content="noindex"><title>No encontrado</title>'
    '<p>No encontramos esta página. <a href="/productos">Ver productos</a></p>',
  ),
  headers: _pageHeaders(noindex: true),
);

Future<Response> _localAsset(String root, String relative) async {
  final file = File('$root/$relative');
  if (relative.contains('..') || !await file.exists()) {
    return Response.notFound(null);
  }
  final type = switch (relative.split('.').last) {
    'ttf' => 'font/ttf',
    'webp' => 'image/webp',
    'png' => 'image/png',
    'svg' => 'image/svg+xml',
    _ => 'application/octet-stream',
  };
  return Response.ok(
    file.openRead(),
    headers: {
      'content-type': type,
      'cache-control': 'public, max-age=31536000, immutable',
    },
  );
}
