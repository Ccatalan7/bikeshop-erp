import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../modules/purchases/models/purchase_order_document.dart';
import '../../modules/settings/services/appearance_service.dart';

/// **El pedido que se le manda al proveedor.**
///
/// No es `PurchaseDocumentPdfGenerator`. Ése imprime el documento que el
/// proveedor **nos** emitió —tiene «saldo adeudado» y habla de una deuda ya
/// contraída—; esto es lo contrario: lo que le pedimos antes de que exista
/// factura alguna. Mandarle su propia plantilla de deuda a un proveedor es
/// pedirle plata en vez de mercadería.
///
/// Toma un [PurchaseOrderDocument] ya formateado, el mismo que dibuja la vista
/// previa en pantalla, para que lo aprobado y lo enviado sean el mismo papel.
class PurchaseOrderPdfGenerator {
  const PurchaseOrderPdfGenerator._();

  static Uint8List? _cachedLogoBytes;
  static String? _cachedLogoUrl;

  static String fileNameFor(PurchaseOrderDocument document) {
    final folio = document.isDraft ? 'borrador' : document.orderNumber;
    return 'pedido_$folio.pdf';
  }

  static Future<Uint8List> generateBytes(
    PurchaseOrderDocument document, {
    required AppearanceService appearanceService,
  }) async {
    final pdf = await generate(document, appearanceService: appearanceService);
    return pdf.save();
  }

  static Future<pw.Document> generate(
    PurchaseOrderDocument document, {
    required AppearanceService appearanceService,
  }) async {
    final pdf = pw.Document();
    final logo = await _logo(appearanceService);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.letter,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logo != null)
                  pw.Image(logo, width: 120, height: 40, fit: pw.BoxFit.contain)
                else
                  pw.Text(
                    document.buyerName.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blue800,
                    ),
                  ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      'PEDIDO',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    pw.SizedBox(height: 3),
                    pw.Text(
                      document.isDraft
                          ? 'Borrador · sin número'
                          : '# ${document.orderNumber}',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      document.issuedOn,
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 18),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: _party(
                    'De',
                    document.buyerName,
                    <String?>[document.buyerCity],
                  ),
                ),
                pw.SizedBox(width: 24),
                pw.Expanded(
                  child: _party(
                    'Para',
                    document.supplierName,
                    <String?>[
                      document.supplierLegalName,
                      document.supplierRut,
                      document.supplierContact,
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 18),
            pw.Table(
              border: const pw.TableBorder(
                horizontalInside:
                    pw.BorderSide(color: PdfColors.grey300, width: .5),
                bottom: pw.BorderSide(color: PdfColors.grey300, width: .5),
              ),
              columnWidths: {
                0: const pw.FlexColumnWidth(5),
                1: const pw.FlexColumnWidth(1.1),
                2: const pw.FlexColumnWidth(1.7),
                3: const pw.FlexColumnWidth(1.9),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _cell('Producto', header: true),
                    _cell('Cant.', header: true, alignEnd: true),
                    _cell('Precio unit.', header: true, alignEnd: true),
                    _cell('Total neto', header: true, alignEnd: true),
                  ],
                ),
                for (final line in document.lines)
                  pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 6, vertical: 5),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(line.name,
                                style: const pw.TextStyle(fontSize: 9)),
                            if (line.reference != null)
                              pw.Text(
                                line.reference!,
                                style: const pw.TextStyle(
                                  fontSize: 7.5,
                                  color: PdfColors.grey600,
                                ),
                              ),
                          ],
                        ),
                      ),
                      _cell(line.quantity, alignEnd: true),
                      _cell(line.unitCost, alignEnd: true),
                      _cell(line.netAmount, alignEnd: true),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 14),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.end,
              children: [
                pw.SizedBox(
                  width: 210,
                  child: pw.Column(
                    children: [
                      _totalRow('Neto', document.netTotal),
                      _totalRow('IVA 19%', document.ivaAmount),
                      pw.Divider(color: PdfColors.grey400, height: 10),
                      _totalRow('Total', document.total, bold: true),
                    ],
                  ),
                ),
              ],
            ),
            if (document.paymentTerms != null) ...[
              pw.SizedBox(height: 14),
              pw.Text(
                'Condiciones de pago: ${document.paymentTerms}',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
            if (document.note != null) ...[
              pw.SizedBox(height: 10),
              pw.Text(document.note!, style: const pw.TextStyle(fontSize: 9)),
            ],
            // La salvedad viaja en el papel, no sólo en la pantalla: quien
            // aprueba tiene que verla en lo mismo que va a mandar.
            if (document.unverifiedCostLines > 0) ...[
              pw.SizedBox(height: 12),
              pw.Text(
                document.unverifiedCostLines == 1
                    ? '1 línea lleva un precio de referencia interna, no un '
                        'precio ya cotizado. Confirmar antes de despachar.'
                    : '${document.unverifiedCostLines} líneas llevan un precio '
                        'de referencia interna, no uno ya cotizado. Confirmar '
                        'antes de despachar.',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    return pdf;
  }

  static pw.Widget _party(String role, String name, List<String?> details) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          role.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 7.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey600,
            letterSpacing: 1,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          name,
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        for (final detail in details)
          if (detail != null)
            pw.Text(
              detail,
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            ),
      ],
    );
  }

  static pw.Widget _cell(String text,
      {bool header = false, bool alignEnd = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        text,
        textAlign: alignEnd ? pw.TextAlign.right : pw.TextAlign.left,
        style: pw.TextStyle(
          fontSize: header ? 8 : 9,
          fontWeight: header ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: header ? PdfColors.grey800 : PdfColors.black,
        ),
      ),
    );
  }

  static pw.Widget _totalRow(String label, String amount, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: bold ? 11 : 9,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
          pw.Text(
            amount,
            style: pw.TextStyle(
              fontSize: bold ? 11 : 9,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  static Future<pw.ImageProvider?> _logo(
      AppearanceService appearanceService) async {
    try {
      final url = appearanceService.companyLogoUrl;
      if (url == null || url.isEmpty) return null;
      if (_cachedLogoBytes != null && _cachedLogoUrl == url) {
        return pw.MemoryImage(_cachedLogoBytes!);
      }
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return null;
      _cachedLogoBytes = response.bodyBytes;
      _cachedLogoUrl = url;
      return pw.MemoryImage(_cachedLogoBytes!);
    } catch (_) {
      // Un logo que no baja no puede impedir que salga el pedido.
      return null;
    }
  }
}
