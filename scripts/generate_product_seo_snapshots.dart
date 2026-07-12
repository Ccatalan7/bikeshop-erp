import 'dart:convert';
import 'dart:io';

const num _structuredDataMaxShippingRateClp = 30000;

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
/// - Fetches products from Supabase via REST using `SUPABASE_SECRET_KEY`
///   from `.env` (never printed).
/// - Writes canonical HTML files at `build/web_store/productos/<slug>/<sku>`
///   and legacy UUID snapshots that point crawlers to the canonical URL.
/// - Writes `sitemap.xml` and `robots.txt` into the same build directory.
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
  final productScope =
      (parsed['product-scope'] ?? 'published').trim().toLowerCase();
  final onlyMerchant = productScope == 'merchant';

  if (tenantId == null || tenantId.isEmpty) {
    stderr.writeln('❌ Missing --tenant-id');
    exitCode = 2;
    return;
  }

  final buildDir = Directory(buildDirPath);
  final baseIndexFile = File(pathJoin(buildDir.path, 'index.html'));

  if (!buildDir.existsSync() || !baseIndexFile.existsSync()) {
    stderr.writeln('❌ Build dir/index.html not found: ${baseIndexFile.path}');
    stderr.writeln(
        '   Run the store build first: flutter build web ... -o $buildDirPath');
    exitCode = 2;
    return;
  }

  final env = await _readDotEnv(File('.env'));
  final serviceRoleKey =
      _resolveEnvValue('SUPABASE_SECRET_KEY', env: env) ?? '';
  if (serviceRoleKey.isEmpty) {
    stderr.writeln(
      '❌ SUPABASE_SECRET_KEY not found in environment or .env',
    );
    exitCode = 2;
    return;
  }

  final supabaseUrl =
      _resolveEnvValue('SUPABASE_URL', env: env)?.isNotEmpty == true
          ? _resolveEnvValue('SUPABASE_URL', env: env)!
          : 'https://xzdvtzdqjeyqxnkqprtf.supabase.co';

  final baseIndexHtml = await baseIndexFile.readAsString();

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
  final descriptionTemplate =
      _getSetting(settings, 'seo_product_description_template') ??
          '{product_description}';

  final products = await _fetchProducts(
    supabaseUrl: supabaseUrl,
    tenantId: tenantId,
    serviceRoleKey: serviceRoleKey,
    onlyMerchant: onlyMerchant,
  );
  final productUrlAliases = await _fetchProductUrlAliases(
    supabaseUrl: supabaseUrl,
    tenantId: tenantId,
    serviceRoleKey: serviceRoleKey,
  );
  final pages = await _fetchWebsitePages(
    supabaseUrl: supabaseUrl,
    tenantId: tenantId,
    serviceRoleKey: serviceRoleKey,
  );
  final baseHtml = _buildHomepageHtml(
    baseHtml: baseIndexHtml,
    storeUrl: storeUrl,
    storeName: storeName,
    pages: pages,
  );
  await baseIndexFile.writeAsString(baseHtml);
  final pageBlocks = await _fetchWebsiteBlocksForPages(
    supabaseUrl: supabaseUrl,
    pages: pages,
    serviceRoleKey: serviceRoleKey,
  );

  final outDir = Directory(pathJoin(buildDir.path, 'productos'));
  outDir.createSync(recursive: true);

  final productHtmlById = <String, String>{};
  final canonicalPathByProductId = <String, String>{};
  var written = 0;
  for (final product in products) {
    final id = (product['id'] ?? '').toString();
    if (id.isEmpty) continue;

    final productName =
        _cleanText(_firstNonEmpty(product['website_name'], product['name']));
    final productSku = (product['sku'] ?? '').toString().trim();
    final productBrand = (product['brand'] ?? '').toString().trim();
    final productCategory = (product['category_name'] ?? '').toString().trim();
    final productDescriptionRaw =
        _firstNonEmpty(product['website_description'], product['description']);
    final productSearchTerms = _stringList(product['website_search_terms']);
    final fallbackDescription = _fallbackProductDescription(
      productName: productName,
      productBrand: productBrand,
      productCategory: productCategory,
      storeName: storeName,
    );
    final baseProductDescription = _cleanText(productDescriptionRaw).isNotEmpty
        ? _cleanText(productDescriptionRaw)
        : fallbackDescription;
    final productSearchPhrase = _productLocalSearchPhrase(
      productName: productName,
      productCategory: productCategory,
      searchTerms: productSearchTerms,
    );
    final productDescription = _appendProductSearchPhrase(
      description: baseProductDescription,
      searchPhrase: productSearchPhrase,
    );

    final priceNum =
        _toNum(product['website_price']) ?? _toNum(product['price']);
    final currency = (product['price_currency'] ?? 'CLP').toString();

    final stockQty = _toInt(product['stock_quantity']) ??
        _toInt(product['inventory_qty']) ??
        0;
    final trackStock = product['track_stock'] != false;
    final inStock = !trackStock || stockQty > 0;

    final imageUrls = _productImageUrls(product);
    final imageUrl = imageUrls.isEmpty ? '' : imageUrls.first;

    final productPath = _publicProductPath(product);
    final productUrl = _joinUrl(storeUrl, productPath);

    final variables = <String, String>{
      'store_name': storeName,
      'product_name': productName,
      'product_sku': productSku,
      'product_brand': productBrand,
      'product_price': priceNum?.toStringAsFixed(0) ?? '',
      'product_description': productDescription,
    };

    final seoTitleOverride =
        _cleanText((product['website_seo_title'] ?? '').toString());
    final baseTitle =
        _truncate(_cleanText(_applyTemplate(titleTemplate, variables)), 120);
    final title = seoTitleOverride.isNotEmpty
        ? _truncate(seoTitleOverride, 120)
        : _buildProductSeoTitle(
            baseTitle: baseTitle.isNotEmpty ? baseTitle : productName,
            storeName: storeName,
            searchPhrase: productSearchPhrase,
          );
    final seoDescriptionOverride =
        _cleanText((product['website_seo_description'] ?? '').toString());
    final description = _truncate(
      seoDescriptionOverride.isNotEmpty
          ? seoDescriptionOverride
          : _cleanText(_applyTemplate(descriptionTemplate, variables)),
      320,
    );

    final html = _buildProductHtml(
      baseHtml: baseHtml,
      title: title.isNotEmpty ? title : productName,
      description: description.isNotEmpty
          ? description
          : _truncate(productDescription, 320),
      canonicalUrl: productUrl,
      ogImageUrl: imageUrl,
      jsonLdProduct: _buildProductJsonLd(
        productUrl: productUrl,
        storeUrl: storeUrl,
        storeName: _cleanText(storeName),
        product: product,
        description: _cleanText(
            description.isNotEmpty ? description : productDescription),
        inStock: inStock,
        currency: currency,
        priceNum: priceNum,
        imageUrls: imageUrls,
        productBrand: productBrand,
        productSku: productSku,
      ),
      fallbackHtml: _buildProductFallbackHtml(
        title: title.isNotEmpty ? title : productName,
        description: description.isNotEmpty
            ? description
            : _truncate(productDescription, 320),
        canonicalUrl: productUrl,
        imageUrl: imageUrl,
        productBrand: productBrand,
        productCategory: productCategory,
        productSku: productSku,
        priceNum: priceNum,
        currency: currency,
        inStock: inStock,
      ),
      isProduct: true,
    );

    final relativeProductPath =
        productPath.substring('/productos/'.length).split('/');
    var canonicalOutPath = outDir.path;
    for (final segment in relativeProductPath) {
      canonicalOutPath = pathJoin(canonicalOutPath, segment);
    }
    final canonicalOutFile = File(canonicalOutPath);
    canonicalOutFile.parent.createSync(recursive: true);
    await canonicalOutFile.writeAsString(html);

    // Keep old indexed/shared UUID URLs crawlable while signaling the clean
    // product URL as canonical inside the generated HTML.
    final legacyOutFile = File(pathJoin(outDir.path, id));
    if (legacyOutFile.path != canonicalOutFile.path) {
      await legacyOutFile.writeAsString(
        _buildLegacyProductRedirectHtml(
          html: html,
          canonicalUrl: productUrl,
        ),
      );
    }
    productHtmlById[id] = html;
    canonicalPathByProductId[id] = productPath;
    written++;
  }

  final redirectAliases = _buildProductRedirectAliases(
    products: products,
    aliases: productUrlAliases,
    canonicalPathByProductId: canonicalPathByProductId,
  );
  var aliasSnapshotsWritten = 0;
  for (final redirect in redirectAliases) {
    final html = productHtmlById[redirect.productId];
    final canonicalPath = canonicalPathByProductId[redirect.productId];
    if (html == null || canonicalPath == null) continue;
    await _writeRedirectSnapshot(
      buildDir: buildDir,
      aliasPath: redirect.aliasPath,
      html: html,
      canonicalUrl: _joinUrl(storeUrl, canonicalPath),
    );
    aliasSnapshotsWritten++;
  }
  final firebaseRedirectsWritten = await _writeFirebaseProductRedirects(
    firebaseConfigFile: File(parsed['firebase-config'] ?? 'firebase.json'),
    manifestFile: File(
      parsed['redirect-manifest'] ?? 'scripts/generated_product_redirects.json',
    ),
    redirects: redirectAliases,
    canonicalPathByProductId: canonicalPathByProductId,
  );

  final categories = _buildProductCategories(
    products: products,
    storeUrl: storeUrl,
  );
  final categoryOutDir = Directory(pathJoin(outDir.path, 'categoria'));
  categoryOutDir.createSync(recursive: true);
  var categoryPagesWritten = 0;
  for (final category in categories) {
    final categoryUrl =
        _joinUrl(storeUrl, '/productos/categoria/${category.slug}');
    final title = _buildCategorySeoTitle(
      category: category,
      storeName: storeName,
    );
    final description = _buildCategorySeoDescription(
      category: category,
      storeName: storeName,
    );
    final html = _buildCategoryHtml(
      baseHtml: baseHtml,
      title: _truncate(_cleanText(title), 120),
      description: _truncate(_cleanText(description), 320),
      canonicalUrl: categoryUrl,
      jsonLd: _buildCategoryJsonLd(
        category: category,
        categoryUrl: categoryUrl,
        storeName: storeName,
      ),
      fallbackHtml: _buildCategoryFallbackHtml(
        title: _truncate(_cleanText(title), 120),
        description: _truncate(_cleanText(description), 320),
        category: category,
      ),
    );
    await File(pathJoin(categoryOutDir.path, category.slug))
        .writeAsString(html);
    categoryPagesWritten++;
  }

  stdout.writeln('✅ Product SEO snapshots generated: $written');
  stdout.writeln('✅ Product alias snapshots generated: $aliasSnapshotsWritten');
  stdout.writeln(
      '✅ Firebase product 301 redirects generated: $firebaseRedirectsWritten');
  stdout.writeln('✅ Category SEO pages generated: $categoryPagesWritten');
  final staticTrustPagesWritten = await _writeStaticTrustPages(
    buildDir: buildDir,
    baseHtml: baseHtml,
    storeUrl: storeUrl,
    storeName: storeName,
    settings: settings,
    pages: pages,
    pageBlocks: pageBlocks,
  );
  stdout
      .writeln('✅ Trust/policy SEO pages generated: $staticTrustPagesWritten');
  await _writeCrawlerFiles(
    buildDir: buildDir,
    storeUrl: storeUrl,
    products: products,
    categories: categories,
    pages: pages,
  );
  stdout.writeln('✅ robots.txt and sitemap.xml generated');
}

