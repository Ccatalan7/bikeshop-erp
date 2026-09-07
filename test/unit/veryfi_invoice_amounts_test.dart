import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/veryfi_adapter.dart';
import 'package:vinabike_erp/modules/purchases/services/purchase_invoice_ocr_application_policy.dart';

void main() {
  test('Derman line totals produce net unit costs and preserve explicit IVA',
      () {
    // Amounts from the authorized native Veryfi run of Derman 10959.
    const quantities = [1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1];
    const totals = [
      7810,
      7810,
      7810,
      7810,
      7810,
      8258,
      8258,
      21460,
      6699,
      7525,
      10253
    ];
    final invoice = VeryfiAdapter.toParsedInvoice({
      'subtotal': 101503,
      'tax': 19286,
      'total': 120789,
      'line_items': List.generate(
          totals.length,
          (i) => {
                'description': 'Producto $i',
                'quantity': quantities[i],
                'price': null,
                'total': totals[i],
              }),
    });
    expect(invoice.taxAmount, 19286);
    expect(invoice.netAmount, 101503);
    expect(invoice.total, 120789);
    expect(invoice.lineItems[5].unitPrice, 4129);
    expect(invoice.lineItems[7].unitPrice, 10730);
    for (var i = 0; i < totals.length; i++) {
      final item = invoice.lineItems[i];
      expect(item.quantity, quantities[i]);
      expect(item.total, totals[i]);
      expect(
          PurchaseInvoiceOcrApplicationPolicy.appliedLineTotal(item,
              fallbackUnitCost: 99999),
          totals[i]);
    }
    // The purchase form adds IVA to the net subtotal; do not gross up lines.
    final subtotal = invoice.lineItems.fold<double>(
        0,
        (sum, item) =>
            sum +
            PurchaseInvoiceOcrApplicationPolicy.appliedLineTotal(item,
                fallbackUnitCost: 0));
    expect(subtotal + (subtotal * .19).round(), invoice.total);
  });

  test('missing price respects explicit discounts without changing evidence',
      () {
    final invoice = VeryfiAdapter.toParsedInvoice({
      'line_items': [
        {'quantity': 2, 'total': 1800, 'discount': 200},
        {'quantity': 2, 'total': 1800, 'discount_rate': 10},
      ]
    });
    for (final item in invoice.lineItems) {
      expect(item.unitPrice, 1000);
      expect(item.total, 1800);
      expect(item.quantity, 2);
      expect(item.wasAutoAdjusted, isTrue);
    }
    expect(invoice.lineItems[0].discount, 200);
    expect(invoice.lineItems[1].discountRate, 10);
  });

  test('does not replace explicit prices or invent missing base amounts', () {
    final invoice = VeryfiAdapter.toParsedInvoice({
      'line_items': [
        {'quantity': 2, 'price': 700, 'total': 1800},
        {'quantity': 2, 'price': 0, 'total': 1800},
        {'total': 1800},
        {'quantity': 0, 'total': 1800},
        {'quantity': 2},
        {'quantity': 2, 'total': 0, 'discount_rate': 100},
        {'quantity': 2, 'total': 1800, 'discount': 200, 'discount_rate': 50},
      ]
    });
    expect(invoice.lineItems[0].unitPrice, 700);
    expect(invoice.lineItems[1].unitPrice, 0);
    for (final item in invoice.lineItems.skip(2)) {
      expect(item.unitPrice, isNull);
    }
  });
}
