import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/supplier_variant_resolution.dart';

/// Parsed invoice data extracted from OCR text
class ParsedInvoice {
  final String? rut; // Chilean tax ID (e.g., "12.345.678-9")
  final String? invoiceNumber; // Folio or invoice number
  final DateTime? date; // Invoice date
  final double? total; // Total amount
  final double? netAmount; // Document net amount, when explicitly stated
  final double? taxAmount; // Document tax amount, when explicitly stated
  /// ISO 4217 currency carried by the source document when it is known.
  ///
  /// Money stays numeric elsewhere in the legacy OCR model, so supplier
  /// resolution keeps the currency beside it instead of assuming CLP when a
  /// durable source line is prepared.
  final String? currencyCode;
  final String? supplierName; // Vendor/supplier name
  final List<ParsedLineItem> lineItems; // Extracted line items
  final String rawText; // Full extracted text for debugging

  ParsedInvoice({
    this.rut,
    this.invoiceNumber,
    this.date,
    this.total,
    this.netAmount,
    this.taxAmount,
    this.currencyCode,
    this.supplierName,
    this.lineItems = const [],
    required this.rawText,
  });

  ParsedInvoice copyWith({
    String? rut,
    String? invoiceNumber,
    DateTime? date,
    double? total,
    double? netAmount,
    double? taxAmount,
    String? currencyCode,
    String? supplierName,
    List<ParsedLineItem>? lineItems,
    String? rawText,
  }) {
    return ParsedInvoice(
      rut: rut ?? this.rut,
      invoiceNumber: invoiceNumber ?? this.invoiceNumber,
      date: date ?? this.date,
      total: total ?? this.total,
      netAmount: netAmount ?? this.netAmount,
      taxAmount: taxAmount ?? this.taxAmount,
      currencyCode: currencyCode ?? this.currencyCode,
      supplierName: supplierName ?? this.supplierName,
      lineItems: lineItems ?? this.lineItems,
      rawText: rawText ?? this.rawText,
    );
  }

  @override
  String toString() {
    return 'ParsedInvoice(rut: $rut, number: $invoiceNumber, date: $date, '
        'net: $netAmount, tax: $taxAmount, total: $total, '
        'currency: $currencyCode, '
        'supplier: $supplierName, items: $lineItems)';
  }
}

/// Line item extracted from invoice
class ParsedLineItem {
  final String description;

  /// Supplier-authored product-line title, without the selected option.
  ///
  /// [description] remains the operator-facing line and may include
  /// `(BLACK)`; variant identity travels independently below.
  final String? lineTitle;
  final String? variantLabel;
  final String? variantKey;
  final String? sku;
  final String? rawRowText;
  final String? imageUrl;
  final String? productUrl;

  /// Quantity bought from the supplier before catalog-unit resolution.
  ///
  /// For AliExpress this is deliberately kept separate from any pack evidence:
  /// buying `2` listings whose selected option says `4 pairs` is still a source
  /// purchase quantity of `2` until a matched catalog product defines its unit.
  final double? sourcePurchaseQuantity;

  /// Supplier price per purchased option before landed-cost allocation.
  /// This is a commercial row discriminator, not catalog identity or cost.
  final double? sourcePurchaseUnitPrice;

  /// Explicit count printed by the supplier for the selected pack/option.
  /// This is evidence only; it must not multiply [quantity] before resolution.
  final int? rawPackCount;

  /// Supplier unit lexeme attached to [rawPackCount] (`pcs`, `pares`, etc.).
  /// It is intentionally not translated into a catalog inventory unit here.
  final String? rawUnitToken;
  final bool rawPackEvidenceConflict;

  /// Supplier order identities contributing to this consolidated source row.
  /// They are evidence/audit context, never catalog-product identity.
  final List<String> sourceOrderNumbers;
  final SupplierVariantResolution? supplierResolution;
  final double? quantity;
  final double? unitPrice;
  final double? total;
  final double? discount;
  final double? discountRate;
  final bool discountInferred;
  final bool wasAutoAdjusted;
  final String? adjustmentSummary;

  // Product verification fields (populated after database lookup)
  final bool? existsInDatabase;
  final String? matchedProductId;
  final String? matchedProductName;
  final int? currentStock;

  ParsedLineItem({
    required this.description,
    this.lineTitle,
    this.variantLabel,
    this.variantKey,
    this.sku,
    this.rawRowText,
    this.imageUrl,
    this.productUrl,
    this.sourcePurchaseQuantity,
    this.sourcePurchaseUnitPrice,
    this.rawPackCount,
    this.rawUnitToken,
    this.rawPackEvidenceConflict = false,
    this.sourceOrderNumbers = const <String>[],
    this.supplierResolution,
    this.quantity,
    this.unitPrice,
    this.total,
    this.discount,
    this.discountRate,
    this.discountInferred = false,
    this.wasAutoAdjusted = false,
    this.adjustmentSummary,
    this.existsInDatabase,
    this.matchedProductId,
    this.matchedProductName,
    this.currentStock,
  });

