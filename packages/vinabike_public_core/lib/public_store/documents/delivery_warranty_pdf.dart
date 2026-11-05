import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../modules/website/models/website_seo_settings_aliases.dart';
import 'store_document_style.dart';

/// Where the QR of a reception or a delivery takes the customer: the store's
/// page that links a new or existing account to the shop's customer record
/// (`claim_customer_portal_code_v1`, 20261104200000).
///
/// The code travels in the fragment, never in the path or the query: a
/// fragment is not sent to the server, so it stays out of request logs and
/// out of the page address Analytics records.
const customerPortalClaimPath = '/cuenta/vincular';

String customerPortalClaimUrl(String storeOrigin, String code) {
  final origin = WebsiteSeoSettingsAliases.normalizeHttpsOrigin(storeOrigin);
  return '$origin$customerPortalClaimPath#c=${Uri.encodeComponent(code)}';
}

/// One line of the job as the document lists it: what was done (a service or
/// another charge) or a part that was installed. Never a price: the price is
/// on the invoice.
class DeliveryWarrantyPdfLine {
  const DeliveryWarrantyPdfLine({
    required this.kind,
    required this.name,
    required this.quantity,
    this.jobBikeId,
  });

  /// `service`, `part` or `other`.
  final String kind;
  final String name;
  final double quantity;
  final String? jobBikeId;

  bool get isPart => kind == 'part';

  /// `× 2` for more than one; nothing for one.
  String? get quantityLabel {
    if (quantity <= 1) return null;
    final whole = quantity == quantity.roundToDouble();
    return '× ${whole ? quantity.toInt() : quantity.toStringAsFixed(1)}';
  }
}

/// A bike of the job, as it left the shop.
class DeliveryWarrantyPdfBike {
  const DeliveryWarrantyPdfBike({
    required this.jobBikeId,
    required this.brand,
    required this.model,
    required this.year,
    required this.color,
    required this.serialNumber,
    required this.workRequested,
    required this.workPerformed,
  });

  final String? jobBikeId;
  final String? brand;
  final String? model;
  final int? year;
  final String? color;
  final String? serialNumber;
  final String? workRequested;
  final String? workPerformed;

  /// «Trek Marlin 7 2022».
  String get title {
    final parts = [?brand, ?model, if (year != null) '$year'];
    return parts.isEmpty ? 'Bicicleta' : parts.join(' ');
  }

