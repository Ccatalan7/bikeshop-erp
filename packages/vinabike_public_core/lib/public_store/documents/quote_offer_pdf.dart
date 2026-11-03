import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../modules/website/models/website_seo_settings_aliases.dart';
import '../../shared/utils/chilean_utils.dart';
import 'store_document_style.dart';

/// One line of the offer, as the customer's quote page draws it.
class QuoteOfferPdfLine {
  const QuoteOfferPdfLine({
    required this.name,
    required this.sku,
    required this.quantity,
    required this.quantityRequested,
    required this.availability,
    required this.unitPrice,
    required this.lineTotal,
    required this.leadDaysMin,
    required this.leadDaysMax,
    required this.note,
  });

  final String name;
  final String? sku;

  /// What the shop offers; 0 when it could not get it.
  final int quantity;
  final int quantityRequested;

  /// `in_stock`, `on_order`, `unavailable` (`pending` never leaves a draft).
  final String availability;
  final double? unitPrice;
  final double? lineTotal;
  final int? leadDaysMin;
  final int? leadDaysMax;
  final String? note;

  bool get isOffered => quantity > 0 && availability != 'unavailable';
  bool get isOnOrder => isOffered && availability == 'on_order';

  /// «En stock», «A pedido · llega en 3 a 5 días hábiles», «No disponible»,
  /// with «2 de 3» when only part of it is offered: the page's words.
  String get availabilityLabel {
    final base = switch (availability) {
      'in_stock' => 'En stock',
      'on_order' => 'A pedido',
      'unavailable' => 'No disponible',
      _ => 'Por confirmar',
    };
    final partial = quantity > 0 && quantity < quantityRequested
        ? ' · $quantity de $quantityRequested'
        : '';
    final min = leadDaysMin;
    final max = leadDaysMax;
    final lead = availability == 'on_order' && min != null
        ? ' · llega en ${max == null || max == min ? '$min' : '$min a $max'} '
              'días hábiles'
        : '';
    return '$base$partial$lead';
  }
}

/// The offer as the customer sees it, with the store's letterhead: the
/// public projection of the quote (`customer_quote_public_projection_internal`),
/// which the HTML store reads with the quote's link and the ERP with
/// `customer_quote_offer_document_v1`. Both draw this same document.
class QuoteOfferPdfInput {
  const QuoteOfferPdfInput({
    required this.storeName,
    required this.tagline,
    required this.legalName,
    required this.supportEmail,
    required this.supportPhone,
    required this.storeOrigin,
    required this.quoteNumber,
    required this.offerNumber,
    required this.quoteStatus,
    required this.offerStatus,
    required this.customerName,
    required this.sentAt,
    required this.validUntil,
    required this.acceptedAt,
    required this.rejectedAt,
    required this.expiredAt,
    required this.lines,
    required this.subtotal,
    required this.taxAmount,
    required this.total,
    required this.notes,
  });

