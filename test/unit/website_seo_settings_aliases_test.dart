import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_seo_settings_aliases.dart';

void main() {
  group('WebsiteSeoSettingsAliases', () {
    test('promotes legacy metadata updates to the canonical family', () {
      final normalized = WebsiteSeoSettingsAliases.normalize({
        'meta_title': 'Taller de bicicletas en Viña del Mar',
        'meta_description': 'Mantención y repuestos para tu bicicleta.',
        'meta_keywords': 'taller bicicletas, repuestos',
      });

      expect(
        normalized['seo_meta_title'],
        'Taller de bicicletas en Viña del Mar',
      );
      expect(
        normalized['seo_meta_description'],
        'Mantención y repuestos para tu bicicleta.',
      );
      expect(
        normalized['seo_meta_keywords'],
        'taller bicicletas, repuestos',
      );
    });

    test('canonical updates win and remain mirrored, including clears', () {
      final normalized = WebsiteSeoSettingsAliases.normalize({
        'seo_meta_title': '',
        'meta_title': 'Valor obsoleto',
      });

      expect(normalized['seo_meta_title'], isEmpty);
      expect(normalized['meta_title'], isEmpty);
    });

    test('store URL is the unique canonical-base owner', () {
      final normalized = WebsiteSeoSettingsAliases.normalize({
        'store_url': 'https://tienda.ejemplo.cl/',
        'seo_canonical_url': 'https://dominio-obsoleto.example',
      });

      expect(
        normalized['store_url'],
        'https://tienda.ejemplo.cl',
      );
      expect(
        normalized['seo_canonical_url'],
        'https://tienda.ejemplo.cl',
      );
    });

    test('canonical base accepts only a clean HTTPS origin', () {
      expect(
        WebsiteSeoSettingsAliases.normalizeHttpsOrigin(
          'https://vinabike.cl/',
        ),
        'https://vinabike.cl',
      );
      expect(
        WebsiteSeoSettingsAliases.normalizeHttpsOrigin(
          'https://vinabike.cl/productos?category=1',
        ),
        isEmpty,
      );
      expect(
        WebsiteSeoSettingsAliases.normalizeHttpsOrigin(
          'http://vinabike.cl',
        ),
        isEmpty,
      );
      expect(
        WebsiteSeoSettingsAliases.normalizeHttpsOrigin(
          'https://user:secret@vinabike.cl',
        ),
        isEmpty,
      );
    });
  });

  test('site settings is the single writer and SEO center routes back to it',
      () {
    final settingsSource = File(
      'lib/modules/website/pages/website_settings_page.dart',
    ).readAsStringSync();
    final centerSource = File(
      'lib/modules/website/pages/seo_settings_page.dart',
    ).readAsStringSync();

    expect(settingsSource, contains("context.push('/website/seo')"));
    expect(settingsSource, contains("'seo_meta_title':"));
    expect(settingsSource, contains("'seo_meta_description':"));
    expect(settingsSource, contains("'seo_meta_keywords':"));
    expect(settingsSource, contains("'seo_og_image':"));
    expect(settingsSource, contains('WebsiteImagePickerField('));
    expect(settingsSource, isNot(contains("'meta_title':")));
    expect(settingsSource, isNot(contains("'meta_description':")));
    expect(settingsSource, isNot(contains("'meta_keywords':")));
    expect(
      centerSource,
      contains("route: '/website/settings?section=seo'"),
    );
  });

  test('initial HTML generation uses the same domain and locality owners', () {
    final source = File('scripts/sync_seo_index.sh').readAsStringSync();

    expect(
      source,
      contains(r'CANONICAL_URL=$(get_setting "store_url" "")'),
    );
    expect(
      source,
      contains(
        r'ADDRESS_CITY=$(get_setting "seo_address_city" '
        r'"$(get_setting "seo_address_locality"',
      ),
    );
    expect(
      source,
      isNot(contains(r'CANONICAL_URL=$(get_setting "seo_canonical_url"')),
    );
    expect(
      source,
      contains('require_https_origin "store_url" "\$CANONICAL_URL"'),
    );
    expect(source, isNot(contains('PUBLISHED_TRUST_PAGES=')));
    expect(source, isNot(contains('page_is_published')));
    expect(source, isNot(contains(r'$LEGAL_LINKS_HTML')));
    expect(
      source.indexOf('if [[ "\$CHECK_ONLY" == true ]]'),
      greaterThan(source.indexOf('require_nonempty_setting "seo_ga_id"')),
    );
    expect(source, contains('web/index.html is stale for \$label'));
    expect(source, contains('require_nonempty_setting "business_legal_name"'));
    expect(source, contains('require_nonempty_setting "business_tax_id"'));
    expect(
      source,
      isNot(contains('get_setting "business_legal_name" "NEWEN SpA"')),
    );
    expect(
      source,
      isNot(contains('get_setting "business_tax_id" "77.541.999-7"')),
    );
    expect(source, isNot(contains('/politica-de-reembolso')));
    expect(source, isNot(contains('/terminos-y-condiciones')));
  });
}
