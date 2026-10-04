import 'dart:convert';
import 'dart:io';

import 'package:jaspr/server.dart';

import 'product_page_model.dart';
import 'product_page_view.dart';
import 'public_reads.dart';
import 'storefront_config.dart';

/// The prefix Firebase Hosting forwards to this service while it renders a
/// hidden copy of the store (phase 0). Pages also answer without it.
const hiddenRoutePrefix = '/_html';

final _productRoute = RegExp(r'^/productos/[^/]+/([^/]+)$');

/// Serves product pages, built per visit from the public reads.
///
/// Every page is `no-store`: price and stock are read on each visit, so the
/// edge never keeps an old copy. Phase 0 pages say `noindex`.
Handler storefrontHandler({
  required StorefrontConfig config,
  required PublicReads reads,
}) {
  return (Request request) async {
    var path = '/${request.url.path}';
    if (path == hiddenRoutePrefix || path.startsWith('$hiddenRoutePrefix/')) {
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

    final match = _productRoute.firstMatch(path);
    if (match == null) return _notFound();
    final sku = Uri.decodeComponent(match.group(1)!);

    final watch = Stopwatch()..start();
    final ProductPageReads data;
    try {
      data = await reads.productPage(sku);
    } on Object catch (error) {
      stderr.writeln('read failed for $sku: $error');
      return Response(
        502,
        body: 'La tienda no pudo leer este producto. Intenta de nuevo.',
        headers: _pageHeaders(contentType: 'text/plain; charset=utf-8'),
      );
    }
    final dataMs = watch.elapsedMilliseconds;
    final page = data.page;
    if (page == null || page['product'] is! Map) return _notFound();

    final model = ProductPageModel.build(
      config: config,
      shell: StorefrontShell.fromJson(data.shell),
      page: page,
    );
    final rendered = await renderComponent(
      ProductPageDocument(model),
      request: request,
    );
    final renderMs = watch.elapsedMilliseconds - dataMs;
    return Response(
      200,
      body: rendered.body,
      headers: {
        ..._pageHeaders(),
        'server-timing': 'data;dur=$dataMs, render;dur=$renderMs',
      },
    );
  };
}

Map<String, String> _pageHeaders({
  String contentType = 'text/html; charset=utf-8',
}) => {
  'content-type': contentType,
  'cache-control': 'no-store',
  'x-robots-tag': 'noindex',
};

Response _notFound() => Response.notFound(
  utf8.encode(
    '<!DOCTYPE html><html lang="es-CL"><meta charset="utf-8">'
    '<meta name="robots" content="noindex"><title>No encontrado</title>'
    '<p>No encontramos esta página. <a href="/productos">Ver productos</a></p>',
  ),
  headers: _pageHeaders(),
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
