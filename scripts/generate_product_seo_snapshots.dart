import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:vinabike_erp/modules/website/models/website_block_public_visibility.dart';
import 'package:vinabike_erp/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_erp/modules/website/models/website_seo_settings_aliases.dart';
import 'package:vinabike_erp/public_store/models/public_commerce_product_projection.dart';
import 'package:vinabike_erp/public_store/models/public_product_seo_copy.dart';

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
///   from the process environment (never printed).
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
///     --expected-store-url https://vinabike.cl
void main(List<String> args) async {
  late final Map<String, String> parsed;
  try {
    parsed = _parseArgs(args);
  } on FormatException catch (error) {
    stderr.writeln('❌ ${error.message}');
    exitCode = 2;
    return;
  }

  final buildDirPath = (parsed['build-dir'] ?? 'build/web_store').trim();
  final tenantId = parsed['tenant-id']?.trim();
  final publicationEvidencePath = parsed['publication-evidence-file']?.trim();
  if (parsed.containsKey('store-url')) {
    stderr.writeln(
      '❌ --store-url ya no es una fuente de verdad; usa '
      '--expected-store-url solo como guard de website_settings.store_url',
    );
    exitCode = 2;
    return;
  }
  final rawExpectedStoreUrl = (parsed['expected-store-url'] ?? '').trim();
  final expectedStoreUrl = rawExpectedStoreUrl.isEmpty
      ? ''
      : WebsiteSeoSettingsAliases.normalizeHttpsOrigin(rawExpectedStoreUrl);
  final productScope =
      (parsed['product-scope'] ?? 'published').trim().toLowerCase();
  final onlyMerchant = productScope == 'merchant';

  if (buildDirPath.isEmpty) {
    stderr.writeln('❌ --build-dir no puede estar vacío');
    exitCode = 2;
    return;
  }
  if (tenantId == null || tenantId.isEmpty) {
    stderr.writeln('❌ Missing --tenant-id');
    exitCode = 2;
    return;
  }
  if (!_uuidPattern.hasMatch(tenantId)) {
    stderr.writeln('❌ --tenant-id debe ser un UUID canónico');
    exitCode = 2;
    return;
  }
  if (productScope != 'published' && productScope != 'merchant') {
    stderr.writeln(
      '❌ --product-scope debe ser "published" o "merchant"',
    );
    exitCode = 2;
    return;
  }
  if (parsed.containsKey('publication-evidence-file') &&
      publicationEvidencePath!.isEmpty) {
    stderr.writeln('❌ --publication-evidence-file no puede estar vacío');
    exitCode = 2;
    return;
  }
  if (rawExpectedStoreUrl.isNotEmpty && expectedStoreUrl.isEmpty) {
    stderr.writeln(
      '❌ --expected-store-url debe ser un origen HTTPS público sin rutas ni parámetros',
    );
    exitCode = 2;
    return;
  }

  File? publicationEvidenceFile;
  if (publicationEvidencePath != null) {
    try {
      publicationEvidenceFile = prepareSeoPublicationEvidenceOutput(
        publicationEvidencePath,
      );
    } on Object catch (error) {
      stderr.writeln(
        '❌ No se puede preparar --publication-evidence-file: $error',
      );
      exitCode = 2;
      return;
    }
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

  final serviceRoleKey =
      Platform.environment['SUPABASE_SECRET_KEY']?.trim() ?? '';
  if (serviceRoleKey.isEmpty) {
    stderr.writeln(
      '❌ SUPABASE_SECRET_KEY not found in the process environment',
    );
    exitCode = 2;
    return;
  }

  final configuredSupabaseUrl = Platform.environment['SUPABASE_URL']?.trim();
  const approvedSupabaseUrl = 'https://xzdvtzdqjeyqxnkqprtf.supabase.co';
  final supabaseUrl = (configuredSupabaseUrl?.isNotEmpty == true
          ? configuredSupabaseUrl!
          : approvedSupabaseUrl)
      .replaceFirst(RegExp(r'/+$'), '');
  if (supabaseUrl != approvedSupabaseUrl) {
    stderr.writeln(
      '❌ SUPABASE_URL is not the approved production project for storefront snapshots',
    );
    exitCode = 2;
    return;
  }

  final baseIndexHtml = await baseIndexFile.readAsString();

  Future<SeoOwnerSourceSnapshot> readSeoOwnerSource() {
    return _readSeoOwnerSourceSnapshot(
      supabaseUrl: supabaseUrl,
      tenantId: tenantId,
      serviceRoleKey: serviceRoleKey,
    );
  }

  final seoOwnerSource = await fetchConsistentSeoOwnerSourceSnapshot(
    readOnce: readSeoOwnerSource,
  );
  final settings = seoOwnerSource.websiteSettings.values;

  final storeUrl = WebsiteSeoSettingsAliases.normalizeHttpsOrigin(
    _getSetting(settings, 'store_url') ?? '',
  );
  if (storeUrl.isEmpty) {
    stderr.writeln(
      '❌ website_settings.store_url debe contener el origen HTTPS canónico',
    );
    exitCode = 2;
    return;
  }
  if (expectedStoreUrl.isNotEmpty && expectedStoreUrl != storeUrl) {
    stderr.writeln(
      '❌ --expected-store-url no coincide con website_settings.store_url',
    );
    exitCode = 2;
    return;
  }

  final storeName = _cleanText(
    _getSetting(settings, 'seo_business_name') ??
        _getSetting(settings, 'store_name') ??
        '',
  );
  if (storeName.isEmpty) {
    stderr.writeln(
      '❌ website_settings.seo_business_name/store_name es obligatorio',
    );
    exitCode = 2;
    return;
  }
  final storeLocality = _getSetting(settings, 'seo_address_city') ??
      _getSetting(settings, 'seo_address_locality') ??
      '';
  final contactFacts = SeoContactFacts.fromSettings(settings);

  final titleTemplate = _getSetting(settings, 'seo_product_title_template') ??
      '{product_name} | $storeName';
  final descriptionTemplate =
      _getSetting(settings, 'seo_product_description_template') ??
          '{product_description}';

  // Redirect identity is owned by every published website product, regardless
  // of the optional snapshot scope. Loading the complete owner set once keeps
  // a Merchant-only diagnostic build from erasing redirects for ordinary
  // published products.
  final publishedProductOwners = seoOwnerSource.publishedProductOwners;
  final productCandidates = selectSeoSnapshotCandidatesForScope(
    publishedProducts: publishedProductOwners,
    onlyMerchant: onlyMerchant,
  );
  final publicAvailability = seoOwnerSource.publicAvailability;
  final products = productCandidates
      .where((product) =>
          publicAvailability.containsKey((product['id'] ?? '').toString()))
      .map((product) {
    final quantity = publicAvailability[(product['id'] ?? '').toString()]!;
    return <String, dynamic>{
      ...product,
      'stock_quantity': quantity,
      'inventory_qty': quantity,
    };
  }).toList(growable: false);
  final resolvedBrandNamesById = buildTenantSafeProductBrandNameMap(
    brandRows: seoOwnerSource.brandRows,
    tenantId: tenantId,
    requestedBrandIds: publishedProductOwners
        .map((product) => (product['brand_id'] ?? '').toString())
        .where((id) => id.trim().isNotEmpty),
  );
  final activeCategoryRows = seoOwnerSource.activeCategoryRows;
  final presentationRegistry = WebsiteCatalogPresentationRegistry.decode(
    settings[websiteCatalogPresentationsSettingKey],
  );
  final catalogPresentation = presentationRegistry.forCatalogRoot(
        WebsiteCatalogRoot.products,
      ) ??
      WebsiteCatalogPresentation.catalogRoot(WebsiteCatalogRoot.products);
  final catalogIndexable =
      catalogPresentation.allowIndexing && products.isNotEmpty;
  final categories = buildCanonicalCategorySeoProjections(
    products: products,
    activeCategories: activeCategoryRows,
    presentationRegistry: presentationRegistry,
    storeUrl: storeUrl,
    resolvedBrandNamesById: resolvedBrandNamesById,
  );
  final categoriesById = {
    for (final category in categories) category.categoryId: category,
  };
  final activeCategoryPathsById = buildActiveCategoryPathMap(
    activeCategories: activeCategoryRows,
  );
  final productUrlAliases = seoOwnerSource.productUrlAliases;
  final websiteContentSnapshot = seoOwnerSource.websiteContent;
  final pages = websiteContentSnapshot.pages;
  final pageBlocks = websiteContentSnapshot.pageBlocks;
  final dynamicCmsPages = buildPublishedDynamicCmsSeoProjections(
    pages: pages,
    pageBlocks: pageBlocks,
    storeUrl: storeUrl,
    storeName: storeName,
    globalDescription: _getSetting(settings, 'seo_meta_description') ??
        _getSetting(settings, 'meta_description') ??
        _getSetting(settings, 'store_description') ??
        '',
    globalKeywords: _getSetting(settings, 'seo_meta_keywords') ??
        _getSetting(settings, 'meta_keywords') ??
        '',
    globalImageUrl: _getSetting(settings, 'seo_og_image') ??
        _getSetting(settings, 'logo_url') ??
        '',
    contactFacts: contactFacts,
    settingsUpdatedAt: seoOwnerSource.websiteSettings.updatedAt,
  );
  final eligibleStaticTrustPagePaths = buildPublishedStaticTrustPagePaths(
    pages: pages,
    pageBlocks: pageBlocks,
  );
  final publicFallbackPaths = <String>{
    if (catalogIndexable) '/productos',
    ...eligibleStaticTrustPagePaths,
    ...dynamicCmsPages.map((page) => page.canonicalPath),
  };
  final baseHtml = _buildHomepageHtml(
    baseHtml: baseIndexHtml,
    storeUrl: storeUrl,
    storeName: storeName,
    globalTitle: _getSetting(settings, 'seo_meta_title') ??
        _getSetting(settings, 'meta_title') ??
        storeName,
    globalDescription: _getSetting(settings, 'seo_meta_description') ??
        _getSetting(settings, 'meta_description') ??
        _getSetting(settings, 'store_description') ??
        '',
    globalKeywords: _getSetting(settings, 'seo_meta_keywords') ??
        _getSetting(settings, 'meta_keywords') ??
        '',
    globalImageUrl: _getSetting(settings, 'seo_og_image') ??
        _getSetting(settings, 'logo_url') ??
        '',
    publicFallbackPaths: publicFallbackPaths,
  );
  await baseIndexFile.writeAsString(baseHtml);

  // Redirect identity follows owner publication, not transient catalog
  // availability. A product can leave the current snapshot/sitemap because it
  // is out of stock while its old indexed UUID must still 301 to the same
  // canonical product route.
  final canonicalPathByProductId = buildSeoProductCanonicalPathLedger(
    publishedProducts: publishedProductOwners,
  );
  final outDir = Directory(pathJoin(buildDir.path, 'productos'));
  // This directory is generated output. Recreate it so a product removed from
  // the current public visibility policy cannot survive as a stale soft-404
  // snapshot or sitemap destination from an earlier build.
  if (outDir.existsSync()) {
    outDir.deleteSync(recursive: true);
  }
  outDir.createSync(recursive: true);

  final productHtmlById = <String, String>{};
  var written = 0;
  for (final product in products) {
    final productCategoryId = (product['category_id'] ?? '').toString().trim();
    final canonicalCategory = categoriesById[productCategoryId];
    final commerce = projectSeoSnapshotCommerceProduct(
      product,
      resolvedBrandNamesById: resolvedBrandNamesById,
      categoryPath: activeCategoryPathsById[productCategoryId],
    );
    final id = commerce.id;
    if (id.isEmpty) continue;

    final productName = _cleanText(commerce.title);
    final productSku = commerce.sku;
    final productBrand = commerce.brand;
    final productCategory = commerce.categoryPath;
    final productSearchTerms = _stringList(product['website_search_terms']);
    final baseProductDescription = _cleanText(commerce.description);

    final priceNum = commerce.price > 0 ? commerce.price : null;
    final currency = commerce.currency;
    final inStock = commerce.availability == PublicCommerceAvailability.inStock;
    final imageUrls = commerce.imageUrls;
    final imageUrl = imageUrls.isEmpty ? '' : imageUrls.first;

    final productPath =
        canonicalPathByProductId[id] ?? _publicProductPath(product);
    final productUrl = _joinUrl(storeUrl, productPath);

    final seoTitleOverride =
        _cleanText((product['website_seo_title'] ?? '').toString());
    final seoDescriptionOverride =
        _cleanText((product['website_seo_description'] ?? '').toString());
    final seoCopy = resolvePublicProductSeoCopyFromInput(
      PublicProductSeoCopyInput(
        seoTitleOverride: seoTitleOverride,
        seoDescriptionOverride: seoDescriptionOverride,
        titleTemplate: titleTemplate,
        descriptionTemplate: descriptionTemplate,
        storeName: storeName,
        locality: storeLocality,
        searchTerms: productSearchTerms,
        product: PublicProductSeoProductInput(
          name: productName,
          sku: productSku,
          price: priceNum ?? 0,
          brand: productBrand,
          description: baseProductDescription,
          categoryPath: productCategory,
        ),
      ),
    );
    final fallbackSeoDescription = buildPublicProductSeoDescription(
      product: commerce,
      storeName: storeName,
    );
    final title = seoCopy.title;
    final description = seoCopy.description;

    final html = _buildProductHtml(
      baseHtml: baseHtml,
      title: title.isNotEmpty ? title : productName,
      description: description.isNotEmpty
          ? description
          : _truncate(fallbackSeoDescription, 320),
      canonicalUrl: productUrl,
      ogImageUrl: imageUrl,
      jsonLdProduct: _buildProductJsonLd(
        productUrl: productUrl,
        storeUrl: storeUrl,
        storeName: _cleanText(storeName),
        commerce: commerce,
        canonicalCategory: canonicalCategory,
      ),
      fallbackHtml: _buildProductFallbackHtml(
        title: productName,
        description: baseProductDescription.isNotEmpty
            ? baseProductDescription
            : fallbackSeoDescription,
        storeName: storeName,
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
    written++;
  }

  final redirectAliases = buildSeoProductRedirectAliases(
    products: publishedProductOwners,
    aliases: productUrlAliases,
    canonicalPathByProductId: canonicalPathByProductId,
  );
  final categoryRedirectAliases = buildCanonicalCategoryRouteAliasProjections(
    presentationRegistry: presentationRegistry,
    activeCategories: activeCategoryRows,
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
  final firebaseRedirectPlan = await _buildFirebaseStorefrontRedirectPlan(
    firebaseConfigFile: File(parsed['firebase-config'] ?? 'firebase.json'),
    manifestFile: File(
      parsed['redirect-manifest'] ?? 'scripts/generated_product_redirects.json',
    ),
    productRedirects: redirectAliases,
    categoryRedirects: categoryRedirectAliases,
    canonicalPathByProductId: canonicalPathByProductId,
    expectedPublicDirectory: buildDir.path,
  );

  final catalogUrl = _joinUrl(storeUrl, '/productos');
  final catalogTitle = catalogPresentation.seoTitle.trim().isNotEmpty
      ? catalogPresentation.seoTitle.trim()
      : 'Productos para bicicletas | $storeName'
          '${storeLocality.isEmpty ? '' : ' $storeLocality'}';
  final catalogDescription =
      catalogPresentation.seoDescription.trim().isNotEmpty
          ? catalogPresentation.seoDescription.trim()
          : 'Catálogo de productos publicados por $storeName con precios '
              'informados en CLP.';
  await File(pathJoin(outDir.path, 'index.html')).writeAsString(
    _buildCategoryHtml(
      baseHtml: baseHtml,
      title: catalogTitle,
      description: catalogDescription,
      canonicalUrl: catalogUrl,
      ogImageUrl: catalogPresentation.socialImageUrl,
      allowIndexing: catalogIndexable,
      jsonLd: _buildCatalogJsonLd(
        products: products,
        storeUrl: storeUrl,
        storeName: storeName,
        catalogUrl: catalogUrl,
        description: catalogDescription,
        resolvedBrandNamesById: resolvedBrandNamesById,
      ),
      fallbackHtml: _buildCatalogFallbackHtml(
        products: products,
        title: catalogTitle,
        description: catalogDescription,
      ),
    ),
  );
  final categoryOutDir = Directory(pathJoin(outDir.path, 'categoria'));
  categoryOutDir.createSync(recursive: true);
  var categoryPagesWritten = 0;
  var categoryAliasPagesWritten = 0;
  for (final category in categories) {
    final categoryUrl = _joinUrl(storeUrl, category.canonicalPath);
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
      ogImageUrl: category.socialImageUrl,
      allowIndexing: category.allowIndexing,
      jsonLd: _buildCategoryJsonLd(
        category: category,
        categoryUrl: categoryUrl,
        storeName: storeName,
      ),
      fallbackHtml: _buildCategoryFallbackHtml(
        title: category.displayTitle,
        description: _truncate(_cleanText(description), 320),
        storeName: storeName,
        category: category,
      ),
    );
    await File(pathJoin(categoryOutDir.path, category.slug))
        .writeAsString(html);
    categoryPagesWritten++;
  }
  for (final redirect in categoryRedirectAliases) {
    final categoryUrl = _joinUrl(storeUrl, redirect.canonicalPath);
    final title = '${redirect.name} | $storeName';
    final description = redirect.description.isNotEmpty
        ? redirect.description
        : 'Explora la colección ${redirect.name} de $storeName.';
    final aliasHtml = _buildCategoryHtml(
      baseHtml: baseHtml,
      title: _truncate(_cleanText(title), 120),
      description: _truncate(_cleanText(description), 320),
      canonicalUrl: categoryUrl,
      ogImageUrl: redirect.imageUrl,
      allowIndexing: false,
      jsonLd: jsonEncode({
        '@context': 'https://schema.org',
        '@type': 'WebPage',
        'name': redirect.name,
        'url': categoryUrl,
      }),
      fallbackHtml: '',
    );
    await _writeRedirectSnapshot(
      buildDir: buildDir,
      aliasPath: redirect.aliasPath,
      html: aliasHtml,
      canonicalUrl: categoryUrl,
    );
    categoryAliasPagesWritten++;
  }

  stdout.writeln('✅ Product SEO snapshots generated: $written');
  stdout.writeln('✅ Product alias snapshots generated: $aliasSnapshotsWritten');
  stdout.writeln('✅ Category SEO pages generated: $categoryPagesWritten');
  stdout.writeln(
      '✅ Category alias noindex snapshots generated: $categoryAliasPagesWritten');
  final staticTrustPagePaths = await _writeStaticTrustPages(
    buildDir: buildDir,
    baseHtml: baseHtml,
    storeUrl: storeUrl,
    storeName: storeName,
    settings: settings,
    pages: pages,
    pageBlocks: pageBlocks,
    availablePublicPaths: publicFallbackPaths,
  );
  stdout.writeln(
      '✅ Trust/policy SEO pages generated: ${staticTrustPagePaths.length}');
  final dynamicCmsPagesWritten = await _writeStaticDynamicCmsPages(
    buildDir: buildDir,
    baseHtml: baseHtml,
    storeUrl: storeUrl,
    storeName: storeName,
    pages: dynamicCmsPages,
    availablePublicPaths: publicFallbackPaths,
  );
  stdout.writeln('✅ Dynamic CMS SEO pages generated: $dynamicCmsPagesWritten');
  await _writeCrawlerFiles(
    buildDir: buildDir,
    storeUrl: storeUrl,
    products: products,
    categories: categories,
    websitePages: pages,
    websitePageBlocks: pageBlocks,
    dynamicCmsPages: dynamicCmsPages,
    staticTrustPagePaths: staticTrustPagePaths,
    productsCatalogIndexable: catalogIndexable,
    resolvedBrandNamesById: resolvedBrandNamesById,
    websiteSettingsUpdatedAt: seoOwnerSource.websiteSettings.updatedAt,
    brandRows: seoOwnerSource.brandRows,
    activeCategoryRows: activeCategoryRows,
  );
  stdout.writeln('✅ robots.txt and sitemap.xml generated');
  await validateGeneratedSeoArtifacts(
    buildDir: buildDir,
    storeUrl: storeUrl,
    staticTrustPagePaths: staticTrustPagePaths,
    expectedLocalBusinessIdentity:
        buildExpectedLocalBusinessIdentity(settings, storeUrl: storeUrl),
  );
  stdout.writeln('✅ Generated SEO artifact contract validated');
  await assertSeoOwnerSourceSnapshotIsCurrent(
    expected: seoOwnerSource,
    readOnce: readSeoOwnerSource,
  );
  stdout.writeln('✅ Complete SEO owner-source revision revalidated');
  if (publicationEvidenceFile != null) {
    await writeSeoPublicationEvidenceFile(
      outputFile: publicationEvidenceFile,
      ownerSourceSha256: seoOwnerSource.ownerSourceSha256,
      buildInputSha256: seoOwnerSource.buildInputSha256,
    );
    stdout.writeln(
      '✅ Deterministic publication evidence written to '
      '${publicationEvidenceFile.path}',
    );
  }
  await firebaseRedirectPlan.apply();
  stdout.writeln(
    '✅ Firebase storefront 301 redirects generated: '
    '${firebaseRedirectPlan.redirectCount}',
  );
}

// -----------------------------------------------------------------------------
// HTML mutation
// -----------------------------------------------------------------------------

String _buildHomepageHtml({
  required String baseHtml,
  required String storeUrl,
  required String storeName,
  required String globalTitle,
  required String globalDescription,
  required String globalKeywords,
  required String globalImageUrl,
  required Set<String> publicFallbackPaths,
}) {
  final title = _cleanText(globalTitle);
  final description = _cleanText(globalDescription);
  final keywords = _cleanText(globalKeywords);
  final imageUrl = _cleanText(globalImageUrl);
  var html = _rewriteHomepageFallbackLinks(
    baseHtml: baseHtml,
    publicPaths: publicFallbackPaths,
  );
  html = _replaceLinkHref(html, rel: 'canonical', href: storeUrl);
  html = _replaceOrInsertMetaName(
    html,
    name: 'robots',
    content: 'index,follow',
  );
  html = _replaceOrInsertMetaName(
    html,
    name: 'googlebot',
    content: 'index,follow',
  );

  final effectiveTitle = title.isNotEmpty ? _truncate(title, 120) : storeName;
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
  if (keywords.isNotEmpty) {
    html = _replaceOrInsertMetaName(
      html,
      name: 'keywords',
      content: keywords,
    );
  }
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
  if (imageUrl.isNotEmpty) {
    html = _replaceOrInsertMetaProperty(
      html,
      property: 'og:image',
      content: imageUrl,
    );
    html = _replaceOrInsertMetaName(
      html,
      name: 'twitter:image',
      content: imageUrl,
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

String buildHomepageSeoHtml({
  required String baseHtml,
  required String storeUrl,
  required String storeName,
  required String globalTitle,
  required String globalDescription,
  String globalKeywords = '',
  String globalImageUrl = '',
  Set<String> publicFallbackPaths = const {},
}) {
  return _buildHomepageHtml(
    baseHtml: baseHtml,
    storeUrl: storeUrl,
    storeName: storeName,
    globalTitle: globalTitle,
    globalDescription: globalDescription,
    globalKeywords: globalKeywords,
    globalImageUrl: globalImageUrl,
    publicFallbackPaths: publicFallbackPaths,
  );
}

String _rewriteHomepageFallbackLinks({
  required String baseHtml,
  required Set<String> publicPaths,
}) {
  final homepageMain = RegExp(
    r'<main class="storefront-nojs-fallback">.*?</main>',
    caseSensitive: false,
    dotAll: true,
  );
  final match = homepageMain.firstMatch(baseHtml);
  if (match == null) return baseHtml;

  var mainHtml = match.group(0)!;
  final primaryLinks = const <(String, String)>[
    ('/productos', 'Productos'),
    ('/servicios', 'Servicios'),
    ('/contacto', 'Contacto'),
  ]
      .where((entry) => publicPaths.contains(entry.$1))
      .map(
        (entry) =>
            '<a href="${_escapeHtml(entry.$1)}">${_escapeHtml(entry.$2)}</a>',
      )
      .join('\n          ');
  final legalLinks = _trustPageDefinitions()
      .entries
      .where((entry) => publicPaths.contains('/${entry.key}'))
      .map(
        (entry) => '<a href="/${_escapeHtml(entry.key)}">'
            '${_escapeHtml(entry.value.navLabel)}</a>',
      )
      .join('\n          ');

  mainHtml = mainHtml.replaceFirst(
    RegExp(
      r'<nav aria-label="Navegación principal">.*?</nav>',
      caseSensitive: false,
      dotAll: true,
    ),
    '<nav aria-label="Navegación principal">\n'
    '          $primaryLinks\n'
    '        </nav>',
  );
  mainHtml = mainHtml.replaceFirst(
    RegExp(
      r'<footer aria-label="Información legal">.*?</footer>',
      caseSensitive: false,
      dotAll: true,
    ),
    '<footer aria-label="Información legal">\n'
    '          $legalLinks\n'
    '        </footer>',
  );
  return baseHtml.replaceFirst(homepageMain, mainHtml);
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
  html = _replaceOrInsertMetaName(
    html,
    name: 'robots',
    content: 'index,follow',
  );
  html = _replaceOrInsertMetaName(
    html,
    name: 'googlebot',
    content: 'index,follow',
  );

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
    html = replaceStorefrontNoJsFallback(
      baseHtml: html,
      semanticMainHtml: fallbackHtml,
    );
  }

  return html;
}

String _buildCategoryHtml({
  required String baseHtml,
  required String title,
  required String description,
  required String canonicalUrl,
  required String ogImageUrl,
  required bool allowIndexing,
  required String jsonLd,
  required String fallbackHtml,
}) {
  var html = baseHtml;

  html = _replaceTag(html, RegExp(r'<title>.*?</title>', dotAll: true),
      '<title>${_escapeHtml(title)}</title>');

  html = _replaceMetaContent(html, name: 'title', content: title);
  html = _replaceMetaContent(html, name: 'description', content: description);
  html = _replaceLinkHref(html, rel: 'canonical', href: canonicalUrl);
  html = _replaceOrInsertMetaName(
    html,
    name: 'robots',
    content: allowIndexing ? 'index,follow' : 'noindex,follow',
  );
  html = _replaceOrInsertMetaName(
    html,
    name: 'googlebot',
    content: allowIndexing ? 'index,follow' : 'noindex,follow',
  );

  html = _replaceMetaProperty(html, property: 'og:type', content: 'website');
  html = _replaceMetaProperty(html, property: 'og:url', content: canonicalUrl);
  html = _replaceMetaProperty(html, property: 'og:title', content: title);
  html = _replaceMetaProperty(html,
      property: 'og:description', content: description);
  if (ogImageUrl.isNotEmpty) {
    html = _replaceOrInsertMetaProperty(
      html,
      property: 'og:image',
      content: ogImageUrl,
    );
    html = _replaceOrInsertMetaName(
      html,
      name: 'twitter:image',
      content: ogImageUrl,
    );
  } else {
    html = _removeMetaProperty(html, property: 'og:image');
    html = _removeMetaName(html, name: 'twitter:image');
  }

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
    html = replaceStorefrontNoJsFallback(
      baseHtml: html,
      semanticMainHtml: fallbackHtml,
    );
  }
  return html;
}

/// Replaces the homepage no-JavaScript document instead of appending a second
/// `<main>`/`<h1>` to every generated route.
///
/// `web/index.html` owns the single `<noscript>` shell and its base styles.
/// Route snapshots only replace that shell's semantic document. A minimal
/// standalone `<noscript>` is inserted for fixture/base files that do not yet
/// contain the storefront shell.
String replaceStorefrontNoJsFallback({
  required String baseHtml,
  required String semanticMainHtml,
}) {
  final normalizedMain = semanticMainHtml.trim();
  if (normalizedMain.isEmpty) return baseHtml;

  final homepageMain = RegExp(
    r'<main class="storefront-nojs-fallback">.*?</main>',
    dotAll: true,
  );
  if (homepageMain.hasMatch(baseHtml)) {
    return baseHtml.replaceFirst(homepageMain, normalizedMain);
  }

  final genericNoScriptMain = RegExp(
    r'<noscript\b[^>]*>\s*<main\b.*?</main>\s*</noscript>',
    caseSensitive: false,
    dotAll: true,
  );
  if (genericNoScriptMain.hasMatch(baseHtml)) {
    return baseHtml.replaceFirst(
      genericNoScriptMain,
      '<noscript id="storefront-nojs-fallback">\n'
      '    $normalizedMain\n'
      '  </noscript>',
    );
  }

  final noJsShellClose = RegExp(
    r'</noscript>',
    caseSensitive: false,
  );
  if (baseHtml.contains('id="storefront-nojs-fallback"') &&
      noJsShellClose.hasMatch(baseHtml)) {
    return baseHtml.replaceFirst(
      noJsShellClose,
      '$normalizedMain\n    </noscript>',
    );
  }

  final standaloneFallback = '''
  <noscript id="storefront-nojs-fallback">
    $normalizedMain
  </noscript>
''';
  return baseHtml.replaceFirst(
    RegExp(r'</body>', caseSensitive: false),
    '$standaloneFallback</body>',
  );
}

/// Static SEO facts for an editor-owned dynamic CMS page.
///
/// The same projection owns both file generation and sitemap eligibility so a
/// route cannot be advertised before it has meaningful crawlable content.
class SeoContactFacts {
  const SeoContactFacts({
    this.phone = '',
    this.email = '',
    this.address = '',
  });

  factory SeoContactFacts.fromSettings(Map<String, String> settings) {
    final addressParts = <String>[
      _getSetting(settings, 'seo_address_street') ??
          _getSetting(settings, 'contact_address') ??
          '',
      _getSetting(settings, 'seo_address_city') ??
          _getSetting(settings, 'seo_address_locality') ??
          '',
      _getSetting(settings, 'seo_address_region') ?? '',
      _getSetting(settings, 'seo_address_postal') ?? '',
      _getSetting(settings, 'seo_address_country') ?? '',
    ].map(_cleanText).where((part) => part.isNotEmpty);
    final uniqueAddressParts = <String>[];
    final seen = <String>{};
    for (final part in addressParts) {
      if (seen.add(part.toLowerCase())) uniqueAddressParts.add(part);
    }

    return SeoContactFacts(
      phone: _cleanText(
        _getSetting(settings, 'seo_phone') ??
            _getSetting(settings, 'contact_phone') ??
            _getSetting(settings, 'business_phone') ??
            '',
      ),
      email: _cleanText(
        _getSetting(settings, 'seo_email') ??
            _getSetting(settings, 'contact_email') ??
            '',
      ),
      address: uniqueAddressParts.join(', '),
    );
  }

  final String phone;
  final String email;
  final String address;

  bool get hasAny =>
      phone.trim().isNotEmpty ||
      email.trim().isNotEmpty ||
      address.trim().isNotEmpty;
}

/// Content eligibility shared behaviorally with the public Flutter pages.
///
/// Titles, labels, images, links and CTA copy are useful presentation, but they
/// do not constitute a crawlable page by themselves. Structured Features and
/// FAQ blocks must contain at least one real item; Contacto may additionally
/// rely on factual phone, email or address values from the canonical settings.
bool hasMeaningfulDynamicCmsPageContent({
  required String canonicalPath,
  required List<Map<String, dynamic>> blocks,
  SeoContactFacts contactFacts = const SeoContactFacts(),
}) {
  if (canonicalPath == '/contacto' && contactFacts.hasAny) return true;
  return blocks.any(_hasMeaningfulSeoBlockContent);
}

bool _hasMeaningfulSeoBlockContent(Map<String, dynamic> block) {
  if (!isWebsiteBlockVisibleOnAnyPublicBreakpoint(block)) return false;
  final type = (block['block_type'] ?? '').toString().trim().toLowerCase();
  final rawData = block['block_data'];
  if (rawData is! Map) return false;
  final data = Map<String, dynamic>.from(rawData);

  if (type == 'cta') return false;
  if (type == 'features') {
    final features = data['features'];
    if (features is! List) return false;
    return features.whereType<Map>().any((feature) {
      final item = Map<String, dynamic>.from(feature);
      return _cleanText((item['title'] ?? '').toString()).isNotEmpty ||
          _cleanText((item['description'] ?? '').toString()).isNotEmpty;
    });
  }
  if (type == 'faq') {
    final items = data['items'];
    if (items is! List) return false;
    return items.whereType<Map>().any((item) {
      final entry = Map<String, dynamic>.from(item);
      return _cleanText((entry['question'] ?? '').toString()).isNotEmpty &&
          _cleanText((entry['answer'] ?? '').toString()).isNotEmpty;
    });
  }
  if (type == 'contact') {
    return _hasFactualContactValue(data);
  }

  return _semanticBodyFragments(data).isNotEmpty;
}

bool _hasFactualContactValue(Map<String, dynamic> data) {
  const factualKeys = <String>{
    'address',
    'contactaddress',
    'email',
    'contactemail',
    'phone',
    'telephone',
    'contactphone',
    'whatsapp',
  };
  var found = false;

  void visit(dynamic value, {String? fieldName}) {
    if (found) return;
    if (value is Map) {
      for (final entry in value.entries) {
        visit(entry.value, fieldName: entry.key.toString());
      }
      return;
    }
    if (value is List) {
      for (final item in value) {
        visit(item, fieldName: fieldName);
      }
      return;
    }
    if (value is! String || fieldName == null) return;
    final normalizedField =
        fieldName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    found = factualKeys.contains(normalizedField) &&
        _cleanText(_policyText(value)).isNotEmpty;
  }

  visit(data);
  return found;
}

List<String> _semanticBodyFragments(Map<String, dynamic> data) {
  const semanticBodyKeys = <String>{
    'answer',
    'body',
    'caption',
    'comment',
    'content',
    'description',
    'detail',
    'details',
    'html',
    'quote',
    'richtext',
    'subtitle',
    'text',
  };
  final fragments = <String>[];
  final seen = <String>{};

  void collect(dynamic value, {String? fieldName}) {
    if (value is Map) {
      for (final entry in value.entries) {
        collect(entry.value, fieldName: entry.key.toString());
      }
      return;
    }
    if (value is List) {
      for (final item in value) {
        collect(item, fieldName: fieldName);
      }
      return;
    }
    if (value is! String || fieldName == null) return;
    final normalizedField =
        fieldName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (!semanticBodyKeys.contains(normalizedField)) return;
    final text = _cleanText(_policyText(value));
    if (text.isEmpty || !seen.add(text.toLowerCase())) return;
    fragments.add(text);
  }

  collect(data);
  return fragments;
}

class PublishedDynamicCmsSeoProjection {
  const PublishedDynamicCmsSeoProjection({
    required this.pageId,
    required this.canonicalPath,
    required this.pageTitle,
    required this.seoTitle,
    required this.description,
    required this.keywords,
    required this.ogImageUrl,
    required this.bodyHtml,
    required this.updatedAt,
  });

  final String pageId;
  final String canonicalPath;
  final String pageTitle;
  final String seoTitle;
  final String description;
  final String keywords;
  final String ogImageUrl;
  final String bodyHtml;
  final DateTime? updatedAt;
}

List<PublishedDynamicCmsSeoProjection> buildPublishedDynamicCmsSeoProjections({
  required List<Map<String, dynamic>> pages,
  required Map<String, List<Map<String, dynamic>>> pageBlocks,
  required String storeUrl,
  required String storeName,
  String globalDescription = '',
  String globalKeywords = '',
  String globalImageUrl = '',
  SeoContactFacts contactFacts = const SeoContactFacts(),
  DateTime? settingsUpdatedAt,
}) {
  final projections = <PublishedDynamicCmsSeoProjection>[];
  final effectiveStoreName = _cleanText(storeName);

  for (final page in pages) {
    if (page['is_published'] != true) continue;
    final canonicalPath = _routeForWebsitePage(page);
    if (canonicalPath == null ||
        canonicalPath == '/' ||
        canonicalPath == '/productos' ||
        websiteStaticTrustPageSlugs.contains(
          canonicalPath.replaceFirst(RegExp(r'^/'), ''),
        )) {
      continue;
    }

    final pageId = (page['id'] ?? '').toString().trim();
    if (pageId.isEmpty) continue;
    final blocks = pageBlocks[pageId] ?? const <Map<String, dynamic>>[];
    if (!hasMeaningfulDynamicCmsPageContent(
      canonicalPath: canonicalPath,
      blocks: blocks,
      contactFacts: contactFacts,
    )) {
      continue;
    }
    final bodyHtml = _renderDynamicCmsBlocks(
      blocks,
      canonicalPath: canonicalPath,
      contactFacts: contactFacts,
    );
    if (bodyHtml.trim().isEmpty) continue;

    final slug = (page['slug'] ?? '').toString().trim();
    final configuredPageTitle = _cleanText((page['title'] ?? '').toString());
    final pageTitle = configuredPageTitle.isNotEmpty
        ? configuredPageTitle
        : _humanizeCmsSlug(slug);
    final configuredSeoTitle =
        _cleanText((page['meta_title'] ?? '').toString());
    final seoTitle = configuredSeoTitle.isNotEmpty
        ? _truncate(configuredSeoTitle, 120)
        : _truncate(
            effectiveStoreName.isEmpty
                ? pageTitle
                : '$pageTitle | $effectiveStoreName',
            120,
          );

    final configuredDescription =
        _cleanText((page['meta_description'] ?? '').toString());
    final blockDescription = _dynamicCmsTextFragments(
      blocks,
      canonicalPath: canonicalPath,
      contactFacts: contactFacts,
    ).join(' ');
    final effectiveDescription = configuredDescription.isNotEmpty
        ? configuredDescription
        : blockDescription.isNotEmpty
            ? blockDescription
            : _cleanText(globalDescription).isNotEmpty
                ? _cleanText(globalDescription)
                : pageTitle;

    final configuredKeywords =
        _cleanText((page['meta_keywords'] ?? '').toString());
    final configuredImage = _cleanText((page['og_image_url'] ?? '').toString());
    projections.add(
      PublishedDynamicCmsSeoProjection(
        pageId: pageId,
        canonicalPath: canonicalPath,
        pageTitle: _truncate(pageTitle, 120),
        seoTitle: seoTitle,
        description: _truncate(effectiveDescription, 320),
        keywords: configuredKeywords.isNotEmpty
            ? configuredKeywords
            : _cleanText(globalKeywords),
        ogImageUrl: configuredImage.isNotEmpty
            ? configuredImage
            : _cleanText(globalImageUrl),
        bodyHtml: bodyHtml,
        updatedAt: maxFactualSeoUpdatedAt([
          settingsUpdatedAt,
          _parseDateTime(page['updated_at']),
          ...blocks
              .where(isWebsiteBlockVisibleOnAnyPublicBreakpoint)
              .map((block) => _parseDateTime(block['updated_at'])),
        ]),
      ),
    );
  }

  projections.sort(
    (a, b) => a.canonicalPath.compareTo(b.canonicalPath),
  );
  return List.unmodifiable(projections);
}

Future<int> _writeStaticDynamicCmsPages({
  required Directory buildDir,
  required String baseHtml,
  required String storeUrl,
  required String storeName,
  required List<PublishedDynamicCmsSeoProjection> pages,
  required Set<String> availablePublicPaths,
}) async {
  final outputDirectory = Directory(pathJoin(buildDir.path, 'pagina'));
  if (outputDirectory.existsSync()) {
    outputDirectory.deleteSync(recursive: true);
  }
  for (final slug in websiteDynamicDirectPageSlugs) {
    final outputFile = File(pathJoin(buildDir.path, slug));
    if (outputFile.existsSync()) outputFile.deleteSync();
  }
  if (pages.any((page) => page.canonicalPath.startsWith('/pagina/'))) {
    outputDirectory.createSync(recursive: true);
  }

  var written = 0;
  final writtenPaths = <String>{};
  for (final page in pages) {
    final html = buildStaticCmsPageSnapshotHtml(
      baseHtml: baseHtml,
      storeUrl: storeUrl,
      storeName: storeName,
      page: page,
      availablePublicPaths: availablePublicPaths,
    );
    var outputPath = buildDir.path;
    for (final segment in page.canonicalPath.substring(1).split('/')) {
      outputPath = pathJoin(outputPath, segment);
    }
    final outputFile = File(outputPath);
    outputFile.parent.createSync(recursive: true);
    await outputFile.writeAsString(html);
    writtenPaths.add(page.canonicalPath);
    written++;
  }
  for (final slug in websiteDynamicDirectPageSlugs) {
    final canonicalPath = '/$slug';
    if (writtenPaths.contains(canonicalPath)) continue;
    await File(pathJoin(buildDir.path, slug)).writeAsString(
      buildUnavailableStaticCmsPageSnapshotHtml(
        baseHtml: baseHtml,
        storeUrl: storeUrl,
        storeName: storeName,
        canonicalPath: canonicalPath,
        pageTitle: slug == 'servicios' ? 'Servicios' : 'Contacto',
      ),
    );
    written++;
  }
  return written;
}

String buildStaticCmsPageSnapshotHtml({
  required String baseHtml,
  required String storeUrl,
  required String storeName,
  required PublishedDynamicCmsSeoProjection page,
  required Set<String> availablePublicPaths,
}) {
  final canonicalUrl = _joinUrl(storeUrl, page.canonicalPath);
  final bodyHtml = '''
  <main id="seo-static-page" class="storefront-nojs-fallback">
    <div class="seo-static-shell">
      <header>
        <p class="seo-eyebrow"><a href="/">${_escapeHtml(storeName)}</a></p>
        <h1>${_escapeHtml(page.pageTitle)}</h1>
        <p>${_escapeHtml(page.description)}</p>
      </header>
      ${page.bodyHtml}
      <nav class="seo-page-nav" aria-label="Navegación de la tienda">
        <a href="/">Inicio</a>
        ${_dynamicPageNavigationLinks(availablePublicPaths)}
      </nav>
    </div>
  </main>
''';
  final jsonLd = jsonEncode({
    '@context': 'https://schema.org',
    '@type': 'WebPage',
    'name': page.pageTitle,
    'headline': page.seoTitle,
    'description': page.description,
    'url': canonicalUrl,
    'isPartOf': {
      '@type': 'WebSite',
      'name': storeName,
      'url': storeUrl.replaceAll(RegExp(r'/+$'), ''),
    },
    if (page.ogImageUrl.isNotEmpty)
      'primaryImageOfPage': {
        '@type': 'ImageObject',
        'url': page.ogImageUrl,
      },
  });
  return _buildStaticTrustPageHtml(
    baseHtml: baseHtml,
    title: page.seoTitle,
    description: page.description,
    keywords: page.keywords,
    canonicalUrl: canonicalUrl,
    ogImageUrl: page.ogImageUrl,
    bodyHtml: bodyHtml,
    jsonLd: jsonLd,
    jsonLdElementId: 'seo-cms-page-jsonld',
    jsonLdLabel: 'CMS Page',
  );
}

String buildUnavailableStaticCmsPageSnapshotHtml({
  required String baseHtml,
  required String storeUrl,
  required String storeName,
  required String canonicalPath,
  required String pageTitle,
}) {
  final canonicalUrl = _joinUrl(storeUrl, canonicalPath);
  const description =
      'Esta sección no tiene una publicación pública disponible en este momento.';
  final bodyHtml = '''
  <main id="seo-static-page" class="storefront-nojs-fallback">
    <div class="seo-static-shell">
      <header>
        <p class="seo-eyebrow"><a href="/">${_escapeHtml(storeName)}</a></p>
        <h1>${_escapeHtml(pageTitle)}</h1>
        <p>$description</p>
      </header>
      <nav class="seo-page-nav" aria-label="Navegación de la tienda">
        <a href="/">Volver al inicio</a>
      </nav>
    </div>
  </main>
''';

  return _buildStaticTrustPageHtml(
    baseHtml: baseHtml,
    title: _truncate('$pageTitle | $storeName', 120),
    description: description,
    keywords: '',
    canonicalUrl: canonicalUrl,
    ogImageUrl: '',
    bodyHtml: bodyHtml,
    jsonLd: '',
    allowIndexing: false,
    jsonLdElementId: 'seo-unavailable-page-jsonld',
    jsonLdLabel: 'Unavailable Page',
  );
}

String _dynamicPageNavigationLinks(Set<String> availablePublicPaths) {
  return const <(String, String)>[
    ('/productos', 'Productos'),
    ('/servicios', 'Servicios'),
    ('/contacto', 'Contacto'),
  ]
      .where((entry) => availablePublicPaths.contains(entry.$1))
      .map(
        (entry) =>
            '<a href="${_escapeHtml(entry.$1)}">${_escapeHtml(entry.$2)}</a>',
      )
      .join('\n        ');
}

String _renderDynamicCmsBlocks(
  List<Map<String, dynamic>> blocks, {
  required String canonicalPath,
  required SeoContactFacts contactFacts,
}) {
  final visible = blocks
      .where(isWebsiteBlockVisibleOnAnyPublicBreakpoint)
      .toList(growable: false);
  visible.sort((a, b) =>
      (_toInt(a['order_index']) ?? 0).compareTo(_toInt(b['order_index']) ?? 0));

  final output = StringBuffer();
  for (final block in visible) {
    if (!_hasMeaningfulSeoBlockContent(block)) continue;
    final type = (block['block_type'] ?? '').toString().trim().toLowerCase();
    final data = block['block_data'] is Map
        ? Map<String, dynamic>.from(block['block_data'] as Map)
        : const <String, dynamic>{};
    final configuredHeading = _cleanText(
      (data['title'] ?? data['headline'] ?? data['heading'] ?? '').toString(),
    );

    if (type == 'features') {
      final items = (data['features'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) =>
              _cleanText((item['title'] ?? '').toString()).isNotEmpty ||
              _cleanText((item['description'] ?? '').toString()).isNotEmpty)
          .toList(growable: false);
      if (items.isEmpty) continue;
      output.writeln('<section>');
      if (configuredHeading.isNotEmpty) {
        output.writeln('<h2>${_escapeHtml(configuredHeading)}</h2>');
      }
      output.writeln('<ul>');
      for (final item in items) {
        final title = _cleanText((item['title'] ?? '').toString());
        final description = _cleanText((item['description'] ?? '').toString());
        output.writeln('<li>');
        if (title.isNotEmpty) {
          output.writeln('<strong>${_escapeHtml(title)}</strong>');
        }
        if (description.isNotEmpty) {
          output.writeln('<p>${_escapeHtml(description)}</p>');
        }
        output.writeln('</li>');
      }
      output
        ..writeln('</ul>')
        ..writeln('</section>');
      continue;
    }

    if (type == 'faq') {
      final items = (data['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) =>
              _cleanText((item['question'] ?? '').toString()).isNotEmpty &&
              _cleanText((item['answer'] ?? '').toString()).isNotEmpty)
          .toList(growable: false);
      if (items.isEmpty) continue;
      output.writeln('<section>');
      if (configuredHeading.isNotEmpty) {
        output.writeln('<h2>${_escapeHtml(configuredHeading)}</h2>');
      }
      output.writeln('<dl>');
      for (final item in items) {
        output
          ..writeln(
            '<dt>${_escapeHtml(_cleanText((item['question'] ?? '').toString()))}</dt>',
          )
          ..writeln(
            '<dd>${_escapeHtml(_cleanText((item['answer'] ?? '').toString()))}</dd>',
          );
      }
      output
        ..writeln('</dl>')
        ..writeln('</section>');
      continue;
    }

    final fragments = type == 'contact'
        ? _contactFactStringsFromData(data)
        : _semanticBodyFragments(data);
    if (fragments.isEmpty) continue;
    final heading =
        configuredHeading.isNotEmpty ? configuredHeading : fragments.first;
    output.writeln('<section>');
    if (heading.isNotEmpty) {
      output.writeln('<h2>${_escapeHtml(heading)}</h2>');
    }
    for (final paragraph in fragments) {
      if (paragraph.toLowerCase() == heading.toLowerCase()) continue;
      output.writeln('<p>${_escapeHtml(paragraph)}</p>');
    }
    output.writeln('</section>');
  }

  if (canonicalPath == '/contacto' && contactFacts.hasAny) {
    output
      ..writeln('<section>')
      ..writeln('<h2>Información de contacto</h2>')
      ..writeln('<address>');
    if (contactFacts.address.isNotEmpty) {
      output.writeln(
        '<p>Dirección: ${_escapeHtml(contactFacts.address)}</p>',
      );
    }
    if (contactFacts.phone.isNotEmpty) {
      output.writeln(
        '<p>Teléfono: ${_escapeHtml(contactFacts.phone)}</p>',
      );
    }
    if (contactFacts.email.isNotEmpty) {
      output.writeln(
        '<p>Email: ${_escapeHtml(contactFacts.email)}</p>',
      );
    }
    output
      ..writeln('</address>')
      ..writeln('</section>');
  }
  return output.toString();
}

List<String> _dynamicCmsTextFragments(
  List<Map<String, dynamic>> blocks, {
  required String canonicalPath,
  required SeoContactFacts contactFacts,
}) {
  final fragments = <String>[];
  final seen = <String>{};
  for (final block in blocks) {
    if (!isWebsiteBlockVisibleOnAnyPublicBreakpoint(block)) continue;
    for (final fragment in _dynamicCmsBlockTextFragments(block)) {
      if (seen.add(fragment.toLowerCase())) fragments.add(fragment);
    }
  }
  if (canonicalPath == '/contacto') {
    for (final fact in [
      contactFacts.address,
      contactFacts.phone,
      contactFacts.email,
    ]) {
      if (fact.isNotEmpty && seen.add(fact.toLowerCase())) {
        fragments.add(fact);
      }
    }
  }
  return fragments;
}

List<String> _dynamicCmsBlockTextFragments(
  Map<String, dynamic> block,
) {
  if (!_hasMeaningfulSeoBlockContent(block)) return const [];
  final type = (block['block_type'] ?? '').toString().trim().toLowerCase();
  final rawData = block['block_data'];
  if (rawData is! Map) return const [];
  final data = Map<String, dynamic>.from(rawData);

  if (type == 'features') {
    return (data['features'] as List? ?? const [])
        .whereType<Map>()
        .expand((rawItem) {
      final item = Map<String, dynamic>.from(rawItem);
      return [
        _cleanText((item['title'] ?? '').toString()),
        _cleanText((item['description'] ?? '').toString()),
      ].where((text) => text.isNotEmpty);
    }).toList(growable: false);
  }
  if (type == 'faq') {
    return (data['items'] as List? ?? const [])
        .whereType<Map>()
        .expand((rawItem) {
      final item = Map<String, dynamic>.from(rawItem);
      final question = _cleanText((item['question'] ?? '').toString());
      final answer = _cleanText((item['answer'] ?? '').toString());
      return question.isEmpty || answer.isEmpty
          ? const <String>[]
          : <String>[question, answer];
    }).toList(growable: false);
  }
  if (type == 'contact') return _contactFactStringsFromData(data);
  final bodyFragments = _semanticBodyFragments(data);
  if (bodyFragments.isEmpty) return const [];
  final heading = _cleanText(
    (data['title'] ?? data['headline'] ?? data['heading'] ?? '').toString(),
  );
  return [
    if (heading.isNotEmpty) heading,
    ...bodyFragments,
  ];
}

List<String> _contactFactStringsFromData(Map<String, dynamic> data) {
  const factualKeys = <String>{
    'address',
    'contactaddress',
    'email',
    'contactemail',
    'phone',
    'telephone',
    'contactphone',
    'whatsapp',
  };
  final facts = <String>[];
  final seen = <String>{};

  void visit(dynamic value, {String? fieldName}) {
    if (value is Map) {
      for (final entry in value.entries) {
        visit(entry.value, fieldName: entry.key.toString());
      }
      return;
    }
    if (value is List) {
      for (final item in value) {
        visit(item, fieldName: fieldName);
      }
      return;
    }
    if (value is! String || fieldName == null) return;
    final normalizedField =
        fieldName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (!factualKeys.contains(normalizedField)) return;
    final fact = _cleanText(_policyText(value));
    if (fact.isNotEmpty && seen.add(fact.toLowerCase())) facts.add(fact);
  }

  visit(data);
  return facts;
}

String _humanizeCmsSlug(String slug) {
  final normalized = _cleanText(
    slug.replaceAll(RegExp(r'[-_]+'), ' ').replaceAll(RegExp(r'\s+'), ' '),
  );
  if (normalized.isEmpty) return 'Página';
  return '${normalized[0].toUpperCase()}${normalized.substring(1)}';
}

const websiteStaticTrustPageSlugs = <String>{
  'nosotros',
  'terminos',
  'privacidad',
  'devoluciones',
  'envios',
};

const websiteDynamicDirectPageSlugs = <String>{
  'servicios',
  'contacto',
};

/// Returns only editor-owned trust routes that are currently published.
///
/// Publication and meaningful visible content are both required. A missing
/// block projection cannot become indexable through generated fallback copy.
Set<String> buildPublishedStaticTrustPagePaths({
  required List<Map<String, dynamic>> pages,
  required Map<String, List<Map<String, dynamic>>> pageBlocks,
}) {
  return Set.unmodifiable({
    for (final page in pages)
      if (_isIndexableStaticTrustPage(page, pageBlocks))
        '/${(page['slug'] ?? '').toString().trim()}',
  });
}

bool hasMeaningfulStaticTrustPageContent(
  List<Map<String, dynamic>> blocks,
) {
  return _renderTrustBlocks(blocks).trim().isNotEmpty;
}

bool _isIndexableStaticTrustPage(
  Map<String, dynamic> page,
  Map<String, List<Map<String, dynamic>>> pageBlocks,
) {
  final slug = (page['slug'] ?? '').toString().trim();
  final pageId = (page['id'] ?? '').toString().trim();
  return page['is_published'] == true &&
      websiteStaticTrustPageSlugs.contains(slug) &&
      pageId.isNotEmpty &&
      hasMeaningfulStaticTrustPageContent(
        pageBlocks[pageId] ?? const <Map<String, dynamic>>[],
      );
}

Future<Set<String>> _writeStaticTrustPages({
  required Directory buildDir,
  required String baseHtml,
  required String storeUrl,
  required String storeName,
  required Map<String, String> settings,
  required List<Map<String, dynamic>> pages,
  required Map<String, List<Map<String, dynamic>>> pageBlocks,
  required Set<String> availablePublicPaths,
}) async {
  final definitions = _trustPageDefinitions();
  final publishedPaths = buildPublishedStaticTrustPagePaths(
    pages: pages,
    pageBlocks: pageBlocks,
  );

  for (final entry in definitions.entries) {
    final slug = entry.key;
    final page = _findPageBySlug(pages, slug);
    final blocks = page == null
        ? const <Map<String, dynamic>>[]
        : pageBlocks[(page['id'] ?? '').toString()] ??
            const <Map<String, dynamic>>[];
    final html = buildStaticTrustPageSnapshotHtml(
      baseHtml: baseHtml,
      slug: slug,
      storeUrl: storeUrl,
      storeName: storeName,
      settings: settings,
      page: page,
      blocks: blocks,
      publishedPaths: publishedPaths,
      availablePublicPaths: availablePublicPaths,
    );

    await File(pathJoin(buildDir.path, slug)).writeAsString(html);
  }

  return publishedPaths;
}

String buildStaticTrustPageSnapshotHtml({
  required String baseHtml,
  required String slug,
  required String storeUrl,
  required String storeName,
  required Map<String, String> settings,
  required Map<String, dynamic>? page,
  required List<Map<String, dynamic>> blocks,
  required Set<String> publishedPaths,
  required Set<String> availablePublicPaths,
}) {
  final definition = _trustPageDefinitions()[slug];
  if (definition == null) {
    throw ArgumentError.value(slug, 'slug', 'No es una ruta legal conocida.');
  }
  final allowIndexing = publishedPaths.contains('/$slug') &&
      page?['is_published'] == true &&
      hasMeaningfulStaticTrustPageContent(blocks);
  final configuredPageTitle = _cleanText((page?['title'] ?? '').toString());
  final pageTitle = allowIndexing && configuredPageTitle.isNotEmpty
      ? configuredPageTitle
      : definition.title;
  final configuredTitle = _cleanText((page?['meta_title'] ?? '').toString());
  final seoTitle = allowIndexing && configuredTitle.isNotEmpty
      ? _truncate(configuredTitle, 120)
      : _truncate('$pageTitle | $storeName', 120);
  final descriptionFromPage =
      _cleanText((page?['meta_description'] ?? '').toString());
  final ownerContentSummary = _cleanText(_renderTrustBlocks(blocks));
  final description = _truncate(
    !allowIndexing
        ? 'Esta página no tiene contenido público disponible en este momento.'
        : descriptionFromPage.isNotEmpty
            ? descriptionFromPage
            : ownerContentSummary,
    320,
  );
  final configuredKeywords =
      _cleanText((page?['meta_keywords'] ?? '').toString());
  final keywords = allowIndexing && configuredKeywords.isNotEmpty
      ? configuredKeywords
      : allowIndexing
          ? _getSetting(settings, 'seo_meta_keywords') ??
              _getSetting(settings, 'meta_keywords') ??
              ''
          : '';
  final configuredImage = _cleanText((page?['og_image_url'] ?? '').toString());
  final ogImageUrl = allowIndexing && configuredImage.isNotEmpty
      ? configuredImage
      : allowIndexing
          ? _getSetting(settings, 'seo_og_image') ??
              _getSetting(settings, 'logo_url') ??
              ''
          : '';
  final canonicalUrl = _joinUrl(storeUrl, '/$slug');
  final bodyHtml = _buildStaticTrustPageBody(
    title: pageTitle,
    description: description,
    blocks: blocks,
    storeName: storeName,
    allowIndexing: allowIndexing,
    publishedPaths: publishedPaths,
    availablePublicPaths: availablePublicPaths,
  );

  return _buildStaticTrustPageHtml(
    baseHtml: baseHtml,
    title: seoTitle,
    description: description,
    keywords: keywords,
    canonicalUrl: canonicalUrl,
    ogImageUrl: ogImageUrl,
    bodyHtml: bodyHtml,
    jsonLd: _buildStaticTrustPageJsonLd(
      slug: slug,
      title: pageTitle,
      description: description,
      pageUrl: canonicalUrl,
      storeUrl: storeUrl,
      storeName: storeName,
    ),
    allowIndexing: allowIndexing,
  );
}

String _buildStaticTrustPageHtml({
  required String baseHtml,
  required String title,
  required String description,
  required String keywords,
  required String canonicalUrl,
  required String ogImageUrl,
  required String bodyHtml,
  required String jsonLd,
  bool allowIndexing = true,
  String jsonLdElementId = 'seo-trust-page-jsonld',
  String jsonLdLabel = 'Trust Page',
}) {
  var html = baseHtml;

  html = _replaceTag(html, RegExp(r'<title>.*?</title>', dotAll: true),
      '<title>${_escapeHtml(title)}</title>');
  html = _replaceMetaContent(html, name: 'title', content: title);
  html = _replaceOrInsertMetaName(
    html,
    name: 'description',
    content: description,
  );
  if (keywords.isNotEmpty) {
    html = _replaceOrInsertMetaName(
      html,
      name: 'keywords',
      content: keywords,
    );
  }
  html = _replaceLinkHref(html, rel: 'canonical', href: canonicalUrl);
  html = _replaceOrInsertMetaName(
    html,
    name: 'robots',
    content: allowIndexing ? 'index,follow' : 'noindex,follow',
  );
  html = _replaceOrInsertMetaName(
    html,
    name: 'googlebot',
    content: allowIndexing ? 'index,follow' : 'noindex,follow',
  );
  html = _replaceMetaProperty(html, property: 'og:type', content: 'website');
  html = _replaceMetaProperty(html, property: 'og:url', content: canonicalUrl);
  html = _replaceMetaProperty(html, property: 'og:title', content: title);
  html = _replaceMetaProperty(html,
      property: 'og:description', content: description);
  if (ogImageUrl.isNotEmpty) {
    html = _replaceOrInsertMetaProperty(
      html,
      property: 'og:image',
      content: ogImageUrl,
    );
    html = _replaceOrInsertMetaName(
      html,
      name: 'twitter:image',
      content: ogImageUrl,
    );
  } else {
    html = _removeMetaProperty(html, property: 'og:image');
    html = _removeMetaName(html, name: 'twitter:image');
  }
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

  final injection = jsonLd.trim().isEmpty
      ? ''
      : '\n  <!-- JSON-LD Structured Data for $jsonLdLabel (generated at deploy) -->\n'
          '  <script type="application/ld+json" id="$jsonLdElementId">\n'
          '  $jsonLd\n'
          '  </script>\n';

  html = html.replaceFirst(RegExp(r'</head>'), '$style$injection</head>');
  return replaceStorefrontNoJsFallback(
    baseHtml: html,
    semanticMainHtml: bodyHtml,
  );
}

String _buildStaticTrustPageBody({
  required String title,
  required String description,
  required List<Map<String, dynamic>> blocks,
  required String storeName,
  required bool allowIndexing,
  required Set<String> publishedPaths,
  required Set<String> availablePublicPaths,
}) {
  final content = _renderTrustBlocks(blocks);
  final renderedContent = allowIndexing
      ? content
      : '''
      <section>
        <h2>Contenido no publicado</h2>
        <p>La tienda todavía no ha publicado información para esta página.</p>
      </section>
''';
  final policyLinks = _trustPageDefinitions()
      .entries
      .where((entry) => publishedPaths.contains('/${entry.key}'))
      .map(
        (entry) => '<a href="/${_escapeHtml(entry.key)}">'
            '${_escapeHtml(entry.value.navLabel)}</a>',
      )
      .join('\n        ');

  return '''
  <main id="seo-static-page" class="storefront-nojs-fallback">
    <div class="seo-static-shell">
      <header>
        <p class="seo-eyebrow"><a href="/">${_escapeHtml(storeName)}</a></p>
        <h1>${_escapeHtml(title)}</h1>
        <p>${_escapeHtml(description)}</p>
      </header>
      $renderedContent
      <nav class="seo-page-nav" aria-label="Información de la tienda">
        <a href="/">Inicio</a>
        ${availablePublicPaths.contains('/productos') ? '<a href="/productos">Productos</a>' : ''}
        $policyLinks
      </nav>
    </div>
  </main>
''';
}

String _renderTrustBlocks(List<Map<String, dynamic>> blocks) {
  final visible = blocks
      .where(isWebsiteBlockVisibleOnAnyPublicBreakpoint)
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
      final body = type == 'contact'
          ? _contactFactStringsFromData(data)
          : <String>[
              if (content.isNotEmpty) content,
              if (content.isEmpty && subtitle.isNotEmpty) subtitle,
            ];
      if (body.isEmpty) continue;
      out.writeln('<section>');
      if (title.isNotEmpty) out.writeln('<h2>${_escapeHtml(title)}</h2>');
      for (final paragraph in body) {
        out.writeln(_paragraphsHtml(paragraph));
      }
      out.writeln('</section>');
      continue;
    }

    if (type == 'features') {
      final features = data['features'];
      if (features is! List || features.isEmpty) continue;
      final meaningfulFeatures = features
          .whereType<Map>()
          .map((feature) => Map<String, dynamic>.from(feature))
          .where((item) =>
              _policyText(item['title']).isNotEmpty ||
              _policyText(item['description']).isNotEmpty)
          .toList(growable: false);
      if (meaningfulFeatures.isEmpty) continue;
      out.writeln('<section>');
      if (title.isNotEmpty) out.writeln('<h2>${_escapeHtml(title)}</h2>');
      out.writeln('<ul>');
      for (final item in meaningfulFeatures) {
        final itemTitle = _policyText(item['title']);
        final itemDescription = _policyText(item['description']);
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
      final meaningfulItems = items
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) =>
              _policyText(item['question']).isNotEmpty &&
              _policyText(item['answer']).isNotEmpty)
          .toList(growable: false);
      if (meaningfulItems.isEmpty) continue;
      out.writeln('<section>');
      if (title.isNotEmpty) out.writeln('<h2>${_escapeHtml(title)}</h2>');
      out.writeln('<dl>');
      for (final map in meaningfulItems) {
        final question = _policyText(map['question']);
        final answer = _policyText(map['answer']);
        out.writeln('<dt>${_escapeHtml(question)}</dt>');
        out.writeln('<dd>${_escapeHtml(answer)}</dd>');
      }
      out.writeln('</dl>');
      out.writeln('</section>');
      continue;
    }

    final body = <String>[
      if (subtitle.isNotEmpty) subtitle,
      if (content.isNotEmpty) content,
    ];
    if (body.isNotEmpty) {
      out.writeln('<section>');
      if (title.isNotEmpty) out.writeln('<h2>${_escapeHtml(title)}</h2>');
      for (final paragraph in body) {
        out.writeln(_paragraphsHtml(paragraph));
      }
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
}) {
  final pageType = switch (slug) {
    'contacto' => 'ContactPage',
    'nosotros' => 'AboutPage',
    _ => 'WebPage',
  };

  final data = <String, dynamic>{
    '@context': 'https://schema.org',
    '@type': pageType,
    'name': title,
    'description': description,
    'url': pageUrl,
    'isPartOf': {
      '@type': 'WebSite',
      'name': storeName,
      'url': storeUrl,
    },
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
  return (value ?? '').toString().replaceAll(RegExp(r'[ \t]+'), ' ').trim();
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

Map<String, _TrustPageDefinition> _trustPageDefinitions() {
  return const {
    'nosotros': _TrustPageDefinition(
      title: 'Sobre Nosotros',
      navLabel: 'Nosotros',
    ),
    'envios': _TrustPageDefinition(
      title: 'Información de Envíos',
      navLabel: 'Envíos',
    ),
    'devoluciones': _TrustPageDefinition(
      title: 'Política de Devoluciones',
      navLabel: 'Devoluciones',
    ),
    'terminos': _TrustPageDefinition(
      title: 'Términos y Condiciones',
      navLabel: 'Términos y condiciones',
    ),
    'privacidad': _TrustPageDefinition(
      title: 'Política de Privacidad',
      navLabel: 'Privacidad',
    ),
  };
}

String? _buildProductJsonLd({
  required String productUrl,
  required String storeUrl,
  required String storeName,
  required PublicCommerceProductProjection commerce,
  required SeoCategoryProjection? canonicalCategory,
}) {
  if (commerce.imageUrls.isEmpty) {
    return null;
  }

  final productData = <String, dynamic>{
    '@type': 'Product',
    'name': _cleanText(commerce.title),
    if (commerce.description.isNotEmpty)
      'description': _cleanText(commerce.description),
    'url': productUrl,
    'image': commerce.imageUrls,
    if (commerce.sku.isNotEmpty) 'sku': commerce.sku,
    if (commerce.mpn.isNotEmpty) 'mpn': commerce.mpn,
    if (commerce.categoryPath.isNotEmpty) 'category': commerce.categoryPath,
    if (commerce.brand.isNotEmpty)
      'brand': {
        '@type': 'Brand',
        'name': commerce.brand,
      },
    if (commerce.gtin.isNotEmpty) 'gtin': commerce.gtin,
    'offers': {
      '@type': 'Offer',
      'url': productUrl,
      'priceCurrency': commerce.currency,
      if (commerce.price > 0) 'price': commerce.formattedPrice,
      'availability': commerce.availability.schemaValue,
      'itemCondition': 'https://schema.org/NewCondition',
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
        if (canonicalCategory != null)
          (
            canonicalCategory.displayTitle,
            canonicalCategory.canonicalPath,
          ),
        (commerce.title, productUrl),
      ],
    ),
  ];

  final data = <String, dynamic>{
    '@context': 'https://schema.org',
    '@graph': graph,
  };

  return jsonEncode(data);
}

String _buildCategoryJsonLd({
  required SeoCategoryProjection category,
  required String categoryUrl,
  required String storeName,
}) {
  final itemList = category.products.take(10).toList(growable: false);
  final data = <String, dynamic>{
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'CollectionPage',
        'name': category.displayTitle,
        'url': categoryUrl,
        'description': _buildCategorySeoDescription(
          category: category,
          storeName: storeName,
        ),
        if (category.imageUrl.isNotEmpty) 'image': category.imageUrl,
      },
      _buildBreadcrumbListJsonLd(
        storeUrl: categoryUrl,
        items: [
          ('Inicio', '/'),
          ('Productos', '/productos'),
          (category.displayTitle, categoryUrl),
        ],
      ),
      {
        '@type': 'ItemList',
        'name': '${category.displayTitle} en $storeName',
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

String _buildCatalogJsonLd({
  required List<Map<String, dynamic>> products,
  required String storeUrl,
  required String storeName,
  required String catalogUrl,
  required String description,
  required Map<String, String> resolvedBrandNamesById,
}) {
  final visibleProducts = products.take(24).toList(growable: false);
  return jsonEncode({
    '@context': 'https://schema.org',
    '@graph': [
      {
        '@type': 'CollectionPage',
        'name': 'Productos para bicicletas en $storeName',
        'url': catalogUrl,
        'description': description,
      },
      _buildBreadcrumbListJsonLd(
        storeUrl: storeUrl,
        items: [('Inicio', '/'), ('Productos', '/productos')],
      ),
      {
        '@type': 'ItemList',
        'name': 'Catálogo de $storeName',
        'numberOfItems': products.length,
        'itemListElement': [
          for (var i = 0; i < visibleProducts.length; i++)
            {
              '@type': 'ListItem',
              'position': i + 1,
              'url': _joinUrl(
                storeUrl,
                _publicProductPath(visibleProducts[i]),
              ),
              'name': _cleanText(
                projectSeoSnapshotCommerceProduct(
                  visibleProducts[i],
                  resolvedBrandNamesById: resolvedBrandNamesById,
                ).title,
              ),
            },
        ],
      },
    ],
  });
}

Map<String, dynamic> _buildBreadcrumbListJsonLd({
  required String storeUrl,
  required List<(String, String)> items,
}) {
  final baseUrl = WebsiteSeoSettingsAliases.normalizeHttpsOrigin(
    _urlOrigin(storeUrl),
  );
  if (baseUrl.isEmpty) {
    throw ArgumentError.value(
      storeUrl,
      'storeUrl',
      'Debe ser un origen HTTPS público.',
    );
  }

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

class SeoWebsiteSettingsSource {
  SeoWebsiteSettingsSource.fromRows(Iterable<Map<String, dynamic>> sourceRows)
      : rows = List<Map<String, dynamic>>.unmodifiable(
          sourceRows
              .map((row) => Map<String, dynamic>.unmodifiable(row))
              .toList(growable: false)
            ..sort((a, b) {
              final byKey = (a['key'] ?? '')
                  .toString()
                  .compareTo((b['key'] ?? '').toString());
              if (byKey != 0) return byKey;
              return _canonicalSeoSourceJson(a)
                  .compareTo(_canonicalSeoSourceJson(b));
            }),
        ) {
    final nextValues = <String, String>{};
    for (final row in rows) {
      final key = (row['key'] ?? '').toString().trim();
      if (key.isEmpty) continue;
      if (nextValues.containsKey(key)) {
        throw StateError(
          'website_settings devolvió más de un owner para la clave $key.',
        );
      }
      nextValues[key] = (row['value'] ?? '').toString();
    }
    values = Map<String, String>.unmodifiable(nextValues);
  }

  final List<Map<String, dynamic>> rows;
  late final Map<String, String> values;

  DateTime? get updatedAt => maxFactualSeoUpdatedAt(
        rows.map((row) => _parseDateTime(row['updated_at'])),
      );
}

Future<SeoWebsiteSettingsSource> _fetchWebsiteSettingsSource({
  required String supabaseUrl,
  required String tenantId,
  required String serviceRoleKey,
}) async {
  final url = Uri.parse(
    '$supabaseUrl/rest/v1/website_settings'
    '?tenant_id=eq.$tenantId'
    '&select=key,value,updated_at'
    '&order=key.asc',
  );

  final response = await _httpGet(
    url,
    headers: {
      'apikey': serviceRoleKey,
    },
  );

  final decoded = jsonDecode(response) as List<dynamic>;
  return SeoWebsiteSettingsSource.fromRows(
    decoded.map((row) => Map<String, dynamic>.from(row as Map)),
  );
}

typedef SeoSnapshotProductPageLoader = Future<List<Map<String, dynamic>>>
    Function(Uri uri);

Uri buildSeoSnapshotProductPageUri({
  required String supabaseUrl,
  required String tenantId,
  required bool onlyMerchant,
  required int pageSize,
  String? afterId,
}) {
  return Uri.parse('$supabaseUrl/rest/v1/products').replace(
    queryParameters: {
      'tenant_id': 'eq.$tenantId',
      if (onlyMerchant) 'is_google_merchant': 'eq.true',
      'is_active': 'eq.true',
      'is_published': 'eq.true',
      'show_on_website': 'eq.true',
      'product_type': 'eq.product',
      'select':
          'id,name,description,website_description,website_name,website_price,website_image_url,website_image_url_optimized,website_image_urls,website_seo_title,website_seo_description,website_search_terms,website_merchant_title,website_merchant_description,website_merchant_gtin,website_merchant_mpn,website_merchant_brand,website_google_product_category,is_google_merchant,price,price_currency,sku,gtin,barcode,image_url,image_url_optimized,image_urls,brand_id,brand,category_id,category_name,stock_quantity,inventory_qty,track_stock,is_set,product_type,is_active,is_published,show_on_website,updated_at,created_at',
      'order': 'id.asc',
      if (afterId?.trim().isNotEmpty == true) 'id': 'gt.${afterId!.trim()}',
      'limit': pageSize.toString(),
    },
  );
}

Future<List<Map<String, dynamic>>> fetchSeoSnapshotProductCandidates({
  required String supabaseUrl,
  required String tenantId,
  required String serviceRoleKey,
  required bool onlyMerchant,
  int pageSize = 1000,
  SeoSnapshotProductPageLoader? pageLoader,
}) async {
  // Keep this aligned with the public storefront surface, not only the much
  // smaller Google Merchant subset. Merchant can still be requested explicitly
  // with `--product-scope merchant` for debugging feed-specific issues.
  final products = <Map<String, dynamic>>[];
  String? afterId;
  final loadPage = pageLoader ??
      (Uri uri) async {
        final response = await _httpGet(
          uri,
          headers: {
            'apikey': serviceRoleKey,
          },
        );
        return (jsonDecode(response) as List<dynamic>)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList(growable: false);
      };

  while (true) {
    final url = buildSeoSnapshotProductPageUri(
      supabaseUrl: supabaseUrl,
      tenantId: tenantId,
      onlyMerchant: onlyMerchant,
      pageSize: pageSize,
      afterId: afterId,
    );
    final page = await loadPage(url);
    products.addAll(page);
    if (page.length < pageSize) break;

    final nextAfterId = (page.last['id'] ?? '').toString().trim();
    if (nextAfterId.isEmpty || nextAfterId == afterId) {
      throw StateError(
        'La paginación SEO no pudo avanzar después de '
        '${afterId ?? 'la primera página'}.',
      );
    }
    afterId = nextAfterId;
  }

  return products;
}

List<Map<String, dynamic>> selectSeoSnapshotCandidatesForScope({
  required Iterable<Map<String, dynamic>> publishedProducts,
  required bool onlyMerchant,
}) {
  final selected = onlyMerchant
      ? publishedProducts.where(
          (product) => product['is_google_merchant'] == true,
        )
      : publishedProducts;
  return List.unmodifiable(selected);
}

Future<List<Map<String, dynamic>>> _fetchProductBrandRows({
  required String supabaseUrl,
  required String tenantId,
  required String serviceRoleKey,
  required Iterable<String> brandIds,
}) async {
  final requestedIds = brandIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList(growable: false);
  if (requestedIds.isEmpty) return const [];

  // Keep REST URLs bounded even when a large catalog references many brands.
  const batchSize = 200;
  final rows = <Map<String, dynamic>>[];
  for (var start = 0; start < requestedIds.length; start += batchSize) {
    final end = start + batchSize < requestedIds.length
        ? start + batchSize
        : requestedIds.length;
    final batch = requestedIds.sublist(start, end);
    final url = Uri.parse('$supabaseUrl/rest/v1/product_brands').replace(
      queryParameters: {
        'select': 'id,name,tenant_id,is_active,updated_at',
        'id': 'in.(${batch.join(',')})',
        // Brands may be shared (tenant_id NULL) or owned by this tenant.
        // Service-role snapshot generation must never resolve another
        // tenant's brand even if an invalid foreign ID reaches a product row.
        'or': '(tenant_id.eq.$tenantId,tenant_id.is.null)',
        'is_active': 'eq.true',
        'order': 'id.asc',
        'limit': batch.length.toString(),
      },
    );
    final response = await _httpGet(
      url,
      headers: {
        'apikey': serviceRoleKey,
      },
    );
    final decoded = jsonDecode(response) as List<dynamic>;
    rows.addAll(
      decoded.map((row) => Map<String, dynamic>.from(row as Map)),
    );
  }

  rows.sort(
    (a, b) => (a['id'] ?? '').toString().compareTo(
          (b['id'] ?? '').toString(),
        ),
  );
  return List.unmodifiable(rows);
}

Future<List<Map<String, dynamic>>> _fetchActiveProductCategories({
  required String supabaseUrl,
  required String tenantId,
  required String serviceRoleKey,
}) async {
  const pageSize = 1000;
  final categories = <Map<String, dynamic>>[];
  for (var offset = 0;; offset += pageSize) {
    final url = Uri.parse(
      '$supabaseUrl/rest/v1/product_categories'
      '?tenant_id=eq.$tenantId'
      '&is_active=eq.true'
      '&select=id,name,full_path,parent_id,level,description,image_url,'
      'sort_order,is_active,show_on_website,updated_at'
      '&order=sort_order.asc,full_path.asc,id.asc'
      '&limit=$pageSize'
      '&offset=$offset',
    );

    final response = await _httpGet(
      url,
      headers: {
        'apikey': serviceRoleKey,
      },
    );

    final decoded = jsonDecode(response) as List<dynamic>;
    categories.addAll(
      decoded.map((row) => Map<String, dynamic>.from(row as Map)),
    );
    if (decoded.length < pageSize) break;
  }
  return categories;
}

Future<Map<String, int>> _fetchPublicProductAvailability({
  required String supabaseUrl,
  required String tenantId,
  required String serviceRoleKey,
  required List<String> productIds,
}) async {
  if (productIds.isEmpty) return const {};

  const pageSize = 1000;
  final quantities = <String, int>{};
  for (var offset = 0;; offset += pageSize) {
    final response = await _httpPostJson(
      Uri.parse('$supabaseUrl/rest/v1/rpc/get_public_products'),
      headers: {
        'apikey': serviceRoleKey,
      },
      body: {
        'p_tenant_id': tenantId,
        'p_product_ids': productIds,
        'p_only_in_stock': true,
        'p_sort_by': 'name',
        'p_limit': pageSize,
        'p_offset': offset,
      },
    );

    final decoded = jsonDecode(response) as List<dynamic>;
    for (final rawRow in decoded) {
      final row = rawRow as Map<String, dynamic>;
      final id = (row['id'] ?? '').toString();
      if (id.isEmpty) continue;
      quantities[id] =
          _toInt(row['stock_quantity']) ?? _toInt(row['inventory_qty']) ?? 0;
    }
    if (decoded.length < pageSize) break;
  }

  return quantities;
}

typedef SeoSnapshotProductAliasPageLoader = Future<List<Map<String, dynamic>>>
    Function(Uri uri);

Future<List<Map<String, dynamic>>> fetchSeoSnapshotProductUrlAliases({
  required String supabaseUrl,
  required String tenantId,
  required String serviceRoleKey,
  int pageSize = 1000,
  SeoSnapshotProductAliasPageLoader? pageLoader,
}) async {
  if (pageSize <= 0) {
    throw ArgumentError.value(pageSize, 'pageSize', 'Debe ser mayor que cero.');
  }
  final aliases = <Map<String, dynamic>>[];
  final loadPage = pageLoader ??
      (Uri uri) async {
        final response = await _httpGet(
          uri,
          headers: {
            'apikey': serviceRoleKey,
          },
        );
        return (jsonDecode(response) as List<dynamic>)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList(growable: false);
      };

  for (var offset = 0;; offset += pageSize) {
    final uri = Uri.parse('$supabaseUrl/rest/v1/product_url_aliases').replace(
      queryParameters: {
        'tenant_id': 'eq.$tenantId',
        'select': 'product_id,alias_path,source,created_at',
        // `created_at` is not unique: historical imports can give thousands of
        // aliases the same timestamp. The tenant-unique path is the required
        // tie-breaker so offset pages cannot omit/duplicate tied rows.
        'order': 'created_at.asc,alias_path.asc',
        'limit': pageSize.toString(),
        'offset': offset.toString(),
      },
    );
    final page = await loadPage(uri);
    aliases.addAll(page);
    if (page.length < pageSize) break;
  }

  return List.unmodifiable(aliases);
}

typedef SeoSnapshotWebsitePageLoader = Future<List<Map<String, dynamic>>>
    Function(Uri uri);

Uri buildSeoSnapshotWebsitePageUri({
  required String supabaseUrl,
  required String tenantId,
  required int pageSize,
  String? afterId,
}) {
  return Uri.parse('$supabaseUrl/rest/v1/website_pages').replace(
    queryParameters: {
      'tenant_id': 'eq.$tenantId',
      'is_published': 'eq.true',
      'select': 'id,slug,title,meta_title,meta_description,meta_keywords,'
          'og_image_url,is_published,is_home,updated_at',
      'order': 'id.asc',
      if (afterId?.trim().isNotEmpty == true) 'id': 'gt.${afterId!.trim()}',
      'limit': pageSize.toString(),
    },
  );
}

Future<List<Map<String, dynamic>>> fetchSeoSnapshotPublishedWebsitePages({
  required String supabaseUrl,
  required String tenantId,
  required String serviceRoleKey,
  int pageSize = 500,
  SeoSnapshotWebsitePageLoader? pageLoader,
}) async {
  if (pageSize <= 0) {
    throw ArgumentError.value(pageSize, 'pageSize', 'Debe ser mayor que cero.');
  }
  final pages = <Map<String, dynamic>>[];
  String? afterId;
  final loadPage = pageLoader ??
      (Uri uri) async {
        final response = await _httpGet(
          uri,
          headers: {
            'apikey': serviceRoleKey,
          },
        );
        return (jsonDecode(response) as List<dynamic>)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList(growable: false);
      };

  while (true) {
    final uri = buildSeoSnapshotWebsitePageUri(
      supabaseUrl: supabaseUrl,
      tenantId: tenantId,
      pageSize: pageSize,
      afterId: afterId,
    );
    final page = await loadPage(uri);
    pages.addAll(page);
    if (page.length < pageSize) break;

    final nextAfterId = (page.last['id'] ?? '').toString().trim();
    if (nextAfterId.isEmpty || nextAfterId == afterId) {
      throw StateError(
        'La paginación de páginas SEO no pudo avanzar después de '
        '${afterId ?? 'la primera página'}.',
      );
    }
    afterId = nextAfterId;
  }

  return List.unmodifiable(pages);
}

Uri buildSeoSnapshotWebsiteBlockPageUri({
  required String supabaseUrl,
  required List<String> pageIds,
  required int pageSize,
  String? afterId,
}) {
  return Uri.parse('$supabaseUrl/rest/v1/website_blocks').replace(
    queryParameters: {
      'page_id': 'in.(${pageIds.join(',')})',
      'is_visible': 'eq.true',
      'select':
          'id,page_id,block_type,block_data,order_index,is_visible,updated_at',
      'order': 'id.asc',
      if (afterId?.trim().isNotEmpty == true) 'id': 'gt.${afterId!.trim()}',
      'limit': pageSize.toString(),
    },
  );
}

Future<Map<String, List<Map<String, dynamic>>>>
    fetchSeoSnapshotWebsiteBlocksForPages({
  required String supabaseUrl,
  required List<Map<String, dynamic>> pages,
  required String serviceRoleKey,
  int pageSize = 1000,
  int pageIdBatchSize = 100,
  SeoSnapshotWebsitePageLoader? pageLoader,
}) async {
  if (pageSize <= 0) {
    throw ArgumentError.value(pageSize, 'pageSize', 'Debe ser mayor que cero.');
  }
  if (pageIdBatchSize <= 0) {
    throw ArgumentError.value(
      pageIdBatchSize,
      'pageIdBatchSize',
      'Debe ser mayor que cero.',
    );
  }
  final pageIds = pages
      .map((page) => (page['id'] ?? '').toString().trim())
      .where((id) => id.isNotEmpty)
      .toSet()
      .toList(growable: false)
    ..sort();
  if (pageIds.isEmpty) return {};

  final loadPage = pageLoader ??
      (Uri uri) async {
        final response = await _httpGet(
          uri,
          headers: {
            'apikey': serviceRoleKey,
          },
        );
        return (jsonDecode(response) as List<dynamic>)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList(growable: false);
      };
  final byPage = <String, List<Map<String, dynamic>>>{};

  for (var start = 0; start < pageIds.length; start += pageIdBatchSize) {
    final end = min(start + pageIdBatchSize, pageIds.length);
    final batch = pageIds.sublist(start, end);
    String? afterId;

    while (true) {
      final uri = buildSeoSnapshotWebsiteBlockPageUri(
        supabaseUrl: supabaseUrl,
        pageIds: batch,
        pageSize: pageSize,
        afterId: afterId,
      );
      final page = await loadPage(uri);
      for (final block in page) {
        final pageId = (block['page_id'] ?? '').toString().trim();
        if (pageId.isEmpty || !batch.contains(pageId)) continue;
        byPage.putIfAbsent(pageId, () => <Map<String, dynamic>>[]).add(block);
      }
      if (page.length < pageSize) break;

      final nextAfterId = (page.last['id'] ?? '').toString().trim();
      if (nextAfterId.isEmpty || nextAfterId == afterId) {
        throw StateError(
          'La paginación de bloques SEO no pudo avanzar después de '
          '${afterId ?? 'la primera página'} para el lote iniciado en '
          '${batch.first}.',
        );
      }
      afterId = nextAfterId;
    }
  }

  for (final blocks in byPage.values) {
    blocks.sort((a, b) {
      final order = (_toInt(a['order_index']) ?? 0)
          .compareTo(_toInt(b['order_index']) ?? 0);
      if (order != 0) return order;
      return (a['id'] ?? '').toString().compareTo(
            (b['id'] ?? '').toString(),
          );
    });
  }

  return Map<String, List<Map<String, dynamic>>>.unmodifiable({
    for (final entry in byPage.entries)
      entry.key: List<Map<String, dynamic>>.unmodifiable(entry.value),
  });
}

class SeoWebsiteContentSnapshot {
  SeoWebsiteContentSnapshot({
    required this.pages,
    required this.pageBlocks,
  }) : revision = _canonicalSeoSourceJson({
          'pages': pages,
          'pageBlocks': pageBlocks,
        });

  final List<Map<String, dynamic>> pages;
  final Map<String, List<Map<String, dynamic>>> pageBlocks;
  final String revision;
}

/// Reads the website page and block owners twice and accepts the projection
/// only when both reads describe the same revision.
///
/// PostgREST requests cannot share a transaction snapshot. This optimistic
/// read/CAS guard therefore fails the release instead of mixing a page row from
/// one editor save with blocks from another.
Future<SeoWebsiteContentSnapshot> fetchConsistentSeoWebsiteContentSnapshot({
  required String supabaseUrl,
  required String tenantId,
  required String serviceRoleKey,
  SeoSnapshotWebsitePageLoader? pageLoader,
  SeoSnapshotWebsitePageLoader? blockPageLoader,
}) async {
  Future<SeoWebsiteContentSnapshot> readOnce() async {
    final pages = await fetchSeoSnapshotPublishedWebsitePages(
      supabaseUrl: supabaseUrl,
      tenantId: tenantId,
      serviceRoleKey: serviceRoleKey,
      pageLoader: pageLoader,
    );
    final blocks = await fetchSeoSnapshotWebsiteBlocksForPages(
      supabaseUrl: supabaseUrl,
      pages: pages,
      serviceRoleKey: serviceRoleKey,
      pageLoader: blockPageLoader,
    );
    return SeoWebsiteContentSnapshot(pages: pages, pageBlocks: blocks);
  }

  final first = await readOnce();
  final second = await readOnce();
  if (first.revision != second.revision) {
    throw StateError(
      'Las páginas o bloques del sitio cambiaron durante la lectura SEO. '
      'Se abortó para no publicar un snapshot mezclado; reintenta con la '
      'revisión estable.',
    );
  }
  return second;
}

Future<void> assertSeoWebsiteContentSnapshotIsCurrent({
  required SeoWebsiteContentSnapshot expected,
  required String supabaseUrl,
  required String tenantId,
  required String serviceRoleKey,
  SeoSnapshotWebsitePageLoader? pageLoader,
  SeoSnapshotWebsitePageLoader? blockPageLoader,
}) async {
  final current = await fetchConsistentSeoWebsiteContentSnapshot(
    supabaseUrl: supabaseUrl,
    tenantId: tenantId,
    serviceRoleKey: serviceRoleKey,
    pageLoader: pageLoader,
    blockPageLoader: blockPageLoader,
  );
  if (current.revision != expected.revision) {
    throw StateError(
      'Las páginas o bloques del sitio cambiaron mientras se generaban los '
      'artefactos SEO. No se aplicaron redirects; vuelve a generar desde la '
      'revisión actual.',
    );
  }
}

class SeoOwnerSourceSnapshot {
  SeoOwnerSourceSnapshot({
    required this.websiteSettings,
    required this.publishedProductOwners,
    required this.publicAvailability,
    required this.brandRows,
    required this.activeCategoryRows,
    required this.productUrlAliases,
    required this.websiteContent,
  }) {
    final editorialProjection = <String, dynamic>{
      'websiteSettings': _sortedSeoSourceRowRevisions(websiteSettings.rows),
      'publishedProductOwners': _sortedSeoSourceRowRevisions(
        publishedProductOwners.map(_withoutTransientProductStock),
      ),
      'brandRows': _sortedSeoSourceRowRevisions(brandRows),
      'activeCategoryRows': _sortedSeoSourceRowRevisions(activeCategoryRows),
      'productUrlAliases': _sortedSeoSourceRowRevisions(productUrlAliases),
      'websitePages': _sortedSeoSourceRowRevisions(websiteContent.pages),
      'websitePageBlocks': {
        for (final pageId in websiteContent.pageBlocks.keys.toList()..sort())
          pageId: _sortedSeoSourceRowRevisions(
            websiteContent.pageBlocks[pageId]!,
          ),
      },
    };
    final buildProjection = <String, dynamic>{
      ...editorialProjection,
      // The complete build input deliberately retains both the canonical
      // public-availability projection and stock facts embedded in product
      // rows. A stock transition must invalidate the optimistic build CAS even
      // though it is not a new editorial owner revision.
      'publishedProductOwners':
          _sortedSeoSourceRowRevisions(publishedProductOwners),
      'publicAvailability': publicAvailability,
    };
    ownerSourceRevision = _canonicalSeoSourceJson(editorialProjection);
    revision = _canonicalSeoSourceJson(buildProjection);
    ownerSourceSha256 = _sha256Hex(ownerSourceRevision);
    buildInputSha256 = _sha256Hex(revision);
  }

  final SeoWebsiteSettingsSource websiteSettings;
  final List<Map<String, dynamic>> publishedProductOwners;
  final Map<String, int> publicAvailability;
  final List<Map<String, dynamic>> brandRows;
  final List<Map<String, dynamic>> activeCategoryRows;
  final List<Map<String, dynamic>> productUrlAliases;
  final SeoWebsiteContentSnapshot websiteContent;
  late final String ownerSourceRevision;
  late final String revision;
  late final String ownerSourceSha256;
  late final String buildInputSha256;
}

typedef SeoOwnerSourceSnapshotLoader = Future<SeoOwnerSourceSnapshot>
    Function();

/// PostgREST cannot give this multi-owner build one transaction snapshot.
///
/// Read every owner twice and accept the release input only when both complete
/// source revisions match. This prevents settings, catalog, availability,
/// brands, categories, aliases, presentations, pages, and blocks from being
/// combined across different editor/inventory revisions.
Future<SeoOwnerSourceSnapshot> fetchConsistentSeoOwnerSourceSnapshot({
  required SeoOwnerSourceSnapshotLoader readOnce,
}) async {
  final first = await readOnce();
  final second = await readOnce();
  if (first.revision != second.revision) {
    throw StateError(
      'Las fuentes del sitio cambiaron durante la lectura SEO. Se abortó para '
      'no publicar una mezcla de settings, catálogo, stock, marcas, '
      'categorías, aliases, páginas o bloques.',
    );
  }
  return second;
}

Future<void> assertSeoOwnerSourceSnapshotIsCurrent({
  required SeoOwnerSourceSnapshot expected,
  required SeoOwnerSourceSnapshotLoader readOnce,
}) async {
  final current = await fetchConsistentSeoOwnerSourceSnapshot(
    readOnce: readOnce,
  );
  if (current.revision != expected.revision) {
    throw StateError(
      'Una fuente del sitio cambió mientras se generaban los artefactos SEO. '
      'No se aplicaron redirects; vuelve a generar desde la revisión actual.',
    );
  }
}

Future<SeoOwnerSourceSnapshot> _readSeoOwnerSourceSnapshot({
  required String supabaseUrl,
  required String tenantId,
  required String serviceRoleKey,
}) async {
  final websiteSettings = await _fetchWebsiteSettingsSource(
    supabaseUrl: supabaseUrl,
    tenantId: tenantId,
    serviceRoleKey: serviceRoleKey,
  );
  final publishedProductOwners = await fetchSeoSnapshotProductCandidates(
    supabaseUrl: supabaseUrl,
    tenantId: tenantId,
    serviceRoleKey: serviceRoleKey,
    onlyMerchant: false,
  );
  final productIds = publishedProductOwners
      .map((product) => (product['id'] ?? '').toString().trim())
      .where((id) => id.isNotEmpty)
      .toList(growable: false);
  final publicAvailability = await _fetchPublicProductAvailability(
    supabaseUrl: supabaseUrl,
    tenantId: tenantId,
    serviceRoleKey: serviceRoleKey,
    productIds: productIds,
  );
  final brandRows = await _fetchProductBrandRows(
    supabaseUrl: supabaseUrl,
    tenantId: tenantId,
    serviceRoleKey: serviceRoleKey,
    brandIds: publishedProductOwners
        .map((product) => (product['brand_id'] ?? '').toString())
        .where((id) => id.trim().isNotEmpty),
  );
  final activeCategoryRows = await _fetchActiveProductCategories(
    supabaseUrl: supabaseUrl,
    tenantId: tenantId,
    serviceRoleKey: serviceRoleKey,
  );
  final productUrlAliases = await fetchSeoSnapshotProductUrlAliases(
    supabaseUrl: supabaseUrl,
    tenantId: tenantId,
    serviceRoleKey: serviceRoleKey,
  );
  final pages = await fetchSeoSnapshotPublishedWebsitePages(
    supabaseUrl: supabaseUrl,
    tenantId: tenantId,
    serviceRoleKey: serviceRoleKey,
  );
  final pageBlocks = await fetchSeoSnapshotWebsiteBlocksForPages(
    supabaseUrl: supabaseUrl,
    pages: pages,
    serviceRoleKey: serviceRoleKey,
  );

  return SeoOwnerSourceSnapshot(
    websiteSettings: websiteSettings,
    publishedProductOwners: List.unmodifiable(publishedProductOwners),
    publicAvailability: Map.unmodifiable(publicAvailability),
    brandRows: List.unmodifiable(brandRows),
    activeCategoryRows: List.unmodifiable(activeCategoryRows),
    productUrlAliases: List.unmodifiable(productUrlAliases),
    websiteContent: SeoWebsiteContentSnapshot(
      pages: pages,
      pageBlocks: pageBlocks,
    ),
  );
}

List<String> _sortedSeoSourceRowRevisions(
  Iterable<Map<String, dynamic>> rows,
) {
  final revisions = rows.map(_canonicalSeoSourceJson).toList(growable: false)
    ..sort();
  return revisions;
}

const Set<String> _transientProductStockKeys = {
  'stock_quantity',
  'inventory_qty',
  // Product stock updates advance the shared row timestamp. Keeping it in the
  // editorial projection would make an inventory-only movement look like a
  // content revision even after both quantity fields were removed.
  'updated_at',
};

Map<String, dynamic> _withoutTransientProductStock(
  Map<String, dynamic> row,
) {
  return <String, dynamic>{
    for (final entry in row.entries)
      if (!_transientProductStockKeys.contains(entry.key))
        entry.key: entry.value,
  };
}

String _canonicalSeoSourceJson(dynamic value) {
  dynamic canonicalize(dynamic node) {
    if (node is Map) {
      final keys = node.keys.map((key) => key.toString()).toList()..sort();
      return <String, dynamic>{
        for (final key in keys) key: canonicalize(node[key]),
      };
    }
    if (node is List) return node.map(canonicalize).toList(growable: false);
    return node;
  }

  return jsonEncode(canonicalize(value));
}

String _sha256Hex(String canonicalJson) {
  return sha256.convert(utf8.encode(canonicalJson)).toString();
}

final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');
final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-'
  r'[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
);

/// Resolves and clears a previous generated evidence file before any remote
/// reads. A failed build therefore cannot leave stale hashes that look like
/// evidence from the failed invocation.
///
/// Existing unrelated files and symbolic links fail closed instead of being
/// overwritten.
File prepareSeoPublicationEvidenceOutput(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('El path de evidencia está vacío.');
  }
  final outputFile = File(trimmed);
  final type = FileSystemEntity.typeSync(
    outputFile.path,
    followLinks: false,
  );
  if (type == FileSystemEntityType.directory ||
      type == FileSystemEntityType.link) {
    throw FileSystemException(
      'El path de evidencia debe ser un archivo regular.',
      outputFile.path,
    );
  }
  if (type == FileSystemEntityType.file) {
    final dynamic existing;
    try {
      existing = jsonDecode(outputFile.readAsStringSync());
    } on FormatException {
      throw const FormatException(
        'El archivo existente no es evidencia de publicación reemplazable.',
      );
    }
    if (existing is! Map ||
        existing.keys.map((key) => key.toString()).toSet().difference(
          const {'owner_source_sha256', 'build_input_sha256'},
        ).isNotEmpty ||
        existing.length != 2 ||
        !_sha256Pattern.hasMatch(
          (existing['owner_source_sha256'] ?? '').toString(),
        ) ||
        !_sha256Pattern.hasMatch(
          (existing['build_input_sha256'] ?? '').toString(),
        )) {
      throw const FormatException(
        'El archivo existente no es evidencia de publicación reemplazable.',
      );
    }
    outputFile.deleteSync();
  }
  return outputFile;
}

/// Writes only the two deterministic source digests consumed by the release
/// manifest. No tenant data, credentials, revision payloads, or timestamps are
/// exposed.
Future<void> writeSeoPublicationEvidenceFile({
  required File outputFile,
  required String ownerSourceSha256,
  required String buildInputSha256,
}) async {
  if (!_sha256Pattern.hasMatch(ownerSourceSha256) ||
      !_sha256Pattern.hasMatch(buildInputSha256)) {
    throw const FormatException(
      'La evidencia de publicación requiere dos SHA-256 canónicos.',
    );
  }

  const encoder = JsonEncoder.withIndent('  ');
  final contents = '${encoder.convert({
        'owner_source_sha256': ownerSourceSha256,
        'build_input_sha256': buildInputSha256,
      })}\n';
  outputFile.parent.createSync(recursive: true);
  final temporaryFile = File(
    '${outputFile.path}.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}',
  );
  try {
    await temporaryFile.writeAsString(contents, flush: true);
    if (outputFile.existsSync()) {
      await outputFile.delete();
    }
    await temporaryFile.rename(outputFile.path);
    if (await outputFile.readAsString() != contents) {
      throw StateError(
        'La evidencia escrita no coincide con la proyección determinista.',
      );
    }
  } finally {
    if (temporaryFile.existsSync()) {
      temporaryFile.deleteSync();
    }
  }
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

Future<String> _httpPostJson(
  Uri url, {
  required Map<String, String> headers,
  required Map<String, dynamic> body,
}) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(url);
    headers.forEach(req.headers.set);
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    final res = await req.close();
    final responseBody = await res.transform(utf8.decoder).join();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException(
        'POST $url failed: ${res.statusCode} ${res.reasonPhrase}\n$responseBody',
      );
    }
    return responseBody;
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

List<String> _stringList(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((entry) => _cleanText((entry ?? '').toString()))
      .where((entry) => entry.isNotEmpty)
      .toList(growable: false);
}

String _buildProductFallbackHtml({
  required String title,
  required String description,
  required String storeName,
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
  details.add(inStock ? 'Disponibilidad: en stock' : 'Disponibilidad: agotado');

  final imageHtml = imageUrl.isEmpty
      ? ''
      : '<img src="${_escapeHtml(imageUrl)}" alt="${_escapeHtml(title)}" '
          'loading="lazy" style="max-width:240px;height:auto;">';
  final descriptionHtml =
      description.trim().isEmpty ? '' : '<p>${_escapeHtml(description)}</p>';

  return '''
  <main id="seo-product-fallback" class="storefront-nojs-fallback">
    <article>
      <h1>${_escapeHtml(title)}</h1>
      $descriptionHtml
      $imageHtml
      <ul>
        ${details.map((item) => '<li>${_escapeHtml(item)}</li>').join('\n        ')}
      </ul>
      <p><a href="${_escapeHtml(canonicalUrl)}">Ver producto en ${_escapeHtml(storeName)}</a></p>
      <p><a href="/productos">Ver más productos de bicicleta</a></p>
    </article>
  </main>''';
}

String _buildCategorySeoTitle({
  required SeoCategoryProjection category,
  required String storeName,
}) {
  if (category.seoTitle.trim().isNotEmpty) return category.seoTitle.trim();
  final cleanStoreName = _cleanText(storeName);
  return cleanStoreName.isEmpty
      ? category.displayTitle
      : '${category.displayTitle} | $cleanStoreName';
}

String _buildCategorySeoDescription({
  required SeoCategoryProjection category,
  required String storeName,
}) {
  if (category.seoDescription.trim().isNotEmpty) {
    return category.seoDescription.trim();
  }
  if (category.description.isNotEmpty) return category.description;

  // This is a factual fallback projected from canonical owners and is also
  // rendered in the snapshot body. It deliberately does not infer technical
  // attributes or buying claims from product titles.
  return _cleanText(
    '${category.productCount} productos publicados en '
    '${category.displayTitle}${storeName.trim().isEmpty ? '' : ' de $storeName'}.',
  );
}

String _buildCategoryFallbackHtml({
  required String title,
  required String description,
  required String storeName,
  required SeoCategoryProjection category,
}) {
  final items = category.products.take(24).map((product) {
    return '<li><a href="${_escapeHtml(product.url)}">'
        '${_escapeHtml(product.name)}</a></li>';
  }).join('\n          ');

  return '''
  <main id="seo-category-fallback" class="storefront-nojs-fallback">
    <h1>${_escapeHtml(title)}</h1>
    <p>${_escapeHtml(description)}</p>
    <ul>
        $items
    </ul>
    <p><a href="/productos">Ver catálogo completo de ${_escapeHtml(storeName)}</a></p>
  </main>''';
}

String _buildCatalogFallbackHtml({
  required List<Map<String, dynamic>> products,
  required String title,
  required String description,
}) {
  final items = products.take(24).map((product) {
    final name = _cleanText(_firstNonEmpty(
      product['website_name'],
      product['name'],
    ));
    return '<li><a href="${_escapeHtml(_publicProductPath(product))}">'
        '${_escapeHtml(name)}</a></li>';
  }).join('\n          ');

  return '''
  <main id="seo-catalog-fallback" class="storefront-nojs-fallback">
    <h1>${_escapeHtml(title)}</h1>
    <p>${_escapeHtml(description)}</p>
    <ul>
        $items
    </ul>
    <p><a href="/productos">Ver catálogo completo</a></p>
  </main>''';
}

/// Builds the exact active catalog-category path projection used by product
/// metadata.
///
/// Product metadata and collection publication have deliberately different
/// eligibility rules: a product keeps the factual path of its exact active
/// category even when that category is a hidden descendant, while only
/// `show_on_website` categories may produce collection pages. Inactive rows
/// are excluded rather than leaking a stale catalog path into a snapshot.
Map<String, String> buildActiveCategoryPathMap({
  required List<Map<String, dynamic>> activeCategories,
}) {
  final pathsById = <String, String>{};
  for (final row in activeCategories) {
    final categoryId = (row['id'] ?? '').toString().trim();
    if (categoryId.isEmpty || row['is_active'] != true) continue;

    final fullPath = _cleanText((row['full_path'] ?? '').toString());
    final categoryName = _cleanText((row['name'] ?? '').toString());
    final categoryPath = fullPath.isNotEmpty ? fullPath : categoryName;
    if (categoryPath.isNotEmpty) {
      pathsById[categoryId] = categoryPath;
    }
  }
  return Map.unmodifiable(pathsById);
}

/// Builds crawler category pages from the same stable category IDs, saved
/// presentation registry, and already-canonical public product result used by
/// the storefront.
///
/// [products] must be the result after `get_public_products` eligibility has
/// been applied. Display names alone never establish category membership.
List<SeoCategoryProjection> buildCanonicalCategorySeoProjections({
  required List<Map<String, dynamic>> products,
  required List<Map<String, dynamic>> activeCategories,
  required WebsiteCatalogPresentationRegistry presentationRegistry,
  required String storeUrl,
  Map<String, String> resolvedBrandNamesById = const {},
}) {
  final categoryRowsById = <String, Map<String, dynamic>>{};
  for (final row in activeCategories) {
    final id = (row['id'] ?? '').toString().trim();
    if (id.isEmpty || row['is_active'] != true) {
      continue;
    }
    categoryRowsById[id] = row;
  }

  final childIdsByParentId = <String, Set<String>>{};
  for (final entry in categoryRowsById.entries) {
    final parentId = (entry.value['parent_id'] ?? '').toString().trim();
    if (parentId.isEmpty || !categoryRowsById.containsKey(parentId)) continue;
    childIdsByParentId.putIfAbsent(parentId, () => <String>{}).add(entry.key);
  }

  Set<String> descendantIdsFor(String rootId) {
    final ids = <String>{};
    final pending = <String>[rootId];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!ids.add(current)) continue;
      pending.addAll(childIdsByParentId[current] ?? const <String>{});
    }
    return ids;
  }

  final projections = <SeoCategoryProjection>[];
  final categoryIdBySlug = <String, String>{};
  for (final entry in categoryRowsById.entries) {
    final row = entry.value;
    // Category publication owns discoverable collection pages. Hidden active
    // descendants still contribute products to a published ancestor, matching
    // the storefront hierarchy and the separate visible-category product rule.
    if (row['show_on_website'] != true) continue;
    final name = _cleanText((row['name'] ?? '').toString());
    if (name.isEmpty) continue;

    final presentation = presentationRegistry.forCategory(entry.key) ??
        WebsiteCatalogPresentation.fallback(
          categoryId: entry.key,
          categoryName: name,
        );
    if (presentation.slug.isEmpty) continue;

    final descendantIds = descendantIdsFor(entry.key);
    final categoryProducts = <SeoCategoryProductProjection>[];
    for (final product in products) {
      final categoryId = (product['category_id'] ?? '').toString().trim();
      if (categoryId.isEmpty || !descendantIds.contains(categoryId)) continue;
      final productPath = _publicProductPath(product);
      if (productPath == '/productos') continue;
      final productName = _cleanText(
        projectSeoSnapshotCommerceProduct(
          product,
          resolvedBrandNamesById: resolvedBrandNamesById,
        ).title,
      );
      if (productName.isEmpty) continue;
      categoryProducts.add(
        SeoCategoryProductProjection(
          name: productName,
          url: _joinUrl(storeUrl, productPath),
          updatedAt: _parseDateTime(product['updated_at']),
        ),
      );
    }

    // Empty public categories are not indexable and must not survive through
    // a stale presentation record.
    if (categoryProducts.isEmpty) continue;

    for (final routeSlug in {
      presentation.slug,
      ...presentation.slugAliases,
    }) {
      final previousCategoryId = categoryIdBySlug[routeSlug];
      if (previousCategoryId != null && previousCategoryId != entry.key) {
        throw StateError(
          'Las categorías públicas $previousCategoryId y ${entry.key} '
          'comparten la ruta o alias $routeSlug. Configura rutas únicas en '
          'Catálogo web > Categorías > Presentación.',
        );
      }
      categoryIdBySlug[routeSlug] = entry.key;
    }

    final categoryDescription =
        _cleanText((row['description'] ?? '').toString());
    final categoryImageUrl = (row['image_url'] ?? '').toString().trim();
    projections.add(
      SeoCategoryProjection(
        categoryId: entry.key,
        name: name,
        fullPath: _cleanText((row['full_path'] ?? '').toString()).isNotEmpty
            ? _cleanText((row['full_path'] ?? '').toString())
            : name,
        slug: presentation.slug,
        slugAliases: presentation.slugAliases,
        canonicalPath: publicCategoryPath(presentation: presentation),
        displayTitle:
            presentation.heroTitle.isNotEmpty ? presentation.heroTitle : name,
        description: presentation.heroDescription.isNotEmpty
            ? presentation.heroDescription
            : categoryDescription,
        seoTitle: presentation.seoTitle,
        seoDescription: presentation.seoDescription,
        imageUrl: presentation.heroImageUrl.isNotEmpty
            ? presentation.heroImageUrl
            : categoryImageUrl,
        socialImageUrl: presentation.socialImageUrl.isNotEmpty
            ? presentation.socialImageUrl
            : presentation.heroImageUrl.isNotEmpty
                ? presentation.heroImageUrl
                : categoryImageUrl,
        allowIndexing: presentation.allowIndexing,
        sortOrder: _toInt(row['sort_order']) ?? 0,
        updatedAt: _parseDateTime(row['updated_at']),
        products: List.unmodifiable(categoryProducts),
      ),
    );
  }

  projections.sort((a, b) {
    final byOrder = a.sortOrder.compareTo(b.sortOrder);
    if (byOrder != 0) return byOrder;
    return a.fullPath.compareTo(b.fullPath);
  });
  return List.unmodifiable(projections);
}

/// Resolves the exact public-commerce facts used by every generated snapshot.
///
/// Linked brands are canonical `product_brands` facts. The denormalized
/// `products.brand` value remains only the projection's final legacy fallback,
/// matching Merchant precedence without inventing manufacturer identity.
PublicCommerceProductProjection projectSeoSnapshotCommerceProduct(
  Map<String, dynamic> product, {
  Map<String, String> resolvedBrandNamesById = const {},
  String? categoryPath,
}) {
  final brandId = (product['brand_id'] ?? '').toString().trim();
  return PublicCommerceProductProjection.fromJson(
    product,
    resolvedBrand:
        brandId.isEmpty ? null : resolvedBrandNamesById[brandId]?.trim(),
    categoryPath: categoryPath,
  );
}

/// Defensively filters brand rows after the tenant-scoped REST query.
///
/// `product_brands` supports both tenant-owned and shared (`tenant_id NULL`)
/// records. Rows belonging to another tenant are never returned to the
/// snapshot projection, even if a malformed response or foreign ID is passed.
Map<String, String> buildTenantSafeProductBrandNameMap({
  required List<Map<String, dynamic>> brandRows,
  required String tenantId,
  required Iterable<String> requestedBrandIds,
}) {
  final requested = requestedBrandIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet();
  final namesById = <String, String>{};
  for (final row in brandRows) {
    final id = (row['id'] ?? '').toString().trim();
    final name = (row['name'] ?? '').toString().trim();
    final rowTenantId = (row['tenant_id'] ?? '').toString().trim();
    final belongsToScope =
        rowTenantId.isEmpty || rowTenantId == tenantId.trim();
    if (requested.contains(id) &&
        name.isNotEmpty &&
        row['is_active'] == true &&
        belongsToScope) {
      namesById[id] = name;
    }
  }
  return Map.unmodifiable(namesById);
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
  required List<SeoCategoryProjection> categories,
  required List<Map<String, dynamic>> websitePages,
  required Map<String, List<Map<String, dynamic>>> websitePageBlocks,
  required List<PublishedDynamicCmsSeoProjection> dynamicCmsPages,
  required Set<String> staticTrustPagePaths,
  required bool productsCatalogIndexable,
  required Map<String, String> resolvedBrandNamesById,
  required DateTime? websiteSettingsUpdatedAt,
  required List<Map<String, dynamic>> brandRows,
  required List<Map<String, dynamic>> activeCategoryRows,
}) async {
  final normalizedStoreUrl = storeUrl.replaceAll(RegExp(r'/+$'), '');
  final urls = <String, SeoSitemapUrl>{};
  final brandUpdatedAtById = <String, DateTime?>{
    for (final row in brandRows)
      (row['id'] ?? '').toString().trim(): _parseDateTime(row['updated_at']),
  }..remove('');
  final categoryUpdatedAtById = <String, DateTime?>{
    for (final row in activeCategoryRows)
      (row['id'] ?? '').toString().trim(): _parseDateTime(row['updated_at']),
  }..remove('');

  void addUrl(
    String path, {
    DateTime? lastmod,
    String? changefreq,
    String? priority,
    List<SeoSitemapImage> images = const [],
  }) {
    if (!isIndexableStorefrontPathForSitemap(path)) return;
    final normalizedPath =
        path == '/' ? '/' : '/${path.replaceAll(RegExp(r'^/+|/+$'), '')}';
    urls[normalizedPath] = SeoSitemapUrl(
      loc: _joinUrl(normalizedStoreUrl, normalizedPath),
      lastmod: lastmod,
      changefreq: changefreq,
      priority: priority,
      images: images,
    );
  }

  addUrl(
    '/',
    lastmod: _websitePageUpdatedAtForPath(
      websitePages,
      websitePageBlocks,
      '/',
      additionalContributors: [websiteSettingsUpdatedAt],
    ),
    changefreq: 'weekly',
    priority: '1.0',
  );
  if (productsCatalogIndexable) {
    addUrl(
      '/productos',
      lastmod: maxFactualSeoUpdatedAt(
        [
          websiteSettingsUpdatedAt,
          ...products.map((product) => _parseDateTime(product['updated_at'])),
          ...brandRows.map((row) => _parseDateTime(row['updated_at'])),
          ...activeCategoryRows.map((row) => _parseDateTime(row['updated_at'])),
        ],
      ),
      changefreq: 'daily',
      priority: '0.9',
    );
  }
  for (final path in staticTrustPagePaths) {
    addUrl(
      path,
      lastmod: _websitePageUpdatedAtForPath(
        websitePages,
        websitePageBlocks,
        path,
        additionalContributors: [websiteSettingsUpdatedAt],
      ),
      changefreq: path == '/nosotros' ? 'monthly' : 'yearly',
      priority: path == '/nosotros' ? '0.5' : '0.3',
    );
  }

  for (final page in dynamicCmsPages) {
    addUrl(
      page.canonicalPath,
      lastmod: page.updatedAt,
      changefreq: 'monthly',
      priority: page.canonicalPath == '/servicios'
          ? '0.7'
          : page.canonicalPath == '/contacto'
              ? '0.6'
              : '0.5',
    );
  }

  for (final product in products) {
    final productPath = _publicProductPath(product);
    if (productPath == '/productos') continue;
    final commerce = projectSeoSnapshotCommerceProduct(
      product,
      resolvedBrandNamesById: resolvedBrandNamesById,
    );
    final productName = _cleanText(commerce.title);
    addUrl(
      productPath,
      lastmod: maxFactualSeoUpdatedAt([
        websiteSettingsUpdatedAt,
        _parseDateTime(product['updated_at']),
        brandUpdatedAtById[(product['brand_id'] ?? '').toString().trim()],
        categoryUpdatedAtById[(product['category_id'] ?? '').toString().trim()],
      ]),
      changefreq: 'weekly',
      priority: '0.8',
      images: commerce.imageUrls
          .map(
            (url) => SeoSitemapImage(
              loc: url,
              title: productName,
            ),
          )
          .toList(growable: false),
    );
  }

  for (final category in categories) {
    if (!category.allowIndexing) continue;
    addUrl(
      category.canonicalPath,
      lastmod: maxFactualSeoUpdatedAt([
        websiteSettingsUpdatedAt,
        category.updatedAt,
        ...category.products.map((product) => product.updatedAt),
      ]),
      changefreq: 'weekly',
      priority: '0.7',
    );
  }

  final sorted = urls.values.toList()..sort((a, b) => a.loc.compareTo(b.loc));

  await File(pathJoin(buildDir.path, 'sitemap.xml'))
      .writeAsString(buildSeoSitemapXml(sorted));

  final robots = '''
User-agent: *
Allow: /

Disallow: /cuenta/
Disallow: /pedido/

Sitemap: $normalizedStoreUrl/sitemap.xml
''';

  await File(pathJoin(buildDir.path, 'robots.txt')).writeAsString(robots);
}

