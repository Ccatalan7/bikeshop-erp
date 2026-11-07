import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:vinabike_public_core/public_store/documents/delivery_warranty_pdf.dart';
import 'package:vinabike_public_core/public_store/documents/job_quote_pdf.dart';

import 'order_summary_pdf_route.dart';
import 'public_reads.dart';

/// Where whatsapp-send asks for the PDF that travels on top of a workshop
/// notice (20261107130000): the quote of «Presupuesto listo» or the receipt
/// of «Trabajo entregado».
const workshopNoticeDocumentPdfPath = '/cuenta/aviso.pdf';

final _noticeCode = RegExp(r'^[A-Za-z0-9_-]{43}$');

/// `POST /cuenta/aviso.pdf` with `{token}`: the notice's one-time code, left
/// by the database when the notice went out. The code travels in the body,
/// never in the address, and is only sent to Supabase
/// (`workshop_notice_document_v1`), which counts each read. The receipt is
/// the one the customer's account draws ([buildDeliveryWarrantyPdf]); the
/// quote, [buildJobQuotePdf]. The file name is the one the customer sees in
/// the chat.
Future<Response> workshopNoticeDocumentPdf(
  Request request, {
  required PublicReads reads,
  required OrderSummaryFonts fonts,
}) async {
  final body = await readDocumentRequest(request);
  final token = body?['token']?.toString().trim() ?? '';
  if (!_noticeCode.hasMatch(token)) {
    return documentTextResponse(400, 'Solicitud inválida.');
  }
  final Object? answer;
  try {
    answer = await reads.workshopNoticeDocument(token);
  } on Object catch (error) {
    stderr.writeln(
      'workshop notice document read failed: '
      '${error is PublicReadException ? error.message : error.runtimeType}',
    );
    return documentTextResponse(503, 'No pudimos leer el documento.');
  }
  if (answer is! Map) {
    return documentTextResponse(404, 'Documento no encontrado.');
  }
  final document = answer['document'];
  final Uint8List bytes;
  final String fileName;
  try {
    switch (answer['kind']) {
      case 'quote':
        final input = JobQuotePdfInput.fromProjection(document);
        if (input == null) {
          return documentTextResponse(404, 'Documento no encontrado.');
        }
        bytes = await buildJobQuotePdf(
          input,
          regularFont: await fonts.face('Barlow-Regular'),
          boldFont: await fonts.face('Barlow-Bold'),
          logo: await fonts.storeLogo(input.logoUrl),
        );
        fileName = input.fileName;
      case 'delivery':
        // Without the QR nor the «ya está en tu cuenta» line: the notice's
        // button «Guardar en mi cuenta» is how this one reaches the account.
        final input = DeliveryWarrantyPdfInput.fromProjection(document);
        if (input == null) {
          return documentTextResponse(404, 'Documento no encontrado.');
        }
        bytes = await buildDeliveryWarrantyPdf(
          input,
          regularFont: await fonts.face('Barlow-Regular'),
          boldFont: await fonts.face('Barlow-Bold'),
          logo: await fonts.storeLogo(input.logoUrl),
        );
        fileName =
            'Comprobante ${input.jobNumber.replaceAll(RegExp(r'[^0-9A-Za-z-]'), '_')}.pdf';
      default:
        return documentTextResponse(404, 'Documento no encontrado.');
    }
  } on Object catch (error) {
    stderr.writeln('workshop notice document pdf failed: $error');
    return documentTextResponse(503, 'No pudimos generar el documento.');
  }
  return Response.ok(
    bytes,
    headers: {
      'content-type': 'application/pdf',
      'content-disposition': 'attachment; filename="$fileName"',
      'cache-control': 'no-store',
      'x-robots-tag': 'noindex',
    },
  );
}
