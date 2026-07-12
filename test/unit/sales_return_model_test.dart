import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/sales/models/sales_return.dart';

void main() {
  const line = SalesReturnableLine(
    lineIndex: 2,
    productName: 'Cadena',
    soldQuantity: 5,
    returnedQuantity: 2,
  );

  test('returnable balance is derived from posted cumulative returns', () {
    expect(line.remainingQuantity, 3);
  });

  test('return draft declares its physical disposition explicitly', () {
    const draft = SalesReturnLineDraft(
      line: line,
      quantity: 2,
      disposition: SalesReturnDisposition.quarantine,
    );
    expect(draft.validate(), isNull);
    expect(draft.toRpcJson(), {
      'line_index': 2,
      'returned_quantity': 2,
      'disposition': 'quarantine',
    });
  });

  test('return draft rejects more than the remaining sold balance', () {
    const draft = SalesReturnLineDraft(line: line, quantity: 4);
    expect(draft.validate(), contains('supera'));
  });

  test('quarantine history exposes held and resolved workflow states', () {
    const held = SalesReturnHistoryLine(
      id: 'line-1',
      productName: 'Cadena',
      quantity: 1,
      disposition: 'quarantine',
      quarantineStatus: 'held',
    );
    const released = SalesReturnHistoryLine(
      id: 'line-1',
      productName: 'Cadena',
      quantity: 1,
      disposition: 'quarantine',
      quarantineStatus: 'released',
      resolutionId: 'resolution-1',
    );
    expect(held.isHeld, isTrue);
    expect(released.hasActiveResolution, isTrue);
  });
}
