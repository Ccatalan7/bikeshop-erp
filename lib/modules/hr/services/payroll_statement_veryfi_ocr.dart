import 'dart:typed_data';

import '../../../shared/services/veryfi_proxy_service.dart';

typedef PayrollStatementVeryfiRequest = Future<Map<String, dynamic>> Function(
  Uint8List bytes,
  String filename,
);

/// Thin Payroll adapter over the ERP's canonical authenticated Veryfi proxy.
///
/// The adapter deliberately returns text only. The source bytes and the full
/// Veryfi response stay in memory for this call and are never written to the
/// Payroll database or to application logs.
class PayrollStatementVeryfiOcr {
  const PayrollStatementVeryfiOcr({PayrollStatementVeryfiRequest? request})
      : _request = request;

  final PayrollStatementVeryfiRequest? _request;

  Future<String> extractText({
    required Uint8List bytes,
    required String filename,
    String? sourcePath,
  }) async {
    final request = _request ?? _invokeCanonicalProxy;
    final response = await request(bytes, filename);
    final text = payrollStatementTextFromVeryfi(response);
    if (text.replaceAll(RegExp(r'\s'), '').length < 50) {
      throw const FormatException(
        'Veryfi no devolvió suficiente texto para interpretar la cartola.',
      );
    }
    return text;
  }

  static Future<Map<String, dynamic>> _invokeCanonicalProxy(
    Uint8List bytes,
    String filename,
  ) {
    return VeryfiProxyService().parseBankStatementFromBytes(bytes, filename);
  }
}

/// Extracts document text without running the invoice adapter or logging raw
/// line maps. Veryfi response shapes vary by document family, so the reader
/// accepts the direct document field first, then page text, then raw row text.
String payrollStatementTextFromVeryfi(Map<String, dynamic> response) {
  const textKeys = <String>[
    'ocr_text',
    'raw_text',
    'full_text',
    'document_text',
    'extracted_text',
    'text',
  ];

  String? directText(Map<dynamic, dynamic> map) {
    for (final key in textKeys) {
      final value = _veryfiFieldValue(map[key]);
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  final structuredTransactions = _veryfiTransactions(response)
      .map(_payrollStatementLineFromVeryfiTransaction)
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (structuredTransactions.isNotEmpty) {
    return structuredTransactions.join('\n');
  }

  final direct = directText(response);
  if (direct != null) return direct;

  final ocr = response['ocr'];
  if (ocr is Map) {
    final nested = directText(ocr);
    if (nested != null) return nested;
  }

  final pageTexts = <String>[];
  final pages = response['pages'];
  if (pages is List) {
    for (final page in pages) {
      if (page is! Map) continue;
      final text = directText(page);
      if (text != null) pageTexts.add(text);
    }
  }
  if (pageTexts.isNotEmpty) return pageTexts.join('\n');

  final rowTexts = <String>[];
  for (final collectionKey in const <String>[
    'line_items',
    'lines',
    'items',
    'transactions',
  ]) {
    final rows = response[collectionKey];
    if (rows is! List) continue;
    for (final row in rows) {
      if (row is! Map) continue;
      final text = directText(row);
      if (text != null) rowTexts.add(text);
    }
    if (rowTexts.isNotEmpty) break;
  }
  return rowTexts.join('\n');
}

List<Map<dynamic, dynamic>> _veryfiTransactions(
  Map<String, dynamic> response,
) {
  final direct = response['transactions'];
  if (direct is List) {
    final rows = direct.whereType<Map>().toList(growable: false);
    if (rows.isNotEmpty) return rows;
  }

  final rows = <Map<dynamic, dynamic>>[];
  final accounts = response['accounts'];
  if (accounts is List) {
    for (final account in accounts.whereType<Map>()) {
      final transactions = account['transactions'];
      if (transactions is List) rows.addAll(transactions.whereType<Map>());
    }
  }
  return rows;
}

dynamic _veryfiFieldValue(dynamic raw) {
  if (raw is Map && raw.containsKey('value')) return raw['value'];
  return raw;
}

String _payrollStatementLineFromVeryfiTransaction(
  Map<dynamic, dynamic> transaction,
) {
  String? textOf(String key) {
    final value = _veryfiFieldValue(transaction[key]);
    final text = value?.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    return text == null || text.isEmpty ? null : text;
  }

  num? numberOf(String key) {
    final value = _veryfiFieldValue(transaction[key]);
    if (value is num) return value;
    return num.tryParse(value?.toString().replaceAll(',', '.') ?? '');
  }

  String? dateOf() {
    final raw = textOf('date') ?? textOf('posted_date');
    if (raw == null) return null;
    final date = DateTime.tryParse(raw);
    if (date == null) return raw;
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year}';
  }

  String amountCell(num? value) {
    if (value == null || value.abs() < 0.5) return '-';
    final digits = value.abs().round().toString();
    final grouped = digits.replaceAllMapped(
      RegExp(r'(?<=\d)(?=(\d{3})+$)'),
      (_) => '.',
    );
    return '${value < 0 ? '-' : ''}\$$grouped';
  }

  final date = dateOf();
  final description = textOf('description') ??
      textOf('vendor') ??
      textOf('category') ??
      textOf('text');
  final document = textOf('transaction_id') ?? textOf('card_number');
  final debit = numberOf('debit_amount');
  final credit = numberOf('credit_amount');
  final balance = numberOf('balance');
  final hasStructuredMovement = debit != null || credit != null;
  if (!hasStructuredMovement) return textOf('text') ?? '';

  return <String>[
    if (date != null) date,
    description ?? 'Movimiento bancario',
    document ?? '-',
    amountCell(debit),
    amountCell(credit),
    amountCell(balance),
  ].join('  ');
}