// -----------------------------------------------------------------------------
// HTML mutation
// -----------------------------------------------------------------------------

String _buildHomepageHtml({
  required String baseHtml,
  required String storeUrl,
  required String storeName,
  required List<Map<String, dynamic>> pages,
}) {
  Map<String, dynamic>? homePage;
  for (final page in pages) {
    final slug = (page['slug'] ?? '').toString().trim();
    if (page['is_home'] == true || slug == 'home' || slug == 'inicio') {
      homePage = page;
      break;
    }
  }

  final title = _cleanText((homePage?['meta_title'] ?? '').toString());
  final description =
      _cleanText((homePage?['meta_description'] ?? '').toString());
  if (title.isEmpty && description.isEmpty) return baseHtml;

  final effectiveTitle = title.isNotEmpty ? _truncate(title, 120) : storeName;
  var html = baseHtml;
  html = _replaceTag(
    html,
    RegExp(r'<title>.*?</title>', dotAll: true),
    '<title>${_escapeHtml(effectiveTitle)}</title>',
  );
  html = _replaceMetaContent(html, name: 'title', content: effectiveTitle);
  if (description.isNotEmpty) {
    html = _replaceMetaContent(
      html,
      name: 'description',
      content: _truncate(description, 320),
    );
  }
  html = _replaceLinkHref(html, rel: 'canonical', href: storeUrl);
  html = _replaceMetaProperty(html, property: 'og:url', content: storeUrl);
  html = _replaceMetaProperty(
    html,
    property: 'og:title',
    content: effectiveTitle,
  );
  if (description.isNotEmpty) {
    html = _replaceMetaProperty(
      html,
      property: 'og:description',
      content: _truncate(description, 320),
    );
  }
  html = _replaceMetaName(html, name: 'twitter:url', content: storeUrl);
  html = _replaceMetaName(
    html,
    name: 'twitter:title',
    content: effectiveTitle,
  );
  if (description.isNotEmpty) {
    html = _replaceMetaName(
      html,
      name: 'twitter:description',
      content: _truncate(description, 320),
    );
  }
  return html;
}

String _buildProductHtml({
  required String baseHtml,
  required String title,
  required String description,
  required String canonicalUrl,
  required String ogImageUrl,
  required String? jsonLdProduct,
  required String fallbackHtml,
  required bool isProduct,
}) {
  var html = baseHtml;

  html = _replaceTag(html, RegExp(r'<title>.*?</title>', dotAll: true),
      '<title>${_escapeHtml(title)}</title>');

  html = _replaceMetaContent(html, name: 'title', content: title);
  html = _replaceMetaContent(html, name: 'description', content: description);

  html = _replaceLinkHref(html, rel: 'canonical', href: canonicalUrl);

  html = _replaceMetaProperty(html,
      property: 'og:type', content: isProduct ? 'product' : 'website');
  html = _replaceMetaProperty(html, property: 'og:url', content: canonicalUrl);
  html = _replaceMetaProperty(html, property: 'og:title', content: title);
  html = _replaceMetaProperty(html,
      property: 'og:description', content: description);

  // Set/insert og:image + twitter:image if we have a product image.
  if (ogImageUrl.isNotEmpty) {
    html = _replaceOrInsertMetaProperty(html,
        property: 'og:image', content: ogImageUrl);
    html = _replaceOrInsertMetaName(html,
        name: 'twitter:image', content: ogImageUrl);
  }

  html = _replaceMetaName(html, name: 'twitter:url', content: canonicalUrl);
  html = _replaceMetaName(html, name: 'twitter:title', content: title);
  html =
      _replaceMetaName(html, name: 'twitter:description', content: description);

  if (jsonLdProduct != null && jsonLdProduct.isNotEmpty) {
    // Inject product JSON-LD right before </head>.
    final injection =
        '\n  <!-- JSON-LD Structured Data for Product (generated at deploy) -->\n'
        '  <script type="application/ld+json" id="seo-product-jsonld">\n'
        '  $jsonLdProduct\n'
        '  </script>\n';

    if (html.contains('id="seo-product-jsonld"')) {
      // If already present, replace the whole block.
      html = html.replaceAll(
        RegExp(
            r'<script type="application/ld\+json" id="seo-product-jsonld">.*?</script>',
            dotAll: true),
        '${injection.trim()}\n',
      );
    } else {
      html = html.replaceFirst(RegExp(r'</head>'), '$injection</head>');
    }
  } else {
    html = html.replaceAll(
      RegExp(
          r'\s*<!-- JSON-LD Structured Data for Product \(generated at deploy\) -->\s*<script type="application/ld\+json" id="seo-product-jsonld">.*?</script>\s*',
          dotAll: true),
      '\n',
    );
  }

  if (fallbackHtml.isNotEmpty) {
    html = html.replaceFirst(RegExp(r'</body>'), '$fallbackHtml\n</body>');
  }

  return html;
}

String _buildCategoryHtml({
  required String baseHtml,
  required String title,
  required String description,
  required String canonicalUrl,
  required String jsonLd,
  required String fallbackHtml,
}) {
  var html = baseHtml;

  html = _replaceTag(html, RegExp(r'<title>.*?</title>', dotAll: true),
      '<title>${_escapeHtml(title)}</title>');

  html = _replaceMetaContent(html, name: 'title', content: title);
  html = _replaceMetaContent(html, name: 'description', content: description);
  html = _replaceLinkHref(html, rel: 'canonical', href: canonicalUrl);

  html = _replaceMetaProperty(html, property: 'og:type', content: 'website');
  html = _replaceMetaProperty(html, property: 'og:url', content: canonicalUrl);
  html = _replaceMetaProperty(html, property: 'og:title', content: title);
  html = _replaceMetaProperty(html,
      property: 'og:description', content: description);

  html = _replaceMetaName(html, name: 'twitter:url', content: canonicalUrl);
  html = _replaceMetaName(html, name: 'twitter:title', content: title);
  html =
      _replaceMetaName(html, name: 'twitter:description', content: description);

  final injection =
      '\n  <!-- JSON-LD Structured Data for Product Category (generated at deploy) -->\n'
      '  <script type="application/ld+json" id="seo-category-jsonld">\n'
      '  $jsonLd\n'
      '  </script>\n';

  html = html.replaceFirst(RegExp(r'</head>'), '$injection</head>');
  if (fallbackHtml.isNotEmpty) {
    html = html.replaceFirst(RegExp(r'</body>'), '$fallbackHtml\n</body>');
  }
  return html;
}

Future<int> _writeStaticTrustPages({
  required Directory buildDir,
  required String baseHtml,
  required String storeUrl,
  required String storeName,
  required Map<String, String> settings,
  required List<Map<String, dynamic>> pages,
  required Map<String, List<Map<String, dynamic>>> pageBlocks,
}) async {
  final fallbacks = _trustPageFallbacks(storeName);
  var written = 0;

  for (final entry in fallbacks.entries) {
    final slug = entry.key;
    final fallback = entry.value;
    final page = _findPageBySlug(pages, slug);
    final blocks = page == null
        ? const <Map<String, dynamic>>[]
        : pageBlocks[(page['id'] ?? '').toString()] ??
            const <Map<String, dynamic>>[];

    final title = _cleanText((page?['title'] ?? '').toString()).isNotEmpty
        ? _cleanText((page?['title'] ?? '').toString())
        : fallback.title;
    final descriptionFromPage =
        _cleanText((page?['meta_description'] ?? '').toString());
    final description = _truncate(
      descriptionFromPage.isNotEmpty
          ? descriptionFromPage
          : fallback.description,
      320,
    );
    final canonicalUrl = _joinUrl(storeUrl, '/$slug');

    final bodyHtml = _buildStaticTrustPageBody(
      slug: slug,
      title: title,
      description: description,
      fallback: fallback,
      blocks: blocks,
      settings: settings,
      storeName: storeName,
      storeUrl: storeUrl,
    );

    final html = _buildStaticTrustPageHtml(
      baseHtml: baseHtml,
      title: '$title | $storeName',
      description: description,
      canonicalUrl: canonicalUrl,
      bodyHtml: bodyHtml,
      jsonLd: _buildStaticTrustPageJsonLd(
        slug: slug,
        title: title,
        description: description,
        pageUrl: canonicalUrl,
        storeUrl: storeUrl,
        storeName: storeName,
        settings: settings,
      ),
    );

    await File(pathJoin(buildDir.path, slug)).writeAsString(html);
    written++;
  }

  return written;
}

