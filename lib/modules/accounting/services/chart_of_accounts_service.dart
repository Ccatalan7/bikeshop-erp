import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../../shared/services/database_service.dart';
import '../data/standard_chart_of_accounts.dart';
import '../models/account.dart';

class ChartOfAccountsService extends ChangeNotifier {
  ChartOfAccountsService(this._databaseService);

  final DatabaseService _databaseService;
  final List<Account> _accounts = [];
  bool _isInitialized = false;

  List<Account> get accounts => List.unmodifiable(_accounts);
  bool get isInitialized => _isInitialized;

  Future<void> initializeChartOfAccounts({bool forceRefresh = false}) async {
    // Quick return if already initialized (unless forcing refresh)
    if (_isInitialized && !forceRefresh) {
      return; // Already initialized and loaded
    }

    try {
      debugPrint('🔄 Initializing Chart of Accounts...');
      final startTime = DateTime.now();

      _accounts.clear();

      // Only ensure standard accounts if database is empty or force refresh
      if (forceRefresh) {
        await _ensureStandardChartOfAccounts();
      }

      final remoteAccounts = await _databaseService.select('accounts');

      final loadTime = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('✅ Loaded ${remoteAccounts.length} accounts in ${loadTime}ms');

      final mappedAccounts = remoteAccounts
          .map((raw) => Account.fromJson(raw))
          .toList(growable: false)
        ..sort((a, b) => a.code.compareTo(b.code));

      _accounts.addAll(mappedAccounts);
      _isInitialized = true;
      notifyListeners();

      final totalTime = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('✅ Chart of Accounts initialized in ${totalTime}ms');
    } catch (e) {
      debugPrint('❌ Error initializing chart of accounts: $e');
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

  Account? getAccountById(String id) {
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
      final payload = {
        'code': account.code,
        'name': account.name,
        'type': account.type.name,
        'category': account.category.name,
        'description': account.description,
        'parent_id': account.parentId,
        'is_active': account.isActive,
      };

      final inserted = await _databaseService.insert('accounts', payload);
      final newAccount = Account.fromJson(inserted);

      _accounts.removeWhere((existing) => existing.code == newAccount.code);
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
      if (account.id == null) {
        throw ArgumentError(
            'No se puede actualizar una cuenta sin identificador.');
      }

      final payload = {
        'name': account.name,
        'description': account.description,
        'type': account.type.name,
        'category': account.category.name,
        'parent_id': account.parentId,
        'is_active': account.isActive,
      };

      final updated =
          await _databaseService.update('accounts', account.id!, payload);
      final refreshed = Account.fromJson(updated);

      final index = _accounts.indexWhere((a) => a.id == refreshed.id);
      if (index != -1) {
        _accounts[index] = refreshed;
      } else {
        _accounts.add(refreshed);
      }

      _accounts.sort((a, b) => a.code.compareTo(b.code));
      notifyListeners();
    } catch (e) {
      debugPrint('Error updating account: $e');
      rethrow;
    }
  }

  Future<void> deleteAccount(String accountId) async {
    try {
      await _databaseService.delete('accounts', accountId);
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

  Future<void> _ensureStandardChartOfAccounts() async {
    try {
      for (final definition in kStandardChartOfAccounts) {
        final description = definition.description.isNotEmpty
            ? definition.description
            : '${definition.name} (${definition.category.displayName})';
        await _databaseService.ensureAccount(
          code: definition.code,
          name: definition.name,
          type: definition.type.name,
          category: definition.category.name,
          description: description,
          parentCode: definition.parentCode,
        );
      }
    } catch (e) {
      debugPrint('Error seeding standard chart of accounts: $e');
      rethrow;
    }
  }
}
