import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Parsed invoice data extracted from OCR text
class ParsedInvoice {
  final String? rut; // Chilean tax ID (e.g., "12.345.678-9")
  final String? invoiceNumber; // Folio or invoice number
  final DateTime? date; // Invoice date
  final double? total; // Total amount
  final String? supplierName; // Vendor/supplier name
  final List<ParsedLineItem> lineItems; // Extracted line items
  final String rawText; // Full extracted text for debugging

  ParsedInvoice({
    this.rut,
    this.invoiceNumber,
    this.date,
    this.total,
    this.supplierName,
    this.lineItems = const [],
    required this.rawText,
  });

  @override
  String toString() {
    return 'ParsedInvoice(rut: $rut, number: $invoiceNumber, date: $date, total: $total, supplier: $supplierName, items: $lineItems)';
  }
}

/// Line item extracted from invoice
class ParsedLineItem {
  final String description;
  final String? sku;
  final double? quantity;
  final double? unitPrice;
  final double? total;
  final double? discount;
  final double? discountRate;

  ParsedLineItem({
    required this.description,
    this.sku,
    this.quantity,
    this.unitPrice,
    this.total,
    this.discount,
    this.discountRate,
  });

  @override
  String toString() {
    return 'LineItem($description, sku: $sku, qty: $quantity, price: $unitPrice, total: $total, discount: $discount, rate: $discountRate)';
  }
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
      supplierName: _extractSupplierNameFromLines(lines),
      lineItems: _extractLineItems(lines),
      rawText: text,
    );
  }

  /// Extract Chilean RUT (e.g., "76.123.456-7", "12345678-9")
  /// Patterns: XX.XXX.XXX-X or XXXXXXXX-X
  String? _extractRUT(List<String> lines) {
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

      // If current line is exactly "TOTAL" (or "Total neto", "TOTAL GENERAL", etc.)
      if (currentLine == 'TOTAL' ||
          currentLine.startsWith('TOTAL ') ||
          currentLine == 'MONTO TOTAL' ||
          currentLine == 'MONTO') {
        // Check if next line has a currency amount
        final amountPattern = RegExp(r'\$\s*([\d.,]+)');
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
        // Format: 12,345.67 (US format)
        cleaned = cleaned.replaceAll(',', '');
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
    // Strategy 1: Look for "Mauricio Kishinevsky" or company patterns at bottom
    for (var i = lines.length - 1; i >= 0 && i > lines.length - 20; i--) {
      final text = lines[i].trim();

      // Check for company indicators (S.A., Ltda., SpA, etc.)
      if (RegExp(r'\b(S\.A\.|Ltda\.|SpA|SPA|LTDA)\b', caseSensitive: false)
          .hasMatch(text)) {
        // Clean up the company name
        var companyName = text
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
      if (text.contains('77541999-7') || text.toUpperCase().contains('NEWEN')) {
        continue;
      }

      if (text.length > 3 &&
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

  /// Extract line items from invoice table
  /// Handles MKR format: Each product spans ~12 lines
  /// Format: [CODE] Name, Description lines, Barcode, Quantity, Unit, Price, Discount, Tax, $, Total
  List<ParsedLineItem> _extractLineItems(List<String> lines) {
    final items = <ParsedLineItem>[];

    print('🔍 Extracting line items from ${lines.length} lines...');

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

        print('📦 Found product code: [$code] $description at line $i');

        // Collect description lines (until we hit a barcode-like number or "Unidades")
        i++;
        int safetyCounter = 0;
        const maxDescLines = 5; // Safety: Max 5 description lines per product

        while (i < endIndex && safetyCounter < maxDescLines) {
          final descLine = lines[i].trim();

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
            description += ' ' + descLine;
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
