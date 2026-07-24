import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/utils/product_url.dart';

void main() {
  group('productUrlSlug', () {
    test('creates a readable Spanish product slug', () {
      expect(
        productUrlSlug('Asiento Paseo C/resorte N707'),
        'asiento-paseo-c-resorte-n707',
      );
    });

    test('removes accents and repeated separators', () {
      expect(
        productUrlSlug('Cámara Maxxis 29" / Válvula'),
        'camara-maxxis-29-valvula',
      );
    });
  });

  group('buildPublicProductPath', () {
    test('uses readable name and stable SKU', () {
      expect(
        buildPublicProductPath(
          name: 'Asiento Paseo C/resorte N707',
          sku: '2000000305653',
          fallbackProductId: '44d273dd-1b45-41f3-9120-6e963c34b748',
        ),
        '/productos/asiento-paseo-c-resorte-n707/2000000305653',
      );
    });

    test('preserves the UUID route when SKU is unavailable', () {
      expect(
        buildPublicProductPath(
          name: 'Producto sin SKU',
          sku: ' ',
          fallbackProductId: '44d273dd-1b45-41f3-9120-6e963c34b748',
        ),
        '/productos/44d273dd-1b45-41f3-9120-6e963c34b748',
      );
    });
  });

  group('normalizePublicProductRouteForRuntime', () {
    test('mounts a canonical detail route for ERP Preview', () {
      expect(
        normalizePublicProductRouteForRuntime(
          '/productos/camara-rbx/6927116100148?preview=true',
          isErpMounted: true,
        ),
        '/tienda/productos/camara-rbx/6927116100148?preview=true',
      );
    });

    test('restores the clean route for the standalone storefront', () {
      expect(
        normalizePublicProductRouteForRuntime(
          '/tienda/productos/camara-rbx/6927116100148?edit=true',
          isErpMounted: false,
        ),
        '/productos/camara-rbx/6927116100148?edit=true',
      );
    });

    test('does not rewrite unrelated storefront routes', () {
      expect(
        normalizePublicProductRouteForRuntime(
          '/productos?category=camaras&preview=true',
          isErpMounted: true,
        ),
        '/tienda/productos?category=camaras&preview=true',
      );
      expect(
        normalizePublicProductRouteForRuntime(
          '/contacto?preview=true',
          isErpMounted: true,
        ),
        '/contacto?preview=true',
      );
    });
  });

  group('normalizePublicCatalogRouteForRuntime', () {
    test('mounts clean category routes inside ERP Preview', () {
      expect(
        normalizePublicCatalogRouteForRuntime(
          '/productos/categoria/camaras?q=29#catalogo',
          isErpMounted: true,
        ),
        '/tienda/productos/categoria/camaras?q=29#catalogo',
      );
    });

    test('restores clean service collection routes for the public app', () {
      expect(
        normalizePublicCatalogRouteForRuntime(
          '/tienda/servicios/categoria/mantenciones?preview=true',
          isErpMounted: false,
        ),
        '/servicios/categoria/mantenciones?preview=true',
      );
    });
  });
}
