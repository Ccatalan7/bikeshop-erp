import '../models/payroll_statement_reconciliation.dart';

/// Parses text already extracted from a Banco de Chile account statement.
///
/// This class deliberately does not read files, call OCR providers, persist
/// data, or log source text. It only turns page text into reviewable rows.
class PayrollBankStatementParser {
  const PayrollBankStatementParser();

  PayrollBankStatementParseResult parseText(
    String extractedText, {
    required int statementYear,
  }) {
    return parsePages(
      extractedText.split('\f'),
      statementYear: statementYear,
    );
  }

  PayrollBankStatementParseResult parsePages(
    List<String> pageTexts, {
    required int statementYear,
  }) {
    if (statementYear <= 0) {
      throw ArgumentError.value(
        statementYear,
        'statementYear',
        'Must be a positive civil year.',
      );
    }

    final parsedRows = <PayrollStatementRow>[];
    final warnings = <PayrollStatementParseWarning>[];
    _StatementRowBuilder? pendingRow;
    _ColumnLayout? activeLayout;
    var sourceRowNumber = 0;

    void finalizePendingRow() {
      final builder = pendingRow;
      if (builder == null) return;

      sourceRowNumber += 1;
      final row = _parseRow(
        builder,
        statementYear: statementYear,
        sourceRowNumber: sourceRowNumber,
      );
      parsedRows.add(row);
      for (final code in row.parseWarningCodes) {
        warnings.add(
          PayrollStatementParseWarning(
            code: code,
            message: _warningMessage(code),
            evidence: row.evidence,
          ),
        );
      }
      pendingRow = null;
    }

    for (var pageIndex = 0; pageIndex < pageTexts.length; pageIndex += 1) {
      final pageNumber = pageIndex + 1;
      final lines = pageTexts[pageIndex]
          .replaceAll('\r\n', '\n')
          .replaceAll('\r', '\n')
          .split('\n');

      for (var lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
        final lineNumber = lineIndex + 1;
        final rawLine = lines[lineIndex].replaceAll('\u00a0', ' ');
        final trimmedLine = rawLine.trim();
        if (trimmedLine.isEmpty) continue;

        final discoveredLayout = _ColumnLayout.tryParse(rawLine);
        if (discoveredLayout != null) {
          activeLayout = discoveredLayout;
          continue;
        }
        if (_isStatementNoise(trimmedLine)) continue;

        final dateMatch = _rowDatePattern.firstMatch(rawLine);
        if (dateMatch != null) {
          finalizePendingRow();
          pendingRow = _StatementRowBuilder(
            dateMatch: dateMatch,
            layout: activeLayout,
            firstLine: _SourceLine(
              pageNumber: pageNumber,
              lineNumber: lineNumber,
              text: rawLine,
            ),
          );
          continue;
        }

        final sourceLine = _SourceLine(
          pageNumber: pageNumber,
          lineNumber: lineNumber,
          text: rawLine,
        );
        if (_hasRecognizedMovement(
          <_SourceLine>[sourceLine],
          activeLayout,
        )) {
          final current = pendingRow;
          if (current == null || current.hasRecognizedMovement) {
            finalizePendingRow();
            pendingRow = _StatementRowBuilder(
              dateMatch: null,
              layout: activeLayout,
              firstLine: sourceLine,
            );
            continue;
          }
        }

        pendingRow?.add(sourceLine);
      }
    }

    finalizePendingRow();
    return PayrollBankStatementParseResult(
      rows: parsedRows,
      warnings: warnings,
    );
  }
}

final RegExp _rowDatePattern = RegExp(
  r'^\s*(\d{1,2})\s*[/.-]\s*(\d{1,2})'
  r'(?:\s*[/.-]\s*(\d{2,4}))?(?=\s|$)',
);

