import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../shared/utils/chilean_utils.dart';
import '../../settings/models/company_profile.dart';
import '../models/website_models.dart';

/// The paper the shipping label is printed on.
enum ShippingLabelPaper {
  /// 10 × 15 cm, the parcel label Chilexpress, Starken, Pullman Cargo and
  /// Correos de Chile take on a box; a thermal printer prints it as is.
  label10x15,

  /// Two labels side by side on a letter sheet, with a cut line, for an
  /// ordinary printer.
  letter,
}

/// The Barlow faces of the label (TrueType, from `assets/fonts/`).
class ShippingLabelFonts {
  const ShippingLabelFonts({
    required this.regular,
    required this.medium,
    required this.semiBold,
    required this.bold,
    required this.extraBold,
  });

  final ByteData regular;
  final ByteData medium;
  final ByteData semiBold;
  final ByteData bold;
  final ByteData extraBold;
}

/// What one label says, already in the words printed on it.
///
/// Recipient first and largest — name, street, the comuna the carrier sorts
/// by, region and postal code, phone and RUT — then the delivery
/// instructions, the sender with its RUT, and the facts a counter asks for:
/// order, ship date, declared value, contents, weight and size. Weight, size
/// and a missing RUT stay as lines to write by hand: no one measured them.
class ShippingLabelData {
  const ShippingLabelData({
    required this.orderNumber,
    required this.recipientName,
    required this.street,
    required this.comuna,
    required this.regionLine,
    required this.phone,
    required this.recipientRut,
    required this.instructions,
    required this.senderTitle,
    required this.senderAddress,
    required this.senderContact,
    required this.brandName,
    required this.website,
    required this.contents,
    required this.declaredValue,
    required this.shipDate,
  });

  factory ShippingLabelData.fromOrder(
    OnlineOrder order, {
    required CompanyProfile? company,
    required String? recipientRut,
    required DateTime shipDate,
  }) {
    String clean(String? value) => value?.trim() ?? '';
    String joined(Iterable<String?> parts, String separator) => parts
        .map(clean)
        .where((part) => part.isNotEmpty)
        .toSet()
        .join(separator);

    final street = joined(
      [order.shippingAddressLine1, order.shippingAddressLine2],
      ', ',
    );
    final postalCode = clean(order.shippingPostalCode);
    final region = clean(order.shippingState);

    final brand = clean(company?.fantasyName).isNotEmpty
        ? clean(company?.fantasyName)
        : clean(company?.name).isNotEmpty
            ? clean(company?.name)
            : order.storefrontIdentity.displayName;
    final legalName = clean(company?.legalName);
    final senderRut = ChileanUtils.formatRut(clean(company?.taxId));
    final senderPhone = ChileanUtils.formatPhone(
      clean(company?.phone).isNotEmpty
          ? company?.phone
          : order.storefrontIdentity.supportPhone,
    );
    final senderEmail = clean(company?.publicEmail).isNotEmpty
        ? clean(company?.publicEmail)
        : clean(company?.email).isNotEmpty
            ? clean(company?.email)
            : clean(order.storefrontIdentity.supportEmail);
    final senderRegion = clean(company?.region);
    final website = clean(company?.websiteUrl)
        .replaceFirst(RegExp(r'^https?://'), '')
        .replaceFirst(RegExp(r'/$'), '');

    final items = order.items;
    final units = items.fold<int>(0, (sum, item) => sum + item.quantity);
    final contents = items.length == 1
        ? '${items.single.quantity} × ${items.single.productName.trim()}'
        : '$units u. · ${items.map((item) => item.productName.trim()).join(' · ')}';
    final declared = items.fold<double>(0, (sum, item) => sum + item.subtotal);

    return ShippingLabelData(
      orderNumber: order.orderNumber,
      recipientName: order.customerName.trim(),
      street: street.isNotEmpty ? street : clean(order.customerAddress),
      comuna: clean(order.shippingCity).toUpperCase(),
      regionLine: [
        if (region.isNotEmpty) region,
        if (postalCode.isNotEmpty) 'CP $postalCode',
      ].join(' · '),
      phone: ChileanUtils.formatPhone(order.customerPhone),
      recipientRut: clean(recipientRut).isEmpty
          ? null
          : ChileanUtils.formatRut(clean(recipientRut)),
      instructions: clean(order.customerNotes).isEmpty
          ? null
          : clean(order.customerNotes),
      senderTitle: joined(
        [
          brand,
          if (legalName.isNotEmpty && legalName != brand) legalName,
          if (senderRut.isNotEmpty) 'RUT $senderRut',
        ],
        ' · ',
      ),
      senderAddress: joined(
        [
          joined([company?.address, company?.comuna], ', '),
          if (senderRegion.isNotEmpty)
            'Región de $senderRegion'
                .replaceFirst('Región de Región', 'Región'),
          if (clean(company?.postalCode).isNotEmpty)
            'CP ${clean(company?.postalCode)}',
        ],
        ' · ',
      ),
      senderContact: joined([senderPhone, senderEmail], ' · '),
      brandName: brand,
      website: website,
      contents: contents,
      declaredValue: declared > 0 ? declared : order.total - order.shippingCost,
      shipDate: shipDate,
    );
  }

