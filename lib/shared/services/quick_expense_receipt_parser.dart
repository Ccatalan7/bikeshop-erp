class ParsedQuickExpenseReceipt {
  const ParsedQuickExpenseReceipt({
    this.supplierName,
    this.identifier,
    this.total,
    this.date,
    this.dueDate,
    this.transactionNumber,
    this.authorizationCode,
    this.cub,
    this.paymentMethod,
    this.purchaseDescription,
    this.isDomainService = false,
  });

  final String? supplierName;
  final String? identifier;
  final double? total;
  final DateTime? date;
  final DateTime? dueDate;
  final String? transactionNumber;
  final String? authorizationCode;
  final String? cub;
  final String? paymentMethod;
  final String? purchaseDescription;
  final bool isDomainService;
}

/// Extracts expense fields from payment confirmations that are not tax
/// invoices, including utility portals and NIC Chile's WebPay receipt.
class QuickExpenseReceiptParser {
  const QuickExpenseReceiptParser();

  static const domainExpenseAccountCode = '6207-01';
  static const domainExpenseCategoryName = 'Servicios Digitales';

  bool looksLikePaymentReceipt(String rawText) {
    final text = _receiptSearchText(rawText);
    final hasReceiptWords =
        (text.contains('comprobante') && text.contains('pago')) ||
            text.contains('estado de pago');
    final isWebPayConfirmation = text.contains('webpay') &&
        (text.contains('identificador de pago') ||
            text.contains('codigo de autorizacion'));

    return isWebPayConfirmation ||
        (hasReceiptWords &&
            (text.contains('total pagado') ||
                text.contains('medio de pago') ||
                text.contains('estado de pago') ||
                text.contains('no de comprobante') ||
                text.contains('n de comprobante') ||
                text.contains('n cliente') ||
                text.contains('monto') ||
                text.contains('suministro electrico')));
  }

  bool isGenericSupplierName(String? value) {
    final text = _receiptSearchText(value ?? '');
    return text == 'servicio' ||
        text == 'servicio suministro electrico' ||
        text == 'comprobante de pago' ||
        text == 'oficina virtual';
  }