  factory ParsedLineItem.fromJson(Map<String, dynamic> json) {
    return ParsedLineItem(
      description: json['description']?.toString() ?? '',
      lineTitle: _nullableText(json['lineTitle'] ?? json['line_title']),
      variantLabel:
          _nullableText(json['variantLabel'] ?? json['variant_label']),
      variantKey: _nullableText(json['variantKey'] ?? json['variant_key']),
      sku: _nullableText(json['sku']),
      rawRowText: _nullableText(json['rawRowText'] ?? json['raw_row_text']),
      imageUrl: _nullableText(json['imageUrl'] ?? json['image_url']),
      productUrl: _nullableText(json['productUrl'] ?? json['product_url']),
      sourcePurchaseQuantity: _nullableDouble(
        json['sourcePurchaseQuantity'] ?? json['source_purchase_quantity'],
      ),
      sourcePurchaseUnitPrice: _nullableDouble(
        json['sourcePurchaseUnitPrice'] ?? json['source_purchase_unit_price'],
      ),
      rawPackCount:
          _nullableInt(json['rawPackCount'] ?? json['raw_pack_count']),
      rawUnitToken:
          _nullableText(json['rawUnitToken'] ?? json['raw_unit_token']),
      rawPackEvidenceConflict: json['rawPackEvidenceConflict'] == true ||
          json['raw_pack_evidence_conflict'] == true,
      sourceOrderNumbers: _stringList(
        json['sourceOrderNumbers'] ?? json['source_order_numbers'],
      ),
      supplierResolution: _supplierResolution(
        json['supplierResolution'] ?? json['supplier_resolution'],
      ),
      quantity: _nullableDouble(json['quantity']),
      unitPrice: _nullableDouble(json['unitPrice'] ?? json['unit_price']),
      total: _nullableDouble(json['total']),
      discount: _nullableDouble(json['discount']),
      discountRate:
          _nullableDouble(json['discountRate'] ?? json['discount_rate']),
      discountInferred:
          json['discountInferred'] == true || json['discount_inferred'] == true,
      wasAutoAdjusted:
          json['wasAutoAdjusted'] == true || json['was_auto_adjusted'] == true,
      adjustmentSummary: _nullableText(
        json['adjustmentSummary'] ?? json['adjustment_summary'],
      ),
      existsInDatabase: json['existsInDatabase'] as bool? ??
          json['exists_in_database'] as bool?,
      matchedProductId: _nullableText(
        json['matchedProductId'] ?? json['matched_product_id'],
      ),
      matchedProductName: _nullableText(
        json['matchedProductName'] ?? json['matched_product_name'],
      ),
      currentStock: _nullableInt(json['currentStock'] ?? json['current_stock']),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'description': description,
        'lineTitle': lineTitle,
        'variantLabel': variantLabel,
        'variantKey': variantKey,
        'sku': sku,
        'rawRowText': rawRowText,
        'imageUrl': imageUrl,
        'productUrl': productUrl,
        'sourcePurchaseQuantity': sourcePurchaseQuantity,
        'sourcePurchaseUnitPrice': sourcePurchaseUnitPrice,
        'rawPackCount': rawPackCount,
        'rawUnitToken': rawUnitToken,
        'rawPackEvidenceConflict': rawPackEvidenceConflict,
        'sourceOrderNumbers': sourceOrderNumbers,
        if (supplierResolution != null)
          'supplierResolution': supplierResolution!.toJson(),
        'quantity': quantity,
        'unitPrice': unitPrice,
        'total': total,
        'discount': discount,
        'discountRate': discountRate,
        'discountInferred': discountInferred,
        'wasAutoAdjusted': wasAutoAdjusted,
        'adjustmentSummary': adjustmentSummary,
        'existsInDatabase': existsInDatabase,
        'matchedProductId': matchedProductId,
        'matchedProductName': matchedProductName,
        'currentStock': currentStock,
      };

  static String? _nullableText(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static double? _nullableDouble(dynamic value) {
    if (value is num) return value.toDouble();
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return double.tryParse(text.replaceAll(',', '.'));
  }

  static int? _nullableInt(dynamic value) {
    if (value is num) return value.toInt();
    return _nullableDouble(value)?.toInt();
  }

  static List<String> _stringList(dynamic value) {
    final values = value is Iterable
        ? value
        : value == null
            ? const <dynamic>[]
            : value.toString().split(',');
    final normalized = values
        .map((entry) => entry?.toString().trim() ?? '')
        .where((entry) => entry.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return List<String>.unmodifiable(normalized);
  }

  static SupplierVariantResolution? _supplierResolution(dynamic value) {
    if (value is! Map) return null;
    final normalized = value.map(
      (key, raw) => MapEntry(key.toString(), raw),
    );
    final resolution = SupplierVariantResolution.fromLookupJson(normalized);
    return resolution.isResolved ? resolution : null;
  }

  /// One exact graph can resolve a line even when it expands to many products.
  bool get hasAuthoritativeCatalogResolution =>
      supplierResolution?.isResolved == true;

  /// Create a copy with updated verification fields
  ParsedLineItem copyWith({
    String? description,
    String? lineTitle,
    String? variantLabel,
    String? variantKey,
    String? sku,
    String? rawRowText,
    String? imageUrl,
    String? productUrl,
    double? sourcePurchaseQuantity,
    double? sourcePurchaseUnitPrice,
    int? rawPackCount,
    String? rawUnitToken,
    bool? rawPackEvidenceConflict,
    List<String>? sourceOrderNumbers,
    SupplierVariantResolution? supplierResolution,
    bool clearSupplierResolution = false,
    double? quantity,
    double? unitPrice,
    double? total,
    double? discount,
    double? discountRate,
    bool? discountInferred,
    bool? wasAutoAdjusted,
    String? adjustmentSummary,
    bool? existsInDatabase,
    String? matchedProductId,
    String? matchedProductName,
    int? currentStock,
  }) {
    return ParsedLineItem(
      description: description ?? this.description,
      lineTitle: lineTitle ?? this.lineTitle,
      variantLabel: variantLabel ?? this.variantLabel,
      variantKey: variantKey ?? this.variantKey,
      sku: sku ?? this.sku,
      rawRowText: rawRowText ?? this.rawRowText,
      imageUrl: imageUrl ?? this.imageUrl,
      productUrl: productUrl ?? this.productUrl,
      sourcePurchaseQuantity:
          sourcePurchaseQuantity ?? this.sourcePurchaseQuantity,
      sourcePurchaseUnitPrice:
          sourcePurchaseUnitPrice ?? this.sourcePurchaseUnitPrice,
      rawPackCount: rawPackCount ?? this.rawPackCount,
      rawUnitToken: rawUnitToken ?? this.rawUnitToken,
      rawPackEvidenceConflict:
          rawPackEvidenceConflict ?? this.rawPackEvidenceConflict,
      sourceOrderNumbers: sourceOrderNumbers ?? this.sourceOrderNumbers,
      supplierResolution: clearSupplierResolution
          ? null
          : supplierResolution ?? this.supplierResolution,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      total: total ?? this.total,
      discount: discount ?? this.discount,
      discountRate: discountRate ?? this.discountRate,
      discountInferred: discountInferred ?? this.discountInferred,
      wasAutoAdjusted: wasAutoAdjusted ?? this.wasAutoAdjusted,
      adjustmentSummary: adjustmentSummary ?? this.adjustmentSummary,
      existsInDatabase: existsInDatabase ?? this.existsInDatabase,
      matchedProductId: matchedProductId ?? this.matchedProductId,
      matchedProductName: matchedProductName ?? this.matchedProductName,
      currentStock: currentStock ?? this.currentStock,
    );
  }

  @override
  String toString() {
    return 'LineItem($description, sku: $sku, sourceQty: '
        '$sourcePurchaseQuantity at $sourcePurchaseUnitPrice, '
        'pack: $rawPackCount $rawUnitToken, '
        'packConflict: $rawPackEvidenceConflict, '
        'orders: ${sourceOrderNumbers.join(',')}, '
        'qty: $quantity, price: $unitPrice, total: $total, '
        'discount: $discount, rate: $discountRate, '
        'inferred: $discountInferred, adjusted: $wasAutoAdjusted, '
        'exists: $existsInDatabase)';
  }
}

class _GeneratedAliExpressAmountRow {
  final int rowNumber;
  final double? quantity;
  final double? unitPrice;
  final double? total;
  final String rawText;

  const _GeneratedAliExpressAmountRow({
    required this.rowNumber,
    required this.quantity,
    required this.unitPrice,
    required this.total,
    required this.rawText,
  });
}

class _GeneratedAliExpressProductBlock {
  final String description;
  final String? lineTitle;
  final String? variantLabel;
  final String? variantKey;
  final String? sku;
  final String? imageUrl;
  final String? productUrl;
  final double? sourcePurchaseQuantity;
  final double? sourcePurchaseUnitPrice;
  final int? rawPackCount;
  final String? rawUnitToken;
  final bool rawPackEvidenceConflict;
  final List<String> sourceOrderNumbers;
  final String rawText;

  const _GeneratedAliExpressProductBlock({
    required this.description,
    this.lineTitle,
    this.variantLabel,
    this.variantKey,
    this.sku,
    this.imageUrl,
    this.productUrl,
    this.sourcePurchaseQuantity,
    this.sourcePurchaseUnitPrice,
    this.rawPackCount,
    this.rawUnitToken,
    this.rawPackEvidenceConflict = false,
    this.sourceOrderNumbers = const <String>[],
    required this.rawText,
  });
}

/// Service to parse invoice data from OCR text
/// Optimized for Chilean DTE (Documentos Tributarios Electrónicos)
class InvoiceParserService {
  static final InvoiceParserService _instance =
      InvoiceParserService._internal();
  factory InvoiceParserService() => _instance;
  InvoiceParserService._internal();

  /// Parse invoice from OCR recognized text
  /// Extracts: RUT, invoice number, date, total, supplier name, line items
  ParsedInvoice parseInvoice(RecognizedText recognizedText) {
    final fullText = recognizedText.text;
    final lines = fullText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    print('📋 Parsing invoice from ${lines.length} lines of text');

    return ParsedInvoice(
      rut: _extractRUT(lines),
      invoiceNumber: _extractInvoiceNumber(lines),
      date: _extractDate(lines),
      total: _extractTotal(lines),
      netAmount: _extractNetAmount(lines),
      taxAmount: _extractTaxAmount(lines),
      supplierName: _extractSupplierName(lines, recognizedText.blocks),
      lineItems: _extractLineItems(lines),
      rawText: fullText,
    );
  }

  /// Parse invoice from plain text (for PDF extraction)
  /// Extracts: RUT, invoice number, date, total, supplier name, line items
  ParsedInvoice parseInvoiceFromText(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    print('📋 ========== PARSING INVOICE FROM PLAIN TEXT ==========');
    print('📋 Total lines: ${lines.length}');
    print('📋 First 50 lines:');
    for (var i = 0; i < lines.length && i < 50; i++) {
      print('  Line $i: "${lines[i]}"');
    }
    print('📋 =====================================================');

    return ParsedInvoice(
      rut: _extractRUT(lines),
      invoiceNumber: _extractInvoiceNumber(lines),
      date: _extractDate(lines),
      total: _extractTotal(lines),
      netAmount: _extractNetAmount(lines),
      taxAmount: _extractTaxAmount(lines),
      supplierName: _extractSupplierNameFromLines(lines),
      lineItems: _extractLineItems(lines),
      rawText: text,
    );
  }

  /// Extract Chilean RUT (e.g., "76.123.456-7", "12345678-9")
  /// Patterns: XX.XXX.XXX-X or XXXXXXXX-X
  String? _extractRUT(List<String> lines) {
    final delegatedSellerRut = _extractDelegatedMarketplaceSellerRut(lines);
    if (delegatedSellerRut != null) {
      print('✅ Found delegated marketplace seller RUT: $delegatedSellerRut');
      return delegatedSellerRut;
    }

    // Pattern: digits with optional dots/hyphens
    final rutPattern =
        RegExp(r'\b(\d{1,2}\.?\d{3}\.?\d{3}-[\dkK])\b', caseSensitive: false);

    for (var line in lines) {
      final match = rutPattern.firstMatch(line);
      if (match != null) {
        var rut = match.group(1)!;
        // Normalize format: add dots if missing
        if (!rut.contains('.')) {
          rut = rut.replaceAllMapped(
            RegExp(r'(\d{1,2})(\d{3})(\d{3})(-.+)'),
            (m) => '${m[1]}.${m[2]}.${m[3]}${m[4]}',
          );
        }
        print('✅ Found RUT: $rut');
        return rut;
      }
    }

    print('⚠️ RUT not found');
    return null;
  }

  /// Extract invoice/folio number
  /// Patterns: "FOLIO: 12345", "N° 12345", "Factura 12345", "Pedido # \n 262040"
  String? _extractInvoiceNumber(List<String> lines) {
    for (final line in lines) {
      final aliExpressMatch =
          RegExp(r'^#\s*(AE-[A-Z0-9\-]+)$', caseSensitive: false)
              .firstMatch(line.trim());
      if (aliExpressMatch != null) {
        final number = aliExpressMatch.group(1)!.trim();
        print('✅ Found invoice number (AliExpress): $number');
        return number;
      }
    }

    // Pattern 1: Number on same line
    final sameLinePatterns = [
      RegExp(r'(?:FOLIO|Folio|folio)[:\s]+(\d+)', caseSensitive: false),
      RegExp(r'N[°º]\s*(\d+)', caseSensitive: false),
      RegExp(r'(?:Factura|FACTURA|Boleta|BOLETA|Pedido|PEDIDO)[:\s#]*(\d+)',
          caseSensitive: false),
    ];

    for (var line in lines) {
      for (var pattern in sameLinePatterns) {
        final match = pattern.firstMatch(line);
        if (match != null) {
          final number = match.group(1)!;
          print('✅ Found invoice number (same line): $number');
          return number;
        }
      }
    }

    // Pattern 2: Label on one line, number on next line (e.g., "Pedido #" then "262040")
    for (var i = 0; i < lines.length - 1; i++) {
      final currentLine = lines[i];
      final nextLine = lines[i + 1];

      // Check if current line is a label without number
      if (RegExp(r'^(?:Pedido|PEDIDO|Factura|FACTURA|Folio|FOLIO)\s*#?\s*$',
              caseSensitive: false)
          .hasMatch(currentLine)) {
        // Check if next line is just digits
        final numberMatch = RegExp(r'^(\d+)$').firstMatch(nextLine);
        if (numberMatch != null) {
          final number = numberMatch.group(1)!;
          print('✅ Found invoice number (split lines): $number');
          return number;
        }
      }
    }

    print('⚠️ Invoice number not found');
    return null;
  }

  /// Extract date from invoice
  /// Patterns: "DD/MM/YYYY", "DD-MM-YYYY", "DD.MM.YYYY", "Fecha: ..."
  DateTime? _extractDate(List<String> lines) {
    final datePattern = RegExp(
      r'(\d{1,2})[/\-\.](\d{1,2})[/\-\.](\d{2,4})',
      caseSensitive: false,
    );

    for (var line in lines) {
      // Skip lines that look like phone numbers or IDs
      if (line.contains('Fono') ||
          line.contains('Teléfono') ||
          line.contains('Tel')) {
        continue;
      }

      final match = datePattern.firstMatch(line);
      if (match != null) {
        try {
          var day = int.parse(match.group(1)!);
          var month = int.parse(match.group(2)!);
          var year = int.parse(match.group(3)!);

          // Handle 2-digit years
          if (year < 100) {
            year += 2000;
          }

          // Validate date
          if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
            final date = DateTime(year, month, day);
            print('✅ Found date: ${date.toString().split(' ')[0]}');
            return date;
          }
        } catch (e) {
          // Invalid date, continue searching
        }
      }
    }

    print('⚠️ Date not found');
    return null;
  }

  /// Extract total amount
  /// Patterns: "TOTAL: $12.345", "Total $12,345", "Total \n $ 65.233" (split lines)
  double? _extractTotal(List<String> lines) {
    // Strategy 1: Check for "Total" keyword followed by amount on NEXT line
    for (var i = 0; i < lines.length - 1; i++) {
      final currentLine = lines[i].trim().toUpperCase();
      final nextLine = lines[i + 1].trim();
      final normalizedLabel = currentLine
          .replaceAll(RegExp(r'[:：]+$'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      // If current line is exactly "TOTAL" (or "Total neto", "TOTAL GENERAL", etc.)
      if (normalizedLabel == 'TOTAL' ||
          normalizedLabel.startsWith('TOTAL ') ||
          normalizedLabel == 'MONTO TOTAL' ||
          normalizedLabel == 'TOTAL A PAGAR') {
        // Check if next line has a currency amount
        final amountPattern = RegExp(
          r'\$?\s*([0-9]{1,3}(?:[.,][0-9]{3})+|[0-9]{4,})(?!\d)',
        );
        final match = amountPattern.firstMatch(nextLine);
        if (match != null) {
          final amountStr = match.group(1)!;
          final amount = _parseAmount(amountStr);
          if (amount != null && amount > 0 && amount < 1000000000) {
            print(
                '✅ Found total (split lines): \$$amount from lines: "$currentLine" + "$nextLine"');
            return amount;
          }
        }
      }
    }

    // Strategy 2: Look for "Total" with amount on SAME line
    final totalPatterns = [
      RegExp(r'(?:^|\s)(?:TOTAL|Total|total)[\s:]*\$?\s*([\d.,]+)',
          caseSensitive: false),
      RegExp(r'(?:^|\s)(?:MONTO|Monto|monto)[\s:]*\$?\s*([\d.,]+)',
          caseSensitive: false),
      RegExp(r'Total\s+[Nn]eto\s*\$?\s*([\d.,]+)', caseSensitive: false),
    ];

    for (var line in lines) {
      for (var pattern in totalPatterns) {
        final match = pattern.firstMatch(line);
        if (match != null) {
          final amountStr = match.group(1)!;
          final amount = _parseAmount(amountStr);
          if (amount != null && amount > 0 && amount < 1000000000) {
            // Sanity check: < 1 billion
            print('✅ Found total (same line): \$$amount from line: "$line"');
            return amount;
          }
        }
      }
    }

    // Strategy 3: Look for amounts in the last 10 lines (totals are usually at bottom)
    final lastLines =
        lines.length > 10 ? lines.sublist(lines.length - 10) : lines;
    double? maxAmount;

    for (var line in lastLines) {
      // Look for currency amounts ($12.345 or similar)
      final amountPattern = RegExp(r'\$\s*([\d.,]+)');
      for (var match in amountPattern.allMatches(line)) {
        final amountStr = match.group(1)!;
        final amount = _parseAmount(amountStr);
        // Must be reasonable invoice amount (between $100 and $100 million)
        if (amount != null && amount > 100 && amount < 100000000) {
          if (maxAmount == null || amount > maxAmount) {
            maxAmount = amount;
            print('📊 Potential total: \$$amount from line: "$line"');
          }
        }
      }
    }

    if (maxAmount != null) {
      print('✅ Found total (bottom section): \$$maxAmount');
    } else {
      print('⚠️ Total not found');
    }
    return maxAmount;
  }

  double? _extractNetAmount(List<String> lines) {
    final breakdown = _extractDocumentTaxBreakdown(lines);
    if (breakdown != null) return breakdown.$1;
    return _extractLabeledDocumentAmount(
      lines,
      labels: const ['monto neto', 'total neto', 'neto'],
    );
  }

  double? _extractTaxAmount(List<String> lines) {
    final breakdown = _extractDocumentTaxBreakdown(lines);
    if (breakdown != null) return breakdown.$2;
    return _extractLabeledDocumentAmount(
      lines,
      labels: const ['iva', 'i v a', 'monto iva', 'total iva'],
    );
  }

  (double, double)? _extractDocumentTaxBreakdown(List<String> lines) {
    var netLabelIndex = -1;
    var taxLabelIndex = -1;
    for (var i = 0; i < lines.length; i++) {
      final normalized = _normalizeInvoiceSearchText(lines[i]);
      if (netLabelIndex < 0 &&
          (normalized == 'neto' ||
              normalized.contains('monto neto') ||
              normalized.contains('total neto'))) {
        netLabelIndex = i;
      }
      final compact = normalized.replaceAll(' ', '');
      if (taxLabelIndex < 0 &&
          (compact == 'iva' ||
              compact.endsWith('iva') ||
              compact.contains('montoiva') ||
              compact.contains('totaliva'))) {
        taxLabelIndex = i;
      }
    }
    if (netLabelIndex < 0 || taxLabelIndex < 0) return null;

    final start = netLabelIndex < taxLabelIndex ? netLabelIndex : taxLabelIndex;
    final amounts = <double>[];
    for (var i = start + 1; i < lines.length && amounts.length < 2; i++) {
      final normalized = _normalizeInvoiceSearchText(lines[i]);
      if (i > netLabelIndex &&
          i > taxLabelIndex &&
          (normalized == 'total' ||
              normalized == 'monto total' ||
              normalized == 'total a pagar')) {
        break;
      }
      final amount = _parseStandaloneDocumentAmount(lines[i].trim());
      if (amount != null) amounts.add(amount);
    }
    if (amounts.length < 2) return null;

    final netAmount = amounts[0] >= amounts[1] ? amounts[0] : amounts[1];
    final taxAmount = amounts[0] < amounts[1] ? amounts[0] : amounts[1];
    return (netAmount, taxAmount);
  }

  double? _extractLabeledDocumentAmount(
    List<String> lines, {
    required List<String> labels,
  }) {
    for (var i = 0; i < lines.length; i++) {
      final normalized = _normalizeInvoiceSearchText(lines[i]);
      final matchedLabel = labels.firstWhere(
        (label) =>
            normalized == label ||
            normalized.startsWith('$label ') ||
            normalized.endsWith(' $label'),
        orElse: () => '',
      );
      if (matchedLabel.isEmpty) continue;

      final currentTail = lines[i]
          .replaceFirst(
            RegExp(RegExp.escape(matchedLabel), caseSensitive: false),
            '',
          )
          .replaceAll(RegExp(r'\(\s*\d+(?:[.,]\d+)?\s*%\s*\)'), '')
          .trim();
      final currentAmount = _parseStandaloneDocumentAmount(currentTail);
      if (currentAmount != null) return currentAmount;

      final end = (i + 4).clamp(0, lines.length).toInt();
      for (var j = i + 1; j < end; j++) {
        final candidate = lines[j].trim();
        if (RegExp(r'^\(?\s*\d+(?:[.,]\d+)?\s*%\s*\)?$').hasMatch(candidate)) {
          continue;
        }
        final amount = _parseStandaloneDocumentAmount(candidate);
        if (amount != null) return amount;
      }
    }
    return null;
  }

  double? _parseStandaloneDocumentAmount(String value) {
    if (value.isEmpty) return null;
    final match = RegExp(
      r'^(?:CLP\s*)?\$?\s*([0-9]{1,3}(?:[.,][0-9]{3})+|[0-9]{4,})(?:[.,]00)?$',
      caseSensitive: false,
    ).firstMatch(value);
    if (match == null) return null;
    final amount = _parseAmount(match.group(1)!);
    if (amount == null || amount <= 0 || amount >= 1000000000) return null;
    return amount;
  }

  /// Parse amount string (handles Chilean format: 12.345,67 or US format: 12,345.67)
  double? _parseAmount(String amountStr) {
    try {
      // Remove currency symbols, spaces, and other non-numeric chars except . and ,
      var cleaned = amountStr.replaceAll(RegExp(r'[^\d.,]'), '');

      // If empty after cleaning, return null
      if (cleaned.isEmpty) return null;

      // Determine decimal separator (last . or ,)
      final lastDot = cleaned.lastIndexOf('.');
      final lastComma = cleaned.lastIndexOf(',');

      if (lastDot > lastComma) {
        if (lastComma < 0 &&
            RegExp(r'^\d{1,3}(?:\.\d{3})+$').hasMatch(cleaned)) {
          // Format: 12.345 (Chilean thousands, no decimals)
          cleaned = cleaned.replaceAll('.', '');
        } else {
          // Format: 12,345.67 (US format)
          cleaned = cleaned.replaceAll(',', '');
        }
      } else if (lastComma > lastDot) {
        // Format: 12.345,67 (Chilean format)
        cleaned = cleaned.replaceAll('.', '').replaceAll(',', '.');
      }

      return double.parse(cleaned);
    } catch (e) {
      return null;
    }
  }

  /// Extract supplier name (usually at the top of the invoice)
  /// Takes first 1-3 text blocks (header area)
  String? _extractSupplierName(List<String> lines, List<TextBlock> blocks) {
    final delegatedSeller = _extractDelegatedMarketplaceSellerName(lines);
    if (delegatedSeller != null) {
      print('✅ Found delegated marketplace seller: $delegatedSeller');
      return delegatedSeller;
    }

    if (blocks.isEmpty) return null;

    // Take first text block (usually company name)
    // Skip if it looks like a document type ("FACTURA", "BOLETA")
    for (var i = 0; i < blocks.length.clamp(0, 3); i++) {
      final text = blocks[i].text.trim();
      if (text.length > 3 &&
          !text.toUpperCase().contains('FACTURA') &&
          !text.toUpperCase().contains('BOLETA') &&
          !text.toUpperCase().contains('DOCUMENTO') &&
          !RegExp(r'^\d+$').hasMatch(text)) {
        // Not just numbers
        print('✅ Found supplier name: $text');
        return text;
      }
    }

    print('⚠️ Supplier name not found');
    return null;
  }

  /// Extract supplier name from plain text lines (for PDF extraction)
  /// For purchase orders: Supplier is usually at the BOTTOM (sender info)
  /// For invoices: Supplier is usually at the TOP
  String? _extractSupplierNameFromLines(List<String> lines) {
    final delegatedSeller = _extractDelegatedMarketplaceSellerName(lines);
    if (delegatedSeller != null) {
      print('✅ Found delegated marketplace seller: $delegatedSeller');
      return delegatedSeller;
    }

    for (final line in lines) {
      if (line.toUpperCase().contains('ALIEXPRESS MARKETPLACE')) {
        print('✅ Found supplier name (AliExpress): AliExpress Marketplace');
        return 'AliExpress Marketplace';
      }
    }

    // Strategy 1: Look for "Mauricio Kishinevsky" or company patterns at bottom
    for (var i = lines.length - 1; i >= 0 && i > lines.length - 20; i--) {
      final text = lines[i].trim();
      if (_isKnownRecipientLine(text)) {
        continue;
      }

      // Check for company indicators (S.A., Ltda., SpA, etc.)
      if (RegExp(r'\b(S\.A\.|Ltda\.|SpA|SPA|LTDA)\b', caseSensitive: false)
          .hasMatch(text)) {
        // Clean up the company name
        var companyName = text
            .replaceAll(
                RegExp(r'^(?:NOMBRE|Nombre|Raz[oó]n Social)\s*:\s*',
                    caseSensitive: false),
                '')
            .replaceAll(
                RegExp(r'(Importaciones|Exportación|Casa Matriz|Fonos).*',
                    caseSensitive: false),
                '')
            .trim();

        if (companyName.length > 3) {
          print('✅ Found supplier name (bottom): $companyName');
          return companyName;
        }
      }

      // Check for "MKR" or other short brand names
      if (text.toUpperCase().contains('MKR') && text.length < 50) {
        print('✅ Found supplier name (MKR): $text');
        return text;
      }
    }

    // Strategy 2: Fallback to top of document (traditional invoice format)
    // Skip recipient info (first 3-4 lines usually have recipient RUT/address)
    for (var i = 0; i < lines.length.clamp(0, 15); i++) {
      var text = lines[i].trim();

      // Skip recipient lines (those with your company RUT/name)
      if (_isKnownRecipientLine(text)) {
        continue;
      }

      if (text.length > 3 &&
          !_looksLikePdfPageHeader(text) &&
          !text.toUpperCase().contains('FACTURA') &&
          !text.toUpperCase().contains('BOLETA') &&
          !text.toUpperCase().contains('DOCUMENTO') &&
          !text.toUpperCase().contains('RUT:') &&
          !text.toUpperCase().contains('PEDIDO') &&
          !text.toUpperCase().contains('ORDEN') &&
          !text.toUpperCase().contains('REFERENCIA') &&
          !text.toUpperCase().contains('FECHA') &&
          !text.toUpperCase().contains('VENDEDOR') &&
          !RegExp(r'^\d+$').hasMatch(text) &&
          !RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(text)) {
        // Not a date

        // Remove RUT prefix if present: "[77541999-7] Newen Spa" → "Newen Spa"
        text = text.replaceAll(
            RegExp(r'^\[\d{1,2}\.?\d{3}\.?\d{3}-[\dkK]\]\s*'), '');
        text =
            text.replaceAll(RegExp(r'^\d{1,2}\.?\d{3}\.?\d{3}-[\dkK]\s+'), '');
        text = text
            .replaceAll(RegExp(r'\s*Giro:.*$', caseSensitive: false), '')
            .trim();

        // If still has content after RUT removal
        if (text.length > 3) {
          print('✅ Found supplier name (top): $text');
          return text;
        }
      }
    }

    print('⚠️ Supplier name not found');
    return null;
  }

  String? _extractDelegatedMarketplaceSellerName(List<String> lines) {
    final markerIndex = _delegatedMarketplaceSellerMarkerIndex(lines);
    if (markerIndex < 0) return null;

    final marker = lines[markerIndex].trim();
    final inlineName = marker.replaceFirst(
      RegExp(
        r'^.*por\s+cuenta\s+y\s+orden\s+del\s+vendedor\s*:?\s*',
        caseSensitive: false,
      ),
      '',
    );
    if (inlineName != marker && _isPlausibleDelegatedSellerName(inlineName)) {
      return _cleanDelegatedSellerName(inlineName);
    }

    final nameLines = <String>[];
    final end = (markerIndex + 6).clamp(0, lines.length).toInt();
    for (var i = markerIndex + 1; i < end; i++) {
      final value = lines[i].trim();
      final normalized = _normalizeInvoiceSearchText(value);
      if (normalized == 'cliente' ||
          normalized.startsWith('rut') ||
          RegExp(
            r'\b\d{1,2}\.?\d{3}\.?\d{3}-[\dkK]\b',
            caseSensitive: false,
          ).hasMatch(value)) {
        break;
      }
      if (_isPlausibleDelegatedSellerName(value)) {
        nameLines.add(value);
      }
    }

    if (nameLines.isEmpty) return null;
    return _cleanDelegatedSellerName(nameLines.join(' '));
  }

  String? _extractDelegatedMarketplaceSellerRut(List<String> lines) {
    final markerIndex = _delegatedMarketplaceSellerMarkerIndex(lines);
    if (markerIndex < 0) return null;

    final rutPattern =
        RegExp(r'\b(\d{1,2}\.?\d{3}\.?\d{3}-[\dkK])\b', caseSensitive: false);
    final end = (markerIndex + 8).clamp(0, lines.length).toInt();
    for (var i = markerIndex; i < end; i++) {
      if (i > markerIndex &&
          _normalizeInvoiceSearchText(lines[i]) == 'cliente') {
        break;
      }
      final match = rutPattern.firstMatch(lines[i]);
      if (match != null) return _normalizeRutFormat(match.group(1)!);
    }
    return null;
  }

  int _delegatedMarketplaceSellerMarkerIndex(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      if (_normalizeInvoiceSearchText(lines[i])
          .contains('por cuenta y orden del vendedor')) {
        return i;
      }
    }
    return -1;
  }

  String _normalizeInvoiceSearchText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[áàäâ]'), 'a')
        .replaceAll(RegExp(r'[éèëê]'), 'e')
        .replaceAll(RegExp(r'[íìïî]'), 'i')
        .replaceAll(RegExp(r'[óòöô]'), 'o')
        .replaceAll(RegExp(r'[úùüû]'), 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _isPlausibleDelegatedSellerName(String value) {
    final normalized = _normalizeInvoiceSearchText(value);
    if (normalized.length < 3) return false;
    return normalized != 'cliente' &&
        normalized != 'nombre' &&
        normalized != 'rut' &&
        !normalized.startsWith('fecha') &&
        !RegExp(r'^\d+$').hasMatch(normalized);
  }

  String _cleanDelegatedSellerName(String value) {
    return value
        .replaceAll(RegExp(r'^[\s:.-]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'\.$'), '')
        .trim();
  }

  String _normalizeRutFormat(String rut) {
    if (rut.contains('.')) return rut;
    return rut.replaceAllMapped(
      RegExp(r'(\d{1,2})(\d{3})(\d{3})(-.+)'),
      (match) => '${match[1]}.${match[2]}.${match[3]}${match[4]}',
    );
  }

  bool _looksLikePdfPageHeader(String value) {
    final normalized = _normalizeInvoiceSearchText(value);
    return RegExp(r'^\d{1,2}\s+\d{1,2}\s+\d{2,4}\b').hasMatch(normalized) &&
        (normalized.contains('pagina') ||
            RegExp(r'\b\d{1,2}\s+\d{2}\b').hasMatch(normalized));
  }

  bool _isKnownRecipientLine(String value) {
    final normalized =
        value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9K]+'), '');
    return normalized.contains('NEWEN') ||
        normalized.contains('775419997') ||
        normalized.contains('RUT775419997');
  }

  /// Extract line items from invoice table
  /// Handles MKR format: Each product spans ~12 lines
  /// Format: [CODE] Name, Description lines, Barcode, Quantity, Unit, Price, Discount, Tax, $, Total
  List<ParsedLineItem> _extractLineItems(List<String> lines) {
    final items = <ParsedLineItem>[];

    print('🔍 Extracting line items from ${lines.length} lines...');

    final aliExpressItems = _extractGeneratedAliExpressLineItems(lines);
    if (aliExpressItems.isNotEmpty) {
      print(
          '📦 Extracted ${aliExpressItems.length} AliExpress generated line items');
      return aliExpressItems;
    }

    final delegatedMarketplaceItems =
        _extractDelegatedMarketplaceLineItems(lines);
    if (delegatedMarketplaceItems.isNotEmpty) {
      print(
        '📦 Extracted ${delegatedMarketplaceItems.length} delegated marketplace line items',
      );
      return delegatedMarketplaceItems;
    }

    // Find table boundaries
    int startIndex = -1;
    int endIndex = lines.length;

    // Find start: Look for "IMPORTE" header (last column before data)
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].toUpperCase().trim() == 'IMPORTE') {
        startIndex = i + 1; // Data starts after IMPORTE header
        print('📋 Found table start at line $i: "${lines[i]}"');
        break;
      }
    }

    // Find end: Look for "Total neto" (starts totals section)
    for (int i = startIndex >= 0 ? startIndex : 0; i < lines.length; i++) {
      if (lines[i].toUpperCase().contains('TOTAL NETO') ||
          lines[i].toUpperCase().contains('TOTAL') && i > startIndex + 10) {
        endIndex = i;
        print('📋 Found table end at line $i: "${lines[i]}"');
        break;
      }
    }

    if (startIndex < 0 || startIndex >= endIndex) {
      print('⚠️ Could not find valid table boundaries');
      return items;
    }

    // Parse products: Each product starts with [CODE] pattern
    int i = startIndex;
    int productCount = 0;
    const maxProducts = 50; // Safety: Max 50 products per invoice

    while (i < endIndex && productCount < maxProducts) {
      final line = lines[i].trim();

      // Check if this line starts a new product: [CODE] Name
      final productMatch = RegExp(r'^\[([A-Z0-9]+)\]\s+(.+)$').firstMatch(line);
      if (productMatch != null) {
        productCount++;
        final code = productMatch.group(1)!;
        var description = productMatch.group(2)!;
        String? imageUrl;
        String? productUrl;
        final rawRowBuffer = StringBuffer(line);

        print('📦 Found product code: [$code] $description at line $i');

        // Collect description lines (until we hit a barcode-like number or "Unidades")
        i++;
        int safetyCounter = 0;
        const maxDescLines = 10; // URLs from generated invoices may wrap.

        while (i < endIndex && safetyCounter < maxDescLines) {
          final descLine = lines[i].trim();
          rawRowBuffer.writeln(descLine);

          if (_isMetadataLine(descLine, 'ORIGINAL_TITLE')) {
            i++;
            safetyCounter++;
            continue;
          }

          final extractedImageUrl = _extractMetadataUrl(descLine, 'IMAGE_URL');
          if (extractedImageUrl != null) {
            imageUrl = extractedImageUrl;
            i++;
            safetyCounter++;
            continue;
          }

          final extractedProductUrl =
              _extractMetadataUrl(descLine, 'PRODUCT_URL') ??
                  _extractAliExpressProductUrl(descLine);
          if (extractedProductUrl != null) {
            productUrl = extractedProductUrl;
            i++;
            safetyCounter++;
            continue;
          }

          if (_looksLikeQuantityBeforeUnit(lines, i, endIndex)) {
            break;
          }

          // Stop if we hit quantity-related keywords
          if (descLine.toUpperCase().contains('UNIDADES') ||
              RegExp(r'^\d{13,}$').hasMatch(descLine)) {
            break;
          }

          // Add description lines (skip barcode, quantity patterns)
          if (descLine.isNotEmpty &&
              !RegExp(r'^[\d,\.]+$').hasMatch(descLine) &&
              descLine.toUpperCase() != 'IVA 19%' &&
              descLine.toUpperCase() != 'VTA' &&
              descLine != '\$') {
            description += ' $descLine';
          }

          i++;
          safetyCounter++;
        }

        // Now we should be near quantity line
        // Look ahead for quantity (number with comma, like "20,00" or "3,00")
        double? quantity;
        double? unitPrice;
        double? lineTotal;

        for (int j = i; j < (i + 15).clamp(0, endIndex); j++) {
          if (j >= lines.length) break; // Safety check
          final testLine = lines[j].trim();

          // Quantity: Usually before "Unidades", format "20,00" (1-4 digits, comma, 2 decimals)
          if (quantity == null &&
              RegExp(r'^\d{1,4},\d{2}$').hasMatch(testLine)) {
            quantity = _parseAmount(testLine);
            print('  📊 Quantity: $quantity at line $j');
          }

          // Unit price: Usually after "Unidades", format "2.550,10" (has thousands separator)
          if (unitPrice == null &&
              RegExp(r'^\d{1,3}\.\d{3},\d{2}$').hasMatch(testLine) &&
              j > 0 &&
              lines[j - 1].toUpperCase().contains('UNIDADES')) {
            unitPrice = _parseAmount(testLine);
            print('  💰 Unit price: \$$unitPrice at line $j');
          }

          // Line total: After "$" symbol, format "25.501" or "7.336"
          if (lineTotal == null && j > 0 && lines[j - 1].trim() == '\$') {
            final totalMatch = RegExp(r'^([\d.,]+)$').firstMatch(testLine);
            if (totalMatch != null) {
              lineTotal = _parseAmount(totalMatch.group(1)!);
              print('  💵 Line total: \$$lineTotal at line $j');
              break; // Found total, move to next product
            }
          }
        }

        // Create line item if we have minimum required data
        if (description.isNotEmpty) {
          items.add(ParsedLineItem(
            description: description.trim(),
            sku: code,
            rawRowText: rawRowBuffer.toString().trim(),
            imageUrl: imageUrl,
            productUrl: productUrl,
            quantity: quantity,
            unitPrice: unitPrice,
            total: lineTotal,
          ));
          print(
              '  ✅ Added item: $code - $description (qty: $quantity, price: \$$unitPrice)');
        }

        // Skip ahead past this product's data (roughly 12 lines per product)
        i += 10;
      } else {
        i++;
      }
    }

    print('📦 Extracted ${items.length} line items');
    return items;
  }

  List<ParsedLineItem> _extractDelegatedMarketplaceLineItems(
    List<String> lines,
  ) {
    if (_delegatedMarketplaceSellerMarkerIndex(lines) < 0) return const [];

    var startIndex = -1;
    for (var i = 0; i < lines.length; i++) {
      final normalized = _normalizeInvoiceSearchText(lines[i]);
      if (normalized == 'imp ad' || normalized == 'detalle') {
        startIndex = i + 1;
      }
      if (startIndex >= 0 && normalized == 'importes totales') {
        break;
      }
    }
    if (startIndex < 0) return const [];

    var endIndex = lines.length;
    for (var i = startIndex; i < lines.length; i++) {
      final normalized = _normalizeInvoiceSearchText(lines[i]);
      if (normalized == 'importes totales' ||
          normalized == 'monto neto' ||
          normalized == 'transporte') {
        endIndex = i;
        break;
      }
    }
    if (startIndex >= endIndex) return const [];

    final items = <ParsedLineItem>[];
    var cursor = startIndex;
    while (cursor < endIndex && items.length < 100) {
      if (!RegExp(r'^\d{1,3}$').hasMatch(lines[cursor].trim())) {
        cursor++;
        continue;
      }

      var quantityIndex = -1;
      for (var i = cursor + 2; i < endIndex && i <= cursor + 8; i++) {
        if (!_looksLikeDelegatedMarketplaceQuantity(lines[i])) continue;
        final moneyCount = lines
            .sublist(i + 1, (i + 5).clamp(0, endIndex).toInt())
            .where(_looksLikeCurrencyAmountLine)
            .length;
        if (moneyCount >= 2) {
          quantityIndex = i;
          break;
        }
      }
      if (quantityIndex < 0) {
        cursor++;
        continue;
      }

      final description = lines
          .sublist(cursor + 1, quantityIndex)
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .join(' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (description.isEmpty) {
        cursor = quantityIndex + 1;
        continue;
      }

      final moneyLines = <String>[];
      var nextCursor = quantityIndex + 1;
      while (nextCursor < endIndex && moneyLines.length < 2) {
        final value = lines[nextCursor].trim();
        if (_looksLikeCurrencyAmountLine(value)) {
          moneyLines.add(value);
        }
        nextCursor++;
      }
      if (moneyLines.length < 2) {
        cursor = quantityIndex + 1;
        continue;
      }

      final quantity = _parseAmount(lines[quantityIndex]);
      final unitPrice = _parseAmount(moneyLines.first);
      final total = _parseAmount(moneyLines.last);
      items.add(
        ParsedLineItem(
          description: description,
          rawRowText: lines
              .sublist(cursor, nextCursor)
              .map((line) => line.trim())
              .join('\n'),
          quantity: quantity,
          unitPrice: unitPrice,
          total: total,
        ),
      );
      cursor = nextCursor;
    }

    return items;
  }

  bool _looksLikeDelegatedMarketplaceQuantity(String value) {
    return RegExp(r'^\d{1,6}(?:[.,]\d{1,3})?$').hasMatch(value.trim());
  }

  bool _looksLikeCurrencyAmountLine(String value) {
    return RegExp(r'^\$\s*\d[\d.,]*$').hasMatch(value.trim());
  }

  List<ParsedLineItem> _extractGeneratedAliExpressLineItems(
      List<String> lines) {
    final looksGenerated = lines.any((line) =>
            line.toUpperCase().contains('ALIEXPRESS MARKETPLACE') ||
            line.toUpperCase().contains('FACTURA OCR ALIEXPRESS')) &&
        lines.any((line) => line.toUpperCase().contains('SKU:')) &&
        lines.any((line) => line.toUpperCase().contains('IMPORTE'));
    if (!looksGenerated) return const [];

    final amountRowsByNumber = <int, _GeneratedAliExpressAmountRow>{
      for (final row in _extractGeneratedAliExpressAmountRows(lines))
        row.rowNumber: row,
    };
    final productBlocks = _extractGeneratedAliExpressProductBlocks(lines);
    if (productBlocks.isEmpty) return const [];

    final items = <ParsedLineItem>[];
    for (var i = 0; i < productBlocks.length && i < 100; i++) {
      final product = productBlocks[i];
      final amount = amountRowsByNumber[i + 1];
      final description = _cleanGeneratedDescription(product.description);
      if (description.isEmpty &&
          (product.sku == null || product.sku!.isEmpty)) {
        continue;
      }

      items.add(ParsedLineItem(
        description: description.isEmpty
            ? product.sku ?? 'AliExpress item'
            : description,
        lineTitle: product.lineTitle,
        variantLabel: product.variantLabel,
        variantKey: product.variantKey,
        sku: product.sku,
        rawRowText: [
          if (amount != null) amount.rawText,
          product.rawText,
        ].join('\n').trim(),
        imageUrl: product.imageUrl,
        productUrl: product.productUrl,
        sourcePurchaseQuantity:
            product.sourcePurchaseQuantity ?? amount?.quantity,
        sourcePurchaseUnitPrice: product.sourcePurchaseUnitPrice,
        rawPackCount: product.rawPackCount,
        rawUnitToken: product.rawUnitToken,
        rawPackEvidenceConflict: product.rawPackEvidenceConflict,
        sourceOrderNumbers: product.sourceOrderNumbers,
        // Generated AliExpress rows carry the supplier purchase quantity here.
        // Pack evidence remains separate until catalog resolution.
        quantity: product.sourcePurchaseQuantity ?? amount?.quantity,
        unitPrice: amount?.unitPrice,
        total: amount?.total,
      ));
    }

    return items;
  }

  List<_GeneratedAliExpressAmountRow> _extractGeneratedAliExpressAmountRows(
    List<String> lines,
  ) {
    var tableStart = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].toUpperCase().trim() == 'IMPORTE') {
        tableStart = i + 1;
        break;
      }
    }
    if (tableStart < 0) return const [];

