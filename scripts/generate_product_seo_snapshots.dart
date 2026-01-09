import 'dart:convert';
import 'dart:io';

/// Generates static HTML "SEO snapshots" for product routes.
///
/// Why: Firebase Hosting is configured as an SPA (rewrite ** -> /index.html).
/// Google Merchant (and other bots) may not reliably execute Flutter JS, which
/// can cause price/availability/content mismatches and trigger account-level
/// issues like "Misleading content".
///
/// This script:
/// - Reads `build/web_store/index.html` as the base template (already synced by
///   `scripts/sync_seo_index.sh`).
/// - Fetches products from Supabase via REST using `SUPABASE_SERVICE_ROLE_KEY`
///   from `.env` (never printed).
/// - Writes HTML files at `build/web_store/productos/<uuid>` (no extension) so
///   `/productos/<uuid>` can be served as static HTML.
/// - Adds/overrides meta tags, canonical URL, OG/Twitter, and injects Product
///   JSON-LD.
///
/// Usage (example):
///   dart run scripts/generate_product_seo_snapshots.dart \
///     --build-dir build/web_store \
///     --tenant-id 5443b130-cc28-45af-a420-cd500b288890 \
///     --store-url https://vinabike.cl
void main(List<String> args) async {
  final parsed = _parseArgs(args);

  final buildDirPath = parsed['build-dir'] ?? 'build/web_store';
  final tenantId = parsed['tenant-id'];
  final storeUrl = parsed['store-url'] ?? 'https://vinabike.cl';
  final productScope = (parsed['product-scope'] ?? 'merchant').trim().toLowerCase();
  final onlyMerchant = productScope != 'published';

  if (tenantId == null || tenantId.isEmpty) {
    stderr.writeln('❌ Missing --tenant-id');
    exitCode = 2;
    return;
  }

  final buildDir = Directory(buildDirPath);
  final baseIndexFile = File(p.join(buildDir.path, 'index.html'));

  if (!buildDir.existsSync() || !baseIndexFile.existsSync()) {
    stderr.writeln('❌ Build dir/index.html not found: ${baseIndexFile.path}');
    stderr.writeln('   Run the store build first: flutter build web ... -o $buildDirPath');
    exitCode = 2;
    return;
  }

  final env = await _readDotEnv(File('.env'));
  final serviceRoleKey = env['SUPABASE_SERVICE_ROLE_KEY']?.trim();
  if (serviceRoleKey == null || serviceRoleKey.isEmpty) {
    stderr.writeln('❌ SUPABASE_SERVICE_ROLE_KEY not found in .env');
    exitCode = 2;
    return;
  }

  final supabaseUrl = env['SUPABASE_URL']?.trim().isNotEmpty == true
      ? env['SUPABASE_URL']!.trim()
      : 'https://xzdvtzdqjeyqxnkqprtf.supabase.co';

  final baseHtml = await baseIndexFile.readAsString();

  final settings = await _fetchWebsiteSettings(
    supabaseUrl: supabaseUrl,
    tenantId: tenantId,
    serviceRoleKey: serviceRoleKey,
  );

  final storeName = _getSetting(settings, 'seo_business_name') ??
      _getSetting(settings, 'store_name') ??
      'Vinabike';

  final titleTemplate = _getSetting(settings, 'seo_product_title_template') ??
      '{product_name} | $storeName';
  final descriptionTemplate = _getSetting(settings, 'seo_product_description_template') ??
      '{product_description}';

  final products = await _fetchProducts(
    supabaseUrl: supabaseUrl,
    tenantId: tenantId,
    serviceRoleKey: serviceRoleKey,
    onlyMerchant: onlyMerchant,
  );

  final outDir = Directory(p.join(buildDir.path, 'productos'));
  outDir.createSync(recursive: true);

  var written = 0;
  for (final product in products) {
    final id = (product['id'] ?? '').toString();
    if (id.isEmpty) continue;

    final productName = (product['name'] ?? '').toString().trim();
    final productSku = (product['sku'] ?? '').toString().trim();
    final productBrand = (product['brand'] ?? '').toString().trim();
    final productDescriptionRaw = (product['description'] ?? '').toString();
    final productDescription = _cleanText(productDescriptionRaw);

    final priceNum = _toNum(product['price']);
    final currency = (product['price_currency'] ?? 'CLP').toString();

    final stockQty = _toInt(product['stock_quantity']) ?? _toInt(product['inventory_qty']) ?? 0;
    final inStock = stockQty > 0;

    final imageUrl = (product['image_url'] ?? '').toString().trim();

    final productUrl = '${storeUrl.replaceAll(RegExp(r'/+$'), '')}/productos/$id';

    final variables = <String, String>{
      'store_name': storeName,
      'product_name': productName,
      'product_sku': productSku,
      'product_brand': productBrand,
      'product_price': priceNum?.toStringAsFixed(0) ?? '',
      'product_description': productDescription,
    };

    final title = _truncate(_applyTemplate(titleTemplate, variables), 120);
    final description = _truncate(_applyTemplate(descriptionTemplate, variables), 320);

    final html = _buildProductHtml(
      baseHtml: baseHtml,
      title: title.isNotEmpty ? title : productName,
      description: description.isNotEmpty ? description : _truncate(productDescription, 320),
      canonicalUrl: productUrl,
      ogImageUrl: imageUrl,
      jsonLdProduct: _buildProductJsonLd(
        productUrl: productUrl,
        storeName: storeName,
        product: product,
        description: description.isNotEmpty ? description : productDescription,
        inStock: inStock,
        currency: currency,
        priceNum: priceNum,
        imageUrl: imageUrl,
        productBrand: productBrand,
        productSku: productSku,
      ),
      isProduct: true,
    );

    final outFile = File(p.join(outDir.path, id));
    await outFile.writeAsString(html);
    written++;
  }

  stdout.writeln('✅ Product SEO snapshots generated: $written');
}

