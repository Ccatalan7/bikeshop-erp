import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_erp/public_store/models/public_commerce_product_projection.dart';

import '../../scripts/generate_product_seo_snapshots.dart' as snapshots;

void main() {
  test('SEO generators omit return facts without a structured editor owner',
      () {
    final generator =
        File('scripts/generate_product_seo_snapshots.dart').readAsStringSync();
    final indexSync = File('scripts/sync_seo_index.sh').readAsStringSync();

    for (final source in [generator, indexSync]) {
      expect(source, isNot(contains('MerchantReturnPolicy')));
      expect(source, isNot(contains('merchantReturnDays')));
      expect(source, isNot(contains('ReturnByMail')));
      expect(source, isNot(contains('ReturnFeesCustomerResponsibility')));
    }
  });

  group('canonical category SEO projection', () {
    test(
        'product paths include hidden active descendants while collections do not',
        () {
      final categoryRows = [
        _category(
          id: 'root',
          name: 'Transmisión',
          fullPath: 'Componentes / Transmisión',
        ),
        _category(
          id: 'hidden-child',
          name: 'Biela izquierda',
          fullPath: 'Componentes / Transmisión / Volantes / Biela izquierda',
          parentId: 'root',
          showOnWebsite: false,
        ),
        _category(
          id: 'inactive-child',
          name: 'Ruta antigua',
          fullPath: 'Componentes / Transmisión / Ruta antigua',
          parentId: 'root',
          isActive: false,
          showOnWebsite: false,
        ),
      ];
      final categoryPaths = snapshots.buildActiveCategoryPathMap(
        activeCategories: categoryRows,
      );
      final product = _product(
        id: 'p-hidden-child',
        categoryId: 'hidden-child',
        name: 'Biela izquierda aluminio',
        sku: 'BIELA-1',
      );

      expect(categoryPaths, {
        'root': 'Componentes / Transmisión',
        'hidden-child':
            'Componentes / Transmisión / Volantes / Biela izquierda',
      });
      expect(categoryPaths, isNot(contains('inactive-child')));

      final snapshotProjection = snapshots.projectSeoSnapshotCommerceProduct(
        product,
        categoryPath: categoryPaths[product['category_id']],
      );
      final runtimeProjection = PublicCommerceProductProjection.fromJson(
        product,
        categoryPath: categoryPaths[product['category_id']],
      );
      expect(
        snapshotProjection.categoryPath,
        'Componentes / Transmisión / Volantes / Biela izquierda',
      );
      expect(
        snapshotProjection.toContractJson(),
        runtimeProjection.toContractJson(),
      );

      final collections = snapshots.buildCanonicalCategorySeoProjections(
        products: [product],
        activeCategories: categoryRows,
        presentationRegistry: const WebsiteCatalogPresentationRegistry({}),
        storeUrl: 'https://vinabike.cl',
      );
      expect(
        collections.map((category) => category.categoryId),
        ['root'],
      );
    });

    test('uses published stable IDs, saved presentation and eligible products',
        () {
      final registry = WebsiteCatalogPresentationRegistry({
        'root': WebsiteCatalogPresentation(
          categoryId: 'root',
          slug: 'componentes-profesionales',
          slugAliases: const ['componentes'],
          heroTitle: 'Componentes',
          heroDescription: 'Componentes publicados por Viñabike.',
          heroImageUrl: 'https://cdn.example.test/componentes.webp',
          seoTitle: 'Componentes para bicicleta',
          seoDescription: 'Compra componentes publicados y compatibles.',
          socialImageUrl: 'https://cdn.example.test/componentes-social.webp',
          allowIndexing: false,
        ),
      });
      final categories = snapshots.buildCanonicalCategorySeoProjections(
        products: [
          _product(
            id: 'p-root',
            categoryId: 'root',
            name: 'Producto raíz',
            sku: 'ROOT-1',
          ),
          _product(
            id: 'p-child',
            categoryId: 'child',
            name: 'Nombre interno',
            websiteName: 'Cadena visible',
            sku: 'CHAIN-1',
          ),
          _product(
            id: 'p-hidden',
            categoryId: 'hidden',
            name: 'No debe indexar su categoría',
            sku: 'HIDDEN-1',
          ),
          {
            ..._product(
              id: 'p-name-only',
              categoryId: '',
              name: 'Cámara 29 material inventado',
              sku: 'NAME-1',
            ),
            'category_name': 'Categoría fabricada desde el título',
          },
        ],
        activeCategories: [
          _category(
            id: 'root',
            name: 'Componentes',
            fullPath: 'Componentes',
            sortOrder: 1,
          ),
          _category(
            id: 'child',
            name: 'Cadenas',
            fullPath: 'Componentes / Transmisión / Cadenas',
            parentId: 'root',
            sortOrder: 2,
          ),
          _category(
            id: 'empty',
            name: 'Vacía',
            fullPath: 'Vacía',
            sortOrder: 3,
          ),
          _category(
            id: 'hidden',
            name: 'Oculta',
            fullPath: 'Componentes / Oculta',
            parentId: 'root',
            showOnWebsite: false,
          ),
          _category(
            id: 'inactive',
            name: 'Inactiva',
            fullPath: 'Inactiva',
            isActive: false,
          ),
        ],
        presentationRegistry: registry,
        storeUrl: 'https://vinabike.cl',
      );

      expect(categories.map((category) => category.categoryId), [
        'root',
        'child',
      ]);
      final root = categories.first;
      expect(root.slug, 'componentes-profesionales');
      expect(root.slugAliases, const ['componentes']);
      expect(
          root.canonicalPath, '/productos/categoria/componentes-profesionales');
      expect(root.displayTitle, 'Componentes');
      expect(root.description, 'Componentes publicados por Viñabike.');
      expect(root.imageUrl, 'https://cdn.example.test/componentes.webp');
      expect(root.seoTitle, 'Componentes para bicicleta');
      expect(
        root.seoDescription,
        'Compra componentes publicados y compatibles.',
      );
      expect(
        root.socialImageUrl,
        'https://cdn.example.test/componentes-social.webp',
      );
      expect(root.allowIndexing, isFalse);
      expect(root.productCount, 3);
      expect(
        root.products.map((product) => product.name),
        [
          'Producto raíz',
          'Cadena visible',
          'No debe indexar su categoría',
        ],
      );

      final child = categories.last;
      expect(child.slug, 'cadenas');
      expect(child.productCount, 1);
      expect(child.products.single.name, 'Cadena visible');
    });

    test('fails closed when two non-empty public categories share a slug', () {
      final registry = WebsiteCatalogPresentationRegistry({
        'a': WebsiteCatalogPresentation(categoryId: 'a', slug: 'repetida'),
        'b': WebsiteCatalogPresentation(categoryId: 'b', slug: 'repetida'),
      });

      expect(
        () => snapshots.buildCanonicalCategorySeoProjections(
          products: [
            _product(id: 'p-a', categoryId: 'a', name: 'A', sku: 'A-1'),
            _product(id: 'p-b', categoryId: 'b', name: 'B', sku: 'B-1'),
          ],
          activeCategories: [
            _category(id: 'a', name: 'A', fullPath: 'A'),
            _category(id: 'b', name: 'B', fullPath: 'B'),
          ],
          presentationRegistry: registry,
          storeUrl: 'https://vinabike.cl',
        ),
        throwsStateError,
      );
    });

    test('fails closed when a current slug collides with a category alias', () {
      final registry = WebsiteCatalogPresentationRegistry({
        'a': WebsiteCatalogPresentation(
          categoryId: 'a',
          slug: 'componentes',
          slugAliases: const ['repuestos'],
        ),
        'b': WebsiteCatalogPresentation(
          categoryId: 'b',
          slug: 'repuestos',
        ),
      });

      expect(
        () => snapshots.buildCanonicalCategorySeoProjections(
          products: [
            _product(id: 'p-a', categoryId: 'a', name: 'A', sku: 'A-1'),
            _product(id: 'p-b', categoryId: 'b', name: 'B', sku: 'B-1'),
          ],
          activeCategories: [
            _category(id: 'a', name: 'A', fullPath: 'A'),
            _category(id: 'b', name: 'B', fullPath: 'B'),
          ],
          presentationRegistry: registry,
          storeUrl: 'https://vinabike.cl',
        ),
        throwsStateError,
      );
    });

    test('projects durable aliases only for generated product collections', () {
      final registry = WebsiteCatalogPresentationRegistry({
        'category-1': WebsiteCatalogPresentation(
          categoryId: 'category-1',
          slug: 'mantencion',
          slugAliases: const ['servicio-taller'],
        ),
      });

      final aliases = snapshots.buildCanonicalCategoryRouteAliasProjections(
        presentationRegistry: registry,
        activeCategories: [
          _category(
            id: 'category-1',
            name: 'Mantención',
            fullPath: 'Servicios / Mantención',
          ),
        ],
      );

      expect(
        aliases.map((alias) => alias.aliasPath),
        [
          '/productos/categoria/servicio-taller',
        ],
      );
      expect(
        aliases.map((alias) => alias.canonicalPath),
        [
          '/productos/categoria/mantencion',
        ],
      );
    });
  });

  test('sitemap accepts canonical public paths only', () {
    expect(
      snapshots.isIndexableStorefrontPathForSitemap(
        '/productos/categoria/camaras',
      ),
      isTrue,
    );
    expect(
      snapshots.isIndexableStorefrontPathForSitemap(
        '/productos/categoria/camaras?brand=brand-1&sort=price_asc',
      ),
      isFalse,
    );
    expect(
      snapshots.isIndexableStorefrontPathForSitemap(
        '/productos?q=camara&preview=true',
      ),
      isFalse,
    );
    expect(
      snapshots.isIndexableStorefrontPathForSitemap(
        '/tienda/productos/categoria/camaras',
      ),
      isFalse,
    );
    expect(
      snapshots.isIndexableStorefrontPathForSitemap(
        'https://vinabike.cl/productos',
      ),
      isFalse,
    );
  });

  test('sitemap emits lastmod only from a factual updated_at value', () {
    final sitemap = snapshots.buildSeoSitemapXml([
      const snapshots.SeoSitemapUrl(
        loc: 'https://taller.example',
        changefreq: 'weekly',
      ),
      snapshots.SeoSitemapUrl(
        loc: 'https://taller.example/productos/producto/SKU-1',
        lastmod: DateTime.utc(2026, 7, 27, 23, 59),
        changefreq: 'weekly',
      ),
    ]);

    expect(
      RegExp(r'<lastmod>').allMatches(sitemap),
      hasLength(1),
    );
    expect(sitemap, contains('<lastmod>2026-07-27</lastmod>'));
    final homeEntry = RegExp(
      r'<url>\s*<loc>https://taller\.example</loc>(.*?)</url>',
      dotAll: true,
    ).firstMatch(sitemap)!.group(1)!;
    expect(homeEntry, isNot(contains('<lastmod>')));

    final source = File(
      'scripts/generate_product_seo_snapshots.dart',
    ).readAsStringSync();
    expect(
      source,
      isNot(contains("_parseDateTime(product['created_at'])")),
    );
    expect(source, isNot(contains('lastmod ?? now')));
  });

  test('home always receives canonical, robots and global SEO owner values',
      () {
    final html = snapshots.buildHomepageSeoHtml(
      baseHtml: '''
<!doctype html>
<html><head>
  <title>Viejo</title>
  <meta name="title" content="Viejo">
  <meta name="description" content="Vieja">
  <link rel="canonical" href="https://old.example">
  <meta property="og:url" content="https://old.example">
  <meta property="og:title" content="Viejo">
  <meta property="og:description" content="Vieja">
  <meta name="twitter:url" content="https://old.example">
  <meta name="twitter:title" content="Viejo">
  <meta name="twitter:description" content="Vieja">
</head><body>
  <noscript><main class="storefront-nojs-fallback"><h1>Inicio</h1></main></noscript>
</body></html>
''',
      storeUrl: 'https://taller.example',
      storeName: 'Taller',
      globalTitle: 'Título global',
      globalDescription: 'Descripción global',
    );

    expect(
      html,
      contains('<link rel="canonical" href="https://taller.example">'),
    );
    expect(html, contains('<meta name="robots" content="index,follow">'));
    expect(html, contains('<meta name="googlebot" content="index,follow">'));
    expect(html, contains('<title>Título global</title>'));
    expect(html, contains('content="Descripción global"'));
  });

  group('published dynamic CMS SEO snapshots', () {
    test('projects non-trust published pages with visible textual content', () {
      final pages = [
        {
          'id': 'cms-guide',
          'slug': 'guía de-tallas',
          'title': 'Guía de tallas',
          'meta_title': 'Cómo elegir la talla de bicicleta',
          'meta_description': 'Compara medidas antes de elegir tu bicicleta.',
          'meta_keywords': 'talla bicicleta, guía de tallas',
          'og_image_url': 'https://cdn.vinabike.cl/guia.jpg',
          'is_published': true,
          'updated_at': '2026-07-28T12:00:00Z',
        },
        {
          'id': 'cms-fallback',
          'slug': 'cuidado-basico',
          'title': 'Cuidado básico',
          'is_published': true,
        },
        {
          'id': 'cms-empty',
          'slug': 'solo-imagen',
          'title': 'Solo imagen',
          'is_published': true,
        },
        {
          'id': 'cms-draft',
          'slug': 'borrador',
          'title': 'Borrador',
          'is_published': false,
        },
        {
          'id': 'cms-direct',
          'slug': 'terminos',
          'title': 'Términos',
          'is_published': true,
        },
        {
          'id': 'cms-contact',
          'slug': 'contacto',
          'title': 'Contacto',
          'is_published': true,
        },
      ];
      final blocks = <String, List<Map<String, dynamic>>>{
        'cms-guide': [
          {
            'block_type': 'hero',
            'block_data': {
              'title': 'Encuentra tu talla',
              'subtitle': 'Mide tu estatura y entrepierna antes de comprar.',
              'image_url': 'https://cdn.vinabike.cl/hero.jpg',
            },
            'order_index': 0,
            'is_visible': true,
            'updated_at': '2026-07-28T14:00:00Z',
          },
          {
            'block_type': 'text',
            'block_data': {'content': 'Texto que no debe publicarse.'},
            'order_index': 1,
            'is_visible': false,
          },
        ],
        'cms-fallback': [
          {
            'block_type': 'text',
            'block_data': {
              'heading': 'Limpieza después de cada salida',
              'content': 'Seca la transmisión y revisa la presión.',
            },
            'is_visible': true,
          },
        ],
        'cms-empty': [
          {
            'block_type': 'gallery',
            'block_data': {
              'image_url': 'https://cdn.vinabike.cl/gallery.jpg',
            },
            'is_visible': true,
          },
        ],
        'cms-draft': [
          {
            'block_type': 'text',
            'block_data': {'content': 'Contenido todavía privado.'},
            'is_visible': true,
          },
        ],
        'cms-direct': [
          {
            'block_type': 'text',
            'block_data': {'content': 'Contenido legal.'},
            'is_visible': true,
          },
        ],
        'cms-contact': [
          {
            'block_type': 'text',
            'block_data': {'content': 'Escríbenos mediante el formulario.'},
            'is_visible': true,
          },
        ],
      };

      final projections = snapshots.buildPublishedDynamicCmsSeoProjections(
        pages: pages,
        pageBlocks: blocks,
        storeUrl: 'https://vinabike.cl',
        storeName: 'Viñabike',
        globalDescription: 'Descripción global.',
        globalKeywords: 'bicicletas, taller',
        globalImageUrl: 'https://cdn.vinabike.cl/default.jpg',
        settingsUpdatedAt: DateTime.utc(2026, 7, 28, 13),
      );

      expect(
        projections.map((page) => page.canonicalPath),
        [
          '/contacto',
          '/pagina/cuidado-basico',
          '/pagina/gu%C3%ADa%20de-tallas',
        ],
      );
      final guide = projections.last;
      expect(guide.seoTitle, 'Cómo elegir la talla de bicicleta');
      expect(
        guide.description,
        'Compara medidas antes de elegir tu bicicleta.',
      );
      expect(guide.keywords, 'talla bicicleta, guía de tallas');
      expect(guide.ogImageUrl, 'https://cdn.vinabike.cl/guia.jpg');
      expect(guide.updatedAt, DateTime.utc(2026, 7, 28, 14));
      expect(guide.bodyHtml, contains('Encuentra tu talla'));
      expect(guide.bodyHtml, contains('Mide tu estatura'));
      expect(guide.bodyHtml, isNot(contains('no debe publicarse')));

      final fallback = projections[1];
      expect(
        fallback.description,
        'Limpieza después de cada salida '
        'Seca la transmisión y revisa la presión.',
      );
      expect(fallback.keywords, 'bicicletas, taller');
      expect(fallback.ogImageUrl, 'https://cdn.vinabike.cl/default.jpg');
    });

    test('renders canonical metadata, WebPage JSON-LD and CMS text', () {
      final projection = snapshots.PublishedDynamicCmsSeoProjection(
        pageId: 'cms-guide',
        canonicalPath: '/pagina/guia',
        pageTitle: 'Guía de compra',
        seoTitle: 'Guía para comprar bicicleta',
        description: 'Información comprobable para elegir una bicicleta.',
        keywords: 'comprar bicicleta, guía',
        ogImageUrl: 'https://cdn.vinabike.cl/guia.jpg',
        bodyHtml:
            '<section><h2>Qué debes medir</h2><p>Estatura y entrepierna.</p></section>',
        updatedAt: DateTime.utc(2026, 7, 28),
      );
      const baseHtml = '''
<!doctype html>
<html>
<head>
  <title>Base</title>
  <meta name="title" content="Base">
  <meta name="description" content="Base">
  <meta name="robots" content="index,follow">
  <meta name="googlebot" content="index,follow">
  <link rel="canonical" href="https://vinabike.cl">
  <meta property="og:type" content="website">
  <meta property="og:url" content="https://vinabike.cl">
  <meta property="og:title" content="Base">
  <meta property="og:description" content="Base">
  <meta name="twitter:url" content="https://vinabike.cl">
  <meta name="twitter:title" content="Base">
  <meta name="twitter:description" content="Base">
</head>
<body><script src="main.dart.js"></script></body>
</html>
''';

      final html = snapshots.buildStaticCmsPageSnapshotHtml(
        baseHtml: baseHtml,
        storeUrl: 'https://vinabike.cl',
        storeName: 'Viñabike',
        page: projection,
        availablePublicPaths: const {
          '/productos',
          '/servicios',
        },
      );

      expect(html, contains('<title>Guía para comprar bicicleta</title>'));
      expect(
        html,
        contains(
          '<link rel="canonical" href="https://vinabike.cl/pagina/guia">',
        ),
      );
      expect(html, contains('name="keywords"'));
      expect(html, contains('content="comprar bicicleta, guía"'));
      expect(html, contains('property="og:image"'));
      expect(html, contains('https://cdn.vinabike.cl/guia.jpg'));
      expect(html, contains('"@type":"WebPage"'));
      expect(html, contains('"url":"https://vinabike.cl/pagina/guia"'));
      expect(html, contains('Qué debes medir'));
      expect(html, contains('Estatura y entrepierna.'));
      expect(html, contains('href="/servicios"'));
      expect(html, isNot(contains('href="/contacto"')));
      expect(RegExp(r'<h1\b', caseSensitive: false).allMatches(html),
          hasLength(1));
      expect(
        RegExp(r'<main\b', caseSensitive: false).allMatches(html),
        hasLength(1),
      );
    });

    test('known unavailable direct routes receive a neutral noindex snapshot',
        () {
      const baseHtml = '''
<!doctype html>
<html>
<head>
  <title>Portada heredada</title>
  <meta name="title" content="Portada heredada">
  <meta name="description" content="Descripción de portada">
  <meta name="robots" content="index,follow">
  <meta name="googlebot" content="index,follow">
  <link rel="canonical" href="https://vinabike.cl">
  <meta property="og:type" content="website">
  <meta property="og:url" content="https://vinabike.cl">
  <meta property="og:title" content="Portada heredada">
  <meta property="og:description" content="Descripción de portada">
  <meta property="og:image" content="https://vinabike.cl/home.jpg">
  <meta name="twitter:url" content="https://vinabike.cl">
  <meta name="twitter:title" content="Portada heredada">
  <meta name="twitter:description" content="Descripción de portada">
  <meta name="twitter:image" content="https://vinabike.cl/home.jpg">
</head>
<body>
  <noscript><main><h1>Portada heredada</h1></main></noscript>
  <script src="main.dart.js"></script>
</body>
</html>
''';

      for (final route in const {
        '/servicios': 'Servicios',
        '/contacto': 'Contacto',
      }.entries) {
        final html = snapshots.buildUnavailableStaticCmsPageSnapshotHtml(
          baseHtml: baseHtml,
          storeUrl: 'https://vinabike.cl',
          storeName: 'Viñabike',
          canonicalPath: route.key,
          pageTitle: route.value,
        );

        expect(
          html,
          contains(
            '<link rel="canonical" href="https://vinabike.cl${route.key}">',
          ),
        );
        expect(html, contains('<meta name="robots" content="noindex,follow">'));
        expect(
          html,
          contains('<meta name="googlebot" content="noindex,follow">'),
        );
        expect(html, contains('<h1>${route.value}</h1>'));
        expect(html, isNot(contains('Portada heredada</h1>')));
        expect(html, isNot(contains('https://vinabike.cl/home.jpg')));
        expect(
          RegExp(r'<main\b', caseSensitive: false).allMatches(html),
          hasLength(1),
        );
        expect(
          RegExp(r'<h1\b', caseSensitive: false).allMatches(html),
          hasLength(1),
        );
      }
    });
  });

  test('website page/block snapshot fails when owner revision changes',
      () async {
    final stablePages = [
      {
        'id': 'page-1',
        'slug': 'contacto',
        'title': 'Contacto',
        'is_published': true,
        'updated_at': '2026-07-28T12:00:00Z',
      },
    ];
    var blockRead = 0;
    Future<List<Map<String, dynamic>>> pageLoader(Uri _) async => stablePages;
    Future<List<Map<String, dynamic>>> changingBlockLoader(Uri _) async {
      blockRead++;
      return [
        {
          'id': 'block-1',
          'page_id': 'page-1',
          'block_type': 'text',
          'block_data': {
            'content': blockRead == 1 ? 'Primera revisión' : 'Segunda revisión',
          },
          'order_index': 0,
          'is_visible': true,
          'updated_at': '2026-07-28T12:00:0${blockRead}Z',
        },
      ];
    }

    await expectLater(
      snapshots.fetchConsistentSeoWebsiteContentSnapshot(
        supabaseUrl: 'https://project.example',
        tenantId: 'tenant-1',
        serviceRoleKey: 'not-used-by-loader',
        pageLoader: pageLoader,
        blockPageLoader: changingBlockLoader,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test(
      'complete SEO owner snapshot is deterministic and rejects every mutated source',
      () async {
    final baseline = _seoOwnerSourceSnapshot();
    final reordered = _seoOwnerSourceSnapshot(reverseRows: true);
    expect(reordered.revision, baseline.revision);

    final mutations = <String, snapshots.SeoOwnerSourceSnapshot>{
      'settings': _seoOwnerSourceSnapshot(settingValue: 'Tienda actualizada'),
      'presentations':
          _seoOwnerSourceSnapshot(presentationValue: '{"version":2}'),
      'product price': _seoOwnerSourceSnapshot(price: 12000),
      'availability': _seoOwnerSourceSnapshot(stock: 4),
      'brand': _seoOwnerSourceSnapshot(brandName: 'Marca actualizada'),
      'category':
          _seoOwnerSourceSnapshot(categoryName: 'Categoría actualizada'),
      'alias': _seoOwnerSourceSnapshot(aliasPath: '/productos/alias-nuevo'),
      'page': _seoOwnerSourceSnapshot(pageTitle: 'Página actualizada'),
      'block': _seoOwnerSourceSnapshot(blockContent: 'Bloque actualizado'),
    };

    for (final mutation in mutations.entries) {
      var readCount = 0;
      await expectLater(
        snapshots.fetchConsistentSeoOwnerSourceSnapshot(
          readOnce: () async => readCount++ == 0 ? baseline : mutation.value,
        ),
        throwsA(isA<StateError>()),
        reason: mutation.key,
      );
    }

    final changedAfterGeneration =
        _seoOwnerSourceSnapshot(stock: 1, blockContent: 'Cambio final');
    await expectLater(
      snapshots.assertSeoOwnerSourceSnapshotIsCurrent(
        expected: baseline,
        readOnce: () async => changedAfterGeneration,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('factual lastmod uses the newest available contributor or stays absent',
      () {
    expect(
      snapshots.maxFactualSeoUpdatedAt([
        DateTime.utc(2026, 7, 27, 18),
        null,
        DateTime.utc(2026, 7, 28, 9),
        DateTime.utc(2026, 7, 28, 8),
      ]),
      DateTime.utc(2026, 7, 28, 9),
    );
    expect(
      snapshots.maxFactualSeoUpdatedAt(const [null, null]),
      isNull,
    );
  });

  test('snapshot source does not manufacture category pages or wheel SEO', () {
    final source = File(
      'scripts/generate_product_seo_snapshots.dart',
    ).readAsStringSync();

    expect(source, contains('websiteCatalogPresentationsSettingKey'));
    expect(source, contains("product['category_id']"));
    expect(source, contains('_fetchActiveProductCategories'));
    expect(source, isNot(contains('_buildProductCategories')));
    expect(source, isNot(contains('_categoryWheelSizeSummary')));
    expect(source, isNot(contains('_productSearchKind')));
    expect(source, isNot(contains('category.products.length >= 2')));
    expect(source, contains('presentation.seoTitle'));
    expect(source, contains('presentation.seoDescription'));
    expect(source, contains('presentation.socialImageUrl'));
    expect(source, contains('presentation.slugAliases'));
    expect(source, contains('for (final alias in presentation.slugAliases)'));
    expect(
        source, isNot(contains('for (final services in const [false, true])')));
    expect(source, contains("'/productos/categoria/\$alias'"));
    expect(
      source,
      contains('buildCanonicalCategoryRouteAliasProjections'),
    );
    expect(source, contains('allowIndexing: false'));
    expect(source, contains('_buildFirebaseStorefrontRedirectPlan'));
    expect(source, contains("'type': 301"));
    expect(source, contains("content: allowIndexing ? 'index,follow'"));
    expect(source, contains("content: 'index,follow'"));
    expect(source, contains("content: 'noindex,follow'"));
    expect(source, contains('if (!category.allowIndexing) continue;'));
  });

  test('snapshot generation consumes configured tenant identity only', () {
    final source = File(
      'scripts/generate_product_seo_snapshots.dart',
    ).readAsStringSync();

    expect(source, contains("_getSetting(settings, 'store_url')"));
    expect(source, contains('--expected-store-url'));
    expect(source, contains('expectedStoreUrl != storeUrl'));
    expect(source, isNot(contains("?? 'https://vinabike.cl'")));
    expect(source, isNot(contains("?? 'Vinabike'")));
    expect(source, isNot(contains("? 'Viñabike' :")));
    expect(
      source,
      isNot(contains("replaceAll('vinabikechile@gmail.com'")),
    );
    expect(
      source,
      isNot(contains('Ver producto en Viñabike')),
    );
    expect(
      source,
      isNot(contains('Ver catálogo completo de Viñabike')),
    );
    expect(
      source,
      isNot(contains(
        'Catálogo online de bicicletas, repuestos y accesorios en Viña del Mar.',
      )),
    );
    expect(source, contains('El manifiesto de redirects generado es inválido'));
    expect(
      source.indexOf('await firebaseRedirectPlan.apply()'),
      greaterThan(source.indexOf('await validateGeneratedSeoArtifacts(')),
    );
  });

  test('Firebase redirects fail closed and produce an exact owned manifest',
      () async {
    final root =
        await Directory.systemTemp.createTemp('seo-redirect-contract-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final buildDir = Directory('${root.path}/build/web_store')
      ..createSync(recursive: true);
    final configFile = File('${root.path}/firebase.json');
    final manifestFile = File('${root.path}/redirects.json');
    const aliasPath = '/productos/old-product-id';
    const canonicalPath = '/productos/producto-publicado/SKU-1';

    await configFile.writeAsString(
      jsonEncode({
        'hosting': [
          {
            'target': 'store',
            'public': buildDir.path,
            'redirects': <Map<String, dynamic>>[],
          },
        ],
      }),
    );
    final plan = await snapshots.buildFirebaseStorefrontRedirectPlan(
      firebaseConfigFile: configFile,
      manifestFile: manifestFile,
      productRedirects: const [
        snapshots.SeoProductRedirectAlias(
          productId: 'product-1',
          aliasPath: aliasPath,
        ),
      ],
      categoryRedirects: const [],
      canonicalPathByProductId: const {'product-1': canonicalPath},
      expectedPublicDirectory: buildDir.path,
    );

    expect(plan.redirectCount, 1);
    expect(await manifestFile.exists(), isFalse);
    await plan.apply();
    final config =
        jsonDecode(await configFile.readAsString()) as Map<String, dynamic>;
    final manifest =
        jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
    final store = (config['hosting'] as List).single as Map<String, dynamic>;
    expect(store['redirects'], manifest['redirects']);
    expect(manifest.keys.toSet(), {'generatedAt', 'redirects'});
    expect(manifest['redirects'], [
      {
        'source': aliasPath,
        'destination': canonicalPath,
        'type': 301,
      },
    ]);

    await manifestFile.writeAsString(
      jsonEncode({
        'generatedAt': DateTime.utc(2026, 7, 28).toIso8601String(),
        'redirects': 'schema roto',
      }),
    );
    await expectLater(
      snapshots.buildFirebaseStorefrontRedirectPlan(
        firebaseConfigFile: configFile,
        manifestFile: manifestFile,
        productRedirects: const [],
        categoryRedirects: const [],
        canonicalPathByProductId: const {},
        expectedPublicDirectory: buildDir.path,
      ),
      throwsA(isA<FormatException>()),
    );

    await manifestFile.delete();
    await configFile.writeAsString(
      jsonEncode({
        'hosting': [
          {
            'target': 'store',
            'public': buildDir.path,
            'redirects': [
              {
                'source': aliasPath,
                'destination': '/productos/manual/SKU-2',
                'type': 301,
              },
            ],
          },
        ],
      }),
    );
    await expectLater(
      snapshots.buildFirebaseStorefrontRedirectPlan(
        firebaseConfigFile: configFile,
        manifestFile: manifestFile,
        productRedirects: const [
          snapshots.SeoProductRedirectAlias(
            productId: 'product-1',
            aliasPath: aliasPath,
          ),
        ],
        categoryRedirects: const [],
        canonicalPathByProductId: const {'product-1': canonicalPath},
        expectedPublicDirectory: buildDir.path,
      ),
      throwsA(isA<StateError>()),
    );

    await configFile.writeAsString(
      jsonEncode({
        'hosting': [
          {
            'target': 'store',
            'public': buildDir.path,
            'redirects': <Map<String, dynamic>>[],
          },
        ],
      }),
    );
    await expectLater(
      snapshots.buildFirebaseStorefrontRedirectPlan(
        firebaseConfigFile: configFile,
        manifestFile: manifestFile,
        productRedirects: const [
          snapshots.SeoProductRedirectAlias(
            productId: 'product-1',
            aliasPath: aliasPath,
          ),
        ],
        categoryRedirects: const [],
        canonicalPathByProductId: const {
          'product-1': 'https://external.example/product',
        },
        expectedPublicDirectory: buildDir.path,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('artifact validator rejects sitemap routes without snapshots', () async {
    final buildDir = await Directory.systemTemp.createTemp(
      'storefront-seo-artifact-contract-',
    );
    addTearDown(() async {
      if (await buildDir.exists()) await buildDir.delete(recursive: true);
    });
    await File('${buildDir.path}/index.html').writeAsString('''
<!doctype html>
<html>
<head>
  <link rel="canonical" href="https://taller-norte.example">
  <meta name="robots" content="index,follow">
  <script type="application/ld+json">
    {"@context":"https://schema.org","@type":"LocalBusiness","name":"Taller Norte"}
  </script>
</head>
<body><main><h1>Taller Norte</h1></main></body>
</html>
''');
    await File('${buildDir.path}/sitemap.xml').writeAsString('''
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://taller-norte.example</loc></url>
  <url><loc>https://taller-norte.example/contacto</loc></url>
</urlset>
''');

    await expectLater(
      snapshots.validateGeneratedSeoArtifacts(
        buildDir: buildDir,
        storeUrl: 'https://taller-norte.example',
        staticTrustPagePaths: const {},
      ),
      throwsA(
        predicate(
          (error) => error
              .toString()
              .contains('/contacto aparece en sitemap.xml sin snapshot'),
        ),
      ),
    );
  });

  test('trust snapshots and sitemap routes require a published page owner', () {
    final paths = snapshots.buildPublishedStaticTrustPagePaths(
      pages: [
        {
          'id': 'terms-page',
          'slug': 'terminos',
          'is_published': true,
        },
        {
          'id': 'privacy-page',
          'slug': 'privacidad',
          'is_published': false,
        },
        {
          'id': 'invented-page',
          'slug': 'pagina-inventada',
          'is_published': true,
        },
      ],
      pageBlocks: {
        'terms-page': [
          {
            'id': 'terms-block',
            'block_type': 'text',
            'block_data': {'content': 'Condición publicada por el editor.'},
            'is_visible': true,
          },
        ],
        'privacy-page': [
          {
            'id': 'privacy-block',
            'block_type': 'text',
            'block_data': {'content': 'Borrador privado.'},
            'is_visible': true,
          },
        ],
        'invented-page': [
          {
            'id': 'invented-block',
            'block_type': 'text',
            'block_data': {'content': 'No es una ruta legal conocida.'},
            'is_visible': true,
          },
        ],
      },
    );

    expect(paths, {'/terminos'});

    final source = File(
      'scripts/generate_product_seo_snapshots.dart',
    ).readAsStringSync();
    expect(source, contains('staticTrustPagePaths: staticTrustPagePaths'));
    expect(source, contains('for (final path in staticTrustPagePaths)'));
    expect(source, isNot(contains("addUrl('/terminos'")));
    expect(source, isNot(contains("addUrl('/privacidad'")));
  });
}

Map<String, dynamic> _product({
  required String id,
  required String categoryId,
  required String name,
  required String sku,
  String? websiteName,
}) {
  return {
    'id': id,
    'category_id': categoryId,
    'name': name,
    'website_name': websiteName,
    'sku': sku,
  };
}

Map<String, dynamic> _category({
  required String id,
  required String name,
  required String fullPath,
  String? parentId,
  int sortOrder = 0,
  bool isActive = true,
  bool showOnWebsite = true,
}) {
  return {
    'id': id,
    'name': name,
    'full_path': fullPath,
    'parent_id': parentId,
    'description': '',
    'image_url': '',
    'sort_order': sortOrder,
    'is_active': isActive,
    'show_on_website': showOnWebsite,
  };
}

snapshots.SeoOwnerSourceSnapshot _seoOwnerSourceSnapshot({
  String settingValue = 'Tienda',
  String presentationValue = '{"version":1}',
  int price = 10000,
  int stock = 3,
  String brandName = 'Marca',
  String categoryName = 'Categoría',
  String aliasPath = '/productos/alias-anterior',
  String pageTitle = 'Página',
  String blockContent = 'Contenido',
  bool reverseRows = false,
}) {
  List<Map<String, dynamic>> ordered(
    List<Map<String, dynamic>> rows,
  ) {
    return reverseRows ? rows.reversed.toList(growable: false) : rows;
  }

  final settings = snapshots.SeoWebsiteSettingsSource.fromRows(
    ordered([
      {
        'key': 'store_name',
        'value': settingValue,
        'updated_at': '2026-07-28T10:00:00Z',
      },
      {
        'key': websiteCatalogPresentationsSettingKey,
        'value': presentationValue,
        'updated_at': '2026-07-28T10:01:00Z',
      },
    ]),
  );
  final products = ordered([
    {
      'id': 'product-1',
      'price': price,
      'brand_id': 'brand-1',
      'category_id': 'category-1',
      'updated_at': '2026-07-28T10:02:00Z',
    },
    {
      'id': 'product-2',
      'price': 20000,
      'brand_id': 'brand-2',
      'category_id': 'category-2',
      'updated_at': '2026-07-28T10:03:00Z',
    },
  ]);
  final brands = ordered([
    {
      'id': 'brand-1',
      'name': brandName,
      'tenant_id': 'tenant-1',
      'is_active': true,
      'updated_at': '2026-07-28T10:04:00Z',
    },
    {
      'id': 'brand-2',
      'name': 'Otra marca',
      'tenant_id': 'tenant-1',
      'is_active': true,
      'updated_at': '2026-07-28T10:05:00Z',
    },
  ]);
  final categories = ordered([
    {
      'id': 'category-1',
      'name': categoryName,
      'show_on_website': true,
      'updated_at': '2026-07-28T10:06:00Z',
    },
    {
      'id': 'category-2',
      'name': 'Otra categoría',
      'show_on_website': false,
      'updated_at': '2026-07-28T10:07:00Z',
    },
  ]);
  final aliases = ordered([
    {
      'product_id': 'product-1',
      'alias_path': aliasPath,
      'source': 'slug_change',
      'created_at': '2026-07-28T10:08:00Z',
    },
    {
      'product_id': 'product-2',
      'alias_path': '/productos/otro-alias',
      'source': 'legacy',
      'created_at': '2026-07-28T10:09:00Z',
    },
  ]);
  final pages = ordered([
    {
      'id': 'page-1',
      'slug': 'contacto',
      'title': pageTitle,
      'is_published': true,
      'updated_at': '2026-07-28T10:10:00Z',
    },
    {
      'id': 'page-2',
      'slug': 'nosotros',
      'title': 'Nosotros',
      'is_published': true,
      'updated_at': '2026-07-28T10:11:00Z',
    },
  ]);
  final pageOneBlocks = ordered([
    {
      'id': 'block-1',
      'page_id': 'page-1',
      'block_type': 'text',
      'block_data': {'content': blockContent},
      'order_index': 0,
      'is_visible': true,
      'updated_at': '2026-07-28T10:12:00Z',
    },
    {
      'id': 'block-2',
      'page_id': 'page-1',
      'block_type': 'text',
      'block_data': {'content': 'Otro bloque'},
      'order_index': 1,
      'is_visible': true,
      'updated_at': '2026-07-28T10:13:00Z',
    },
  ]);

  return snapshots.SeoOwnerSourceSnapshot(
    websiteSettings: settings,
    publishedProductOwners: products,
    publicAvailability: reverseRows
        ? {'product-2': 1, 'product-1': stock}
        : {'product-1': stock, 'product-2': 1},
    brandRows: brands,
    activeCategoryRows: categories,
    productUrlAliases: aliases,
    websiteContent: snapshots.SeoWebsiteContentSnapshot(
      pages: pages,
      pageBlocks: reverseRows
          ? {
              'page-2': const <Map<String, dynamic>>[],
              'page-1': pageOneBlocks,
            }
          : {
              'page-1': pageOneBlocks,
              'page-2': const <Map<String, dynamic>>[],
            },
    ),
  );
}
