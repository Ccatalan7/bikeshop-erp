import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/utils/whatsapp_link.dart';

void main() {
  test('a Chilean number becomes the digits wa.me expects', () {
    expect(whatsappDigits('+56 9 1234 5678'), '56912345678');
    expect(whatsappDigits('912345678'), '56912345678');
    expect(whatsappDigits('56912345678'), '56912345678');
    expect(whatsappDigits(''), '');
  });

  test('the chat opens with the question already written', () {
    final uri = whatsappChatUri('+56 9 1234 5678',
        text: 'Hola, ¿le sirve a mi bicicleta?');
    expect(uri!.host, 'wa.me');
    expect(uri.path, '/56912345678');
    expect(uri.queryParameters['text'], 'Hola, ¿le sirve a mi bicicleta?');
    expect(uri.toString(), isNot(contains('+')));
    expect(whatsappChatUri('  '), isNull);
  });
}
