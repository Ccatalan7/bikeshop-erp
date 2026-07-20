import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/messaging/utils/conversation_search.dart';

void main() {
  test('normalizes accents, punctuation and repeated whitespace', () {
    expect(
      ConversationSearch.normalize('  Joaquín  Núñez — PG-00472 '),
      'joaquin nunez pg 00472',
    );
  });

  test('combines tokens across customer, bicycle and job fields', () {
    final query = ConversationSearch.normalize('oxford felipe');

    expect(
      ConversationSearch.matches(query, [
        'Felipe Elizama',
        'Oxford South Mountain Soul',
        'PG-00472',
      ]),
      isTrue,
    );
    expect(
      ConversationSearch.matches(query, [
        'Luciano Prado',
        'Oxford Merak 1',
      ]),
      isFalse,
    );
  });

  test('finds a Chilean phone regardless of formatting', () {
    expect(
      ConversationSearch.matches(
        ConversationSearch.normalize('976431387'),
        ['+56 9 7643 1387'],
      ),
      isTrue,
    );
  });
}
