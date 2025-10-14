import 'dart:collection';

import 'package:flutter/foundation.dart';
import '../../../shared/services/database_service.dart';
import '../models/account.dart';
import '../models/journal_entry.dart';
import 'chart_of_accounts_service.dart';
import 'journal_entry_service.dart';

class AccountingService extends ChangeNotifier {
  final DatabaseService _databaseService;
  late final ChartOfAccountsService _chartOfAccountsService;
  late final JournalEntryService _journalEntryService;

  bool _isInitialized = false;
  bool _isLoading = false;
  String? _error;

  AccountingService(this._databaseService) {
    _chartOfAccountsService = ChartOfAccountsService(_databaseService);
    _journalEntryService =
        JournalEntryService(_databaseService, _chartOfAccountsService);

    // Listen to changes
    _chartOfAccountsService.addListener(_notifyListeners);
    _journalEntryService.addListener(_notifyListeners);
  }

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  String? get error => _error;

  ChartOfAccountsService get chartOfAccounts => _chartOfAccountsService;
  JournalEntryService get journalEntries => _journalEntryService;

  List<Account> get accounts => _chartOfAccountsService.accounts;
  List<JournalEntry> get entries => _journalEntryService.journalEntries;

  Future<void> initializeChileanChartOfAccounts() async {
    await initialize();
  }

  Future<Map<AccountType, List<Account>>> getChartOfAccounts() async {
    await initialize();

    final grouped = _chartOfAccountsService.getAccountsGroupedByType();
    final ordered = LinkedHashMap<AccountType, List<Account>>();

    for (final type in AccountType.values) {
      final accountsForType = grouped[type];
      if (accountsForType != null && accountsForType.isNotEmpty) {
        ordered[type] = accountsForType;
      }
    }

    return ordered;
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _chartOfAccountsService.initializeChartOfAccounts();
      await _journalEntryService.ensureLoaded();
      _isInitialized = true;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      rethrow;
    }
  }

  void _notifyListeners() {
    notifyListeners();
  }

  // Account-related methods
  Future<List<Account>> getAccounts({String? searchTerm}) async {
    await initialize();

    if (searchTerm != null && searchTerm.isNotEmpty) {
      return _chartOfAccountsService.searchAccounts(searchTerm);
    }
    return _chartOfAccountsService.accounts;
  }

  Future<Account?> getAccountById(String id) async {
    await initialize();
    return _chartOfAccountsService.getAccountById(id);
  }

  Future<Account?> getAccountByCode(String code) async {
    await initialize();
    return _chartOfAccountsService.getAccountByCode(code);
  }

  Future<void> createAccount(Account account) async {
    await initialize();
    await _chartOfAccountsService.addAccount(account);
  }

  Future<void> updateAccount(Account account) async {
    await initialize();
    await _chartOfAccountsService.updateAccount(account);
  }

  Future<void> deleteAccount(String accountId) async {
    await initialize();
    await _chartOfAccountsService.deleteAccount(accountId);
  }

  // Journal Entry methods
  Future<List<JournalEntry>> getJournalEntries({
    String? searchTerm,
    JournalEntryType? type,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    await initialize();

    await _journalEntryService.ensureLoaded();

    var entries = _journalEntryService.journalEntries;

    if (type != null) {
      entries = _journalEntryService.getEntriesByType(type);
    }

    if (startDate != null && endDate != null) {
      entries = _journalEntryService.getEntriesByDateRange(startDate, endDate);
    }

    if (searchTerm != null && searchTerm.isNotEmpty) {
      entries = _journalEntryService.searchEntries(searchTerm);
    }

    return entries;
  }

  Future<void> createJournalEntry({
    required DateTime date,
    required String description,
    required JournalEntryType type,
    required List<JournalLine> lines,
    String? sourceModule,
    String? sourceReference,
  }) async {
    await initialize();

    final entry = await _journalEntryService.createJournalEntry(
      date: date,
      description: description,
      type: type,
      lines: lines,
      sourceModule: sourceModule,
      sourceReference: sourceReference,
    );

    await _journalEntryService.postJournalEntry(entry);
  }

  Future<void> postSalesEntry({
    required DateTime date,
    required String customerName,
    required String invoiceNumber,
    required double subtotal,
    required double ivaAmount,
    required double total,
    List<SalesLineEntry>? salesLines,
  }) async {
    await initialize();

    await _journalEntryService.postSalesEntry(
      date: date,
      customerName: customerName,
      invoiceNumber: invoiceNumber,
      subtotal: subtotal,
      ivaAmount: ivaAmount,
      total: total,
      salesLines: salesLines,
    );
  }

  Future<void> postPurchaseEntry({
    required DateTime date,
    required String supplierName,
    required String invoiceNumber,
    required double subtotal,
    required double ivaAmount,
    required double total,
  }) async {
    await initialize();

    await _journalEntryService.postPurchaseEntry(
      date: date,
      supplierName: supplierName,
      invoiceNumber: invoiceNumber,
      subtotal: subtotal,
      ivaAmount: ivaAmount,
      total: total,
    );
  }

  Future<void> reverseJournalEntry(String entryId) async {
    await initialize();
    await _journalEntryService.reverseEntry(entryId);
  }

  /// Delete a journal entry (TEMP: for testing)
  Future<void> deleteJournalEntry(String entryId) async {
    await initialize();
    await _journalEntryService.deleteEntry(entryId);
  }

  /// Force reload of journal entries from database
  Future<void> reloadJournalEntries({int limit = 100}) async {
    await _journalEntryService.reload(limit: limit);
  }

  @override
  void dispose() {
    _chartOfAccountsService.removeListener(_notifyListeners);
    _journalEntryService.removeListener(_notifyListeners);
    super.dispose();
  }
}