  /// Null when the answer has no sent offer to draw (a draft, another
  /// answer, nothing).
  static QuoteOfferPdfInput? fromPublicQuote(Object? value) {
    if (value is! Map) return null;
    final quote = value['quote'];
    final offer = value['offer'];
    if (quote is! Map || offer is! Map) return null;
    final rawLines = offer['lines'];
    final number = _text(quote['number']);
    if (rawLines is! List || rawLines.isEmpty || number == null) return null;
    final storefront = value['storefront'];
    String? identity(String key) {
      if (storefront is! Map || storefront['schemaVersion'] != 1) return null;
      return _text(storefront[key]);
    }

    final origin = WebsiteSeoSettingsAliases.normalizeHttpsOrigin(
      identity('storeUrl') ?? '',
    );
    return QuoteOfferPdfInput(
      storeName: identity('displayName') ?? 'Tienda',
      tagline: identity('tagline'),
      legalName: identity('legalName'),
      supportEmail: identity('supportEmail'),
      supportPhone: identity('supportPhone'),
      storeOrigin: origin.isEmpty ? null : origin,
      quoteNumber: number,
      offerNumber: (offer['number'] as num?)?.toInt() ?? 1,
      quoteStatus: _text(quote['status']) ?? 'offered',
      offerStatus: _text(offer['status']) ?? 'sent',
      customerName: _text(quote['customerName']),
      sentAt: _date(offer['sentAt']),
      validUntil: _date(offer['validUntil']) ?? _date(quote['expiresAt']),
      acceptedAt: _date(quote['acceptedAt']),
      rejectedAt: _date(quote['rejectedAt']),
      expiredAt: _date(quote['expiredAt']),
      lines: [
        for (final line in rawLines.whereType<Map>())
          QuoteOfferPdfLine(
            name: _text(line['name']) ?? 'Producto',
            sku: _text(line['sku']),
            quantity: (line['quantity'] as num?)?.toInt() ?? 0,
            quantityRequested:
                (line['quantityRequested'] as num?)?.toInt() ??
                (line['quantity'] as num?)?.toInt() ??
                0,
            availability: _text(line['availability']) ?? 'pending',
            unitPrice: (line['unitPrice'] as num?)?.toDouble(),
            lineTotal: (line['lineTotal'] as num?)?.toDouble(),
            leadDaysMin: (line['leadDaysMin'] as num?)?.toInt(),
            leadDaysMax: (line['leadDaysMax'] as num?)?.toInt(),
            note: _text(line['note']),
          ),
      ],
      subtotal: _amount(offer['subtotal']),
      taxAmount: _amount(offer['taxAmount']),
      total: _amount(offer['total']),
      notes: _text(offer['notes']),
    );
  }

  final String storeName;
  final String? tagline;
  final String? legalName;
  final String? supportEmail;
  final String? supportPhone;

  /// `https://vinabike.cl`, from the site's `store_url`; null when unset.
  final String? storeOrigin;
  final String quoteNumber;
  final int offerNumber;
  final String quoteStatus;
  final String offerStatus;
  final String? customerName;
  final DateTime? sentAt;
  final DateTime? validUntil;
  final DateTime? acceptedAt;
  final DateTime? rejectedAt;
  final DateTime? expiredAt;
  final List<QuoteOfferPdfLine> lines;
  final double subtotal;
  final double taxAmount;
  final double total;
  final String? notes;

  /// The file name both sides offer.
  String get fileName =>
      'cotizacion_${quoteNumber.replaceAll(RegExp(r'[^0-9A-Za-z-]'), '_')}.pdf';

  /// The customer asked for changes and the shop prepares a new offer: this
  /// one is the previous one.
  bool get isPrevious =>
      offerStatus == 'superseded' && quoteStatus == 'confirming';

  bool get hasOnOrder => lines.any((line) => line.isOnOrder);

  String get statusLabel => isPrevious
      ? 'Oferta anterior'
      : switch (quoteStatus) {
          'offered' => 'Vigente',
          'accepted' => 'Aceptada',
          'rejected' => 'Rechazada',
          'expired' => 'Vencida',
          'cancelled' => 'Anulada',
          _ => 'En revisión',
        };

