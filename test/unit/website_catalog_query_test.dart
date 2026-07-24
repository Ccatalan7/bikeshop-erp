import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_catalog_query.dart';
import 'package:vinabike_erp/modules/website/models/website_destination.dart';

const _brandA = '00000000-0000-4000-8000-000000000001';
const _brandB = '00000000-0000-4000-8000-000000000002';
const _brandC = '00000000-0000-4000-8000-000000000003';

void main() {
  group('WebsiteCatalogQuery', () {
    test('omits defaults from canonical URLs', () {
      final query = WebsiteCatalogQuery();

      expect(query.categoryScope, WebsiteCatalogCategoryScope.subtree);
      expect(query.toQueryParameters(), isEmpty);
      expect(
        WebsiteDestination.routeForCatalog(catalogQuery: query),
        '/productos',
      );
    });

    test('round-trips direct category scope through the catalog destination',
        () {
      final href = WebsiteDestination.routeForCatalog(
        categorySlug: 'Cadenas',
        catalogQuery: WebsiteCatalogQuery(
          categoryScope: WebsiteCatalogCategoryScope.direct,
        ),
      );

      expect(
        href,
        '/productos/categoria/cadenas?category_scope=direct',
      );

      final destination = WebsiteDestination.parse(href);
      final decoded = WebsiteCatalogQuery.fromUri(Uri.parse(destination.href));

      expect(destination.kind, WebsiteDestinationKind.category);
      expect(destination.reference, 'cadenas');
      expect(decoded.categoryScope, WebsiteCatalogCategoryScope.direct);
      expect(decoded.toQueryParameters(), {'category_scope': 'direct'});
      expect(
        WebsiteDestination.routeForCatalog(
          categorySlug: destination.reference,
          catalogQuery: decoded,
        ),
        href,
      );
    });

    test('canonicalizes explicit subtree scope by omitting it', () {
      final query = WebsiteCatalogQuery.fromUri(
        Uri.parse('/productos/categoria/cadenas?category_scope=subtree'),
      );

      expect(query.categoryScope, WebsiteCatalogCategoryScope.subtree);
      expect(query.toQueryParameters(), isEmpty);
    });

    test('invalid category scope fails closed', () {
      expect(
        WebsiteCatalogQuery.tryParse(
          Uri.parse('/productos/categoria/cadenas?category_scope=invalid'),
        ),
        isNull,
      );
      expect(
        WebsiteCatalogQuery.tryParse(
          Uri.parse('/productos/categoria/cadenas?category_scope='),
        ),
        isNull,
      );
      expect(
        () => WebsiteCatalogQuery.fromUri(
          Uri.parse('/productos/categoria/cadenas?category_scope=invalid'),
        ),
        throwsFormatException,
      );
    });

    test('canonicalizes every supported filter in stable order', () {
      final query = WebsiteCatalogQuery(
        searchQuery: '  cámara   29  ',
        productType: WebsiteCatalogProductTypeFilter.product,
        categoryScope: WebsiteCatalogCategoryScope.direct,
        brandIds: const [_brandB, _brandA, _brandB, '  $_brandC  '],
        minPrice: 3990,
        maxPrice: 15000.5,
        stock: WebsiteCatalogStockFilter.available,
        sort: WebsiteCatalogSort.priceAsc,
        page: 2,
        pageSize: 50,
      );

      expect(query.brandIds, [_brandA, _brandB, _brandC]);
      expect(query.toQueryParameters().keys, [
        'q',
        'type',
        'category_scope',
        'brand',
        'min_price',
        'max_price',
        'stock',
        'sort',
        'page',
        'page_size',
      ]);
      expect(
        WebsiteDestination.routeForCatalog(
          categorySlug: 'Cámaras',
          catalogQuery: query,
        ),
        '/productos/categoria/camaras?'
        'q=c%C3%A1mara+29&type=product&category_scope=direct&'
        'brand=$_brandA%2C$_brandB%2C$_brandC&'
        'min_price=3990&max_price=15000.5&stock=available&sort=price_asc&'
        'page=2&page_size=50',
      );
    });

    test('reads compatibility aliases and writes only canonical keys', () {
      final query = WebsiteCatalogQuery.fromUri(
        Uri.parse(
          '/servicios?search=mantencion&product_type=servicios&'
          'brand_ids=$_brandB,$_brandA,$_brandB&price_min=1000&price_max=9000&'
          'availability=in_stock&sort_by=price_desc&pagina=3&per_page=50',
        ),
      );

      expect(query.searchQuery, 'mantencion');
      expect(query.productType, WebsiteCatalogProductTypeFilter.service);
      expect(query.brandIds, [_brandA, _brandB]);
      expect(query.minPrice, 1000);
      expect(query.maxPrice, 9000);
      expect(query.stock, WebsiteCatalogStockFilter.available);
      expect(query.sort, WebsiteCatalogSort.priceDesc);
      expect(query.page, 3);
      expect(query.pageSize, 50);
      expect(query.toQueryParameters(), {
        'q': 'mantencion',
        'type': 'service',
        'brand': '$_brandA,$_brandB',
        'min_price': '1000',
        'max_price': '9000',
        'stock': 'available',
        'sort': 'price_desc',
        'page': '3',
        'page_size': '50',
      });
    });

    test('invalid price filters fail closed', () {
      expect(
        WebsiteCatalogQuery.tryParse(
          Uri.parse('/productos?min_price=no-es-numero'),
        ),
        isNull,
      );
      expect(
        WebsiteCatalogQuery.tryParse(
          Uri.parse('/productos?min_price='),
        ),
        isNull,
      );
      expect(
        WebsiteCatalogQuery.tryParse(
          Uri.parse('/productos?min_price=-1'),
        ),
        isNull,
      );
      expect(
        WebsiteCatalogQuery.tryParse(
          Uri.parse('/productos?min_price=200&max_price=100'),
        ),
        isNull,
      );
      expect(
        () => WebsiteCatalogQuery.fromUri(
          Uri.parse('/productos?min_price=200&max_price=100'),
        ),
        throwsFormatException,
      );
      expect(
        () => WebsiteCatalogQuery(minPrice: 200, maxPrice: 100),
        throwsArgumentError,
      );
    });

    test('invalid brand identifiers fail closed before the UUID RPC', () {
      expect(
        WebsiteCatalogQuery.tryParse(
          Uri.parse('/productos?brand=no-es-un-uuid'),
        ),
        isNull,
      );
      expect(
        () => WebsiteCatalogQuery(brandIds: const ['no-es-un-uuid']),
        throwsArgumentError,
      );
    });
  });

  test('legacy routeForCatalog calls remain source compatible', () {
    expect(
      WebsiteDestination.routeForCatalog(
        categoryId: 'category-1',
        searchQuery: 'Maxxis',
        productType: 'producto',
      ),
      '/productos?category=category-1&q=Maxxis&type=product',
    );
    expect(
      WebsiteDestination.routeForCatalog(productType: 'servicio'),
      '/servicios?type=service',
    );
  });
}
