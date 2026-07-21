import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/aliexpress_daily_invoice_service.dart';

void main() {
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