// -----------------------------------------------------------------------------
// HTML mutation
// -----------------------------------------------------------------------------

String _buildProductHtml({
  required String baseHtml,
  required String title,
  required String description,
  required String canonicalUrl,
  required String ogImageUrl,
  required String jsonLdProduct,
  required bool isProduct,
}) {
  var html = baseHtml;

  html = _replaceTag(html, RegExp(r'<title>.*?</title>', dotAll: true), '<title>${_escapeHtml(title)}</title>');

  html = _replaceMetaContent(html, name: 'title', content: title);
  html = _replaceMetaContent(html, name: 'description', content: description);

  html = _replaceLinkHref(html, rel: 'canonical', href: canonicalUrl);

  html = _replaceMetaProperty(html, property: 'og:type', content: isProduct ? 'product' : 'website');
  html = _replaceMetaProperty(html, property: 'og:url', content: canonicalUrl);
  html = _replaceMetaProperty(html, property: 'og:title', content: title);
  html = _replaceMetaProperty(html, property: 'og:description', content: description);

  // Set/insert og:image + twitter:image if we have a product image.
  if (ogImageUrl.isNotEmpty) {
    html = _replaceOrInsertMetaProperty(html, property: 'og:image', content: ogImageUrl);
    html = _replaceOrInsertMetaName(html, name: 'twitter:image', content: ogImageUrl);
  }

  html = _replaceMetaName(html, name: 'twitter:url', content: canonicalUrl);
  html = _replaceMetaName(html, name: 'twitter:title', content: title);
  html = _replaceMetaName(html, name: 'twitter:description', content: description);

  // Inject product JSON-LD right before </head>.
  final injection = '\n  <!-- JSON-LD Structured Data for Product (generated at deploy) -->\n'
      '  <script type="application/ld+json" id="seo-product-jsonld">\n'
      '  ${jsonLdProduct}\n'
      '  </script>\n';

  if (html.contains('id="seo-product-jsonld"')) {
    // If already present, replace the whole block.
    html = html.replaceAll(
      RegExp(r'<script type="application/ld\+json" id="seo-product-jsonld">.*?</script>', dotAll: true),
      '${injection.trim()}\n',
    );
  } else {
    html = html.replaceFirst(RegExp(r'</head>'), '$injection</head>');
  }

  return html;
}

