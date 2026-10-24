import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_public_core/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_public_core/public_store/seo/public_catalog_seo.dart';

void main() {
  group('category SEO without editor words', () {
    test('the title names the bicycle and the city a local search uses', () {
      expect(
        publicCategorySeoTitle(
          seoTitle: '',
          displayTitle: 'Neumáticos',
          storeName: 'Viñabike',
          storeLocality: 'Viña del Mar',
        ),
        'Neumáticos para bicicleta | Viñabike Viña del Mar',
      );
      expect(
        publicCategorySeoTitle(
          seoTitle: '',
          displayTitle: 'Bicicletas urbanas',
          storeName: 'Viñabike',
        ),
        'Bicicletas urbanas | Viñabike',
      );
      expect(
        publicCategorySeoTitle(
          seoTitle: '',
          displayTitle: 'Mantenciones',
          storeName: 'Viñabike',
          storeLocality: 'Viña del Mar',
          services: true,
        ),
        'Mantenciones de bicicleta | Viñabike Viña del Mar',
      );
    });

    test('the editor title and the category intro still win', () {
      expect(
        publicCategorySeoTitle(
          seoTitle: 'Neumáticos MTB y ruta',
          displayTitle: 'Neumáticos',
          storeName: 'Viñabike',
          storeLocality: 'Viña del Mar',
        ),
        'Neumáticos MTB y ruta',
      );
      expect(
        publicCategorySeoDescription(
          seoDescription: '',
          intro: 'Neumáticos Kenda y Maxxis.',
          productCount: 18,
          displayTitle: 'Neumáticos',
          storeName: 'Viñabike',
        ),
        'Neumáticos Kenda y Maxxis.',
      );
    });

    test('the catalog says what is sold, where and how it arrives', () {
      expect(
        publicCatalogSeoDescription(
          presentation: WebsiteCatalogPresentation.fallback(
            categoryId: '',
            categoryName: 'Productos',
          ),
          storeName: 'Viñabike',
          storeLocality: 'Viña del Mar',
        ),
        'Repuestos y accesorios para bicicleta en Viñabike, Viña del Mar, con '
        'precio y stock al día. Retiro en tienda sin costo o despacho a '
        'domicilio.',
      );
    });

    test('the fallback description states only counted facts', () {
      expect(
        publicCategorySeoDescription(
          seoDescription: '',
          intro: '',
          productCount: 18,
          displayTitle: 'Neumáticos',
          storeName: 'Viñabike',
          storeLocality: 'Viña del Mar',
        ),
        'Neumáticos para bicicleta en Viñabike, Viña del Mar: 18 productos '
        'con precio y stock al día.',
      );
      expect(
        publicCategorySeoDescription(
          seoDescription: '',
          intro: '',
          productCount: 1,
          displayTitle: 'Limpieza',
          storeName: 'Viñabike',
          services: true,
        ),
        'Limpieza de bicicleta en Viñabike: 1 servicio con precio publicado.',
      );
    });
  });

  // 2026-10-23: a Google text names the catalog's own figures.
  group('live figures in a category\'s Google texts', () {
    const facts = PublicCatalogTextFacts(
      count: 22,
      priceFrom: 3990,
      priceTo: 17990,
      brands: ['Kenda', 'Maxxis', 'Chaoyang', 'CST'],
    );

    test('each placeholder says today\'s figure', () {
      expect(
        resolvePublicCatalogText(
          '{cantidad} cámaras desde {desde} hasta {hasta}: {marcas}',
          facts,
        ),
        '22 cámaras desde \$ 3.990 hasta \$ 17.990: Kenda, Maxxis y Chaoyang',
      );
    });

    test('a figure that is not known leaves the formula its turn', () {
      const unknown = PublicCatalogTextFacts(count: 22);
      expect(resolvePublicCatalogText('Desde {desde}', unknown), isNull);
      expect(publicCatalogEditorText('Desde {desde}', unknown), '');
      expect(publicCatalogEditorText('Sin cifras', unknown), 'Sin cifras');
      expect(
        publicCategorySeoTitle(
          seoTitle: publicCatalogEditorText('Desde {desde}', unknown),
          displayTitle: 'Cámaras',
          storeName: 'Viñabike',
          storeLocality: 'Viña del Mar',
        ),
        'Cámaras para bicicleta | Viñabike Viña del Mar',
      );
    });

    test(
        'a page for a measure is named after its category and its value; '
        'a brand keeps its capital', () {
      expect(
        publicCategoryLandingDisplayTitle(
          landing: WebsiteCatalogLanding(
            slug: 'aro-26',
            label: 'Aro 26',
            specFilters: const {
              'bead_seat_diameter_mm': ['559'],
            },
          ),
          categoryTitle: 'Cámaras',
        ),
        'Cámaras aro 26',
      );
      expect(
        publicCategoryLandingDisplayTitle(
          landing: WebsiteCatalogLanding(
            slug: 'kenda',
            label: 'Kenda',
            brandIds: const ['b0000000-0000-4000-8000-00000000000a'],
          ),
          categoryTitle: 'Neumáticos',
        ),
        'Neumáticos Kenda',
      );
    });
  });
}
