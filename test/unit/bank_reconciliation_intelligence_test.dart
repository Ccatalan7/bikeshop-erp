import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/accounting/bank_reconciliation/models/bank_reconciliation_models.dart';
import 'package:vinabike_erp/modules/accounting/bank_reconciliation/services/bank_counterparty_identity.dart';
import 'package:vinabike_erp/modules/accounting/bank_reconciliation/services/bank_reconciliation_advisor.dart';
import 'package:vinabike_erp/modules/accounting/bank_reconciliation/services/bank_reconciliation_catalog_codec.dart';
import 'package:vinabike_erp/modules/accounting/bank_reconciliation/services/bank_reconciliation_matcher.dart';

// Cases come from the June–September 2026 Banco de Chile statements and the
// production ERP records they reconcile against.
void main() {
  const matcher = BankReconciliationMatcher();
  const advisor = BankReconciliationAdvisor();

  group('names printed by the bank', () {
    BankIdentityStrength strength(String bank, List<String> names) =>
        BankCounterpartyIdentity.compare(bank, names).strength;

    test('legal name reordered, channel word inserted, accents dropped', () {
      expect(
        strength(
            'Bravo Espinoza Internet Carolina Antonia', ['Carolina Bravo']),
        BankIdentityStrength.strong,
      );
      expect(
        strength('Vicente Diaz Internet', ['Vicente Díaz']),
        BankIdentityStrength.strong,
      );
    });

    test('a misspelled ERP name and a nickname still identify the person', () {
      expect(
        strength('Guido Giovanni Nattero Internet Inostroza', ['Guido Natero']),
        BankIdentityStrength.strong,
      );
      expect(
        strength(
            'Inostroza Espinoza Internet Catalina Nicol', ['Cata Inostrosza']),
        BankIdentityStrength.strong,
      );
    });

    test('only the last bank word can be cut, and legal names count', () {
      expect(
        strength('Comercializadora Internet Bicicletas Univer', [
          'Derman',
          'Comercializadora Bicicletas Universal Dos Limitada',
        ]),
        BankIdentityStrength.strong,
      );
      expect(
        strength('Mauricio Kishinevsky Internet R. S.a.',
            ['MKR Imports', 'Mauricio Kishinevsky Rosental S.A.']),
        BankIdentityStrength.strong,
      );
      // "Ciclo" in the middle of the line is a whole word, not "CicloBar".
      expect(
        strength('Comercial Ciclo Spa Internet', ['CicloBar']),
        isNot(BankIdentityStrength.strong),
      );
    });

    test('placeholders identify nobody; two different people conflict', () {
      expect(
        strength('Macarena Andrea Pizarro Escobar', ['Cliente Mostrador']),
        BankIdentityStrength.unknown,
      );
      expect(
        strength('Patricio Ignacio Basau Internet', ['Maximo Gallardo']),
        BankIdentityStrength.conflict,
      );
    });
  });

  group('direct movements', () {
    test('the bank name picks the right sale among equal amounts', () {
      final movements = [
        _movement('felipe', _d(6, 24), BankMovementDirection.credit, 20000,
            counterparty: 'Felipe Ignacio Aguirre Internet Acosta'),
      ];
      final candidates = [
        _sale('alonso', _d(6, 19), 20000, 'Alonso Ahumada'),
        _sale('mostrador', _d(6, 17), 20000, 'Cliente Mostrador'),
        _sale('aguirre', _d(6, 24), 20000, 'Felipe Aguirre'),
      ];

      final proposal = matcher
          .match(movements: movements, candidates: candidates)['felipe']!
          .first;

      expect(proposal.allocations.single.candidate.targetId, 'aguirre');
      expect(proposal.isSelectedByDefault, isTrue);
      expect(proposal.reasons.join(' '), contains('Mismo titular'));
    });

    test('a salary rounded up by the transfer is still decisive', () {
      final proposal = matcher.match(
        movements: [
          _movement('vicente', _d(7, 23), BankMovementDirection.debit, 72000,
              counterparty: 'Vicente Diaz Internet'),
        ],
        candidates: [_salary('gto-169', _d(7, 23), 71750, 'Vicente Díaz')],
      )['vicente']!.single;

      expect(proposal.isSelectedByDefault, isTrue);
      expect(proposal.allocatedBankAmountClp, 72000);
    });

    test('someone else paying is proposed, never preselected', () {
      final proposal = matcher.match(
        movements: [
          _movement('basau', _d(6, 30), BankMovementDirection.credit, 76000,
              counterparty: 'Patricio Ignacio Basau Internet'),
        ],
        candidates: [_sale('fv-789', _d(6, 27), 76000, 'Maximo Gallardo')],
      )['basau']!.single;

      expect(proposal.isSelectedByDefault, isFalse);
      expect(proposal.reasons, contains('El banco muestra otro titular'));
    });

    test('Nómina evidence ties one transfer to a salary and a reimbursement',
        () {
      final evidence = [
        BankObservedRowEvidence(date: _d(7, 10), amountClp: 22000),
      ];
      final proposal = matcher.match(
        movements: [
          _movement('fernando', _d(7, 10), BankMovementDirection.debit, 22000,
              counterparty: 'Fernando Tapia Internet'),
        ],
        candidates: [
          _salary('gto-171', _d(7, 10), 10000, 'Fernando José Tapia Carrillo',
              evidence: evidence),
          _salary('gto-150', _d(7, 10), 12000, 'Fernando José Tapia Carrillo',
              evidence: evidence),
        ],
      )['fernando']!.single;

      expect(proposal.isSelectedByDefault, isTrue);
      expect(
        proposal.allocations.map((item) => item.bankAmountClp),
        containsAll(<int>[10000, 12000]),
      );
    });

    test('the best arrangement over all rows wins over the first certain row',
        () {
      // 14 Jul: Nómina tied 5.500 to the 135.000 transfer; the other 129.500
      // must come from a salary that no nearer transfer explains better.
      final movements = [
        _movement('jun-30', _d(6, 30), BankMovementDirection.debit, 129500,
            counterparty: 'Vicente Diaz Internet'),
        _movement('jul-14', _d(7, 14), BankMovementDirection.debit, 135000,
            counterparty: 'Vicente Diaz Internet'),
      ];
      final candidates = [
        _salary('gto-170', _d(7, 14), 5500, 'Vicente Díaz', evidence: [
          BankObservedRowEvidence(date: _d(7, 14), amountClp: 135000),
        ]),
        _salary('gto-127', _d(6, 29), 129500, 'Vicente Díaz'),
        _salary('gto-157', _d(8, 12), 129500, 'Vicente Díaz'),
        _salary('gto-100', _d(5, 27), 130200, 'Vicente Díaz'),
      ];

      final result =
          matcher.match(movements: movements, candidates: candidates);

      final june = result['jun-30']!.first;
      expect(june.allocations.single.candidate.targetId, 'gto-127');
      expect(june.isSelectedByDefault, isTrue);
      final july = result['jul-14']!.first;
      expect(
        july.allocations.map((item) => item.candidate.targetId),
        unorderedEquals(<String>['gto-170', 'gto-157']),
      );
    });
  });

  group('card deposits', () {
    test('the statement proves the real rate and a single-sale deposit fits',
        () {
      // Debit really costs 1,21% + VAT at 2 banking days; the configured
      // 1,75% at 1 day never fits.
      final sales = [
        _debitSale('a', _d(8, 19), 120000),
        _debitSale('b', _d(8, 20), 37000),
        _debitSale('c', _d(9, 2), 16000),
        _debitSale('d', _d(9, 4), 24000),
      ];
      final deposits = [
        _deposit('dep-a', _d(8, 21), 118272),
        _deposit('dep-b', _d(8, 24), 36467),
        _deposit('dep-c', _d(9, 4), 15769),
        _deposit('dep-d', _d(9, 8), 23655),
      ];

      final result = matcher.analyze(
        movements: deposits,
        candidates: sales,
        terminalPolicies: _policies(),
      );

      for (final deposit in deposits) {
        final proposal = result.proposals[deposit.sourceRowId]!.first;
        expect(proposal.isSelectedByDefault, isTrue,
            reason: deposit.sourceRowId);
        expect(proposal.reasons, contains('Cuadra al peso'));
      }
      expect(
        result.insights.map((item) => item.title).join(' '),
        contains('no cobra lo configurado en débito'),
      );
    });
  });

  test('a near deposit never credits a sale more than its gross', () {
    // 60.000 + 2.000 net 60.708 under the configured debit terms; the bank
    // paid 200 more. Putting the residue on the small sale would credit it
    // 2.158 for a 2.000 sale, which the database rejects for the whole review.
    final proposal = matcher.analyze(
      movements: [_deposit('near', _d(8, 11), 60908)],
      candidates: [
        _debitSale('big', _d(8, 10), 60000),
        _debitSale('small', _d(8, 10), 2000),
      ],
      terminalPolicies: _policies(),
    ).proposals['near']!.first;

    expect(proposal.isSelectedByDefault, isFalse);
    expect(proposal.allocatedBankAmountClp, 60908);
    for (final allocation in proposal.allocations) {
      expect(
        allocation.bankAmountClp,
        lessThanOrEqualTo(allocation.candidate.amountClp),
      );
    }
    expect(proposal.reasons.join(' '), contains('Diferencia de \$200'));
  });

  group('suggestions for unregistered movements', () {
    final options = BankReconciliationWorkspaceOptions(
      accounts: const [
        BankReconciliationLedgerAccountOption(
          accountId: 'rent',
          code: '6201',
          name: 'Arriendo de Locales',
          type: 'expense',
        ),
        BankReconciliationLedgerAccountOption(
          accountId: 'digital',
          code: '6207',
          name: 'Servicios Digitales',
          type: 'expense',
        ),
        BankReconciliationLedgerAccountOption(
          accountId: 'finance',
          code: '6601',
          name: 'Gastos Financieros',
          type: 'expense',
        ),
        BankReconciliationLedgerAccountOption(
          accountId: 'misc',
          code: '6801',
          name: 'Gastos Varios',
          type: 'expense',
        ),
      ],
      paymentMethods: const [
        BankReconciliationPaymentMethodOption(
          paymentMethodId: 'transfer-id',
          code: 'transfer',
          name: 'Transferencia',
          accountId: 'bank',
        ),
        BankReconciliationPaymentMethodOption(
          paymentMethodId: 'card-id',
          code: 'card',
          name: 'Tarjeta',
          accountId: 'bank',
        ),
      ],
    );

    Map<String, BankReconciliationSuggestion> suggest(
      List<BankStatementMovement> movements,
      BankReconciliationContext context,
    ) =>
        advisor.suggest(
          movements: movements,
          proposals: const {},
          context: context,
          options: options,
        );

    test('a transfer returned the same day cancels its pair', () {
      final suggestions = suggest([
        _movement('out', _d(6, 5), BankMovementDirection.debit, 28000,
            counterparty: 'Vicente Diaz Internet'),
        _movement('back', _d(6, 5), BankMovementDirection.credit, 28000,
            counterparty: 'Vicente Diaz Frias Internet'),
      ], BankReconciliationContext());

      expect(suggestions['out']!.kind, BankSuggestionKind.dismiss);
      expect(suggestions['back']!.relatedSourceRowId, 'out');
      expect(suggestions['back']!.resolution!.reason, contains('devuelta'));
    });

    test('a salary Nómina still owes is paid there, not booked here', () {
      final suggestion = suggest(
          [
            _movement('braulio', _d(8, 31), BankMovementDirection.debit, 71400,
                counterparty: 'Braulio Munoz Internet'),
          ],
          BankReconciliationContext(payrollLines: [
            BankPayrollExpectation(
              voucherId: 'v37',
              voucherNumber: 'NOM-00037',
              periodLabel: 'Semana 35',
              periodEnd: _d(8, 30),
              lineId: 'line',
              employeeName: 'Braulio Muñoz',
              names: const ['Braulio Muñoz'],
              amountClp: 71400,
              paymentMethod: 'transfer',
            ),
          ]))['braulio']!;

      expect(suggestion.kind, BankSuggestionKind.payroll);
      expect(suggestion.resolution, isNull);
      expect(suggestion.followUp, contains('NOM-00037'));
    });

    test('the monthly rent is booked like the previous months', () {
      final suggestion = suggest(
          [
            _movement('rent', _d(9, 16), BankMovementDirection.debit, 499467,
                counterparty: 'Darinka Lagomarsino Internet'),
          ],
          BankReconciliationContext(parties: [
            BankCounterpartyProfile(
              kind: BankCounterpartyKind.payee,
              displayName: 'Darinka Lagomarsino',
              names: const ['Darinka Lagomarsino'],
              usual: const [
                BankUsualBooking(
                  accountId: 'rent',
                  paymentMethodCode: 'transfer',
                  uses: 3,
                  lastDescription: 'Gasto Arriendo',
                ),
              ],
            ),
          ]))['rent']!;

      expect(suggestion.confidence, BankReconciliationConfidence.high);
      expect(suggestion.resolution!.action,
          BankReconciliationActionKind.createExpense);
      expect(suggestion.resolution!.accountId, 'rent');
      expect(suggestion.resolution!.paymentMethodId, 'transfer-id');
      expect(suggestion.resolution!.counterparty, 'Darinka Lagomarsino');
    });

    test('a card charge is classified by its merchant', () {
      final suggestion = suggest([
        _movement('cloud', _d(9, 2), BankMovementDirection.debit, 9928,
            description: 'Pago: Google Cloud Jl5r Renca'),
      ], BankReconciliationContext())['cloud']!;

      expect(suggestion.resolution!.accountId, 'digital');
      expect(suggestion.resolution!.paymentMethodId, 'card-id');
      expect(suggestion.confidence, BankReconciliationConfidence.high);
    });

    test('a bank fee goes to financial expenses, not to a look-alike supplier',
        () {
      final suggestion = suggest(
          [
            _movement('fee', _d(9, 16), BankMovementDirection.debit, 459,
                description:
                    'Comision Compras En El Extranjero Oficina Central'),
          ],
          BankReconciliationContext(parties: [
            BankCounterpartyProfile(
              kind: BankCounterpartyKind.supplier,
              displayName: 'Bancook',
              names: const ['Bancook'],
              usual: const [BankUsualBooking(accountId: 'misc', uses: 1)],
            ),
          ]))['fee']!;

      expect(suggestion.kind, BankSuggestionKind.postJournal);
      expect(suggestion.resolution!.accountId, 'finance');
    });

    test('an earlier decision for the same person is proposed again', () {
      final suggestion = suggest(
          [
            _movement('mother', _d(9, 20), BankMovementDirection.debit, 98000,
                counterparty: 'Maria Angelica Internet Sandoval'),
          ],
          BankReconciliationContext(decisions: const [
            BankPriorDecision(
              action: BankReconciliationActionKind.createExpense,
              direction: BankMovementDirection.debit,
              description: 'App-traspaso A: Maria Angelica Internet Sandoval',
              counterparty: 'Maria Angelica Internet Sandoval',
              accountId: 'misc',
              paymentMethodId: 'transfer-id',
              supplierName: 'Maria Angélica Sandoval',
              text: 'Devolución de préstamo',
            ),
          ]))['mother']!;

      expect(suggestion.confidence, BankReconciliationConfidence.high);
      expect(suggestion.resolution!.accountId, 'misc');
      expect(suggestion.resolution!.description, 'Devolución de préstamo');
    });
  });

  test('the v2 catalog keeps identities, Nómina evidence and payroll lines',
      () {
    final context = const BankReconciliationCatalogCodec().context({
      'candidates': [
        {
          'target_kind': 'expense_payment',
          'target_id': 'gto-157',
          'direction': 'debit',
          'amount': 129500.0,
          'occurred_on': '2026-08-12',
          'label': 'Gasto GTO-00157',
          'counterparty': 'Proveedor',
          'counterparty_kind': 'employee',
          'counterparty_names': ['Vicente Diaz Frias', 'Vicente Díaz'],
          'bank_evidence': [
            {'date': '2026-07-14', 'amount': 135000.0},
          ],
        },
      ],
      'payroll_lines': [
        {
          'voucher_id': 'v37',
          'voucher_number': 'NOM-00037',
          'period_label': 'Semana 35',
          'period_end': '2026-08-30',
          'line_id': 'line',
          'employee_name': 'Braulio Muñoz',
          'amount': 71400.0,
          'payment_method': 'transfer',
        },
      ],
    });

    final candidate = context.candidates.single;
    expect(candidate.counterpartyKind, BankCounterpartyKind.employee);
    expect(candidate.identityNames, contains('Vicente Díaz'));
    expect(candidate.bankEvidence.single.amountClp, 135000);
    expect(context.payrollLines.single.amountClp, 71400);
  });
}