  /// «Negra · N° de serie WTU123».
  String? get detail {
    final parts = [
      ?color,
      if (serialNumber != null) 'N° de serie $serialNumber',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// The delivery and warranty document, as the customer keeps it: the
/// projection of `mechanic_job_delivery_documents`
/// (`job_delivery_document_projection_internal`), which the ERP reads with
/// `ensure_job_delivery_document_v1` and the customer's account with
/// `list_my_job_delivery_documents_v1`. Both draw this same document.
class DeliveryWarrantyPdfInput {
  const DeliveryWarrantyPdfInput({
    required this.storeName,
    required this.tagline,
    this.logoUrl,
    required this.legalName,
    required this.supportEmail,
    required this.supportPhone,
    required this.storeOrigin,
    required this.jobNumber,
    required this.customerName,
    required this.deliveredAt,
    required this.serviceWarrantyDays,
    required this.serviceWarrantyExpiresAt,
    required this.partsWarrantyMonths,
    required this.partsWarrantyExpiresAt,
    required this.clientRequest,
    required this.diagnosis,
    required this.workPerformed,
    required this.subjectNotes,
    required this.bikes,
    required this.lines,
    required this.claimUrl,
    required this.hasAccount,
  });

  /// Null when [value] is not a document (no number, no delivery date, no
  /// warranty).
  ///
  /// [claimUrl] is the QR to create the account; pass it only when the
  /// customer has none. [hasAccount] says the document is already in their
  /// account.
  static DeliveryWarrantyPdfInput? fromProjection(
    Object? value, {
    String? claimUrl,
    bool hasAccount = false,
  }) {
    if (value is! Map) return null;
    final snapshot = value['snapshot'] is Map
        ? value['snapshot'] as Map
        : const <String, Object?>{};
    final number = _text(value['job_number']) ?? _text(snapshot['job_number']);
    final deliveredAt = _date(value['delivered_at']);
    final serviceExpires = _date(value['service_warranty_expires_at']);
    final partsExpires = _date(value['parts_warranty_expires_at']);
    if (number == null ||
        deliveredAt == null ||
        serviceExpires == null ||
        partsExpires == null) {
      return null;
    }
    final storefront = value['storefront'];
    String? identity(String key) {
      if (storefront is! Map || storefront['schemaVersion'] != 1) return null;
      return _text(storefront[key]);
    }

    final origin = WebsiteSeoSettingsAliases.normalizeHttpsOrigin(
      identity('storeUrl') ?? '',
    );
    final customer = snapshot['customer'];
    return DeliveryWarrantyPdfInput(
      storeName: identity('displayName') ?? 'Tienda',
      tagline: identity('tagline'),
      logoUrl: identity('logoUrl'),
      legalName: identity('legalName'),
      supportEmail: identity('supportEmail'),
      supportPhone: identity('supportPhone'),
      storeOrigin: origin.isEmpty ? null : origin,
      jobNumber: number,
      customerName: customer is Map ? _text(customer['name']) : null,
      deliveredAt: deliveredAt,
      serviceWarrantyDays:
          (value['service_warranty_days'] as num?)?.toInt() ?? 0,
      serviceWarrantyExpiresAt: serviceExpires,
      partsWarrantyMonths:
          (value['parts_warranty_months'] as num?)?.toInt() ?? 0,
      partsWarrantyExpiresAt: partsExpires,
      clientRequest: _text(snapshot['client_request']),
      diagnosis: _text(snapshot['diagnosis']),
      workPerformed: _text(snapshot['work_performed']),
      subjectNotes: _text(snapshot['subject_notes']),
      bikes: [
        for (final bike
            in (snapshot['bikes'] as List? ?? const []).whereType<Map>())
          DeliveryWarrantyPdfBike(
            jobBikeId: _text(bike['job_bike_id']),
            brand: _text(bike['brand']),
            model: _text(bike['model']),
            year: (bike['year'] as num?)?.toInt(),
            color: _text(bike['color']),
            serialNumber: _text(bike['serial_number']),
            workRequested: _text(bike['work_requested']),
            workPerformed: _text(bike['work_performed']),
          ),
      ],
      lines: [
        for (final line
            in (snapshot['lines'] as List? ?? const []).whereType<Map>())
          if (_text(line['name']) case final name?)
            DeliveryWarrantyPdfLine(
              kind: _text(line['kind']) ?? 'other',
              name: name,
              quantity: (line['quantity'] as num?)?.toDouble() ?? 1,
              jobBikeId: _text(line['job_bike_id']),
            ),
      ],
      claimUrl: _text(claimUrl),
      hasAccount: hasAccount,
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
  final DateTime deliveredAt;
  final int serviceWarrantyDays;

  /// The current end of the service warranty: an extension moves it.
  final DateTime serviceWarrantyExpiresAt;
  final int partsWarrantyMonths;
  final DateTime partsWarrantyExpiresAt;
  final String? clientRequest;
  final String? diagnosis;
  final String? workPerformed;

  /// What was serviced when it is a part, not a bike («Rueda trasera 26»).
  final String? subjectNotes;
  final List<DeliveryWarrantyPdfBike> bikes;
  final List<DeliveryWarrantyPdfLine> lines;
  final String? claimUrl;
  final bool hasAccount;

  /// The file name both sides offer.
  String get fileName =>
      'comprobante_entrega_${jobNumber.replaceAll(RegExp(r'[^0-9A-Za-z-]'), '_')}.pdf';

  String? get storeHost {
    final origin = storeOrigin;
    if (origin == null) return null;
    final host = Uri.parse(origin).host;
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  /// «14 días», «1 mes», «2 meses»; «Sin garantía» for zero.
  String get serviceWarrantyLabel => serviceWarrantyDays <= 0
      ? 'Sin garantía'
      : serviceWarrantyDays == 1
      ? '1 día'
      : '$serviceWarrantyDays días';

  String get partsWarrantyLabel => partsWarrantyMonths <= 0
      ? 'Sin garantía'
      : partsWarrantyMonths == 1
      ? '1 mes'
      : '$partsWarrantyMonths meses';

  bool get hasParts => lines.any((line) => line.isPart);

  /// A job that installed no parts gives no parts warranty: the document, the
  /// ERP and the portal leave it out instead of promising one for nothing.
  bool get showsPartsWarranty => hasParts;

  /// What the customer asked for: the job's request, or each bike's when the
  /// job has several.
  String? get requestSummary {
    if (clientRequest != null) return clientRequest;
    final perBike = [
      for (final bike in bikes)
        if (bike.workRequested != null) bike.workRequested!,
    ];
    return perBike.isEmpty ? null : perBike.join(' · ');
  }

  /// What the warranty covers and how to use it: three short lines in the
  /// store's voice — a modern brand, neither an app nor a notary
  /// (owner, 2026-11-04).
  List<String> get instructions => [
    showsPartsWarranty
        ? 'Cubre la mano de obra y los repuestos instalados en este servicio.'
        : 'Cubre la mano de obra de este servicio.',
    'No cubre golpes, caídas, mal uso, desgaste normal ni intervenciones de '
        'terceros.',
    'Para hacerla válida, muestra este comprobante en el taller, impreso o en '
        'tu teléfono.',
  ];

  static const legalLine = 'Sin perjuicio de la garantía legal (Ley 19.496).';

  /// The closing line, with the store's name.
  String get thanksLine => 'Gracias por confiar en $storeName.';

  /// Where the customer finds it again.
  String get accountLine => storeHost == null
      ? 'Este comprobante también está en tu cuenta.'
      : 'Este comprobante también está en tu cuenta en $storeHost.';

  static const claimTitle = 'Crea tu cuenta';

  static const claimBody =
      'Escanea el código para revisar tus servicios, garantías y facturas.';

  /// «contacto@… · +56 9 …», with what the store publishes.
  String? get contactLine {
    final ways = [?supportEmail, ?supportPhone];
    return ways.isEmpty ? null : ways.join(' · ');
  }

  /// The lines grouped by bike when the job has more than one; one group
  /// otherwise. A line without a bike goes to the last group, untitled.
  List<({DeliveryWarrantyPdfBike? bike, List<DeliveryWarrantyPdfLine> lines})>
  get groups {
    if (bikes.length <= 1) {
      return [(bike: bikes.isEmpty ? null : bikes.first, lines: lines)];
    }
    final grouped = [
      for (final bike in bikes)
        (
          bike: bike,
          lines: [
            for (final line in lines)
              if (line.jobBikeId != null && line.jobBikeId == bike.jobBikeId)
                line,
          ],
        ),
    ];
    final known = {for (final bike in bikes) bike.jobBikeId};
    final loose = [
      for (final line in lines)
        if (line.jobBikeId == null || !known.contains(line.jobBikeId)) line,
    ];
    return [...grouped, if (loose.isNotEmpty) (bike: null, lines: loose)];
  }
}

String? _text(Object? raw) {
  final text = raw?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

DateTime? _date(Object? raw) => raw == null ? null : DateTime.tryParse('$raw');

/// Draws the delivery and warranty document the customer keeps. It is not a
/// receipt or a tax document: the invoice is.
///
/// [regularFont] and [boldFont] are the store's Barlow faces (TrueType): the
/// app reads them from its bundle, the HTML store from Hosting. [logo] is the
/// store's logo ([storeDocumentLogoSource]); without it the letterhead writes
/// the name.
Future<Uint8List> buildDeliveryWarrantyPdf(
  DeliveryWarrantyPdfInput document, {
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
    title: 'Comprobante de entrega ${document.jobNumber}',
    author: document.storeName,
    subject: 'Comprobante de entrega y garantía',
  );
  final legal = document.legalName;
  final footerParty =
      legal != null && legal.toLowerCase() != document.storeName.toLowerCase()
      ? '${document.storeName} · $legal · '
      : '${document.storeName} · ';

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
                    document.storeName,
                    null,
                    compact: true,
                    logo: logoImage,
                  ),
                  pw.Text(
                    document.jobNumber,
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
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    '${footerParty}Este documento no es boleta ni factura.',
                    style: const pw.TextStyle(
                      color: storeDocumentMuted,
                      fontSize: 8,
                    ),
                  ),
                  if (document.contactLine case final contact?) ...[
                    pw.SizedBox(height: 2),
                    pw.Text(
                      contact,
                      style: const pw.TextStyle(
                        color: storeDocumentMuted,
                        fontSize: 8,
                      ),
                    ),
                  ],
                ],
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
        // Who and what first, then what was done, and the warranty at the
        // end with its conditions: the owner's order (2026-11-04: «¿cómo
        // aparecen los datos de garantía antes que el nombre y la bici? Pon
        // las garantías al final»).
        _documentHeader(document, logoImage),
        pw.SizedBox(height: 20),
        _party(document),
        if (document.requestSummary != null) ...[
          pw.SizedBox(height: 16),
          _textSection('Servicio solicitado', document.requestSummary!),
        ],
        if (document.diagnosis != null) ...[
          pw.SizedBox(height: 12),
          _textSection('Diagnóstico', document.diagnosis!),
        ],
        pw.SizedBox(height: 16),
        ..._work(document),
        pw.SizedBox(height: 20),
        _warranty(document),
        pw.SizedBox(height: 10),
        // The warranty's conditions and, for a customer without an account,
        // the QR beside them: side by side so an ordinary job fits one page.
        if (document.claimUrl != null)
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(flex: 17, child: _instructions(document)),
              pw.SizedBox(width: 10),
              pw.Expanded(flex: 10, child: _claim(document)),
            ],
          )
        else
          _instructions(document),
        pw.SizedBox(height: 14),
        pw.Text(
          document.thanksLine,
          style: pw.TextStyle(
            color: storeDocumentInk,
            fontSize: 10,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        if (document.hasAccount) ...[
          pw.SizedBox(height: 3),
          pw.Text(
            document.accountLine,
            style: const pw.TextStyle(color: storeDocumentMuted, fontSize: 9),
          ),
        ],
      ],
    ),
  );

  return pdf.save();
}

pw.Widget _documentHeader(
  DeliveryWarrantyPdfInput document,
  pw.ImageProvider? logo,
) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Expanded(
        child: storeDocumentWordmark(
          document.storeName,
          document.tagline,
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
              'COMPROBANTE DE ENTREGA Y GARANTÍA',
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
            document.jobNumber,
            style: pw.TextStyle(
              color: storeDocumentInk,
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Entregado el ${storeDocumentDate(document.deliveredAt)}',
            style: const pw.TextStyle(color: storeDocumentMuted, fontSize: 9),
          ),
        ],
      ),
    ],
  );
}

