import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/models/website_block_registry.dart';
import 'package:vinabike_erp/modules/website/models/website_block_type.dart';

void main() {
  group('WebsiteProductsBlockContract selection compatibility', () {
    test('merges canonical then legacy IDs without loss or duplicates', () {
      final contract = WebsiteProductsBlockContract.fromData(
        const <String, dynamic>{
          'productIds': <Object?>['a', 42, ' a ', '', null],
          'selectedProducts': <Object?>['legacy', '42', 'b', 'legacy'],
        },
      );

      expect(contract.productIds, <String>['a', '42', 'legacy', 'b']);
      expect(contract.selectionFingerprint, 'a\u001f42\u001flegacy\u001fb');
    });

    test('reads documents from either generation', () {
      expect(
        WebsiteProductsBlockContract.fromData(
          const <String, dynamic>{
            'productIds': <String>['new']
          },
        ).productIds,
        <String>['new'],
      );
      expect(
        WebsiteProductsBlockContract.fromData(
          const <String, dynamic>{
            'selectedProducts': <int>[7, 9]
          },
        ).productIds,
        <String>['7', '9'],
      );
    });

    test('one selection command writes identical normalized generations', () {
      final update = WebsiteProductsBlockContract.selectionWrite(
        const <Object?>['first', ' first ', 2, null, ''],
      );

      expect(update.keys.toSet(), <String>{'productIds', 'selectedProducts'});
      expect(update['productIds'], <String>['first', '2']);
      expect(update['selectedProducts'], <String>['first', '2']);

      final reloaded = WebsiteProductsBlockContract.fromData(
        Map<String, dynamic>.from(
          jsonDecode(jsonEncode(update)) as Map,
        ),
      );
      expect(reloaded.productIds, <String>['first', '2']);
    });
  });

  group('WebsiteProductsBlockContract persisted defaults', () {
    test('new blocks use the canonical key and no ghost showStock', () {
      final defaults = WebsiteBlockRegistry.definitionFor(
        WebsiteBlockType.products,
      ).defaultData;

      expect(defaults['productIds'], isA<List<String>>());
      expect(defaults.containsKey('selectedProducts'), isFalse);
      expect(defaults.containsKey('showStock'), isFalse);
      expect(defaults, containsPair('showPrice', true));
      expect(defaults, containsPair('showSku', false));
      expect(defaults, containsPair('showBrand', false));
    });

    test('normalizes invalid enum and numeric payloads defensively', () {
      final contract = WebsiteProductsBlockContract.fromData(
        const <String, dynamic>{
          'productSource': 'unknown',
          'layout': 'stack',
          'itemsPerRow': 99,
          'maxProducts': '1',
          'showPrice': 'false',
        },
      );

      expect(contract.productSource, 'featured');
      expect(contract.layout, 'grid');
      expect(contract.itemsPerRow, 4);
      expect(contract.maxProducts, 4);
      expect(contract.showPrice, isTrue);
    });
  });
}