String _buildStaticTrustPageHtml({
  required String baseHtml,
  required String title,
  required String description,
  required String canonicalUrl,
  required String bodyHtml,
  required String jsonLd,
}) {
  var html = baseHtml;

  html = _replaceTag(html, RegExp(r'<title>.*?</title>', dotAll: true),
      '<title>${_escapeHtml(title)}</title>');
  html = _replaceMetaContent(html, name: 'title', content: title);
  html = _replaceMetaContent(html, name: 'description', content: description);
  html = _replaceLinkHref(html, rel: 'canonical', href: canonicalUrl);
  html = _replaceMetaProperty(html, property: 'og:type', content: 'website');
  html = _replaceMetaProperty(html, property: 'og:url', content: canonicalUrl);
  html = _replaceMetaProperty(html, property: 'og:title', content: title);
  html = _replaceMetaProperty(html,
      property: 'og:description', content: description);
  html = _replaceMetaName(html, name: 'twitter:url', content: canonicalUrl);
  html = _replaceMetaName(html, name: 'twitter:title', content: title);
  html =
      _replaceMetaName(html, name: 'twitter:description', content: description);

  const style = '''
  <style id="seo-static-page-style">
    #seo-static-page {
      box-sizing: border-box;
      width: 100%;
      margin: 0;
      padding: 28px 24px 64px;
      color: #18212f;
      font-family: Inter, Arial, Helvetica, sans-serif;
      font-size: 16px;
      line-height: 1.65;
      background: #f6f7f8;
    }
    #seo-static-page * { box-sizing: border-box; }
    #seo-static-page .seo-static-shell {
      max-width: 1120px;
      margin: 0 auto;
    }
    #seo-static-page a { color: #2563eb; font-weight: 700; }
    #seo-static-page header,
    #seo-static-page section,
    #seo-static-page .seo-page-nav {
      background: #ffffff;
      border: 1px solid #e0e4ea;
      border-radius: 8px;
      box-shadow: 0 12px 24px rgba(0, 0, 0, 0.035);
    }
    #seo-static-page header {
      padding: 28px;
      margin-bottom: 18px;
    }
    #seo-static-page section {
      padding: 24px;
      margin: 0 0 18px;
    }
    #seo-static-page h1 {
      margin: 0 0 12px;
      font-size: 38px;
      line-height: 1.08;
      letter-spacing: 0;
    }
    #seo-static-page h2 {
      margin: 0 0 12px;
      font-size: 22px;
      line-height: 1.25;
      letter-spacing: 0;
    }
    #seo-static-page h3 {
      margin: 18px 0 6px;
      font-size: 18px;
      line-height: 1.3;
      letter-spacing: 0;
    }
    #seo-static-page p { margin: 0 0 12px; }
    #seo-static-page ul { padding-left: 22px; }
    #seo-static-page dl { margin: 0; }
    #seo-static-page dt { margin-top: 16px; font-weight: 700; }
    #seo-static-page dd { margin: 6px 0 0; }
    #seo-static-page .seo-eyebrow {
      margin-bottom: 10px;
      color: #667085;
      font-size: 13px;
      font-weight: 800;
    }
    #seo-static-page .seo-business-grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 10px 18px;
      margin-top: 8px;
    }
    #seo-static-page .seo-business-grid p {
      margin: 0;
      padding: 12px;
      background: #f8fafc;
      border: 1px solid #e0e4ea;
      border-radius: 8px;
    }
    #seo-static-page .seo-page-nav {
      padding: 16px;
      display: flex;
      flex-wrap: wrap;
      gap: 12px 18px;
    }
    @media (max-width: 640px) {
      #seo-static-page { padding: 18px 14px 48px; }
      #seo-static-page h1 { font-size: 30px; }
      #seo-static-page header,
      #seo-static-page section { padding: 18px; }
      #seo-static-page .seo-business-grid { grid-template-columns: 1fr; }
    }
  </style>
''';

  final injection =
      '\n  <!-- JSON-LD Structured Data for Trust Page (generated at deploy) -->\n'
      '  <script type="application/ld+json" id="seo-trust-page-jsonld">\n'
      '  $jsonLd\n'
      '  </script>\n';

  html = html.replaceFirst(RegExp(r'</head>'), '$style$injection</head>');
  html = html.replaceFirst(RegExp(r'<body>'), '<body>\n$bodyHtml');
  return html;
}

String _buildStaticTrustPageBody({
  required String slug,
  required String title,
  required String description,
  required _TrustPageFallback fallback,
  required List<Map<String, dynamic>> blocks,
  required Map<String, String> settings,
  required String storeName,
  required String storeUrl,
}) {
  final content = _renderTrustBlocks(blocks);
  final fallbackContent = _paragraphsHtml(fallback.body);
  final renderedContent = content.trim().isNotEmpty ? content : fallbackContent;

  return '''
  <main id="seo-static-page">
    <div class="seo-static-shell">
      <header>
        <p class="seo-eyebrow"><a href="${_escapeHtml(_joinUrl(storeUrl, '/'))}">${_escapeHtml(storeName)}</a></p>
        <h1>${_escapeHtml(title)}</h1>
        <p>${_escapeHtml(description)}</p>
      </header>
      ${_businessInfoHtml(settings, storeName)}
      $renderedContent
      <nav class="seo-page-nav" aria-label="Información de la tienda">
        <a href="/productos">Productos</a>
        <a href="/contacto">Contacto</a>
        <a href="/envios">Envíos</a>
        <a href="/devoluciones">Devoluciones</a>
        <a href="/terminos">Términos y condiciones</a>
        <a href="/privacidad">Privacidad</a>
      </nav>
    </div>
  </main>
''';
}

String _businessInfoHtml(Map<String, String> settings, String storeName) {
  final email = _setting(settings, ['contact_email', 'seo_email'],
      fallback: 'contacto@vinabike.cl');
  final phone = _setting(settings, ['contact_phone', 'seo_phone'],
      fallback: '+56998357797');
  final address = _setting(settings, ['contact_address'],
      fallback: 'Álvarez 32, Local 17, Viña del Mar, Chile');
  final hoursSummary = _parseBusinessHours(settings)?.summary ??
      'Lunes a viernes de 11:00 a 19:30; sábados de 11:00 a 15:00.';

  return '''
    <section>
      <h2>Información de la tienda</h2>
      <div class="seo-business-grid">
        <p><strong>Nombre comercial:</strong><br>${_escapeHtml(storeName)}</p>
        <p><strong>Dirección:</strong><br>${_escapeHtml(address)}</p>
        <p><strong>Teléfono y WhatsApp:</strong><br>${_escapeHtml(phone)}</p>
        <p><strong>Email:</strong><br><a href="mailto:${_escapeHtml(email)}">${_escapeHtml(email)}</a></p>
        <p><strong>Horario referencial:</strong><br>${_escapeHtml(hoursSummary)}</p>
        <p><strong>Moneda:</strong><br>Pesos chilenos (CLP). Los precios publicados incluyen IVA cuando corresponde.</p>
      </div>
    </section>
''';
}

String _renderTrustBlocks(List<Map<String, dynamic>> blocks) {
  final visible = blocks
      .where((block) => block['is_visible'] != false)
      .toList(growable: false);
  visible.sort((a, b) =>
      (_toInt(a['order_index']) ?? 0).compareTo(_toInt(b['order_index']) ?? 0));

  final out = StringBuffer();
  for (final block in visible) {
    final type = (block['block_type'] ?? '').toString().trim().toLowerCase();
    final data = block['block_data'] is Map
        ? Map<String, dynamic>.from(block['block_data'] as Map)
        : <String, dynamic>{};

    final title = _policyText(data['title']);
    final subtitle = _policyText(data['subtitle']);
    final content = _policyText(data['content']);

    if (type == 'hero') {
      // Legacy policy heroes used generic marketing copy; static snapshots
      // already have a factual page header, so skip those old hero snippets.
      continue;
    }

    if (type == 'about' || type == 'contact') {
      out.writeln('<section>');
      if (title.isNotEmpty) out.writeln('<h2>${_escapeHtml(title)}</h2>');
      if (content.isNotEmpty) {
        out.writeln(_paragraphsHtml(content));
      } else if (subtitle.isNotEmpty) {
        out.writeln(_paragraphsHtml(subtitle));
      }
      out.writeln('</section>');
      continue;
    }

    if (type == 'features') {
      final features = data['features'];
      if (features is! List || features.isEmpty) continue;
      out.writeln('<section>');
      if (title.isNotEmpty) out.writeln('<h2>${_escapeHtml(title)}</h2>');
      out.writeln('<ul>');
      for (final feature in features) {
        if (feature is! Map) continue;
        final item = Map<String, dynamic>.from(feature);
        final itemTitle = _policyText(item['title']);
        final itemDescription = _policyText(item['description']);
        if (itemTitle.isEmpty && itemDescription.isEmpty) continue;
        out.writeln('<li>');
        if (itemTitle.isNotEmpty) {
          out.writeln('<h3>${_escapeHtml(itemTitle)}</h3>');
        }
        if (itemDescription.isNotEmpty) {
          out.writeln('<p>${_escapeHtml(itemDescription)}</p>');
        }
        out.writeln('</li>');
      }
      out.writeln('</ul>');
      out.writeln('</section>');
      continue;
    }

    if (type == 'faq') {
      final items = data['items'];
      if (items is! List || items.isEmpty) continue;
      out.writeln('<section>');
      if (title.isNotEmpty) out.writeln('<h2>${_escapeHtml(title)}</h2>');
      out.writeln('<dl>');
      for (final item in items) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final question = _policyText(map['question']);
        final answer = _policyText(map['answer']);
        if (question.isEmpty && answer.isEmpty) continue;
        if (question.isNotEmpty) {
          out.writeln('<dt>${_escapeHtml(question)}</dt>');
        }
        if (answer.isNotEmpty) out.writeln('<dd>${_escapeHtml(answer)}</dd>');
      }
      out.writeln('</dl>');
      out.writeln('</section>');
      continue;
    }

    if (title.isNotEmpty || subtitle.isNotEmpty || content.isNotEmpty) {
      out.writeln('<section>');
      if (title.isNotEmpty) out.writeln('<h2>${_escapeHtml(title)}</h2>');
      if (subtitle.isNotEmpty) out.writeln(_paragraphsHtml(subtitle));
      if (content.isNotEmpty) out.writeln(_paragraphsHtml(content));
      out.writeln('</section>');
    }
  }

  return out.toString();
}

