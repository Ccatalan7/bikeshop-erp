import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/accounting/models/account.dart';
import 'package:vinabike_erp/modules/accounting/utils/bank_ledger_account_policy.dart';

void main() {
  const tenantId = 'tenant-1';

  Account account({
    required String id,
    required String code,
    required String name,
    String? parentId,
    AccountType type = AccountType.asset,
    bool isActive = true,
  }) {
    return Account(
      id: id,
      tenantId: tenantId,
      code: code,
      name: name,
      type: type,
      category: type == AccountType.expense
          ? AccountCategory.financialExpense
          : AccountCategory.currentAsset,
      parentId: parentId,
      isActive: isActive,
    );
  }

  test('accepts bank roots and their custom children', () {
    final root = account(
      id: 'bank-root',
      code: '1110',
      name: 'Bancos - Cuenta Corriente',
    );
    final child = account(
      id: 'bci',
      code: 'BCI-OPERATIVA',
      name: 'Cuenta operativa BCI',
      parentId: root.id,
    );

    expect(BankLedgerAccountPolicy.isBankAccount(root, [root, child]), isTrue);
    expect(BankLedgerAccountPolicy.isBankAccount(child, [root, child]), isTrue);
  });

  test('rejects cash, clearing and expense accounts', () {
    final cash = account(id: 'cash', code: '1101', name: 'Caja General');
    final clearing = account(
      id: 'clearing',
      code: '1140-TBK',
      name: 'Fondos por recibir · Transbank',
    );
    final commission = account(
      id: 'commission',
      code: '6601-TBK',
      name: 'Comisiones · Transbank',
      type: AccountType.expense,
    );

    final accounts = [cash, clearing, commission];
    expect(BankLedgerAccountPolicy.activeBankAccounts(accounts), isEmpty);
  });

  test('rejects inactive bank accounts and cyclic non-bank ancestry', () {
    final inactiveBank = account(
      id: 'inactive-bank',
      code: '1110-OLD',
      name: 'Banco cerrado',
      isActive: false,
    );
    final a = account(
      id: 'a',
      code: '1198',
      name: 'Activo A',
      parentId: 'b',
    );
    final b = account(
      id: 'b',
      code: '1199',
      name: 'Activo B',
      parentId: 'a',
    );

    expect(
      BankLedgerAccountPolicy.activeBankAccounts([inactiveBank, a, b]),
      isEmpty,
    );
  });
}
