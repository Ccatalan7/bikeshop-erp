import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:vinabike_public_core/public_store/documents/quote_offer_pdf.dart';

import 'order_summary_pdf_route.dart';
import 'public_reads.dart';

/// Where the quote page asks for its offer's PDF.
const quoteOfferPdfPath = '/cotizacion/oferta.pdf';

/// `POST /cotizacion/oferta.pdf` with `{access_token}`: the quote's offer as
/// the ERP's «PDF de la oferta» draws it too ([buildQuoteOfferPdf], shared).
/// The link travels in the body, never in the address; without it nothing is
/// read.
Future<Response> quoteOfferPdf(
  Request request, {
  required PublicReads reads,
  required OrderSummaryFonts fonts,
}) async {
  final body = await readDocumentRequest(request);
  final token = body?['access_token']?.toString().trim() ?? '';
  if (token.length < 40 || token.length > 128) {
    return documentTextResponse(400, 'Solicitud inválida.');
  }
  final Object? answer;
  try {
    answer = await reads.publicQuote(token);
  } on Object catch (error) {
    stderr.writeln('quote offer read failed: $error');
    return documentTextResponse(503, 'No pudimos leer la cotización.');
  }
  final input = QuoteOfferPdfInput.fromPublicQuote(answer);
  if (input == null) {
    return documentTextResponse(404, 'La cotización no tiene una oferta.');
  }
  final Uint8List bytes;
  try {
    bytes = await buildQuoteOfferPdf(
      input,
      regularFont: await fonts.face('Barlow-Regular'),
      boldFont: await fonts.face('Barlow-Bold'),
    );
  } on Object catch (error) {
    stderr.writeln('quote offer pdf failed: $error');
    return documentTextResponse(503, 'No pudimos generar el PDF.');
  }
  return Response.ok(
    bytes,
    headers: {
      'content-type': 'application/pdf',
      'content-disposition': 'attachment; filename="${input.fileName}"',
      'cache-control': 'no-store',
      'x-robots-tag': 'noindex',
    },
  );
}
