import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_erp/modules/website/models/website_destination.dart';
import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/public_store/services/public_category_publication.dart';

PublicCategoryDescriptor _category(
  String id,
  String name, {
  String? fullPath,
  bool showOnWebsite = false,
}) {
  return PublicCategoryDescriptor(
    id: id,
    name: name,
    fullPath: fullPath ?? name,
    showOnWebsite: showOnWebsite,
  );
}

WebsiteNavigation _categoryLink(
  String label,
  String linkValue, {
  bool isVisible = true,
  bool showOnDesktop = true,
  bool showOnMobile = true,
  List<WebsiteNavigation> children = const [],
}) {
  final now = DateTime(2026, 1, 1);
  return WebsiteNavigation(
    id: 'nav-${websiteNavigationTestSlug(label)}',
    tenantId: 'tenant',
    label: label,
    linkType: NavLinkType.category,
    linkValue: linkValue,
    isVisible: isVisible,
    showOnDesktop: showOnDesktop,
    showOnMobile: showOnMobile,
    children: children,
    createdAt: now,
    updatedAt: now,
  );
}

WebsiteNavigation _pageLink(String label, String linkValue) {
  final now = DateTime(2026, 1, 1);
  return WebsiteNavigation(
    id: 'nav-${websiteNavigationTestSlug(label)}',
    tenantId: 'tenant',
    label: label,
    linkType: NavLinkType.page,
    linkValue: linkValue,
    createdAt: now,
    updatedAt: now,
  );
}

String websiteNavigationTestSlug(String raw) =>
    raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

const _cadenasId = '11111111-1111-4111-8111-111111111111';
const _frenosId = '22222222-2222-4222-8222-222222222222';
const _rueditasId = '33333333-3333-4333-8333-333333333333';
const _componentesId = '44444444-4444-4444-8444-444444444444';
const _transmisionId = '55555555-5555-4555-8555-555555555555';
const _pinonesId = '66666666-6666-4666-8666-666666666666';
const _cassetteId = '77777777-7777-4777-8777-777777777777';

