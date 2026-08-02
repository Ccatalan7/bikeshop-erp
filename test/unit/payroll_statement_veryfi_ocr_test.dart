import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/hr/services/payroll_bank_statement_parser.dart';
import 'package:vinabike_erp/modules/hr/services/payroll_statement_veryfi_ocr.dart';

void main() {
  test('uses the canonical top-level OCR text without serializing other data',
      () {
    final text = payrollStatementTextFromVeryfi(<String, dynamic>{
      'ocr_text': 'Cuenta corriente 123\n27/07/2026 Transferencia 10.000',
      'vendor': <String, dynamic>{'name': 'must not be appended'},
    });

    expect(text, contains('Cuenta corriente'));
    expect(text, isNot(contains('must not be appended')));
  });

  test('falls back to ordered page text and then row text', () {
    expect(
      payrollStatementTextFromVeryfi(<String, dynamic>{
        'pages': <Map<String, dynamic>>[
          <String, dynamic>{'text': 'página uno'},
          <String, dynamic>{'ocr_text': 'página dos'},
        ],
      }),
      'página uno\npágina dos',
    );
    expect(
      payrollStatementTextFromVeryfi(<String, dynamic>{
        'line_items': <Map<String, dynamic>>[
          <String, dynamic>{'text': 'fila uno'},
          <String, dynamic>{'raw_text': 'fila dos'},
        ],
      }),
      'fila uno\nfila dos',
    );
  });

  test('normalizes Veryfi bank transactions into the existing parser contract',
      () {
    final text = payrollStatementTextFromVeryfi(<String, dynamic>{
      'transactions': <Map<String, dynamic>>[
        <String, dynamic>{
          'date': <String, dynamic>{'value': '2026-07-14'},
          'description': <String, dynamic>{
            'value': 'App-traspaso A: Persona Úno',
          },
          'transaction_id': <String, dynamic>{'value': '000101'},
          'debit_amount': <String, dynamic>{'value': 128000},
          'credit_amount': <String, dynamic>{'value': null},
          'balance': <String, dynamic>{'value': 900000},
        },
      ],
    });

    expect(
      text,
      r'14/07/2026  App-traspaso A: Persona Úno  000101  $128.000  -  $900.000',
    );
    final parsed = const PayrollBankStatementParser().parseText(
      text,
      statementYear: 2026,
    );
    expect(parsed.rows, hasLength(1));
    expect(parsed.rows.single.debitAmountClp, 128000);
    expect(parsed.rows.single.beneficiaryObserved, 'Persona Úno');
  });

  test('adapter calls the existing proxy boundary once and rejects empty OCR',
      () async {
    var calls = 0;
    final adapter = PayrollStatementVeryfiOcr(
      request: (bytes, filename) async {
        calls += 1;
        expect(bytes, hasLength(3));
        expect(filename, 'cartola.png');
        return <String, dynamic>{'ocr_text': 'sin texto útil'};
      },
    );

    await expectLater(
      adapter.extractText(
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
        filename: 'cartola.png',
      ),
      throwsA(isA<FormatException>()),
    );
    expect(calls, 1);
  });
}
