import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/aliexpress_daily_invoice_service.dart';

void main() {
  _trustedDomainTests();
  _apiSourceOfTruthTests();

  group('AliExpressDailyInvoiceService', () {
    test('accepts only HTTPS AliExpress hosts', () {
      expect(
        AliExpressDailyInvoiceService.isTrustedUri(
          Uri.parse('https://www.aliexpress.com/p/order/index.html'),
        ),
        isTrue,
      );
      expect(
        AliExpressDailyInvoiceService.isTrustedUri(
          Uri.parse('https://login.aliexpress.com/login.htm'),
        ),
        isTrue,
      );
      expect(
        AliExpressDailyInvoiceService.isTrustedUri(
          Uri.parse('http://www.aliexpress.com/p/order/index.html'),
        ),
        isFalse,
      );
      expect(
        AliExpressDailyInvoiceService.isTrustedUri(
          Uri.parse('https://aliexpress.com.evil.example/orders'),
        ),
        isFalse,
      );
    });

    test('resolves a canonical detail URL from the order number', () {
      final uri = AliExpressDailyInvoiceService.resolveOrderDetailUri(
        <String, dynamic>{
          'orderNumber': '123 456 789',
          'pageUrl': AliExpressDailyInvoiceService.ordersUri,
        },
      );

      expect(uri?.host, 'www.aliexpress.com');
      expect(uri?.path, '/p/order/detail.html');
      expect(uri?.queryParameters['orderId'], '123456789');
    });

    test('never treats an AliExpress message thread as an order detail', () {
      final uri = AliExpressDailyInvoiceService.resolveOrderDetailUri(
        <String, dynamic>{
          'orderNumber': '8211744661738042',
          'pageUrl':
              'https://www.aliexpress.com/p/message/index.html?fromCode=order&orderId=8211744661738042&bizContext=orderDetail',
        },
      );

      expect(uri?.path, '/p/order/detail.html');
      expect(uri?.queryParameters['orderId'], '8211744661738042');
    });

    test('deduplicates repeated copies of the same daily order', () {
      final repeatedOrder = <String, dynamic>{
        'orderNumber': '8211744661738042',
        'orderDate': '2026-06-15',
        'pageUrl':
            'https://www.aliexpress.com/p/order/detail.html?orderId=8211744661738042',
        'subtotal': 10200,
        'shipping': 1,
        'tax': 1723,
        'discount': 1133,
        'total': 10790,
        'items': [
          {
            'sku': 'AE-14758950',
            'itemId': '1005006114758950',
            'description': 'ZTTO 4 pares de pastillas de freno MS-01B',
            'quantity': 2,
            'unitPrice': 5100,
            'total': 10200,
            'imageUrl': 'https://ae01.alicdn.com/pads.jpg',
          },
        ],
      };
      final invoice = AliExpressDailyInvoiceService.buildDailyInvoice(
        date: DateTime(2026, 6, 15),
        orders: [repeatedOrder, Map<String, dynamic>.from(repeatedOrder)],
      );

      expect(invoice['total'], 10790);
      expect(invoice['subtotal'], 10200);
      expect((invoice['sourceOrders'] as List), hasLength(1));
      final items = List<Map<String, dynamic>>.from(invoice['items'] as List);
      expect(items, hasLength(1));
      expect(items.single['quantity'], 8);
    });

    test('keeps authoritative detail components and product media', () {
      final merged = AliExpressDailyInvoiceService.mergeListAndDetailOrder(
        <String, dynamic>{
          'orderNumber': '123',
          'orderDate': '2026-07-20',
          'subtotal': 100,
          'shipping': 50,
          'total': 150,
          'items': [
            {'description': 'Lista', 'quantity': 1, 'unitPrice': 100},
          ],
        },
        <String, dynamic>{
          'orderNumber': '123',
          'orderDate': '2026-07-20',
          'subtotal': 100,
          'shipping': null,
          'tax': null,
          'discount': null,
          'total': 100,
          '__authoritativeTotals': true,
          'items': [
            {
              'description': 'Detalle',
              'quantity': 1,
              'unitPrice': 100,
              'imageUrl': 'https://ae01.alicdn.com/product.jpg',
            },
          ],
        },
        Uri.parse(
          'https://www.aliexpress.com/p/order/detail.html?orderId=123',
        ),
      );

      expect(merged['shipping'], isNull);
      expect(merged['total'], 100);
      final items = List<Map<String, dynamic>>.from(merged['items'] as List);
      expect(items.single['description'], 'Detalle');
      expect(items.single['imageUrl'], contains('alicdn.com'));
    });

    test('builds one exact-day landed-cost invoice', () {
      final invoice = AliExpressDailyInvoiceService.buildDailyInvoice(
        date: DateTime(2026, 7, 20),
        orders: [
          <String, dynamic>{
            'orderNumber': '111111',
            'orderDate': '2026-07-20',
            'subtotal': 400,
            'shipping': 200,
            'total': 600,
            'items': [
              {
                'sku': 'AE-LISTING-1',
                'description': 'Puños ODI',
                'quantity': 1,
                'unitPrice': 100,
                'total': 100,
                'imageUrl': 'https://ae01.alicdn.com/grips.jpg',
              },
              {
                'sku': 'AE-LISTING-2',
                'description': 'Postiza ZTTO',
                'quantity': 1,
                'unitPrice': 300,
                'total': 300,
              },
            ],
          },
        ],
      );

      expect(invoice['orderDate'], '2026-07-20');
      expect(invoice['orderNumber'], '111111');
      expect(invoice['total'], 600);
      final items = List<Map<String, dynamic>>.from(invoice['items'] as List);
      expect(items, hasLength(2));
      expect(items.first['unitPrice'], 150);
      expect(items.last['unitPrice'], 450);
      expect(items.first['sku'], 'AE-LISTING-1');
      expect(items.first['imageUrl'], contains('grips.jpg'));
      expect(
        items.fold<num>(0, (sum, item) => sum + (item['total'] as num)),
        600,
      );
    });

    test('deduplicates order rows and converts brake-pad packs to pairs', () {
      Map<String, dynamic> order(String number) => <String, dynamic>{
            'orderNumber': number,
            'orderDate': '2026-06-15',
            'subtotal': 10200,
            'shipping': 1,
            'tax': 1723,
            'discount': 1133,
            'total': 10790,
            'items': [
              {
                'sku': 'AE-14758950',
                'description':
                    'ZTTO 4 pares de pastillas de freno semimetálicas MS-01B',
                'quantity': 2,
                'unitPrice': 5100,
                'total': 10200,
                'imageUrl': 'https://ae01.alicdn.com/pads.jpg',
              },
              {
                'sku': 'AE-14758950',
                'itemId': '1005000014758950',
                'description':
                    'ZTTO 4 pares de pastillas de freno semimetálicas MS-01B',
                'quantity': 2,
                'unitPrice': 5100,
                'total': 10200,
              },
            ],
          };

      final invoice = AliExpressDailyInvoiceService.buildDailyInvoice(
        date: DateTime(2026, 6, 15),
        orders: [order('111111'), order('222222')],
      );

      final items = List<Map<String, dynamic>>.from(invoice['items'] as List);
      expect(items, hasLength(1));
      final item = items.single;
      expect(item['sourcePurchaseQuantity'], 4);
      expect(item['unitsPerPurchase'], 4);
      expect(item['quantity'], 16);
      expect(item['sourceUnitPrice'], 1275);
      expect(item['allocatedShippingTotal'], 2);
      expect(item['allocatedTaxTotal'], 3446);
      expect(item['allocatedDiscountTotal'], 2266);
      expect(item['unitPrice'], 1348.75);
      expect(item['total'], 21580);
      expect(item['allocatedAdjustment'], -0.13);
      expect(item['itemId'], '1005000014758950');
      expect(item['imageUrl'], contains('pads.jpg'));
      expect(item['sourceOrderNumbers'], ['111111', '222222']);
      expect(invoice['subtotal'], 20400);
      expect(invoice['shipping'], 2);
      expect(invoice['tax'], 3446);
      expect(invoice['discount'], 2266);
      expect(invoice['total'], 21580);
      expect(invoice['componentDifference'], -2);
    });
  });
}