  ParsedQuickExpenseReceipt parse(
    String rawText, {
    String? fileName,
    DateTime? now,
  }) {
    String? matchText(RegExp pattern) {
      final match = pattern.firstMatch(rawText);
      final value = match?.group(1)?.trim();
      if (value == null || value.isEmpty || _isReceiptLabelText(value)) {
        return null;
      }
      return value;
    }

    final receiptText = _receiptSearchText(rawText);
    final isCgeReceipt = receiptText.contains('cge') ||
        receiptText.contains('suministro electrico');
    final isNicChileReceipt = _looksLikeNicChileReceipt(rawText, receiptText);
    final isWebPayReceipt = receiptText.contains('webpay');
    final rowMatch = RegExp(
      r'^([A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9 .&-]+?)\s+([A-Za-z0-9.-]+)\s+\$?\s*([\d.,]+)\s+(\d{1,2}[-/]\d{1,2}[-/]\d{2,4})\s+([A-Za-z0-9.-]+)\s*$',
      multiLine: true,
    ).firstMatch(rawText);

    final amountValuePattern = RegExp(
      r'\$?\s*([0-9]{1,3}(?:[.,][0-9]{3})+|[0-9]{4,8})(?!\d)',
      caseSensitive: false,
    );
    final idValuePattern = RegExp(
      r'([A-Za-z0-9.-]{4,})',
      caseSensitive: false,
    );
    final referenceValuePattern = RegExp(
      r'([A-Za-z0-9.-]{6,})',
      caseSensitive: false,
    );

    final supplierName = isNicChileReceipt
        ? 'NIC Chile'
        : isCgeReceipt
            ? 'CGE'
            : rowMatch?.group(1)?.trim();
    final identifier = rowMatch?.group(2)?.trim() ??
        matchText(RegExp(
          r'N[°º]\s*Cliente\s*:\s*([A-Za-z0-9.-]+)',
          caseSensitive: false,
        )) ??
        _extractReceiptValue(
          rawText,
          const ['n cliente', 'no cliente'],
          valuePattern: idValuePattern,
        );
    final rowTotal = rowMatch?.group(3)?.trim();
    final dueDate = rowMatch?.group(4)?.trim();
    final rowAuthorization = rowMatch?.group(5)?.trim();
    final receiptDate = matchText(RegExp(
          r'Fecha\s+de\s+Comprobante\s*:\s*(\d{1,2}[-/]\d{1,2}[-/]\d{2,4})',
          caseSensitive: false,
        )) ??
        matchText(RegExp(
          r'\b(\d{1,2}[-/]\d{1,2}[-/]\d{2,4})\s*,\s*\d{1,2}:\d{2}\s*(?:AM|PM)?\b',
          caseSensitive: false,
        )) ??
        matchText(RegExp(
          r'Fecha(?:\s+de\s+la\s+transacci[oó]n)?\s*:\s*(\d{1,2}[-/]\d{1,2}[-/]\d{2,4})',
          caseSensitive: false,
        ));

    final transactionNumber = matchText(
          RegExp(
            r'Identificador\s+de\s+pago\s*:\s*([A-Za-z0-9.-]+)',
            caseSensitive: false,
          ),
        ) ??
        _extractReceiptValue(
          rawText,
          const ['identificador de pago'],
          valuePattern: referenceValuePattern,
          lookAheadLines: 2,
        ) ??
        matchText(
          RegExp(
            r'N[°º]\s*de\s*transacci[oó]n\s*:\s*([A-Za-z0-9.-]+)',
            caseSensitive: false,
          ),
        ) ??
        matchText(
          RegExp(
            r'N[°º]\s*de\s*Comprobante\s*:\s*([A-Za-z0-9.-]+)',
            caseSensitive: false,
          ),
        ) ??
        _extractReceiptValue(
          rawText,
          const [
            'n de comprobante',
            'no de comprobante',
            'numero de comprobante',
          ],
          valuePattern: referenceValuePattern,
          lookAheadLines: 5,
        );
    final authorizationCode = rowAuthorization ??
        matchText(RegExp(
          r'C[oó]digo\s+de\s+autorizaci[oó]n\s*:\s*([A-Za-z0-9.-]+)',
          caseSensitive: false,
        )) ??
        _extractReceiptValue(
          rawText,
          const ['codigo de autorizacion'],
          valuePattern: referenceValuePattern,
          lookAheadLines: 2,
        );
    final parsedDate = _parseOptionalDate(receiptDate) ??
        (isWebPayReceipt
            ? _parseWebPayPartialDate(
                rawText,
                fileName: fileName,
                now: now,
              )
            : null);

    return ParsedQuickExpenseReceipt(
      supplierName: supplierName,
      identifier: identifier,
      total: _parseOptionalAmount(
        matchText(RegExp(
              r'TOTAL\s+PAGADO\s*:\s*\$?\s*([\d.,]+)',
              caseSensitive: false,
            )) ??
            matchText(RegExp(
              r'Monto(?:\s+de\s+la\s+transacci[oó]n)?\s*:\s*\$?\s*([\d.,]+)',
              caseSensitive: false,
            )) ??
            _extractReceiptValue(
              rawText,
              const [
                'monto de la transaccion',
                'monto total',
                'total pagado',
                'monto',
              ],
              valuePattern: amountValuePattern,
              lookAheadLines: 5,
            ) ??
            rowTotal ??
            matchText(RegExp(
              r'TOTAL\s*:\s*\$?\s*([\d.,]+)',
              caseSensitive: false,
            )),
      ),
      date: parsedDate,
      dueDate: _parseOptionalDate(dueDate),
      transactionNumber: transactionNumber,
      authorizationCode: authorizationCode,
      cub: matchText(
        RegExp(r'CUB\s*:\s*([A-Za-z0-9.-]+)', caseSensitive: false),
      ),
      paymentMethod: _paymentMethodHint(receiptText, isCgeReceipt),
      purchaseDescription: _extractPurchaseDescription(rawText),
      isDomainService:
          isNicChileReceipt || receiptText.contains('restauracion de dominio'),
    );
  }

