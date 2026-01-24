import '../../modules/sales/models/sales_models.dart';
import '../../shared/models/tax_treatment.dart';
import 'package:flutter/foundation.dart';
import '../services/invoice_parser_service.dart';

/// Adapter to convert Veryfi response JSON into our internal `Invoice` model.
class VeryfiAdapter {
  /// Format a number with Chilean thousand separators (dots)
  /// e.g., 12690 → "12.690", 1790 → "1.790"
  static String _formatWithDots(int value) {
    final str = value.toString();
    if (str.length <= 3) return str;

    final buffer = StringBuffer();
    int count = 0;
    for (int i = str.length - 1; i >= 0; i--) {
      buffer.write(str[i]);
      count++;
      if (count % 3 == 0 && i > 0) {
        buffer.write('.');
      }
    }
    return buffer.toString().split('').reversed.join();
  }

  /// Patterns to extract SKU codes from product descriptions.
  /// Priority order:
  /// 1. Explicit "SKU: XXXXX" labels (highest priority)
  /// 2. Alphanumeric codes with dashes like "U-311728"
  /// 3. Pure alphanumeric codes like "213111BN"
  /// 4. Size/dimension codes as last resort

  /// Try to extract a SKU from a description string.
  /// Prioritizes explicit SKU labels over dimension/size codes.
  static String? _extractSkuFromDescription(String description) {
    if (description.isEmpty) return null;

    // PRIORITY 1: Look for explicit "SKU: XXXXX" or "Código: XXXXX" labels
    // These are the most reliable - suppliers explicitly label their SKUs
    final explicitSkuPatterns = [
      // "SKU: 213111BN" or "SKU:213111BN" or "SKU 213111BN"
      RegExp(r'SKU[:\s]+([A-Z0-9\-]+)', caseSensitive: false),
      // "Código: ABC123" or "Cod: ABC123"
      RegExp(r'C[óo]d(?:igo)?[:\s]+([A-Z0-9\-]+)', caseSensitive: false),
      // "Ref: ABC123" or "Referencia: ABC123"
      RegExp(r'Ref(?:erencia)?[:\s]+([A-Z0-9\-]+)', caseSensitive: false),
    ];

    for (final pattern in explicitSkuPatterns) {
      final match = pattern.firstMatch(description);
      if (match != null) {
        final sku = match.group(1)!.trim();
        if (sku.length >= 3) {
          debugPrint('   🔍 Found explicit SKU label: "$sku"');
          return sku;
        }
      }
    }

    // PRIORITY 2: Alphanumeric codes with dashes (likely supplier codes)
    final dashedPattern =
        RegExp(r'[A-Z0-9]{1,3}-[A-Z0-9\-]+', caseSensitive: false);
    final match = dashedPattern.firstMatch(description);
    if (match != null) {
      final sku = match.group(0)!.trim();
      debugPrint('   🔍 Found dashed code: "$sku"');
      return sku;
    }

    // Default: Check if the description itself starts with a code-like pattern
    // Continue searching for other patterns if not found...

    // PRIORITY 3: Pure numeric codes (6+ digits, likely supplier codes)
    // e.g., "213111", "213016"
    final numericPattern = RegExp(r'\b(\d{6,})\b');
    final numericMatch = numericPattern.firstMatch(description);
    if (numericMatch != null) {
      final sku = numericMatch.group(1)!;
      debugPrint('   🔍 Found numeric SKU: "$sku"');
      return sku;
    }

    // PRIORITY 4: Alphanumeric codes ending with letters (e.g., "213111BN")
    // Must have at least 4 digits followed by letters
    final alphanumericPattern =
        RegExp(r'\b(\d{4,}[A-Z]{1,3})\b', caseSensitive: false);
    final alphaMatch =
        alphanumericPattern.firstMatch(description.toUpperCase());
    if (alphaMatch != null) {
      final sku = alphaMatch.group(1)!;
      debugPrint('   🔍 Found alphanumeric SKU: "$sku"');
      return sku;
    }

    // PRIORITY 5 (LOWEST): Size/dimension codes - only if nothing else found
    // These are less reliable as SKUs, but better than nothing
    // Skipping this for now - size codes caused confusion

    debugPrint('   ⚠ No SKU pattern found in: "$description"');
    return null;
  }

