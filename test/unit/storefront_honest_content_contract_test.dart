import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/public_store/services/public_page_publication.dart';
import 'package:vinabike_erp/public_store/widgets/public_store_layout.dart';
import '../support/library_source.dart';

/// The storefront may only state what its owner actually configured.
///
/// Three separate ways this was violated, each fixed here:
///
/// 1. the footer invented navigation the owner never placed;
/// 2. `/contacto` stayed public and indexable without a published owner; and
/// 3. contact data, social accounts, delivery promises, payment badges and the
///    product canonical fell back to one specific tenant's real values.
void main() {
  final layoutSource = readLibrarySource('lib/public_store/widgets/public_store_layout.dart');
  final contactSource = File(
    'lib/public_store/pages/contact_page.dart',
  ).readAsStringSync();
  final productSource = File(
    'lib/public_store/pages/product_detail_page.dart',
  ).readAsStringSync();

  group('footer renders only persisted navigation', () {
    test('no fabricated quick links remain in either renderer', () {
      // Both empty branches must return an empty list rather than a
      // renderer-authored column.
      expect(
        layoutSource,
        contains('if (desktopItems.isEmpty) {\n      // Navigation is '
            'editor-owned.'),
      );
      expect(layoutSource, contains('if (mobileItems.isEmpty) {'));
      expect(
        RegExp(r'return const <Widget>\[\];').allMatches(layoutSource).length,
        greaterThanOrEqualTo(2),
        reason: 'desktop and mobile empty branches must both render nothing',
      );
    });

    test('the dead fabricated-link helper is gone', () {
      expect(layoutSource, isNot(contains('_buildFooterLinkDesktop')));
    });

    test('legal links are never renderer-authored either', () {
      // The old empty branch hardcoded these labels. Persisted navigation is
      // the only source now.
      for (final label in const [
        "'Términos y Condiciones',\n                  primaryColor",
        "'Política de Privacidad',\n                  primaryColor",
      ]) {
        expect(layoutSource, isNot(contains(label)));
      }
    });
  });

  group('/contacto publication is owned by website_pages', () {
    WebsitePage page({
      required String slug,
      required bool isPublished,
    }) {
      final now = DateTime.utc(2026, 1, 1);
      return WebsitePage(
        id: 'page-$slug',
        tenantId: 'tenant',
        slug: slug,
        title: slug,
        isPublished: isPublished,
        createdAt: now,
        updatedAt: now,
      );
    }

    test('/contacto is a managed clean path', () {
      expect(
        PublicPagePublication.managedCleanPaths,
        contains('/contacto'),
      );
    });

    test('/servicios is NOT managed: its owner is the catalog root', () {
      expect(
        PublicPagePublication.managedCleanPaths,
        isNot(contains('/servicios')),
        reason: 'gating /servicios here would give it a second publisher',
      );
    });

    test('a draft /contacto is not linkable', () {
      final publication = PublicPagePublication.resolve(
        pages: [page(slug: 'contacto', isPublished: false)],
        isAuthoritative: true,
      );
      expect(publication.allowsHref('/contacto'), isFalse);
      expect(publication.isPublishedPath('/contacto'), isFalse);
    });

    test('a published /contacto is linkable', () {
      final publication = PublicPagePublication.resolve(
        pages: [page(slug: 'contacto', isPublished: true)],
        isAuthoritative: true,
      );
      expect(publication.allowsHref('/contacto'), isTrue);
    });

    test('/servicios stays linkable regardless of website_pages', () {
      final publication = PublicPagePublication.resolve(
        pages: [page(slug: 'contacto', isPublished: false)],
        isAuthoritative: true,
      );
      expect(publication.allowsHref('/servicios'), isTrue);
    });

    test('runtime SEO consults the owner for managed clean paths', () {
      expect(layoutSource, contains('seoOwnerIsPublished'));
      expect(
        layoutSource,
        contains('PublicPagePublication.managedCleanPaths.contains'),
      );
      expect(layoutSource, contains('ownerIsPublished: seoOwnerIsPublished'));
    });

    test('the page stays reachable for Preview and Edit', () {
      expect(contactSource, contains('editProvider.isInEditorContext'));
      expect(
        contactSource,
        contains('if (!isEditorContext &&'),
      );
      expect(contactSource, contains('_ContactUnavailable'));
    });
  });

  group('social values normalize from handle or URL', () {
    test('a bare handle becomes the network profile URL', () {
      expect(
        normalizeSocialUrl('tienda', 'https://instagram.com/'),
        'https://instagram.com/tienda',
      );
      expect(
        normalizeSocialUrl('@tienda', 'https://instagram.com/'),
        'https://instagram.com/tienda',
      );
    });

    test('an absolute URL is preserved', () {
      expect(
        normalizeSocialUrl(
          'https://facebook.com/mi-tienda',
          'https://facebook.com/',
        ),
        'https://facebook.com/mi-tienda',
      );
    });

    test('a scheme-less absolute value gains https', () {
      expect(
        normalizeSocialUrl(
            'www.instagram.com/tienda', 'https://instagram.com/'),
        'https://www.instagram.com/tienda',
      );
    });

    test('YouTube keeps the @ its canonical handle URL requires', () {
      expect(
        normalizeSocialUrl(
          '@canal',
          'https://youtube.com/',
          keepAtPrefix: true,
        ),
        'https://youtube.com/@canal',
      );
    });

    test('an unset network is omitted, never substituted', () {
      expect(normalizeSocialUrl('', 'https://instagram.com/'), isNull);
      expect(normalizeSocialUrl('   ', 'https://instagram.com/'), isNull);
      expect(normalizeSocialUrl('@', 'https://instagram.com/'), isNull);
    });

    test('a non-web scheme can never become a footer link', () {
      expect(
        normalizeSocialUrl('javascript:alert(1)', 'https://instagram.com/'),
        isNull,
      );
      expect(
        normalizeSocialUrl('mailto:a@b.cl', 'https://instagram.com/'),
        isNull,
      );
    });
  });

  // Payment claims moved to the tenant-scoped `PublicCheckoutCapabilities`
  // contract; their coverage lives in
  // `storefront_payment_claim_contract_test.dart`.

  group('no functional tenant fallback remains', () {
    test('contact fields omit rather than substitute', () {
      for (final fabricated in const [
        "'contacto@vinabike.cl'",
        "'+56 9 9835 7797'",
        "'+56998357797'",
        'Álvarez 32',
        "'Viñabike'",
      ]) {
        expect(
          contactSource,
          isNot(contains(fabricated)),
          reason: 'contact page must not fall back to $fabricated',
        );
      }
    });

    test('the address row is conditional like phone and email', () {
      expect(contactSource, contains('if (contactAddress.isNotEmpty)'));
    });

    test('the mail action is disabled without a mailbox', () {
      expect(contactSource, contains("contactEmail.trim().isEmpty"));
    });

    test('product canonical and JSON-LD never claim another domain', () {
      expect(productSource, isNot(contains("'https://vinabike.cl'")));
      expect(productSource, contains('_publicStoreOrigin('));
      expect(
        productSource,
        contains('WebsiteSeoSettingsAliases.normalizeHttpsOrigin'),
      );
      // With no trustworthy origin the structured data is dropped rather than
      // published against a foreign domain.
      expect(
        productSource,
        contains('removeStructuredDataScript(_structuredDataScriptId);'),
      );
    });

    test('delivery and pickup promises come from settings', () {
      for (final fabricated in const [
        "'Despacho a Chile continental'",
        "'Entrega estimada de 3 a 12 días hábiles.'",
        'Alvarez 32, Local 17',
      ]) {
        expect(productSource, isNot(contains(fabricated)));
      }
      expect(productSource, contains('_buildFulfilmentPromises('));
      expect(productSource, contains("'shipping_promise_title'"));
    });

    test('the YouTube channel is no longer a shared default', () {
      expect(layoutSource,
          isNot(contains("'youtube_handle', '@vinabikechannel'")));
    });

    test('the copyright names the store or nobody', () {
      expect(
        layoutSource,
        isNot(contains("storeName.isNotEmpty ? storeName : 'Vinabike'")),
      );
    });
  });
}
