import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/document_emission_date.dart';
import 'package:vinabike_erp/shared/services/invoice_parser_service.dart';

// An electronic invoice prints the SII resolution date before the emission
// date; reading the first date put two purchases in 2014 (2026-10-29).
// Supplier and customer data are invented.
const _dteText = '''
DISTRIBUIDORA EJEMPLO LTDA.
R.U.T.: 76.000.000-0
FACTURA ELECTRONICA
N° 142770
S.I.I. - SANTIAGO CENTRO
Res. 80 del 22-08-2014
Señor(es): TALLER DE PRUEBA SPA
Fecha Emision: 22 de Julio del 2026
Forma de pago: Contado
TOTAL \$ 86.110
Timbre Electrónico SII
''';

void main() {
  final today = DateTime(2026, 10, 30);

  group('DocumentEmissionDate.problem', () {
    test('accepts today, tomorrow and the first day of last year', () {
      expect(DocumentEmissionDate.problem(today, today: today), isNull);
      expect(
        DocumentEmissionDate.problem(DateTime(2026, 10, 31), today: today),
        isNull,
      );
      expect(
        DocumentEmissionDate.problem(DateTime(2025, 1, 1), today: today),
        isNull,
      );
    });

    test('accepts an eleven-month-old AliExpress backfill', () {
      expect(
        DocumentEmissionDate.problem(
          today.subtract(const Duration(days: 330)),
          today: today,
        ),
        isNull,
      );
    });

    test('refuses a date after tomorrow or before last year', () {
      expect(
        DocumentEmissionDate.problem(DateTime(2026, 11, 1), today: today),
        contains('posterior a hoy'),
      );
      expect(
        DocumentEmissionDate.problem(DateTime(2024, 12, 31), today: today),
        contains('este año o del anterior'),
      );
    });

    test('names the SII resolution date', () {
      expect(
        DocumentEmissionDate.problem(DateTime(2014, 8, 22), today: today),
        contains('resolución del SII'),
      );
    });
  });

  group('DocumentEmissionDate.fromText', () {
    test('reads the emission in words and skips the resolution', () {
      expect(DocumentEmissionDate.fromText(_dteText), DateTime(2026, 7, 22));
    });

    test('reads a numeric emission on the label line or the next one', () {
      expect(
        DocumentEmissionDate.fromText('Fecha de Emisión : 21/08/2026'),
        DateTime(2026, 8, 21),
      );
      expect(
        DocumentEmissionDate.fromText('F. EMISION\n21-08-2026\nVencimiento'),
        DateTime(2026, 8, 21),
      );
    });

    test('ignores a resolution printed after the emission', () {
      expect(
        DocumentEmissionDate.fromText(
          'Fecha Emisión: 15.07.2026  Res. Ex. N° 80 del 22-08-2014',
        ),
        DateTime(2026, 7, 15),
      );
    });

    test('returns nothing without the label or with an impossible day', () {
      expect(DocumentEmissionDate.fromText('Res. 80 del 22-08-2014'), isNull);
      expect(
          DocumentEmissionDate.fromText('Fecha Emisión: 31/02/2026'), isNull);
    });
  });

  group('DocumentEmissionDate.sanitize', () {
    test('replaces the resolution date with the labeled emission', () {
      final read =
          ParsedInvoice(date: DateTime(2014, 8, 22), rawText: _dteText);

      final sanitized = DocumentEmissionDate.sanitize(read, today: today);

      expect(sanitized.date, DateTime(2026, 7, 22));
      expect(sanitized.dateNote, contains('Fecha Emisión'));
    });

    test('drops an impossible date and says why when there is no label', () {
      final read = ParsedInvoice(
        date: DateTime(2014, 8, 22),
        rawText: 'FACTURA ELECTRONICA\nRes. 80 del 22-08-2014',
      );

      final sanitized = DocumentEmissionDate.sanitize(read, today: today);

      expect(sanitized.date, isNull);
      expect(sanitized.dateNote, contains('resolución del SII'));
      expect(sanitized.dateNote, contains('Escribe la fecha de emisión'));
    });

    test('keeps a possible date as it was read', () {
      final read =
          ParsedInvoice(date: DateTime(2026, 8, 21), rawText: _dteText);

      final sanitized = DocumentEmissionDate.sanitize(read, today: today);

      expect(sanitized.date, DateTime(2026, 8, 21));
      expect(sanitized.dateNote, isNull);
    });

    test('fills a missing date from the label', () {
      final read = ParsedInvoice(rawText: _dteText);

      final sanitized = DocumentEmissionDate.sanitize(read, today: today);

      expect(sanitized.date, DateTime(2026, 7, 22));
      expect(sanitized.dateNote, isNull);
    });
  });

  test('the camera and PDF parser no longer take the resolution date', () {
    final parsed = InvoiceParserService().parseInvoiceFromText(_dteText);

    expect(parsed.date, DateTime(2026, 7, 22));
  });

  test('the picker range matches the database rule', () {
    expect(DocumentEmissionDate.earliest(today), DateTime(2025, 1, 1));
    expect(DocumentEmissionDate.latest(today), DateTime(2026, 10, 31));
    expect(
      DocumentEmissionDate.clamp(DateTime(2014, 8, 22), today: today),
      DateTime(2025, 1, 1),
    );
  });
}