  String? get storeHost {
    final origin = storeOrigin;
    if (origin == null) return null;
    final host = Uri.parse(origin).host;
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  /// What comes next, in one or two sentences: how to accept a valid
  /// offer, or what happened to it.
  String get nextStep {
    final where = storeHost == null
        ? 'en la tienda, en Mi cuenta › Cotizaciones'
        : 'en $storeHost › Mi cuenta › Cotizaciones';
    if (isPrevious) {
      return 'Esta es la oferta anterior: estamos preparando una nueva con '
          'tus cambios y te avisamos cuando esté lista.';
    }
    return switch (quoteStatus) {
      'offered' =>
        'Ábrela con el enlace que te mandamos o $where y toca «Aceptar '
            'oferta»: eliges retiro o despacho y pagas.'
            '${hasOnOrder ? ' Lo que viene a pedido lo pedimos al tiro y te avisamos cuando llegue.' : ''}',
      'accepted' =>
        'Aceptaste esta oferta${_on(acceptedAt)}. Sigue tu pedido con el '
            'enlace de la cotización o $where.',
      'expired' =>
        'Esta oferta venció${_on(expiredAt ?? validUntil)}. Escríbenos y '
            'la renovamos.',
      'rejected' => 'Rechazaste esta oferta${_on(rejectedAt)}.',
      'cancelled' => 'Esta cotización se anuló.',
      _ => 'Estamos revisando tu cotización y te avisamos cuando esté lista.',
    };
  }

  /// «¿Dudas? Escríbenos a … o al …», with what the store publishes.
  String? get contactLine {
    final email = supportEmail;
    final phone = supportPhone;
    if (email == null && phone == null) return null;
    final ways = [
      if (email != null) 'a $email',
      if (phone != null) 'al $phone',
    ].join(' o ');
    return '¿Dudas? Escríbenos $ways.';
  }

  static String _on(DateTime? at) =>
      at == null ? '' : ' el ${storeDocumentDate(at)}';
}

String? _text(Object? raw) {
  final text = raw?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

DateTime? _date(Object? raw) => raw == null ? null : DateTime.tryParse('$raw');

double _amount(Object? raw) => raw is num ? raw.toDouble() : 0.0;

/// Draws the offer the customer keeps or the shop sends by WhatsApp. It is a
/// quote: it never claims to be a receipt or a tax document.
///
/// [regularFont] and [boldFont] are the store's Barlow faces (TrueType): the
/// app reads them from its bundle, the HTML store from Hosting.
Future<Uint8List> buildQuoteOfferPdf(
  QuoteOfferPdfInput quote, {
  required ByteData regularFont,
  required ByteData boldFont,
}) async {
  final regular = pw.Font.ttf(regularFont);
  final bold = pw.Font.ttf(boldFont);
  final pdf = pw.Document(
    theme: pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      italic: regular,
      boldItalic: bold,
    ),
    title: 'Cotización ${quote.quoteNumber}',
    author: quote.storeName,
    subject: 'Oferta de cotización',
  );
  final legal = quote.legalName;
  final footerParty =
      legal != null && legal.toLowerCase() != quote.storeName.toLowerCase()
      ? '${quote.storeName} · $legal · '
      : '${quote.storeName} · ';

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(42, 38, 42, 34),
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox()
          : pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 10),
              margin: const pw.EdgeInsets.only(bottom: 18),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(color: storeDocumentLine),
                ),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  storeDocumentWordmark(quote.storeName, null, compact: true),
                  pw.Text(
                    quote.quoteNumber,
                    style: const pw.TextStyle(
                      color: storeDocumentMuted,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
      footer: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 10),
        margin: const pw.EdgeInsets.only(top: 18),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: storeDocumentLine)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(
                '${footerParty}Cotización: no es boleta ni factura.',
                style: const pw.TextStyle(
                  color: storeDocumentMuted,
                  fontSize: 8,
                ),
              ),
            ),
            pw.SizedBox(width: 16),
            pw.Text(
              'Página ${context.pageNumber} de ${context.pagesCount}',
              style: const pw.TextStyle(color: storeDocumentMuted, fontSize: 8),
            ),
          ],
        ),
      ),
      build: (context) => [
        _documentHeader(quote),
        pw.SizedBox(height: 22),
        _infoStrip(quote),
        pw.SizedBox(height: 24),
        _sectionTitle('Detalle de la oferta'),
        pw.SizedBox(height: 10),
        _linesTable(quote),
        pw.SizedBox(height: 6),
        pw.Text(
          'Precios con IVA incluido. No incluye despacho.',
          style: const pw.TextStyle(color: storeDocumentMuted, fontSize: 8),
        ),
        pw.SizedBox(height: 14),
        _totalBlock(quote),
        if (quote.notes != null) ...[
          pw.SizedBox(height: 20),
          _storeNote(quote),
        ],
        pw.SizedBox(height: 22),
        _nextStep(quote),
      ],
    ),
  );

  return pdf.save();
}

pw.Widget _documentHeader(QuoteOfferPdfInput quote) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Expanded(child: storeDocumentWordmark(quote.storeName, quote.tagline)),
      pw.SizedBox(width: 24),
      pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: pw.BoxDecoration(
              color: storeDocumentSoftSurface,
              borderRadius: pw.BorderRadius.circular(2),
            ),
            child: pw.Text(
              'COTIZACIÓN',
              style: pw.TextStyle(
                color: storeDocumentBrand,
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.6,
              ),
            ),
          ),
          pw.SizedBox(height: 9),
          pw.Text(
            quote.quoteNumber,
            style: pw.TextStyle(
              color: storeDocumentInk,
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (quote.offerNumber > 1) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              'Oferta ${quote.offerNumber}',
              style: pw.TextStyle(
                color: storeDocumentBrand,
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    ],
  );
}

