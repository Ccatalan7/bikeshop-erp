import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/sales/services/sales_service.dart';

void main() {
  test('negative stock feedback stays compact and names projected balances',
      () {
    const warnings = [
      SalesNegativeStockWarning(productName: 'Neumático', projectedStock: -1),
      SalesNegativeStockWarning(productName: 'Maza', projectedStock: -2),
      SalesNegativeStockWarning(productName: 'Cadena', projectedStock: -3),
    ];

    expect(
      formatSalesNegativeStockWarning(warnings),
      'Factura confirmada. Stock negativo: Neumático (-1), Maza (-2) y 1 más.',
    );
  });
}
