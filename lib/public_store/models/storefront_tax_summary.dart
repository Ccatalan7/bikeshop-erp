/// Deterministic storefront tax breakdown for gross, tax-included CLP prices.
///
/// The database is authoritative, but cart, checkout and confirmation use this
/// same line-level rule so the customer never sees a payment-method-derived
/// estimate. Only exempt (0%) and standard IVA (19%) classifications are
/// supported. The known legacy fraction `0.19` normalizes to canonical `19`.
class StorefrontTaxLineInput {
  const StorefrontTaxLineInput({
    required this.label,
    required this.grossUnitPrice,
    required this.quantity,
    required this.taxRate,
  });

  final String label;
  final num grossUnitPrice;
  final int quantity;
  final num? taxRate;
}

enum StorefrontTaxIssueCode {
  missingTaxRate,
  unsupportedTaxRate,
  invalidUnitPrice,
  invalidQuantity,
  amountTooLarge,
}

class StorefrontTaxIssue {
  const StorefrontTaxIssue({
    required this.code,
    required this.label,
  });

  final StorefrontTaxIssueCode code;
  final String label;

  String get customerMessage {
    final item = label.trim().isEmpty ? 'Un producto' : '“${label.trim()}”';
    return switch (code) {
      StorefrontTaxIssueCode.missingTaxRate =>
        '$item no tiene clasificación tributaria configurada.',
      StorefrontTaxIssueCode.unsupportedTaxRate =>
        '$item tiene una clasificación tributaria no soportada.',
      StorefrontTaxIssueCode.invalidUnitPrice =>
        '$item no tiene un precio válido en pesos chilenos.',
      StorefrontTaxIssueCode.invalidQuantity =>
        '$item no tiene una cantidad válida.',
      StorefrontTaxIssueCode.amountTooLarge =>
        '$item supera el monto que podemos procesar de forma segura.',
    };
  }
}

class StorefrontTaxLineBreakdown {
  const StorefrontTaxLineBreakdown({
    required this.label,
    required this.grossUnitPrice,
    required this.quantity,
    required this.taxRate,
    required this.grossAmount,
    required this.netAmount,
    required this.taxAmount,
  });

  final String label;
  final int grossUnitPrice;
  final int quantity;
  final int taxRate;
  final int grossAmount;
  final int netAmount;
  final int taxAmount;

  bool get isTaxable => taxRate == 19;
  bool get isExempt => taxRate == 0;
}

class StorefrontTaxSummary {
  const StorefrontTaxSummary._({
    required this.lines,
    required this.issues,
    required this.grossAmount,
    required this.netAmount,
    required this.taxAmount,
  });

  // JavaScript's largest exactly representable integer. Flutter web must not
  // silently round an order that the PostgreSQL numeric calculation preserves.
  static const int _maxSafeInteger = 9007199254740991;

  final List<StorefrontTaxLineBreakdown> lines;
  final List<StorefrontTaxIssue> issues;
  final int grossAmount;
  final int netAmount;
  final int taxAmount;

  factory StorefrontTaxSummary.calculate(
    Iterable<StorefrontTaxLineInput> inputs,
  ) {
    final lines = <StorefrontTaxLineBreakdown>[];
    final issues = <StorefrontTaxIssue>[];
    var grossAmount = 0;
    var netAmount = 0;
    var taxAmount = 0;

    for (final input in inputs) {
      if (input.quantity < 1) {
        issues.add(StorefrontTaxIssue(
          code: StorefrontTaxIssueCode.invalidQuantity,
          label: input.label,
        ));
        continue;
      }

      final unitPrice = _wholePositiveClp(input.grossUnitPrice);
      if (unitPrice == null) {
        issues.add(StorefrontTaxIssue(
          code: StorefrontTaxIssueCode.invalidUnitPrice,
          label: input.label,
        ));
        continue;
      }

      final canonicalTaxRate = normalizeTaxRate(input.taxRate);
      if (canonicalTaxRate == null) {
        issues.add(StorefrontTaxIssue(
          code: input.taxRate == null
              ? StorefrontTaxIssueCode.missingTaxRate
              : StorefrontTaxIssueCode.unsupportedTaxRate,
          label: input.label,
        ));
        continue;
      }

      if (unitPrice > _maxSafeInteger ~/ input.quantity) {
        issues.add(StorefrontTaxIssue(
          code: StorefrontTaxIssueCode.amountTooLarge,
          label: input.label,
        ));
        continue;
      }

      final lineGross = unitPrice * input.quantity;
      final lineNet =
          canonicalTaxRate == 19 ? (lineGross / 1.19).round() : lineGross;
      final lineTax = lineGross - lineNet;

      if (grossAmount > _maxSafeInteger - lineGross ||
          netAmount > _maxSafeInteger - lineNet ||
          taxAmount > _maxSafeInteger - lineTax) {
        issues.add(StorefrontTaxIssue(
          code: StorefrontTaxIssueCode.amountTooLarge,
          label: input.label,
        ));
        continue;
      }

      lines.add(StorefrontTaxLineBreakdown(
        label: input.label,
        grossUnitPrice: unitPrice,
        quantity: input.quantity,
        taxRate: canonicalTaxRate,
        grossAmount: lineGross,
        netAmount: lineNet,
        taxAmount: lineTax,
      ));
      grossAmount += lineGross;
      netAmount += lineNet;
      taxAmount += lineTax;
    }

    return StorefrontTaxSummary._(
      lines: List.unmodifiable(lines),
      issues: List.unmodifiable(issues),
      grossAmount: grossAmount,
      netAmount: netAmount,
      taxAmount: taxAmount,
    );
  }

  static int? normalizeTaxRate(num? rawRate) {
    if (rawRate == null) return null;
    final value = rawRate.toDouble();
    if (!value.isFinite) return null;
    if (value == 0) return 0;
    if (value == 19 || (value - 0.19).abs() < 0.000000001) return 19;
    return null;
  }

  static int? _wholePositiveClp(num rawAmount) {
    final value = rawAmount.toDouble();
    if (!value.isFinite || value <= 0 || value > _maxSafeInteger) return null;
    if (value != value.roundToDouble()) return null;
    return value.toInt();
  }

  bool get isValid => issues.isEmpty;
  bool get hasTaxableLines => lines.any((line) => line.isTaxable);
  bool get hasExemptLines => lines.any((line) => line.isExempt);
  bool get isMixed => hasTaxableLines && hasExemptLines;

  String get netLabel {
    if (isMixed) return 'Neto + exento';
    if (hasExemptLines && !hasTaxableLines) return 'Subtotal exento';
    return 'Neto';
  }

  String get ivaLabel {
    if (isMixed) return 'IVA incluido (ítems afectos)';
    if (hasTaxableLines) return 'IVA incluido (19%)';
    return 'IVA';
  }

  String? get checkoutBlockMessage {
    if (issues.isEmpty) return null;
    return '${issues.first.customerMessage} '
        'No podemos finalizar la compra hasta que la tienda lo corrija.';
  }
}
