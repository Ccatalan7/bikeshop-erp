import '../models/account.dart';

/// Canonical classification for real bank ledger accounts.
///
/// Cash, processor clearing accounts and other current assets are not valid
/// destinations for a bank statement or an acquiring-provider settlement.
class BankLedgerAccountPolicy {
  const BankLedgerAccountPolicy._();

  static List<Account> activeBankAccounts(Iterable<Account> accounts) {
    final snapshot = accounts.toList(growable: false);
    return snapshot
        .where((account) => isBankAccount(account, snapshot))
        .toList(growable: false);
  }

  static bool isBankAccount(Account account, Iterable<Account> accounts) {
    if (!account.isActive || account.type != AccountType.asset) return false;
    final byId = <String, Account>{
      for (final candidate in accounts)
        if (candidate.id != null) candidate.id!: candidate,
    };
    final visited = <String>{};
    Account? current = account;
    while (current != null) {
      final identity = current.id ?? current.code;
      if (!visited.add(identity)) return false;
      if (_isBankRoot(current)) return true;
      current = current.parentId == null ? null : byId[current.parentId];
    }
    return false;
  }

  static bool _isBankRoot(Account account) {
    final code = account.code.trim().toUpperCase();
    if (code == '1110' ||
        code == '1115' ||
        code.startsWith('1110-') ||
        code.startsWith('1115-')) {
      return true;
    }
    final normalized = _normalize('${account.code} ${account.name}');
    return normalized.contains('banco') ||
        normalized.contains('cuenta corriente') ||
        normalized.contains('cuenta de ahorro');
  }

  static String _normalize(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9áéíóúüñ ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