String _buildProductJsonLd({
  required String productUrl,
  required String storeName,
  required Map<String, dynamic> product,
  required String description,
  required bool inStock,
  required String currency,
  required num? priceNum,
  required String imageUrl,
  required String productBrand,
  required String productSku,
}) {
  final name = (product['name'] ?? '').toString().trim();
  final gtin = (product['gtin'] ?? product['barcode'] ?? '').toString().trim();

  final data = <String, dynamic>{
    '@context': 'https://schema.org',
    '@type': 'Product',
    'name': name,
    'description': description,
    'url': productUrl,
    if (imageUrl.isNotEmpty) 'image': [imageUrl],
    if (productSku.isNotEmpty) 'sku': productSku,
    if (productBrand.isNotEmpty)
      'brand': {
        '@type': 'Brand',
        'name': productBrand,
      },
    if (gtin.isNotEmpty) 'gtin': gtin,
    'offers': {
      '@type': 'Offer',
      'url': productUrl,
      'priceCurrency': currency,
      if (priceNum != null) 'price': priceNum.toString(),
      'availability': inStock
          ? 'https://schema.org/InStock'
          : 'https://schema.org/OutOfStock',
      'seller': {
        '@type': 'Organization',
        'name': storeName,
      },
    },
  };

  return const JsonEncoder.withIndent('  ').convert(data);
}

// -----------------------------------------------------------------------------
// Supabase REST
// -----------------------------------------------------------------------------

Future<Map<String, String>> _fetchWebsiteSettings({
  required String supabaseUrl,
  required String tenantId,
  required String serviceRoleKey,
}) async {
  final url = Uri.parse(
    '$supabaseUrl/rest/v1/website_settings'
    '?tenant_id=eq.$tenantId'
    '&select=key,value',
  );

  final response = await _httpGet(
    url,
    headers: {
      'apikey': serviceRoleKey,
      'Authorization': 'Bearer $serviceRoleKey',
    },
  );

  final decoded = jsonDecode(response) as List<dynamic>;
  final settings = <String, String>{};
  for (final row in decoded) {
    final map = row as Map<String, dynamic>;
    final k = (map['key'] ?? '').toString();
    final v = (map['value'] ?? '').toString();
    if (k.isNotEmpty) settings[k] = v;
  }
  return settings;
}

Future<List<Map<String, dynamic>>> _fetchProducts({
  required String supabaseUrl,
  required String tenantId,
  required String serviceRoleKey,
  required bool onlyMerchant,
}) async {
  // Keep this aligned with Merchant feed selection as much as possible.
  final url = Uri.parse(
    '$supabaseUrl/rest/v1/products'
    '?tenant_id=eq.$tenantId'
    '${onlyMerchant ? '&is_google_merchant=eq.true' : ''}'
    '&is_published=eq.true'
    '&select=id,name,description,price,price_currency,sku,gtin,barcode,image_url,brand,stock_quantity,inventory_qty',
  );

  final response = await _httpGet(
    url,
    headers: {
      'apikey': serviceRoleKey,
      'Authorization': 'Bearer $serviceRoleKey',
    },
  );

  final decoded = jsonDecode(response) as List<dynamic>;
  return decoded.map((e) => (e as Map<String, dynamic>)).toList();
}

Future<String> _httpGet(Uri url, {required Map<String, String> headers}) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(url);
    headers.forEach(req.headers.set);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException('GET $url failed: ${res.statusCode} ${res.reasonPhrase}\n$body');
    }
    return body;
  } finally {
    client.close(force: true);
  }
}

String? _getSetting(Map<String, String> settings, String key) {
  final v = settings[key];
  if (v == null) return null;
  final trimmed = v.trim();
  return trimmed.isEmpty ? null : trimmed;
}

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

String _applyTemplate(String template, Map<String, String> variables) {
  var out = template;
  for (final entry in variables.entries) {
    out = out.replaceAll('{${entry.key}}', entry.value);
  }
  return out;
}

String _truncate(String text, int maxLen) {
  final t = text.trim();
  if (t.length <= maxLen) return t;
  return t.substring(0, maxLen).trim();
}

String _cleanText(String text) {
  var t = text;
  // Strip HTML tags (simple but effective for meta snippets).
  t = t.replaceAll(RegExp(r'<[^>]+>'), ' ');
  // Collapse whitespace.
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t;
}

num? _toNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  return num.tryParse(s);
}

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  return int.tryParse(s);
}

