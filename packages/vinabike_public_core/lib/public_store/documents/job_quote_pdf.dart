import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../modules/website/models/website_seo_settings_aliases.dart';
import '../../shared/utils/chilean_utils.dart';
import 'store_document_style.dart';

/// One line of the workshop quote: a service, a part or another charge, with
/// what the customer pays for it. Never its internal note nor its cost.
class JobQuotePdfLine {
  const JobQuotePdfLine({
    required this.kind,
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.total,
  });

  /// `service`, `part` or `other`.
  final String kind;
  final String name;
  final double quantity;
  final double unitPrice;
  final double total;

  String get kindLabel => switch (kind) {
    'service' => 'Servicio',
    'part' => 'Repuesto',
    _ => 'Otro',
  };

  /// `1`, `2`, `1,5`.
  String get quantityLabel {
    final whole = quantity == quantity.roundToDouble();
    return whole
        ? '${quantity.toInt()}'
        : quantity.toStringAsFixed(1).replaceAll('.', ',');
  }
}

/// The workshop quote as the customer gets it with the WhatsApp notice
/// «Presupuesto listo» (20261107130000): the projection
/// `job_quote_document_projection_internal`, which the HTML store reads with
/// the notice's one-time code (`workshop_notice_document_v1`). It is a quote:
/// it never claims to be a receipt or a tax document.
class JobQuotePdfInput {
  const JobQuotePdfInput({
    required this.storeName,
    required this.tagline,
    this.logoUrl,
    required this.legalName,
    required this.supportEmail,
    required this.supportPhone,
    required this.storeOrigin,
    required this.jobNumber,
    required this.customerName,
    required this.item,
    required this.issuedAt,
    required this.validUntil,
    required this.clientRequest,
    required this.diagnosis,
    required this.lines,
    required this.subtotal,
    required this.discount,
    required this.total,
  });

  /// Null when [value] is not a quote to draw (no number or no lines).
  static JobQuotePdfInput? fromProjection(Object? value) {
    if (value is! Map) return null;
    final number = _text(value['job_number']);
    final rawLines = value['lines'];
    if (number == null || rawLines is! List || rawLines.isEmpty) return null;
    final storefront = value['storefront'];
    String? identity(String key) {
      if (storefront is! Map || storefront['schemaVersion'] != 1) return null;
      return _text(storefront[key]);
    }

    final origin = WebsiteSeoSettingsAliases.normalizeHttpsOrigin(
      identity('storeUrl') ?? '',
    );
    final customer = value['customer'];
    final lines = [
      for (final line in rawLines.whereType<Map>())
        if (_text(line['name']) case final name?)
          JobQuotePdfLine(
            kind: _text(line['kind']) ?? 'other',
            name: name,
            quantity: _amount(line['quantity'], fallback: 1),
            unitPrice: _amount(line['unit_price']),
            total: _amount(line['total']),
          ),
    ];
    if (lines.isEmpty) return null;
    return JobQuotePdfInput(
      storeName: identity('displayName') ?? 'Tienda',
      tagline: identity('tagline'),
      logoUrl: identity('logoUrl'),
      legalName: identity('legalName'),
      supportEmail: identity('supportEmail'),
      supportPhone: identity('supportPhone'),
      storeOrigin: origin.isEmpty ? null : origin,
      jobNumber: number,
      customerName: customer is Map ? _text(customer['name']) : null,
      item: _text(value['item']),
      issuedAt: _date(value['issued_at']),
      validUntil: _date(value['valid_until']),
      clientRequest: _text(value['client_request']),
      diagnosis: _text(value['diagnosis']),
      lines: lines,
      subtotal: _amount(value['subtotal']),
      discount: _amount(value['discount']),
      total: _amount(value['total']),
    );
  }

  final String storeName;
  final String? tagline;

  /// The site's logo (`logoUrl` of the storefront identity), when it has
  /// one: [storeDocumentLogoSource] falls back to the bundled one.
  final String? logoUrl;
  final String? legalName;
  final String? supportEmail;
  final String? supportPhone;