String _buildStaticTrustPageJsonLd({
  required String slug,
  required String title,
  required String description,
  required String pageUrl,
  required String storeUrl,
  required String storeName,
  required Map<String, String> settings,
}) {
  final email = _setting(settings, ['contact_email', 'seo_email'],
      fallback: 'contacto@vinabike.cl');
  final phone = _setting(settings, ['contact_phone', 'seo_phone'],
      fallback: '+56998357797');
  final address = _setting(settings, ['contact_address'],
      fallback: 'Álvarez 32, Local 17, Viña del Mar, Chile');
  final instagram = _setting(settings, ['instagram'], fallback: '');
  final openingHoursSpecification =
      _parseBusinessHours(settings)?.jsonLdSpecifications ??
          _defaultOpeningHoursSpecification();

  final pageType = switch (slug) {
    'contacto' => 'ContactPage',
    'nosotros' => 'AboutPage',
    _ => 'WebPage',
  };

  final data = <String, dynamic>{
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': pageType,
        'name': title,
        'description': description,
        'url': pageUrl,
        'isPartOf': {
          '@type': 'WebSite',
          'name': storeName,
          'url': storeUrl,
        },
      },
      {
        '@type': 'LocalBusiness',
        '@id': _joinUrl(storeUrl, '/#localbusiness'),
        'name': storeName,
        'url': storeUrl,
        'email': email,
        'telephone': phone,
        'address': {
          '@type': 'PostalAddress',
          'streetAddress': address,
          'addressLocality': 'Viña del Mar',
          'addressCountry': 'CL',
        },
        'areaServed': {
          '@type': 'Country',
          'name': 'Chile',
        },
        if (instagram.isNotEmpty) 'sameAs': [instagram],
        'openingHoursSpecification': openingHoursSpecification,
        'hasMerchantReturnPolicy': _buildMerchantReturnPolicyJsonLd(storeUrl),
        'contactPoint': {
          '@type': 'ContactPoint',
          'contactType': 'customer support',
          'email': email,
          'telephone': phone,
          'areaServed': 'CL',
          'availableLanguage': ['es'],
        },
      },
    ],
  };

  return jsonEncode(data);
}

String _paragraphsHtml(String text) {
  final normalized = _policyText(text);
  if (normalized.isEmpty) return '';
  final paragraphs = normalized
      .split(RegExp(r'\n\s*\n'))
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty);
  return paragraphs.map((p) => '<p>${_escapeHtml(p)}</p>').join('\n');
}

String _policyText(dynamic value) {
  return (value ?? '')
      .toString()
      .replaceAll('vinabikechile@gmail.com', 'contacto@vinabike.cl')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .trim();
}

String _setting(Map<String, String> settings, List<String> keys,
    {required String fallback}) {
  for (final key in keys) {
    final value = settings[key]?.trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return fallback;
}

class _SeoBusinessHours {
  const _SeoBusinessHours({
    required this.summary,
    required this.jsonLdSpecifications,
  });

  final String summary;
  final List<Map<String, dynamic>> jsonLdSpecifications;
}

class _SeoBusinessHoursPeriod {
  const _SeoBusinessHoursPeriod({required this.opens, required this.closes});

  final String opens;
  final String closes;

  String get label => '$opens - $closes';
}

_SeoBusinessHours? _parseBusinessHours(Map<String, String> settings) {
  final raw = _setting(
    settings,
    ['google_business_regular_hours', 'business_hours_json'],
    fallback: '',
  );
  if (raw.isEmpty) return null;

  try {
    final decoded = jsonDecode(raw);
    final root = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : <String, dynamic>{};
    final data = root['opening_hours'] is Map
        ? Map<String, dynamic>.from(root['opening_hours'] as Map)
        : root;
    final periods = data['periods'] as List<dynamic>? ?? const [];
    if (periods.isEmpty) return null;

    const dayOrder = [
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
      'SUNDAY',
    ];
    const dayLabels = {
      'MONDAY': 'Lunes',
      'TUESDAY': 'Martes',
      'WEDNESDAY': 'Miércoles',
      'THURSDAY': 'Jueves',
      'FRIDAY': 'Viernes',
      'SATURDAY': 'Sábado',
      'SUNDAY': 'Domingo',
    };
    const schemaDayLabels = {
      'MONDAY': 'Monday',
      'TUESDAY': 'Tuesday',
      'WEDNESDAY': 'Wednesday',
      'THURSDAY': 'Thursday',
      'FRIDAY': 'Friday',
      'SATURDAY': 'Saturday',
      'SUNDAY': 'Sunday',
    };

    final hoursByDay = {
      for (final day in dayOrder) day: <_SeoBusinessHoursPeriod>[],
    };

    for (final rawPeriod in periods) {
      if (rawPeriod is! Map) continue;
      final period = Map<String, dynamic>.from(rawPeriod);

      if (period.containsKey('openDay') || period.containsKey('openTime')) {
        final openDay = period['openDay']?.toString().toUpperCase();
        if (openDay == null || !hoursByDay.containsKey(openDay)) continue;

        final openTime = _formatBusinessTime(period['openTime']);
        final closeTime = _formatBusinessTime(period['closeTime']);
        if (openTime == null || closeTime == null) continue;

        hoursByDay[openDay]!.add(
          _SeoBusinessHoursPeriod(opens: openTime, closes: closeTime),
        );
        continue;
      }

      final open = period['open'] is Map
          ? Map<String, dynamic>.from(period['open'] as Map)
          : null;
      final close = period['close'] is Map
          ? Map<String, dynamic>.from(period['close'] as Map)
          : null;
      final openDay = _googlePlacesDayToBusinessDay(open?['day']);
      if (openDay == null || !hoursByDay.containsKey(openDay)) continue;

      final openTime = _formatPlacesTime(open?['time']);
      final closeTime = _formatPlacesTime(close?['time']);
      if (openTime == null || closeTime == null) continue;

      hoursByDay[openDay]!.add(
        _SeoBusinessHoursPeriod(opens: openTime, closes: closeTime),
      );
    }

    final daySchedules = <String, String>{
      for (final day in dayOrder)
        day: hoursByDay[day]!.isEmpty
            ? 'Cerrado'
            : hoursByDay[day]!.map((period) => period.label).join(' / '),
    };

    final summaryParts = <String>[];
    var start = 0;
    while (start < dayOrder.length) {
      final schedule = daySchedules[dayOrder[start]]!;
      var end = start;

      while (end + 1 < dayOrder.length &&
          daySchedules[dayOrder[end + 1]] == schedule) {
        end++;
      }

      summaryParts.add(
        '${_formatSeoDayRange(dayLabels[dayOrder[start]]!, dayLabels[dayOrder[end]]!)}: $schedule',
      );
      start = end + 1;
    }

    final jsonLdSpecifications = <Map<String, dynamic>>[];
    for (final day in dayOrder) {
      final schemaDay = schemaDayLabels[day]!;
      for (final period in hoursByDay[day]!) {
        jsonLdSpecifications.add({
          '@type': 'OpeningHoursSpecification',
          'dayOfWeek': schemaDay,
          'opens': period.opens,
          'closes': period.closes,
        });
      }
    }

    if (jsonLdSpecifications.isEmpty) return null;

    return _SeoBusinessHours(
      summary: summaryParts.join('; '),
      jsonLdSpecifications: jsonLdSpecifications,
    );
  } catch (_) {
    return null;
  }
}

List<Map<String, dynamic>> _defaultOpeningHoursSpecification() {
  return [
    {
      '@type': 'OpeningHoursSpecification',
      'dayOfWeek': ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
      'opens': '11:00',
      'closes': '19:30',
    },
    {
      '@type': 'OpeningHoursSpecification',
      'dayOfWeek': 'Saturday',
      'opens': '11:00',
      'closes': '15:00',
    },
  ];
}

String _formatSeoDayRange(String start, String end) {
  if (start == end) return start;
  if (start == 'Lunes' && end == 'Domingo') return 'Todos los días';
  return '$start a $end';
}

String? _googlePlacesDayToBusinessDay(dynamic rawDay) {
  final day = rawDay is num ? rawDay.toInt() : int.tryParse('$rawDay');
  return switch (day) {
    0 => 'SUNDAY',
    1 => 'MONDAY',
    2 => 'TUESDAY',
    3 => 'WEDNESDAY',
    4 => 'THURSDAY',
    5 => 'FRIDAY',
    6 => 'SATURDAY',
    _ => null,
  };
}

String? _formatBusinessTime(dynamic rawTime) {
  if (rawTime is String) return _formatPlacesTime(rawTime);
  if (rawTime is! Map) return null;

  final time = Map<String, dynamic>.from(rawTime);
  final hours = (time['hours'] as num?)?.toInt() ?? 0;
  final minutes = (time['minutes'] as num?)?.toInt() ?? 0;

  return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
}

String? _formatPlacesTime(dynamic rawTime) {
  final digits = rawTime?.toString().trim();
  if (digits == null || digits.isEmpty) return null;
  if (digits.contains(':')) return digits;
  if (digits.length < 3) return null;

  final padded = digits.padLeft(4, '0');
  final hours = padded.substring(0, 2);
  final minutes = padded.substring(2, 4);
  return '$hours:$minutes';
}

Map<String, dynamic>? _findPageBySlug(
  List<Map<String, dynamic>> pages,
  String slug,
) {
  for (final page in pages) {
    if ((page['slug'] ?? '').toString().trim() == slug) return page;
  }
  return null;
}

Map<String, _TrustPageFallback> _trustPageFallbacks(String storeName) {
  return {
    'contacto': _TrustPageFallback(
      title: 'Contacto',
      description:
          'Contacta a $storeName en Viña del Mar: dirección, teléfono, email, WhatsApp y horarios de atención.',
      body:
          'Estamos ubicados en Álvarez 32, Local 17, Viña del Mar. Puedes escribirnos a contacto@vinabike.cl o llamarnos al +56 9 9835 7797 para consultas sobre productos, pedidos, garantías y servicio técnico.',
    ),
    'nosotros': _TrustPageFallback(
      title: 'Sobre Nosotros',
      description:
          'Conoce $storeName, tienda y taller de bicicletas en Viña del Mar.',
      body:
          '$storeName es una tienda y taller de bicicletas en Viña del Mar. Vendemos bicicletas, repuestos y accesorios, y también realizamos mantenciones y reparaciones.',
    ),
    'terminos': _TrustPageFallback(
      title: 'Términos y Condiciones',
      description:
          'Condiciones de compra, pago, disponibilidad, garantías y uso del sitio de $storeName.',
      body:
          'Los precios se publican en pesos chilenos (CLP). La disponibilidad de productos está sujeta a stock. Las compras se confirman una vez validado el pago y los datos del pedido.',
    ),
    'privacidad': _TrustPageFallback(
      title: 'Política de Privacidad',
      description:
          'Información sobre tratamiento de datos personales de clientes de $storeName.',
      body:
          'Usamos los datos personales entregados por clientes para procesar pedidos, coordinar entregas, responder consultas y entregar soporte. No vendemos datos personales a terceros.',
    ),
    'devoluciones': _TrustPageFallback(
      title: 'Política de Devoluciones',
      description:
          'Condiciones de devolución, retracto, cambios y reembolsos para compras en $storeName.',
      body:
          'Puedes solicitar devolución dentro de 10 días desde la recepción del producto, siempre que esté sin uso, en estado original y con embalaje completo. Para iniciar el proceso, escribe a contacto@vinabike.cl con tu número de pedido.',
    ),
    'envios': _TrustPageFallback(
      title: 'Información de Envíos',
      description:
          'Opciones de despacho, retiro en tienda, plazos y costos de envío para compras en $storeName.',
      body:
          'Despachamos a Chile continental y ofrecemos retiro en tienda en Álvarez 32, Local 17, Viña del Mar. Los costos de envío se calculan según peso y destino durante el checkout.',
    ),
  };
}

String? _buildProductJsonLd({
  required String productUrl,
  required String storeUrl,
  required String storeName,
  required Map<String, dynamic> product,
  required String description,
  required bool inStock,
  required String currency,
  required num? priceNum,
  required List<String> imageUrls,
  required String productBrand,
  required String productSku,
}) {
  final name =
      _cleanText(_firstNonEmpty(product['website_name'], product['name']));
  if (imageUrls.isEmpty) {
    return null;
  }

  final gtin = _validGtin(_firstNonEmpty(
    product['website_merchant_gtin'],
    product['gtin'],
    product['barcode'],
  ));
  final cleanDescription = _cleanText(description);
  final category = (product['category_name'] ?? '').toString().trim();
  final structuredBrandName =
      productBrand.isNotEmpty ? productBrand : (gtin == null ? 'Genérico' : '');

  final productData = <String, dynamic>{
    '@type': 'Product',
    'name': name,
    'description': cleanDescription,
    'url': productUrl,
    'image': imageUrls,
    if (productSku.isNotEmpty) 'sku': productSku,
    if (gtin == null && productSku.isNotEmpty) 'mpn': productSku,
    if (category.isNotEmpty) 'category': category,
    if (structuredBrandName.isNotEmpty)
      'brand': {
        '@type': 'Brand',
        'name': structuredBrandName,
      },
    if (gtin != null) 'gtin': gtin,
    'offers': {
      '@type': 'Offer',
      'url': productUrl,
      'priceCurrency': currency,
      if (priceNum != null) 'price': priceNum.toString(),
      'availability': inStock
          ? 'https://schema.org/InStock'
          : 'https://schema.org/OutOfStock',
      'itemCondition': 'https://schema.org/NewCondition',
      'shippingDetails': _buildShippingDetailsJsonLd(currency),
      'hasMerchantReturnPolicy': _buildMerchantReturnPolicyJsonLd(storeUrl),
      'seller': {
        '@type': 'Organization',
        'name': storeName,
      },
    },
  };

  final graph = <Map<String, dynamic>>[
    productData,
    _buildBreadcrumbListJsonLd(
      storeUrl: storeUrl,
      items: [
        ('Inicio', '/'),
        ('Productos', '/productos'),
        if (category.isNotEmpty)
          (category, '/productos/categoria/${_slugify(category)}'),
        (name, productUrl),
      ],
    ),
  ];

  final data = <String, dynamic>{
    '@context': 'https://schema.org',
    '@graph': graph,
  };

  return jsonEncode(data);
}

Map<String, dynamic> _buildShippingDetailsJsonLd(String currency) {
  return {
    '@type': 'OfferShippingDetails',
    'shippingRate': {
      '@type': 'MonetaryAmount',
      'maxValue': _structuredDataMaxShippingRateClp,
      'currency': currency,
    },
    'shippingDestination': {
      '@type': 'DefinedRegion',
      'addressCountry': 'CL',
    },
    'deliveryTime': {
      '@type': 'ShippingDeliveryTime',
      'handlingTime': {
        '@type': 'QuantitativeValue',
        'minValue': 1,
        'maxValue': 2,
        'unitCode': 'DAY',
      },
      'transitTime': {
        '@type': 'QuantitativeValue',
        'minValue': 2,
        'maxValue': 10,
        'unitCode': 'DAY',
      },
    },
  };
}

Map<String, dynamic> _buildMerchantReturnPolicyJsonLd(String storeUrl) {
  return {
    '@type': 'MerchantReturnPolicy',
    'applicableCountry': 'CL',
    'returnPolicyCategory':
        'https://schema.org/MerchantReturnFiniteReturnWindow',
    'merchantReturnDays': 10,
    'returnMethod': 'https://schema.org/ReturnByMail',
    'returnFees': 'https://schema.org/ReturnFeesCustomerResponsibility',
    'url': _joinUrl(storeUrl, '/devoluciones'),
  };
}

String _buildCategoryJsonLd({
  required _ProductCategorySeo category,
  required String categoryUrl,
  required String storeName,
}) {
  final itemList = category.products.take(10).toList(growable: false);
  final data = <String, dynamic>{
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'CollectionPage',
        'name': '${category.name} para bicicletas',
        'url': categoryUrl,
        'description':
            'Productos de ${category.name} disponibles en $storeName.',
      },
      _buildBreadcrumbListJsonLd(
        storeUrl: categoryUrl,
        items: [
          ('Inicio', '/'),
          ('Productos', '/productos'),
          (category.name, categoryUrl),
        ],
      ),
      {
        '@type': 'ItemList',
        'name': '${category.name} en $storeName',
        'numberOfItems': category.productCount,
        'itemListElement': [
          for (var i = 0; i < itemList.length; i++)
            {
              '@type': 'ListItem',
              'position': i + 1,
              'url': itemList[i].url,
              'name': itemList[i].name,
            },
        ],
      },
    ],
  };
  return jsonEncode(data);
}

