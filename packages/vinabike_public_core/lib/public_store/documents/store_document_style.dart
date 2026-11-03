import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:timezone/timezone.dart' as tz;

import '../../shared/utils/shop_zone.dart';

/// What the store's customer documents share —the order summary and the
/// quote offer—, so a customer who keeps both sees one store: the palette,
/// the wordmark and how a date reads.
const storeDocumentInk = PdfColor.fromInt(0xFF17242C);
const storeDocumentMuted = PdfColor.fromInt(0xFF66747D);
const storeDocumentLine = PdfColor.fromInt(0xFFDDE4E8);
const storeDocumentSoftSurface = PdfColor.fromInt(0xFFF4F7F8);
const storeDocumentBrand = PdfColor.fromInt(0xFF174A68);
const storeDocumentWarning = PdfColor.fromInt(0xFF7A5A20);
const storeDocumentWarningSurface = PdfColor.fromInt(0xFFFFF8E8);
const storeDocumentPositive = PdfColor.fromInt(0xFF1E6B45);
const storeDocumentPositiveSurface = PdfColor.fromInt(0xFFE8F4EE);

/// The store's name as the letterhead sets it, with its tagline below on the
/// first page.
pw.Widget storeDocumentWordmark(
  String storeName,
  String? tagline, {
  bool compact = false,
}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        storeName.toUpperCase(),
        style: pw.TextStyle(
          color: storeDocumentBrand,
          fontSize: compact ? 12 : 23,
          fontWeight: pw.FontWeight.bold,
          letterSpacing: 0.8,
        ),
      ),
      if (!compact && tagline != null) ...[
        pw.SizedBox(height: 4),
        pw.Text(
          tagline,
          style: const pw.TextStyle(color: storeDocumentMuted, fontSize: 9),
        ),
      ],
    ],
  );
}

/// `dd/mm/aaaa hh:mm` on the shop's clock.
String storeDocumentDateTime(DateTime value) {
  final local = _shopTime(value);
  return '${storeDocumentDate(value)} ${_two(local.hour)}:${_two(local.minute)}';
}

/// `dd/mm/aaaa` on the shop's clock.
String storeDocumentDate(DateTime value) {
  final local = _shopTime(value);
  return '${_two(local.day)}/${_two(local.month)}/${local.year}';
}

tz.TZDateTime _shopTime(DateTime value) =>
    tz.TZDateTime.from(value.toUtc(), shopLocation());

String _two(int number) => number.toString().padLeft(2, '0');