PayrollStatementRow _parseRow(
  _StatementRowBuilder builder, {
  required int statementYear,
  required int sourceRowNumber,
}) {
  final warningCodes = <String>[];
  final evidence = PayrollStatementRowEvidence(
    sourceRowNumber: sourceRowNumber,
    startPageNumber: builder.lines.first.pageNumber,
    startLineNumber: builder.lines.first.lineNumber,
    endPageNumber: builder.lines.last.pageNumber,
    endLineNumber: builder.lines.last.lineNumber,
  );

  final dateMatch = builder.dateMatch;
  final date = dateMatch == null
      ? null
      : _parseCivilDate(
          dateMatch,
          statementYear: statementYear,
        );
  if (dateMatch == null) {
    warningCodes.add('missing_date');
  } else if (date == null) {
    warningCodes.add('invalid_date');
  }

  final fields = _parseFields(builder.lines, builder.layout);

  if (fields.direction == PayrollStatementMovementDirection.unknown) {
    warningCodes.add('ambiguous_direction');
  }
  if (fields.debitAmountClp == null && fields.creditAmountClp == null) {
    warningCodes.add('missing_transaction_amount');
  }
  warningCodes.addAll(fields.warningCodes);

  return PayrollStatementRow(
    bookingDate: date,
    description: fields.description,
    beneficiaryObserved:
        fields.direction == PayrollStatementMovementDirection.outgoing
            ? _extractOutgoingBeneficiary(fields.description)
            : null,
    documentNumber: fields.documentNumber,
    debitAmountClp: fields.debitAmountClp,
    creditAmountClp: fields.creditAmountClp,
    balanceAmountClp: fields.balanceAmountClp,
    direction: fields.direction,
    evidence: evidence,
    parseWarningCodes: warningCodes.toSet().toList(growable: false),
  );
}

String? _extractOutgoingBeneficiary(String description) {
  final text = description.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return null;
  final patterns = <RegExp>[
    RegExp(
      r'^(?:app[\s-]*traspaso|traspaso|transferencia)\s+a\s*:?\s*(.+)$',
      caseSensitive: false,
    ),
    RegExp(
      r'^transferencia\s+enviada\s+a\s*:?\s*(.+)$',
      caseSensitive: false,
    ),
  ];
  for (final pattern in patterns) {
    final candidate = pattern.firstMatch(text)?.group(1)?.trim();
    if (candidate == null || candidate.length < 2 || candidate.length > 160) {
      continue;
    }
    return candidate;
  }
  return null;
}

_ParsedStatementFields _parseFields(
  List<_SourceLine> lines,
  _ColumnLayout? layout,
) {
  final fixedWidthFields =
      layout == null ? null : _parseUsingColumnLayout(lines, layout);
  final fallbackFields = _parseUsingDelimitedText(lines);
  return _preferFields(fixedWidthFields, fallbackFields);
}

bool _hasRecognizedMovement(
  List<_SourceLine> lines,
  _ColumnLayout? layout,
) {
  final fields = _parseFields(lines, layout);
  return fields.debitAmountClp != null || fields.creditAmountClp != null;
}

PayrollCivilDate? _parseCivilDate(
  RegExpMatch match, {
  required int statementYear,
}) {
  final day = int.tryParse(match.group(1) ?? '');
  final month = int.tryParse(match.group(2) ?? '');
  final rawYear = int.tryParse(match.group(3) ?? '');
  if (day == null || month == null) return null;

  var year = rawYear ?? statementYear;
  if (year < 100) year += year >= 70 ? 1900 : 2000;
  if (!PayrollCivilDate.isValid(year, month, day)) return null;
  return PayrollCivilDate(year, month, day);
}

_ParsedStatementFields _preferFields(
  _ParsedStatementFields? fixedWidth,
  _ParsedStatementFields fallback,
) {
  if (fixedWidth == null) return fallback;

  final fixedHasMovement =
      fixedWidth.debitAmountClp != null || fixedWidth.creditAmountClp != null;
  final fallbackHasMovement =
      fallback.debitAmountClp != null || fallback.creditAmountClp != null;
  if (!fixedHasMovement && fallbackHasMovement) return fallback;
  if (fixedWidth.direction == PayrollStatementMovementDirection.unknown &&
      fallback.direction != PayrollStatementMovementDirection.unknown &&
      fallbackHasMovement) {
    return fallback;
  }

  final description = fixedWidth.description.isNotEmpty
      ? fixedWidth.description
      : fallback.description;
  if (fixedHasMovement) {
    return _ParsedStatementFields(
      description: description,
      documentNumber: fixedWidth.documentNumber ?? fallback.documentNumber,
      debitAmountClp: fixedWidth.debitAmountClp,
      creditAmountClp: fixedWidth.creditAmountClp,
      balanceAmountClp:
          fixedWidth.balanceAmountClp ?? fallback.balanceAmountClp,
      direction: fixedWidth.direction,
      warningCodes: fixedWidth.warningCodes,
    );
  }
  return _ParsedStatementFields(
    description: description,
    documentNumber: fixedWidth.documentNumber ?? fallback.documentNumber,
    debitAmountClp: fixedWidth.debitAmountClp ?? fallback.debitAmountClp,
    creditAmountClp: fixedWidth.creditAmountClp ?? fallback.creditAmountClp,
    balanceAmountClp: fixedWidth.balanceAmountClp ?? fallback.balanceAmountClp,
    direction: fixedWidth.direction != PayrollStatementMovementDirection.unknown
        ? fixedWidth.direction
        : fallback.direction,
    warningCodes: <String>{
      ...fixedWidth.warningCodes,
      ...fallback.warningCodes,
    }.toList(growable: false),
  );
}