DateTime? _websitePageUpdatedAtForPath(
  List<Map<String, dynamic>> pages,
  Map<String, List<Map<String, dynamic>>> pageBlocks,
  String path, {
  Iterable<DateTime?> additionalContributors = const [],
}) {
  for (final page in pages) {
    if (_routeForWebsitePage(page) == path) {
      final pageId = (page['id'] ?? '').toString().trim();
      return maxFactualSeoUpdatedAt([
        ...additionalContributors,
        _parseDateTime(page['updated_at']),
        ...?pageBlocks[pageId]
            ?.where(isWebsiteBlockVisibleOnAnyPublicBreakpoint)
            .map((block) => _parseDateTime(block['updated_at'])),
      ]);
    }
  }
  return maxFactualSeoUpdatedAt(additionalContributors);
}

DateTime? maxFactualSeoUpdatedAt(Iterable<DateTime?> values) {
  DateTime? latest;
  for (final value in values) {
    if (value != null && (latest == null || value.isAfter(latest))) {
      latest = value;
    }
  }
  return latest;
}

String buildSeoSitemapXml(Iterable<SeoSitemapUrl> urls) {
  final sitemap = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln(
      '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" '
      'xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">',
    );
  for (final url in urls) {
    sitemap
      ..writeln('  <url>')
      ..writeln('    <loc>${_escapeXml(url.loc)}</loc>');
    if (url.lastmod != null) {
      sitemap.writeln('    <lastmod>${_formatDate(url.lastmod!)}</lastmod>');
    }
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
  return sitemap.toString();
}

/// Fails the deploy-time generator when its final files violate the crawler
/// contract. This validates the artifacts that Firebase will receive, not just
/// the Dart builders that produced them.
Future<void> validateGeneratedSeoArtifacts({
  required Directory buildDir,
  required String storeUrl,
  required Set<String> staticTrustPagePaths,
  Map<String, String>? expectedLocalBusinessIdentity,
}) async {
  final files = <String, File>{};
  const unownedReturnPolicyType = 'Merchant' 'ReturnPolicy';

  void addFile(File file) {
    if (file.existsSync()) files[file.absolute.path] = file;
  }

  void addDirectory(String relativePath) {
    final directory = Directory(pathJoin(buildDir.path, relativePath));
    if (!directory.existsSync()) return;
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is File) addFile(entity);
    }
  }

  addFile(File(pathJoin(buildDir.path, 'index.html')));
  addDirectory('productos');
  addDirectory('pagina');
  for (final slug in _trustPageDefinitions().keys) {
    addFile(File(pathJoin(buildDir.path, slug)));
  }

  final failures = <String>[];
  final normalizedStoreUrl = storeUrl.replaceAll(RegExp(r'/+$'), '');
  final normalizedStoreOrigin = _urlOrigin(normalizedStoreUrl);
  final sitemapFile = File(pathJoin(buildDir.path, 'sitemap.xml'));
  String? sitemap;
  final sitemapEntries = <(String, String, File)>[];
  if (!sitemapFile.existsSync()) {
    failures.add('/sitemap.xml no existe.');
  } else {
    sitemap = await sitemapFile.readAsString();
    if (!sitemap.contains('<urlset ') || !sitemap.contains('</urlset>')) {
      failures.add('/sitemap.xml no contiene un urlset completo.');
    }
    for (final match in RegExp(r'<loc>(.*?)</loc>').allMatches(sitemap)) {
      final value = _unescapeXml(match.group(1)!.trim());
      final uri = Uri.tryParse(value);
      if (uri == null ||
          !uri.hasScheme ||
          _urlOrigin(value) != normalizedStoreOrigin ||
          uri.hasQuery ||
          uri.hasFragment) {
        failures.add('sitemap.xml contiene una URL fuera del owner: $value.');
        continue;
      }
      final encodedPath = value.substring(normalizedStoreOrigin.length);
      final path = encodedPath.isEmpty ? '/' : encodedPath;
      final file = _snapshotFileForPublicPath(buildDir, path);
      if (!file.existsSync()) {
        failures.add('$path aparece en sitemap.xml sin snapshot generado.');
        continue;
      }
      addFile(file);
      sitemapEntries.add((value, path, file));
    }
  }

  for (final file in files.values) {
    final html = await file.readAsString();
    if (!RegExp(r'<html\b', caseSensitive: false).hasMatch(html)) continue;
    final relativePath =
        file.absolute.path.substring(buildDir.absolute.path.length);
    final h1Count =
        RegExp(r'<h1\b', caseSensitive: false).allMatches(html).length;
    final mainCount =
        RegExp(r'<main\b', caseSensitive: false).allMatches(html).length;
    if (h1Count != 1) {
      failures.add('$relativePath contiene $h1Count elementos h1.');
    }
    if (mainCount != 1) {
      failures.add('$relativePath contiene $mainCount elementos main.');
    }
    if (html.contains(unownedReturnPolicyType)) {
      failures.add(
        '$relativePath contiene $unownedReturnPolicyType sin dueño.',
      );
    }

    final localBusinessNodes = <Map<dynamic, dynamic>>[];
    final jsonLdScripts = RegExp(
      r'<script[^>]+type="application/ld\+json"[^>]*>(.*?)</script>',
      caseSensitive: false,
      dotAll: true,
    ).allMatches(html);
    if (jsonLdScripts.isEmpty) {
      failures.add('$relativePath no contiene JSON-LD.');
    }
    for (final script in jsonLdScripts) {
      try {
        final decoded = jsonDecode(script.group(1)!.trim());
        localBusinessNodes.addAll(
          _schemaNodesByType(decoded, 'LocalBusiness'),
        );
      } catch (error) {
        failures.add('$relativePath contiene JSON-LD inválido: $error');
      }
    }
    if (localBusinessNodes.length != 1) {
      failures.add(
        '$relativePath contiene ${localBusinessNodes.length} nodos '
        'LocalBusiness.',
      );
    } else if (expectedLocalBusinessIdentity != null) {
      final localBusiness = localBusinessNodes.single;
      for (final entry in expectedLocalBusinessIdentity.entries) {
        final actual = _readNestedJsonValue(localBusiness, entry.key);
        if (actual != entry.value) {
          failures.add(
            '$relativePath declara LocalBusiness.${entry.key}=$actual; '
            'esperaba ${entry.value}.',
          );
        }
      }
    }

    final semanticMain = RegExp(
      r'<main\b[^>]*>.*?</main>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(html)?.group(0);
    if (semanticMain != null) {
      for (final link in RegExp(
        r'href="([^"#?]+)"',
        caseSensitive: false,
      ).allMatches(semanticMain)) {
        final href = _unescapeXml(link.group(1)!.trim());
        final String? linkedPath;
        if (href.startsWith('/')) {
          linkedPath = href;
        } else {
          final uri = Uri.tryParse(href);
          final sameOwner = uri != null &&
              uri.hasScheme &&
              _urlOrigin(href) == normalizedStoreOrigin &&
              !uri.hasQuery &&
              !uri.hasFragment;
          if (!sameOwner) {
            linkedPath = null;
          } else {
            final encodedPath = href.substring(normalizedStoreOrigin.length);
            linkedPath = encodedPath.isEmpty ? '/' : encodedPath;
          }
        }
        if (linkedPath == null) continue;
        final linkedFile = _snapshotFileForPublicPath(buildDir, linkedPath);
        if (!linkedFile.existsSync()) {
          failures.add(
            '$relativePath enlaza $linkedPath sin snapshot generado.',
          );
        }
      }
    }
  }

  if (sitemap != null) {
    for (final entry in sitemapEntries) {
      final html = await entry.$3.readAsString();
      final canonical = _readHtmlCanonical(html);
      if (canonical != entry.$1) {
        failures.add(
          '${entry.$2} declara canonical=$canonical; '
          'sitemap.xml declara ${entry.$1}.',
        );
      }
      final robots = _readHtmlMetaContent(html, 'robots');
      if (robots != 'index,follow') {
        failures.add(
          '${entry.$2} aparece en sitemap.xml con robots=$robots.',
        );
      }
    }
    for (final entry in _trustPageDefinitions().entries) {
      final path = '/${entry.key}';
      final expected = staticTrustPagePaths.contains(path);
      final sitemapContains = sitemap
          .contains('<loc>${_escapeXml('$normalizedStoreUrl$path')}</loc>');
      if (sitemapContains != expected) {
        failures.add(
          '$path ${expected ? 'falta en' : 'aparece indebidamente en'} '
          'sitemap.xml.',
        );
      }
    }
  }

  for (final entry in _trustPageDefinitions().entries) {
    final path = '/${entry.key}';
    final file = File(pathJoin(buildDir.path, entry.key));
    if (!file.existsSync()) {
      failures.add('$path no tiene snapshot neutral/indexable.');
      continue;
    }
    final html = await file.readAsString();
    final expectedIndexable = staticTrustPagePaths.contains(path);
    final robots = _readHtmlMetaContent(html, 'robots');
    final expectedRobots =
        expectedIndexable ? 'index,follow' : 'noindex,follow';
    if (robots != expectedRobots) {
      failures.add('$path declara robots=$robots; esperaba $expectedRobots.');
    }
    final canonical = _readHtmlCanonical(html);
    final expectedCanonical = '$normalizedStoreUrl$path';
    if (canonical != expectedCanonical) {
      failures.add(
        '$path declara canonical=$canonical; esperaba $expectedCanonical.',
      );
    }

    final legalLinks = RegExp(
      r'href="/(nosotros|envios|devoluciones|terminos|privacidad)"',
      caseSensitive: false,
    ).allMatches(html);
    for (final match in legalLinks) {
      final linkedPath = '/${match.group(1)!.toLowerCase()}';
      if (!staticTrustPagePaths.contains(linkedPath)) {
        failures.add('$path enlaza la ruta legal no publicada $linkedPath.');
      }
    }
  }

  if (failures.isNotEmpty) {
    throw StateError(
      'Falló el contrato de artefactos SEO:\n- ${failures.join('\n- ')}',
    );
  }
}