void main() {
  group('PublicCategoryPublication', () {
    test('publication is exactly the flagged set', () {
      final publication = PublicCategoryPublication.resolve(
        categories: [
          _category(_cadenasId, 'Cadenas', showOnWebsite: true),
          _category(_frenosId, 'Frenos'),
        ],
        navigation: const [],
      );

      expect(publication.isPublished(_cadenasId), isTrue);
      expect(publication.isPublished(_frenosId), isFalse);
      expect(publication.menuOnlyCategoryIds, isEmpty);
    });

    test('a menu link never publishes: it surfaces as a pending data fix', () {
      // Ownership is asymmetric: show_on_website owns publication, the menu
      // owns placement. A menu row targeting an unpublished category is a
      // misconfiguration to report — the renderer must not widen publication.
      final publication = PublicCategoryPublication.resolve(
        categories: [
          _category(_cadenasId, 'Cadenas', showOnWebsite: true),
          _category(_frenosId, 'Frenos'),
        ],
        navigation: [
          _categoryLink('Frenos', '/productos?category=$_frenosId'),
        ],
      );

      expect(publication.isPublished(_frenosId), isFalse);
      expect(publication.menuOnlyCategoryIds, contains(_frenosId));
      expect(publication.unresolvedNavigationTokens, isEmpty);
    });

    test('diagnostics resolve every link_value shape the editor has written',
        () {
      final publication = PublicCategoryPublication.resolve(
        categories: [
          _category(_cadenasId, 'Cadenas'),
          _category(_frenosId, 'Frenos'),
          _category(_rueditasId, 'Rueda Estabilizadora'),
        ],
        navigation: [
          // Bare id (oldest rows).
          _categoryLink('Cadenas', _cadenasId),
          // Legacy query destination.
          _categoryLink('Frenos', '/productos?category=$_frenosId'),
          // Clean collection path written by the current editor.
          _categoryLink(
            'Rueda Estabilizadora',
            '/productos/categoria/rueda-estabilizadora?category_scope=direct',
          ),
        ],
      );

      // None are flagged, so none are published — but every shape resolves
      // into an actionable diagnostic instead of vanishing.
      expect(publication.publishedIds, isEmpty);
      expect(
        publication.menuOnlyCategoryIds,
        containsAll(<String>[_cadenasId, _frenosId, _rueditasId]),
      );
      expect(publication.unresolvedNavigationTokens, isEmpty);
    });

    test('resolves a service collection path as well as a product one', () {
      final publication = PublicCategoryPublication.resolve(
        categories: [_category(_frenosId, 'Regulación de frenos')],
        navigation: [
          _categoryLink(
            'Regulación de frenos',
            '/servicios/categoria/regulacion-de-frenos',
          ),
        ],
      );

      expect(publication.isPublished(_frenosId), isFalse);
      expect(publication.menuOnlyCategoryIds, contains(_frenosId));
    });

    test('ignores hidden navigation items', () {
      final publication = PublicCategoryPublication.resolve(
        categories: [_category(_frenosId, 'Frenos')],
        navigation: [
          _categoryLink(
            'Frenos',
            '/productos?category=$_frenosId',
            isVisible: false,
          ),
        ],
      );

      expect(publication.isPublished(_frenosId), isFalse);
      expect(publication.menuOnlyCategoryIds, isEmpty);
    });

    test('fails closed when a slug is claimed by more than one category', () {
      // "Volante" and "Volantes" both exist in production. A duplicated leaf
      // slug must never publish an unrelated branch that happens to match.
      final publication = PublicCategoryPublication.resolve(
        categories: [
          _category(_frenosId, 'Volante', fullPath: 'Componentes / Volante'),
          _category(
            _rueditasId,
            'Volante',
            fullPath: 'Accesorios / Volante',
          ),
        ],
        navigation: [_categoryLink('Volante', '/productos/categoria/volante')],
      );

      expect(publication.publishedIds, isEmpty);
      expect(publication.unresolvedNavigationTokens, contains('volante'));
    });

    test('reports a menu destination that names no existing category', () {
      final publication = PublicCategoryPublication.resolve(
        categories: [_category(_cadenasId, 'Cadenas')],
        navigation: [
          _categoryLink('Fantasma', '/productos/categoria/fantasma'),
        ],
      );

      expect(publication.publishedIds, isEmpty);
      expect(publication.unresolvedNavigationTokens, contains('fantasma'));
    });

    test('a category link with no destination never publishes anything', () {
      final publication = PublicCategoryPublication.resolve(
        categories: [_category(_cadenasId, 'Cadenas')],
        navigation: [_categoryLink('Vacío', '   ')],
      );

      expect(publication.publishedIds, isEmpty);
      expect(publication.unresolvedNavigationTokens, isEmpty);
    });

    test('category cards intersect authored values with publication', () {
      final publication = PublicCategoryPublication.resolve(
        categories: [
          _category(_cadenasId, 'Cadenas', showOnWebsite: true),
          _category(_frenosId, 'Frenos'),
        ],
        navigation: const [],
      );

      expect(publication.allowsCategoryValue(_cadenasId), isTrue);
      expect(
        publication.allowsCategoryValue(
          '/productos?category=$_cadenasId',
        ),
        isTrue,
      );
      expect(
        publication.allowsCategoryValue('/productos/categoria/cadenas'),
        isTrue,
      );
      expect(publication.allowsCategoryValue(_frenosId), isFalse);
      expect(
        publication.allowsCategoryValue(
          '/productos?category=$_frenosId',
        ),
        isFalse,
      );
      expect(
        publication.allowsCategoryValue('/productos'),
        isFalse,
        reason: 'A generic catalog route cannot impersonate a category card.',
      );
    });

    test('href guard normalizes every internal category URL shape', () {
      final publication = PublicCategoryPublication.resolve(
        categories: [
          _category(_cadenasId, 'Cadenas', showOnWebsite: true),
          _category(_pinonesId, 'Piñones'),
        ],
        navigation: const [],
      );
      final storefrontOrigins = WebsiteDestination.resolveInternalOrigins(
        configuredUrls: const ['https://vinabike.cl'],
        ownedHosts: const [
          'vinabike-store.web.app',
          'vinabike-store.firebaseapp.com',
        ],
      );

      for (final href in <String>[
        'productos?category=$_pinonesId',
        '/productos/?category=$_pinonesId',
        '/tienda/productos/?category_id=$_pinonesId',
        'productos/categoria/pinones',
        '/tienda/productos/categoria/pinones/',
        'https://vinabike.cl/productos?category=$_pinonesId',
        'http://www.vinabike.cl/productos?category=$_pinonesId',
        'https://vinabike-store.web.app/productos?category=$_pinonesId',
      ]) {
        expect(
          publication.allowsHref(
            href,
            internalOrigins: storefrontOrigins,
          ),
          isFalse,
          reason: 'Unpublished category escaped through $href',
        );
      }

      for (final href in <String>[
        'productos?category=$_cadenasId',
        '/productos/?category=$_cadenasId',
        '/tienda/productos/?category_id=$_cadenasId',
        'productos/categoria/cadenas',
        '/tienda/productos/categoria/cadenas/',
        'https://vinabike.cl/productos?category=$_cadenasId',
        'http://www.vinabike.cl/productos?category=$_cadenasId',
        'https://vinabike-store.web.app/productos?category=$_cadenasId',
      ]) {
        expect(
          publication.allowsHref(
            href,
            internalOrigins: storefrontOrigins,
          ),
          isTrue,
          reason: 'Published category was rejected through $href',
        );
      }

      expect(
        publication.allowsHref(
          'https://otra-tienda.cl/productos?category=$_pinonesId',
          internalOrigins: storefrontOrigins,
        ),
        isTrue,
        reason: 'A different origin remains an external destination.',
      );
    });

    test('diagnostics also inspect nested menu rows', () {
      final publication = PublicCategoryPublication.resolve(
        categories: [_category(_frenosId, 'Frenos')],
        navigation: [
          _categoryLink(
            'Componentes',
            _componentesId,
            children: [
              _categoryLink(
                'Frenos',
                '/productos?category=$_frenosId',
              ),
            ],
          ),
        ],
      );

      expect(publication.menuOnlyCategoryIds, contains(_frenosId));
    });
  });

  group('PublicCategoryNavigationProjection', () {
    test('keeps only published category leaves as destinations', () {
      final published = _categoryLink('Cadenas', _cadenasId);
      final unpublished = _categoryLink('Frenos', _frenosId);
      final publication = PublicCategoryPublication.resolve(
        categories: [
          _category(_cadenasId, 'Cadenas', showOnWebsite: true),
          _category(_frenosId, 'Frenos'),
        ],
        navigation: [published, unpublished],
      );
      final projection = PublicCategoryNavigationProjection(publication);

      final desktop = projection.forDesktop([published, unpublished]);

      expect(desktop.map((item) => item.label), ['Cadenas']);
      expect(projection.canNavigate(desktop.single), isTrue);
      expect(projection.canNavigate(unpublished), isFalse);
    });

    test('retains the top menu shell only as structure for a published child',
        () {
      final child = _categoryLink('Cadenas', _cadenasId);
      final parent = _categoryLink(
        'Componentes',
        _componentesId,
        children: [child],
      );
      final publication = PublicCategoryPublication.resolve(
        categories: [
          _category(_componentesId, 'Componentes'),
          _category(_cadenasId, 'Cadenas', showOnWebsite: true),
        ],
        navigation: [parent],
      );
      final projection = PublicCategoryNavigationProjection(publication);

      final desktop = projection.forDesktop([parent]);

      expect(desktop, hasLength(1));
      expect(desktop.single.label, 'Componentes');
      expect(desktop.single.children.map((item) => item.label), ['Cadenas']);
      expect(projection.canNavigate(desktop.single), isFalse);
      expect(desktop.single.linkType, NavLinkType.action);
      expect(desktop.single.href, isNull);
      expect(projection.canNavigate(desktop.single.children.single), isTrue);
    });

    test(
        'removes an unpublished category card and promotes its published child',
        () {
      final cassette = _categoryLink('Cassette', _cassetteId);
      final pinones = _categoryLink(
        'Piñones',
        _pinonesId,
        children: [cassette],
      );
      final transmision = _categoryLink(
        'Transmisión',
        _transmisionId,
        children: [pinones],
      );
      final componentes = _categoryLink(
        'Componentes',
        _componentesId,
        children: [transmision],
      );
      final publication = PublicCategoryPublication.resolve(
        categories: [
          _category(_componentesId, 'Componentes'),
          _category(_transmisionId, 'Transmisión'),
          _category(_pinonesId, 'Piñones'),
          _category(_cassetteId, 'Cassette', showOnWebsite: true),
        ],
        navigation: [componentes],
      );
      final projection = PublicCategoryNavigationProjection(publication);

      final desktop = projection.forDesktop([componentes]);
      final projectedTransmission = desktop.single.children.single;

      expect(desktop.single.label, 'Componentes');
      expect(projectedTransmission.label, 'Transmisión');
      expect(
        projectedTransmission.children.map((item) => item.label),
        ['Cassette'],
      );
      expect(
        desktop
            .expand((item) => item.children)
            .expand((item) => item.children)
            .map((item) => item.label),
        isNot(contains('Piñones')),
      );
      expect(projection.canNavigate(projectedTransmission.children.single),
          isTrue);
    });

    test('removes an unpublished branch with no published descendants', () {
      final child = _categoryLink('Frenos', _frenosId);
      final parent = _categoryLink(
        'Componentes',
        _componentesId,
        children: [child],
      );
      final publication = PublicCategoryPublication.resolve(
        categories: [
          _category(_componentesId, 'Componentes'),
          _category(_frenosId, 'Frenos'),
        ],
        navigation: [parent],
      );
      final projection = PublicCategoryNavigationProjection(publication);

      expect(projection.forDesktop([parent]), isEmpty);
      expect(projection.forMobile([parent]), isEmpty);
    });

    test('fails closed for unresolved and not-yet-loaded category rows', () {
      final unresolved =
          _categoryLink('Fantasma', '/productos/categoria/fantasma');

      final unresolvedProjection = PublicCategoryNavigationProjection(
        PublicCategoryPublication.resolve(
          categories: [_category(_cadenasId, 'Cadenas')],
          navigation: [unresolved],
        ),
      );
      final emptyProjection = PublicCategoryNavigationProjection(
        PublicCategoryPublication.empty(),
      );

      expect(unresolvedProjection.forDesktop([unresolved]), isEmpty);
      expect(emptyProjection.forDesktop([unresolved]), isEmpty);
    });

    test('current slugs and durable aliases resolve through the same registry',
        () {
      final aliased = _categoryLink(
        'Cadenas',
        '/productos/categoria/cadenas-antiguas',
      );
      final publication = PublicCategoryPublication.resolve(
        categories: [
          _category(_cadenasId, 'Cadenas', showOnWebsite: true),
        ],
        navigation: [aliased],
        presentationRegistry: WebsiteCatalogPresentationRegistry({
          _cadenasId: WebsiteCatalogPresentation(
            categoryId: _cadenasId,
            slug: 'cadenas',
            slugAliases: const ['cadenas-antiguas'],
          ),
        }),
      );
      final projection = PublicCategoryNavigationProjection(publication);

      expect(projection.forDesktop([aliased]), hasLength(1));
      expect(projection.canNavigate(aliased), isTrue);
    });

    test('recognizes a known withdrawn route without republishing it', () {
      final publication = PublicCategoryPublication.resolve(
        categories: [
          _category(_pinonesId, 'Piñones'),
          _category(_cassetteId, 'Cassette', showOnWebsite: true),
        ],
        navigation: const [],
        presentationRegistry: WebsiteCatalogPresentationRegistry({
          _pinonesId: WebsiteCatalogPresentation(
            categoryId: _pinonesId,
            slug: 'pinones',
            slugAliases: const ['pinones-antiguos'],
          ),
        }),
      );

      for (final value in [
        _pinonesId,
        'pinones',
        '/productos/categoria/pinones-antiguos',
      ]) {
        expect(
          publication.resolveCategoryValue(value),
          _pinonesId,
          reason: value,
        );
        expect(
          publication.isKnownUnpublishedCategoryValue(value),
          isTrue,
          reason: value,
        );
      }
      expect(publication.isPublished(_pinonesId), isFalse);
      expect(
        publication.isKnownUnpublishedCategoryValue('cassette'),
        isFalse,
      );
    });

    test('unknown and ambiguous withdrawn-looking routes do not redirect', () {
      final publication = PublicCategoryPublication.resolve(
        categories: [
          _category(
            _pinonesId,
            'Volante',
            fullPath: 'Componentes / Volante',
          ),
          _category(
            _frenosId,
            'Volante',
            fullPath: 'Accesorios / Volante',
          ),
        ],
        navigation: const [],
      );

      expect(publication.resolveCategoryValue('volante'), isNull);
      expect(
        publication.isKnownUnpublishedCategoryValue('volante'),
        isFalse,
      );
      expect(
        publication.isKnownUnpublishedCategoryValue('no-existe'),
        isFalse,
      );
    });

    test('defensively gates a mistyped page row carrying a category href', () {
      final mistyped = _pageLink('Frenos', '/productos?category=$_frenosId');
      final publication = PublicCategoryPublication.resolve(
        categories: [_category(_frenosId, 'Frenos')],
        navigation: [mistyped],
      );
      final projection = PublicCategoryNavigationProjection(publication);

      expect(projection.forDesktop([mistyped]), isEmpty);
      expect(projection.canNavigate(mistyped), isFalse);
    });

    test('removes a same-store absolute URL to an unpublished category', () {
      final mistyped = _pageLink(
        'Piñones',
        'https://vinabike.cl/tienda/productos/?cat=$_pinonesId',
      );
      final storefrontOrigins = <Uri>[Uri.parse('https://vinabike.cl')];
      final publication = PublicCategoryPublication.resolve(
        categories: [_category(_pinonesId, 'Piñones')],
        navigation: [mistyped],
        internalOrigins: storefrontOrigins,
      );
      final projection = PublicCategoryNavigationProjection(
        publication,
        internalOrigins: storefrontOrigins,
      );

      expect(projection.forDesktop([mistyped]), isEmpty);
      expect(projection.canNavigate(mistyped), isFalse);
    });

    test('applies desktop and mobile visibility before retaining ancestors',
        () {
      final desktopChild = _categoryLink(
        'Cadenas',
        _cadenasId,
        showOnMobile: false,
      );
      final parent = _categoryLink(
        'Componentes',
        _componentesId,
        children: [desktopChild],
      );
      final publication = PublicCategoryPublication.resolve(
        categories: [
          _category(_componentesId, 'Componentes'),
          _category(_cadenasId, 'Cadenas', showOnWebsite: true),
        ],
        navigation: [parent],
      );
      final projection = PublicCategoryNavigationProjection(publication);

      expect(projection.forDesktop([parent]), hasLength(1));
      expect(projection.forMobile([parent]), isEmpty);
    });
  });
}