_ParsedStatementFields? _parseUsingColumnLayout(
  List<_SourceLine> lines,
  _ColumnLayout layout,
) {
  final descriptions = <String>[];
  final documentParts = <String>[];
  final debitParts = <String>[];
  final creditParts = <String>[];
  final balanceParts = <String>[];

  for (final sourceLine in lines) {
    final columns = layout.read(sourceLine.text);
    _appendIfPresent(descriptions, columns.description);
    _appendIfPresent(documentParts, columns.documentNumber);
    _appendIfPresent(debitParts, columns.debit);
    _appendIfPresent(creditParts, columns.credit);
    _appendIfPresent(balanceParts, columns.balance);
  }

  final debit = _parseClpCell(debitParts.join(' '));
  final credit = _parseClpCell(creditParts.join(' '));
  final balance = _parseClpCell(balanceParts.join(' '));
  final hasRecognizedAmount =
      debit.recognized || credit.recognized || balance.recognized;
  if (!hasRecognizedAmount) return null;

  final debitAmount = debit.amountClp;
  final creditAmount = credit.amountClp;
  final direction = _directionFromColumns(
    debitAmountClp: debitAmount,
    creditAmountClp: creditAmount,
  );
  return _ParsedStatementFields(
    description: _cleanDescription(descriptions.join(' ')),
    documentNumber: _cleanDocumentNumber(documentParts.join(' ')),
    debitAmountClp: debitAmount,
    creditAmountClp: creditAmount,
    balanceAmountClp: balance.amountClp,
    direction: direction,
  );
}

_ParsedStatementFields _parseUsingDelimitedText(List<_SourceLine> lines) {
  final cells = <String>[];
  for (var index = 0; index < lines.length; index += 1) {
    var text = lines[index].text;
    if (index == 0) {
      text = text.replaceFirst(_rowDatePattern, '').trimLeft();
    }
    final lineCells = text
        .trim()
        .split(RegExp(r'(?:\t+|\s{2,})'))
        .map((cell) => cell.trim())
        .where((cell) => cell.isNotEmpty);
    cells.addAll(lineCells);
  }

  final structured = _parseStructuredCells(cells);
  if (structured != null) return structured;

  final flattened = lines.asMap().entries.map((entry) {
    if (entry.key == 0) {
      return entry.value.text.replaceFirst(_rowDatePattern, '');
    }
    return entry.value.text;
  }).join(' ');
  return _parseFlattenedRow(flattened);
}

_ParsedStatementFields? _parseStructuredCells(List<String> cells) {
  if (cells.isEmpty) {
    return const _ParsedStatementFields(
      description: '',
      documentNumber: null,
      debitAmountClp: null,
      creditAmountClp: null,
      balanceAmountClp: null,
      direction: PayrollStatementMovementDirection.unknown,
    );
  }

  final amountCellIndices = <int>[];
  for (var index = cells.length - 1; index >= 0; index -= 1) {
    if (_looksLikeStatementAmountCell(cells[index])) {
      amountCellIndices.add(index);
      if (amountCellIndices.length == 3) break;
    }
  }
  if (amountCellIndices.length < 2) return null;

  final orderedAmountIndices = amountCellIndices.reversed.toList();
  final firstAmountIndex = orderedAmountIndices.first;
  final amountCells = orderedAmountIndices
      .map((index) => _parseClpCell(cells[index]))
      .toList(growable: false);

  String? documentNumber;
  var descriptionEnd = firstAmountIndex;
  if (descriptionEnd > 0 &&
      _looksLikeDocumentNumber(cells[descriptionEnd - 1])) {
    documentNumber = _cleanDocumentNumber(cells[descriptionEnd - 1]);
    descriptionEnd -= 1;
  }
  final description = _cleanDescription(
    cells.take(descriptionEnd).join(' '),
  );

  if (amountCells.length >= 3) {
    final debit = amountCells[0].amountClp;
    final credit = amountCells[1].amountClp;
    return _ParsedStatementFields(
      description: description,
      documentNumber: documentNumber,
      debitAmountClp: debit,
      creditAmountClp: credit,
      balanceAmountClp: amountCells[2].amountClp,
      direction: _directionFromColumns(
        debitAmountClp: debit,
        creditAmountClp: credit,
      ),
    );
  }

  return _fieldsFromSingleTransactionAmount(
    description: description,
    documentNumber: documentNumber,
    transactionCell: amountCells[0],
    balanceCell: amountCells[1],
  );
}

