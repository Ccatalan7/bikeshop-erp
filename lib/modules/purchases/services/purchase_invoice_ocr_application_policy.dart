import 'dart:math' as math;

import '../../../shared/models/tax_treatment.dart';
import '../../../shared/services/invoice_parser_service.dart';

class PurchaseInvoiceOcrTotalReconciliation {
  const PurchaseInvoiceOcrTotalReconciliation({
    required this.invoiceTotal,
    required this.appliedLineTotal,
    required this.difference,
    required this.toleranceClp,
  });

  final double invoiceTotal;
  final double appliedLineTotal;
  final double difference;
  final double toleranceClp;

  bool get isWithinTolerance => difference <= toleranceClp;
}

/// Pure rules for applying parsed OCR data to a purchase-invoice draft.
///
/// AliExpress distributes tax, shipping and discounts into each line's landed
/// unit cost. Those lines therefore use [TaxTreatment.noTax]: adding another
/// 19% would duplicate tax. Header reconciliation allows at most one CLP per
/// line for whole-peso allocation/rounding; it is deliberately not a broad
/// percentage tolerance.
class PurchaseInvoiceOcrApplicationPolicy {
  const PurchaseInvoiceOcrApplicationPolicy._();

  static bool isAliExpress(ParsedInvoice invoice) {
    bool containsAliExpress(String? value) {
      final normalized = (value ?? '')
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
          .trim();
      return normalized.contains('aliexpress') ||
          normalized.contains('ali express');
    }

    return containsAliExpress(invoice.supplierName) ||
        containsAliExpress(invoice.rawText);
  }

  static TaxTreatment taxTreatmentFor({
    required ParsedInvoice invoice,
    required TaxTreatment current,
  }) {
    if (isAliExpress(invoice)) return TaxTreatment.noTax;
    if (invoice.total != null && current == TaxTreatment.noTax) {
      return TaxTreatment.taxIncluded;
    }
    return current;
  }

  static double normalizedQuantity(double? quantity) {
    final rounded = (quantity ?? 1).roundToDouble();
    return rounded <= 0 ? 1 : rounded;
  }

  static double appliedLineTotal(
    ParsedLineItem item, {
    required double fallbackUnitCost,
  }) {
    final quantity = normalizedQuantity(item.quantity);
    final unitCost = item.unitPrice ?? fallbackUnitCost;
    final gross = quantity * unitCost;

    double discount = 0;
    if (item.discount != null && item.discount! > 0) {
      discount = item.discount!;
    } else if (item.discountRate != null && item.discountRate! > 0) {
      discount = gross * (item.discountRate! / 100);
    }
    return math.max(0.0, gross - discount).toDouble();
  }

  static double reconciliationToleranceClp(int appliedLineCount) =>
      math.max(1, appliedLineCount).toDouble();

  static bool allParsedLinesResolved({
    required int parsedLineCount,
    required int resolvedLineCount,
  }) =>
      parsedLineCount == resolvedLineCount;

  static PurchaseInvoiceOcrTotalReconciliation reconcile({
    required double invoiceTotal,
    required Iterable<double> appliedLineTotals,
  }) {
    final totals = appliedLineTotals.toList(growable: false);
    final appliedTotal = totals.fold<double>(0, (sum, value) => sum + value);
    return PurchaseInvoiceOcrTotalReconciliation(
      invoiceTotal: invoiceTotal,
      appliedLineTotal: appliedTotal,
      difference: (invoiceTotal - appliedTotal).abs(),
      toleranceClp: reconciliationToleranceClp(totals.length),
    );
  }
}
