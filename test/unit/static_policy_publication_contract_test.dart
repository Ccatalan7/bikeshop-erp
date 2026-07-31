import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/public_store/pages/static_policy_page.dart';

import '../../scripts/generate_product_seo_snapshots.dart' as snapshots;

void main() {
  test(
      'generator and runtime share strict empty/about/features/FAQ/contact/CTA eligibility',
      () {
    final cases = <({
      String name,
      List<Map<String, dynamic>> blocks,
      bool expected,
    })>[
      (name: 'empty', blocks: const [], expected: false),
      (
        name: 'about title only',
        blocks: [
          {
            'block_type': 'about',
            'block_data': {'title': 'Quiénes somos'},
            'is_visible': true,
          },
        ],
        expected: false,
      ),
      (
        name: 'about body',
        blocks: [
          {
            'block_type': 'about',
            'block_data': {
              'title': 'Quiénes somos',
              'content': 'Historia publicada por el editor.',
            },
            'is_visible': true,
          },
        ],
        expected: true,
      ),
      (
        name: 'about body disabled on every public breakpoint',
        blocks: [
          {
            'block_type': 'about',
            'block_data': {
              'content': 'No debe llegar al runtime ni al snapshot.',
              'visibility': {
                'desktop': false,
                'tablet': false,
                'mobile': false,
              },
            },
            'is_visible': true,
          },
        ],
        expected: false,
      ),
      (
        name: 'about body available on one public breakpoint',
        blocks: [
          {
            'block_type': 'about',
            'block_data': {
              'content': 'Contenido disponible en tablet.',
              'visibility': {
                'desktop': false,
                'tablet': true,
                'mobile': false,
              },
            },
            'is_visible': true,
          },
        ],
        expected: true,
      ),
      (
        name: 'features empty',
        blocks: [
          {
            'block_type': 'features',
            'block_data': {
              'title': 'Ventajas',
              'features': [
                {'icon': 'verified', 'title': '', 'description': ''},
              ],
            },
            'is_visible': true,
          },
        ],
        expected: false,
      ),
      (
        name: 'features factual item',
        blocks: [
          {
            'block_type': 'features',
            'block_data': {
              'title': 'Ventajas',
              'features': [
                {
                  'title': 'Diagnóstico',
                  'description': 'Revisión técnica antes del trabajo.',
                },
              ],
            },
            'is_visible': true,
          },
        ],
        expected: true,
      ),
      (
        name: 'FAQ question without answer',
        blocks: [
          {
            'block_type': 'faq',
            'block_data': {
              'items': [
                {'question': '¿Atienden los sábados?', 'answer': ''},
              ],
            },
            'is_visible': true,
          },
        ],
        expected: false,
      ),
      (
        name: 'FAQ complete pair',
        blocks: [
          {
            'block_type': 'faq',
            'block_data': {
              'items': [
                {
                  'question': '¿Atienden los sábados?',
                  'answer': 'Consulta el horario publicado antes de venir.',
                },
              ],
            },
            'is_visible': true,
          },
        ],
        expected: true,
      ),
      (
        name: 'contact factual field',
        blocks: [
          {
            'block_type': 'contact',
            'block_data': {'phone': '+56 9 1111 2222'},
            'is_visible': true,
          },
        ],
        expected: true,
      ),
      (
        name: 'button only',
        blocks: [
          {
            'block_type': 'cta',
            'block_data': {
              'title': 'Compra ahora',
              'buttonText': 'Ir al catálogo',
              'buttonLink': '/productos',
            },
            'is_visible': true,
          },
        ],
        expected: false,
      ),
    ];

    for (final entry in cases) {
      expect(
        snapshots.hasMeaningfulDynamicCmsPageContent(
          canonicalPath: '/pagina/prueba',
          blocks: entry.blocks,
        ),
        entry.expected,
        reason: 'generador dinámico: ${entry.name}',
      );
      expect(
        hasMeaningfulPublicWebsitePageContent(entry.blocks),
        entry.expected,
        reason: 'runtime dinámico: ${entry.name}',
      );
      expect(
        snapshots.hasMeaningfulStaticTrustPageContent(entry.blocks),
        entry.expected,
        reason: 'generador legal: ${entry.name}',
      );
      expect(
        hasMeaningfulPublicPolicyContent(entry.blocks),
        entry.expected,
        reason: 'runtime legal: ${entry.name}',
      );
    }

    expect(
      snapshots.hasMeaningfulDynamicCmsPageContent(
        canonicalPath: '/contacto',
        blocks: const [],
        contactFacts: const snapshots.SeoContactFacts(
          email: 'contacto@tienda.example',
        ),
      ),
      isTrue,
    );
    expect(
      hasMeaningfulPublicWebsitePageContent(
        const [],
        isContactPage: true,
        contactFacts: const PublicWebsiteContactFacts(
          address: 'Calle 1, Ciudad',
        ),
      ),
      isTrue,
    );
  });

  test('policy content eligibility requires visible editor-owned body content',
      () {
    expect(
      hasMeaningfulPublicPolicyContent([
        {
          'block_type': 'hero',
          'block_data': {'title': 'Encabezado sin política'},
          'is_visible': true,
        },
        {
          'block_type': 'text',
          'block_data': {'content': 'Contenido oculto'},
          'is_visible': false,
        },
      ]),
      isFalse,
    );

    expect(
      hasMeaningfulPublicPolicyContent([
        {
          'block_type': 'text',
          'block_data': {'content': 'Condición publicada por el editor.'},
          'is_visible': true,
        },
      ]),
      isTrue,
    );
  });

  test('runtime policy projection enforces origin publication provenance', () {
    final published = _policyPage(isPublished: true);
    final unpublished = _policyPage(isPublished: false);
    final meaningfulBlocks = [
      {
        'id': 'terms-block',
        'block_type': 'text',
        'block_data': {'content': 'Condición publicada por el editor.'},
        'is_visible': true,
      },
    ];

    final origin = StaticPolicyPublicationProjection.fromLoadResult(
      PageSnapshotLoadResult.origin(
        CachedPageSnapshot(page: published, blocks: meaningfulBlocks),
      ),
    );
    expect(origin.isAuthoritativelyPublic, isTrue);
    expect(origin.shouldRenderPublicContent, isTrue);
    expect(origin.shouldIndex, isTrue);

    final stale = StaticPolicyPublicationProjection.fromLoadResult(
      PageSnapshotLoadResult.staleFallback(
        CachedPageSnapshot(page: published, blocks: meaningfulBlocks),
      ),
    );
    expect(stale.isAuthoritativelyPublic, isFalse);
    expect(stale.shouldRenderPublicContent, isTrue);
    expect(stale.shouldIndex, isFalse);

    final notPublished = StaticPolicyPublicationProjection.fromLoadResult(
      PageSnapshotLoadResult.origin(
        CachedPageSnapshot(page: unpublished, blocks: meaningfulBlocks),
      ),
    );
    expect(notPublished.shouldRenderPublicContent, isFalse);
    expect(notPublished.shouldIndex, isFalse);

    final empty = StaticPolicyPublicationProjection.fromLoadResult(
      PageSnapshotLoadResult.origin(
        CachedPageSnapshot(page: published, blocks: const []),
      ),
    );
    expect(empty.shouldRenderPublicContent, isFalse);
    expect(empty.shouldIndex, isFalse);

    final missing = StaticPolicyPublicationProjection.fromLoadResult(
      const PageSnapshotLoadResult.originMissing(),
    );
    expect(missing.shouldRenderPublicContent, isFalse);
    expect(missing.shouldIndex, isFalse);

    final editorOnly = StaticPolicyPublicationProjection.fromState(
      page: unpublished,
      blocks: meaningfulBlocks,
      provenance: StaticPolicyRetainedProvenance.editor,
    );
    expect(editorOnly.canRenderRetainedContent, isTrue);
    expect(editorOnly.shouldRenderPublicContent, isFalse);
    expect(editorOnly.shouldIndex, isFalse);

    expect(
      availablePublicPolicySlugs({
        'terminos': PageSnapshotLoadResult.origin(
          CachedPageSnapshot(page: published, blocks: meaningfulBlocks),
        ),
        'privacidad': PageSnapshotLoadResult.staleFallback(
          CachedPageSnapshot(page: published, blocks: meaningfulBlocks),
        ),
        'envios': PageSnapshotLoadResult.origin(
          CachedPageSnapshot(page: unpublished, blocks: meaningfulBlocks),
        ),
        'nosotros': PageSnapshotLoadResult.origin(
          CachedPageSnapshot(page: published, blocks: const []),
        ),
      }),
      {'terminos'},
    );
  });

  test('published trust snapshot has one semantic document and one business',
      () {
    final html = snapshots.buildStaticTrustPageSnapshotHtml(
      baseHtml: _baseHtml,
      slug: 'terminos',
      storeUrl: 'https://vinabike.cl',
      storeName: 'Viñabike',
      settings: const {},
      page: {
        'id': 'terms-page',
        'slug': 'terminos',
        'title': 'Condiciones publicadas',
        'meta_title': 'Condiciones publicadas | Viñabike',
        'meta_description': 'Texto configurado por el editor.',
        'is_published': true,
      },
      blocks: [
        {
          'id': 'terms-block',
          'block_type': 'text',
          'block_data': {
            'title': 'Alcance',
            'content': 'Esta condición proviene del editor.',
          },
          'is_visible': true,
          'order_index': 0,
        },
      ],
      publishedPaths: const {'/terminos'},
      availablePublicPaths: const {'/productos', '/terminos'},
    );

    expect(_tagCount(html, 'h1'), 1);
    expect(_tagCount(html, 'main'), 1);
    expect(html, isNot(contains('Inicio base que debe reemplazarse')));
    expect(html, contains('content="index,follow"'));
    expect(html, contains('Esta condición proviene del editor.'));
    expect(html, contains('href="/terminos"'));
    expect(html, isNot(contains('href="/envios"')));
    expect(_schemaTypeCount(html, 'LocalBusiness'), 1);
    expect(_schemaTypeCount(html, 'WebPage'), 1);
    _expectValidJsonLd(html);
  });

  test('missing or empty trust owner is neutral and noindex', () {
    final html = snapshots.buildStaticTrustPageSnapshotHtml(
      baseHtml: _baseHtml,
      slug: 'devoluciones',
      storeUrl: 'https://vinabike.cl',
      storeName: 'Viñabike',
      settings: const {
        'seo_meta_keywords': 'dato que no debe heredar',
      },
      page: {
        'id': 'returns-page',
        'slug': 'devoluciones',
        'title': 'Borrador factual',
        'meta_title': 'Plazo inventado',
        'meta_description': 'Tienes 10 días y devolución garantizada.',
        'meta_keywords': 'retracto garantizado',
        'is_published': true,
      },
      blocks: const [],
      publishedPaths: const {'/devoluciones'},
      availablePublicPaths: const {},
    );

    expect(_tagCount(html, 'h1'), 1);
    expect(_tagCount(html, 'main'), 1);
    expect(html, contains('content="noindex,follow"'));
    expect(
      html,
      contains(
        'Esta página no tiene contenido público disponible en este momento.',
      ),
    );
    expect(html, contains('Contenido no publicado'));
    expect(html, isNot(contains('Tienes 10 días')));
    expect(html, isNot(contains('Plazo inventado')));
    expect(html, isNot(contains('retracto garantizado')));
    expect(_schemaTypeCount(html, 'LocalBusiness'), 1);
    _expectValidJsonLd(html);
  });

  test('route fallback replaces the homepage main instead of appending one',
      () {
    final html = snapshots.replaceStorefrontNoJsFallback(
      baseHtml: _baseHtml,
      semanticMainHtml: '''
<main id="seo-route" class="storefront-nojs-fallback">
  <h1>Documento de ruta</h1>
</main>
''',
    );

    expect(_tagCount(html, 'main'), 1);
    expect(_tagCount(html, 'h1'), 1);
    expect(html, contains('Documento de ruta'));
    expect(html, isNot(contains('Inicio base que debe reemplazarse')));
  });

  test('artifact gate validates final trust files and rejects duplicate h1',
      () async {
    final buildDir =
        await Directory.systemTemp.createTemp('vinabike-seo-contract-');
    try {
      await File('${buildDir.path}/index.html').writeAsString(_baseHtml);
      const slugs = [
        'nosotros',
        'envios',
        'devoluciones',
        'terminos',
        'privacidad',
      ];
      for (final slug in slugs) {
        final isTerms = slug == 'terminos';
        final html = snapshots.buildStaticTrustPageSnapshotHtml(
          baseHtml: _baseHtml,
          slug: slug,
          storeUrl: 'https://vinabike.cl',
          storeName: 'Viñabike',
          settings: const {},
          page: isTerms
              ? {
                  'id': 'terms-page',
                  'slug': 'terminos',
                  'title': 'Términos',
                  'is_published': true,
                }
              : null,
          blocks: isTerms
              ? [
                  {
                    'id': 'terms-block',
                    'block_type': 'text',
                    'block_data': {'content': 'Texto publicado.'},
                    'is_visible': true,
                  },
                ]
              : const [],
          publishedPaths: const {'/terminos'},
          availablePublicPaths: const {'/terminos'},
        );
        await File('${buildDir.path}/$slug').writeAsString(html);
      }
      await File('${buildDir.path}/sitemap.xml').writeAsString('''
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://vinabike.cl/terminos</loc></url>
</urlset>
''');

      await snapshots.validateGeneratedSeoArtifacts(
        buildDir: buildDir,
        storeUrl: 'https://vinabike.cl',
        staticTrustPagePaths: const {'/terminos'},
      );

      final termsFile = File('${buildDir.path}/terminos');
      await termsFile.writeAsString(
        '${await termsFile.readAsString()}<h1>Duplicado</h1>',
      );
      await expectLater(
        snapshots.validateGeneratedSeoArtifacts(
          buildDir: buildDir,
          storeUrl: 'https://vinabike.cl',
          staticTrustPagePaths: const {'/terminos'},
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('contiene 2 elementos h1'),
          ),
        ),
      );
    } finally {
      if (buildDir.existsSync()) {
        await buildDir.delete(recursive: true);
      }
    }
  });
}

