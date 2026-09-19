import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/accounting/bank_reconciliation/models/bank_reconciliation_models.dart';
import 'package:vinabike_erp/modules/accounting/bank_reconciliation/services/bank_reconciliation_draft_codec.dart';

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

BankReconciliationCandidate _salary(String id, int amount) =>
    BankReconciliationCandidate(
      targetKind: BankReconciliationTargetKind.expensePayment,
      targetId: id,
      direction: BankMovementDirection.debit,
      amountClp: amount,
      occurredOn: const BankCivilDate(2026, 8, 12),
      label: 'Gasto $id',
    );

final _vicente = _salary('vicente', 94500);
final _lucas = _salary('lucas', 38500);

BankPayrollPaymentDraft _payroll(int owed) => BankPayrollPaymentDraft(
      voucherId: 'week-35',
      voucherNumber: 'NOM-00037',
      periodLabel: 'Semana 35',
      lineId: 'line-braulio',
      employeeName: 'Braulio Muñoz',
      expectedAmountClp: owed,
      amountClp: 71400,
      paymentMethodId: 'transfer',
      confirmDraft: true,
    );

/// The review as it is prepared: nothing decided but the matcher's choice.
BankReconciliationPreparedDraft _fresh({
  List<BankReconciliationCandidate>? catalog,
  bool googleTakesVicente = false,
  int? salaryOwed = 71400,
}) {
  final vicenteAsDirect = BankReconciliationProposal(
    sourceRowId: 'google',
    matchKind: BankReconciliationMatchKind.direct,
    confidence: BankReconciliationConfidence.high,
    allocations: <BankReconciliationAllocationDraft>[
      BankReconciliationAllocationDraft(
        candidate: _vicente,
        bankAmountClp: 94500,
      ),
    ],
    reasons: const <String>['Monto exacto'],
    isSelectedByDefault: true,
  );
  return BankReconciliationPreparedDraft(
    fileSha256: 'a' * 64,
    filename: 'cartola julio.pdf',
    sourceType: 'pdf_text',
    parserName: 'banco_chile_statement',
    parserVersion: 'v1',
    rows: <BankReconciliationRowDraft>[
      BankReconciliationRowDraft(
        movement: _movement('mother', const BankCivilDate(2026, 7, 7),
            BankMovementDirection.debit, 133000, 'App-traspaso A: Maria'),
        proposals: const [],
      ),
      BankReconciliationRowDraft(
        movement: _movement('repay', const BankCivilDate(2026, 8, 17),
            BankMovementDirection.debit, 214685, 'App-traspaso A: Maria'),
        proposals: const [],
      ),
      BankReconciliationRowDraft(
        movement: _movement('owner', const BankCivilDate(2026, 8, 11),
            BankMovementDirection.credit, 700000, 'Traspaso De: Claudio'),
        proposals: const [],
      ),
      BankReconciliationRowDraft(
        movement: _movement('google', const BankCivilDate(2026, 8, 12),
            BankMovementDirection.debit, 94500, 'Pago: Google'),
        proposals: googleTakesVicente
            ? <BankReconciliationProposal>[vicenteAsDirect]
            : const [],
      ),
      BankReconciliationRowDraft(
        movement: _movement('braulio', const BankCivilDate(2026, 8, 31),
            BankMovementDirection.debit, 71400, 'App-traspaso A: Braulio'),
        proposals: const [],
        suggestion: salaryOwed == null
            ? null
            : BankReconciliationSuggestion(
                kind: BankSuggestionKind.payroll,
                confidence: BankReconciliationConfidence.medium,
                title: 'Sueldo de Braulio Muñoz',
                resolution: BankReconciliationResolutionDraft(
                  action: BankReconciliationActionKind.payPayroll,
                  payroll: _payroll(salaryOwed),
                ),
              ),
      ),
    ],
    candidateCatalog:
        catalog ?? <BankReconciliationCandidate>[_vicente, _lucas],
  );
}

/// What the operator decided in the first sitting.
BankReconciliationPreparedDraft _decided() {
  final fresh = _fresh();
  final rows = fresh.rowsBySourceId;
  final manual = BankReconciliationProposal.manual(
    sourceRowId: 'mother',
    movementAmountClp: 133000,
    candidates: <BankReconciliationCandidate>[_vicente, _lucas],
  )!;
  return fresh.replaceRows(<BankReconciliationRowDraft>[
    rows['mother']!.copyWith(
      proposals: <BankReconciliationProposal>[manual],
      selectedProposalId: BankReconciliationRowDraft.proposalIdentity(manual),
      resolution: const BankReconciliationResolutionDraft(
        action: BankReconciliationActionKind.associateExisting,
      ),
    ),
    rows['repay']!.copyWith(
      resolution: const BankReconciliationResolutionDraft(
        action: BankReconciliationActionKind.split,
        paymentMethodId: 'transfer',
        splitParts: <BankSplitPartDraft>[
          BankSplitPartDraft(
            accountId: 'fees',
            amountClp: 50000,
            description: 'Honorarios contador',
            supplierId: 'pedro',
            isExpense: true,
          ),
          BankSplitPartDraft(
            accountId: 'vat',
            amountClp: 164685,
            description: 'F29 y patente',
          ),
        ],
      ),
    ),
    rows['owner']!.copyWith(
      aiAnalysis: const BankAiAnalysis(
        explanation: 'Un aporte tuyo como socio.',
        answer: 'Es un aporte mío',
        resolution: BankReconciliationResolutionDraft(
          action: BankReconciliationActionKind.classifyAccount,
          accountId: 'partner',
          description: 'Aporte de capital',
        ),
      ),
    ),
    rows['braulio']!.copyWith(
      resolution: rows['braulio']!.suggestion!.resolution,
    ),
  ]);
}