Map<String, dynamic> _buildBreadcrumbListJsonLd({
  required String storeUrl,
  required List<(String, String)> items,
}) {
  final baseUrl = storeUrl.startsWith('http')
      ? _urlOrigin(storeUrl)
      : 'https://vinabike.cl';

  return {
    '@type': 'BreadcrumbList',
    'itemListElement': [
      for (var i = 0; i < items.length; i++)
        {
          '@type': 'ListItem',
          'position': i + 1,
          'name': _cleanText(items[i].$1),
          'item': items[i].$2.startsWith('http')
              ? items[i].$2
              : _joinUrl(baseUrl, items[i].$2),
        },
    ],
  };
}

String _urlOrigin(String url) {
  final uri = Uri.parse(url);
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$port';
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
  // Keep this aligned with the public storefront surface, not only the much
  // smaller Google Merchant subset. Merchant can still be requested explicitly
  // with `--product-scope merchant` for debugging feed-specific issues.
  const pageSize = 1000;
  final products = <Map<String, dynamic>>[];

  for (var offset = 0;; offset += pageSize) {
    final url = Uri.parse(
      '$supabaseUrl/rest/v1/products'
      '?tenant_id=eq.$tenantId'
      '${onlyMerchant ? '&is_google_merchant=eq.true' : ''}'
      '&is_active=eq.true'
      '&is_published=eq.true'
      '&show_on_website=eq.true'
      '&product_type=eq.product'
      '&select=id,name,description,website_description,website_name,website_price,website_image_url,website_image_url_optimized,website_image_urls,website_seo_title,website_seo_description,website_search_terms,website_merchant_gtin,price,price_currency,sku,gtin,barcode,image_url,image_url_optimized,image_urls,brand,category_name,stock_quantity,inventory_qty,track_stock,updated_at,created_at'
      '&limit=$pageSize'
      '&offset=$offset',
    );

    final response = await _httpGet(
      url,
      headers: {
        'apikey': serviceRoleKey,
        'Authorization': 'Bearer $serviceRoleKey',
      },
    );

    final decoded = jsonDecode(response) as List<dynamic>;
    products.addAll(decoded.map((e) => (e as Map<String, dynamic>)));
    if (decoded.length < pageSize) break;
  }

  return products;
}

Future<List<Map<String, dynamic>>> _fetchProductUrlAliases({
  required String supabaseUrl,
  required String tenantId,
  required String serviceRoleKey,
}) async {
  const pageSize = 1000;
  final aliases = <Map<String, dynamic>>[];

  for (var offset = 0;; offset += pageSize) {
    final url = Uri.parse(
      '$supabaseUrl/rest/v1/product_url_aliases'
      '?tenant_id=eq.$tenantId'
      '&select=product_id,alias_path,source,created_at'
      '&order=created_at.asc'
      '&limit=$pageSize'
      '&offset=$offset',
    );
    final response = await _httpGet(
      url,
      headers: {
        'apikey': serviceRoleKey,
        'Authorization': 'Bearer $serviceRoleKey',
      },
    );
    final decoded = jsonDecode(response) as List<dynamic>;
    aliases.addAll(decoded.map((e) => (e as Map<String, dynamic>)));
    if (decoded.length < pageSize) break;
  }

  return aliases;
}