Map<String, String> buildExpectedLocalBusinessIdentity(
  Map<String, String> settings, {
  required String storeUrl,
}) {
  return Map.unmodifiable({
    'name': _cleanText(
      _getSetting(settings, 'seo_business_name') ??
          _getSetting(settings, 'store_name') ??
          '',
    ),
    'legalName': _cleanText(
      _getSetting(settings, 'business_legal_name') ?? '',
    ),
    'taxID': _cleanText(_getSetting(settings, 'business_tax_id') ?? ''),
    'telephone': _cleanText(
      _getSetting(settings, 'seo_phone') ??
          _getSetting(settings, 'contact_phone') ??
          '',
    ),
    'email': _cleanText(
      _getSetting(settings, 'seo_email') ??
          _getSetting(settings, 'contact_email') ??
          '',
    ),
    'url': storeUrl.replaceAll(RegExp(r'/+$'), ''),
    'address.addressLocality': _cleanText(
      _getSetting(settings, 'seo_address_city') ??
          _getSetting(settings, 'seo_address_locality') ??
          '',
    ),
    'address.addressRegion':
        _cleanText(_getSetting(settings, 'seo_address_region') ?? ''),
    'address.postalCode':
        _cleanText(_getSetting(settings, 'seo_address_postal') ?? ''),
    'address.addressCountry':
        _cleanText(_getSetting(settings, 'seo_address_country') ?? ''),
  });
}