String _escapeHtml(String text) {
  return text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

String _replaceTag(String html, RegExp pattern, String replacement) {
  if (pattern.hasMatch(html)) return html.replaceAll(pattern, replacement);
  return html;
}

String _replaceMetaContent(String html, {required String name, required String content}) {
  final esc = _escapeHtml(content);
  final re = RegExp(r'<meta\s+name="' + RegExp.escape(name) + r'"\s+content="[^"]*"\s*/?>');
  if (re.hasMatch(html)) {
    return html.replaceAll(re, '<meta name="$name" content="$esc">');
  }
  return html;
}

String _replaceMetaName(String html, {required String name, required String content}) {
  final esc = _escapeHtml(content);
  final re = RegExp(r'<meta\s+name="' + RegExp.escape(name) + r'"\s+content="[^"]*"\s*/?>');
  if (re.hasMatch(html)) {
    return html.replaceAll(re, '<meta name="$name" content="$esc">');
  }
  return html;
}

String _replaceOrInsertMetaName(String html, {required String name, required String content}) {
  final esc = _escapeHtml(content);
  final re = RegExp(r'<meta\s+name="' + RegExp.escape(name) + r'"\s+content="[^"]*"\s*/?>');
  if (re.hasMatch(html)) {
    return html.replaceAll(re, '<meta name="$name" content="$esc">');
  }

  // Insert near the first twitter tag.
  final anchor = RegExp(r'<meta\s+name="twitter:card"[^>]*>');
  if (anchor.hasMatch(html)) {
    return html.replaceFirstMapped(
      anchor,
      (m) => '${m.group(0)}\n  <meta name="$name" content="$esc">',
    );
  }

  return html;
}

String _replaceMetaProperty(String html, {required String property, required String content}) {
  final esc = _escapeHtml(content);
  final re = RegExp(r'<meta\s+property="' + RegExp.escape(property) + r'"\s+content="[^"]*"\s*/?>');
  if (re.hasMatch(html)) {
    return html.replaceAll(re, '<meta property="$property" content="$esc">');
  }
  return html;
}

String _replaceOrInsertMetaProperty(String html, {required String property, required String content}) {
  final esc = _escapeHtml(content);
  final re = RegExp(r'<meta\s+property="' + RegExp.escape(property) + r'"\s+content="[^"]*"\s*/?>');
  if (re.hasMatch(html)) {
    return html.replaceAll(re, '<meta property="$property" content="$esc">');
  }

  // Insert near the first og tag.
  final anchor = RegExp(r'<meta\s+property="og:type"[^>]*>');
  if (anchor.hasMatch(html)) {
    return html.replaceFirstMapped(
      anchor,
      (m) => '${m.group(0)}\n  <meta property="$property" content="$esc">',
    );
  }

  return html;
}

String _replaceLinkHref(String html, {required String rel, required String href}) {
  final esc = _escapeHtml(href);
  final re = RegExp(r'<link\s+rel="' + RegExp.escape(rel) + r'"\s+href="[^"]*"\s*/?>');
  if (re.hasMatch(html)) {
    return html.replaceAll(re, '<link rel="$rel" href="$esc">');
  }
  return html;
}

Future<Map<String, String>> _readDotEnv(File file) async {
  if (!file.existsSync()) return {};
  final lines = await file.readAsLines();
  final out = <String, String>{};

  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;

    final idx = line.indexOf('=');
    if (idx <= 0) continue;

    final key = line.substring(0, idx).trim();
    var value = line.substring(idx + 1).trim();

    // Strip optional surrounding quotes.
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }

    out[key] = value;
  }

  return out;
}

Map<String, String> _parseArgs(List<String> args) {
  final out = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--')) continue;
    final key = arg.substring(2);

    final next = (i + 1) < args.length ? args[i + 1] : null;
    if (next == null || next.startsWith('--')) {
      out[key] = 'true';
      continue;
    }

    out[key] = next;
    i++;
  }
  return out;
}

// Minimal path join helper to avoid importing additional packages.
class p {
  static String join(String a, String b) {
    if (a.endsWith(Platform.pathSeparator)) return '$a$b';
    return '$a${Platform.pathSeparator}$b';
  }
}