  final String orderNumber;
  final String recipientName;
  final String street;
  final String comuna;
  final String regionLine;
  final String phone;
  final String? recipientRut;
  final String? instructions;
  final String senderTitle;
  final String senderAddress;
  final String senderContact;
  final String brandName;
  final String website;
  final String contents;
  final double declaredValue;
  final DateTime shipDate;
}

/// 10 × 15 cm.
const PdfPageFormat shippingLabelFormat = PdfPageFormat(
  100 * PdfPageFormat.mm,
  150 * PdfPageFormat.mm,
);

/// The label as a PDF: one label per package («Bulto 1 de 3»…), on its own
/// 10 × 15 cm page or two to a letter sheet.
///
/// Black on white only: it has to come out the same from a thermal printer,
/// a laser printer and a photocopy, and the carrier reads it at arm's length.
Future<Uint8List> buildShippingLabelPdf(
  ShippingLabelData data, {
  required int packages,
  required ShippingLabelPaper paper,
  required ShippingLabelFonts fonts,
  Uint8List? logo,
}) async {
  final faces = _Faces(
    regular: pw.Font.ttf(fonts.regular),
    medium: pw.Font.ttf(fonts.medium),
    semiBold: pw.Font.ttf(fonts.semiBold),
    bold: pw.Font.ttf(fonts.bold),
    extraBold: pw.Font.ttf(fonts.extraBold),
  );
  final logoImage = logo == null ? null : pw.MemoryImage(logo);
  final count = packages.clamp(1, 99);
  final document = pw.Document(
    title: 'Etiqueta ${data.orderNumber}',
    author: data.brandName,
    theme: pw.ThemeData.withFont(base: faces.regular, bold: faces.bold),
  );

  pw.Widget label(int index) => pw.SizedBox(
        width: shippingLabelFormat.width,
        height: shippingLabelFormat.height,
        child: _label(data, faces, logoImage, index + 1, count),
      );

  if (paper == ShippingLabelPaper.label10x15) {
    for (var index = 0; index < count; index++) {
      document.addPage(
        pw.Page(
          pageFormat: shippingLabelFormat,
          margin: pw.EdgeInsets.zero,
          build: (_) => label(index),
        ),
      );
    }
  } else {
    for (var first = 0; first < count; first += 2) {
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.fromLTRB(0, 36, 0, 36),
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  for (var index = first;
                      index < first + 2 && index < count;
                      index++)
                    _cutFrame(label(index)),
                ],
              ),
              pw.SizedBox(height: 8),
              pw.Text(
                'Recorta por la línea punteada y pega la etiqueta en la cara más grande de la caja.',
                style: pw.TextStyle(
                  font: faces.regular,
                  fontSize: 7.5,
                  color: _muted,
                ),
              ),
            ],
          ),
        ),
      );
    }
  }
  return document.save();
}

const PdfColor _ink = PdfColor.fromInt(0xFF111111);
const PdfColor _muted = PdfColor.fromInt(0xFF4A4A4A);

class _Faces {
  const _Faces({
    required this.regular,
    required this.medium,
    required this.semiBold,
    required this.bold,
    required this.extraBold,
  });

  final pw.Font regular;
  final pw.Font medium;
  final pw.Font semiBold;
  final pw.Font bold;
  final pw.Font extraBold;
}

pw.Widget _cutFrame(pw.Widget child) => pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: _muted,
          width: 0.6,
          style: pw.BorderStyle.dashed,
        ),
      ),
      child: child,
    );

pw.Widget _caption(_Faces faces, String text, {double size = 6.7}) => pw.Text(
      text.toUpperCase(),
      style: pw.TextStyle(
        font: faces.bold,
        fontSize: size,
        letterSpacing: 1.1,
        color: _muted,
      ),
    );

