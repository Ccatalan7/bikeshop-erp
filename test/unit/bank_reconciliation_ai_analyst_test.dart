import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/accounting/bank_reconciliation/models/bank_reconciliation_models.dart';
import 'package:vinabike_erp/modules/accounting/bank_reconciliation/services/bank_reconciliation_ai_analyst.dart';

BankStatementMovement _movement(
  String id,
  BankCivilDate date,
  BankMovementDirection direction,
  int amount,
  String description,
) =>
    BankStatementMovement(
      sourceRowId: id,
      ordinal: 1,
      bookingDate: date,
      description: description,
      normalizedDescription: description.toLowerCase(),
      direction: direction,
      amountClp: amount,
      sourcePage: 1,
      sourceLineStart: 1,
      sourceLineEnd: 1,
    );

BankReconciliationCandidate _salary(String id, int amount, String who) =>
    BankReconciliationCandidate(
      targetKind: BankReconciliationTargetKind.expensePayment,
      targetId: id,
      direction: BankMovementDirection.debit,
      amountClp: amount,
      occurredOn: const BankCivilDate(2026, 8, 12),
      label: 'Gasto $id',
      counterparty: 'Proveedor',
      counterpartyNames: [who],
    );

final _options = BankReconciliationWorkspaceOptions(
  accounts: const [
    BankReconciliationLedgerAccountOption(
      accountId: 'fees',
      code: '6103',
      name: 'Honorarios Profesionales',
      type: 'expense',
    ),
    BankReconciliationLedgerAccountOption(
      accountId: 'vat',
      code: '2150',
      name: 'IVA Débito Fiscal',
      type: 'liability',
    ),
    BankReconciliationLedgerAccountOption(
      accountId: 'partner',
      code: '3102',
      name: 'Aportes de socio · Claudio Catalán',
      type: 'equity',
    ),
  ],
  paymentMethods: const [
    BankReconciliationPaymentMethodOption(
      paymentMethodId: 'transfer-id',
      code: 'transfer',
      name: 'Transferencia',
      accountId: 'bank',
    ),
  ],
  suppliers: const [
    BankReconciliationSupplierOption(supplierId: 'pedro', name: 'Pedro Madrid'),
  ],
);

BankReconciliationPreparedDraft _draft() => BankReconciliationPreparedDraft(
      fileSha256: 'a' * 64,
      filename: 'cartola julio.pdf',
      sourceType: 'pdf_text',
      parserName: 'banco_chile_statement',
      parserVersion: 'v1',
      rows: [
        BankReconciliationRowDraft(
          movement: _movement(
              'mother',
              const BankCivilDate(2026, 7, 7),
              BankMovementDirection.debit,
              133000,
              'App-traspaso A: Maria Angelica Sandoval'),
          proposals: const [],
        ),
        BankReconciliationRowDraft(
          movement: _movement(
              'repay',
              const BankCivilDate(2026, 8, 17),
              BankMovementDirection.debit,
              214685,
              'App-traspaso A: Maria Angelica Sandoval'),
          proposals: const [],
        ),
        BankReconciliationRowDraft(
          movement: _movement(
              'owner',
              const BankCivilDate(2026, 8, 11),
              BankMovementDirection.credit,
              700000,
              'Traspaso De: Claudio Angel Catalan'),
          proposals: const [],
        ),
      ],
      candidateCatalog: [
        _salary('vicente', 94500, 'Vicente Díaz'),
        _salary('lucas', 38500, 'Lucas Pacheco'),
        _salary('fernando', 72000, 'Fernando Tapia'),
      ],
    );

/// The ids the prompt gave each movement, operation and account, by what
/// they name.
Map<String, String> _ids(String prompt) {
  final ids = <String, String>{};
  for (final line in const LineSplitter().convert(prompt)) {
    final match = RegExp(r'^([MOAS]\d+)\*? \| (.*)$').firstMatch(line.trim());
    if (match == null) continue;
    final fields = match.group(2)!;
    for (final key in [
      'Maria Angelica',
      'Claudio Angel',
      'Gasto vicente',
      'Gasto lucas',
      'Gasto fernando',
      'Honorarios',
      'IVA Débito',
      'Aportes de socio',
      'Pedro Madrid',
    ]) {
      if (fields.contains(key)) {
        ids.putIfAbsent(
            key == 'Maria Angelica' && fields.contains('214685')
                ? 'repay'
                : key,
            () => match.group(1)!);
      }
    }
  }
  return ids;
}