List<Map<dynamic, dynamic>> _schemaNodesByType(
  dynamic node,
  String expectedType,
) {
  final matches = <Map<dynamic, dynamic>>[];
  void visit(dynamic value) {
    if (value is List) {
      for (final child in value) {
        visit(child);
      }
      return;
    }
    if (value is! Map) return;
    if (value['@type'] == expectedType) matches.add(value);
    for (final child in value.values) {
      visit(child);
    }
  }

  visit(node);
  return matches;
}

String _readNestedJsonValue(Map<dynamic, dynamic> object, String dottedPath) {
  dynamic current = object;
  for (final segment in dottedPath.split('.')) {
    if (current is! Map || !current.containsKey(segment)) return '';
    current = current[segment];
  }
  return current?.toString() ?? '';
}

String? _readHtmlMetaContent(String html, String name) {
  final match = RegExp(
    '<meta[^>]+name="${RegExp.escape(name)}"[^>]+content="([^"]*)"[^>]*>',
    caseSensitive: false,
  ).firstMatch(html);
  return match?.group(1);
}

String? _readHtmlCanonical(String html) {
  final match = RegExp(
    r'<link[^>]+rel="canonical"[^>]+href="([^"]*)"[^>]*>',
    caseSensitive: false,
  ).firstMatch(html);
  return match?.group(1);
}