BankCivilDate _d(int month, int day) => BankCivilDate(2026, month, day);

BankStatementMovement _movement(
  String id,
  BankCivilDate date,
  BankMovementDirection direction,
  int amount, {
  String? counterparty,
  String? description,
}) {
  final text = description ??
      (direction == BankMovementDirection.credit
          ? 'Traspaso De: $counterparty'
          : 'App-traspaso A: $counterparty');
  return BankStatementMovement(
    sourceRowId: id,
    ordinal: 1,
    bookingDate: date,
    description: text,
    normalizedDescription: text.toLowerCase(),
    counterpartyObserved: counterparty,
    direction: direction,
    amountClp: amount,
    sourcePage: 1,
    sourceLineStart: 1,
    sourceLineEnd: 1,
  );
}

BankReconciliationCandidate _sale(
  String id,
  BankCivilDate date,
  int amount,
  String customer,
) =>
    BankReconciliationCandidate(
      targetKind: BankReconciliationTargetKind.salesPayment,
      targetId: id,
      direction: BankMovementDirection.credit,
      amountClp: amount,
      occurredOn: date,
      label: 'Venta $id',
      counterparty: customer,
      paymentMethodCode: 'transfer',
      counterpartyKind: BankCounterpartyKind.customer,
      counterpartyNames: <String>[customer],
    );