void _apiSourceOfTruthTests() {
  group('las líneas de la API mandan sobre el detalle raspado', () {
    test('un pedido de 2 unidades no se reduce a 1 por el detalle', () {
      // Caso real del 2026-04-06 (pedido 8209933206118042): la API entregó las
      // 2 unidades y el detalle leído de la página sólo veía 1. Al pisar las
      // líneas con el detalle, la unidad faltante se absorbía como «ajuste» y
      // el costo unitario que entraba al inventario quedaba al doble.
      final listOrder = <String, dynamic>{
        'via': 'api',
        'orderNumber': '8209933206118042',
        'orderDate': '2026-04-06',
        'total': 8057,
        // La API entrega las unidades ya agregadas por producto.
        'items': [
          {
            'sku': 'AE-54962320',
            'itemId': '1005008554962320',
            'description': 'ROCKBROS botella de agua 600ML',
            'quantity': 2,
            'unitPrice': 3490,
            'total': 6980,
            'imageUrl': 'https://ae01.alicdn.com/kf/botella.jpg',
          },
        ],
      };
      final detailOrder = <String, dynamic>{
        'orderNumber': '8209933206118042',
        'orderDate': '2026-04-16',
        'subtotal': 6980,
        'tax': 1286,
        'discount': 209,
        'total': 8057,
        'items': [
          {
            'sku': 'AE-54962320',
            'description': 'ROCKBROS botella de agua 600ML',
            'quantity': 1,
            'unitPrice': 3490,
            'total': 3490,
            'imageUrl': 'https://ae01.alicdn.com/kf/botella.jpg',
          },
        ],
      };

      final merged = AliExpressDailyInvoiceService.mergeListAndDetailOrder(
        listOrder,
        detailOrder,
        Uri.parse(
          'https://www.aliexpress.com/p/order/detail.html?orderId=8209933206118042',
        ),
      );

      final items = (merged['items'] as List).cast<Map<String, dynamic>>();
      final units = items.fold<num>(
        0,
        (sum, item) => sum + (item['quantity'] as num? ?? 0),
      );
      expect(units, 2, reason: 'las dos unidades de la API se conservan');
      // El desglose de montos sigue viniendo del detalle, que es quien lo tiene.
      expect(merged['subtotal'], 6980);
      expect(merged['tax'], 1286);
      expect(merged['discount'], 209);
      // Y la fecha del pedido es la de la API, no otra fecha de la página.
      expect(merged['orderDate'], '2026-04-06');
    });

    test('sin origen API el detalle sigue mandando sobre la lista', () {
      final merged = AliExpressDailyInvoiceService.mergeListAndDetailOrder(
        <String, dynamic>{
          'orderNumber': '1',
          'orderDate': '2026-04-06',
          'items': [
            {'sku': 'X', 'description': 'parcial', 'quantity': 1, 'total': 100},
          ],
        },
        <String, dynamic>{
          'orderNumber': '1',
          'orderDate': '2026-04-07',
          'items': [
            {
              'sku': 'X',
              'description': 'completo',
              'quantity': 2,
              'unitPrice': 50,
              'total': 100,
              'imageUrl': 'https://ae01.alicdn.com/kf/x.jpg',
            },
          ],
        },
        Uri.parse('https://www.aliexpress.com/p/order/detail.html?orderId=1'),
      );
      final items = (merged['items'] as List).cast<Map<String, dynamic>>();
      expect(items.single['description'], 'completo');
      expect(merged['orderDate'], '2026-04-07');
    });
  });
}

void _trustedDomainTests() {
  group('dominios de AliExpress reconocidos', () {
    test('acepta los sitios regionales donde compra el taller', () {
      // La cuenta navega el sitio estadounidense: con sólo `.com` en la lista,
      // «Compras del día» no aparecía ahí (2026-08-06).
      for (final url in [
        'https://www.aliexpress.com/p/order/index.html',
        'https://www.aliexpress.us/p/order/index.html',
        'https://es.aliexpress.com/',
        'https://aliexpress.com/',
      ]) {
        expect(
          AliExpressDailyInvoiceService.isTrustedUri(Uri.parse(url)),
          isTrue,
          reason: '$url es AliExpress',
        );
      }
    });

    test('sigue rechazando lo que no es AliExpress ni es HTTPS', () {
      for (final url in [
        'http://www.aliexpress.com/',
        'https://aliexpress.com.attacker.net/',
        'https://notaliexpress.com/',
        'https://aliexpress.evil/',
      ]) {
        expect(
          AliExpressDailyInvoiceService.isTrustedUri(Uri.parse(url)),
          isFalse,
          reason: '$url no debe habilitar el extractor',
        );
      }
    });
  });
}