/// Sitemap inputs are public canonical paths only.
///
/// Search, sort, facet, Preview, Edit and ERP-mounted URLs are transient
/// application state. They must never become discovery entries; a valuable
/// combination needs its own editor-owned collection instead.
bool isIndexableStorefrontPathForSitemap(String rawPath) {
  final value = rawPath.trim();
  if (value.isEmpty) return false;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.hasScheme ||
      uri.host.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return false;
  }
  final path = uri.path;
  if (path.isEmpty || !path.startsWith('/')) return false;
  if (path == '/tienda' || path.startsWith('/tienda/')) return false;
  return true;
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

String _unescapeXml(String text) {
  return text
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&gt;', '>')
      .replaceAll('&lt;', '<')
      .replaceAll('&amp;', '&');
}

File _snapshotFileForPublicPath(Directory buildDir, String publicPath) {
  final normalized = publicPath == '/'
      ? '/'
      : '/${publicPath.replaceAll(RegExp(r'^/+|/+$'), '')}';
  if (normalized == '/') {
    return File(pathJoin(buildDir.path, 'index.html'));
  }
  if (normalized == '/productos') {
    return File(pathJoin(pathJoin(buildDir.path, 'productos'), 'index.html'));
  }

  var outputPath = buildDir.path;
  for (final segment in normalized.substring(1).split('/')) {
    if (segment.isEmpty || segment == '.' || segment == '..') {
      return File(pathJoin(buildDir.path, '.invalid-public-path'));
    }
    outputPath = pathJoin(outputPath, segment);
  }
  return File(outputPath);
}

