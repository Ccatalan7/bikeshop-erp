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
  });
}
