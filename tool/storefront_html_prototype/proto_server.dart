// Ficha de producto en HTML, generada en el servidor en cada visita.
//
// Prueba de la migración (2026-10-04): lee las mismas funciones públicas de
// Supabase que la tienda Flutter y reutiliza, sin copiarlo, el código Dart que
// ya decide cómo se ve un producto: la proyección comercial, la ficha técnica,
// el texto SEO, las rutas de categoría y los datos para Google.
//
// Cómo correrla: tool/storefront_html_prototype/README.md. Plan:
// docs/architecture/storefront-html-migration-plan.md.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vinabike_erp/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_erp/modules/website/theme/website_theme_color_value.dart';
import 'package:vinabike_erp/public_store/models/public_business_hours.dart';
import 'package:vinabike_erp/public_store/models/public_commerce_product_projection.dart';
import 'package:vinabike_erp/public_store/models/public_product_seo_copy.dart';
import 'package:vinabike_erp/public_store/models/public_product_spec_sheet.dart';
import 'package:vinabike_erp/public_store/models/storefront_logo_source.dart';
import 'package:vinabike_erp/public_store/seo/public_product_structured_data.dart';
import 'package:vinabike_erp/public_store/utils/product_url.dart';
import 'package:vinabike_erp/shared/utils/chilean_utils.dart';

const supabaseUrl = 'https://xzdvtzdqjeyqxnkqprtf.supabase.co';
const storeOrigin = 'https://vinabike.cl';
const tenantId = VinabikeCanonicalTenant.id;

late final String apiKey;
late final String repoDir;

Future<void> main(List<String> args) async {
  apiKey = Platform.environment['SUPABASE_PUBLISHABLE_KEY']?.trim() ?? '';
  if (apiKey.isEmpty) {
    stderr.writeln('Falta SUPABASE_PUBLISHABLE_KEY');
    exit(2);
  }
  repoDir = _arg(args, '--repo') ?? Directory.current.path;
  final port = int.parse(_arg(args, '--port') ?? '4325');
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  server.autoCompress = true;
  stdout.writeln('Ficha HTML de prueba en http://localhost:$port/');
  await for (final request in server) {
    unawaited(_handle(request));
  }
}

String? _arg(List<String> args, String name) {
  final i = args.indexOf(name);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
}

// ---------------------------------------------------------------------------
// Rutas
// ---------------------------------------------------------------------------

Future<void> _handle(HttpRequest request) async {
  final path = request.uri.path;
  final response = request.response;
  try {
    if (path.startsWith('/assets/assets/')) {
      await _serveAsset(request, path.substring('/assets/'.length));
      return;
    }
    final match = RegExp(r'^/productos/[^/]+/([^/]+)$').firstMatch(path);
    if (path == '/') {
      response.statusCode = 302;
      response.headers.set('location',
          '/productos/horquilla-suntour-29-auron-35-eq-lo-rc-160mm-15x110mm-blanco-2022/H911');
      await response.close();
      return;
    }
    if (match == null) {
      response.statusCode = 404;
      response.headers.contentType = ContentType.html;
      response.write('<p>En la prueba sólo existen las fichas: '
          '<code>/productos/&lt;nombre&gt;/&lt;sku&gt;</code></p>');
      await response.close();
      return;
    }
    final sku = Uri.decodeComponent(match.group(1)!);
    final watch = Stopwatch()..start();
    final page = await _loadProductPage(sku);
    final dataMs = watch.elapsedMilliseconds;
    if (page == null) {
      response.statusCode = 404;
      response.headers.contentType = ContentType.html;
      response.write('<p>Producto no encontrado.</p>');
      await response.close();
      return;
    }
    final html = renderProductPage(page);
    response.headers.contentType = ContentType.html;
    response.headers.set('cache-control', 'no-store');
    response.headers.set('server-timing',
        'data;dur=$dataMs, render;dur=${watch.elapsedMilliseconds - dataMs}');
    response.write(html);
    await response.close();
  } catch (error, stack) {
    stderr.writeln('$path → $error\n$stack');
    response.statusCode = 500;
    response.write('Error: $error');
    await response.close();
  }
}

Future<void> _serveAsset(HttpRequest request, String relative) async {
  final file = File('$repoDir/$relative');
  if (relative.contains('..') || !file.existsSync()) {
    request.response.statusCode = 404;
    await request.response.close();
    return;
  }
  final type = relative.endsWith('.ttf')
      ? 'font/ttf'
      : relative.endsWith('.webp')
          ? 'image/webp'
          : 'application/octet-stream';
  request.response.headers.set('content-type', type);
  request.response.headers
      .set('cache-control', 'public, max-age=31536000, immutable');
  await request.response.addStream(file.openRead());
  await request.response.close();
}

// ---------------------------------------------------------------------------
// Datos: las mismas lecturas públicas que la tienda Flutter
// ---------------------------------------------------------------------------

final HttpClient _http = HttpClient()
  ..connectionTimeout = const Duration(seconds: 10);

Future<dynamic> _rpc(String fn, Map<String, Object?> body) => _send(
      'POST',
      Uri.parse('$supabaseUrl/rest/v1/rpc/$fn'),
      body: {
        for (final e in body.entries)
          if (e.value != null) e.key: e.value
      },
    );

Future<List<dynamic>> _table(String query) async =>
    (await _send('GET', Uri.parse('$supabaseUrl/rest/v1/$query'))) as List;