  /// `https://vinabike.cl`, from the site's `store_url`; null when unset.
  final String? storeOrigin;
  final String jobNumber;
  final String? customerName;

  /// What was left: «Trek Marlin 7», «bicicleta» or the component.
  final String? item;
  final DateTime? issuedAt;
  final DateTime? validUntil;
  final String? clientRequest;
  final String? diagnosis;
  final List<JobQuotePdfLine> lines;
  final double subtotal;
  final double discount;
  final double total;

  /// What the customer sees in the chat: «Presupuesto PG-00671.pdf».
  String get fileName =>
      'Presupuesto ${jobNumber.replaceAll(RegExp(r'[^0-9A-Za-z-]'), '_')}.pdf';

  /// «Trek Marlin 7»; without a name, nothing (the job number says enough).
  String? get itemLabel {
    final value = item;
    if (value == null) return null;
    return value == 'bicicleta' || value == 'componente'
        ? null
        : value[0].toUpperCase() + value.substring(1);
  }

  /// How to approve it, in the words of the WhatsApp message it travels with.
  static const howToApprove =
      'Toca «Aprobar presupuesto» en el mensaje de WhatsApp o respóndenos por '
      'ahí. Empezamos apenas lo apruebes; si algo cambia al trabajar, te '
      'consultamos antes.';

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
}

String? _text(Object? raw) {
  final text = raw?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

DateTime? _date(Object? raw) => raw == null ? null : DateTime.tryParse('$raw');

double _amount(Object? raw, {double fallback = 0}) => raw is num
    ? raw.toDouble()
    : double.tryParse(raw?.toString() ?? '') ?? fallback;

/// Draws the workshop quote the customer gets by WhatsApp.
///
/// [regularFont] and [boldFont] are the store's Barlow faces (TrueType): the
/// app reads them from its bundle, the HTML store from Hosting. [logo] is the
/// store's logo ([storeDocumentLogoSource]); without it the letterhead writes
/// the name.
Future<Uint8List> buildJobQuotePdf(
  JobQuotePdfInput quote, {
  required ByteData regularFont,
  required ByteData boldFont,
  Uint8List? logo,
}) async {
  final logoImage = storeDocumentLogoImage(logo);
  final regular = pw.Font.ttf(regularFont);
  final bold = pw.Font.ttf(boldFont);
  final pdf = pw.Document(
    theme: pw.ThemeData.withFont(
      base: regular,
      bold: bold,
      italic: regular,
      boldItalic: bold,
    ),
    title: 'Presupuesto ${quote.jobNumber}',
    author: quote.storeName,
    subject: 'Presupuesto del taller',
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
                  storeDocumentWordmark(
                    quote.storeName,
                    null,
                    compact: true,
                    logo: logoImage,
                  ),
                  pw.Text(
                    quote.jobNumber,
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
                '${footerParty}Presupuesto: no es boleta ni factura.',
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
        _documentHeader(quote, logoImage),
        pw.SizedBox(height: 22),
        _infoStrip(quote),
        if (quote.clientRequest != null || quote.diagnosis != null) ...[
          pw.SizedBox(height: 20),
          _requestAndDiagnosis(quote),
        ],
        pw.SizedBox(height: 22),
        _sectionTitle('Detalle del presupuesto'),
        pw.SizedBox(height: 10),
        _linesTable(quote),
        pw.SizedBox(height: 14),
        _totalBlock(quote),
        pw.SizedBox(height: 22),
        _nextStep(quote),
      ],
    ),
  );

  return pdf.save();
}