  /// Try to extract a SKU from raw text line (e.g. "2207 CAMARA 26...")
  /// This is used when Veryfi returns a null SKU but the text clearly starts with one.
  static String? _extractSkuFromRawText(String text) {
    if (text.isEmpty) return null;
    // Look for alphanumeric code at start of string (3+ chars)
    // MUST contain at least one digit to avoid matching description words like "GRUESA", "BICICLETA"
    final regex = RegExp(r'^([A-Z0-9-]*\d[A-Z0-9-]*)\s+');
    final match = regex.firstMatch(text.trim());
    if (match != null) {
      final candidate = match.group(1)!;
      // Filter out pure quantities if they are small digits (unlikely to be 3+ chars due to regex, but safe check)
      if (candidate.length < 3) return null;
      return candidate;
    }
    return null;
  }

  /// Parse a Veryfi response map into a `Invoice`.
  ///
  /// `tenantId` is required (multi-tenant). `defaultInvoiceType` can be
  /// used to mark pegas/service invoices if needed.
  static Invoice parseInvoice({
    required Map<String, dynamic> veryfiJson,
    required String tenantId,
    String defaultInvoiceType = 'sale',
  }) {
    // Helper to read nested vendor/name
    String? vendorName;
    try {
      vendorName = veryfiJson['vendor']?['name'] as String?;
    } catch (_) {}
    vendorName ??= veryfiJson['vendor_name'] as String?;
    vendorName ??= veryfiJson['supplier_name'] as String?;

    final invoiceNumber = (veryfiJson['invoice_number'] as String?) ??
        (veryfiJson['number'] as String?) ??
        'VF-${DateTime.now().millisecondsSinceEpoch}';

    DateTime parseDate(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      return DateTime.now();
    }

    final date = parseDate(veryfiJson['date']);
    final dueDate = veryfiJson['due_date'] != null
        ? parseDate(veryfiJson['due_date'])
        : null;

    // Lines: Veryfi commonly returns `line_items`, `lines` or `items`
    final rawLines = (veryfiJson['line_items'] ??
            veryfiJson['lines'] ??
            veryfiJson['items']) as List? ??
        [];

    final items = <InvoiceItem>[];
    double computedSubtotal = 0.0;

    for (final raw in rawLines) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final description =
          map['description']?.toString() ?? map['name']?.toString() ?? '';
      final qty = (map['quantity'] as num?)?.toDouble() ??
          (map['qty'] as num?)?.toDouble() ??
          1.0;
      final unit = (map['unit_price'] as num?)?.toDouble() ??
          (map['price'] as num?)?.toDouble() ??
          0.0;
      final lineTotal = (map['total'] as num?)?.toDouble() ??
          (map['line_total'] as num?)?.toDouble() ??
          (qty * unit);

      computedSubtotal += (map['subtotal'] as num?)?.toDouble() ?? lineTotal;

      final invoiceItem = InvoiceItem(
        id: map['id']?.toString(),
        invoiceId: null,
        productId: null,
        productName: description,
        productSku: map['sku']?.toString(),
        description: description,
        isCatalogProduct: false,
        quantity: qty,
        unitPrice: unit,
        discount: (map['discount'] as num?)?.toDouble() ?? 0.0,
        lineTotal: lineTotal,
        cost: 0,
        isService: false,
      );

      items.add(invoiceItem);
    }

    final subtotal =
        (veryfiJson['subtotal'] as num?)?.toDouble() ?? computedSubtotal;
    final total = (veryfiJson['total'] as num?)?.toDouble() ??
        (veryfiJson['grand_total'] as num?)?.toDouble() ??
        subtotal;

    // Taxes: Veryfi may return `taxes` array or `tax_amount`
    double ivaAmount = 0.0;
    if (veryfiJson['taxes'] is List) {
      for (final t in (veryfiJson['taxes'] as List)) {
        if (t is Map &&
            (t['name'] as String?)?.toLowerCase().contains('iva') == true) {
          ivaAmount += (t['amount'] as num?)?.toDouble() ?? 0.0;
        } else if (t is Map) {
          ivaAmount += (t['amount'] as num?)?.toDouble() ?? 0.0;
        }
      }
    }
    ivaAmount = ivaAmount == 0.0
        ? (veryfiJson['tax_amount'] as num?)?.toDouble() ?? (total - subtotal)
        : ivaAmount;

    // Determine tax treatment: if total equals subtotal it's noTax, else taxIncluded
    final taxTreatment =
        (ivaAmount > 0) ? TaxTreatment.taxIncluded : TaxTreatment.noTax;