Future<dynamic> _send(String method, Uri uri, {Object? body}) async {
  final request = await _http.openUrl(method, uri);
  request.headers.set('apikey', apiKey);
  request.headers.set('authorization', 'Bearer $apiKey');
  if (body != null) {
    request.headers.contentType = ContentType.json;
    request.write(jsonEncode(body));
  }
  final response = await request.close().timeout(const Duration(seconds: 20));
  final text = await response.transform(utf8.decoder).join();
  if (response.statusCode >= 300) {
    throw HttpException('$method ${uri.path} → ${response.statusCode} $text');
  }
  return jsonDecode(text);
}

/// Lo que cambia poco (tema, menús, categorías) se guarda un minuto en
/// memoria: en la migración real lo invalida la base al cambiar.
class SharedData {
  SharedData(this.settings, this.navigation, this.pagesById, this.categories,
      this.tiers);
  final Map<String, String> settings;
  final List<Map<String, dynamic>> navigation;
  final Map<String, Map<String, dynamic>> pagesById;
  final Map<String, Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> tiers;
  final DateTime readAt = DateTime.now();
}

SharedData? _shared;

Future<SharedData> _sharedData() async {
  final cached = _shared;
  if (cached != null &&
      DateTime.now().difference(cached.readAt) < const Duration(minutes: 1)) {
    return cached;
  }
  final results = await Future.wait([
    _rpc('get_public_store_data', {'p_tenant_id': tenantId}),
    _table('website_navigation?tenant_id=eq.$tenantId&is_visible=eq.true'
        '&select=id,menu_location,label,link_type,link_value,parent_id,'
        'order_index,show_on_desktop,show_on_mobile&order=order_index.asc'),
    _table('website_pages?tenant_id=eq.$tenantId&is_published=eq.true'
        '&select=id,slug,is_home,title'),
    _table('product_categories?tenant_id=eq.$tenantId&is_active=eq.true'
        '&select=id,name,parent_id,full_path,show_on_website'),
    _rpc('get_public_online_shipping_tiers', {'p_tenant_id': tenantId}),
  ]);
  final store = results[0] as Map<String, dynamic>;
  final settings = <String, String>{
    for (final e in (store['settings'] as Map).entries)
      e.key.toString(): e.value?.toString() ?? '',
  };
  return _shared = SharedData(
    settings,
    [for (final r in results[1] as List) Map<String, dynamic>.from(r as Map)],
    {
      for (final r in results[2] as List)
        (r as Map)['id'].toString(): Map<String, dynamic>.from(r),
    },
    {
      for (final r in results[3] as List)
        (r as Map)['id'].toString(): Map<String, dynamic>.from(r),
    },
    [for (final r in results[4] as List) Map<String, dynamic>.from(r as Map)],
  );
}

class ProductPage {
  ProductPage({
    required this.shared,
    required this.row,
    required this.commerce,
    required this.sheet,
    required this.trail,
    required this.related,
    required this.seo,
    required this.productUrl,
  });

  final SharedData shared;
  final Map<String, dynamic> row;
  final PublicCommerceProductProjection commerce;
  final PublicProductSpecSheet sheet;
  final List<({String name, String? path})> trail;
  final List<({PublicCommerceProductProjection commerce, String path})> related;
  final PublicProductSeoCopy seo;
  final String productUrl;
}

