import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../support/library_source.dart';

/// Ownership and save-atomicity guardrails for the public site configuration.
///
/// These are source-contract assertions because the regressions they catch are
/// structural: "who writes this key" and "how many upserts does one save
/// issue" are not observable from a rendered frame.
void main() {
  final settingsPage = File(
    'lib/modules/website/pages/website_settings_page.dart',
  ).readAsStringSync();
  final websiteService = readLibrarySource('lib/modules/website/services/website_service.dart');
  final companyProfile = File(
    'lib/modules/settings/services/company_profile_service.dart',
  ).readAsStringSync();
  final productForm = File(
    'lib/modules/inventory/pages/product_form_page.dart',
  ).readAsStringSync();
  final syncScript = File('scripts/sync_seo_index.sh').readAsStringSync();

  group('the whole form saves in one operation', () {
    test('the page uses saveSettings and never a per-key loop', () {
      expect(settingsPage, contains('await service.saveSettings(settings)'));
      expect(
        settingsPage,
        isNot(contains('await service.saveSetting(entry.key, entry.value)')),
        reason: 'a per-key loop leaves the site half configured on failure',
      );
      expect(settingsPage, isNot(contains('for (final entry in settings')));
    });

    test('the service persists the normalized map in one atomic upsert', () {
      expect(
        websiteService,
        contains(".upsert(rows, onConflict: 'tenant_id,key')"),
      );
      expect(
        websiteService,
        contains('website_settings_tenant_key_unique'),
      );
      expect(
        websiteService,
        isNot(contains('// Update or insert each setting individually')),
      );
      expect(
        websiteService,
        isNot(contains('for (final entry in values.entries) {')),
      );
      expect(
        websiteService.indexOf('.upsert(rows'),
        lessThan(websiteService.indexOf('_settings.addAll(normalizedValues)')),
        reason: 'the cache must change only after the database commit succeeds',
      );
    });
  });

  group('the company profile stays the single writer of its own keys', () {
    // Every key `CompanyProfileService` projects into `website_settings` must
    // stay out of this page's save map. That projection skips empty values, so
    // a second writer's cleared value is silently resurrected.
    const companyOwnedKeys = [
      'business_legal_name',
      'business_tax_id',
      'seo_address_street',
      'seo_address_city',
      'seo_address_region',
      'seo_address_postal',
      'seo_address_country',
    ];

    test('the projection still owns them', () {
      for (final key in companyOwnedKeys) {
        expect(
          companyProfile,
          contains("put('$key'"),
          reason: '$key must remain owned by the company profile',
        );
      }
    });

    test('the settings page never writes them', () {
      for (final key in companyOwnedKeys) {
        expect(
          settingsPage,
          isNot(contains("'$key':")),
          reason: '$key must not become a second writer here',
        );
      }
    });

    test('the settings page exposes them read-only with an owner handoff', () {
      for (final key in companyOwnedKeys) {
        expect(
          settingsPage,
          contains("key: '$key'"),
          reason: '$key must stay visible where SEO is configured',
        );
      }
      expect(settingsPage, contains("context.push('/settings/company')"));
      expect(settingsPage, contains('Sin definir'));
    });
  });

  group('seo_ga_id has exactly one owner', () {
    test('the settings page writes it', () {
      expect(settingsPage, contains("'seo_ga_id':"));
      expect(settingsPage, contains("service.getSetting('seo_ga_id', '')"));
    });

    test('it is validated with the same shape the publish script enforces', () {
      expect(settingsPage, contains(r"RegExp(r'^G-[A-Z0-9]+$')"));
      expect(syncScript, contains(r'^G-[A-Z0-9]+$'));
      expect(syncScript, contains('require_nonempty_setting "seo_ga_id"'));
    });
  });

  test('SEO --check covers every deterministic social and identity projection',
      () {
    for (final expectedCheck in const [
      'Open Graph URL',
      'Open Graph title',
      'Open Graph description',
      'Open Graph site name',
      'Open Graph image',
      'Twitter card',
      'Twitter URL',
      'Twitter title',
      'Twitter description',
      'Twitter image',
      'Apple application title',
      '.areaServed["@type"] == "Country"',
      '.contactPoint.areaServed == \$country_code',
      '.sameAs == [\$instagram]',
      'require_index_absence "Open Graph image"',
      'require_index_absence "Twitter image"',
    ]) {
      expect(
        syncScript,
        contains(expectedCheck),
        reason: '--check must reject a stale $expectedCheck projection',
      );
    }
  });

  group('the product form holds no site-level Google target or action', () {
    test('no hardcoded domain, project reference or account id', () {
      for (final hardcode in const [
        'vinabike.cl',
        'sc-domain%3A',
        'merchants.google.com/mc/items',
        'google-merchant-feed?domain',
        'supabase.co/functions/v1',
      ]) {
        expect(
          productForm,
          isNot(contains(hardcode)),
          reason: 'the product form must not hardcode $hardcode',
        );
      }
    });

    test('no secret name is recited to the operator', () {
      for (final secret in const [
        'GOOGLE_SERVICE_ACCOUNT_EMAIL',
        'GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY',
        'GOOGLE_MERCHANT_ACCOUNT_ID',
      ]) {
        expect(productForm, isNot(contains(secret)));
      }
    });

    test('site operations moved out and only the diagnostic remains', () {
      expect(productForm, isNot(contains("'submit_sitemap'")));
      expect(productForm, isNot(contains("'refresh_merchant_feed'")));
      expect(productForm, isNot(contains("'google-oauth-callback'")));
      // The product-scoped diagnostic is exactly what should stay.
      expect(productForm, contains("'google-product-diagnostics'"));
      expect(productForm, contains("context.push('/website/seo')"));
    });

    test('the public product URL comes from the tenant origin', () {
      expect(
        productForm,
        contains('WebsiteSeoSettingsAliases.normalizeHttpsOrigin'),
      );
      expect(
          productForm, contains("websiteService.getSetting('store_url', '')"));
    });

    test('the Search Console property is read, never composed', () {
      expect(productForm, contains('_reportedSearchConsoleProperty'));
      expect(
        productForm,
        contains("searchConsole['siteUrl']?.toString()"),
      );
    });
  });
}