Future<List<Map<String, dynamic>>> _fetchWebsitePages({
  required String supabaseUrl,
  required String tenantId,
  required String serviceRoleKey,
}) async {
  final url = Uri.parse(
    '$supabaseUrl/rest/v1/website_pages'
    '?tenant_id=eq.$tenantId'
    '&is_published=eq.true'
    '&select=id,slug,title,meta_title,meta_description,is_home,updated_at'
    '&limit=500',
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

Future<Map<String, List<Map<String, dynamic>>>> _fetchWebsiteBlocksForPages({
  required String supabaseUrl,
  required List<Map<String, dynamic>> pages,
  required String serviceRoleKey,
}) async {
  final pageIds = pages
      .map((page) => (page['id'] ?? '').toString().trim())
      .where((id) => id.isNotEmpty)
      .toList(growable: false);
  if (pageIds.isEmpty) return {};

  final pageFilter = pageIds.map(Uri.encodeComponent).join(',');
  final url = Uri.parse(
    '$supabaseUrl/rest/v1/website_blocks'
    '?page_id=in.($pageFilter)'
    '&is_visible=eq.true'
    '&select=page_id,block_type,block_data,order_index,is_visible'
    '&order=order_index.asc',
  );

  final response = await _httpGet(
    url,
    headers: {
      'apikey': serviceRoleKey,
      'Authorization': 'Bearer $serviceRoleKey',
    },
  );

  final decoded = jsonDecode(response) as List<dynamic>;
  final byPage = <String, List<Map<String, dynamic>>>{};
  for (final item in decoded) {
    final block = item as Map<String, dynamic>;
    final pageId = (block['page_id'] ?? '').toString();
    if (pageId.isEmpty) continue;
    byPage.putIfAbsent(pageId, () => <Map<String, dynamic>>[]).add(block);
  }

  for (final blocks in byPage.values) {
    blocks.sort((a, b) => (_toInt(a['order_index']) ?? 0)
        .compareTo(_toInt(b['order_index']) ?? 0));
  }

  return byPage;
}

Future<String> _httpGet(Uri url, {required Map<String, String> headers}) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(url);
    headers.forEach(req.headers.set);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException(
          'GET $url failed: ${res.statusCode} ${res.reasonPhrase}\n$body');
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
  final cut = t.substring(0, maxLen).trim();
  final lastSpace = cut.lastIndexOf(' ');
  if (lastSpace > (maxLen * 0.75).floor()) {
    return cut.substring(0, lastSpace).trim();
  }
  return cut;
}

String _firstNonEmpty(
  dynamic first, [
  dynamic second,
  dynamic third,
  dynamic fourth,
]) {
  for (final value in [first, second, third, fourth]) {
    final text = (value ?? '').toString().trim();
    if (text.isNotEmpty) return text;
  }
  return '';
}

List<String> _productImageUrls(Map<String, dynamic> product) {
  final urls = <String>[];

  void add(dynamic value) {
    final url = (value ?? '').toString().trim();
    if (url.isEmpty || urls.contains(url)) return;
    if (!url.startsWith('https://') && !url.startsWith('http://')) return;
    urls.add(url);
  }

  add(_firstNonEmpty(
    product['website_image_url_optimized'],
    product['image_url_optimized'],
  ));
  add(_firstNonEmpty(product['website_image_url'], product['image_url']));

  final websiteImageUrls = product['website_image_urls'];
  final baseImageUrls = product['image_urls'];
  final gallerySource = websiteImageUrls is List && websiteImageUrls.isNotEmpty
      ? websiteImageUrls
      : baseImageUrls;
  if (gallerySource is List) {
    for (final image in gallerySource) {
      add(image);
    }
  }

  // Google supports many images per URL, but keeping this capped prevents
  // oversized sitemap entries while still exposing useful product alternates.
  return urls.take(10).toList(growable: false);
}

String? _validGtin(String rawValue) {
  final value = rawValue.trim().replaceAll(RegExp(r'[\s-]+'), '');
  if (!RegExp(r'^\d+$').hasMatch(value)) return null;
  if (!(value.length == 8 ||
      value.length == 12 ||
      value.length == 13 ||
      value.length == 14)) {
    return null;
  }
  if (!_hasValidGtinCheckDigit(value)) return null;
  return value;
}

bool _hasValidGtinCheckDigit(String value) {
  final digits = value.split('').map(int.parse).toList(growable: false);
  final checkDigit = digits.last;
  var sum = 0;
  var positionFromRight = 1;

  for (var i = digits.length - 2; i >= 0; i--) {
    sum += digits[i] * (positionFromRight.isOdd ? 3 : 1);
    positionFromRight++;
  }

  final calculatedCheckDigit = (10 - (sum % 10)) % 10;
  return calculatedCheckDigit == checkDigit;
}

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((entry) => _cleanText((entry ?? '').toString()))
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
}

String _fallbackProductDescription({
  required String productName,
  required String productBrand,
  required String productCategory,
  required String storeName,
}) {
  final parts = <String>[
    'Compra $productName online en $storeName.',
    if (productBrand.isNotEmpty) 'Marca: $productBrand.',
    if (productCategory.isNotEmpty) 'Categoría: $productCategory.',
    'Retiro en tienda y atención especializada para bicicletas en Viña del Mar.',
  ];
  return _cleanText(parts.join(' '));
}

String _productLocalSearchPhrase({
  required String productName,
  required String productCategory,
  required List<String> searchTerms,
}) {
  if (searchTerms.isNotEmpty) {
    return _cleanText(searchTerms.first);
  }

  final haystack = _normalizeSearchText('$productName $productCategory');
  final kind = _productSearchKind(haystack, productCategory);
  if (kind.isEmpty) return '';

  final wheelSize = _extractWheelSize('$productName $productCategory');
  if (wheelSize.isNotEmpty) {
    return '$kind aro $wheelSize para bicicleta en Viña del Mar';
  }
  return '$kind para bicicleta en Viña del Mar';
}

String _productSearchKind(String normalizedHaystack, String productCategory) {
  if (normalizedHaystack.contains('camara')) return 'cámara';
  if (normalizedHaystack.contains('neumatico') ||
      normalizedHaystack.contains('cubierta')) {
    return 'neumático';
  }
  if (normalizedHaystack.contains('cadena')) return 'cadena';
  if (normalizedHaystack.contains('cable')) return 'cable';
  if (normalizedHaystack.contains('pastilla')) return 'pastillas de freno';
  if (normalizedHaystack.contains('freno')) return 'freno';
  if (normalizedHaystack.contains('bolso')) return 'bolso';
  if (normalizedHaystack.contains('luz')) return 'luz';

  final category = _cleanText(productCategory).trim();
  if (category.isEmpty) return '';
  return category.toLowerCase();
}

String _appendProductSearchPhrase({
  required String description,
  required String searchPhrase,
}) {
  final cleanDescription = _cleanText(description);
  if (searchPhrase.isEmpty) return cleanDescription;

  final normalizedDescription = _normalizeSearchText(cleanDescription);
  final normalizedPhrase = _normalizeSearchText(searchPhrase);
  if (normalizedDescription.contains(normalizedPhrase)) {
    return cleanDescription;
  }

  return _cleanText(
    '$cleanDescription Ideal si buscas $searchPhrase, con compra online, '
    'retiro en tienda y asesoría especializada.',
  );
}

String _buildProductSeoTitle({
  required String baseTitle,
  required String storeName,
  required String searchPhrase,
}) {
  final cleanStoreName = _cleanText(storeName);
  final storeSuffix =
      cleanStoreName.isEmpty ? 'Viña del Mar' : '$cleanStoreName Viña del Mar';
  var root = _cleanText(baseTitle);

  if (cleanStoreName.isNotEmpty) {
    root = root.replaceFirst(
      RegExp(r'\s*\|\s*' + RegExp.escape(cleanStoreName) + r'\s*$',
          caseSensitive: false),
      '',
    );
  }

  final normalizedRoot = _normalizeSearchText(root);
  final shortPhrase = _shortProductSearchPhrase(searchPhrase);
  final shouldPrefix = shortPhrase.isNotEmpty &&
      !_titleAlreadyTargetsPhrase(normalizedRoot, searchPhrase);
  final separatorLength = shouldPrefix ? ' -  | '.length : ' | '.length;
  final availableRootLength =
      120 - storeSuffix.length - separatorLength - shortPhrase.length;
  final rootLimit = availableRootLength < 24 ? 24 : availableRootLength;
  final fittedRoot = _truncate(root, rootLimit);
  final rawTitle = shouldPrefix
      ? '$shortPhrase - $fittedRoot | $storeSuffix'
      : '$fittedRoot | $storeSuffix';

  return _truncate(_cleanText(rawTitle), 120);
}

bool _titleAlreadyTargetsPhrase(String normalizedTitle, String searchPhrase) {
  final wheelSize = _extractWheelSize(searchPhrase);
  if (wheelSize.isNotEmpty) {
    return normalizedTitle.contains('aro ${_normalizeWheelSize(wheelSize)}');
  }

  final normalizedPhrase = _normalizeSearchText(searchPhrase)
      .replaceAll(' para bicicleta en vina del mar', '');
  return normalizedPhrase.isNotEmpty &&
      normalizedTitle.contains(normalizedPhrase);
}

String _shortProductSearchPhrase(String searchPhrase) {
  if (searchPhrase.isEmpty) return '';
  final shortened = _cleanText(searchPhrase)
      .replaceAll(' para bicicleta en Viña del Mar', ' Viña del Mar');
  if (shortened.isEmpty) return '';
  return '${shortened[0].toUpperCase()}${shortened.substring(1)}';
}

String _buildProductFallbackHtml({
  required String title,
  required String description,
  required String canonicalUrl,
  required String imageUrl,
  required String productBrand,
  required String productCategory,
  required String productSku,
  required num? priceNum,
  required String currency,
  required bool inStock,
}) {
  final details = <String>[];
  if (productBrand.isNotEmpty) details.add('Marca: $productBrand');
  if (productCategory.isNotEmpty) details.add('Categoría: $productCategory');
  if (productSku.isNotEmpty) details.add('SKU: $productSku');
  if (priceNum != null) {
    details.add('Precio: ${priceNum.toStringAsFixed(0)} $currency');
  }
  details.add(
      inStock ? 'Disponibilidad: en stock' : 'Disponibilidad: consultar stock');

  final imageHtml = imageUrl.isEmpty
      ? ''
      : '<img src="${_escapeHtml(imageUrl)}" alt="${_escapeHtml(title)}" '
          'loading="lazy" style="max-width:240px;height:auto;">';

  return '''
  <noscript id="seo-product-fallback">
    <main>
      <article>
        <h1>${_escapeHtml(title)}</h1>
        <p>${_escapeHtml(description)}</p>
        $imageHtml
        <ul>
          ${details.map((item) => '<li>${_escapeHtml(item)}</li>').join('\n          ')}
        </ul>
        <p>Retiro en tienda y atención especializada para bicicletas en Viña del Mar.</p>
        <p><a href="${_escapeHtml(canonicalUrl)}">Ver producto en Viñabike</a></p>
        <p><a href="/productos">Ver más productos de bicicleta</a></p>
      </article>
    </main>
  </noscript>''';
}

String _buildCategorySeoTitle({
  required _ProductCategorySeo category,
  required String storeName,
}) {
  final sizeSummary = _categoryWheelSizeSummary(category);
  final cleanStoreName = _cleanText(storeName);
  final suffix =
      cleanStoreName.isEmpty ? 'Viña del Mar' : '$cleanStoreName Viña del Mar';

  if (sizeSummary.isNotEmpty && _isWheelProductCategory(category.name)) {
    return '${category.name} para bicicletas aro $sizeSummary | $suffix';
  }
  return '${category.name} para bicicletas | $suffix';
}

String _buildCategorySeoDescription({
  required _ProductCategorySeo category,
  required String storeName,
}) {
  final sizeSummary = _categoryWheelSizeSummary(category);
  final sizeText =
      sizeSummary.isNotEmpty && _isWheelProductCategory(category.name)
          ? ' aro $sizeSummary'
          : '';
  return _cleanText(
    'Compra ${category.name} para bicicletas$sizeText en $storeName. '
    '${category.productCount} productos disponibles online con retiro en tienda '
    'y atención especializada en Viña del Mar.',
  );
}

