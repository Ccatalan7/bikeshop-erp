import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/utils/product_store_page.dart';

void main() {
  // Production row read on 2026-11-02; its canonical page answered 200 and
  // the commercial-name slug a 301 to it.
  const chainId = '7a832bfe-f7f8-4d8e-bb11-6bb7d2c17e71';
  const chainName = 'Cadena 1/2 X 3/32 Kmc Hv408 Caja Grey/brown';
  const chainWebName = 'Cadena KMC HV408 6/7/8 velocidades gris y café';
  const chainSku = '4715575883212';
  const chainPage = 'https://vinabike.cl/productos/'
      'cadena-kmc-hv408-6-7-8-velocidades-gris-y-cafe/4715575883212';

  group('productStorePageUri', () {
    test('the web name names the page, as the store does', () {
      final uri = productStorePageUri(
        storeUrl: 'https://vinabike.cl',
        productId: chainId,
        name: chainName,
        websiteName: chainWebName,
        sku: chainSku,
      );
      expect(uri.toString(), chainPage);
    });

    test('without a web name the commercial name names it', () {
      for (final webName in [null, '', '   ']) {
        final uri = productStorePageUri(
          storeUrl: 'https://vinabike.cl',
          productId: chainId,
          name: chainName,
          websiteName: webName,
          sku: chainSku,
        );
        expect(
          uri.toString(),
          'https://vinabike.cl/productos/'
          'cadena-1-2-x-3-32-kmc-hv408-caja-grey-brown/4715575883212',
          reason: 'web name ${webName == null ? 'null' : '«$webName»'}',
        );
      }
    });

    test('a product without SKU keeps its UUID page', () {
      final uri = productStorePageUri(
        storeUrl: 'https://vinabike.cl',
        productId: chainId,
        name: chainName,
        websiteName: chainWebName,
        sku: '  ',
      );
      expect(uri.toString(), 'https://vinabike.cl/productos/$chainId');
    });

    test('an SKU with a space travels encoded', () {
      final uri = productStorePageUri(
        storeUrl: 'https://vinabike.cl',
        productId: chainId,
        name: 'Disco Shimano RT-MT800',
        sku: 'RDM41 LD',
      );
      expect(
        uri.toString(),
        'https://vinabike.cl/productos/disco-shimano-rt-mt800/RDM41%20LD',
      );
    });

    test('the store address is taken as the site settings normalize it', () {
      final uri = productStorePageUri(
        storeUrl: ' https://vinabike.cl/ ',
        productId: chainId,
        name: chainName,
        websiteName: chainWebName,
        sku: chainSku,
      );
      expect(uri.toString(), chainPage);
    });

    test('no valid https store address, no link', () {
      for (final storeUrl in [
        '',
        'vinabike.cl',
        'http://vinabike.cl',
        'https://vinabike.cl/tienda',
        'https://vinabike.cl?ref=erp',
      ]) {
        final uri = productStorePageUri(
          storeUrl: storeUrl,
          productId: chainId,
          name: chainName,
          websiteName: chainWebName,
          sku: chainSku,
        );
        expect(uri, isNull, reason: '«$storeUrl»');
      }
    });

    test('a product not saved yet has no page', () {
      for (final productId in [null, '', ' ']) {
        final uri = productStorePageUri(
          storeUrl: 'https://vinabike.cl',
          productId: productId,
          name: chainName,
          websiteName: chainWebName,
          sku: chainSku,
        );
        expect(uri, isNull, reason: 'id ${productId ?? 'null'}');
      }
    });
  });
}