BankReconciliationCandidate _salary(
  String id,
  BankCivilDate date,
  int amount,
  String employee, {
  List<BankObservedRowEvidence> evidence = const [],
}) =>
    BankReconciliationCandidate(
      targetKind: BankReconciliationTargetKind.expensePayment,
      targetId: id,
      direction: BankMovementDirection.debit,
      amountClp: amount,
      occurredOn: date,
      label: 'Gasto $id',
      counterparty: 'Proveedor',
      paymentMethodCode: 'transfer',
      counterpartyKind: BankCounterpartyKind.employee,
      counterpartyNames: <String>[employee],
      bankEvidence: evidence,
    );

BankReconciliationCandidate _debitSale(
  String id,
  BankCivilDate date,
  int amount,
) =>
    BankReconciliationCandidate(
      targetKind: BankReconciliationTargetKind.salesPayment,
      targetId: id,
      direction: BankMovementDirection.credit,
      amountClp: amount,
      occurredOn: date,
      label: 'Venta $id',
      paymentMethodCode: 'card_debit',
      provider: BankSettlementProvider.transbank,
      instrument: BankPaymentInstrument.debit,
    );

BankStatementMovement _deposit(String id, BankCivilDate date, int amount) =>
    _movement(
      id,
      date,
      BankMovementDirection.credit,
      amount,
      description: 'Pago: Abonos Debito Y Credito Transbank 0966893109',
    );

List<BankTerminalMatchPolicy> _policies() => [
      BankTerminalMatchPolicy(
        profileId: 'transbank',
        providerCode: 'transbank',
        providerName: 'Transbank',
        terminalName: 'Transbank POS',
        descriptorPatterns: const ['transbank', 'abonos debito y credito'],
        paymentMethodCode: 'card_debit',
        instrument: BankPaymentInstrument.debit,
        commissionRateBps: 175,
        commissionVatBps: 1900,
        settlementBusinessDays: 1,
        bookingGraceBusinessDays: 2,
        amountToleranceClp: 1000,
        effectiveFrom: const BankCivilDate(2026, 5, 20),
      ),
    ];
