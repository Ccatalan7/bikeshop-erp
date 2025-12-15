import '../../modules/sales/models/sales_models.dart';
import '../../shared/models/tax_treatment.dart';
import 'package:flutter/foundation.dart';
import '../services/invoice_parser_service.dart';

/// Adapter to convert Veryfi response JSON into our internal `Invoice` model.
class VeryfiAdapter {
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

      // DEBUG: Print raw map to find discount keys
      debugPrint('🔍 Veryfi Raw Line: $map');

      final desc =
          map['description']?.toString() ?? map['name']?.toString() ?? '';
      final qty = (map['quantity'] as num?)?.toDouble() ??
          (map['qty'] as num?)?.toDouble();
      final price = (map['unit_price'] as num?)?.toDouble() ??
          (map['price'] as num?)?.toDouble();
      final sku = map['sku']?.toString();
      final lineTotal = (map['total'] as num?)?.toDouble() ??
          (map['line_total'] as num?)?.toDouble();

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
    if (total != null) buffer.writeln('Total: $total');
    for (final it in parsedItems) {
      buffer.writeln(
          '${it.description} ${it.quantity ?? ''} x ${it.unitPrice ?? ''} = ${it.total ?? ''}');
    }

    return ParsedInvoice(
      rut: (veryfiJson['vendor_tax_number'] as String?) ??
          (veryfiJson['tax_number'] as String?),
      invoiceNumber: invoiceNumber,
      date: date,
      total: total,
      supplierName: supplierName,
      lineItems: parsedItems,
      rawText: buffer.toString(),
    );
  }
}
