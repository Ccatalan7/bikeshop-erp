import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/public_store/services/public_page_publication.dart';
import '../support/library_source.dart';

WebsitePage _page(
  String slug, {
  required bool published,
  String? id,
}) {
  final now = DateTime.utc(2026, 7, 28);
  return WebsitePage(
    id: id ?? 'page-$slug',
    tenantId: 'tenant',
    slug: slug,
    title: slug,
    isPublished: published,
    createdAt: now,
    updatedAt: now,
  );
}

WebsiteNavigation _navigation(
  String label,
  String href, {
  List<WebsiteNavigation> children = const [],
}) {
  final now = DateTime.utc(2026, 7, 28);
  return WebsiteNavigation(
    id: 'nav-$label',
    tenantId: 'tenant',
    label: label,
    linkType: href.isEmpty ? NavLinkType.action : NavLinkType.page,
    linkValue: href,
    children: children,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('PublicPagePublication', () {
    test('website_pages is the only publication owner', () {
      final publication = PublicPagePublication.resolve(
        pages: [
          _page('terminos', published: true),
          _page('privacidad', published: false),
          _page('campana', published: true),
        ],
        isAuthoritative: true,
      );

      expect(publication.allowsHref('/terminos'), isTrue);
      expect(publication.allowsHref('/terminos?ref=footer#alcance'), isTrue);
      expect(publication.allowsHref('/privacidad'), isFalse);
      expect(publication.allowsHref('/privacidad#datos'), isFalse);
      expect(publication.allowsHref('/pagina/campana'), isTrue);
      expect(publication.allowsHref('/pagina/borrador'), isFalse);
      expect(publication.allowsHref('/productos'), isTrue);
    });

    test('legacy page UUID links cannot bypass publication', () {
      final publication = PublicPagePublication.resolve(
        pages: [
          _page('campana', published: true, id: 'published-page-id'),
          _page('borrador', published: false, id: 'draft-page-id'),
        ],
        isAuthoritative: true,
      );

      expect(publication.isManagedHref('published-page-id'), isTrue);
      expect(publication.allowsHref('published-page-id'), isTrue);
      expect(publication.isManagedHref('/draft-page-id'), isTrue);
      expect(publication.allowsHref('/draft-page-id'), isFalse);
      expect(publication.allowsHref('/unknown-product-id'), isTrue);
    });

    test('unknown publication fails closed only for editor-owned pages', () {
      final publication = PublicPagePublication.resolve(
        pages: [_page('terminos', published: true)],
        isAuthoritative: false,
      );

      expect(publication.allowsHref('/terminos'), isFalse);
      expect(publication.allowsHref('/pagina/campana'), isFalse);
      expect(publication.allowsHref('/productos'), isTrue);
      expect(publication.allowsHref('https://external.example/path'), isTrue);
    });

    test('same-store absolute URLs consume the same publication truth', () {
      final publication = PublicPagePublication.resolve(
        pages: [_page('terminos', published: true)],
        isAuthoritative: true,
        internalOrigins: [Uri.parse('https://vinabike.cl')],
      );

      expect(
        publication.allowsHref('https://vinabike.cl/terminos'),
        isTrue,
      );
      expect(
        publication.allowsHref('https://vinabike.cl/devoluciones'),
        isFalse,
      );
      expect(
        publication.allowsHref('https://example.com/devoluciones'),
        isTrue,
      );
      expect(publication.allowsHref('/tienda/terminos'), isTrue);
      expect(publication.allowsHref('/tienda/devoluciones'), isFalse);
      expect(
        publication.allowsHref(
          'https://vinabike.cl/tienda/devoluciones',
        ),
        isFalse,
      );
    });

    test('unresolved typed page UUID navigation fails closed', () {
      final publication = PublicPagePublication.resolve(
        pages: const [],
        isAuthoritative: true,
      );
      final unresolved = _navigation(
        'Borrador legado',
        '8ec0b97a-6d65-48ab-9b32-58cda6222169',
      );

      expect(publication.canNavigate(unresolved), isFalse);
      expect(publication.forDesktop([unresolved]), isEmpty);
    });

    test('navigation removes a draft label and promotes published children',
        () {
      final publication = PublicPagePublication.resolve(
        pages: [
          _page('borrador', published: false),
          _page('campana', published: true),
        ],
        isAuthoritative: true,
      );
      final projected = publication.forDesktop([
        _navigation(
          'Información',
          '',
          children: [
            _navigation(
              'Borrador',
              '/pagina/borrador',
              children: [
                _navigation('Campaña', '/pagina/campana'),
              ],
            ),
          ],
        ),
      ]);

      expect(projected, hasLength(1));
      expect(projected.single.label, 'Información');
      expect(projected.single.children.map((item) => item.label), ['Campaña']);
      expect(
        projected.single.children.single.href,
        '/pagina/campana',
      );
    });

    test('unpublished top-level owner survives only as a non-clickable group',
        () {
      final publication = PublicPagePublication.resolve(
        pages: [
          _page('terminos', published: false),
          _page('privacidad', published: true),
        ],
        isAuthoritative: true,
      );
      final projected = publication.forDesktop([
        _navigation(
          'Información',
          '/terminos',
          children: [_navigation('Privacidad', '/privacidad')],
        ),
      ]);

      expect(projected.single.label, 'Información');
      expect(projected.single.href, isNull);
      expect(projected.single.children.single.href, '/privacidad');
    });
  });

  test('storefront consumers share the authoritative page boundary', () {
    final bootstrap =
        File('lib/public_store/widgets/public_store_bootstrap.dart')
            .readAsStringSync();
    final layout = readLibrarySource('lib/public_store/widgets/public_store_layout.dart');
    final service = readLibrarySource('lib/modules/website/services/website_service.dart');

    expect(bootstrap, contains('pagePublicationPreflight'));
    expect(
      layout,
      contains('_pagePublication.forAllAudiences(footerNavItems)'),
    );
    expect(layout, contains('_pagePublication.allowsHref(href)'));
    expect(
      service,
      contains('hasAuthoritativePagePublicationForTenant'),
    );
    expect(service, contains('_pageLoadsByTenant'));
    expect(
      bootstrap,
      contains('websiteService.loadPagesForTenant('),
    );
  });
}