_ParsedStatementFields _parseFlattenedRow(String flattened) {
  final cleanText = flattened.replaceAll(RegExp(r'\s+'), ' ').trim();
  final amountMatches = _formattedAmountPattern.allMatches(cleanText).toList();
  if (amountMatches.length < 2) {
    return _ParsedStatementFields(
      description: _cleanDescription(cleanText),
      documentNumber: null,
      debitAmountClp: null,
      creditAmountClp: null,
      balanceAmountClp: null,
      direction: PayrollStatementMovementDirection.unknown,
      warningCodes: const ['unstructured_row'],
    );
  }

  final balanceMatch = amountMatches.last;
  final transactionMatch = amountMatches[amountMatches.length - 2];
  final prefix = cleanText.substring(0, transactionMatch.start).trim();
  final documentMatch =
      RegExp(r'(?:^|\s)([A-Za-z0-9-]{3,})\s*$').firstMatch(prefix);
  final documentNumber = documentMatch?.group(1);
  final description = _cleanDescription(
    documentMatch == null
        ? prefix
        : prefix.substring(0, documentMatch.start).trim(),
  );

  return _fieldsFromSingleTransactionAmount(
    description: description,
    documentNumber: _cleanDocumentNumber(documentNumber ?? ''),
    transactionCell: _parseClpCell(transactionMatch.group(0) ?? ''),
    balanceCell: _parseClpCell(balanceMatch.group(0) ?? ''),
  );
}

_ParsedStatementFields _fieldsFromSingleTransactionAmount({
  required String description,
  required String? documentNumber,
  required _ParsedClpCell transactionCell,
  required _ParsedClpCell balanceCell,
}) {
  final inferredDirection = _inferDirection(description);
  final transactionAmount = transactionCell.amountClp;

  return _ParsedStatementFields(
    description: description,
    documentNumber: documentNumber,
    debitAmountClp:
        inferredDirection == PayrollStatementMovementDirection.outgoing
            ? transactionAmount
            : null,
    creditAmountClp:
        inferredDirection == PayrollStatementMovementDirection.incoming
            ? transactionAmount
            : null,
    balanceAmountClp: balanceCell.amountClp,
    direction: inferredDirection,
    warningCodes: inferredDirection == PayrollStatementMovementDirection.unknown
        ? const ['direction_not_inferred']
        : const [],
  );
}

PayrollStatementMovementDirection _directionFromColumns({
  required int? debitAmountClp,
  required int? creditAmountClp,
}) {
  final hasDebit = debitAmountClp != null && debitAmountClp > 0;
  final hasCredit = creditAmountClp != null && creditAmountClp > 0;
  if (hasDebit && !hasCredit) {
    return PayrollStatementMovementDirection.outgoing;
  }
  if (hasCredit && !hasDebit) {
    return PayrollStatementMovementDirection.incoming;
  }
  return PayrollStatementMovementDirection.unknown;
}