pw.Widget _documentHeader(JobQuotePdfInput quote, pw.ImageProvider? logo) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Expanded(
        child: storeDocumentWordmark(
          quote.storeName,
          quote.tagline,
          logo: logo,
        ),
      ),
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
              'PRESUPUESTO DEL TALLER',
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
            quote.jobNumber,
            style: pw.TextStyle(
              color: storeDocumentInk,
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          if (quote.itemLabel != null) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              quote.itemLabel!,
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

/// Who it is for, when it was made and how long it holds.
pw.Widget _infoStrip(JobQuotePdfInput quote) {
  pw.Widget cell(String label, String value) => pw.Padding(
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
            color: storeDocumentInk,
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
    },
    border: pw.TableBorder.all(color: storeDocumentLine),
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: storeDocumentSoftSurface),
        children: [
          cell('Para', quote.customerName ?? 'Cliente'),
          cell(
            'Fecha',
            quote.issuedAt == null ? '—' : storeDocumentDate(quote.issuedAt!),
          ),
          cell(
            'Vale hasta',
            quote.validUntil == null
                ? '—'
                : storeDocumentDate(quote.validUntil!),
          ),
        ],
      ),
    ],
  );
}

pw.Widget _requestAndDiagnosis(JobQuotePdfInput quote) {
  pw.Widget block(String title, String text) => pw.Expanded(
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          title.toUpperCase(),
          style: const pw.TextStyle(
            color: storeDocumentMuted,
            fontSize: 7.5,
            letterSpacing: 0.5,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          text,
          style: const pw.TextStyle(
            color: storeDocumentInk,
            fontSize: 9.5,
            lineSpacing: 2,
          ),
        ),
      ],
    ),
  );
  final request = quote.clientRequest;
  final diagnosis = quote.diagnosis;
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      if (request != null) block('Lo que nos pediste', request),
      if (request != null && diagnosis != null) pw.SizedBox(width: 24),
      if (diagnosis != null) block('Lo que encontramos', diagnosis),
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

pw.Widget _linesTable(JobQuotePdfInput quote) {
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
      // Un presupuesto largo sigue en otra página: la cabecera se repite.
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(color: storeDocumentBrand),
        children: [
          _tableHeader('Trabajo o repuesto'),
          _tableHeader('Precio', alignRight: true),
          _tableHeader('Cant.', alignRight: true),
          _tableHeader('Total', alignRight: true),
        ],
      ),
      for (final line in quote.lines)
        pw.TableRow(
          verticalAlignment: pw.TableCellVerticalAlignment.top,
          children: [
            _lineCell(line),
            _tableValue(
              ChileanUtils.formatCurrency(line.unitPrice),
              alignRight: true,
            ),
            _tableValue(line.quantityLabel, alignRight: true),
            _tableValue(
              ChileanUtils.formatCurrency(line.total),
              alignRight: true,
              bold: true,
            ),
          ],
        ),
    ],
  );
}

pw.Widget _lineCell(JobQuotePdfLine line) {
  final (ink, surface) = switch (line.kind) {
    'service' => (storeDocumentBrand, storeDocumentSoftSurface),
    'part' => (storeDocumentPositive, storeDocumentPositiveSurface),
    _ => (storeDocumentMuted, storeDocumentSoftSurface),
  };
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          line.name,
          style: pw.TextStyle(
            color: storeDocumentInk,
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
          decoration: pw.BoxDecoration(
            color: surface,
            borderRadius: pw.BorderRadius.circular(2),
          ),
          child: pw.Text(
            line.kindLabel,
            style: pw.TextStyle(
              color: ink,
              fontSize: 7.5,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
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
}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    child: pw.Text(
      text,
      textAlign: alignRight ? pw.TextAlign.right : pw.TextAlign.left,
      style: pw.TextStyle(
        color: storeDocumentInk,
        fontSize: 9,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );
}

pw.Widget _totalBlock(JobQuotePdfInput quote) {
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
            if (quote.discount > 0) ...[
              _totalRow(
                'Subtotal',
                ChileanUtils.formatCurrency(quote.subtotal),
              ),
              _totalRow(
                'Descuento',
                '-${ChileanUtils.formatCurrency(quote.discount)}',
              ),
            ],
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'TOTAL',
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

pw.Widget _nextStep(JobQuotePdfInput quote) {
  final contact = quote.contactLine;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'Cómo aprobarlo',
        style: pw.TextStyle(
          color: storeDocumentInk,
          fontSize: 12,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
      pw.SizedBox(height: 5),
      pw.Text(
        JobQuotePdfInput.howToApprove,
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