class SeoSitemapUrl {
  final String loc;
  final DateTime? lastmod;
  final String? changefreq;
  final String? priority;
  final List<SeoSitemapImage> images;

  const SeoSitemapUrl({
    required this.loc,
    this.lastmod,
    this.changefreq,
    this.priority,
    this.images = const [],
  });
}

class SeoSitemapImage {
  final String loc;
  final String title;

  const SeoSitemapImage({
    required this.loc,
    required this.title,
  });
}

class SeoCategoryProjection {
  final String categoryId;
  final String name;
  final String fullPath;
  final String slug;
  final List<String> slugAliases;
  final String canonicalPath;
  final String displayTitle;
  final String description;
  final String seoTitle;
  final String seoDescription;
  final String imageUrl;
  final String socialImageUrl;
  final bool allowIndexing;
  final int sortOrder;
  final DateTime? updatedAt;
  final List<SeoCategoryProductProjection> products;

  const SeoCategoryProjection({
    required this.categoryId,
    required this.name,
    required this.fullPath,
    required this.slug,
    required this.slugAliases,
    required this.canonicalPath,
    required this.displayTitle,
    required this.description,
    required this.seoTitle,
    required this.seoDescription,
    required this.imageUrl,
    required this.socialImageUrl,
    required this.allowIndexing,
    required this.sortOrder,
    required this.updatedAt,
    required this.products,
  });