    var tableEnd = lines.length;
    for (var i = tableStart; i < lines.length; i++) {
      final upper = lines[i].toUpperCase();
      if (upper.contains('SUBTOTAL') || upper == 'TOTAL') {
        tableEnd = i;
        break;
      }
    }

    final rows = <_GeneratedAliExpressAmountRow>[];
    var rowStart = _findGeneratedAmountRowStart(
      lines,
      tableStart,
      tableEnd,
      1,
    );

    while (rowStart >= 0 && rowStart < tableEnd && rows.length < 100) {
      final rowNumber = int.tryParse(lines[rowStart].trim());
      if (rowNumber == null || rowNumber <= 0 || rowNumber > 100) break;
      final nextRowStart = _findNextGeneratedAmountRowStart(
        lines,
        rowStart + 1,
        tableEnd,
        afterRowNumber: rowNumber,
      );
      final rowEnd = nextRowStart < 0 ? tableEnd : nextRowStart;
      final row = _parseGeneratedAliExpressAmountRow(
        lines.sublist(rowStart, rowEnd),
        rowNumber,
      );
      if (row != null) rows.add(row);
      rowStart = nextRowStart;
    }

    return rows;
  }

  int _findGeneratedAmountRowStart(
    List<String> lines,
    int start,
    int end,
    int expectedIndex,
  ) {
    final expected = expectedIndex.toString();
    for (var i = start; i < end; i++) {
      if (lines[i].trim() != expected) continue;
      final lookaheadEnd = (i + 12).clamp(0, end).toInt();
      final window = lines.sublist(i + 1, lookaheadEnd);
      final hasQuantity =
          window.any((line) => _looksLikeGeneratedPlainNumber(line.trim()));
      final amountCount = window
          .where((line) => _parseSignedGeneratedMoneyLine(line) != null)
          .length;
      if (hasQuantity && amountCount >= 2) return i;
    }
    return -1;
  }

  int _findNextGeneratedAmountRowStart(
    List<String> lines,
    int start,
    int end, {
    required int afterRowNumber,
  }) {
    var precedingAmountCount = 0;
    for (var i = start; i < end; i++) {
      if (_parseSignedGeneratedMoneyLine(lines[i]) != null) {
        precedingAmountCount++;
        continue;
      }
      if (precedingAmountCount < 2) continue;

      final candidate = int.tryParse(lines[i].trim());
      if (candidate == null || candidate <= afterRowNumber || candidate > 100) {
        continue;
      }
      final lookaheadEnd = (i + 12).clamp(0, end).toInt();
      final window = lines.sublist(i + 1, lookaheadEnd);
      final hasQuantity =
          window.any((line) => _looksLikeGeneratedPlainNumber(line.trim()));
      final amountCount = window
          .where((line) => _parseSignedGeneratedMoneyLine(line) != null)
          .length;
      if (hasQuantity && amountCount >= 2) return i;
    }
    return -1;
  }

  _GeneratedAliExpressAmountRow? _parseGeneratedAliExpressAmountRow(
    List<String> row,
    int rowNumber,
  ) {
    if (row.isEmpty) return null;

    final rawRowBuffer = StringBuffer();
    final amounts = <double>[];
    final quantityCandidates = <double>[];
    double? quantity;

    for (var i = 0; i < row.length; i++) {
      final line = row[i].trim();
      if (line.isEmpty) continue;
      rawRowBuffer.writeln(line);
      if (i == 0 && RegExp(r'^\d{1,3}$').hasMatch(line)) continue;

      final amount = _parseSignedGeneratedMoneyLine(line);
      if (amount != null) {
        quantity ??=
            quantityCandidates.isEmpty ? null : quantityCandidates.last;
        amounts.add(amount);
        continue;
      }
      if (line == '\$' && i + 1 < row.length) {
        final splitAmount = _parseSignedAmount(row[i + 1]);
        if (splitAmount != null) {
          quantity ??=
              quantityCandidates.isEmpty ? null : quantityCandidates.last;
          amounts.add(splitAmount);
          i++;
          continue;
        }
      }

      if (_looksLikeGeneratedPlainNumber(line)) {
        final parsedQuantity = _parseAmount(line);
        if (parsedQuantity != null && parsedQuantity > 0) {
          quantityCandidates.add(parsedQuantity);
        }
      }
    }

    quantity ??= quantityCandidates.isEmpty ? null : quantityCandidates.last;
    if (quantity == null && amounts.isEmpty) return null;
    return _GeneratedAliExpressAmountRow(
      rowNumber: rowNumber,
      quantity: quantity,
      unitPrice: amounts.length >= 6
          ? amounts[amounts.length - 2]
          : (amounts.isNotEmpty ? amounts.first : null),
      total: amounts.length > 1 ? amounts.last : null,
      rawText: rawRowBuffer.toString().trim(),
    );
  }

  List<_GeneratedAliExpressProductBlock>
      _extractGeneratedAliExpressProductBlocks(
    List<String> lines,
  ) {
    final blocks = <_GeneratedAliExpressProductBlock>[];
    var i = 0;

    while (i < lines.length && blocks.length < 100) {
      if (!_isGeneratedDescriptionStart(lines, i)) {
        i++;
        continue;
      }

      final skuIndex = _findGeneratedSkuLine(lines, i + 1, maxDistance: 8);
      if (skuIndex < 0) {
        i++;
        continue;
      }

      final descriptionLines = <String>[];
      final rawRowBuffer = StringBuffer();
      for (var j = i; j < skuIndex; j++) {
        final line = lines[j].trim();
        if (_isSkippableGeneratedDescriptionPart(line)) continue;
        descriptionLines.add(line);
        rawRowBuffer.writeln(line);
      }

      final skuLine = lines[skuIndex].trim();
      rawRowBuffer.writeln(skuLine);
      final sku = RegExp(r'^SKU\s*:\s*(\S+)', caseSensitive: false)
          .firstMatch(skuLine)
          ?.group(1)
          ?.trim();

      String? imageUrl;
      String? productUrl;
      String? lineTitle;
      String? variantLabel;
      String? variantKey;
      double? sourcePurchaseQuantity;
      double? sourcePurchaseUnitPrice;
      int? rawPackCount;
      String? rawUnitToken;
      var rawPackEvidenceConflict = false;
      var sourceOrderNumbers = const <String>[];
      double? legacyUnitsPerPurchase;
      String? legacyInventoryUnit;
      var cursor = skuIndex + 1;
      while (cursor < lines.length) {
        if (_isGeneratedDescriptionStart(lines, cursor)) break;

        final line = lines[cursor].trim();
        if (line.isEmpty) {
          cursor++;
          continue;
        }

        rawRowBuffer.writeln(line);
        final extractedLineTitle = _extractMetadataValue(line, 'LINE_TITLE') ??
            _extractMetadataValue(line, 'ORIGINAL_TITLE');
        if (extractedLineTitle != null) {
          lineTitle = extractedLineTitle;
          cursor++;
          continue;
        }
        final extractedVariant = _extractMetadataValue(line, 'VARIANT');
        if (extractedVariant != null) {
          variantLabel = extractedVariant;
          cursor++;
          continue;
        }
        final extractedVariantKey = _extractMetadataValue(line, 'VARIANT_KEY');
        if (extractedVariantKey != null) {
          variantKey = extractedVariantKey;
          cursor++;
          continue;
        }
        final extractedSourceQuantity =
            _extractMetadataNumber(line, 'SOURCE_PURCHASE_QUANTITY');
        if (extractedSourceQuantity != null && extractedSourceQuantity > 0) {
          sourcePurchaseQuantity = extractedSourceQuantity;
          cursor++;
          continue;
        }
        final extractedSourceUnitPrice =
            _extractMetadataNumber(line, 'SOURCE_PURCHASE_UNIT_PRICE');
        if (extractedSourceUnitPrice != null && extractedSourceUnitPrice >= 0) {
          sourcePurchaseUnitPrice = extractedSourceUnitPrice;
          cursor++;
          continue;
        }
        final extractedRawPackCount =
            _extractMetadataPositiveInt(line, 'RAW_PACK_COUNT');
        if (extractedRawPackCount != null) {
          rawPackCount = extractedRawPackCount;
          cursor++;
          continue;
        }
        final extractedRawUnitToken =
            _extractMetadataValue(line, 'RAW_UNIT_TOKEN');
        if (extractedRawUnitToken != null) {
          rawUnitToken = extractedRawUnitToken;
          cursor++;
          continue;
        }
        if (_extractMetadataBoolean(line, 'RAW_PACK_EVIDENCE_CONFLICT') ==
            true) {
          rawPackEvidenceConflict = true;
          cursor++;
          continue;
        }
        final extractedSourceOrders =
            _extractMetadataValue(line, 'SOURCE_ORDERS');
        if (extractedSourceOrders != null) {
          sourceOrderNumbers = ParsedLineItem._stringList(
            extractedSourceOrders,
          );
          cursor++;
          continue;
        }
        final extractedLegacyUnits =
            _extractMetadataNumber(line, 'UNITS_PER_PURCHASE');
        if (extractedLegacyUnits != null && extractedLegacyUnits > 1) {
          legacyUnitsPerPurchase = extractedLegacyUnits;
          cursor++;
          continue;
        }
        final extractedLegacyInventoryUnit =
            _extractMetadataValue(line, 'INVENTORY_UNIT');
        if (extractedLegacyInventoryUnit != null) {
          legacyInventoryUnit = extractedLegacyInventoryUnit;
          cursor++;
          continue;
        }
        final extractedImageUrl = _extractMetadataUrl(line, 'IMAGE_URL');
        if (extractedImageUrl != null) {
          imageUrl = extractedImageUrl;
          cursor++;
          continue;
        }

        final extractedProductUrl = _extractMetadataUrl(line, 'PRODUCT_URL') ??
            _extractAliExpressProductUrl(line);
        if (extractedProductUrl != null) {
          productUrl = extractedProductUrl;
          cursor++;
          continue;
        }

        cursor++;
      }

      final description =
          _cleanGeneratedDescription(descriptionLines.join(' '));
      if (rawPackCount == null &&
          rawUnitToken == null &&
          legacyUnitsPerPurchase != null &&
          legacyUnitsPerPurchase == legacyUnitsPerPurchase.roundToDouble() &&
          legacyInventoryUnit != null) {
        rawPackCount = legacyUnitsPerPurchase.toInt();
        rawUnitToken = legacyInventoryUnit;
      }
      blocks.add(_GeneratedAliExpressProductBlock(
        description: description,
        lineTitle: lineTitle,
        variantLabel: variantLabel,
        variantKey: variantKey,
        sku: sku,
        imageUrl: imageUrl,
        productUrl: productUrl,
        sourcePurchaseQuantity: sourcePurchaseQuantity,
        sourcePurchaseUnitPrice: sourcePurchaseUnitPrice,
        rawPackCount: rawPackCount,
        rawUnitToken: rawUnitToken,
        rawPackEvidenceConflict: rawPackEvidenceConflict,
        sourceOrderNumbers: sourceOrderNumbers,
        rawText: rawRowBuffer.toString().trim(),
      ));
      i = cursor;
    }

    return blocks;
  }

  bool _isGeneratedDescriptionStart(List<String> lines, int index) {
    if (index < 0 || index >= lines.length) return false;
    final line = lines[index].trim();
    if (_isSkippableGeneratedProductLine(line)) return false;
    return _findGeneratedSkuLine(lines, index + 1, maxDistance: 8) > index;
  }

  int _findGeneratedSkuLine(
    List<String> lines,
    int start, {
    required int maxDistance,
  }) {
    final end = (start + maxDistance).clamp(0, lines.length).toInt();
    for (var i = start; i < end; i++) {
      if (RegExp(r'^SKU\s*:', caseSensitive: false).hasMatch(lines[i].trim())) {
        return i;
      }
      if (i > start && _isGeneratedDescriptionStartBoundary(lines[i])) break;
    }
    return -1;
  }

  bool _isGeneratedDescriptionStartBoundary(String line) {
    final upper = line.trim().toUpperCase();
    return upper.startsWith('SUBTOTAL') ||
        upper == 'TOTAL' ||
        upper.startsWith('PAGO REALIZADO') ||
        upper.startsWith('SALDO ADEUDADO');
  }

  bool _isSkippableGeneratedDescriptionPart(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return true;
    if (trimmed.toUpperCase() == 'OR') return true;
    if (_isGeneratedInvoiceNoiseLine(trimmed)) return true;
    if (_looksLikeGeneratedAmount(trimmed)) return true;
    if (_looksLikeGeneratedPlainNumber(trimmed)) return true;
    if (_isMetadataLine(trimmed, 'ORIGINAL_TITLE') ||
        _isMetadataLine(trimmed, 'LINE_TITLE') ||
        _isMetadataLine(trimmed, 'VARIANT') ||
        _isMetadataLine(trimmed, 'VARIANT_KEY') ||
        _isMetadataLine(trimmed, 'SOURCE_PURCHASE_QUANTITY') ||
        _isMetadataLine(trimmed, 'SOURCE_PURCHASE_UNIT_PRICE') ||
        _isMetadataLine(trimmed, 'RAW_PACK_COUNT') ||
        _isMetadataLine(trimmed, 'RAW_UNIT_TOKEN') ||
        _isMetadataLine(trimmed, 'RAW_PACK_EVIDENCE_CONFLICT') ||
        _isMetadataLine(trimmed, 'SOURCE_ORDERS') ||
        _isMetadataLine(trimmed, 'UNITS_PER_PURCHASE') ||
        _isMetadataLine(trimmed, 'INVENTORY_UNIT') ||
        _isMetadataLine(trimmed, 'PRODUCT_URL') ||
        _isMetadataLine(trimmed, 'IMAGE_URL')) {
      return true;
    }
    if (_extractAliExpressProductUrl(trimmed) != null) return true;
    if (RegExp(r'^SKU\s*:', caseSensitive: false).hasMatch(trimmed)) {
      return true;
    }
    return false;
  }

  bool _isSkippableGeneratedProductLine(String line) {
    final trimmed = line.trim();
    if (_isSkippableGeneratedDescriptionPart(trimmed)) return true;
    return !_looksLikeGeneratedDescriptionLine(trimmed);
  }

  bool _looksLikeGeneratedPlainNumber(String line) {
    return RegExp(r'^\d{1,4}(?:[\.,]\d{1,2})?$').hasMatch(line.trim());
  }

  double? _parseSignedAmount(String amountStr) {
    final amount = _parseAmount(amountStr);
    if (amount == null) return null;
    final isNegative = RegExp(r'[-−–]').hasMatch(amountStr);
    return isNegative ? -amount : amount;
  }

  double? _parseSignedGeneratedMoneyLine(String line) {
    final trimmed = line.trim();
    if (!trimmed.contains('\$')) return null;
    return _parseSignedAmount(trimmed);
  }

  bool _looksLikeGeneratedAmount(String line) {
    return _parseSignedGeneratedMoneyLine(line) != null;
  }

  bool _isGeneratedInvoiceNoiseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return true;
    final upper = trimmed.toUpperCase();
    return upper == '#' ||
        upper == 'IMAGEN' ||
        upper == 'ARTÍCULO & DESCRIPCIÓN' ||
        upper == 'ARTICULO & DESCRIPCION' ||
        upper == 'CANTIDAD' ||
        upper == 'TARIFA' ||
        upper == 'IMPORTE' ||
        upper == 'UNIDADES' ||
        upper == '\$' ||
        upper.startsWith('PEDIDO ') ||
        upper.startsWith('FACTURA ') ||
        upper.startsWith('FECHA') ||
        upper.startsWith('PROVEEDOR') ||
        upper.startsWith('PAGO REALIZADO') ||
        upper.startsWith('SALDO ') ||
        upper.startsWith('SUBTOTAL') ||
        upper == 'TOTAL';
  }

  bool _looksLikeGeneratedDescriptionLine(String line) {
    final trimmed = _cleanGeneratedDescription(line);
    if (trimmed.length < 8) return false;
    if (RegExp(r'^[A-Z0-9\-]{2,10}$').hasMatch(trimmed)) return false;
    if (RegExp(r'^AE-[A-Z0-9\-]+$', caseSensitive: false).hasMatch(trimmed)) {
      return false;
    }
    return true;
  }

  String _cleanGeneratedDescription(String value) {
    return value
        .replaceAll(RegExp(r'^\s*\[\d{8,}\]\s*'), '')
        .replaceAll(
            RegExp(r'\s*SKU\s*:\s*\S+.*$', caseSensitive: false, dotAll: true),
            '')
        .replaceAll(
            RegExp(r'\s*Item\s*ID\s*:?\s*\d+.*$',
                caseSensitive: false, dotAll: true),
            '')
        .replaceAll(
            RegExp(r'\s*ORIGINAL_TITLE\s*:.*$',
                caseSensitive: false, dotAll: true),
            '')
        .replaceAll(
            RegExp(r'\s*LINE_TITLE\s*:.*$', caseSensitive: false, dotAll: true),
            '')
        .replaceAll(
            RegExp(r'\s*VARIANT(?:_KEY)?\s*:.*$',
                caseSensitive: false, dotAll: true),
            '')
        .replaceAll(
            RegExp(
                r'\s*(?:SOURCE_PURCHASE_QUANTITY|SOURCE_PURCHASE_UNIT_PRICE|RAW_PACK_COUNT|RAW_UNIT_TOKEN|RAW_PACK_EVIDENCE_CONFLICT|SOURCE_ORDERS|UNITS_PER_PURCHASE|INVENTORY_UNIT)\s*:.*$',
                caseSensitive: false,
                dotAll: true),
            '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _looksLikeQuantityBeforeUnit(
      List<String> lines, int index, int endIndex) {
    final current = lines[index].trim();
    if (!RegExp(r'^\d{1,4}(?:[\.,]\d{1,2})?$').hasMatch(current)) {
      return false;
    }
    if (index + 1 >= endIndex) return false;
    return lines[index + 1].toUpperCase().contains('UNIDADES');
  }

  String? _extractMetadataUrl(String line, String key) {
    final match = RegExp('^$key\\s*:\\s*(\\S+)', caseSensitive: false)
        .firstMatch(line.trim());
    final value = match?.group(1)?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  String? _extractMetadataValue(String line, String key) {
    final match = RegExp('^$key\\s*:\\s*(.+)' r'$', caseSensitive: false)
        .firstMatch(line.trim());
    final value = match?.group(1)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  double? _extractMetadataNumber(String line, String key) {
    final value = _extractMetadataValue(line, key);
    if (value == null) return null;
    return double.tryParse(value.replaceAll(',', '.'));
  }

  int? _extractMetadataPositiveInt(String line, String key) {
    final value = _extractMetadataNumber(line, key);
    if (value == null || value <= 0 || value != value.roundToDouble()) {
      return null;
    }
    return value.toInt();
  }

  bool? _extractMetadataBoolean(String line, String key) {
    final value = _extractMetadataValue(line, key)?.toLowerCase();
    if (value == 'true') return true;
    if (value == 'false') return false;
    return null;
  }

  bool _isMetadataLine(String line, String key) {
    return RegExp('^$key\\s*:', caseSensitive: false).hasMatch(line.trim());
  }

  String? _extractAliExpressProductUrl(String line) {
    final trimmed = line.trim();
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)) {
      return null;
    }
    if (!RegExp(r'aliexpress|/item/|itemId=|productId=', caseSensitive: false)
        .hasMatch(trimmed)) {
      return null;
    }
    return trimmed;
  }

  /// Parse receipt (simpler format than invoice)
  /// Extracts: vendor name, total, date
  ParsedInvoice parseReceipt(RecognizedText recognizedText) {
    final fullText = recognizedText.text;
    final lines = fullText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    print('📋 Parsing receipt from ${lines.length} lines of text');

    return ParsedInvoice(
      supplierName: _extractSupplierName(lines, recognizedText.blocks),
      date: _extractDate(lines),
      total: _extractTotal(lines),
      rawText: fullText,
    );
  }
}