PayrollStatementMovementDirection _inferDirection(String description) {
  final normalized = normalizePayrollReconciliationText(description);
  const incomingMarkers = <String>[
    'app traspaso de',
    'traspaso de',
    'transferencia de',
    'transferencia recibida',
    'abono',
    'deposito',
  ];
  if (incomingMarkers.any(normalized.contains)) {
    return PayrollStatementMovementDirection.incoming;
  }

  const outgoingMarkers = <String>[
    'app traspaso a',
    'traspaso a',
    'transferencia a',
    'transferencia enviada',
    'pago',
    'compra',
    'giro',
    'cargo',
    'comision',
    'impuesto',
    'pac',
    'pat',
  ];
  if (outgoingMarkers.any(normalized.contains)) {
    return PayrollStatementMovementDirection.outgoing;
  }
  return PayrollStatementMovementDirection.unknown;
}

_ParsedClpCell _parseClpCell(String value) {
  var text = value.trim();
  if (text.isEmpty) return const _ParsedClpCell.unrecognized();
  if (RegExp(r'^(?:-|—|–)$').hasMatch(text)) {
    return const _ParsedClpCell(amountClp: null, recognized: true);
  }

  var negative = false;
  if (text.startsWith('(') && text.endsWith(')')) {
    negative = true;
    text = text.substring(1, text.length - 1);
  }
  if (text.contains('-')) negative = true;

  text = text
      .replaceAll(RegExp(r'clp', caseSensitive: false), '')
      .replaceAll(r'$', '')
      .replaceAll(' ', '')
      .replaceAll('.', '')
      .replaceAll('-', '')
      .replaceAll('+', '');
  if (text.contains(',')) {
    final parts = text.split(',');
    if (parts.length != 2 || !RegExp(r'^0+$').hasMatch(parts.last)) {
      return const _ParsedClpCell.unrecognized();
    }
    text = parts.first;
  }
  if (!RegExp(r'^\d+$').hasMatch(text)) {
    return const _ParsedClpCell.unrecognized();
  }

  final amount = int.tryParse(text);
  if (amount == null) return const _ParsedClpCell.unrecognized();
  return _ParsedClpCell(
    amountClp: negative ? -amount : amount,
    recognized: true,
  );
}

bool _looksLikeDocumentNumber(String value) {
  final compact = value.replaceAll(' ', '');
  if (compact.isEmpty || compact.contains(r'$') || compact.contains('.')) {
    return false;
  }
  return RegExp(r'^[A-Za-z0-9-]{1,24}$').hasMatch(compact);
}

bool _looksLikeStatementAmountCell(String value) {
  final text = value.trim();
  if (RegExp(r'^(?:-|—|–)$').hasMatch(text)) return true;
  return text.contains(r'$') ||
      text.toLowerCase().contains('clp') ||
      text.contains('.') ||
      text.contains(',') ||
      text.startsWith('+') ||
      text.startsWith('-') ||
      (text.startsWith('(') && text.endsWith(')'));
}

String? _cleanDocumentNumber(String value) {
  final cleaned = value.replaceAll(RegExp(r'\s+'), '').trim();
  return cleaned.isEmpty ? null : cleaned;
}