Future<ProductPage?> _loadProductPage(String sku) async {
  final sharedFuture = _sharedData();
  final rows = await _rpc('get_public_products', {
    'p_tenant_id': tenantId,
    'p_sku': sku,
    'p_only_in_stock': false,
    'p_limit': 1,
  }) as List;
  if (rows.isEmpty) return null;
  final base = Map<String, dynamic>.from(rows.first as Map);
  final id = base['id'].toString();
  final categoryId = (base['category_id'] ?? '').toString();
  final brandId = (base['brand_id'] ?? '').toString();

  final results = await Future.wait([
    _table('products?tenant_id=eq.$tenantId&id=eq.$id&select='
        'website_name,website_price,website_description,'
        'website_seo_title,website_seo_description,website_search_terms,'
        'website_merchant_title,website_merchant_description,'
        'website_merchant_brand,website_merchant_gtin,website_merchant_mpn,'
        'website_image_url,website_image_url_optimized,website_image_urls,'
        'price_currency,is_set'),
    brandId.isEmpty
        ? Future.value(const [])
        : _table('product_brands?id=eq.$brandId&select=id,name,tenant_id,'
            'is_active'),
    _rpc('get_public_product_technical_specs',
        {'p_tenant_id': tenantId, 'p_product_id': id}),
    categoryId.isEmpty
        ? Future.value(const [])
        : _rpc('get_public_products', {
            'p_tenant_id': tenantId,
            'p_category_ids': [categoryId],
            'p_only_in_stock': true,
            'p_limit': 9,
          }),
    sharedFuture,
  ]);
  final enrichment = (results[0] as List).isEmpty
      ? const <String, dynamic>{}
      : Map<String, dynamic>.from((results[0] as List).first as Map);
  final row = {...base, ...enrichment};
  final brandRows = results[1] as List;
  final brand = brandRows.isEmpty ||
          (brandRows.first as Map)['is_active'] != true ||
          !{
            '',
            tenantId
          }.contains(((brandRows.first as Map)['tenant_id'] ?? '').toString())
      ? null
      : (brandRows.first as Map)['name']?.toString();
  final shared = results[4] as SharedData;

  final trail = _categoryTrail(categoryId, shared);
  final commerce = PublicCommerceProductProjection.fromJson(
    row,
    resolvedBrand: brand,
    categoryPath:
        (shared.categories[categoryId]?['full_path'] ?? '').toString(),
  );
  final specRows = [
    for (final r in results[2] as List)
      PublicProductSpecRow.fromJson(Map<String, dynamic>.from(r as Map)),
  ].where((r) => r.value.isNotEmpty).toList();
  final sheet = PublicProductSpecSheet.build(
    rows: specRows,
    identity: PublicSpecIdentity(
      brand: commerce.brand.isEmpty ? null : commerce.brand,
      model: _text(row['model']),
      manufacturerSku: _text(row['manufacturer_sku']),
      gtin: commerce.gtin.isEmpty ? null : commerce.gtin,
    ),
  );

  final settings = shared.settings;
  final storeName = settings['seo_business_name']?.trim().isNotEmpty == true
      ? settings['seo_business_name']!.trim()
      : (settings['store_name'] ?? 'Viñabike');
  final seo = resolvePublicProductSeoCopyFromInput(
    PublicProductSeoCopyInput(
      seoTitleOverride: _text(row['website_seo_title']) ?? '',
      seoDescriptionOverride: _text(row['website_seo_description']) ?? '',
      titleTemplate:
          settings['seo_product_title_template']?.trim().isNotEmpty == true
              ? settings['seo_product_title_template']!
              : '{product_name} | $storeName',
      descriptionTemplate:
          settings['seo_product_description_template']?.trim().isNotEmpty ==
                  true
              ? settings['seo_product_description_template']!
              : '{product_description}',
      storeName: storeName,
      locality: settings['seo_address_city'] ?? '',
      searchTerms: [
        for (final t in (row['website_search_terms'] as List?) ?? const [])
          t.toString(),
      ],
      product: PublicProductSeoProductInput(
        name: commerce.title,
        sku: commerce.sku,
        price: commerce.price,
        brand: commerce.brand,
        description: commerce.description,
        categoryPath: commerce.categoryPath,
      ),
    ),
  );

  final productPath = buildPublicProductPath(
    name: _text(row['website_name']) ?? (row['name'] ?? '').toString(),
    sku: commerce.sku,
    fallbackProductId: id,
  );
  return ProductPage(
    shared: shared,
    row: row,
    commerce: commerce,
    sheet: sheet,
    trail: trail,
    related: [
      for (final r in results[3] as List)
        if ((r as Map)['id'].toString() != id)
          (
            commerce: PublicCommerceProductProjection.fromJson(
                Map<String, dynamic>.from(r)),
            path: buildPublicProductPath(
              name: (r['name'] ?? '').toString(),
              sku: (r['sku'] ?? '').toString(),
              fallbackProductId: r['id'].toString(),
            ),
          ),
    ].where((p) => p.commerce.imageUrls.isNotEmpty).take(8).toList(),
    seo: seo,
    productUrl: '$storeOrigin$productPath',
  );
}

String? _text(Object? value) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? null : text;
}

WebsiteCatalogPresentationRegistry _registry(SharedData shared) =>
    WebsiteCatalogPresentationRegistry.decode(
        shared.settings[websiteCatalogPresentationsSettingKey]);

String _categoryPath(String id, SharedData shared) {
  final name = (shared.categories[id]?['name'] ?? '').toString();
  return publicCategoryPath(
    presentation: _registry(shared).forCategory(id) ??
        WebsiteCatalogPresentation.fallback(categoryId: id, categoryName: name),
  );
}

/// El recorrido que muestra la miga de la ficha: cada categoría desde la raíz,
/// con enlace sólo si es un destino público.
List<({String name, String? path})> _categoryTrail(
    String categoryId, SharedData shared) {
  final trail = <({String name, String? path})>[];
  final seen = <String>{};
  var current = categoryId;
  while (current.isNotEmpty && seen.add(current)) {
    final category = shared.categories[current];
    if (category == null) break;
    trail.insert(0, (
      name: category['name'].toString(),
      path: category['show_on_website'] == true
          ? _categoryPath(current, shared)
          : null,
    ));
    current = (category['parent_id'] ?? '').toString();
  }
  return trail;
}

String _navHref(Map<String, dynamic> item, SharedData shared) {
  final type = item['link_type']?.toString() ?? '';
  final value = (item['link_value'] ?? '').toString();
  if (type == 'page') {
    final page = shared.pagesById[value];
    if (page != null) {
      return page['is_home'] == true ? '/' : '/${page['slug']}';
    }
    return value == '/tienda' ? '/' : value;
  }
  if (type == 'category') {
    final id = Uri.tryParse(value)?.queryParameters['category'] ?? '';
    if (shared.categories.containsKey(id)) return _categoryPath(id, shared);
  }
  return value.isEmpty ? '/' : value;
}

// ---------------------------------------------------------------------------
// HTML
// ---------------------------------------------------------------------------

String _e(Object? value) => const HtmlEscape().convert('${value ?? ''}');

String _hex(String? raw, String fallback) {
  final argb = parseWebsiteThemeColorValue(raw ?? '');
  if (argb == null) return fallback;
  return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
}

String _price(double value) =>
    ChileanUtils.formatCurrency(value).replaceFirst(r'$ ', r'$');

