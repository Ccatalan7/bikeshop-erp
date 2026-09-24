import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Las URLs `/shop/...` son del sitio anterior (Odoo). Google todavía les
/// muestra impresiones; sin estas reglas caían en la portada con canónica a
/// la portada. Son reglas manuales de `firebase.json`: el generador de
/// snapshots las conserva en su orden, y Firebase aplica la primera que
/// coincide, así que los comodines tienen que ir al final.
void main() {
  final config = jsonDecode(File('firebase.json').readAsStringSync())
      as Map<String, dynamic>;
  final store = (config['hosting'] as List)
      .cast<Map<String, dynamic>>()
      .singleWhere((hosting) => hosting['target'] == 'store');
  final shopRules = (store['redirects'] as List)
      .cast<Map<String, dynamic>>()
      .where((rule) => (rule['source'] as String).startsWith('/shop'))
      .toList();

  test('hay reglas para las URLs /shop que conoce Google', () {
    expect(shopRules.length, greaterThan(100));
    final sources = shopRules.map((rule) => rule['source']).toList();
    expect(sources.toSet().length, sources.length, reason: 'sin duplicados');
    expect(
      sources,
      containsAll(<String>[
        '/shop/s56467-aceite-**',
        '/shop',
        '/shop/cart',
        '/shop/category/**',
        '/shop/**',
      ]),
    );
  });

  test('son permanentes y llevan a la tienda actual', () {
    for (final rule in shopRules) {
      expect(rule['type'], 301, reason: '${rule['source']}');
      final destination = rule['destination'] as String;
      expect(
        destination == '/carrito' || destination.startsWith('/productos'),
        isTrue,
        reason: '${rule['source']} -> $destination',
      );
    }
  });

  test('los comodines van después de las reglas específicas', () {
    final sources = shopRules.map((rule) => rule['source'] as String).toList();
    expect(sources.last, '/shop/**');
    final categoryCatchAll = sources.indexOf('/shop/category/**');
    for (var i = 0; i < categoryCatchAll; i++) {
      expect(sources[i], isNot('/shop/**'));
    }
    for (var i = categoryCatchAll + 1; i < sources.length - 1; i++) {
      expect(sources[i].startsWith('/shop/category/'), isFalse,
          reason: '${sources[i]} quedaría tapada por /shop/category/**');
    }
  });
}
