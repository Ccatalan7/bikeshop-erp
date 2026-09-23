import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/services/ga4_commerce_events.dart';

void main() {
  final sent = <(String, Map<String, Object?>)>[];
  final events = Ga4CommerceEvents.instance;

  setUp(() {
    sent.clear();
    events.send = (name, params) {
      sent.add((name, params));
      return true;
    };
  });

  const cadena = Ga4Item(
    id: 'L471',
    name: 'Llanta Weinmann U28',
    price: 32000,
    quantity: 2,
  );

  test('los eventos de comercio llevan los nombres y montos de GA4', () {
    events.viewItem(cadena);
    events.addToCart(cadena);
    events.beginCheckout([cadena], 72990);
    events.purchase('pedido-1', [cadena], 72990);

    expect(sent.map((event) => event.$1),
        ['view_item', 'add_to_cart', 'begin_checkout', 'purchase']);
    expect(sent[1].$2['value'], 64000, reason: 'precio por cantidad');
    expect(sent[3].$2['transaction_id'], 'pedido-1');
    for (final event in sent) {
      expect(event.$2['currency'], 'CLP');
      expect((event.$2['items'] as List).single, {
        'item_id': 'L471',
        'item_name': 'Llanta Weinmann U28',
        'price': 32000.0,
        'quantity': 2,
      });
    }
  });

  test('un checkout o una compra sin productos no se envía', () {
    events.beginCheckout(const [], 0);
    events.purchase('pedido-2', const [], 0);
    expect(sent, isEmpty);
  });

  test('sólo se cuentan los clics que buscan hablar con el local', () {
    const casos = {
      'https://wa.me/56998357797?text=Hola': 'whatsapp',
      'https://api.whatsapp.com/send?phone=569': 'whatsapp',
      'tel:+56998357797': 'phone',
      'mailto:contacto@vinabike.cl': 'email',
      'https://www.google.com/maps/search/?api=1&query=Alvarez%2032':
          'directions',
      'https://maps.app.goo.gl/abc': 'directions',
      'https://instagram.com/vinabike': null,
      'https://www.google.com/search?q=vinabike': null,
      'https://vinabike.cl/productos': null,
    };
    casos.forEach((url, esperado) {
      expect(Ga4CommerceEvents.contactMethodFor(url), esperado, reason: url);
    });

    events.contactFromUrl('https://wa.me/56998357797');
    events.contactFromUrl('https://instagram.com/vinabike');
    expect(sent, hasLength(1));
    expect(sent.single.$1, 'contact');
    expect(sent.single.$2, {'method': 'whatsapp'});
  });
}