String _buildCategoryFallbackHtml({
  required String title,
  required String description,
  required _ProductCategorySeo category,
}) {
  final items = category.products.take(24).map((product) {
    return '<li><a href="${_escapeHtml(product.url)}">'
        '${_escapeHtml(product.name)}</a></li>';
  }).join('\n          ');

  return '''
  <noscript id="seo-category-fallback">
    <main>
      <h1>${_escapeHtml(title)}</h1>
      <p>${_escapeHtml(description)}</p>
      <ul>
          $items
      </ul>
      <p><a href="/productos">Ver catálogo completo de Viñabike</a></p>
    </main>
  </noscript>''';
}

String _categoryWheelSizeSummary(_ProductCategorySeo category) {
  final sizes = <String>{};
  for (final product in category.products) {
    final size = _extractWheelSize(product.name);
    if (size.isNotEmpty) sizes.add(size);
  }

  final ordered = sizes.toList()
    ..sort((a, b) => _wheelSizeOrder(a).compareTo(_wheelSizeOrder(b)));
  if (ordered.isEmpty) return '';

  final selected = ordered.take(5).toList(growable: false);
  if (selected.length == 1) return selected.first;
  if (selected.length == 2) return '${selected.first} y ${selected.last}';
  return '${selected.take(selected.length - 1).join(', ')} y ${selected.last}';
}

bool _isWheelProductCategory(String categoryName) {
  final normalized = _normalizeSearchText(categoryName);
  return normalized.contains('camara') ||
      normalized.contains('neumatico') ||
      normalized.contains('cubierta') ||
      normalized.contains('llanta') ||
      normalized.contains('aro');
}

int _wheelSizeOrder(String size) {
  const order = {
    '12': 12,
    '14': 14,
    '16': 16,
    '18': 18,
    '20': 20,
    '24': 24,
    '26': 26,
    '27.5': 275,
    '28': 280,
    '29': 290,
    '700c': 700,
  };
  return order[_normalizeWheelSize(size)] ?? 999;
}

String _extractWheelSize(String text) {
  final normalized = _normalizeSearchText(text);
  final patterns = <RegExp>[
    RegExp(r'\baro\s*(700c?|29|28|27[.,]?5|26|24|20|18|16|14|12)\b'),
    RegExp(r'\b(700c?|29|28|27[.,]?5|26|24|20|18|16|14|12)\s*(?:x|×)\b'),
  ];

  for (final pattern in patterns) {
    final match = pattern.firstMatch(normalized);
    if (match == null) continue;
    return _normalizeWheelSize(match.group(1) ?? '');
  }
  return '';
}

String _normalizeWheelSize(String size) {
  final normalized = size.toLowerCase().replaceAll(',', '.').trim();
  if (normalized == '700') return '700c';
  if (normalized == '27.5') return '27.5';
  return normalized.replaceAll(RegExp(r'[^0-9a-z.]'), '');
}

String _normalizeSearchText(String text) {
  var normalized = text.toLowerCase();
  const replacements = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ñ': 'n',
  };
  replacements
      .forEach((from, to) => normalized = normalized.replaceAll(from, to));
  normalized = normalized.replaceAll('×', 'x');
  normalized = normalized.replaceAll(RegExp(r'\s+'), ' ');
  return normalized.trim();
}

List<_ProductCategorySeo> _buildProductCategories({
  required List<Map<String, dynamic>> products,
  required String storeUrl,
}) {
  final bySlug = <String, _MutableProductCategorySeo>{};

  for (final product in products) {
    final name = _cleanText((product['category_name'] ?? '').toString());
    if (name.isEmpty) continue;

    final slug = _slugify(name);
    if (slug.isEmpty) continue;

    final productPath = _publicProductPath(product);
    if (productPath == '/productos') continue;

    final item = _CategoryProductSeo(
      name: _cleanText((product['name'] ?? '').toString()),
      url: _joinUrl(storeUrl, productPath),
    );

    final existing = bySlug.putIfAbsent(
      slug,
      () => _MutableProductCategorySeo(
        name: name,
        slug: slug,
      ),
    );
    existing.products.add(item);
  }

  final categories = bySlug.values
      .where((category) => category.products.length >= 2)
      .map(
        (category) => _ProductCategorySeo(
          name: category.name,
          slug: category.slug,
          products: category.products.toList(growable: false),
        ),
      )
      .toList(growable: false);

  categories.sort((a, b) {
    final byCount = b.productCount.compareTo(a.productCount);
    if (byCount != 0) return byCount;
    return a.name.compareTo(b.name);
  });
  return categories;
}

String _slugify(String value) {
  var s = value.toLowerCase();
  const replacements = {
    'á': 'a',
    'é': 'e',
    'í': 'i',
    'ó': 'o',
    'ú': 'u',
    'ü': 'u',
    'ñ': 'n',
  };
  replacements.forEach((from, to) => s = s.replaceAll(from, to));
  s = s.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  s = s.replaceAll(RegExp(r'-+'), '-');
  return s.replaceAll(RegExp(r'^-|-$'), '');
}

String _publicProductPath(Map<String, dynamic> product) {
  final id = (product['id'] ?? '').toString().trim();
  final sku = (product['sku'] ?? '').toString().trim();
  if (sku.isEmpty) return id.isEmpty ? '/productos' : '/productos/$id';

  final name =
      _cleanText(_firstNonEmpty(product['website_name'], product['name']));
  var slug = _slugify(name);
  if (slug.length > 80) {
    slug = slug.substring(0, 80).replaceFirst(RegExp(r'-+$'), '');
  }
  if (slug.isEmpty) slug = 'producto';
  return '/productos/$slug/${Uri.encodeComponent(sku)}';
}

Future<void> _writeCrawlerFiles({
  required Directory buildDir,
  required String storeUrl,
  required List<Map<String, dynamic>> products,
  required List<_ProductCategorySeo> categories,
  required List<Map<String, dynamic>> pages,
}) async {
  final normalizedStoreUrl = storeUrl.replaceAll(RegExp(r'/+$'), '');
  final now = DateTime.now().toUtc();
  const generatedStaticRoutes = <String>{
    '/',
    '/productos',
    '/servicios',
    '/contacto',
    '/nosotros',
    '/terminos',
    '/privacidad',
    '/devoluciones',
    '/envios',
  };
  final urls = <String, _SitemapUrl>{};

  void addUrl(
    String path, {
    DateTime? lastmod,
    String? changefreq,
    String? priority,
    List<_SitemapImage> images = const [],
  }) {
    if (path.isEmpty) return;
    final normalizedPath =
        path == '/' ? '/' : '/${path.replaceAll(RegExp(r'^/+|/+$'), '')}';
    urls[normalizedPath] = _SitemapUrl(
      loc: _joinUrl(normalizedStoreUrl, normalizedPath),
      lastmod: lastmod ?? now,
      changefreq: changefreq,
      priority: priority,
      images: images,
    );
  }

  addUrl('/', changefreq: 'weekly', priority: '1.0');
  addUrl('/productos', changefreq: 'daily', priority: '0.9');
  addUrl('/servicios', changefreq: 'monthly', priority: '0.7');
  addUrl('/contacto', changefreq: 'monthly', priority: '0.6');
  addUrl('/nosotros', changefreq: 'monthly', priority: '0.5');
  addUrl('/terminos', changefreq: 'yearly', priority: '0.3');
  addUrl('/privacidad', changefreq: 'yearly', priority: '0.3');
  addUrl('/devoluciones', changefreq: 'yearly', priority: '0.3');
  addUrl('/envios', changefreq: 'yearly', priority: '0.3');

  for (final page in pages) {
    final route = _routeForWebsitePage(page);
    if (route == null) continue;
    if (generatedStaticRoutes.contains(route)) continue;
    addUrl(
      route,
      lastmod: _parseDateTime(page['updated_at']),
      changefreq: route == '/' ? 'weekly' : 'monthly',
      priority: route == '/' ? '1.0' : '0.5',
    );
  }

  for (final product in products) {
    final productPath = _publicProductPath(product);
    if (productPath == '/productos') continue;
    final productName =
        _cleanText(_firstNonEmpty(product['website_name'], product['name']));
    addUrl(
      productPath,
      lastmod: now,
      changefreq: 'weekly',
      priority: '0.8',
      images: _productImageUrls(product)
          .map(
            (url) => _SitemapImage(
              loc: url,
              title: productName,
            ),
          )
          .toList(growable: false),
    );
  }

  for (final category in categories) {
    addUrl(
      '/productos/categoria/${category.slug}',
      changefreq: 'weekly',
      priority: '0.7',
    );
  }

  final sorted = urls.values.toList()..sort((a, b) => a.loc.compareTo(b.loc));

  final sitemap = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" '
      'xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">',
    );
  for (final url in sorted) {
    sitemap
      ..writeln('  <url>')
      ..writeln('    <loc>${_escapeXml(url.loc)}</loc>')
      ..writeln('    <lastmod>${_formatDate(url.lastmod)}</lastmod>');
    for (final image in url.images) {
      sitemap
        ..writeln('    <image:image>')
        ..writeln('      <image:loc>${_escapeXml(image.loc)}</image:loc>');
      if (image.title.isNotEmpty) {
        sitemap.writeln(
          '      <image:title>${_escapeXml(image.title)}</image:title>',
        );
      }
      sitemap.writeln('    </image:image>');
    }
    if (url.changefreq != null) {
      sitemap.writeln('    <changefreq>${url.changefreq}</changefreq>');
    }
    if (url.priority != null) {
      sitemap.writeln('    <priority>${url.priority}</priority>');
    }
    sitemap.writeln('  </url>');
  }
  sitemap.writeln('</urlset>');

  await File(pathJoin(buildDir.path, 'sitemap.xml'))
      .writeAsString(sitemap.toString());

  final robots = '''
User-agent: *
Allow: /

Disallow: /cuenta/
Disallow: /checkout
Disallow: /carrito
Disallow: /pedido/

Sitemap: $normalizedStoreUrl/sitemap.xml
''';

  await File(pathJoin(buildDir.path, 'robots.txt')).writeAsString(robots);
}

String? _routeForWebsitePage(Map<String, dynamic> page) {
  final slug = (page['slug'] ?? '').toString().trim();
  final isHome = page['is_home'] == true;
  if (isHome || slug == 'home' || slug == 'inicio') return '/';
  if (slug.isEmpty) return null;

  const directSlugs = <String>{
    'productos',
    'servicios',
    'contacto',
    'nosotros',
    'terminos',
    'privacidad',
    'devoluciones',
    'envios',
  };
  if (directSlugs.contains(slug)) return '/$slug';
  return '/pagina/${Uri.encodeComponent(slug)}';
}