/// The two warranties, side by side: what the customer came for.
pw.Widget _warranty(DeliveryWarrantyPdfInput document) {
  pw.Widget box(String label, String value, DateTime until, bool covered) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 13),
        decoration: pw.BoxDecoration(
          color: covered
              ? storeDocumentPositiveSurface
              : storeDocumentSoftSurface,
          borderRadius: pw.BorderRadius.circular(4),
        ),
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
            pw.SizedBox(height: 5),
            pw.Text(
              value,
              style: pw.TextStyle(
                color: covered ? storeDocumentPositive : storeDocumentInk,
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            if (covered) ...[
              pw.SizedBox(height: 3),
              pw.Text(
                'Válida hasta el ${storeDocumentLongDate(until)}',
                style: const pw.TextStyle(
                  color: storeDocumentInk,
                  fontSize: 9.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      box(
        'Garantía del servicio',
        document.serviceWarrantyLabel,
        document.serviceWarrantyExpiresAt,
        document.serviceWarrantyDays > 0,
      ),
      if (document.showsPartsWarranty) ...[
        pw.SizedBox(width: 10),
        box(
          'Garantía de repuestos',
          document.partsWarrantyLabel,
          document.partsWarrantyExpiresAt,
          document.partsWarrantyMonths > 0,
        ),
      ],
    ],
  );
}

/// Who and what: the customer and the bikes (or the part) that left.
pw.Widget _party(DeliveryWarrantyPdfInput document) {
  pw.Widget cell(String label, String value, {String? detail}) => pw.Padding(
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
        if (detail != null) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            detail,
            style: const pw.TextStyle(color: storeDocumentMuted, fontSize: 8.5),
          ),
        ],
      ],
    ),
  );
  final bikes = document.bikes;
  final String subject;
  final String? subjectDetail;
  if (bikes.isNotEmpty) {
    subject = bikes.map((bike) => bike.title).join(' · ');
    subjectDetail = bikes.length == 1 ? bikes.first.detail : null;
  } else {
    subject = document.subjectNotes ?? 'Trabajo del taller';
    subjectDetail = null;
  }
  return pw.Table(
    columnWidths: const {0: pw.FlexColumnWidth(1), 1: pw.FlexColumnWidth(1.6)},
    border: pw.TableBorder.all(color: storeDocumentLine),
    children: [
      pw.TableRow(
        children: [
          cell('Cliente', document.customerName ?? 'Cliente'),
          cell(
            bikes.length > 1
                ? 'Bicicletas'
                : bikes.isEmpty
                ? 'Trabajo'
                : 'Bicicleta',
            subject,
            detail: subjectDetail,
          ),
        ],
      ),
    ],
  );
}