  int get productCount => products.length;
}

class SeoCategoryProductProjection {
  final String name;
  final String url;
  final DateTime? updatedAt;

  const SeoCategoryProductProjection({
    required this.name,
    required this.url,
    this.updatedAt,
  });
}

class SeoProductRedirectAlias {
  const SeoProductRedirectAlias({
    required this.productId,
    required this.aliasPath,
  });

  final String productId;
  final String aliasPath;
}

class SeoCategoryRouteAliasProjection {
  const SeoCategoryRouteAliasProjection({
    required this.categoryId,
    required this.name,
    required this.description,
    required this.imageUrl,
    required this.aliasPath,
    required this.canonicalPath,
  });

  final String categoryId;
  final String name;
  final String description;
  final String imageUrl;
  final String aliasPath;
  final String canonicalPath;
}

class _TrustPageDefinition {
  final String title;
  final String navLabel;

  const _TrustPageDefinition({
    required this.title,
    required this.navLabel,
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
  var redirectHtml = _replaceOrInsertMetaName(
    html,
    name: 'robots',
    content: 'noindex,follow',
  );
  redirectHtml = _replaceOrInsertMetaName(
    redirectHtml,
    name: 'googlebot',
    content: 'noindex,follow',
  );
  return redirectHtml.replaceFirst(
    closingHead,
    '$redirectMarkup$closingHead',
  );
}

Map<String, String> buildSeoProductCanonicalPathLedger({
  required Iterable<Map<String, dynamic>> publishedProducts,
}) {
  final canonicalPathByProductId = <String, String>{};
  for (final product in publishedProducts) {
    if (product['is_active'] != true ||
        product['is_published'] != true ||
        product['show_on_website'] != true) {
      continue;
    }
    final productId = (product['id'] ?? '').toString().trim();
    if (productId.isEmpty) continue;
    final canonicalPath = _publicProductPath(product);
    if (canonicalPath == '/productos') continue;
    canonicalPathByProductId[productId] = canonicalPath;
  }
  return Map.unmodifiable(canonicalPathByProductId);
}

List<SeoProductRedirectAlias> buildSeoProductRedirectAliases({
  required List<Map<String, dynamic>> products,
  required List<Map<String, dynamic>> aliases,
  required Map<String, String> canonicalPathByProductId,
}) {
  final redirectsBySource = <String, SeoProductRedirectAlias>{};

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
      () => SeoProductRedirectAlias(
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

List<SeoCategoryRouteAliasProjection>
    buildCanonicalCategoryRouteAliasProjections({
  required WebsiteCatalogPresentationRegistry presentationRegistry,
  required List<Map<String, dynamic>> activeCategories,
}) {
  final redirects = <SeoCategoryRouteAliasProjection>[];
  final categoryIdByClaim = <String, String>{};
  for (final row in activeCategories) {
    if (row['is_active'] != true || row['show_on_website'] != true) continue;
    final categoryId = (row['id'] ?? '').toString().trim();
    final name = _cleanText((row['name'] ?? '').toString());
    if (categoryId.isEmpty || name.isEmpty) continue;
    final presentation = presentationRegistry.forCategory(categoryId);
    if (presentation == null) continue;

    for (final claim in {presentation.slug, ...presentation.slugAliases}) {
      final previousCategoryId = categoryIdByClaim[claim];
      if (previousCategoryId != null && previousCategoryId != categoryId) {
        throw StateError(
          'Las categorías públicas $previousCategoryId y $categoryId '
          'comparten la ruta o alias $claim.',
        );
      }
      categoryIdByClaim[claim] = categoryId;
    }

    for (final alias in presentation.slugAliases) {
      final aliasPath = _normalizePublicPath('/productos/categoria/$alias');
      final canonicalPath = publicCategoryPath(
        presentation: presentation,
      );
      if (aliasPath.isEmpty || aliasPath == canonicalPath) continue;
      redirects.add(
        SeoCategoryRouteAliasProjection(
          categoryId: categoryId,
          name: name,
          description: _cleanText((row['description'] ?? '').toString()),
          imageUrl: (row['image_url'] ?? '').toString().trim(),
          aliasPath: aliasPath,
          canonicalPath: canonicalPath,
        ),
      );
    }
  }
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

Future<SeoFirebaseRedirectWritePlan> _buildFirebaseStorefrontRedirectPlan({
  required File firebaseConfigFile,
  required File manifestFile,
  required List<SeoProductRedirectAlias> productRedirects,
  required List<SeoCategoryRouteAliasProjection> categoryRedirects,
  required Map<String, String> canonicalPathByProductId,
  required String expectedPublicDirectory,
}) {
  return buildFirebaseStorefrontRedirectPlan(
    firebaseConfigFile: firebaseConfigFile,
    manifestFile: manifestFile,
    productRedirects: productRedirects,
    categoryRedirects: categoryRedirects,
    canonicalPathByProductId: canonicalPathByProductId,
    expectedPublicDirectory: expectedPublicDirectory,
  );
}

Future<SeoFirebaseRedirectWritePlan> buildFirebaseStorefrontRedirectPlan({
  required File firebaseConfigFile,
  required File manifestFile,
  required List<SeoProductRedirectAlias> productRedirects,
  required List<SeoCategoryRouteAliasProjection> categoryRedirects,
  required Map<String, String> canonicalPathByProductId,
  required String expectedPublicDirectory,
}) async {
  if (!firebaseConfigFile.existsSync()) {
    throw StateError(
      'No existe la configuración Firebase requerida: '
      '${firebaseConfigFile.path}.',
    );
  }

  final generatedBySource = <String, Map<String, dynamic>>{};

  void addGenerated(Map<String, dynamic> candidate) {
    final redirect = _validatedExactRedirect(
      candidate,
      owner: 'redirect generado',
    );
    final source = redirect['source']! as String;
    final previous = generatedBySource[source];
    if (previous != null && !_sameRedirect(previous, redirect)) {
      throw StateError(
        'Dos owners SEO intentan publicar destinos distintos para $source.',
      );
    }
    generatedBySource[source] = redirect;
  }

  for (final redirect in productRedirects) {
    // Exact Firebase rules are reserved for old public /productos/* URLs.
    if (!redirect.aliasPath.startsWith('/productos/')) continue;
    final destination = canonicalPathByProductId[redirect.productId];
    if (destination == null) {
      throw StateError(
        'El alias ${redirect.aliasPath} no tiene un destino canónico vigente.',
      );
    }
    if (destination == redirect.aliasPath) continue;
    addGenerated({
      'source': redirect.aliasPath,
      'destination': destination,
      'type': 301,
    });
  }
  for (final redirect in categoryRedirects) {
    addGenerated({
      'source': redirect.aliasPath,
      'destination': redirect.canonicalPath,
      'type': 301,
    });
  }

  final generated = generatedBySource.values.toList(growable: false)
    ..sort(
      (a, b) => a['source'].toString().compareTo(b['source'].toString()),
    );
  final generatedSources = generatedBySource.keys.toSet();
  for (final redirect in generated) {
    if (generatedSources.contains(redirect['destination'])) {
      throw StateError(
        'El redirect ${redirect['source']} apunta a otro alias '
        '${redirect['destination']}; los destinos deben ser canónicos.',
      );
    }
  }

  final previousBySource = <String, Map<String, dynamic>>{};
  if (manifestFile.existsSync()) {
    try {
      final previous = jsonDecode(await manifestFile.readAsString());
      if (previous is! Map ||
          previous.keys.map((key) => key.toString()).toSet().difference(
            const {'generatedAt', 'redirects'},
          ).isNotEmpty ||
          previous.length != 2 ||
          DateTime.tryParse((previous['generatedAt'] ?? '').toString()) ==
              null ||
          previous['redirects'] is! List) {
        throw const FormatException(
          'Se esperaba {generatedAt, redirects} con tipos válidos.',
        );
      }
      for (final item in previous['redirects'] as List) {
        if (item is! Map) {
          throw const FormatException(
            'Cada redirect del manifiesto debe ser un objeto.',
          );
        }
        final redirect = _validatedExactRedirect(
          Map<String, dynamic>.from(item),
          owner: 'manifiesto anterior',
        );
        final source = redirect['source']! as String;
        if (previousBySource.containsKey(source)) {
          throw FormatException(
            'El manifiesto contiene dos entradas para $source.',
          );
        }
        previousBySource[source] = redirect;
      }
    } catch (error) {
      throw FormatException(
        'El manifiesto de redirects generado es inválido y no puede '
        'reconciliarse de forma segura: $error',
        manifestFile.path,
      );
    }
  }

  final dynamic decodedConfig;
  try {
    decodedConfig = jsonDecode(await firebaseConfigFile.readAsString());
  } catch (error) {
    throw FormatException(
      'firebase.json no contiene JSON válido: $error',
      firebaseConfigFile.path,
    );
  }
  if (decodedConfig is! Map) {
    throw FormatException(
      'firebase.json debe contener un objeto raíz.',
      firebaseConfigFile.path,
    );
  }
  final config = Map<String, dynamic>.from(decodedConfig);
  final hosting = config['hosting'];
  if (hosting is! List || hosting.any((entry) => entry is! Map)) {
    throw FormatException(
      'firebase.json debe declarar hosting como una lista de objetos.',
      firebaseConfigFile.path,
    );
  }

  final storeIndexes = <int>[];
  for (var index = 0; index < hosting.length; index++) {
    final entry = hosting[index] as Map;
    if (entry['target'] == 'store') storeIndexes.add(index);
  }
  if (storeIndexes.length != 1) {
    throw StateError(
      'firebase.json debe contener exactamente un hosting target "store"; '
      'encontrados: ${storeIndexes.length}.',
    );
  }
  final storeIndex = storeIndexes.single;
  final storeHosting =
      Map<String, dynamic>.from(hosting[storeIndex] as Map<dynamic, dynamic>);
  hosting[storeIndex] = storeHosting;

  final configuredPublic = (storeHosting['public'] ?? '').toString().trim();
  if (configuredPublic.isEmpty ||
      Directory(configuredPublic).absolute.path !=
          Directory(expectedPublicDirectory).absolute.path) {
    throw StateError(
      'El target store publica "$configuredPublic", pero los snapshots fueron '
      'generados en "$expectedPublicDirectory".',
    );
  }

  final existingRaw = storeHosting['redirects'];
  if (existingRaw != null && existingRaw is! List) {
    throw FormatException(
      'hosting[target=store].redirects debe ser una lista.',
      firebaseConfigFile.path,
    );
  }
  final existingBySource = <String, Map<String, dynamic>>{};
  for (final item in (existingRaw as List? ?? const [])) {
    if (item is! Map) {
      throw FormatException(
        'Cada redirect de hosting[target=store] debe ser un objeto.',
        firebaseConfigFile.path,
      );
    }
    final redirect = _validatedExactRedirect(
      Map<String, dynamic>.from(item),
      owner: 'firebase.json',
    );
    final source = redirect['source']! as String;
    if (existingBySource.containsKey(source)) {
      throw StateError(
        'firebase.json contiene dos redirects para $source.',
      );
    }
    existingBySource[source] = redirect;
  }

  final retained = <Map<String, dynamic>>[];
  for (final entry in existingBySource.entries) {
    final previous = previousBySource[entry.key];
    if (previous != null) {
      if (!_sameRedirect(previous, entry.value)) {
        throw StateError(
          'firebase.json diverge del manifiesto anterior en ${entry.key}; '
          'no es seguro sobrescribirlo.',
        );
      }
      continue;
    }
    if (generatedBySource.containsKey(entry.key)) {
      throw StateError(
        'El redirect manual ${entry.key} colisiona con uno generado.',
      );
    }
    retained.add(entry.value);
  }
  for (final source in previousBySource.keys) {
    if (!existingBySource.containsKey(source)) {
      throw StateError(
        'El manifiesto anterior declara $source, pero firebase.json no lo '
        'contiene. Repara la divergencia antes de regenerar.',
      );
    }
  }
  retained.sort(
    (a, b) => a['source'].toString().compareTo(b['source'].toString()),
  );
  final finalRedirects = [...retained, ...generated];
  storeHosting['redirects'] = finalRedirects;

  const encoder = JsonEncoder.withIndent('  ');
  final manifest = {
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'redirects': generated,
  };
  final manifestContents = '${encoder.convert(manifest)}\n';
  final decodedManifest = jsonDecode(manifestContents) as Map<String, dynamic>;
  if (!_sameRedirectList(
    decodedManifest['redirects'] as List,
    generated,
  )) {
    throw StateError(
        'El manifiesto serializado no coincide con los redirects.');
  }

  return SeoFirebaseRedirectWritePlan(
    firebaseConfigFile: firebaseConfigFile,
    manifestFile: manifestFile,
    firebaseConfigContents: '${encoder.convert(config)}\n',
    manifestContents: manifestContents,
    redirectCount: generated.length,
  );
}

Map<String, dynamic> _validatedExactRedirect(
  Map<String, dynamic> value, {
  required String owner,
}) {
  const expectedKeys = {'source', 'destination', 'type'};
  final keys = value.keys.toSet();
  if (keys.length != expectedKeys.length || !keys.containsAll(expectedKeys)) {
    throw FormatException(
      '$owner debe contener exactamente source, destination y type.',
    );
  }
  final source = value['source'];
  final destination = value['destination'];
  final type = value['type'];
  if (source is! String ||
      destination is! String ||
      type != 301 ||
      !_isStrictPublicRedirectPath(source) ||
      !_isStrictPublicRedirectPath(destination) ||
      source == destination) {
    throw FormatException(
      '$owner contiene un source/destination/type inválido: $value.',
    );
  }
  return {
    'source': source,
    'destination': destination,
    'type': 301,
  };
}

bool _isStrictPublicRedirectPath(String value) {
  final trimmed = value.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      trimmed != value ||
      !trimmed.startsWith('/') ||
      trimmed.startsWith('//') ||
      uri.hasScheme ||
      uri.host.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.path == '/' ||
      uri.path.endsWith('/') ||
      RegExp(r'[*{}]').hasMatch(trimmed)) {
    return false;
  }
  try {
    for (final rawSegment in uri.path.substring(1).split('/')) {
      final segment = Uri.decodeComponent(rawSegment);
      if (segment.isEmpty || segment == '.' || segment == '..') return false;
    }
  } on FormatException {
    return false;
  }
  return true;
}

bool _sameRedirect(Map<String, dynamic> a, Map<String, dynamic> b) {
  return a['source'] == b['source'] &&
      a['destination'] == b['destination'] &&
      a['type'] == b['type'];
}

bool _sameRedirectList(
  List<dynamic> a,
  List<Map<String, dynamic>> b,
) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    final left = a[index];
    if (left is! Map ||
        !_sameRedirect(Map<String, dynamic>.from(left), b[index])) {
      return false;
    }
  }
  return true;
}

class SeoFirebaseRedirectWritePlan {
  const SeoFirebaseRedirectWritePlan({
    required this.firebaseConfigFile,
    required this.manifestFile,
    required this.firebaseConfigContents,
    required this.manifestContents,
    required this.redirectCount,
  });
  final File firebaseConfigFile;
  final File manifestFile;
  final String firebaseConfigContents;
  final String manifestContents;
  final int redirectCount;

  Future<void> apply() async {
    final configFile = firebaseConfigFile;
    final redirectsFile = manifestFile;
    final originalConfig = await configFile.readAsString();
    final manifestExisted = redirectsFile.existsSync();
    final originalManifest =
        manifestExisted ? await redirectsFile.readAsString() : null;
    redirectsFile.parent.createSync(recursive: true);
    final suffix = DateTime.now().microsecondsSinceEpoch;
    final configTemp = File('${configFile.path}.seo-$suffix.tmp');
    final manifestTemp = File('${redirectsFile.path}.seo-$suffix.tmp');
    try {
      await configTemp.writeAsString(firebaseConfigContents, flush: true);
      await manifestTemp.writeAsString(manifestContents, flush: true);
      await configTemp.rename(configFile.path);
      await manifestTemp.rename(redirectsFile.path);
      if (await configFile.readAsString() != firebaseConfigContents ||
          await redirectsFile.readAsString() != manifestContents) {
        throw StateError(
          'La verificación posterior de redirects no coincide con el plan.',
        );
      }
    } catch (_) {
      await configFile.writeAsString(originalConfig, flush: true);
      if (originalManifest != null) {
        await redirectsFile.writeAsString(originalManifest, flush: true);
      } else if (!manifestExisted && redirectsFile.existsSync()) {
        await redirectsFile.delete();
      }
      rethrow;
    } finally {
      if (configTemp.existsSync()) configTemp.deleteSync();
      if (manifestTemp.existsSync()) manifestTemp.deleteSync();
    }
  }
}

String _normalizePublicPath(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      uri.hasScheme ||
      uri.host.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      !trimmed.startsWith('/') ||
      trimmed.startsWith('//')) {
    return '';
  }
  final path = uri.path;
  if (path.isEmpty) return '';
  final normalized =
      path == '/' ? '/' : '/${path.replaceAll(RegExp(r'^/+|/+$'), '')}';
  if (normalized == '/') return normalized;
  try {
    for (final rawSegment in normalized.substring(1).split('/')) {
      final segment = Uri.decodeComponent(rawSegment);
      if (segment.isEmpty || segment == '.' || segment == '..') return '';
    }
  } on FormatException {
    return '';
  }
  return normalized;
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

String _removeMetaName(String html, {required String name}) {
  final re = RegExp(
    r'\s*<meta\s+name="' + RegExp.escape(name) + r'"\s+content="[^"]*"\s*/?>',
    caseSensitive: false,
  );
  return html.replaceAll(re, '');
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

  return html.replaceFirst(
    RegExp(r'</head>'),
    '  <meta name="$name" content="$esc">\n</head>',
  );
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

String _removeMetaProperty(String html, {required String property}) {
  final re = RegExp(
    r'\s*<meta\s+property="' +
        RegExp.escape(property) +
        r'"\s+content="[^"]*"\s*/?>',
    caseSensitive: false,
  );
  return html.replaceAll(re, '');
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

Map<String, String> _parseArgs(List<String> args) {
  const supported = {
    'build-dir',
    'tenant-id',
    'store-url',
    'expected-store-url',
    'product-scope',
    'publication-evidence-file',
  };
  final out = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (!arg.startsWith('--') || arg.length == 2) {
      throw FormatException('Argumento inesperado: $arg');
    }
    final key = arg.substring(2);
    if (!supported.contains(key)) {
      throw FormatException('Argumento no soportado: --$key');
    }
    if (out.containsKey(key)) {
      throw FormatException('Argumento duplicado: --$key');
    }

    final next = (i + 1) < args.length ? args[i + 1] : null;
    if (next == null || next.startsWith('--')) {
      throw FormatException('--$key requiere un valor explícito');
    }
    if (next.trim().isEmpty) {
      throw FormatException('--$key no puede estar vacío');
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