DateTime? _parseDateTime(dynamic value) {
  final raw = (value ?? '').toString().trim();
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toUtc();
}

String _formatDate(DateTime value) {
  final utc = value.toUtc();
  final year = utc.year.toString().padLeft(4, '0');
  final month = utc.month.toString().padLeft(2, '0');
  final day = utc.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

String _joinUrl(String baseUrl, String path) {
  final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
  if (path.isEmpty || path == '/') return base;
  final p = path.startsWith('/') ? path : '/$path';
  return '$base$p';
}

String _escapeXml(String text) {
  return text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

class _SitemapUrl {
  final String loc;
  final DateTime lastmod;
  final String? changefreq;
  final String? priority;
  final List<_SitemapImage> images;

  const _SitemapUrl({
    required this.loc,
    required this.lastmod,
    this.changefreq,
    this.priority,
    this.images = const [],
  });
}

class _SitemapImage {
  final String loc;
  final String title;

  const _SitemapImage({
    required this.loc,
    required this.title,
  });
}

class _MutableProductCategorySeo {
  final String name;
  final String slug;
  final List<_CategoryProductSeo> products = [];

  _MutableProductCategorySeo({
    required this.name,
    required this.slug,
  });
}

class _ProductCategorySeo {
  final String name;
  final String slug;
  final List<_CategoryProductSeo> products;

  const _ProductCategorySeo({
    required this.name,
    required this.slug,
    required this.products,
  });

  int get productCount => products.length;
}

class _CategoryProductSeo {
  final String name;
  final String url;

  const _CategoryProductSeo({
    required this.name,
    required this.url,
  });
}

class _ProductRedirectAlias {
  const _ProductRedirectAlias({
    required this.productId,
    required this.aliasPath,
  });

  final String productId;
  final String aliasPath;
}

class _TrustPageFallback {
  final String title;
  final String description;
  final String body;

  const _TrustPageFallback({
    required this.title,
    required this.description,
    required this.body,
  });
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

String _buildLegacyProductRedirectHtml({
  required String html,
  required String canonicalUrl,
}) {
  final escapedUrl = _escapeHtml(canonicalUrl);
  final encodedUrl = jsonEncode(canonicalUrl);
  const closingHead = '</head>';
  final redirectMarkup = '''
  <meta http-equiv="refresh" content="0; url=$escapedUrl">
  <script>window.location.replace($encodedUrl);</script>
''';
  return html.replaceFirst(closingHead, '$redirectMarkup$closingHead');
}

List<_ProductRedirectAlias> _buildProductRedirectAliases({
  required List<Map<String, dynamic>> products,
  required List<Map<String, dynamic>> aliases,
  required Map<String, String> canonicalPathByProductId,
}) {
  final redirectsBySource = <String, _ProductRedirectAlias>{};

  void add(String productId, String aliasPath) {
    final canonicalPath = canonicalPathByProductId[productId];
    final normalizedAlias = _normalizePublicPath(aliasPath);
    if (canonicalPath == null ||
        normalizedAlias.isEmpty ||
        normalizedAlias == canonicalPath) {
      return;
    }
    redirectsBySource.putIfAbsent(
      normalizedAlias,
      () => _ProductRedirectAlias(
        productId: productId,
        aliasPath: normalizedAlias,
      ),
    );
  }

  for (final product in products) {
    final id = (product['id'] ?? '').toString().trim();
    if (id.isEmpty) continue;
    add(id, '/productos/$id');
    add(id, '/producto/$id');
    add(id, '/tienda/producto/$id');
  }

  for (final alias in aliases) {
    add(
      (alias['product_id'] ?? '').toString(),
      (alias['alias_path'] ?? '').toString(),
    );
  }

  final redirects = redirectsBySource.values.toList(growable: false);
  redirects.sort((a, b) => a.aliasPath.compareTo(b.aliasPath));
  return redirects;
}

Future<void> _writeRedirectSnapshot({
  required Directory buildDir,
  required String aliasPath,
  required String html,
  required String canonicalUrl,
}) async {
  final normalizedPath = _normalizePublicPath(aliasPath);
  if (normalizedPath.isEmpty || normalizedPath == '/') return;

  var outPath = buildDir.path;
  for (final rawSegment in normalizedPath.substring(1).split('/')) {
    final segment = Uri.decodeComponent(rawSegment);
    if (segment.isEmpty || segment == '.' || segment == '..') return;
    outPath = pathJoin(outPath, segment);
  }
  final outFile = File(outPath);
  outFile.parent.createSync(recursive: true);
  await outFile.writeAsString(
    _buildLegacyProductRedirectHtml(
      html: html,
      canonicalUrl: canonicalUrl,
    ),
  );
}

Future<int> _writeFirebaseProductRedirects({
  required File firebaseConfigFile,
  required File manifestFile,
  required List<_ProductRedirectAlias> redirects,
  required Map<String, String> canonicalPathByProductId,
}) async {
  if (!firebaseConfigFile.existsSync()) return 0;

  final generated = redirects
      .map((redirect) {
        // The old published product URLs used /productos/<uuid>. Keep
        // /producto/* and ERP-mounted aliases available through generated HTML
        // and the runtime alias resolver without consuming Firebase's finite
        // exact-redirect rule budget.
        if (!redirect.aliasPath.startsWith('/productos/')) return null;
        final destination = canonicalPathByProductId[redirect.productId];
        if (destination == null || destination == redirect.aliasPath) {
          return null;
        }
        return <String, dynamic>{
          'source': redirect.aliasPath,
          'destination': destination,
          'type': 301,
        };
      })
      .whereType<Map<String, dynamic>>()
      .toList(growable: false);

  final previousSources = <String>{};
  if (manifestFile.existsSync()) {
    try {
      final previous = jsonDecode(await manifestFile.readAsString());
      if (previous is Map && previous['redirects'] is List) {
        for (final item in previous['redirects'] as List) {
          if (item is Map && item['source'] != null) {
            previousSources.add(item['source'].toString());
          }
        }
      }
    } catch (_) {
      // A malformed generated manifest must not block a storefront build.
    }
  }

  final config = Map<String, dynamic>.from(
      jsonDecode(await firebaseConfigFile.readAsString()));
  final hosting = config['hosting'];
  if (hosting is! List) return 0;

  Map<String, dynamic>? storeHosting;
  for (final entry in hosting) {
    if (entry is Map && entry['target'] == 'store') {
      storeHosting = Map<String, dynamic>.from(entry);
      hosting[hosting.indexOf(entry)] = storeHosting;
      break;
    }
  }
  if (storeHosting == null) return 0;

  final retained = <Map<String, dynamic>>[];
  final existing = storeHosting['redirects'];
  if (existing is List) {
    for (final item in existing) {
      if (item is! Map) continue;
      final redirect = Map<String, dynamic>.from(item);
      if (!previousSources.contains(redirect['source']?.toString())) {
        retained.add(redirect);
      }
    }
  }
  storeHosting['redirects'] = [...retained, ...generated];

  const encoder = JsonEncoder.withIndent('  ');
  await firebaseConfigFile.writeAsString('${encoder.convert(config)}\n');
  manifestFile.parent.createSync(recursive: true);
  await manifestFile.writeAsString(
    '${encoder.convert({
          'generatedAt': DateTime.now().toUtc().toIso8601String(),
          'redirects': generated,
        })}\n',
  );
  return generated.length;
}

String _normalizePublicPath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  final path = Uri.tryParse(trimmed)?.path ?? trimmed;
  if (path.isEmpty) return '';
  return path == '/' ? '/' : '/${path.replaceAll(RegExp(r'^/+|/+$'), '')}';
}

String _replaceTag(String html, RegExp pattern, String replacement) {
  if (pattern.hasMatch(html)) return html.replaceAll(pattern, replacement);
  return html;
}

String _replaceMetaContent(String html,
    {required String name, required String content}) {
  final esc = _escapeHtml(content);
  final re = RegExp(
      r'<meta\s+name="' + RegExp.escape(name) + r'"\s+content="[^"]*"\s*/?>');
  if (re.hasMatch(html)) {
    return html.replaceAll(re, '<meta name="$name" content="$esc">');
  }
  return html;
}

String _replaceMetaName(String html,
    {required String name, required String content}) {
  final esc = _escapeHtml(content);
  final re = RegExp(
      r'<meta\s+name="' + RegExp.escape(name) + r'"\s+content="[^"]*"\s*/?>');
  if (re.hasMatch(html)) {
    return html.replaceAll(re, '<meta name="$name" content="$esc">');
  }
  return html;
}

String _replaceOrInsertMetaName(String html,
    {required String name, required String content}) {
  final esc = _escapeHtml(content);
  final re = RegExp(
      r'<meta\s+name="' + RegExp.escape(name) + r'"\s+content="[^"]*"\s*/?>');
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

String _replaceMetaProperty(String html,
    {required String property, required String content}) {
  final esc = _escapeHtml(content);
  final re = RegExp(r'<meta\s+property="' +
      RegExp.escape(property) +
      r'"\s+content="[^"]*"\s*/?>');
  if (re.hasMatch(html)) {
    return html.replaceAll(re, '<meta property="$property" content="$esc">');
  }
  return html;
}

String _replaceOrInsertMetaProperty(String html,
    {required String property, required String content}) {
  final esc = _escapeHtml(content);
  final re = RegExp(r'<meta\s+property="' +
      RegExp.escape(property) +
      r'"\s+content="[^"]*"\s*/?>');
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

String _replaceLinkHref(String html,
    {required String rel, required String href}) {
  final esc = _escapeHtml(href);
  final re =
      RegExp(r'<link\s+rel="' + RegExp.escape(rel) + r'"\s+href="[^"]*"\s*/?>');
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

    var key = line.substring(0, idx).trim();
    var value = line.substring(idx + 1).trim();

    if (key.startsWith('export ')) {
      key = key.substring('export '.length).trim();
    }

    if (key.isEmpty) continue;

    // Strip optional surrounding quotes.
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }

    out[key] = value;
  }

  return out;
}

String? _resolveEnvValue(String key, {required Map<String, String> env}) {
  final fromProcess = Platform.environment[key]?.trim();
  if (fromProcess != null && fromProcess.isNotEmpty) {
    return fromProcess;
  }

  final fromDotEnv = env[key]?.trim();
  if (fromDotEnv != null && fromDotEnv.isNotEmpty) {
    return fromDotEnv;
  }

  return null;
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
String pathJoin(String a, String b) {
  if (a.endsWith(Platform.pathSeparator)) return '$a$b';
  return '$a${Platform.pathSeparator}$b';
}
