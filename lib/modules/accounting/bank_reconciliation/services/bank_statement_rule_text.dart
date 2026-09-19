import '../models/bank_reconciliation_models.dart';
import 'bank_counterparty_identity.dart';

/// The words of a statement line a company rule is written in, and which
/// lines a rule may speak for.
class BankStatementRuleText {
  const BankStatementRuleText._();

  /// The bank's words without its channel words: "Pago: Google Play Youtu
  /// Renca" → "google play youtu".
  static List<String> words(BankStatementMovement movement) =>
      BankCounterpartyIdentity.tokens(movement.description);

  /// What a rule taught from this line says. A word with a digit is the
  /// bank's code for that one charge ("Google Cloud Jl5r", "Hwm3", "R897"),
  /// never the merchant, so the rule leaves it out and speaks for next
  /// month's charge too.
  static String patternOf(BankStatementMovement movement) {
    final all = words(movement);
    final kept = all.where((word) => !_code.hasMatch(word)).toList();
    return (kept.isEmpty ? all : kept).join(' ');
  }

  static final _code = RegExp(r'\d');

  /// Every word of the rule starts a word of the line, in the same order:
  /// "youtu" speaks for "Dl*google Youtube" and "Google Play Youtu", and
  /// "google cloud" still names "Google Cloud Hwm3".
  static bool matches(String pattern, List<String> lineWords) {
    var at = 0;
    for (final part in pattern.split(' ')) {
      if (part.isEmpty) continue;
      while (at < lineWords.length && !lineWords[at].startsWith(part)) {
        at++;
      }
      if (at == lineWords.length) return false;
      at++;
    }
    return true;
  }

  /// A line names a merchant or a bank charge; a person's transfer is
  /// decided by who it is and what the ERP owes, never by its words.
  static bool canTeach(BankStatementMovement movement) =>
      !movement.isPersonTransfer &&
      !movement.isTransbankDeposit &&
      movement.direction != BankMovementDirection.unknown &&
      patternOf(movement).length >= 3;

  /// The company rule for this line, the most specific when several match.
  static BankReconciliationRule? ruleFor(
    BankStatementMovement movement,
    List<BankReconciliationRule> rules,
  ) {
    if (!canTeach(movement)) return null;
    final lineWords = words(movement);
    BankReconciliationRule? best;
    for (final rule in rules) {
      if (rule.direction != movement.direction ||
          !matches(rule.pattern, lineWords)) {
        continue;
      }
      if (best == null || rule.pattern.length > best.pattern.length) {
        best = rule;
      }
    }
    return best;
  }
}
