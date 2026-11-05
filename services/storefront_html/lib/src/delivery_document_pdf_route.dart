import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';
import 'package:vinabike_public_core/public_store/documents/delivery_warranty_pdf.dart';

import 'order_summary_pdf_route.dart';
import 'portal_page_route.dart';
import 'public_reads.dart';

/// Where the portal asks for a job's delivery and warranty document.
const deliveryDocumentPdfPath = '/cuenta/comprobante.pdf';

/// `POST /cuenta/comprobante.pdf` with the customer's session and
/// `{job_id}`: the job's delivery and warranty document as the ERP draws it
/// ([buildDeliveryWarrantyPdf], shared), read as the customer
/// (`list_my_job_delivery_documents_v1`): only one of their own jobs.
Future<Response> deliveryDocumentPdf(
  Request request, {
  required PublicReads reads,
  required OrderSummaryFonts fonts,
}) async {
  final token = requestBearer(request);
  final body = await readDocumentRequest(request);
  final jobId = body?['job_id']?.toString().trim() ?? '';
  if (token == null ||
      !RegExp(
        r'^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$',
      ).hasMatch(jobId)) {
    return documentTextResponse(400, 'Solicitud inválida.');
  }
  final List<Map<String, dynamic>> documents;
  try {
    documents = await reads.customerDeliveryDocuments(token);
  } on CustomerSessionRefused {
    return documentTextResponse(401, 'Tu sesión venció. Vuelve a entrar.');
  } on Object catch (error) {
    stderr.writeln(
      'delivery document read failed: '
      '${error is PublicReadException ? error.message : error.runtimeType}',
    );
    return documentTextResponse(503, 'No pudimos leer el comprobante.');
  }
  Map<String, dynamic>? document;
  for (final row in documents) {
    if (row['job_id']?.toString() == jobId) document = row;
  }
  final input = DeliveryWarrantyPdfInput.fromProjection(
    document,
    hasAccount: true,
  );
  if (input == null) {
    return documentTextResponse(404, 'Comprobante no encontrado.');
  }
  final Uint8List bytes;
  try {
    bytes = await buildDeliveryWarrantyPdf(
      input,
      regularFont: await fonts.face('Barlow-Regular'),
      boldFont: await fonts.face('Barlow-Bold'),
      logo: await fonts.storeLogo(input.logoUrl),
    );
  } on Object catch (error) {
    stderr.writeln('delivery document pdf failed: $error');
    return documentTextResponse(503, 'No pudimos generar el comprobante.');
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