String _cleanDescription(String value) {
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

void _appendIfPresent(List<String> destination, String value) {
  final cleaned = value.trim();
  if (cleaned.isNotEmpty) destination.add(cleaned);
}

bool _isStatementNoise(String line) {
  final normalized = normalizePayrollReconciliationText(line);
  if (normalized.isEmpty) return true;
  if (const <String>{
    'fecha',
    'descripcion',
    'nro docto',
    'n docto',
    'cargos',
    'abonos',
    'saldo',
  }.contains(normalized)) {
    return true;
  }
  if (RegExp(r'^(pagina|page) \d+( de \d+)?$').hasMatch(normalized)) {
    return true;
  }

  return normalized == 'banco de chile' ||
      normalized.startsWith('cartola cuenta') ||
      normalized.startsWith('cartola bancaria') ||
      normalized.startsWith('movimientos de cuenta') ||
      normalized.startsWith('informese sobre la garantia estatal') ||
      normalized.startsWith('2015 banco de chile') ||
      normalized.startsWith('todos los derechos reservados') ||
      normalized.startsWith('www bancochile cl') ||
      normalized.startsWith('servicio al cliente') ||
      normalized.startsWith('saldo anterior') ||
      normalized.startsWith('saldo inicial');
}

String _warningMessage(String code) {
  return switch (code) {
    'missing_date' =>
      'The monetary row was preserved but its date was not recognized.',
    'invalid_date' => 'The row date is not a valid civil date.',
    'ambiguous_direction' =>
      'The row could not be classified as a debit or credit.',
    'missing_transaction_amount' =>
      'The row has no recognized debit or credit amount.',
    'direction_not_inferred' =>
      'A flattened row did not preserve enough information to infer direction.',
    'unstructured_row' =>
      'The dated row did not preserve the expected statement columns.',
    _ => 'The statement row needs manual review.',
  };
}

final RegExp _formattedAmountPattern = RegExp(
  r'(?:CLP\s*)?\$?\s*-?\d{1,3}(?:\.\d{3})+(?:,0+)?',
  caseSensitive: false,
);

class _SourceLine {
  final int pageNumber;
  final int lineNumber;
  final String text;

  const _SourceLine({
    required this.pageNumber,
    required this.lineNumber,
    required this.text,
  });
}

class _StatementRowBuilder {
  final RegExpMatch? dateMatch;
  final _ColumnLayout? layout;
  final List<_SourceLine> lines;

  _StatementRowBuilder({
    required this.dateMatch,
    required this.layout,
    required _SourceLine firstLine,
  }) : lines = <_SourceLine>[firstLine];

  void add(_SourceLine line) => lines.add(line);

  bool get hasRecognizedMovement => _hasRecognizedMovement(lines, layout);
}

class _ColumnLayout {
  final int descriptionStart;
  final int documentStart;
  final int debitStart;
  final int creditStart;
  final int balanceStart;

  const _ColumnLayout({
    required this.descriptionStart,
    required this.documentStart,
    required this.debitStart,
    required this.creditStart,
    required this.balanceStart,
  });

  static _ColumnLayout? tryParse(String line) {
    final description = RegExp(
      r'descripci[oó]n',
      caseSensitive: false,
    ).firstMatch(line);
    final document = RegExp(
      r'n(?:ro|[°º])?\.?\s*docto\.?',
      caseSensitive: false,
    ).firstMatch(line);
    final debit = RegExp(r'cargos?', caseSensitive: false).firstMatch(line);
    final credit = RegExp(r'abonos?', caseSensitive: false).firstMatch(line);
    final balance = RegExp(r'saldo', caseSensitive: false).firstMatch(line);
    if (description == null ||
        document == null ||
        debit == null ||
        credit == null ||
        balance == null) {
      return null;
    }
    if (!(description.start < document.start &&
        document.start < debit.start &&
        debit.start < credit.start &&
        credit.start < balance.start)) {
      return null;
    }

    return _ColumnLayout(
      // Banco de Chile right-aligns the header a few PDF points after row
      // values. Leave a small gutter so the first letters are not clipped.
      descriptionStart:
          description.start >= 3 ? description.start - 3 : description.start,
      documentStart: document.start,
      debitStart: debit.start,
      creditStart: credit.start,
      balanceStart: balance.start,
    );
  }

  _ColumnValues read(String line) {
    return _ColumnValues(
      description: _slice(line, descriptionStart, documentStart),
      documentNumber: _slice(line, documentStart, debitStart),
      debit: _slice(line, debitStart, creditStart),
      credit: _slice(line, creditStart, balanceStart),
      balance: _slice(line, balanceStart, line.length),
    );
  }

  String _slice(String value, int start, int end) {
    if (start >= value.length) return '';
    final safeEnd = end > value.length ? value.length : end;
    return value.substring(start, safeEnd).trim();
  }
}

class _ColumnValues {
  final String description;
  final String documentNumber;
  final String debit;
  final String credit;
  final String balance;

  const _ColumnValues({
    required this.description,
    required this.documentNumber,
    required this.debit,
    required this.credit,
    required this.balance,
  });
}

class _ParsedClpCell {
  final int? amountClp;
  final bool recognized;

  const _ParsedClpCell({
    required this.amountClp,
    required this.recognized,
  });

  const _ParsedClpCell.unrecognized()
      : amountClp = null,
        recognized = false;
}

class _ParsedStatementFields {
  final String description;
  final String? documentNumber;
  final int? debitAmountClp;
  final int? creditAmountClp;
  final int? balanceAmountClp;
  final PayrollStatementMovementDirection direction;
  final List<String> warningCodes;

  const _ParsedStatementFields({
    required this.description,
    required this.documentNumber,
    required this.debitAmountClp,
    required this.creditAmountClp,
    required this.balanceAmountClp,
    required this.direction,
    this.warningCodes = const [],
  });
}
