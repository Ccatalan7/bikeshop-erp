import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/services/purchase_invoice_ocr_application_policy.dart';
import 'package:vinabike_erp/shared/models/tax_treatment.dart';
import 'package:vinabike_erp/shared/services/invoice_parser_service.dart';

void main() {
  ParsedInvoice invoice({
    String? supplierName,
    String rawText = '',
    double? total,
    List<ParsedLineItem> lineItems = const [],
  }) {
    return ParsedInvoice(
      supplierName: supplierName,
      rawText: rawText,
      total: total,
      lineItems: lineItems,
    );
  }

  group('PurchaseInvoiceOcrApplicationPolicy', () {
    test('keeps AliExpress landed costs out of the additional 19% path', () {
      final parsed = invoice(
        supplierName: 'AliExpress Marketplace',
        total: 79933,
      );

      expect(
        PurchaseInvoiceOcrApplicationPolicy.isAliExpress(parsed),
        isTrue,
      );
      expect(
        PurchaseInvoiceOcrApplicationPolicy.taxTreatmentFor(
          invoice: parsed,
          current: TaxTreatment.taxIncluded,
        ),
        TaxTreatment.noTax,
      );
    });

    test('also recognizes AliExpress from structured raw OCR text', () {
      final parsed = invoice(
        rawText: '{"supplierName":"Ali Express","items":[]}',
      );

      expect(
        PurchaseInvoiceOcrApplicationPolicy.isAliExpress(parsed),
        isTrue,
      );
    });

    test('preserves the normal Chilean purchase tax behavior', () {
      final parsed = invoice(supplierName: 'MKR', total: 119000);

      expect(
        PurchaseInvoiceOcrApplicationPolicy.taxTreatmentFor(
          invoice: parsed,
          current: TaxTreatment.noTax,
        ),
        TaxTreatment.taxIncluded,
      );
    });

    test('reconciles exact landed line costs against the invoice header', () {
      final brakePads = ParsedLineItem(
        description: 'Pastillas ZTTO MS-01B',
        quantity: 8,
        unitPrice: 1348.75,
      );
      final saddle = ParsedLineItem(
        description: 'Sillín gel negro',
        quantity: 2,
        unitPrice: 6970.5,
      );

      final reconciliation = PurchaseInvoiceOcrApplicationPolicy.reconcile(
        invoiceTotal: 24731,
        appliedLineTotals: [
          PurchaseInvoiceOcrApplicationPolicy.appliedLineTotal(
            brakePads,
            fallbackUnitCost: 0,
          ),
          PurchaseInvoiceOcrApplicationPolicy.appliedLineTotal(
            saddle,
            fallbackUnitCost: 0,
          ),
        ],
      );

      expect(reconciliation.appliedLineTotal, 24731);
      expect(reconciliation.difference, 0);
      expect(reconciliation.toleranceClp, 2);
      expect(reconciliation.isWithinTolerance, isTrue);
    });

    test('uses a strict one-CLP-per-line tolerance, not a percentage', () {
      final accepted = PurchaseInvoiceOcrApplicationPolicy.reconcile(
        invoiceTotal: 100000,
        appliedLineTotals: const [49999, 49999],
      );
      final rejected = PurchaseInvoiceOcrApplicationPolicy.reconcile(
        invoiceTotal: 100000,
        appliedLineTotals: const [49998, 49999],
      );

      expect(accepted.toleranceClp, 2);
      expect(accepted.isWithinTolerance, isTrue);
      expect(rejected.difference, 3);
      expect(rejected.isWithinTolerance, isFalse);
    });

    test('never authorizes partial application of parsed lines', () {
      expect(
        PurchaseInvoiceOcrApplicationPolicy.allParsedLinesResolved(
          parsedLineCount: 6,
          resolvedLineCount: 6,
        ),
        isTrue,
      );
      expect(
        PurchaseInvoiceOcrApplicationPolicy.allParsedLinesResolved(
          parsedLineCount: 6,
          resolvedLineCount: 5,
        ),
        isFalse,
      );
    });
  });
}
