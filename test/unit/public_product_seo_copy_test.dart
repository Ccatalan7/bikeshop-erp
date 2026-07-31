import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/models/public_product_seo_copy.dart';

void main() {
  test('typed input resolves CLP, HTML, fallback and primary phrase once', () {
    final copy = resolvePublicProductSeoCopyFromInput(
      const PublicProductSeoCopyInput(
        product: PublicProductSeoProductInput(
          name: '&lt;b&gt;Cámara urbana&lt;/b&gt;',
          sku: 'CAM-26',
          price: 15990,
          brand: 'Marca &amp; Co.',
          description: '<p>Uso diario&nbsp;y recreativo.</p>',
          categoryPath: 'Componentes / Cámaras',
        ),
        storeName: 'Viñabike',
        locality: 'Viña del Mar',
        titleTemplate: '{product_name} {product_price} | {store_name}',
        descriptionTemplate: '',
        searchTerms: [
          'cámara bicicleta Viña del Mar',
          'frase secundaria inerte',
        ],
      ),
    );

    expect(copy.title, contains(r'$ 15.990'));
    expect(copy.title, isNot(contains('<b>')));
    expect(copy.description, contains('Marca & Co.'));
    expect(copy.description, contains('Ideal si buscas cámara bicicleta'));
    expect(copy.description, isNot(contains('frase secundaria')));
    expect(copy.description, isNot(contains('retiro en tienda')));
    expect(copy.description, isNot(contains('asesoría especializada')));
    expect(copy.searchPhrase, 'cámara bicicleta Viña del Mar');
  });

  test('typed input preserves sanitized explicit overrides', () {
    final copy = resolvePublicProductSeoCopyFromInput(
      const PublicProductSeoCopyInput(
        product: PublicProductSeoProductInput(
          name: 'Producto',
          sku: 'SKU',
          price: 1000,
          brand: '',
          description: '',
        ),
        storeName: 'Tienda',
        locality: '',
        titleTemplate: '{product_name}',
        descriptionTemplate: '{product_description}',
        seoTitleOverride: '<strong>Título editorial</strong>',
        seoDescriptionOverride: '<p>Descripción editorial &amp; precisa.</p>',
        searchTerms: ['frase que no debe alterar el override'],
      ),
    );

    expect(copy.title, 'Título editorial');
    expect(copy.description, 'Descripción editorial & precisa.');
    expect(copy.titleSource, PublicProductSeoValueSource.explicit);
    expect(copy.descriptionSource, PublicProductSeoValueSource.explicit);
  });

  test('generated copy uses one explicit search phrase consistently', () {
    final copy = resolvePublicProductSeoCopy(
      seoTitleOverride: '',
      seoDescriptionOverride: '',
      generatedTitleBase: 'Cámara aro 26 | Viñabike',
      generatedDescriptionBase: 'Cámara resistente para uso urbano.',
      fallbackDescription: 'Producto disponible.',
      storeName: 'Viñabike',
      locality: 'Viña del Mar',
      searchTerms: const [
        'cámara bicicleta aro 26 en Viña del Mar',
        'segunda frase que no se debe apilar',
      ],
    );

    expect(copy.title, contains('Viñabike Viña del Mar'));
    expect(copy.title, contains('Cámara aro 26'));
    expect('aro 26'.allMatches(copy.title), hasLength(1));
    expect(copy.description, contains('Ideal si buscas cámara bicicleta'));
    expect(copy.description, isNot(contains('segunda frase')));
    expect(copy.titleSource, PublicProductSeoValueSource.generated);
    expect(copy.descriptionSource, PublicProductSeoValueSource.generated);
  });

  test('hand-written metadata is never rewritten with search terms', () {
    final copy = resolvePublicProductSeoCopy(
      seoTitleOverride: 'Título editorial',
      seoDescriptionOverride: 'Descripción editorial precisa.',
      generatedTitleBase: 'Base',
      generatedDescriptionBase: 'Base',
      fallbackDescription: 'Fallback',
      storeName: 'Tienda',
      locality: 'Valparaíso',
      searchTerms: const ['frase objetivo'],
    );

    expect(copy.title, 'Título editorial');
    expect(copy.description, 'Descripción editorial precisa.');
    expect(copy.titleSource, PublicProductSeoValueSource.explicit);
    expect(copy.descriptionSource, PublicProductSeoValueSource.explicit);
  });

  test('generated description does not duplicate an existing phrase', () {
    final copy = resolvePublicProductSeoCopy(
      seoTitleOverride: '',
      seoDescriptionOverride: '',
      generatedTitleBase: 'Cadena',
      generatedDescriptionBase:
          'Cadena para bicicleta de nueve velocidades en Viña del Mar.',
      fallbackDescription: '',
      storeName: 'Tienda',
      locality: 'Viña del Mar',
      searchTerms: const [
        'cadena para bicicleta de nueve velocidades',
      ],
    );

    expect('Ideal si buscas'.allMatches(copy.description), isEmpty);
  });

  test('runtime, editor preview and snapshot use the typed resolver', () {
    final runtime = File('lib/public_store/pages/product_detail_page.dart')
        .readAsStringSync();
    final editor = File('lib/modules/inventory/pages/product_form_page.dart')
        .readAsStringSync();
    final snapshot =
        File('scripts/generate_product_seo_snapshots.dart').readAsStringSync();

    for (final source in [runtime, editor, snapshot]) {
      expect(source, contains('resolvePublicProductSeoCopyFromInput('));
      expect(source, contains('PublicProductSeoCopyInput('));
    }
    expect(
      editor,
      contains('PublicCommerceProductProjection.fromDraft('),
    );
    expect(snapshot, isNot(contains('_buildProductSeoTitle(')));
    expect(snapshot, isNot(contains('_appendProductSearchPhrase(')));
  });
}