  bool _looksLikeNicChileReceipt(String rawText, String receiptText) {
    if (receiptText.contains('nic chile')) return true;
    if (!receiptText.contains('restauracion de dominio')) return false;
    return receiptText.contains('listado de dominios') ||
        RegExp(r'\b[A-Za-z0-9-]+\.cl\b', caseSensitive: false)
            .hasMatch(rawText);
  }

  String? _paymentMethodHint(String receiptText, bool isCgeReceipt) {
    if (receiptText.contains('webpay debito')) return 'debit';
    if (receiptText.contains('webpay credito')) return 'credit';

    final mentionsDebit = receiptText.contains('debito');
    final mentionsCredit = receiptText.contains('credito');
    if (mentionsDebit && !mentionsCredit) return 'debit';
    if (mentionsCredit && !mentionsDebit) return 'credit';
    if (receiptText.contains('tarjeta') || receiptText.contains('webpay')) {
      return 'card';
    }
    return isCgeReceipt ? 'card' : null;
  }

  String? _extractPurchaseDescription(String rawText) {
    final domainMatch = RegExp(
      r'(?:\d+\s*[.)-]\s*)?Restauraci[oó]n\s+de\s+dominio\s*:\s*([A-Za-z0-9.-]+\.[A-Za-z]{2,})',
      caseSensitive: false,
    ).firstMatch(rawText);
    if (domainMatch != null) {
      return 'Restauración de dominio ${domainMatch.group(1)!.toLowerCase()}';
    }
    return null;
  }

  DateTime? _parseWebPayPartialDate(
    String rawText, {
    String? fileName,
    DateTime? now,
  }) {
    final match = RegExp(
      r'Fecha\s+de\s+la\s+transacci[oó]n\s*:\s*(?:\r?\n\s*)?(\d{1,2})\s*/\s*(\d{1,2})(?!\s*/\s*\d)',
      caseSensitive: false,
    ).firstMatch(rawText);
    if (match == null) return null;

    final first = int.tryParse(match.group(1)!);
    final second = int.tryParse(match.group(2)!);
    if (first == null || second == null) return null;

    // NIC Chile's WebPay confirmation renders this partial value as MM / DD.
    // Retain a defensive DD / MM fallback when the first value cannot be a
    // month, which also tolerates OCR text from other WebPay integrations.
    final month = first > 12 ? second : first;
    final day = first > 12 ? first : second;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;

    final anchor = _dateFromFileName(fileName) ?? now ?? DateTime.now();
    var candidate = _validDate(anchor.year, month, day);
    if (candidate == null) return null;

    // A receipt captured just after New Year may belong to December. Avoid
    // assigning a conspicuously future transaction to the anchor year.
    if (candidate.isAfter(anchor.add(const Duration(days: 31)))) {
      candidate = _validDate(anchor.year - 1, month, day);
    }
    return candidate;
  }

