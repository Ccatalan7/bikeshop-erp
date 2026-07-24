import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new OCR capture replaces stale draft fields and avoids payroll default',
      () {
    final source = File(
      'lib/shared/widgets/quick_access_expense_rail.dart',
    ).readAsStringSync();
    final registry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();

    expect(source, contains('setState(_resetDraftForNewOcrResult);'));
    expect(source, contains('void _resetDraftForNewOcrResult()'));
    expect(source, contains('_selectedPaymentMethodId = null;'));
    expect(source, contains('_selectedSupplier = null;'));
    expect(source, contains('_appliedTemplate = null;'));
    expect(source, contains('_selectedPurchaseInvoice = null;'));
    expect(source, contains("['6205', '6801']"));
    expect(source, isNot(contains("['5200', '6100', '6101']")));
    expect(source, isNot(contains("label: '45.000'")));
    expect(
      source,
      isNot(contains("label: 'Insumos, combustible, mensajería…'")),
    );
    expect(source, contains('_looksLikeTransportOnlyExpense'));
    expect(source, contains('_resolveOfficeSupplyAccount'));
    expect(source, contains('_looksLikeMercadoLibreInvoice'));
    expect(
      source,
      contains("paymentMethodHint: isMercadoLibreInvoice ? 'card' : null"),
    );
    expect(source, contains("final isCombinedCard = code == 'card'"));
    expect(source, contains('_hasExactOcrTaxBreakdown'));
    expect(source, contains('_ocrNetAmount = parsedInvoice.netAmount;'));
    expect(source, contains('_ocrTaxAmount = parsedInvoice.taxAmount;'));
    expect(source, contains('_ocrSupplierRut = parsedInvoice.rut;'));
    expect(source, contains('supplierRut: _resolvedSupplierRut,'));
    expect(
      registry,
      contains('A successful new capture replaces every prior OCR-owned value'),
    );
  });
}