/// The draft as the server hands it back.
Map<String, dynamic> _saved(Map<String, dynamic> encoded) =>
    jsonDecode(jsonEncode(encoded)) as Map<String, dynamic>;

void main() {
  const codec = BankReconciliationDraftCodec();
  const touched = <String>{'mother', 'repay', 'owner', 'braulio'};

  test('what the operator decided comes back in the next sitting', () {
    final saved = _saved(codec.encode(_decided(), touched));

    expect((saved['rows'] as Map).keys, hasLength(4));

    final restore = codec.restore(_fresh(), saved);
    final rows = restore.draft.rowsBySourceId;

    expect(restore.droppedCount, 0);
    expect(restore.restoredRowIds, touched);
    expect(rows['mother']!.isResolved, isTrue);
    expect(
      rows['mother']!.selectedProposal!.allocations.map(
            (item) => item.candidate.targetId,
          ),
      ['vicente', 'lucas'],
    );
    expect(rows['repay']!.isResolved, isTrue);
    expect(rows['repay']!.effectiveResolution.splitParts.first.supplierId,
        'pedro');
    expect(rows['owner']!.aiAnalysis!.answer, 'Es un aporte mío');
    expect(rows['owner']!.aiAnalysis!.resolution!.accountId, 'partner');
    expect(rows['owner']!.isResolved, isFalse);
    expect(
        rows['braulio']!.effectiveResolution.payroll!.lineId, 'line-braulio');
    // A movement nobody touched is reviewed again, not frozen as pending.
    expect(rows['google']!.effectiveResolution.action,
        BankReconciliationActionKind.pending);
  });

  test('a decision today\'s ERP no longer allows is dropped, not forced', () {
    final saved = _saved(codec.encode(_decided(), touched));

    // Lucas's payment was deleted, and the week was paid in Nómina.
    final gone = codec.restore(
      _fresh(
          catalog: <BankReconciliationCandidate>[_vicente], salaryOwed: null),
      saved,
    );
    expect(gone.droppedCount, 2);
    expect(gone.draft.rowsBySourceId['mother']!.isResolved, isFalse);
    expect(gone.draft.rowsBySourceId['braulio']!.isResolved, isFalse);
    expect(gone.draft.rowsBySourceId['repay']!.isResolved, isTrue);

    // Today's review gives Vicente's payment to a movement nobody touched.
    final taken = codec.restore(_fresh(googleTakesVicente: true), saved);
    expect(taken.droppedCount, 1);
    expect(taken.draft.rowsBySourceId['mother']!.selectedProposal, isNull);
    expect(
      taken.draft.rowsBySourceId['google']!.selectedProposal!.allocations.single
          .candidate.targetId,
      'vicente',
    );
  });

  test('a salary is restored as Nómina owes it today', () {
    final saved = _saved(codec.encode(_decided(), touched));

    final restore = codec.restore(_fresh(salaryOwed: 70000), saved);

    expect(restore.droppedCount, 0);
    expect(
      restore.draft.rowsBySourceId['braulio']!.effectiveResolution.payroll!
          .expectedAmountClp,
      70000,
    );
  });

  test('a deposit split the kernel would refuse is not restored', () {
    final options = BankReconciliationWorkspaceOptions(
      accounts: const <BankReconciliationLedgerAccountOption>[
        BankReconciliationLedgerAccountOption(
          accountId: 'fees',
          code: '6103',
          name: 'Honorarios Profesionales',
          type: 'expense',
        ),
        BankReconciliationLedgerAccountOption(
          accountId: 'partner',
          code: '3102',
          name: 'Aportes de socio',
          type: 'equity',
        ),
      ],
      paymentMethods: const <BankReconciliationPaymentMethodOption>[],
    );
    // Saved before the deposit split was blocked: money in, one part on an
    // expense account.
    final saved = _saved(<String, dynamic>{
      'version': BankReconciliationDraftCodec.version,
      'rows': <String, dynamic>{
        '${'a' * 64}:owner': <String, dynamic>{
          'resolution': <String, dynamic>{
            'action': 'split',
            'split_parts': <Map<String, dynamic>>[
              <String, dynamic>{
                'account_id': 'partner',
                'amount': 600000,
                'description': 'Aporte',
                'is_expense': false,
              },
              <String, dynamic>{
                'account_id': 'fees',
                'amount': 100000,
                'description': 'Devolución de honorarios',
                'is_expense': false,
              },
            ],
          },
        },
      },
    });

    final refused = codec.restore(_fresh(), saved, options: options);
    expect(refused.droppedCount, 1);
    expect(refused.draft.rowsBySourceId['owner']!.isResolved, isFalse);

    // The same split of a charge still holds.
    final kept = codec.restore(
      _fresh(),
      _saved(<String, dynamic>{
        'version': BankReconciliationDraftCodec.version,
        'rows': <String, dynamic>{
          '${'a' * 64}:repay': (saved['rows'] as Map)['${'a' * 64}:owner'],
        },
      }),
      options: options,
    );
    expect(kept.droppedCount, 0);
    expect(kept.draft.rowsBySourceId['repay']!.effectiveResolution.action,
        BankReconciliationActionKind.split);
  });

  test('a deposit split the kernel would refuse is not restored from the AI',
      () {
    final options = BankReconciliationWorkspaceOptions(
      accounts: const <BankReconciliationLedgerAccountOption>[
        BankReconciliationLedgerAccountOption(
          accountId: 'fees',
          code: '6103',
          name: 'Honorarios Profesionales',
          type: 'expense',
        ),
        BankReconciliationLedgerAccountOption(
          accountId: 'partner',
          code: '3102',
          name: 'Aportes de socio',
          type: 'equity',
        ),
      ],
      paymentMethods: const <BankReconciliationPaymentMethodOption>[],
    );
    final split = <String, dynamic>{
      'action': 'split',
      'split_parts': <Map<String, dynamic>>[
        <String, dynamic>{
          'account_id': 'partner',
          'amount': 600000,
          'description': 'Aporte',
          'is_expense': false,
        },
        <String, dynamic>{
          'account_id': 'fees',
          'amount': 100000,
          'description': 'Devolución de honorarios',
          'is_expense': false,
        },
      ],
    };
    final saved = _saved(<String, dynamic>{
      'version': BankReconciliationDraftCodec.version,
      'rows': <String, dynamic>{
        '${'a' * 64}:owner': <String, dynamic>{
          'ai': <String, dynamic>{
            'explanation': 'Un aporte con una devolución de honorarios.',
            'resolution': split,
          },
        },
      },
    });

    final reviewed = codec.restore(_fresh(), saved, options: options);
    expect(
      reviewed.draft.rowsBySourceId['owner']!.aiAnalysis!.explanation,
      'Un aporte con una devolución de honorarios.',
    );
    expect(
      reviewed.draft.rowsBySourceId['owner']!.aiAnalysis!.resolution,
      isNull,
    );

    // The accounts of the day are what tells the parts apart: without them
    // neither the decision nor the analysis is taken as good.
    final blind = codec.restore(
      _fresh(),
      _saved(<String, dynamic>{
        'version': BankReconciliationDraftCodec.version,
        'rows': <String, dynamic>{
          '${'a' * 64}:owner': <String, dynamic>{
            'resolution': split,
            'ai': <String, dynamic>{
              'explanation': 'Un aporte con una devolución de honorarios.',
              'resolution': split,
            },
          },
        },
      }),
    );
    expect(blind.droppedCount, 1);
    expect(blind.draft.rowsBySourceId['owner']!.isResolved, isFalse);
    expect(blind.draft.rowsBySourceId['owner']!.aiAnalysis!.resolution, isNull);
  });

  test('a save keeps what the draft holds for statements not loaded', () {
    // July imported again alone, in a conciliation that also has June.
    final june = <String, dynamic>{
      'resolution': <String, dynamic>{
        'action': 'dismiss',
        'reason': 'Duplicado',
      },
      'ai': <String, dynamic>{'explanation': 'Una devolución.'},
    };
    final saved = _saved(<String, dynamic>{
      'version': BankReconciliationDraftCodec.version,
      'rows': <String, dynamic>{
        '${'b' * 64}:p1-l3-r2': june,
        // A movement of this statement nobody touched this sitting is
        // reviewed again, not carried over.
        '${'a' * 64}:google': <String, dynamic>{
          'resolution': <String, dynamic>{'action': 'split'},
        },
      },
    });

    final encoded = codec.encode(
      _decided(),
      const <String>{'repay'},
      saved: saved,
    );
    final rows = encoded['rows'] as Map<String, dynamic>;

    expect(
        rows.keys,
        unorderedEquals(<String>[
          '${'b' * 64}:p1-l3-r2',
          '${'a' * 64}:repay',
        ]));
    expect(rows['${'b' * 64}:p1-l3-r2'], june);
  });

  test('only touched movements are saved, keyed by file and row', () {
    final saved = codec.encode(_decided(), const <String>{'repay'});

    expect((saved['rows'] as Map).keys, ['${'a' * 64}:repay']);
    expect(saved['version'], BankReconciliationDraftCodec.version);
  });
}