  DateTime? _dateFromFileName(String? fileName) {
    if (fileName == null || fileName.trim().isEmpty) return null;
    final match =
        RegExp(r'\b(20\d{2})[-_](\d{1,2})[-_](\d{1,2})\b').firstMatch(fileName);
    if (match == null) return null;
    return _validDate(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  DateTime? _validDate(int year, int month, int day) {
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return date;
  }

  String _receiptSearchText(String value) {
    return _normalizeSearchText(value)
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _normalizeSearchText(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[áàäâ]'), 'a')
        .replaceAll(RegExp(r'[éèëê]'), 'e')
        .replaceAll(RegExp(r'[íìïî]'), 'i')
        .replaceAll(RegExp(r'[óòöô]'), 'o')
        .replaceAll(RegExp(r'[úùüû]'), 'u')
        .replaceAll('ñ', 'n')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String? _extractReceiptValue(
    String rawText,
    List<String> labels, {
    RegExp? valuePattern,
    int lookAheadLines = 3,
  }) {
    final normalizedLabels = labels.map(_receiptSearchText).toList();
    final lines = rawText
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final normalizedLine = _receiptSearchText(line);
      if (!normalizedLabels.any(normalizedLine.contains)) continue;

      final colonIndex = line.indexOf(RegExp(r'[:：]'));
      if (colonIndex >= 0 && colonIndex < line.length - 1) {
        final sameLineValue = _matchReceiptValue(
          line.substring(colonIndex + 1),
          valuePattern,
        );
        if (sameLineValue != null) return sameLineValue;
      }

      final lastLookAheadLine = (i + lookAheadLines).clamp(0, lines.length - 1);
      for (var j = i + 1; j <= lastLookAheadLine; j++) {
        final nextValue = _matchReceiptValue(lines[j], valuePattern);
        if (nextValue != null) return nextValue;
      }
    }
    return null;
  }

  String? _matchReceiptValue(String value, RegExp? valuePattern) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || _isReceiptLabelText(trimmed)) return null;
    if (valuePattern == null) return trimmed;
    final match = valuePattern.firstMatch(trimmed);
    if (match == null) return null;
    return match.group(match.groupCount >= 1 ? 1 : 0)?.trim();
  }

  bool _isReceiptLabelText(String value) {
    final text = _receiptSearchText(value);
    if (text.isEmpty) return true;
    const labels = [
      'servicio',
      'fecha de comprobante',
      'fecha de la transaccion',
      'identificador de pago',
      'n de comprobante',
      'no de comprobante',
      'numero de comprobante',
      'monto',
      'monto de la transaccion',
      'codigo de autorizacion',
      'estado de pago',
      'oficina virtual',
      'comprobante de pago',
    ];
    return labels.any((label) => text == label);
  }

  double? _parseOptionalAmount(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    var cleaned = value.replaceAll(RegExp(r'[^\d.,]'), '');
    if (cleaned.isEmpty) return null;

    final lastDot = cleaned.lastIndexOf('.');
    final lastComma = cleaned.lastIndexOf(',');
    if (lastDot >= 0 && lastComma >= 0) {
      if (lastDot > lastComma) {
        cleaned = cleaned.replaceAll(',', '');
      } else {
        cleaned = cleaned.replaceAll('.', '').replaceAll(',', '.');
      }
    } else if (lastDot >= 0) {
      final decimals = cleaned.length - lastDot - 1;
      if (decimals == 3) cleaned = cleaned.replaceAll('.', '');
    } else if (lastComma >= 0) {
      final decimals = cleaned.length - lastComma - 1;
      cleaned = decimals == 3
          ? cleaned.replaceAll(',', '')
          : cleaned.replaceAll(',', '.');
    }

    final amount = double.tryParse(cleaned);
    return amount == null || amount <= 0 ? null : amount;
  }

  DateTime? _parseOptionalDate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final match =
        RegExp(r'(\d{1,2})[-/](\d{1,2})[-/](\d{2,4})').firstMatch(value);
    if (match == null) return null;

    var day = int.tryParse(match.group(1)!);
    var month = int.tryParse(match.group(2)!);
    var year = int.tryParse(match.group(3)!);
    if (day == null || month == null || year == null) return null;
    if (month > 12 && day <= 12) {
      final parsedMonth = day;
      day = month;
      month = parsedMonth;
    }
    if (year < 100) year += 2000;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    return _validDate(year, month, day);
  }
}