pw.Widget _fillLine(double width) => pw.Container(
      width: width,
      height: 9,
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 0.7)),
      ),
    );

pw.Widget _label(
  ShippingLabelData data,
  _Faces faces,
  pw.ImageProvider? logo,
  int package,
  int packages,
) {
  final shipDate = DateFormat('dd-MM-yyyy').format(data.shipDate);
  return pw.Padding(
    padding: const pw.EdgeInsets.fromLTRB(12.7, 11.3, 12.7, 8.5),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // Brand and service.
        pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 5.5),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 1.8)),
          ),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Expanded(
                child: pw.Align(
                  alignment: pw.Alignment.bottomLeft,
                  child: logo != null
                      ? pw.Image(logo, height: 24, fit: pw.BoxFit.contain)
                      : pw.Text(
                          data.brandName.toUpperCase(),
                          style: pw.TextStyle(
                            font: faces.extraBold,
                            fontSize: 18.5,
                            letterSpacing: -0.3,
                            color: _ink,
                          ),
                        ),
                ),
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 5.5,
                      vertical: 2.6,
                    ),
                    decoration: pw.BoxDecoration(
                      color: _ink,
                      borderRadius: pw.BorderRadius.circular(2),
                    ),
                    child: pw.Text(
                      'DESPACHO A DOMICILIO',
                      style: pw.TextStyle(
                        font: faces.bold,
                        fontSize: 7.4,
                        letterSpacing: 0.9,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 2.5),
                  pw.Text(
                    'BULTO $package DE $packages',
                    style: pw.TextStyle(
                      font: faces.semiBold,
                      fontSize: 7.4,
                      letterSpacing: 0.4,
                      color: _ink,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 6.5),
        // Recipient: the biggest block, read first.
        _caption(faces, 'Para'),
        pw.SizedBox(height: 1.5),
        pw.Text(
          data.recipientName,
          maxLines: 2,
          style: pw.TextStyle(
            font: faces.bold,
            fontSize: 15,
            lineSpacing: 0,
            color: _ink,
          ),
        ),
        pw.SizedBox(height: 1.5),
        pw.Text(
          data.street.isEmpty ? 'Sin dirección registrada' : data.street,
          maxLines: 2,
          style:
              pw.TextStyle(font: faces.semiBold, fontSize: 10.6, color: _ink),
        ),
        if (data.comuna.isNotEmpty) ...[
          pw.SizedBox(height: 2),
          pw.Text(
            data.comuna,
            maxLines: 1,
            style: pw.TextStyle(
              font: faces.extraBold,
              fontSize: 21,
              letterSpacing: 0.3,
              color: _ink,
            ),
          ),
        ],
        if (data.regionLine.isNotEmpty)
          pw.Text(
            data.regionLine,
            style: pw.TextStyle(font: faces.medium, fontSize: 8.5, color: _ink),
          ),
        pw.SizedBox(height: 4),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Text(
                data.phone.isEmpty ? 'Teléfono: ' : 'Tel. ${data.phone}',
                style: pw.TextStyle(
                  font: faces.bold,
                  fontSize: 10.6,
                  color: _ink,
                ),
              ),
            ),
            pw.Text(
              'RUT ',
              style: pw.TextStyle(font: faces.semiBold, fontSize: 7.8),
            ),
            data.recipientRut == null
                ? _fillLine(78)
                : pw.Text(
                    data.recipientRut!,
                    style: pw.TextStyle(font: faces.bold, fontSize: 9.5),
                  ),
          ],
        ),
        if (data.instructions != null) ...[
          pw.SizedBox(height: 6),
          pw.Container(
            padding: const pw.EdgeInsets.fromLTRB(6.4, 4.2, 6.4, 5),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: _ink, width: 0.85),
              borderRadius: pw.BorderRadius.circular(3.5),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _caption(faces, 'Indicaciones de entrega', size: 6.4),
                pw.SizedBox(height: 1.5),
                pw.Text(
                  data.instructions!,
                  maxLines: 5,
                  style: pw.TextStyle(
                    font: faces.regular,
                    fontSize: 7.8,
                    lineSpacing: 1.2,
                    color: _ink,
                  ),
                ),
              ],
            ),
          ),
        ],
        pw.Spacer(),
        // Sender, with the logistics below it: the address reads first,
        // the counter's facts sit together at the foot.
        _caption(faces, 'De'),
        pw.SizedBox(height: 1),
        pw.Text(
          data.senderTitle,
          maxLines: 1,
          style: pw.TextStyle(font: faces.bold, fontSize: 8.8, color: _ink),
        ),
        if (data.senderAddress.isNotEmpty)
          pw.Text(
            data.senderAddress,
            maxLines: 2,
            style: pw.TextStyle(font: faces.regular, fontSize: 7.8),
          ),
        if (data.senderContact.isNotEmpty)
          pw.Text(
            data.senderContact,
            maxLines: 1,
            style: pw.TextStyle(font: faces.regular, fontSize: 7.8),
          ),
        pw.SizedBox(height: 6),
        // What the counter asks for.
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _ink, width: 0.85),
            borderRadius: pw.BorderRadius.circular(3.5),
          ),
          child: pw.Column(
            children: [
              pw.Row(
                children: [
                  _factCell(
                      faces,
                      'Pedido',
                      pw.Text(data.orderNumber,
                          style: pw.TextStyle(font: faces.bold, fontSize: 8.8)),
                      flex: 5,
                      right: true,
                      bottom: true),
                  _factCell(
                      faces,
                      'Fecha de envío',
                      pw.Text(shipDate,
                          style: pw.TextStyle(
                              font: faces.semiBold, fontSize: 8.8)),
                      flex: 4,
                      right: true,
                      bottom: true),
                  _factCell(
                      faces,
                      'Valor declarado',
                      pw.Text(ChileanUtils.formatCurrency(data.declaredValue),
                          style: pw.TextStyle(font: faces.bold, fontSize: 8.8)),
                      flex: 4,
                      bottom: true),
                ],
              ),
              // The contents get the full width: a product name cut in
              // half tells the counter nothing.
              pw.Row(
                children: [
                  _factCell(
                    faces,
                    'Contenido',
                    pw.Text(
                      data.contents,
                      maxLines: 2,
                      style: pw.TextStyle(font: faces.semiBold, fontSize: 7.8),
                    ),
                    flex: 13,
                    bottom: true,
                    height: 33,
                  ),
                ],
              ),
              pw.Row(
                children: [
                  _factCell(
                    faces,
                    'Peso',
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        _fillLine(44),
                        pw.SizedBox(width: 3),
                        pw.Text(
                          'kg',
                          style:
                              pw.TextStyle(font: faces.semiBold, fontSize: 8.2),
                        ),
                      ],
                    ),
                    flex: 5,
                    right: true,
                  ),
                  _factCell(
                    faces,
                    'Medidas (largo × ancho × alto)',
                    pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        for (final (index, unit) in const [
                          (0, '×'),
                          (1, '×'),
                          (2, 'cm'),
                        ]) ...[
                          if (index > 0) pw.SizedBox(width: 3),
                          _fillLine(30),
                          pw.SizedBox(width: 3),
                          pw.Text(
                            unit,
                            style: pw.TextStyle(
                              font: faces.semiBold,
                              fontSize: 8.2,
                            ),
                          ),
                        ],
                      ],
                    ),
                    flex: 8,
                  ),
                ],
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 8),
        // The order, scannable back into the ERP.
        pw.Center(
          child: pw.BarcodeWidget(
            barcode: pw.Barcode.code128(),
            data: data.orderNumber,
            width: 210,
            height: 32,
            drawText: false,
            color: _ink,
          ),
        ),
        pw.SizedBox(height: 2.5),
        pw.Center(
          child: pw.Text(
            data.orderNumber,
            style: pw.TextStyle(
              font: faces.bold,
              fontSize: 7.8,
              letterSpacing: 1.7,
              color: _ink,
            ),
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Center(
          child: pw.Text(
            data.website.isEmpty
                ? 'Gracias por comprar en ${data.brandName}'
                : 'Gracias por comprar en ${data.brandName} · ${data.website}',
            style: pw.TextStyle(
              font: faces.regular,
              fontSize: 6.7,
              color: _muted,
            ),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _factCell(
  _Faces faces,
  String caption,
  pw.Widget value, {
  required int flex,
  bool right = false,
  bool bottom = false,
  double height = 27,
}) {
  const side = pw.BorderSide(color: _ink, width: 0.7);
  return pw.Expanded(
    flex: flex,
    child: pw.Container(
      height: height,
      padding: const pw.EdgeInsets.fromLTRB(5.6, 3.4, 5, 3),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          right: right ? side : pw.BorderSide.none,
          bottom: bottom ? side : pw.BorderSide.none,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _caption(faces, caption, size: 6),
          pw.SizedBox(height: 1.5),
          value,
        ],
      ),
    ),
  );
}