void main() {
  test('what the model cites is checked before it reaches the review',
      () async {
    late String seenPrompt;
    final analyst = BankReconciliationAiAnalyst(
      generate: ({required system, required prompt}) async {
        seenPrompt = prompt;
        final ids = _ids(prompt);
        return jsonEncode({
          'rows': [
            {
              'row': ids['Maria Angelica'],
              'explanation':
                  'Tu mamá pagó los sueldos de Vicente y Lucas de la semana 29.',
              'missing': null,
              'question': '¿Tu mamá les pagó esa semana?',
              'proposal': {
                'type': 'link',
                'ops': [ids['Gasto vicente'], ids['Gasto lucas']],
              },
            },
            {
              'row': ids['repay'],
              'explanation': 'Devolución a tu mamá del F29 y los honorarios.',
              'proposal': {
                'type': 'split',
                'parts': [
                  {
                    'account': ids['Honorarios'],
                    'amount': 50000,
                    'description': 'Honorarios contador',
                    'supplier': ids['Pedro Madrid'],
                  },
                  {
                    'account': ids['IVA Débito'],
                    'amount': 164685,
                    'description': 'F29 y patente',
                  },
                ],
              },
            },
            {
              'row': ids['Claudio Angel'],
              'explanation': 'Un aporte tuyo a la empresa.',
              // An operation that does not exist is never proposed.
              'proposal': {
                'type': 'link',
                'ops': ['O99'],
              },
            },
          ],
        });
      },
    );

    final result = await analyst.analyze(draft: _draft(), options: _options);

    expect(seenPrompt, contains('\$133000'));
    expect(seenPrompt, contains('Vicente Díaz'));
    // Every ERP operation here is dated inside the statement and explained
    // by nothing, so it is marked as missing from the bank.
    expect(seenPrompt, contains('*'));

    final mother = result['mother']!;
    expect(mother.proposal!.allocations.map((a) => a.candidate.targetId),
        ['vicente', 'lucas']);
    expect(mother.question, '¿Tu mamá les pagó esa semana?');

    final repay = result['repay']!.resolution!;
    expect(repay.action, BankReconciliationActionKind.split);
    expect(repay.paymentMethodId, 'transfer-id');
    expect(repay.splitParts.first.isExpense, isTrue);
    expect(repay.splitParts.first.supplierId, 'pedro');
    expect(repay.splitParts.last.isExpense, isFalse);

    final owner = result['owner']!;
    expect(owner.hasProposal, isFalse);
    expect(owner.explanation, 'Un aporte tuyo a la empresa.');
  });

  test('a proposal that does not add up is dropped, its question kept',
      () async {
    final analyst = BankReconciliationAiAnalyst(
      generate: ({required system, required prompt}) async {
        final ids = _ids(prompt);
        return jsonEncode({
          'rows': [
            {
              'row': ids['Maria Angelica'],
              'explanation': 'Podría ser el sueldo de Fernando.',
              'question': '¿Le pagaste a Fernando?',
              'proposal': {
                'type': 'link',
                'ops': [ids['Gasto fernando']],
              },
            },
            {
              'row': ids['repay'],
              'explanation': 'Varios pagos.',
              'proposal': {
                'type': 'split',
                'parts': [
                  {
                    'account': ids['Honorarios'],
                    'amount': 50000,
                    'description': 'Honorarios',
                  },
                  {
                    'account': ids['IVA Débito'],
                    'amount': 100000,
                    'description': 'F29',
                  },
                ],
              },
            },
            {
              'row': ids['Claudio Angel'],
              'explanation': 'Un gasto.',
              // Money coming in is never an expense.
              'proposal': {
                'type': 'expense',
                'account': ids['Honorarios'],
                'description': 'Honorarios',
              },
            },
          ],
        });
      },
    );

    final result = await analyst.analyze(draft: _draft(), options: _options);

    expect(result['mother']!.hasProposal, isFalse);
    expect(result['mother']!.question, '¿Le pagaste a Fernando?');
    expect(result['repay']!.hasProposal, isFalse);
    expect(result['owner']!.hasProposal, isFalse);
  });

  test('money coming in is never split into an expense account', () async {
    final analyst = BankReconciliationAiAnalyst(
      generate: ({required system, required prompt}) async {
        final ids = _ids(prompt);
        return jsonEncode({
          'rows': [
            {
              'row': ids['Claudio Angel'],
              'explanation': 'Un aporte y la devolución de un honorario.',
              'proposal': {
                'type': 'split',
                'parts': [
                  {
                    'account': ids['Aportes de socio'],
                    'amount': 600000,
                    'description': 'Aporte de capital',
                  },
                  {
                    'account': ids['Honorarios'],
                    'amount': 100000,
                    'description': 'Devolución de honorarios',
                  },
                ],
              },
            },
          ],
        });
      },
    );

    final result = await analyst.analyze(draft: _draft(), options: _options);

    // The kernel books every part on an expense account as an expense, and
    // only a charge pays one: the proposal would be refused on apply.
    expect(result['owner']!.hasProposal, isFalse);
  });

  test('the owner\'s answer travels with the one movement it answers',
      () async {
    late String seenPrompt;
    final analyst = BankReconciliationAiAnalyst(
      generate: ({required system, required prompt}) async {
        seenPrompt = prompt;
        final ids = _ids(prompt);
        return jsonEncode({
          'rows': [
            {
              'row': ids['Claudio Angel'],
              'explanation': 'Aporte de capital del socio.',
              'proposal': {
                'type': 'journal',
                'account': ids['Aportes de socio'],
                'description': 'Aporte de capital de Claudio Catalán',
              },
            },
          ],
        });
      },
    );

    final result = await analyst.analyze(
      draft: _draft(),
      options: _options,
      rowIds: {'owner'},
      answers: {'owner': 'Es un aporte mío'},
    );

    expect(seenPrompt, contains('RESPUESTA DEL DUEÑO: Es un aporte mío'));
    expect(seenPrompt, isNot(contains('\$133000')));
    expect(result.keys, ['owner']);
    expect(result['owner']!.answer, 'Es un aporte mío');
    expect(result['owner']!.resolution!.accountId, 'partner');
    expect(result['owner']!.resolution!.action,
        BankReconciliationActionKind.classifyAccount);
  });

  test('an id that slips into a text becomes what it names', () async {
    final analyst = BankReconciliationAiAnalyst(
      generate: ({required system, required prompt}) async {
        final ids = _ids(prompt);
        return jsonEncode({
          'rows': [
            {
              'row': ids['repay'],
              'explanation': 'Parecido a ${ids['Maria Angelica']}; quizás '
                  'incluye ${ids['Honorarios']} de ${ids['Pedro Madrid']}.',
              'question': '¿Incluye ${ids['Gasto lucas']}?',
            },
          ],
        });
      },
    );

    final result = await analyst.analyze(draft: _draft(), options: _options);

    final repay = result['repay']!;
    expect(
      repay.explanation,
      'Parecido a el cargo de \$133.000 del 07-07; quizás incluye '
      '6103 · Honorarios Profesionales de Pedro Madrid.',
    );
    expect(repay.question, '¿Incluye Gasto lucas (\$38.500)?');
  });

  BankReconciliationPreparedDraft transfers(int count) =>
      BankReconciliationPreparedDraft(
        fileSha256: 'b' * 64,
        filename: 'cartola agosto.pdf',
        sourceType: 'pdf_text',
        parserName: 'banco_chile_statement',
        parserVersion: 'v1',
        rows: [
          for (var index = 0; index < count; index++)
            BankReconciliationRowDraft(
              movement: _movement(
                  'row$index',
                  BankCivilDate(2026, 8, 1 + index),
                  BankMovementDirection.debit,
                  94500,
                  'App-traspaso A: Persona $index'),
              proposals: const [],
            ),
        ],
        candidateCatalog: [_salary('vicente', 94500, 'Vicente Díaz')],
      );

  test('batches arrive one by one and never claim one operation twice',
      () async {
    final prompts = <String>[];
    final batches = <Set<String>>[];
    final analyst = BankReconciliationAiAnalyst(
      maxRows: 2,
      concurrency: 2,
      generate: ({required system, required prompt}) async {
        prompts.add(prompt);
        final ids = _ids(prompt);
        // Every batch sees Vicente's salary and links its first movement
        // to it.
        return jsonEncode({
          'rows': [
            {
              'row': 'M1',
              'explanation': 'El sueldo de Vicente.',
              'proposal': {
                'type': 'link',
                'ops': [ids['Gasto vicente']],
              },
            },
            {'row': 'M2', 'explanation': 'Otra transferencia.'},
          ],
        });
      },
    );

    final result = await analyst.analyze(
      draft: transfers(5),
      options: _options,
      onBatch: (analyses) => batches.add(analyses.keys.toSet()),
    );

    expect(prompts, hasLength(3));
    expect(batches, hasLength(3));
    expect(result.keys.toSet(), {'row0', 'row1', 'row2', 'row3', 'row4'});
    final linked = result.values.where((analysis) => analysis.hasProposal);
    expect(linked, hasLength(1));
  });

  test('a batch that fails leaves its movements unread, the rest stands',
      () async {
    var calls = 0;
    final analyst = BankReconciliationAiAnalyst(
      maxRows: 2,
      concurrency: 1,
      generate: ({required system, required prompt}) async {
        calls++;
        if (calls == 2) throw StateError('504');
        return jsonEncode({
          'rows': [
            {'row': 'M1', 'explanation': 'Uno.'},
            {'row': 'M2', 'explanation': 'Dos.'},
          ],
        });
      },
    );

    final result =
        await analyst.analyze(draft: transfers(5), options: _options);
    expect(result.keys.toSet(), {'row0', 'row1', 'row4'});

    final failing = BankReconciliationAiAnalyst(
      maxRows: 2,
      generate: ({required system, required prompt}) async =>
          throw StateError('504'),
    );
    await expectLater(
      failing.analyze(draft: transfers(3), options: _options),
      throwsStateError,
    );
  });

  test('card deposits are read only when asked about alone', () async {
    final seen = <String>[];
    final analyst = BankReconciliationAiAnalyst(
      generate: ({required system, required prompt}) async {
        seen.add(prompt);
        return jsonEncode({'rows': <Object>[]});
      },
    );
    final draft = BankReconciliationPreparedDraft(
      fileSha256: 'c' * 64,
      filename: 'cartola junio.pdf',
      sourceType: 'pdf_text',
      parserName: 'banco_chile_statement',
      parserVersion: 'v1',
      rows: [
        BankReconciliationRowDraft(
          movement: _movement('card', const BankCivilDate(2026, 6, 9),
              BankMovementDirection.credit, 48210, 'Abonos Debito Y Credito'),
          proposals: const [],
        ),
        BankReconciliationRowDraft(
          movement: _movement('transfer', const BankCivilDate(2026, 6, 9),
              BankMovementDirection.credit, 20000, 'Traspaso De: Gregorio'),
          proposals: const [],
        ),
      ],
      candidateCatalog: const [],
    );

    expect(draft.rowsAwaitingAiAnalysis.map((row) => row.movement.sourceRowId),
        ['transfer']);
    await analyst.analyze(draft: draft, options: _options);
    expect(seen.single, contains('Gregorio'));
    expect(seen.single, isNot(contains('Abonos Debito')));

    await analyst.analyze(draft: draft, options: _options, rowIds: {'card'});
    expect(seen.last, contains('Abonos Debito'));
  });
}
