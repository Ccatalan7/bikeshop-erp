import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_erp/modules/website/models/website_destination.dart';
import 'package:vinabike_erp/public_store/widgets/catalog_collection_presentation.dart';

void main() {
  group('websiteCategorySlug', () {
    test('creates stable clean routes from real category labels', () {
      expect(
        websiteCategorySlug('Componentes / Transmisión y Cámaras'),
        'componentes-transmision-y-camaras',
      );
    });
  });

  group('WebsiteCatalogPresentationRegistry', () {
    test('round-trips every editable presentation choice', () {
      final presentation = WebsiteCatalogPresentation(
        categoryId: 'category-1',
        slug: 'drivetrain',
        slugAliases: const ['transmision', 'componentes-transmision'],
        heroSize: WebsiteCatalogHeroSize.immersive,
        heroAlignment: WebsiteCatalogHeroAlignment.center,
        gridDensity: WebsiteCatalogGridDensity.editorial,
        heroImageUrl: 'https://cdn.example.test/drivetrain.webp',
        heroEyebrow: 'Componentes',
        heroTitle: 'Transmisión',
        heroDescription: 'Encuentra la relación adecuada para tu bicicleta.',
        megaMenuImageUrl: 'https://cdn.example.test/drivetrain-mega-menu.webp',
        seoTitle: 'Transmisiones para bicicleta',
        seoDescription: 'Compra transmisiones y repuestos compatibles.',
        socialImageUrl: 'https://cdn.example.test/drivetrain-social.webp',
        allowIndexing: false,
        heroOverlay: 0.55,
        megaMenuOverlay: 0.64,
        megaMenuCardOverlay: 0.28,
        megaMenuOverviewWidth: 330,
        megaMenuContentAlignment: WebsiteMegaMenuContentAlignment.center,
        showBreadcrumbs: false,
        showSubcategories: false,
        facets: [WebsiteCatalogFacet.availability],
      );

      final encoded = WebsiteCatalogPresentationRegistry({
        'category-1': presentation,
      }).encode();
      final decoded = WebsiteCatalogPresentationRegistry.decode(encoded);
      final restored = decoded.forCategory('category-1');

      expect(restored, isNotNull);
      expect(restored!.slug, 'drivetrain');
      expect(
        restored.slugAliases,
        const ['transmision', 'componentes-transmision'],
      );
      expect(restored.heroSize, WebsiteCatalogHeroSize.immersive);
      expect(restored.heroAlignment, WebsiteCatalogHeroAlignment.center);
      expect(restored.gridDensity, WebsiteCatalogGridDensity.editorial);
      expect(restored.heroImageUrl, presentation.heroImageUrl);
      expect(restored.heroEyebrow, presentation.heroEyebrow);
      expect(restored.heroTitle, presentation.heroTitle);
      expect(restored.heroDescription, presentation.heroDescription);
      expect(restored.megaMenuImageUrl, presentation.megaMenuImageUrl);
      expect(restored.seoTitle, presentation.seoTitle);
      expect(restored.seoDescription, presentation.seoDescription);
      expect(restored.socialImageUrl, presentation.socialImageUrl);
      expect(restored.allowIndexing, isFalse);
      expect(restored.heroOverlay, 0.55);
      expect(restored.megaMenuOverlay, 0.64);
      expect(restored.megaMenuCardOverlay, 0.28);
      expect(restored.megaMenuOverviewWidth, 330);
      expect(
        restored.megaMenuContentAlignment,
        WebsiteMegaMenuContentAlignment.center,
      );
      expect(restored.showBreadcrumbs, isFalse);
      expect(restored.showSubcategories, isFalse);
      expect(restored.facets, [WebsiteCatalogFacet.availability]);
      expect(decoded.forSlug('DRIVETRAIN')?.categoryId, 'category-1');
      expect(decoded.forSlug('TRANSMISIÓN')?.categoryId, 'category-1');
    });

    test('slug changes preserve the previous route as a removable alias', () {
      final saved = WebsiteCatalogPresentation(
        categoryId: 'category-1',
        slug: 'camaras',
        slugAliases: const ['tubos'],
      );
      final registry = WebsiteCatalogPresentationRegistry({
        saved.categoryId: saved,
      });

      final prepared = registry.prepareForSave(
        saved.copyWith(
          slug: 'camaras-bicicleta',
          // Removing an older alias remains an explicit editable operation.
          slugAliases: const [],
        ),
      );

      expect(prepared.slug, 'camaras-bicicleta');
      expect(prepared.slugAliases, const ['camaras']);
      expect(
        registry.put(prepared).forSlug('camaras')?.categoryId,
        'category-1',
      );
      expect(
        publicCategoryPath(presentation: prepared),
        '/productos/categoria/camaras-bicicleta',
      );
      expect(
        publicCategoryPath(presentation: prepared, services: true),
        '/servicios/categoria/camaras-bicicleta',
      );
    });

    test('catalog root owners never become fake category routes', () {
      expect(
        publicCategoryPath(
          presentation: WebsiteCatalogPresentation.catalogRoot(
            WebsiteCatalogRoot.products,
          ),
        ),
        '/productos',
      );
      expect(
        publicCategoryPath(
          presentation: WebsiteCatalogPresentation.catalogRoot(
            WebsiteCatalogRoot.services,
          ),
        ),
        '/servicios',
      );
    });

    test('first customization preserves the effective inherited slug', () {
      final inherited = WebsiteCatalogPresentation.fallback(
        categoryId: 'category-1',
        categoryName: 'Servicios / Mantención',
      );
      final validationRegistry = WebsiteCatalogPresentationRegistry({
        inherited.categoryId: inherited,
      });

      final prepared = validationRegistry.prepareForSave(
        inherited.copyWith(slug: 'taller-profesional'),
      );

      expect(prepared.slug, 'taller-profesional');
      expect(
        prepared.slugAliases,
        const ['servicios-mantencion'],
      );
    });

    test('current slugs and aliases share one collision namespace', () {
      final registry = WebsiteCatalogPresentationRegistry({
        'category-1': WebsiteCatalogPresentation(
          categoryId: 'category-1',
          slug: 'camaras',
          slugAliases: const ['tubos'],
        ),
      });

      expect(
        () => registry.prepareForSave(
          WebsiteCatalogPresentation(
            categoryId: 'category-2',
            slug: 'tubos',
          ),
        ),
        throwsA(isA<WebsiteCatalogSlugCollisionException>()),
      );
      expect(
        () => registry.prepareForSave(
          WebsiteCatalogPresentation(
            categoryId: 'category-2',
            slug: 'neumaticos',
            slugAliases: const ['camaras'],
          ),
        ),
        throwsA(isA<WebsiteCatalogSlugCollisionException>()),
      );
    });

    test('alias resolution fails closed when imported settings are ambiguous',
        () {
      final registry = WebsiteCatalogPresentationRegistry({
        'category-1': WebsiteCatalogPresentation(
          categoryId: 'category-1',
          slug: 'camaras',
          slugAliases: const ['componentes'],
        ),
        'category-2': WebsiteCatalogPresentation(
          categoryId: 'category-2',
          slug: 'cadenas',
          slugAliases: const ['componentes'],
        ),
      });

      expect(registry.categorySlugClaimCount('componentes'), 2);
      expect(registry.resolveSlug('componentes'), isNull);
      expect(registry.forSlug('componentes'), isNull);
    });

    test('missing facets inherit defaults but explicit empty stays empty', () {
      final inherited = WebsiteCatalogPresentation.fromJson(const {
        'category_id': 'category-default',
        'slug': 'default',
      });
      final hidden = WebsiteCatalogPresentation.fromJson(const {
        'category_id': 'category-hidden',
        'slug': 'hidden',
        'facets': <String>[],
      });

      expect(
        inherited.facets,
        WebsiteCatalogPresentation.defaultFacets,
      );
      expect(inherited.allowIndexing, isTrue);
      expect(hidden.facets, isEmpty);

      final restored = WebsiteCatalogPresentationRegistry.decode(
        WebsiteCatalogPresentationRegistry({
          hidden.categoryId: hidden,
        }).encode(),
      ).forCategory(hidden.categoryId);
      expect(restored?.facets, isEmpty);
    });

    test('facet order round-trips with stable duplicate removal', () {
      final presentation = WebsiteCatalogPresentation(
        categoryId: 'category-facets',
        slug: 'facets',
        facets: const [
          WebsiteCatalogFacet.price,
          WebsiteCatalogFacet.brand,
          WebsiteCatalogFacet.price,
          WebsiteCatalogFacet.availability,
          WebsiteCatalogFacet.brand,
        ],
      );

      expect(presentation.facets, const [
        WebsiteCatalogFacet.price,
        WebsiteCatalogFacet.brand,
        WebsiteCatalogFacet.availability,
      ]);

      final restored = WebsiteCatalogPresentationRegistry.decode(
        WebsiteCatalogPresentationRegistry({
          presentation.categoryId: presentation,
        }).encode(),
      ).forCategory(presentation.categoryId);
      expect(restored?.facets, presentation.facets);
    });

    test('unknown stored facets do not restore unrelated defaults', () {
      final presentation = WebsiteCatalogPresentation.fromJson(const {
        'category_id': 'category-unknown',
        'slug': 'unknown',
        'facets': ['future_facet'],
      });

      expect(presentation.facets, isEmpty);
    });

    test('mega-menu media defaults, clamps and stays category-owned', () {
      final inherited = WebsiteCatalogPresentation.fromJson(const {
        'category_id': 'category-default',
        'slug': 'transmision',
      });
      final tooDark = WebsiteCatalogPresentation.fromJson(const {
        'category_id': 'category-dark',
        'slug': 'transmision-oscura',
        'mega_menu_image_url': '  https://cdn.example.test/dark.webp  ',
        'mega_menu_overlay': 2,
        'mega_menu_card_overlay': 2,
        'mega_menu_overview_width': 999,
        'mega_menu_content_alignment': 'center',
      });
      final tooLight = WebsiteCatalogPresentation.fromJson(const {
        'category_id': 'category-light',
        'slug': 'transmision-clara',
        'mega_menu_overlay': -1,
        'mega_menu_card_overlay': -1,
        'mega_menu_overview_width': 1,
        'mega_menu_content_alignment': 'future-value',
      });

      expect(inherited.megaMenuImageUrl, isEmpty);
      expect(inherited.megaMenuOverlay, 0.58);
      expect(inherited.megaMenuCardOverlay, 0);
      expect(
        inherited.megaMenuOverviewWidth,
        WebsiteCatalogPresentation.defaultMegaMenuOverviewWidth,
      );
      expect(
        inherited.megaMenuContentAlignment,
        WebsiteMegaMenuContentAlignment.bottom,
      );
      expect(
        tooDark.megaMenuImageUrl,
        'https://cdn.example.test/dark.webp',
      );
      expect(tooDark.megaMenuOverlay, 0.85);
      expect(tooDark.megaMenuCardOverlay, 0.65);
      expect(
        tooDark.megaMenuOverviewWidth,
        WebsiteCatalogPresentation.maxMegaMenuOverviewWidth,
      );
      expect(
        tooDark.megaMenuContentAlignment,
        WebsiteMegaMenuContentAlignment.center,
      );
      expect(tooLight.megaMenuOverlay, 0);
      expect(tooLight.megaMenuCardOverlay, 0);
      expect(
        tooLight.megaMenuOverviewWidth,
        WebsiteCatalogPresentation.minMegaMenuOverviewWidth,
      );
      expect(
        tooLight.megaMenuContentAlignment,
        WebsiteMegaMenuContentAlignment.bottom,
      );
      expect(tooDark.toJson()['mega_menu_image_url'], tooDark.megaMenuImageUrl);
      expect(tooDark.toJson()['mega_menu_overlay'], 0.85);
      expect(tooDark.toJson()['mega_menu_card_overlay'], 0.65);
      expect(tooDark.toJson()['mega_menu_overview_width'], 440);
      expect(tooDark.toJson()['mega_menu_content_alignment'], 'center');
    });

    test('malformed settings fail closed without inventing content', () {
      expect(
        WebsiteCatalogPresentationRegistry.decode('{broken').byCategoryId,
        isEmpty,
      );
    });

    test('catalog roots round-trip without masquerading as categories', () {
      final products = WebsiteCatalogPresentation.catalogRoot(
        WebsiteCatalogRoot.products,
      ).copyWith(
        gridDensity: WebsiteCatalogGridDensity.compact,
        facets: const [
          WebsiteCatalogFacet.brand,
          WebsiteCatalogFacet.price,
        ],
      );
      final services = WebsiteCatalogPresentation.catalogRoot(
        WebsiteCatalogRoot.services,
      ).copyWith(
        gridDensity: WebsiteCatalogGridDensity.editorial,
      );
      final category = WebsiteCatalogPresentation.fallback(
        categoryId: 'category-1',
        categoryName: 'Cámaras',
      );

      final restored = WebsiteCatalogPresentationRegistry.decode(
        WebsiteCatalogPresentationRegistry({
          products.categoryId: products,
          services.categoryId: services,
          category.categoryId: category,
        }).encode(),
      );

      expect(
        restored.forCatalogRoot(WebsiteCatalogRoot.products)?.gridDensity,
        WebsiteCatalogGridDensity.compact,
      );
      expect(
        restored.forCatalogRoot(WebsiteCatalogRoot.products)?.facets,
        const [WebsiteCatalogFacet.brand, WebsiteCatalogFacet.price],
      );
      expect(
        restored.forCatalogRoot(WebsiteCatalogRoot.services)?.gridDensity,
        WebsiteCatalogGridDensity.editorial,
      );
      expect(
        restored.forCategory(websiteProductsCatalogPresentationId),
        isNull,
      );
      expect(restored.forSlug('productos'), isNull);
      expect(restored.categoryPresentationCount, 1);
      expect(products.hasSamePersistedValue(products.copyWith()), isTrue);

      final sanitizedRoot = WebsiteCatalogPresentation.fromJson(const {
        'category_id': websiteProductsCatalogPresentationId,
        'slug': 'invented-route',
        'slug_aliases': ['old-root-route'],
        'hero_title': 'Hidden root hero',
        'mega_menu_image_url': 'https://cdn.example.test/hidden-root-menu.webp',
        'mega_menu_overlay': 0.12,
        'mega_menu_card_overlay': 0.28,
        'mega_menu_overview_width': 330,
        'mega_menu_content_alignment': 'center',
        'seo_title': 'Productos para bicicleta',
        'seo_description': 'Explora el catálogo público.',
        'social_image_url': 'https://cdn.example.test/catalog.webp',
        'allow_indexing': false,
        'show_breadcrumbs': true,
        'show_subcategories': true,
        'grid_density': 'compact',
        'facets': ['brand'],
      });
      expect(sanitizedRoot.slug, 'productos');
      expect(sanitizedRoot.slugAliases, isEmpty);
      expect(sanitizedRoot.heroTitle, isEmpty);
      expect(sanitizedRoot.megaMenuImageUrl, isEmpty);
      expect(sanitizedRoot.megaMenuOverlay, 0.58);
      expect(sanitizedRoot.megaMenuCardOverlay, 0);
      expect(
        sanitizedRoot.megaMenuOverviewWidth,
        WebsiteCatalogPresentation.defaultMegaMenuOverviewWidth,
      );
      expect(
        sanitizedRoot.megaMenuContentAlignment,
        WebsiteMegaMenuContentAlignment.bottom,
      );
      expect(sanitizedRoot.seoTitle, 'Productos para bicicleta');
      expect(sanitizedRoot.seoDescription, 'Explora el catálogo público.');
      expect(
        sanitizedRoot.socialImageUrl,
        'https://cdn.example.test/catalog.webp',
      );
      expect(sanitizedRoot.allowIndexing, isFalse);
      expect(sanitizedRoot.showBreadcrumbs, isFalse);
      expect(sanitizedRoot.showSubcategories, isFalse);
      expect(sanitizedRoot.gridDensity, WebsiteCatalogGridDensity.compact);
      expect(sanitizedRoot.facets, const [WebsiteCatalogFacet.brand]);
    });
  });

  test('shared grid projection changes only through canonical density', () {
    final balanced = websiteCatalogGridMetrics(
      width: 1400,
      density: WebsiteCatalogGridDensity.balanced,
    );
    final compact = websiteCatalogGridMetrics(
      width: 1400,
      density: WebsiteCatalogGridDensity.compact,
    );
    final mobile = websiteCatalogGridMetrics(
      width: 360,
      density: WebsiteCatalogGridDensity.compact,
    );

    expect(balanced.crossAxisCount, 4);
    expect(compact.crossAxisCount, 5);
    expect(mobile.crossAxisCount, 2);
  });

  testWidgets('shared collection header consumes every navigation switch',
      (tester) async {
    final presentation = WebsiteCatalogPresentation(
      categoryId: 'category-1',
      slug: 'camaras',
      heroEyebrow: 'Componentes',
      heroTitle: 'Cámaras',
      heroDescription: 'Todo para mantener tus ruedas listas.',
    );

    Widget buildHeader(WebsiteCatalogPresentation value) {
      return MaterialApp(
        home: SingleChildScrollView(
          child: CatalogCollectionPresentationHeader(
            presentation: value,
            title: value.heroTitle,
            description: value.heroDescription,
            imageUrl: '',
            compact: true,
            breadcrumbs: const [
              CatalogCollectionNavigationItem(
                id: 'root',
                label: 'Productos',
              ),
              CatalogCollectionNavigationItem(
                id: 'category-1',
                label: 'Cámaras',
                selected: true,
              ),
            ],
            subcategories: const [
              CatalogCollectionNavigationItem(
                id: 'child-1',
                label: 'Válvula presta',
              ),
            ],
          ),
        ),
      );
    }

    await tester.pumpWidget(buildHeader(presentation));
    expect(find.text('COMPONENTES'), findsOneWidget);
    expect(find.text('CÁMARAS'), findsOneWidget);
    expect(find.text('Productos'), findsOneWidget);
    expect(find.text('VÁLVULA PRESTA'), findsOneWidget);

    await tester.pumpWidget(
      buildHeader(
        presentation.copyWith(
          showBreadcrumbs: false,
          showSubcategories: false,
        ),
      ),
    );
    expect(find.text('Productos'), findsNothing);
    expect(find.text('VÁLVULA PRESTA'), findsNothing);
  });

  test('typed destinations use clean collection routes and preserve filters',
      () {
    final href = WebsiteDestination.routeForCatalog(
      categoryId: 'category-1',
      categorySlug: 'Cámaras',
      searchQuery: '29 pulgadas',
      productType: 'product',
    );

    expect(
      href,
      '/productos/categoria/camaras?q=29+pulgadas&type=product',
    );
    final destination = WebsiteDestination.parse(href);
    expect(destination.kind, WebsiteDestinationKind.category);
    expect(destination.reference, 'camaras');
  });

  group('the category template (one look for every category page)', () {
    WebsiteCatalogPresentation category(
            {Map<String, dynamic> extra = const {}}) =>
        WebsiteCatalogPresentation.fromJson({
          'category_id': 'frenos',
          'slug': 'frenos',
          ...extra,
        });

    test('a category saved before it follows it unless its look was its own',
        () {
      // Production on 2026-10-06: every saved category at the default look.
      expect(category().ownLook, isFalse);
      expect(category(extra: {'hero_size': 'compact'}).ownLook, isTrue);
      expect(category(extra: {'facets': <String>[]}).ownLook, isTrue);
      // From then on the flag says it.
      expect(
        category(extra: {'hero_size': 'compact', 'own_look': false}).ownLook,
        isFalse,
      );
      expect(category(extra: {'own_look': true}).ownLook, isTrue);
    });

    test('a category draws the template look; its own look stays its own', () {
      final template = WebsiteCatalogPresentation.categoryTemplate().copyWith(
        heroSize: WebsiteCatalogHeroSize.compact,
        gridDensity: WebsiteCatalogGridDensity.editorial,
        showBreadcrumbs: false,
        facets: const [WebsiteCatalogFacet.brand],
      );
      final follows = category().copyWith(heroTitle: 'Frenos de disco');
      final drawn = follows.withCategoryTemplate(template);
      expect(drawn.heroSize, WebsiteCatalogHeroSize.compact);
      expect(drawn.gridDensity, WebsiteCatalogGridDensity.editorial);
      expect(drawn.showBreadcrumbs, isFalse);
      expect(drawn.facets, [WebsiteCatalogFacet.brand]);
      // Texts, photo and address stay the category's.
      expect(drawn.heroTitle, 'Frenos de disco');
      expect(drawn.slug, 'frenos');

      final own = follows.copyWith(
        ownLook: true,
        heroSize: WebsiteCatalogHeroSize.immersive,
      );
      expect(
        own.withCategoryTemplate(template).heroSize,
        WebsiteCatalogHeroSize.immersive,
      );
      // Without a saved template, the default look.
      expect(
        category(extra: {'hero_size': 'compact', 'own_look': false})
            .withCategoryTemplate(null)
            .heroSize,
        WebsiteCatalogHeroSize.standard,
      );
      // A catalog root is never a category.
      final root = WebsiteCatalogPresentation.catalogRoot(
        WebsiteCatalogRoot.products,
      );
      expect(root.withCategoryTemplate(template).gridDensity, root.gridDensity);
    });

    test('is only a look, never routed, and round-trips in the registry', () {
      final template = WebsiteCatalogPresentation.fromJson({
        'category_id': websiteCategoryTemplatePresentationId,
        'slug': 'frenos',
        'hero_title': 'Hidden',
        'seo_title': 'Hidden',
        'hero_size': 'compact',
        'grid_density': 'compact',
      });
      expect(template.isCategoryTemplate, isTrue);
      expect(template.isCategoryPresentation, isFalse);
      expect(template.heroTitle, isEmpty);
      expect(template.seoTitle, isEmpty);
      expect(template.slug, 'categorias');
      expect(template.heroSize, WebsiteCatalogHeroSize.compact);

      final registry = const WebsiteCatalogPresentationRegistry({})
          .put(category().copyWith(slug: 'categorias'))
          .put(template);
      final decoded = WebsiteCatalogPresentationRegistry.decode(
        registry.encode(),
      );
      expect(decoded.categoryTemplate?.gridDensity,
          WebsiteCatalogGridDensity.compact);
      expect(
          decoded.forCategory(websiteCategoryTemplatePresentationId), isNull);
      // Its slug claims no address: the category called «categorias» keeps it.
      expect(decoded.resolveSlug('categorias')?.presentation.ownerId, 'frenos');
      expect(decoded.categoryPresentationCount, 1);
      expect(
        decoded.drawnCategory(decoded.forCategory('frenos')!).gridDensity,
        WebsiteCatalogGridDensity.compact,
      );
    });
  });
}