    final invoice = Invoice(
      id: null,
      tenantId: tenantId,
      customerId: null,
      invoiceNumber: invoiceNumber,
      customerName: vendorName ?? 'Proveedor desconocido',
      customerRut: null,
      date: date,
      dueDate: dueDate,
      reference: veryfiJson['reference']?.toString(),
      status: InvoiceStatus.draft,
      subtotal: subtotal,
      ivaAmount: ivaAmount,
      total: total,
      paidAmount: 0,
      balance: total,
      taxTreatment: taxTreatment,
      netAmount: taxTreatment == TaxTreatment.taxIncluded ? subtotal : subtotal,
      items: items,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      invoiceType: defaultInvoiceType,
      notes: (veryfiJson['notes'] as String?) ?? veryfiJson['memo'] as String?,
    );

    return invoice;
  }

  /// Convert Veryfi JSON response into the app's `ParsedInvoice` structure
  /// so existing UI and flows (which expect `ParsedInvoice`) can reuse it.
  static ParsedInvoice toParsedInvoice(Map<String, dynamic> veryfiJson) {
    String? supplierName;
    try {
      supplierName = veryfiJson['vendor']?['name'] as String?;
    } catch (_) {}
    supplierName ??= veryfiJson['vendor_name'] as String?;
    supplierName ??= veryfiJson['supplier_name'] as String?;

    final invoiceNumber = (veryfiJson['invoice_number'] as String?) ??
        (veryfiJson['number'] as String?) ??
        (veryfiJson['voucher_number'] as String?);

    DateTime? parseDateNullable(dynamic v) {
      if (v == null) return null;
      if (v is String) return DateTime.tryParse(v);
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      return null;
    }

    final date = parseDateNullable(veryfiJson['date']);
    final total = (veryfiJson['total'] as num?)?.toDouble() ??
        (veryfiJson['grand_total'] as num?)?.toDouble();

    final rawLines = (veryfiJson['line_items'] ??
            veryfiJson['lines'] ??
            veryfiJson['items']) as List? ??
        [];
    final parsedItems = <ParsedLineItem>[];
    final buffer = StringBuffer();

    for (final raw in rawLines) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);

      // DEBUG: Print raw map to analyze OCR parsing issues
      debugPrint('🔍 Veryfi Raw Line: $map');
      debugPrint(
          '   📊 Raw quantity type: ${map['quantity'].runtimeType}, value: ${map['quantity']}');
      debugPrint(
          '   📊 Raw unit_price type: ${map['unit_price'].runtimeType}, value: ${map['unit_price']}');
      debugPrint(
          '   📊 Raw total type: ${map['total'].runtimeType}, value: ${map['total']}');

      final desc =
          map['description']?.toString() ?? map['name']?.toString() ?? '';
      var qty = (map['quantity'] as num?)?.toDouble() ??
          (map['qty'] as num?)?.toDouble();
      var price = (map['unit_price'] as num?)?.toDouble() ??
          (map['price'] as num?)?.toDouble();

      // Get SKU from Veryfi, or try to extract from description if not detected
      var sku = map['sku']?.toString();
      final rawText = map['text']?.toString() ?? '';

      if (sku == null || sku.isEmpty) {
        sku = _extractSkuFromDescription(desc);

        // If still null, try extracting from raw text (start of line)
        // Useful when the line starts with the code but Veryfi missed it
        if (sku == null || sku.isEmpty) {
          sku = _extractSkuFromRawText(rawText);
          if (sku != null) {
            debugPrint('   💡 Extracted SKU from raw text: $sku');
          }
        }
      }
      var lineTotal = (map['total'] as num?)?.toDouble() ??
          (map['line_total'] as num?)?.toDouble();

      debugPrint('   ✅ Before fix: qty=$qty, price=$price, total=$lineTotal');

      // CHILEAN NUMBER FORMAT FIX:
      // Veryfi sometimes treats dots as decimal separators (US format)
      // In Chile, dots are thousand separators
      //
      // We use the raw 'text' field to verify if a fix is needed.
      // The text field contains the original OCR text like "$1.790\t6\t$10.740"
      // If the text shows a value like "$1.790" but Veryfi parsed it as 1.79,
      // we need to multiply by 1000.

      // Helper to check if raw text contains a value that looks like it should be 1000x larger
      // e.g., "$1.790" in text but parsed as 1.79
      bool shouldScale(double? parsed, String text) {
        if (parsed == null || parsed <= 0) return false;

        // Look for the value in text with a dot that would make it 1000x
        // e.g., parsed=1.79 should match "$1.790" or "1.790" in text
        final scaledValue = (parsed * 1000).round();

        // Check if the scaled value (with Chilean dot separator) appears in text
        // Format: "X.XXX" where XXX is three digits
        final formattedScaled = _formatWithDots(scaledValue);

        if (text.contains(formattedScaled) ||
            text.contains(scaledValue.toString())) {
          debugPrint('   🔍 Found scaled value $formattedScaled in raw text');
          return true;
        }
        return false;
      }

      // Check and fix quantity
      if (qty != null && qty < 1 && qty > 0) {
        final correctedQty = (qty * 1000).round();
        // Verify: does the raw text contain this corrected quantity as a whole number?
        if (rawText.contains('\t$correctedQty\t') ||
            rawText.contains('\t$correctedQty\n') ||
            rawText.endsWith('\t$correctedQty')) {
          debugPrint('   🔧 Chilean fix (verified): qty $qty → $correctedQty');
          qty = correctedQty.toDouble();
        }
      }

      // Check and fix price
      if (price != null && shouldScale(price, rawText)) {
        final correctedPrice = (price * 1000).round();
        debugPrint(
            '   🔧 Chilean fix (verified): price $price → $correctedPrice');
        price = correctedPrice.toDouble();
      }

      // Check and fix total
      if (lineTotal != null && shouldScale(lineTotal, rawText)) {
        final correctedTotal = (lineTotal * 1000).round();
        debugPrint(
            '   🔧 Chilean fix (verified): total $lineTotal → $correctedTotal');
        lineTotal = correctedTotal.toDouble();
      }

      debugPrint('   ✅ After fix: qty=$qty, price=$price, total=$lineTotal');

      // Extract discount fields
      double? discount = (map['discount'] as num?)?.toDouble();
      double? discountRate = (map['discount_rate'] as num?)?.toDouble();

      // Heuristic: Veryfi sometimes maps discount rate to 'tax' field
      // Check if we have a 'tax' value but no discount, and if the math supports it being a discount
      if (discount == null && discountRate == null && map['tax'] != null) {
        final potentialRate = (map['tax'] as num).toDouble();

        // Calculate expected total if this were a discount rate
        // total = (qty * price) * (1 - rate/100)
        final q = qty ?? 1.0;
        final p = price ?? 0.0;
        final t = lineTotal ?? 0.0;

        final subtotal = q * p;
        final expectedTotal = subtotal * (1 - (potentialRate / 100));

        // Allow for small rounding differences (1% tolerance)
        if (subtotal > 0 && (expectedTotal - t).abs() < (subtotal * 0.01)) {
          debugPrint(
              '💡 Heuristic: Mapped "tax" field ($potentialRate) to discount_rate');
          discountRate = potentialRate;
        }
      }

      parsedItems.add(ParsedLineItem(
        description: desc,
        sku: sku,
        quantity: qty,
        unitPrice: price,
        total: lineTotal,
        discount: discount,
        discountRate: discountRate,
      ));
    }

    // Raw text fallback: combine vendor, invoice number and lines for debugging
    buffer.writeln(supplierName ?? '');
    if (invoiceNumber != null) buffer.writeln('N°: $invoiceNumber');
    if (date != null) buffer.writeln('Fecha: ${date.toIso8601String()}');

    // Calculate corrected total from line items (more accurate than Veryfi's total)
    final correctedTotal =
        parsedItems.fold<double>(0.0, (sum, item) => sum + (item.total ?? 0.0));

    // Use corrected total if it's significantly larger than Veryfi's total
    // (indicates Veryfi divided by 1000 due to Chilean format)
    var finalTotal = total;
    if (total != null && correctedTotal > total * 100) {
      debugPrint('🔧 Chilean fix: invoice total $total → $correctedTotal');
      finalTotal = correctedTotal;
    }

    if (finalTotal != null) buffer.writeln('Total: $finalTotal');
    for (final it in parsedItems) {
      buffer.writeln(
          '${it.description} ${it.quantity ?? ''} x ${it.unitPrice ?? ''} = ${it.total ?? ''}');
    }

    return ParsedInvoice(
      rut: (veryfiJson['vendor_tax_number'] as String?) ??
          (veryfiJson['tax_number'] as String?),
      invoiceNumber: invoiceNumber,
      date: date,
      total: finalTotal,
      supplierName: supplierName,
      lineItems: parsedItems,
      rawText: buffer.toString(),
    );
  }
}
