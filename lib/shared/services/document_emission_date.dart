import 'invoice_parser_service.dart';

/// Una fecha de emisión leída de un documento tiene que poder ser cierta
/// (`docs/architecture/ai-document-reading.md`, regla 8).
///
/// Es el mismo criterio que `purchase_document_date_problem` en la base
/// (migración 20261030010000), que lo vuelve a aplicar al guardar una compra:
/// no después de mañana ni antes del 1 de enero del año pasado. El
/// 2026-10-29 dos facturas de TeknoBike quedaron en 2014 porque el lector
/// devolvió la fecha de la resolución del SII («Res. 80 del 22-08-2014»),
/// impresa en toda factura electrónica, y el formulario la copió sin revisar.
class DocumentEmissionDate {
  const DocumentEmissionDate._();

  static const _months = <String, int>{
    'enero': 1,
    'febrero': 2,
    'marzo': 3,
    'abril': 4,
    'mayo': 5,
    'junio': 6,
    'julio': 7,
    'agosto': 8,
    'septiembre': 9,
    'setiembre': 9,
    'octubre': 10,
    'noviembre': 11,
    'diciembre': 12,
  };

  static final _emissionLabel = RegExp(
    r'(?:fecha\s*(?:de\s*)?|f\.\s*)emisi[oó]n',
    caseSensitive: false,
  );
  static final _numericDate = RegExp(
    r'(\d{1,2})\s*[/\-.]\s*(\d{1,2})\s*[/\-.]\s*(\d{4})',
  );
  static final _wordsDate = RegExp(
    r'(\d{1,2})\s+de\s+([a-záéíóúñ]+)\s+del?\s+(\d{4})',
    caseSensitive: false,
  );
  static final _siiResolution = RegExp(
    r'\bres\b\.?|resoluci[oó]n|timbre',
    caseSensitive: false,
  );

  /// Primer día aceptado: el 1 de enero del año pasado.
  static DateTime earliest(DateTime today) => DateTime(today.year - 1, 1, 1);

  /// Último día aceptado: mañana.
  static DateTime latest(DateTime today) =>
      DateTime(today.year, today.month, today.day + 1);

  /// Por qué [date] no puede ser la emisión de un documento que se registra
  /// [today], o null si puede serlo.
  static String? problem(DateTime date, {DateTime? today}) {
    final now = today ?? DateTime.now();
    final day = DateTime(date.year, date.month, date.day);
    if (day.isAfter(latest(now))) {
      return 'La fecha ${_format(day)} es posterior a hoy.';
    }
    final first = earliest(now);
    if (day.isBefore(first)) {
      if (day == DateTime(2014, 8, 22)) {
        return 'El 22/08/2014 es la resolución del SII que traen impresa las '
            'facturas electrónicas, no la emisión.';
      }
      return 'La fecha ${_format(day)} es anterior al ${_format(first)}: una '
          'compra se registra con fecha de este año o del anterior.';
    }
    return null;
  }

  /// Ajusta [date] al rango aceptado, para abrir un selector de fecha.
  static DateTime clamp(DateTime date, {DateTime? today}) {
    final now = today ?? DateTime.now();
    final first = earliest(now);
    final last = latest(now);
    if (date.isBefore(first)) return first;
    if (date.isAfter(last)) return last;
    return date;
  }

  /// La fecha escrita junto a «Fecha Emisión», en la misma línea o en la
  /// siguiente, en números («22-07-2026») o en palabras («22 de Julio del
  /// 2026»). Una línea de la resolución del SII nunca es la emisión.
  static DateTime? fromText(String text) {
    final lines = text.split('\n');
    for (var index = 0; index < lines.length; index++) {
      final label = _emissionLabel.firstMatch(lines[index]);
      if (label == null) continue;
      final candidates = [
        lines[index].substring(label.end),
        if (index + 1 < lines.length) lines[index + 1],
      ];
      for (final candidate in candidates) {
        final resolution = _siiResolution.firstMatch(candidate);
        final date = _firstDate(
          resolution == null
              ? candidate
              : candidate.substring(0, resolution.start),
        );
        if (date != null) return date;
      }
    }
    return null;
  }

  /// Si [line] habla de la resolución del SII, su fecha no es la emisión.
  static bool isSiiResolutionLine(String line) => _siiResolution.hasMatch(line);

  /// La lectura con una fecha que puede ser cierta. Si la leída no puede
  /// serlo, se usa la que está junto a «Fecha Emisión»; si tampoco hay, la
  /// lectura queda sin fecha y [ParsedInvoice.dateNote] dice por qué, para
  /// que la persona escriba la emisión.
  static ParsedInvoice sanitize(ParsedInvoice invoice, {DateTime? today}) {
    final read = invoice.date;
    final readProblem = read == null ? null : problem(read, today: today);
    if (read != null && readProblem == null) return invoice;

    final labeled = fromText(invoice.rawText);
    if (labeled != null && problem(labeled, today: today) == null) {
      return invoice.copyWith(
        date: labeled,
        dateNote: read == null
            ? null
            : 'Se usó la fecha junto a «Fecha Emisión». $readProblem',
      );
    }
    if (read == null) return invoice;
    return invoice.copyWith(
      clearDate: true,
      dateNote: '$readProblem Escribe la fecha de emisión del documento.',
    );
  }

  static DateTime? _firstDate(String text) {
    final numeric = _numericDate.firstMatch(text);
    final words = _wordsDate.firstMatch(text);
    final useWords =
        words != null && (numeric == null || words.start < numeric.start);
    if (useWords) {
      final month = _months[words.group(2)!.toLowerCase()];
      if (month == null) return null;
      return _valid(
        int.parse(words.group(3)!),
        month,
        int.parse(words.group(1)!),
      );
    }
    if (numeric == null) return null;
    return _valid(
      int.parse(numeric.group(3)!),
      int.parse(numeric.group(2)!),
      int.parse(numeric.group(1)!),
    );
  }

  static DateTime? _valid(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  static String _format(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}