String renderProductPage(ProductPage page) {
  final s = page.shared.settings;
  final c = page.commerce;
  final inStock = c.availability == PublicCommerceAvailability.inStock;
  final primary = _hex(s['theme_primary_color'], '#123f68');
  final accent = _hex(s['theme_accent_color'], '#ff7000');
  final storeName = s['store_name']?.trim().isNotEmpty == true
      ? s['store_name']!
      : 'Viñabike';
  final logo = storefrontFirstLogoSource(
    configuredUrl: s['logo_url'] ?? '',
    tenantId: tenantId,
  );
  final logoUrl = logo.startsWith('http') ? logo : '/$logo';
  final whatsapp = (s['whatsapp'] ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  final waText = Uri.encodeComponent(
      'Hola, quiero consultar por ${c.title} (${c.sku}): ${page.productUrl}');
  final address = s['contact_address'] ?? '';
  final structured = buildPublicProductStructuredData(
    commerce: c,
    productUrl: page.productUrl,
    storeUrl: storeOrigin,
    storeName: storeName,
    categoryTrail: [
      for (final crumb in page.trail)
        if (crumb.path != null)
          PublicStructuredDataCrumb(crumb.name, '$storeOrigin${crumb.path}'),
    ],
    specSheet: page.sheet,
    model: _text(page.row['model']) ?? '',
  );
  final cheapestShipping = page.shared.tiers.isEmpty
      ? null
      : page.shared.tiers
          .map((t) => (t['shipping_gross'] as num).toDouble())
          .reduce((a, b) => a < b ? a : b);
  final days = page.shared.tiers.isEmpty
      ? null
      : '${page.shared.tiers.first['estimated_min_business_days']} a '
          '${page.shared.tiers.first['estimated_max_business_days']}';

  final images = c.imageUrls;
  final description = c.description
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .split(RegExp(r'\n\s*\n|\\n\\n'))
      .map((p) => p.replaceAll(RegExp(r'\s+'), ' ').trim())
      .where((p) => p.isNotEmpty)
      .toList();
  final technicalGroups = page.sheet.groups;

  final b = StringBuffer();
  b.write('''<!DOCTYPE html>
<html lang="es-CL">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_e(page.seo.title.isNotEmpty ? page.seo.title : c.title)}</title>
<meta name="description" content="${_e(page.seo.description)}">
<meta name="robots" content="noindex">
<link rel="canonical" href="${_e(page.productUrl)}">
<meta property="og:type" content="product">
<meta property="og:title" content="${_e(c.title)}">
<meta property="og:description" content="${_e(page.seo.description)}">
${images.isEmpty ? '' : '<meta property="og:image" content="${_e(images.first)}">'}
<link rel="preload" href="/assets/assets/fonts/Oswald-wght.ttf" as="font" type="font/ttf" crossorigin>
${images.isEmpty ? '' : '<link rel="preload" as="image" href="${_e(images.first)}" fetchpriority="high">'}
<style>${_css(primary: primary, accent: accent)}</style>
${structured == null ? '' : '<script type="application/ld+json">${encodeStructuredDataForHtml(structured)}</script>'}
</head>
<body>
<a class="skip" href="#contenido">Ir al contenido</a>
''');
  b.write(_header(page, logoUrl, storeName));
  b.write('<main id="contenido">');

  // Miga
  b.write('<nav class="crumbs wrap" aria-label="Estás en"><ol>'
      '<li><a href="/">Inicio</a></li><li><a href="/productos">Productos</a></li>');
  for (final crumb in page.trail) {
    b.write(crumb.path == null
        ? '<li><span>${_e(crumb.name)}</span></li>'
        : '<li><a href="${_e(crumb.path)}">${_e(crumb.name)}</a></li>');
  }
  b.write(
      '<li aria-current="page"><span>${_e(c.title)}</span></li></ol></nav>');

  // Producto
  b.write('<section class="product wrap">');
  b.write('<div class="gallery">');
  if (images.isNotEmpty) {
    b.write('<figure class="stage"><img id="foto" src="${_e(images.first)}" '
        'alt="${_e(c.title)}" width="900" height="900" fetchpriority="high" '
        'decoding="async"></figure>');
    if (images.length > 1) {
      b.write('<ul class="thumbs" aria-label="Fotos">');
      for (var i = 0; i < images.length; i++) {
        b.write('<li><button type="button" data-src="${_e(images[i])}" '
            'aria-label="Foto ${i + 1} de ${images.length}"'
            '${i == 0 ? ' aria-current="true"' : ''}>'
            '<img src="${_e(images[i])}" alt="" loading="lazy" width="96" height="96">'
            '</button></li>');
      }
      b.write('</ul>');
    }
  }
  b.write('</div>');

  b.write('<div class="buy">');
  if (c.brand.isNotEmpty) b.write('<p class="brand">${_e(c.brand)}</p>');
  b.write('<h1>${_e(c.title)}</h1>');
  final model = _text(page.row['model']);
  b.write('<p class="ids">'
      '${model == null ? '' : '<span>Modelo ${_e(model)}</span>'}'
      '<span>Código ${_e(c.sku)}</span></p>');
  b.write('<div class="price-row"><p class="price">'
      '${c.price > 0 ? _e(_price(c.price)) : 'Consultar'}</p>'
      '<p class="tax">Precio final con IVA incluido</p></div>');
  b.write(inStock
      ? '<p class="stock ok"><span aria-hidden="true"></span>Disponible</p>'
      : '<p class="stock out"><span aria-hidden="true"></span>Agotado</p>');

  final highlights = page.sheet.highlights;
  if (highlights.isNotEmpty) {
    b.write('<dl class="highlights">');
    for (final item in highlights) {
      b.write(
          '<div><dt>${_e(item.label)}</dt><dd>${_e(item.value)}</dd></div>');
    }
    b.write(
        '</dl><a class="to-sheet" href="#ficha">Ver ficha técnica completa</a>');
  }

  b.write('<form class="cart" onsubmit="return protoCart(event)">');
  if (inStock) {
    b.write('<label class="qty"><span class="sr">Cantidad</span>'
        '<input type="number" name="cantidad" min="1" value="1" inputmode="numeric"></label>'
        '<button class="primary" type="submit">Agregar al carrito</button>');
  } else {
    b.write(
        '<button class="primary" type="button" disabled>Sin stock</button>');
  }
  b.write('</form><p class="proto-note" id="proto-note" hidden>'
      'Prueba: el carrito se conecta en la fase 1.</p>');
  if (whatsapp.isNotEmpty) {
    b.write('<a class="secondary" href="https://wa.me/$whatsapp?text=$waText" '
        'rel="noopener">Preguntar por WhatsApp</a>');
  }
  b.write('<ul class="promises">');
  if (address.isNotEmpty) {
    b.write('<li><strong>Retiro gratis en tienda</strong>'
        '<span>${_e(address)}</span></li>');
  }
  if (cheapestShipping != null) {
    b.write('<li><strong>Despacho a domicilio</strong>'
        '<span>Chile continental, desde ${_e(_price(cheapestShipping))}, '
        '$days días hábiles. <a href="/envios">Tarifas</a></span></li>');
  }
  // Los términos viven en la página del editor; aquí sólo se enlaza.
  b.write('<li><strong>Cambios y devoluciones</strong><span>'
      '<a href="/devoluciones">Política de devoluciones</a></span></li>');
  b.write('</ul></div></section>');

  // Ficha técnica
  if (technicalGroups.isNotEmpty || description.isNotEmpty) {
    b.write('<section class="details wrap" id="ficha">');
    b.write(
        '<h2>${page.sheet.hasTechnicalData ? 'Ficha técnica' : 'Detalles del producto'}</h2>');
    if (description.isNotEmpty) {
      b.write('<div class="description">');
      for (final paragraph in description) {
        b.write('<p>${_e(paragraph)}</p>');
      }
      b.write('</div>');
    }
    if (technicalGroups.isNotEmpty) {
      b.write('<div class="sheet">');
      for (final group in technicalGroups) {
        b.write('<section class="group"><h3>${_e(group.title)}</h3><dl>');
        for (final item in group.items) {
          b.write('<div><dt>${_e(item.label)}'
              '${item.hint == null ? '' : '<small>${_e(item.hint)}</small>'}</dt>'
              '<dd>${_e(item.value).replaceAll('\n', '<br>')}'
              '${item.detail == null ? '' : ' <span class="detail">${_e(item.detail)}</span>'}'
              '</dd></div>');
        }
        b.write('</dl></section>');
      }
      b.write('</div>');
    }
    b.write('</section>');
  }

  // Relacionados
  if (page.related.isNotEmpty) {
    final categoryName =
        page.trail.isEmpty ? 'esta categoría' : page.trail.last.name;
    final categoryPath = page.trail.isEmpty ? null : page.trail.last.path;
    b.write('<section class="related wrap"><div class="related-head">'
        '<h2>Más en ${_e(categoryName)}</h2>'
        '${categoryPath == null ? '' : '<a href="${_e(categoryPath)}">Ver todo</a>'}'
        '</div><ul>');
    for (final item in page.related) {
      b.write('<li><a href="${_e(item.path)}">'
          '<img src="${_e(item.commerce.imageUrls.first)}" alt="" loading="lazy" '
          'width="320" height="320">'
          '<span class="name">${_e(item.commerce.title)}</span>'
          '<span class="p">${_e(_price(item.commerce.price))}</span></a></li>');
    }
    b.write('</ul></section>');
  }
  b.write('</main>');
  b.write(_footer(page, storeName));

  // Barra fija en el teléfono
  if (c.price > 0) {
    b.write('<div class="buybar"><span>${_e(_price(c.price))}</span>'
        '<button class="primary" type="button" '
        '${inStock ? 'onclick="protoCart(event)"' : 'disabled'}>'
        '${inStock ? 'Agregar al carrito' : 'Sin stock'}</button></div>');
  }
  b.write('''<script>
function protoCart(e){e.preventDefault();var n=document.getElementById('proto-note');if(n)n.hidden=false;return false}
document.querySelectorAll('.thumbs button').forEach(function(t){t.addEventListener('click',function(){
var f=document.getElementById('foto');f.src=t.dataset.src;
document.querySelectorAll('.thumbs button').forEach(function(o){o.removeAttribute('aria-current')});
t.setAttribute('aria-current','true')})});
</script>
</body></html>''');
  return b.toString();
}

String _header(ProductPage page, String logoUrl, String storeName) {
  final items = page.shared.navigation
      .where((n) => n['menu_location'] == 'header' && n['parent_id'] == null)
      .toList();
  final b = StringBuffer('<header class="top"><div class="wrap bar">'
      '<a class="logo" href="/"><img src="${_e(logoUrl)}" alt="${_e(storeName)}" '
      'width="150" height="40"></a>'
      // Sin JavaScript: una casilla abre el menú en el teléfono; en escritorio
      // el menú está siempre a la vista.
      '<input type="checkbox" id="menu-toggle" class="menu-toggle">'
      '<label for="menu-toggle" class="menu-button" aria-label="Menú">'
      '<span></span><span></span><span></span></label>'
      '<div class="menu"><nav aria-label="Principal"><ul>');
  for (final item in items) {
    final children = page.shared.navigation
        .where((n) => n['parent_id'] == item['id'])
        .toList();
    if (children.isEmpty) {
      b.write('<li><a href="${_e(_navHref(item, page.shared))}">'
          '${_e(item['label'])}</a></li>');
    } else {
      b.write(
          '<li class="has-sub"><a href="${_e(_navHref(item, page.shared))}">'
          '${_e(item['label'])}</a><ul class="sub">');
      for (final child in children) {
        b.write('<li><a href="${_e(_navHref(child, page.shared))}">'
            '${_e(child['label'])}</a></li>');
      }
      b.write('</ul></li>');
    }
  }
  b.write('</ul></nav></div>'
      '<div class="tools"><a href="/productos" aria-label="Buscar">'
      '${_icon('search')}</a><a href="/carrito" aria-label="Carrito">'
      '${_icon('cart')}</a><a class="login" href="/cuenta/login">Iniciar sesión</a>'
      '</div></div></header>');
  return b.toString();
}

String _footer(ProductPage page, String storeName) {
  final s = page.shared.settings;
  final groups = page.shared.navigation
      .where((n) => n['menu_location'] == 'footer' && n['parent_id'] == null)
      .toList();
  final hours = parsePublicBusinessHours(s['business_hours_json'] ?? '');
  const dayNames = {
    'MONDAY': 'Lunes',
    'TUESDAY': 'Martes',
    'WEDNESDAY': 'Miércoles',
    'THURSDAY': 'Jueves',
    'FRIDAY': 'Viernes',
    'SATURDAY': 'Sábado',
    'SUNDAY': 'Domingo',
  };
  final spans = <String, List<String>>{};
  for (final day in publicBusinessDays) {
    final span = hours
        .where((h) => h.day == day)
        .map((h) => '${h.opens}–${h.closes}')
        .join(' / ');
    spans.putIfAbsent(span.isEmpty ? 'Cerrado' : span, () => []).add(day);
  }
  final b = StringBuffer('<footer class="foot"><div class="wrap cols">'
      '<div><p class="foot-name">${_e(storeName)}</p>'
      '<p>${_e(s['contact_address'])}</p>'
      '<p><a href="tel:${_e((s['contact_phone'] ?? '').replaceAll(' ', ''))}">'
      '${_e(s['contact_phone'])}</a></p>'
      '<p><a href="mailto:${_e(s['contact_email'])}">${_e(s['contact_email'])}</a></p></div>'
      '<div><p class="foot-title">Horario</p><dl class="hours">');
  for (final entry in spans.entries) {
    final names = entry.value.map((d) => dayNames[d]!).toList();
    final label =
        names.length > 2 ? '${names.first} a ${names.last}' : names.join(' y ');
    b.write('<div><dt>${_e(label)}</dt><dd>${_e(entry.key)}</dd></div>');
  }
  b.write('</dl></div>');
  for (final group in groups) {
    final links = page.shared.navigation
        .where((n) => n['parent_id'] == group['id'])
        .toList();
    b.write('<div><p class="foot-title">${_e(group['label'])}</p><ul>');
    for (final link in links) {
      b.write('<li><a href="${_e(_navHref(link, page.shared))}">'
          '${_e(link['label'])}</a></li>');
    }
    b.write('</ul></div>');
  }
  b.write('</div><p class="wrap legal">${_e(s['business_legal_name'] ?? '')} · '
      'Ficha generada en HTML — prueba de migración</p></footer>');
  return b.toString();
}

String _icon(String name) => switch (name) {
      'search' =>
        '<svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">'
            '<circle cx="11" cy="11" r="7" fill="none" stroke="currentColor" stroke-width="2"/>'
            '<path d="M20 20l-4-4" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
      _ => '<svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">'
          '<path d="M3 4h2l2.4 11.2a2 2 0 0 0 2 1.6h7.7a2 2 0 0 0 2-1.5L21 8H6.2" '
          'fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" '
          'stroke-linejoin="round"/><circle cx="10" cy="20" r="1.4" fill="currentColor"/>'
          '<circle cx="17" cy="20" r="1.4" fill="currentColor"/></svg>',
    };

String _css({required String primary, required String accent}) => '''
@font-face{font-family:Oswald;src:url(/assets/assets/fonts/Oswald-wght.ttf) format("truetype");font-weight:200 700;font-display:swap}
@font-face{font-family:Barlow;src:url(/assets/assets/fonts/Barlow-Regular.ttf) format("truetype");font-weight:400;font-display:swap}
@font-face{font-family:Barlow;src:url(/assets/assets/fonts/Barlow-Medium.ttf) format("truetype");font-weight:500;font-display:swap}
@font-face{font-family:Barlow;src:url(/assets/assets/fonts/Barlow-SemiBold.ttf) format("truetype");font-weight:600;font-display:swap}
@font-face{font-family:Barlow;src:url(/assets/assets/fonts/Barlow-Bold.ttf) format("truetype");font-weight:700;font-display:swap}
:root{--primary:$primary;--accent:$accent;--ink:#141b24;--muted:#5a6878;--line:#e2e7ee;--soft:#f4f6f9;--ok:#14804a;--bad:#b42318;--r:14px;
--head:Oswald,"Arial Narrow",Arial,sans-serif;--body:Barlow,"Segoe UI",Roboto,Arial,sans-serif}
*{box-sizing:border-box}html{-webkit-text-size-adjust:100%}
body{margin:0;background:#fff;color:var(--ink);font:400 17px/1.55 var(--body)}
img{max-width:100%;display:block}a{color:var(--primary)}
.wrap{max-width:1280px;margin:0 auto;padding-inline:24px}
.skip{position:absolute;left:-999px}.skip:focus{left:16px;top:8px;z-index:9;background:#fff;padding:8px 12px}
.sr{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0)}
.top{position:sticky;top:0;z-index:5;background:rgba(255,255,255,.94);backdrop-filter:saturate(1.4) blur(10px);border-bottom:1px solid var(--line)}
.bar{display:flex;align-items:center;gap:28px;height:68px}
.logo img{height:34px;width:auto}
.menu{flex:1}.menu-toggle{position:absolute;opacity:0;pointer-events:none}.menu-button{display:none}
.menu nav>ul{display:flex;gap:26px;list-style:none;margin:0;padding:0}
.menu nav>ul>li{position:relative}
.menu nav>ul>li>a{display:block;padding:22px 0;font:500 14px/1 var(--body);letter-spacing:.08em;text-transform:uppercase;color:var(--ink);text-decoration:none}
.menu nav>ul>li>a:hover{color:var(--primary)}
.has-sub>a::after{content:"";display:inline-block;width:6px;height:6px;margin-left:7px;border:solid currentColor;border-width:0 1.6px 1.6px 0;transform:translateY(-3px) rotate(45deg)}
.sub{display:none;position:absolute;top:100%;left:-18px;min-width:220px;list-style:none;margin:0;padding:10px;background:#fff;border:1px solid var(--line);border-radius:12px;box-shadow:0 18px 40px rgba(20,27,36,.12)}
.has-sub:hover .sub,.has-sub:focus-within .sub{display:block}
.sub a{display:block;padding:8px 10px;border-radius:8px;color:var(--ink);text-decoration:none;font-size:15px}.sub a:hover{background:var(--soft)}
.tools{display:flex;align-items:center;gap:18px;color:var(--ink)}.tools a{color:inherit;display:flex}
.login{border:1px solid var(--line);border-radius:999px;padding:8px 14px;font:600 13px/1 var(--body);letter-spacing:.06em;text-transform:uppercase;text-decoration:none}
.crumbs ol{display:flex;flex-wrap:wrap;gap:6px;list-style:none;margin:0;padding:18px 0 6px;font-size:14px;color:var(--muted)}
.crumbs li+li::before{content:"/";margin-right:6px;color:#b6c0cc}
.crumbs a{color:var(--muted);text-decoration:none}.crumbs a:hover{color:var(--primary);text-decoration:underline}
.crumbs [aria-current] span{color:var(--ink)}
.product{display:grid;grid-template-columns:minmax(0,1.15fr) minmax(0,1fr);gap:56px;padding-block:18px 56px;align-items:start}
.stage{margin:0;background:var(--soft);border-radius:var(--r);aspect-ratio:1/1;display:grid;place-items:center;overflow:hidden}
.stage img{width:100%;height:100%;object-fit:contain;mix-blend-mode:multiply;padding:6%}
.thumbs{display:flex;gap:10px;list-style:none;margin:12px 0 0;padding:0;overflow-x:auto}
.thumbs button{border:1.5px solid transparent;border-radius:10px;padding:0;background:var(--soft);cursor:pointer;width:76px;height:76px}
.thumbs button[aria-current]{border-color:var(--primary)}
.thumbs img{width:100%;height:100%;object-fit:contain;mix-blend-mode:multiply}
.buy{position:sticky;top:92px}
.brand{margin:0 0 8px;font:600 13px/1 var(--body);letter-spacing:.16em;text-transform:uppercase;color:var(--accent)}
h1{margin:0;font:600 clamp(28px,3.1vw,40px)/1.06 var(--head);text-transform:uppercase;letter-spacing:.01em;text-wrap:balance}
.ids{display:flex;gap:16px;flex-wrap:wrap;margin:12px 0 0;color:var(--muted);font-size:14px}
.price-row{margin:26px 0 6px;display:flex;align-items:baseline;gap:14px;flex-wrap:wrap}
.price{margin:0;font:600 42px/1 var(--head);color:var(--primary);font-variant-numeric:tabular-nums}
.tax{margin:0;color:var(--muted);font-size:14px}
.stock{display:inline-flex;align-items:center;gap:8px;margin:6px 0 0;font-weight:600;font-size:15px}
.stock span{width:8px;height:8px;border-radius:50%;background:currentColor}
.stock.ok{color:var(--ok)}.stock.out{color:var(--bad)}
.highlights{display:grid;grid-template-columns:1fr 1fr;gap:1px;margin:24px 0 0;background:var(--line);border:1px solid var(--line);border-radius:12px;overflow:hidden}
.highlights div{background:#fff;padding:14px 16px}
.highlights dt{font-size:13px;color:var(--muted)}.highlights dd{margin:2px 0 0;font-weight:700;font-size:16px}
.to-sheet{display:inline-block;margin-top:10px;font-weight:600;font-size:15px}
.cart{display:flex;gap:12px;margin-top:26px}
.qty input{width:84px;height:54px;border:1px solid var(--line);border-radius:12px;font:600 17px var(--body);text-align:center}
button.primary{flex:1;height:54px;border:0;border-radius:12px;background:var(--primary);color:#fff;font:600 15px/1 var(--body);letter-spacing:.08em;text-transform:uppercase;cursor:pointer}
button.primary:hover{filter:brightness(1.12)}button.primary:disabled{background:#c7cfd9;cursor:not-allowed}
button.primary:focus-visible,.secondary:focus-visible,a:focus-visible{outline:3px solid var(--accent);outline-offset:2px}
.proto-note{margin:8px 0 0;font-size:14px;color:var(--muted)}
.secondary{display:flex;align-items:center;justify-content:center;height:50px;margin-top:10px;border:1.5px solid var(--primary);border-radius:12px;color:var(--primary);font:600 14px/1 var(--body);letter-spacing:.08em;text-transform:uppercase;text-decoration:none}
.promises{list-style:none;margin:26px 0 0;padding:0;border-top:1px solid var(--line)}
.promises li{display:grid;gap:2px;padding:14px 0;border-bottom:1px solid var(--line);font-size:15px}
.promises span{color:var(--muted)}
.details{padding-block:56px;border-top:1px solid var(--line)}
h2{margin:0 0 26px;font:600 30px/1.1 var(--head);text-transform:uppercase;letter-spacing:.02em}
.description{max-width:70ch;margin-bottom:34px;font-size:18px}.description p{margin:0 0 14px}
.sheet{columns:2 420px;column-gap:48px}
.group{break-inside:avoid;margin-bottom:30px}
.group h3{margin:0 0 6px;font:600 14px/1 var(--body);letter-spacing:.14em;text-transform:uppercase;color:var(--accent)}
.group dl{margin:0}.group dl div{display:grid;grid-template-columns:minmax(150px,40%) 1fr;gap:16px;padding:12px 0;border-bottom:1px solid var(--line)}
.group dt{color:var(--muted)}.group dt small{display:block;font-size:13px;color:#8693a3;margin-top:2px}
.group dd{margin:0;font-weight:600}.detail{font-weight:400;color:var(--muted)}
.related{padding-block:48px 64px;border-top:1px solid var(--line)}
.related-head{display:flex;align-items:baseline;justify-content:space-between;gap:16px}
.related-head a{font-weight:600}
.related ul{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:22px;list-style:none;margin:0;padding:0}
.related li a{display:grid;gap:8px;color:var(--ink);text-decoration:none}
.related img{aspect-ratio:1/1;object-fit:contain;background:var(--soft);border-radius:12px;padding:10%;mix-blend-mode:multiply;width:100%}
.related .name{font-weight:600;line-height:1.3;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.related .p{color:var(--primary);font:600 18px var(--head)}
.foot{background:var(--primary);color:#dfe7f1;padding-top:52px;margin-top:8px}
.foot .cols{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:36px}
.foot p{margin:0 0 6px}.foot a{color:#fff;text-decoration:none}.foot a:hover{text-decoration:underline}
.foot-name{font:600 24px var(--head);color:#fff;text-transform:uppercase}
.foot-title{font:600 13px/1 var(--body)!important;letter-spacing:.14em;text-transform:uppercase;color:#9fb4cc;margin-bottom:12px!important}
.foot ul{list-style:none;margin:0;padding:0;display:grid;gap:8px}
.hours{margin:0;display:grid;gap:6px}.hours div{display:flex;justify-content:space-between;gap:12px}.hours dd{margin:0;color:#fff}
.legal{margin:40px auto 0!important;padding-block:18px;border-top:1px solid rgba(255,255,255,.14);font-size:13px;color:#9fb4cc}
.buybar{display:none}
@media (max-width:980px){
.product{grid-template-columns:1fr;gap:26px}.buy{position:static}
.related ul{grid-template-columns:repeat(2,minmax(0,1fr))}
}
@media (max-width:760px){
body{font-size:16px}.wrap{padding-inline:16px}
.bar{gap:12px;height:60px}.logo{order:1;margin-right:auto}.logo img{height:28px}.tools{order:2;gap:14px}.tools .login{display:none}
.crumbs ol{flex-wrap:nowrap;overflow-x:auto;white-space:nowrap;scrollbar-width:none;padding-top:12px}.crumbs [aria-current]{display:none}
.menu-button{order:3;display:grid;gap:4px;width:28px;cursor:pointer}
.menu-button span{height:2px;background:var(--ink);border-radius:2px}
.menu-toggle:focus-visible+.menu-button{outline:3px solid var(--accent);outline-offset:4px}
.menu{display:none;position:fixed;inset:60px 0 auto;max-height:calc(100vh - 60px);overflow:auto;background:#fff;border-bottom:1px solid var(--line);padding:8px 16px 20px}
.menu-toggle:checked~.menu{display:block}
.menu nav>ul{flex-direction:column;gap:0}.menu nav>ul>li>a{padding:14px 0;border-bottom:1px solid var(--line)}
.sub{position:static;display:block;border:0;box-shadow:none;padding:0 0 8px 12px}.has-sub>a::after{display:none}
.price{font-size:36px}.sheet{columns:1}.group dl div{grid-template-columns:1fr;gap:2px}
.buybar{display:flex;position:fixed;left:0;right:0;bottom:0;z-index:6;gap:14px;align-items:center;padding:10px 16px calc(10px + env(safe-area-inset-bottom,0px));background:#fff;border-top:1px solid var(--line);box-shadow:0 -10px 30px rgba(20,27,36,.08)}
.buybar span{font:600 24px var(--head);color:var(--primary)}.buybar button{height:48px}
body{padding-bottom:76px}
}
''';