pw.Widget _sectionTitle(String text) => pw.Text(
  text,
  style: pw.TextStyle(
    color: storeDocumentInk,
    fontSize: 12,
    fontWeight: pw.FontWeight.bold,
  ),
);

pw.Widget _textSection(String title, String body) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    _sectionTitle(title),
    pw.SizedBox(height: 5),
    pw.Text(
      body,
      style: const pw.TextStyle(
        color: storeDocumentInk,
        fontSize: 10,
        lineSpacing: 2,
      ),
    ),
  ],
);

pw.Widget _bulletRow(String text, {String? trailing, bool muted = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 4,
          height: 4,
          margin: const pw.EdgeInsets.only(top: 4.5, right: 8),
          decoration: const pw.BoxDecoration(
            color: storeDocumentBrand,
            shape: pw.BoxShape.circle,
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            text,
            style: pw.TextStyle(
              color: muted ? storeDocumentMuted : storeDocumentInk,
              fontSize: 10,
              lineSpacing: 2,
            ),
          ),
        ),
        if (trailing != null) ...[
          pw.SizedBox(width: 12),
          pw.Text(
            trailing,
            style: const pw.TextStyle(color: storeDocumentMuted, fontSize: 10),
          ),
        ],
      ],
    ),
  );
}

/// What was done and what was installed, per bike when there are several.
List<pw.Widget> _work(DeliveryWarrantyPdfInput document) {
  final widgets = <pw.Widget>[];
  final groups = document.groups;
  for (var index = 0; index < groups.length; index++) {
    final group = groups[index];
    final done = [
      for (final line in group.lines)
        if (!line.isPart) line,
    ];
    final parts = [
      for (final line in group.lines)
        if (line.isPart) line,
    ];
    final performed = groups.length > 1
        ? group.bike?.workPerformed
        : document.workPerformed ?? group.bike?.workPerformed;
    if (done.isEmpty && parts.isEmpty && performed == null) continue;
    if (widgets.isNotEmpty) widgets.add(pw.SizedBox(height: 14));
    if (groups.length > 1) {
      widgets.add(
        pw.Text(
          group.bike?.title ?? 'Otros',
          style: pw.TextStyle(
            color: storeDocumentBrand,
            fontSize: 10.5,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      );
      widgets.add(pw.SizedBox(height: 6));
    }
    if (done.isNotEmpty || performed != null) {
      widgets.add(_sectionTitle('Trabajo realizado'));
      widgets.add(pw.SizedBox(height: 6));
      for (final line in done) {
        widgets.add(_bulletRow(line.name, trailing: line.quantityLabel));
      }
      if (performed != null) widgets.add(_bulletRow(performed));
    }
    if (parts.isNotEmpty) {
      if (done.isNotEmpty || performed != null) {
        widgets.add(pw.SizedBox(height: 10));
      }
      widgets.add(_sectionTitle('Repuestos instalados'));
      widgets.add(pw.SizedBox(height: 6));
      for (final line in parts) {
        widgets.add(_bulletRow(line.name, trailing: line.quantityLabel));
      }
    }
  }
  return widgets;
}

pw.Widget _instructions(DeliveryWarrantyPdfInput document) {
  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(14, 12, 14, 12),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: storeDocumentLine),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('Sobre tu garantía'),
        pw.SizedBox(height: 7),
        for (final line in document.instructions) _bulletRow(line),
        pw.SizedBox(height: 3),
        pw.Text(
          DeliveryWarrantyPdfInput.legalLine,
          style: const pw.TextStyle(color: storeDocumentMuted, fontSize: 8.5),
        ),
      ],
    ),
  );
}

/// The QR to create the account, only for a customer who has none: the code
/// on top, what it is for below.
pw.Widget _claim(DeliveryWarrantyPdfInput document) {
  return pw.Container(
    padding: const pw.EdgeInsets.fromLTRB(12, 12, 12, 12),
    decoration: pw.BoxDecoration(
      color: storeDocumentSoftSurface,
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.all(4),
              color: PdfColors.white,
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(
                  errorCorrectLevel: pw.BarcodeQRCorrectionLevel.medium,
                ),
                data: document.claimUrl!,
                drawText: false,
                width: 74,
                height: 74,
                color: storeDocumentInk,
              ),
            ),
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Text(
                DeliveryWarrantyPdfInput.claimTitle,
                style: pw.TextStyle(
                  color: storeDocumentBrand,
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          DeliveryWarrantyPdfInput.claimBody,
          style: const pw.TextStyle(
            color: storeDocumentInk,
            fontSize: 9,
            lineSpacing: 2,
          ),
        ),
      ],
    ),
  );
}