/// Who it is for, where it stands and how long it holds: one box in four.
pw.Widget _infoStrip(QuoteOfferPdfInput quote) {
  final statusColor = switch (quote.statusLabel) {
    'Vigente' || 'Aceptada' => storeDocumentPositive,
    'Vencida' || 'Oferta anterior' => storeDocumentWarning,
    _ => storeDocumentInk,
  };
  pw.Widget cell(String label, String value, {PdfColor? color}) => pw.Padding(
    padding: const pw.EdgeInsets.fromLTRB(12, 9, 12, 10),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label.toUpperCase(),
          style: const pw.TextStyle(
            color: storeDocumentMuted,
            fontSize: 7.5,
            letterSpacing: 0.5,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          value,
          style: pw.TextStyle(
            color: color ?? storeDocumentInk,
            fontSize: 10.5,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ],
    ),
  );
  return pw.Table(
    columnWidths: const {
      0: pw.FlexColumnWidth(1.6),
      1: pw.FlexColumnWidth(1),
      2: pw.FlexColumnWidth(1),
      3: pw.FlexColumnWidth(1),
    },
    border: pw.TableBorder.all(color: storeDocumentLine),
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: storeDocumentSoftSurface),
        children: [
          cell('Para', quote.customerName ?? 'Cliente'),
          cell('Estado', quote.statusLabel, color: statusColor),
          cell(
            'Enviada',
            quote.sentAt == null ? '—' : storeDocumentDate(quote.sentAt!),
          ),
          // The validity ends at an hour (sending plus the shop's hours),
          // as the quote page says it.
          cell(
            quote.quoteStatus == 'expired' ? 'Venció' : 'Vale hasta',
            quote.validUntil == null
                ? '—'
                : storeDocumentDateTime(quote.validUntil!),
          ),
        ],
      ),
    ],
  );
}

pw.Widget _sectionTitle(String text) {
  return pw.Text(
    text,
    style: pw.TextStyle(
      color: storeDocumentInk,
      fontSize: 12,
      fontWeight: pw.FontWeight.bold,
    ),
  );
}

pw.Widget _linesTable(QuoteOfferPdfInput quote) {
  return pw.Table(
    columnWidths: const {
      0: pw.FlexColumnWidth(4.6),
      1: pw.FlexColumnWidth(1.5),
      2: pw.FlexColumnWidth(0.8),
      3: pw.FlexColumnWidth(1.6),
    },
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(color: storeDocumentLine),
      bottom: pw.BorderSide(color: storeDocumentLine),
    ),
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: storeDocumentBrand),
        children: [
          _tableHeader('Producto'),
          _tableHeader('Precio', alignRight: true),
          _tableHeader('Cant.', alignRight: true),
          _tableHeader('Total', alignRight: true),
        ],
      ),
      for (final line in quote.lines)
        pw.TableRow(
          verticalAlignment: pw.TableCellVerticalAlignment.top,
          children: [
            _productCell(line),
            _tableValue(
              line.isOffered && line.unitPrice != null
                  ? ChileanUtils.formatCurrency(line.unitPrice!)
                  : '—',
              alignRight: true,
              muted: !line.isOffered,
            ),
            _tableValue(
              line.isOffered ? '${line.quantity}' : '—',
              alignRight: true,
              muted: !line.isOffered,
            ),
            _tableValue(
              line.isOffered && line.lineTotal != null
                  ? ChileanUtils.formatCurrency(line.lineTotal!)
                  : '—',
              alignRight: true,
              bold: line.isOffered,
              muted: !line.isOffered,
            ),
          ],
        ),
    ],
  );
}

