import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/accounting/bank_reconciliation/models/bank_reconciliation_models.dart';
import 'package:vinabike_erp/modules/accounting/bank_reconciliation/services/bank_statement_rule_text.dart';

// Lines come from the June–September 2026 Banco de Chile statements.
BankStatementMovement _line(
  String description, {
  BankMovementDirection direction = BankMovementDirection.debit,
}) =>
    BankStatementMovement(
      sourceRowId: description,
      ordinal: 1,
      bookingDate: const BankCivilDate(2026, 8, 24),
      description: description,
      normalizedDescription: description.toLowerCase(),
      direction: direction,
      amountClp: 2990,
      sourcePage: 1,
      sourceLineStart: 1,
      sourceLineEnd: 1,
    );

BankReconciliationRule _rule(
  String pattern, {
  String accountId = 'withdrawals',
  BankMovementDirection direction = BankMovementDirection.debit,
}) =>
    BankReconciliationRule(
      ruleId: pattern,
      pattern: pattern,
      direction: direction,
      action: BankReconciliationActionKind.classifyAccount,
      accountId: accountId,
      description: pattern,
    );

void main() {
  test('a taught rule keeps the merchant and drops the charge code', () {
    expect(
      BankStatementRuleText.patternOf(_line('Pago: Merpago*melimas Renca')),
      'merpago melimas',
    );
    expect(
      BankStatementRuleText.patternOf(_line('Pago: Google Cloud Jl5r Renca')),
      'google cloud',
    );
  });

  test('a rule taught this month speaks for next month\'s charge', () {
    final taught = _rule(
      BankStatementRuleText.patternOf(_line('Pago: Google Cloud Jl5r Renca')),
      accountId: 'digital',
    );

    expect(
      BankStatementRuleText.ruleFor(
          _line('Pago: Google Cloud Hwm3 Renca'), [taught]),
      same(taught),
    );
  });

  test('a rule word starts a line word, in order', () {
    final youtube = _rule('youtu');

    expect(
      BankStatementRuleText.ruleFor(
          _line('Pago: Dl*google Youtube Renca'), [youtube]),
      same(youtube),
    );
    expect(
      BankStatementRuleText.ruleFor(
          _line('Pago: Google Play Youtu Renca'), [youtube]),
      same(youtube),
    );
    // "tu" inside a word is not the start of one.
    expect(
      BankStatementRuleText.ruleFor(
          _line('Pago: Google Play Youtu Renca'), [_rule('outu')]),
      isNull,
    );
    expect(
      BankStatementRuleText.ruleFor(
          _line('Pago: Google Play Youtu Renca'), [_rule('youtu google')]),
      isNull,
    );
  });

  test('the most specific rule wins, and only in its direction', () {
    final google = _rule('google', accountId: 'digital');
    final youtube = _rule('google play youtu');
    final refund = _rule('youtu', direction: BankMovementDirection.credit);

    expect(
      BankStatementRuleText.ruleFor(
        _line('Pago: Google Play Youtu Renca'),
        [google, youtube, refund],
      ),
      same(youtube),
    );
    expect(
      BankStatementRuleText.ruleFor(
        _line('Pago: Google Cloud Jl5r Renca'),
        [youtube, refund],
      ),
      isNull,
    );
  });

  test('a person\'s transfer and a card deposit are never taught', () {
    final transfer = _line('App-traspaso A: Youtube Rodriguez');
    final received = _line('Traspaso De: Melimas Soto',
        direction: BankMovementDirection.credit);
    final deposit = _line('Pago: Abonos Debito Y Credito Transbank 0966893109',
        direction: BankMovementDirection.credit);

    expect(BankStatementRuleText.canTeach(transfer), isFalse);
    expect(BankStatementRuleText.canTeach(received), isFalse);
    expect(BankStatementRuleText.canTeach(deposit), isFalse);
    expect(BankStatementRuleText.ruleFor(transfer, [_rule('youtu')]), isNull);
    expect(
      BankStatementRuleText.canTeach(_line('Pago: Merpago*melimas Renca')),
      isTrue,
    );
  });
}
