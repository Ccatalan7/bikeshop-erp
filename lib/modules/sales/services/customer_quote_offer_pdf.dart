import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:vinabike_public_core/public_store/documents/quote_offer_pdf.dart';

import '../../../shared/utils/invoice_pdf_generator.dart';

/// La oferta en PDF, dibujada por el núcleo compartido ([buildQuoteOfferPdf])
/// para que el PDF del ERP sea el mismo que el cliente descarga de la tienda.
Future<Uint8List> buildQuoteOfferPdfBytes(QuoteOfferPdfInput quote) async {
  final regularFont = await rootBundle.load('assets/fonts/Barlow-Regular.ttf');
  final boldFont = await rootBundle.load('assets/fonts/Barlow-Bold.ttf');
  return buildQuoteOfferPdf(
    quote,
    regularFont: regularFont,
    boldFont: boldFont,
  );
}

/// En el escritorio se guarda (en Descargas, para arrastrarlo al chat) y se
/// devuelve dónde quedó; en el teléfono y la web abre la hoja de compartir o
/// la descarga, y devuelve null. Null también si el operador cancela.
Future<String?> saveOrShareQuoteOfferPdf(QuoteOfferPdfInput quote) async {
  final bytes = await buildQuoteOfferPdfBytes(quote);
  if (!kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Guardar la oferta en PDF',
      fileName: quote.fileName,
      initialDirectory: await InvoicePdfGenerator.resolveDefaultSaveDirectory(),
      allowedExtensions: const ['pdf'],
      type: FileType.custom,
    );
    if (path == null) return null;
    await File(path).writeAsBytes(bytes);
    return path;
  }
  await Printing.sharePdf(bytes: bytes, filename: quote.fileName);
  return null;
}