WebsitePage _policyPage({required bool isPublished}) {
  final timestamp = DateTime.utc(2026, 7, 29);
  return WebsitePage(
    id: isPublished ? 'published-page' : 'unpublished-page',
    tenantId: 'tenant-a',
    slug: 'terminos',
    title: 'Términos',
    isPublished: isPublished,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

int _tagCount(String html, String tag) {
  return RegExp(
    '<$tag\\b',
    caseSensitive: false,
  ).allMatches(html).length;
}

int _schemaTypeCount(String html, String type) {
  return RegExp(
    '"@type"\\s*:\\s*"$type"',
  ).allMatches(html).length;
}

void _expectValidJsonLd(String html) {
  final scripts = RegExp(
    r'<script[^>]+type="application/ld\+json"[^>]*>(.*?)</script>',
    caseSensitive: false,
    dotAll: true,
  ).allMatches(html);
  expect(scripts, isNotEmpty);
  for (final script in scripts) {
    expect(() => jsonDecode(script.group(1)!.trim()), returnsNormally);
  }
}

const _baseHtml = '''
<!doctype html>
<html>
<head>
  <title>Base</title>
  <meta name="title" content="Base">
  <meta name="description" content="Base">
  <meta name="robots" content="index,follow">
  <meta name="googlebot" content="index,follow">
  <meta name="keywords" content="base">
  <link rel="canonical" href="https://vinabike.cl">
  <meta property="og:type" content="website">
  <meta property="og:url" content="https://vinabike.cl">
  <meta property="og:title" content="Base">
  <meta property="og:description" content="Base">
  <meta property="og:image" content="https://vinabike.cl/base.jpg">
  <meta name="twitter:url" content="https://vinabike.cl">
  <meta name="twitter:title" content="Base">
  <meta name="twitter:description" content="Base">
  <meta name="twitter:image" content="https://vinabike.cl/base.jpg">
  <script type="application/ld+json" id="base-business">
    {"@context":"https://schema.org","@type":"LocalBusiness","name":"Viñabike"}
  </script>
</head>
<body>
  <div id="app-shell">
    <noscript id="storefront-nojs-fallback">
      <main class="storefront-nojs-fallback">
        <h1>Inicio base que debe reemplazarse</h1>
      </main>
    </noscript>
  </div>
  <script src="main.dart.js"></script>
</body>
</html>
''';
