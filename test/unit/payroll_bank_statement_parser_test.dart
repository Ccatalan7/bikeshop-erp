import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/hr/models/payroll_statement_reconciliation.dart';
import 'package:vinabike_erp/modules/hr/services/payroll_bank_statement_parser.dart';

void main() {
  const parser = PayrollBankStatementParser();

  group('PayrollBankStatementParser', () {
    test(
      'preserves the observed transfer beneficiary separately from the description',
      () {
        final result = parser.parseText(
          '14/07/2026 App-traspaso A: Persona Úno '
          r'000101 $128.000 $900.000',
          statementYear: 2026,
        );

        expect(result.rows, hasLength(1));
        final dynamic row = result.rows.single;
        expect(row.description, 'App-traspaso A: Persona Úno');
        expect(row.beneficiaryObserved, 'Persona Úno');
      },
    );

    test('parses debit and credit columns while preserving non-candidates', () {
      final result = parser.parsePages(
        [
          [
            _header(),
            _row(
              date: '14/07',
              description: 'App-traspaso A: Persona Úno',
              document: '000101',
              debit: r'$128.000',
              credit: '-',
              balance: r'$900.000',
            ),
            _row(
              date: '14/07',
              description: 'Transferencia de Cliente Ejemplo',
              document: '000102',
              debit: '-',
              credit: r'$55.000',
              balance: r'$955.000',
            ),
          ].join('\n'),
        ],
        statementYear: 2026,
      );

      expect(result.rows, hasLength(2));
      expect(result.outgoingCandidates, hasLength(1));

      final debit = result.rows.first;
      expect(debit.bookingDate, const PayrollCivilDate(2026, 7, 14));
      expect(debit.debitAmountClp, 128000);
      expect(debit.creditAmountClp, isNull);
      expect(debit.balanceAmountClp, 900000);
      expect(
        debit.direction,
        PayrollStatementMovementDirection.outgoing,
      );
      expect(debit.isOutgoingCandidate, isTrue);
      expect(debit.normalizedDescription, 'app traspaso a persona uno');
      expect(debit.documentNumber, '000101');
      expect(debit.evidence.startPageNumber, 1);
      expect(debit.evidence.sourceRowNumber, 1);

      final credit = result.rows.last;
      expect(credit.debitAmountClp, isNull);
      expect(credit.creditAmountClp, 55000);
      expect(
        credit.direction,
        PayrollStatementMovementDirection.incoming,
      );
      expect(credit.isOutgoingCandidate, isFalse);
    });

    test('joins a split description across pages and skips repeated headers',
        () {
      final result = parser.parsePages(
        [
          [
            _header(),
            _row(
              date: '15/07',
              description: 'App-traspaso A:',
            ),
            'Página 1 de 2',
          ].join('\n'),
          [
            _header(),
            _row(
              description: 'Persona Dos',
              document: '000202',
              debit: r'$72.000',
              credit: '-',
              balance: r'$883.000',
            ),
            'Página 2 de 2',
          ].join('\n'),
        ],
        statementYear: 2026,
      );

      expect(result.rows, hasLength(1));
      final row = result.rows.single;
      expect(row.description, 'App-traspaso A: Persona Dos');
      expect(row.debitAmountClp, 72000);
      expect(row.isOutgoingCandidate, isTrue);
      expect(row.evidence.startPageNumber, 1);
      expect(row.evidence.endPageNumber, 2);
      expect(row.evidence.sourceRowNumber, 1);
    });

    test('parses a flattened transfer row using CLP thousands separators', () {
      final result = parser.parseText(
        '16/07/2026 App-traspaso A: Persona Tres '
        r'000303 $127.750 $800.000',
        statementYear: 2025,
      );

      expect(result.rows, hasLength(1));
      final row = result.rows.single;
      expect(row.bookingDate, const PayrollCivilDate(2026, 7, 16));
      expect(row.description, 'App-traspaso A: Persona Tres');
      expect(row.documentNumber, '000303');
      expect(row.debitAmountClp, 127750);
      expect(row.balanceAmountClp, 800000);
      expect(
        row.direction,
        PayrollStatementMovementDirection.outgoing,
      );
    });

    test('keeps an unstructured dated row for manual review', () {
      final result = parser.parseText(
        '17/07 Movimiento sin columnas legibles',
        statementYear: 2026,
      );

      expect(result.rows, hasLength(1));
      final row = result.rows.single;
      expect(row.isOutgoingCandidate, isFalse);
      expect(row.direction, PayrollStatementMovementDirection.unknown);
      expect(row.parseWarningCodes, contains('unstructured_row'));
      expect(row.parseWarningCodes, contains('missing_transaction_amount'));
      expect(result.warnings, isNotEmpty);
    });

    test(
      'preserves a first monetary movement whose OCR date is missing',
      () {
        final result = parser.parsePages(
          [
            [
              _header(),
              _row(
                description: 'App-traspaso A: Persona Huérfana',
                document: '000401',
                debit: r'$22.000',
                credit: '-',
                balance: r'$778.000',
              ),
              _row(
                date: '18/07',
                description: 'App-traspaso A: Persona Cuatro',
                document: '000402',
                debit: r'$72.000',
                credit: '-',
                balance: r'$706.000',
              ),
            ].join('\n'),
          ],
          statementYear: 2026,
        );

        expect(result.rows, hasLength(2));
        final orphan = result.rows.first;
        expect(orphan.bookingDate, isNull);
        expect(orphan.description, 'App-traspaso A: Persona Huérfana');
        expect(orphan.debitAmountClp, 22000);
        expect(orphan.balanceAmountClp, 778000);
        expect(orphan.direction, PayrollStatementMovementDirection.outgoing);
        expect(orphan.parseWarningCodes, contains('missing_date'));
        expect(orphan.hasCompleteStructuredEvidence, isFalse);
        expect(
          result.warnings.map((warning) => warning.code),
          contains('missing_date'),
        );

        expect(
          result.rows.last.bookingDate,
          const PayrollCivilDate(2026, 7, 18),
        );
        expect(result.rows.last.debitAmountClp, 72000);
      },
    );

    test(
      'splits an intermediate missing-date movement from the preceding row',
      () {
        final result = parser.parsePages(
          [
            [
              _header(),
              _row(
                date: '17/07',
                description: 'App-traspaso A: Persona Cinco',
                document: '000501',
                debit: r'$128.000',
                credit: '-',
                balance: r'$900.000',
              ),
              _row(
                description: 'App-traspaso A: Persona Manager',
                document: '000502',
                debit: r'$22.000',
                credit: '-',
                balance: r'$878.000',
              ),
              _row(
                date: '18/07',
                description: 'App-traspaso A: Persona Seis',
                document: '000503',
                debit: r'$72.000',
                credit: '-',
                balance: r'$806.000',
              ),
            ].join('\n'),
          ],
          statementYear: 2026,
        );

        expect(result.rows, hasLength(3));
        expect(
          result.rows.map((row) => row.debitAmountClp),
          <int?>[128000, 22000, 72000],
        );
        expect(result.rows[1].bookingDate, isNull);
        expect(result.rows[1].description, 'App-traspaso A: Persona Manager');
        expect(result.rows[1].parseWarningCodes, contains('missing_date'));
        expect(result.rows[1].evidence.startLineNumber, 3);
        expect(result.rows[1].evidence.endLineNumber, 3);
      },
    );
  });
}

String _header() {
  return _columns(
    'Fecha',
    'Descripción',
    'Nro Docto',
    'Cargos',
    'Abonos',
    'Saldo',
  );
}

String _row({
  String date = '',
  String description = '',
  String document = '',
  String debit = '',
  String credit = '',
  String balance = '',
}) {
  return _columns(
    date,
    description,
    document,
    debit,
    credit,
    balance,
  );
}

String _columns(
  String date,
  String description,
  String document,
  String debit,
  String credit,
  String balance,
) {
  return date.padRight(10) +
      description.padRight(38) +
      document.padRight(14) +
      debit.padRight(14) +
      credit.padRight(14) +
      balance;
}
