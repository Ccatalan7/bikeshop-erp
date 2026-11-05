import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:timezone/timezone.dart' as tz;

import '../../shared/utils/shop_zone.dart';
import '../models/storefront_logo_source.dart';

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

/// Where a customer document takes the store's logo from: the same order as
/// the site (`storefrontFirstLogoSource`) — the site's logo, the tenant's,
/// and for the canonical store the bundled one, as a web path
/// (`assets/assets/images/…`). Null: the store's name in letters.
///
/// The documents drew the name in letters until 2026-11-04, when the owner
/// saw the first delivery document: «¿qué es ese logo…? ¿cómo es posible que
/// a esta altura del proyecto aún no sepas cuál es el logo de la empresa?».
String? storeDocumentLogoSource({String? identityLogoUrl, String? tenantId}) {
  final source = storefrontFirstLogoSource(
    configuredUrl: identityLogoUrl ?? '',
    tenantId: tenantId,
  );
  return source.isEmpty ? null : source;
}

/// The logo's bytes as a drawable image, or null when they are not one (the
/// letterhead then writes the name).
///
/// The margin the file carries around the mark is trimmed: the bundled logo
/// keeps about 5 % of empty canvas on the left, which set the letterhead
/// visibly inside the text below it.
pw.ImageProvider? storeDocumentLogoImage(Uint8List? bytes) {
  if (bytes == null || bytes.isEmpty) return null;
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      return null;
    }
    final trimmed = img.trim(
      decoded,
      mode: decoded.hasAlpha
          ? img.TrimMode.transparent
          : img.TrimMode.topLeftColor,
    );
    final drawn = trimmed.width > 1 && trimmed.height > 1 ? trimmed : decoded;
    return pw.MemoryImage(img.encodePng(drawn));
  } catch (_) {
    return null;
  }
}

/// The store's letterhead: its [logo] when there is one, its name in letters
/// otherwise, with the tagline below on the first page.
pw.Widget storeDocumentWordmark(
  String storeName,
  String? tagline, {
  bool compact = false,
  pw.ImageProvider? logo,
}) {
  final pw.Widget mark;
  if (logo != null) {
    final height = compact ? 14.0 : 34.0;
    final aspect = (logo.width ?? 4) / (logo.height ?? 1);
    mark = pw.SizedBox(
      height: height,
      width: (height * aspect).clamp(height, compact ? 90.0 : 220.0),
      child: pw.Image(
        logo,
        fit: pw.BoxFit.contain,
        alignment: pw.Alignment.centerLeft,
      ),
    );
  } else {
    mark = pw.Text(
      storeName.toUpperCase(),
      style: pw.TextStyle(
        color: storeDocumentBrand,
        fontSize: compact ? 12 : 23,
        fontWeight: pw.FontWeight.bold,
        letterSpacing: 0.8,
      ),
    );
  }
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      mark,
      if (!compact && tagline != null) ...[
        pw.SizedBox(height: logo != null ? 8 : 4),
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

/// `18 de noviembre de 2026` on the shop's clock: how a date the customer
/// has to remember reads (the end of a warranty).
String storeDocumentLongDate(DateTime value) {
  final local = _shopTime(value);
  return '${local.day} de ${_monthNames[local.month - 1]} de ${local.year}';
}

const _monthNames = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];

tz.TZDateTime _shopTime(DateTime value) =>
    tz.TZDateTime.from(value.toUtc(), shopLocation());

String _two(int number) => number.toString().padLeft(2, '0');
