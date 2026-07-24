import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_catalog_presentation.dart';

import '../../scripts/generate_product_seo_snapshots.dart' as snapshots;

void main() {
  group('canonical category SEO projection', () {
    test('uses published stable IDs, saved presentation and eligible products',
        () {
      final registry = WebsiteCatalogPresentationRegistry({
        'root': WebsiteCatalogPresentation(
          categoryId: 'root',
          slug: 'componentes-profesionales',
          slugAliases: const ['componentes'],
          heroTitle: 'Componentes',
          heroDescription: 'Componentes publicados por Viñabike.',
          heroImageUrl: 'https://cdn.example.test/componentes.webp',
          seoTitle: 'Componentes para bicicleta',
          seoDescription: 'Compra componentes publicados y compatibles.',
          socialImageUrl: 'https://cdn.example.test/componentes-social.webp',
          allowIndexing: false,
        ),
      });
      final categories = snapshots.buildCanonicalCategorySeoProjections(
        products: [
          _product(
            id: 'p-root',
            categoryId: 'root',
            name: 'Producto raíz',
            sku: 'ROOT-1',
          ),
          _product(
            id: 'p-child',
            categoryId: 'child',
            name: 'Nombre interno',
            websiteName: 'Cadena visible',
            sku: 'CHAIN-1',
          ),
          _product(
            id: 'p-hidden',
            categoryId: 'hidden',
            name: 'No debe indexar su categoría',
            sku: 'HIDDEN-1',
          ),
          {
            ..._product(
              id: 'p-name-only',
              categoryId: '',
              name: 'Cámara 29 material inventado',
              sku: 'NAME-1',
            ),
            'category_name': 'Categoría fabricada desde el título',
          },
        ],
        activeCategories: [
          _category(
            id: 'root',
            name: 'Componentes',
            fullPath: 'Componentes',
            sortOrder: 1,
          ),
          _category(
            id: 'child',
            name: 'Cadenas',
            fullPath: 'Componentes / Transmisión / Cadenas',
            parentId: 'root',
            sortOrder: 2,
          ),
          _category(
            id: 'empty',
            name: 'Vacía',
            fullPath: 'Vacía',
            sortOrder: 3,
          ),
          _category(
            id: 'hidden',
            name: 'Oculta',
            fullPath: 'Componentes / Oculta',
            parentId: 'root',
            showOnWebsite: false,
          ),
          _category(
            id: 'inactive',
            name: 'Inactiva',
            fullPath: 'Inactiva',
            isActive: false,
          ),
        ],
        presentationRegistry: registry,
        storeUrl: 'https://vinabike.cl',
      );

      expect(categories.map((category) => category.categoryId), [
        'root',
        'child',
      ]);
      final root = categories.first;
      expect(root.slug, 'componentes-profesionales');
      expect(root.slugAliases, const ['componentes']);
      expect(
          root.canonicalPath, '/productos/categoria/componentes-profesionales');
      expect(root.displayTitle, 'Componentes');
      expect(root.description, 'Componentes publicados por Viñabike.');
      expect(root.imageUrl, 'https://cdn.example.test/componentes.webp');
      expect(root.seoTitle, 'Componentes para bicicleta');
      expect(
        root.seoDescription,
        'Compra componentes publicados y compatibles.',
      );
      expect(
        root.socialImageUrl,
        'https://cdn.example.test/componentes-social.webp',
      );
      expect(root.allowIndexing, isFalse);
      expect(root.productCount, 3);
      expect(
        root.products.map((product) => product.name),
        [
          'Producto raíz',
          'Cadena visible',
          'No debe indexar su categoría',
        ],
      );

      final child = categories.last;
      expect(child.slug, 'cadenas');
      expect(child.productCount, 1);
      expect(child.products.single.name, 'Cadena visible');
    });

    test('fails closed when two non-empty public categories share a slug', () {
      final registry = WebsiteCatalogPresentationRegistry({
        'a': WebsiteCatalogPresentation(categoryId: 'a', slug: 'repetida'),
        'b': WebsiteCatalogPresentation(categoryId: 'b', slug: 'repetida'),
      });

      expect(
        () => snapshots.buildCanonicalCategorySeoProjections(
          products: [
            _product(id: 'p-a', categoryId: 'a', name: 'A', sku: 'A-1'),
            _product(id: 'p-b', categoryId: 'b', name: 'B', sku: 'B-1'),
          ],
          activeCategories: [
            _category(id: 'a', name: 'A', fullPath: 'A'),
            _category(id: 'b', name: 'B', fullPath: 'B'),
          ],
          presentationRegistry: registry,
          storeUrl: 'https://vinabike.cl',
        ),
        throwsStateError,
      );
    });

    test('fails closed when a current slug collides with a category alias', () {
      final registry = WebsiteCatalogPresentationRegistry({
        'a': WebsiteCatalogPresentation(
          categoryId: 'a',
          slug: 'componentes',
          slugAliases: const ['repuestos'],
        ),
        'b': WebsiteCatalogPresentation(
          categoryId: 'b',
          slug: 'repuestos',
        ),
      });

      expect(
        () => snapshots.buildCanonicalCategorySeoProjections(
          products: [
            _product(id: 'p-a', categoryId: 'a', name: 'A', sku: 'A-1'),
            _product(id: 'p-b', categoryId: 'b', name: 'B', sku: 'B-1'),
          ],
          activeCategories: [
            _category(id: 'a', name: 'A', fullPath: 'A'),
            _category(id: 'b', name: 'B', fullPath: 'B'),
          ],
          presentationRegistry: registry,
          storeUrl: 'https://vinabike.cl',
        ),
        throwsStateError,
      );
    });

    test('projects every durable alias for product and service category roots',
        () {
      final registry = WebsiteCatalogPresentationRegistry({
        'category-1': WebsiteCatalogPresentation(
          categoryId: 'category-1',
          slug: 'mantencion',
          slugAliases: const ['servicio-taller'],
        ),
      });

      final aliases = snapshots.buildCanonicalCategoryRouteAliasProjections(
        presentationRegistry: registry,
        activeCategories: [
          _category(
            id: 'category-1',
            name: 'Mantención',
            fullPath: 'Servicios / Mantención',
          ),
        ],
      );

      expect(
        aliases.map((alias) => alias.aliasPath),
        [
          '/productos/categoria/servicio-taller',
          '/servicios/categoria/servicio-taller',
        ],
      );
      expect(
        aliases.map((alias) => alias.canonicalPath),
        [
          '/productos/categoria/mantencion',
          '/servicios/categoria/mantencion',
        ],
      );
    });
  });

  test('sitemap accepts canonical public paths only', () {
    expect(
      snapshots.isIndexableStorefrontPathForSitemap(
        '/productos/categoria/camaras',
      ),
      isTrue,
    );
    expect(
      snapshots.isIndexableStorefrontPathForSitemap(
        '/productos/categoria/camaras?brand=brand-1&sort=price_asc',
      ),
      isFalse,
    );
    expect(
      snapshots.isIndexableStorefrontPathForSitemap(
        '/productos?q=camara&preview=true',
      ),
      isFalse,
    );
    expect(
      snapshots.isIndexableStorefrontPathForSitemap(
        '/tienda/productos/categoria/camaras',
      ),
      isFalse,
    );
    expect(
      snapshots.isIndexableStorefrontPathForSitemap(
        'https://vinabike.cl/productos',
      ),
      isFalse,
    );
  });

  test('snapshot source does not manufacture category pages or wheel SEO', () {
    final source = File(
      'scripts/generate_product_seo_snapshots.dart',
    ).readAsStringSync();

    expect(source, contains('websiteCatalogPresentationsSettingKey'));
    expect(source, contains("product['category_id']"));
    expect(source, contains('_fetchActiveProductCategories'));
    expect(source, isNot(contains('_buildProductCategories')));
    expect(source, isNot(contains('_categoryWheelSizeSummary')));
    expect(source, isNot(contains('_productSearchKind')));
    expect(source, isNot(contains('category.products.length >= 2')));
    expect(source, contains('presentation.seoTitle'));
    expect(source, contains('presentation.seoDescription'));
    expect(source, contains('presentation.socialImageUrl'));
    expect(source, contains('presentation.slugAliases'));
    expect(source, contains('for (final alias in presentation.slugAliases)'));
    expect(source, contains('for (final services in const [false, true])'));
    expect(source, contains(r"'/$root/categoria/$alias'"));
    expect(source, contains('services: services'));
    expect(
      source,
      contains('buildCanonicalCategoryRouteAliasProjections'),
    );
    expect(source, contains('allowIndexing: false'));
    expect(source, contains('_writeFirebaseStorefrontRedirects'));
    expect(source, contains("'type': 301"));
    expect(source, contains("content: allowIndexing ? 'index,follow'"));
    expect(source, contains('if (!category.allowIndexing) continue;'));
  });
}

Map<String, dynamic> _product({
  required String id,
  required String categoryId,
  required String name,
  required String sku,
  String? websiteName,
}) {
  return {
    'id': id,
    'category_id': categoryId,
    'name': name,
    'website_name': websiteName,
    'sku': sku,
  };
}

Map<String, dynamic> _category({
  required String id,
  required String name,
  required String fullPath,
  String? parentId,
  int sortOrder = 0,
  bool isActive = true,
  bool showOnWebsite = true,
}) {
  return {
    'id': id,
    'name': name,
    'full_path': fullPath,
    'parent_id': parentId,
    'description': '',
    'image_url': '',
    'sort_order': sortOrder,
    'is_active': isActive,
    'show_on_website': showOnWebsite,
  };
}
