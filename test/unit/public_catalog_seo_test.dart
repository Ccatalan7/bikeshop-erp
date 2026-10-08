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
}