pw.Widget _productCell(QuoteOfferPdfLine line) {
  final (ink, surface) = switch (line.availability) {
    'in_stock' when line.isOffered => (
      storeDocumentPositive,
      storeDocumentPositiveSurface,
    ),
    'on_order' when line.isOffered => (
      storeDocumentWarning,
      storeDocumentWarningSurface,
    ),
    _ => (storeDocumentMuted, storeDocumentSoftSurface),
  };
  final note = line.note;
  final sku = line.sku;
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          line.name,
          style: pw.TextStyle(
            color: line.isOffered ? storeDocumentInk : storeDocumentMuted,
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        if (sku != null) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            'SKU $sku',
            style: const pw.TextStyle(color: storeDocumentMuted, fontSize: 7.5),
          ),
        ],
        pw.SizedBox(height: 5),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
          decoration: pw.BoxDecoration(
            color: surface,
            borderRadius: pw.BorderRadius.circular(2),
          ),
          child: pw.Text(
            line.availabilityLabel,
            style: pw.TextStyle(
              color: ink,
              fontSize: 7.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
        if (note != null) ...[
          pw.SizedBox(height: 5),
          pw.Text(
            note,
            style: const pw.TextStyle(
              color: storeDocumentInk,
              fontSize: 8.5,
              lineSpacing: 1.5,
            ),
          ),
        ],
      ],
    ),
  );
}

pw.Widget _tableHeader(String text, {bool alignRight = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 9),
    child: pw.Text(
      text,
      textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      style: pw.TextStyle(
        color: PdfColors.white,
        fontSize: 8.5,
        fontWeight: pw.FontWeight.bold,
      ),
    ),
  );
}

pw.Widget _tableValue(
  String text, {
  bool alignRight = false,
  bool bold = false,
  bool muted = false,
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    child: pw.Text(
      text,
      textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      style: pw.TextStyle(
        color: muted ? storeDocumentMuted : storeDocumentInk,
        fontSize: 9,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}

pw.Widget _totalBlock(QuoteOfferPdfInput quote) {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.end,
    children: [
      pw.Container(
        width: 235,
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(
          color: storeDocumentSoftSurface,
          border: pw.Border.all(color: storeDocumentLine),
          borderRadius: pw.BorderRadius.circular(2),
        ),
        child: pw.Column(
          children: [
            _totalRow('Neto', ChileanUtils.formatCurrency(quote.subtotal)),
            _totalRow('IVA', ChileanUtils.formatCurrency(quote.taxAmount)),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'TOTAL DE LA OFERTA',
                  style: pw.TextStyle(
                    color: storeDocumentInk,
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  ChileanUtils.formatCurrency(quote.total),
                  style: pw.TextStyle(
                    color: storeDocumentBrand,
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

pw.Widget _totalRow(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 8),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: const pw.TextStyle(color: storeDocumentMuted, fontSize: 9),
        ),
        pw.Text(
          value,
          style: const pw.TextStyle(color: storeDocumentInk, fontSize: 9),
        ),
      ],
    ),
  );
}

pw.Widget _storeNote(QuoteOfferPdfInput quote) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(14),
    decoration: const pw.BoxDecoration(
      color: storeDocumentSoftSurface,
      border: pw.Border(
        left: pw.BorderSide(color: storeDocumentBrand, width: 3),
      ),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Nota de ${quote.storeName}',
          style: pw.TextStyle(
            color: storeDocumentBrand,
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          quote.notes!,
          style: const pw.TextStyle(
            color: storeDocumentInk,
            fontSize: 9.5,
            lineSpacing: 2,
          ),
        ),
      ],
    ),
  );
}

pw.Widget _nextStep(QuoteOfferPdfInput quote) {
  final contact = quote.contactLine;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        quote.quoteStatus == 'offered' && !quote.isPrevious
            ? 'Cómo aceptarla'
            : 'Lo que pasó con esta oferta',
        style: pw.TextStyle(
          color: storeDocumentInk,
          fontSize: 12,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
      pw.SizedBox(height: 5),
      pw.Text(
        quote.nextStep,
        style: const pw.TextStyle(
          color: storeDocumentInk,
          fontSize: 10,
          lineSpacing: 2,
        ),
      ),
      if (contact != null) ...[
        pw.SizedBox(height: 6),
        pw.Text(
          contact,
          style: const pw.TextStyle(
            color: storeDocumentMuted,
            fontSize: 9.5,
            lineSpacing: 2,
          ),
        ),
      ],
    ],
  );
}
