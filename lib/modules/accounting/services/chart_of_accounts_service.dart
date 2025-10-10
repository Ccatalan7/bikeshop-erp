import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../data/standard_chart_of_accounts.dart';
import '../models/account.dart';

class ChartOfAccountsService extends ChangeNotifier {
  final List<Account> _accounts = [];
  bool _isInitialized = false;

  List<Account> get accounts => List.unmodifiable(_accounts);
  bool get isInitialized => _isInitialized;

  Future<void> initializeChartOfAccounts() async {
    if (_isInitialized) return;

    try {
      _accounts.clear();

      final now = DateTime.now();
      var idCounter = 1;

      for (final definition in kStandardChartOfAccounts) {
        final description = definition.description.isNotEmpty
            ? definition.description
            : '${definition.name} (${definition.category.displayName})';

        _accounts.add(
          Account(
            id: idCounter++,
            code: definition.code,
            name: definition.name,
            type: definition.type,
            category: definition.category,
            description: description,
            parentId: definition.parentCode,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }

      _accounts.sort((a, b) => a.code.compareTo(b.code));

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Error initializing chart of accounts: $e');
      rethrow;
    }
  }

  Map<AccountType, List<Account>> getAccountsGroupedByType() {
    final grouped = LinkedHashMap<AccountType, List<Account>>(
      equals: (a, b) => a == b,
      hashCode: (type) => type.hashCode,
    );

    for (final account in _accounts) {
      grouped.putIfAbsent(account.type, () => []).add(account);
    }

    for (final entry in grouped.entries) {
      entry.value.sort((a, b) => a.code.compareTo(b.code));
    }

    return grouped;
  }

  List<Account> getAccountsByType(AccountType type) {
    return _accounts
        .where((account) => account.type == type)
        .toList(growable: false);
  }

  List<Account> getAccountsByCategory(AccountCategory category) {
    return _accounts
        .where((account) => account.category == category)
        .toList(growable: false);
  }

  Account? getAccountByCode(String code) {
    try {
      return _accounts.firstWhere((account) => account.code == code);
    } catch (_) {
      return null;
    }
  }

  Account? getAccountById(int id) {
    try {
      return _accounts.firstWhere((account) => account.id == id);
    } catch (_) {
      return null;
    }
  }

  List<Account> searchAccounts(String query) {
    if (query.isEmpty) return List.unmodifiable(_accounts);

    final lowerQuery = query.toLowerCase();
    return _accounts.where((account) {
      final matchesCode = account.code.toLowerCase().contains(lowerQuery);
      final matchesName = account.name.toLowerCase().contains(lowerQuery);
      final matchesDescription =
          account.description?.toLowerCase().contains(lowerQuery) ?? false;
      return matchesCode || matchesName || matchesDescription;
    }).toList(growable: false);
  }

  Future<void> addAccount(Account account) async {
    try {
      final newAccount = account.copyWith(
        id: _accounts.length + 1,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      _accounts.add(newAccount);
      _accounts.sort((a, b) => a.code.compareTo(b.code));
      notifyListeners();
    } catch (e) {
      debugPrint('Error adding account: $e');
      rethrow;
    }
  }

  Future<void> updateAccount(Account account) async {
    try {
      final index = _accounts.indexWhere((a) => a.id == account.id);
      if (index != -1) {
        _accounts[index] = account.copyWith(updatedAt: DateTime.now());
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error updating account: $e');
      rethrow;
    }
  }

  Future<void> deleteAccount(int accountId) async {
    try {
      _accounts.removeWhere((account) => account.id == accountId);
      notifyListeners();
    } catch (e) {
      debugPrint('Error deleting account: $e');
      rethrow;
    }
  }

  Account? get cashAccount => getAccountByCode('1101');
  Account? get bankAccount => getAccountByCode('1110');
  Account? get accountsReceivable => getAccountByCode('1130');
  Account? get inventory => getAccountByCode('1150');
  Account? get ivaCredit => getAccountByCode('1180');
  Account? get accountsPayable => getAccountByCode('2100');
  Account? get ivaDebit => getAccountByCode('2150');
  Account? get salesRevenue => getAccountByCode('4100');
  Account? get costOfGoodsSold => getAccountByCode('5100');
}