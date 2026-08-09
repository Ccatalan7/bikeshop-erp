import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/settings/services/factory_reset_service.dart';

void main() {
  group('Factory reset stock-ledger guard', () {
    test('rejects deleting movement evidence while retaining inventory', () {
      expect(
        () => FactoryResetService.validateSelectiveResetSelection(
          deleteInventory: false,
          deleteStockMovements: true,
        ),
        throwsStateError,
      );
    });

    test('rejects deleting inventory and its evidence from the client', () {
      expect(
        () => FactoryResetService.validateSelectiveResetSelection(
          deleteInventory: true,
          deleteStockMovements: true,
        ),
        throwsStateError,
      );
    });

    test('allows retaining both inventory and movement evidence', () {
      expect(
        () => FactoryResetService.validateSelectiveResetSelection(
          deleteInventory: false,
          deleteStockMovements: false,
        ),
        returnsNormally,
      );
    });

    test('rejects client-side financial purges before any delete begins', () {
      expect(
        () => FactoryResetService.validateSelectiveResetSelection(
          deleteSales: true,
          deleteInventory: false,
          deleteStockMovements: false,
        ),
        throwsStateError,
      );
    });

    test('rejects HR purges before any delete begins', () {
      expect(
        () => FactoryResetService.validateSelectiveResetSelection(
          deleteInventory: false,
          deleteStockMovements: false,
          deleteEmployees: true,
        ),
        throwsStateError,
      );
    });

    test('rejects the legacy HR module reset before any delete begins', () {
      expect(
        () => FactoryResetService.validateModuleResetSelection('hr'),
        throwsStateError,
      );
    });

    test('rejects supplier reset when the foundation owns durable history', () {
      expect(
        () => FactoryResetService.validateSupplierResetPreflight({
          'supported': false,
          'error_code': 'supplier_foundation_reset_requires_domain_operation',
          'display_reason': 'Hay evidencia durable que debe conservarse.',
        }),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Hay evidencia durable que debe conservarse.',
          ),
        ),
      );
    });

    test('fails closed when supplier reset preflight is malformed', () {
      expect(
        () => FactoryResetService.validateSupplierResetPreflight(null),
        throwsStateError,
      );
    });

    test('allows supplier reset only after an affirmative server preflight',
        () {
      expect(
        () => FactoryResetService.validateSupplierResetPreflight({
          'supported': true,
        }),
        returnsNormally,
      );
    });

    test('supplier preflight runs before any selective delete helper', () {
      final source = File(
        'lib/modules/settings/services/factory_reset_service.dart',
      ).readAsStringSync();
      final selective = source.substring(
        source.indexOf('Future<void> performSelectiveReset'),
      );
      expect(
        selective.indexOf('get_supplier_foundation_reset_preflight'),
        lessThan(selective.indexOf('Future<void> safeDelete')),
      );
      expect(
        selective,
        isNot(contains("await safeDelete('suppliers');\n"
            "        print('✅ Suppliers deleted');")),
      );
    });
  });
}
