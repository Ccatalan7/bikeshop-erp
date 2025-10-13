import 'package:flutter/foundation.dart';

import '../../../shared/services/database_service.dart';
import '../models/account.dart';
import '../models/journal_entry.dart';
import 'chart_of_accounts_service.dart';

class JournalEntryService extends ChangeNotifier {
  final DatabaseService _databaseService;
  final ChartOfAccountsService _chartOfAccountsService;
  final List<JournalEntry> _journalEntries = [];
  int _nextEntryNumber = 1;
  bool _isLoaded = false;

  JournalEntryService(this._databaseService, this._chartOfAccountsService);

  List<JournalEntry> get journalEntries => List.unmodifiable(_journalEntries);

  Future<void> ensureLoaded() async {
    if (_isLoaded) return;
    await loadJournalEntries();
  }

  Future<void> loadJournalEntries({int limit = 100}) async {
    try {
      debugPrint('🔍 Loading journal entries with limit: $limit');
      final startTime = DateTime.now();
      
      // Load only recent entries with limit and ordering
      final entryDocs = await _databaseService.select(
        'journal_entries',
        orderBy: 'entry_date', // Use new column name
        descending: true,
        limit: limit,
      );
      
      final entriesLoadTime = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('✅ Loaded ${entryDocs.length} entries in ${entriesLoadTime}ms');

      if (entryDocs.isEmpty) {
        _journalEntries.clear();
        _isLoaded = true;
        notifyListeners();
        return;
      }

      // Get all entry IDs for efficient line loading
      final entryIds = entryDocs
          .map((e) => e['id']?.toString())
          .where((id) => id != null)
          .cast<String>()
          .toList();
      
      debugPrint('🔍 Loading lines for ${entryIds.length} entries');
      final linesStartTime = DateTime.now();

      // Load only lines for these entries using WHERE IN clause
      final lineDocs = await _databaseService.select(
        'journal_lines',
        where: 'entry_id', // Correct column name from core_schema.sql
        whereIn: entryIds,
      );
      
      final linesLoadTime = DateTime.now().difference(linesStartTime).inMilliseconds;
      debugPrint('✅ Loaded ${lineDocs.length} lines in ${linesLoadTime}ms');

      final linesByEntry = <String, List<JournalLine>>{};
      for (final rawLine in lineDocs) {
        final entryId =
            (rawLine['entry_id'] ?? rawLine['journal_entry_id'])?.toString();
        if (entryId == null) continue;
        final line = _mapLineFromFirestore(rawLine, entryId);
        linesByEntry.putIfAbsent(entryId, () => []).add(line);
      }

      final entries = <JournalEntry>[];
      for (final rawEntry in entryDocs) {
        final entryId = rawEntry['id']?.toString();
        if (entryId == null) continue;
        final lines = linesByEntry[entryId] ?? <JournalLine>[];
        entries.add(_mapEntryFromFirestore(rawEntry, entryId, lines));
      }

      // Already sorted by date DESC from query
      _journalEntries
        ..clear()
        ..addAll(entries);

      _isLoaded = true;
      _syncNextEntryNumber();
      
      final totalTime = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint('✅ TOTAL: Loaded ${entries.length} entries in ${totalTime}ms');
      
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error loading journal entries: $e');
      rethrow;
    }
  }

  Future<JournalEntry> createJournalEntry({
    required DateTime date,
    required String description,
    required JournalEntryType type,
    required List<JournalLine> lines,
    String? sourceModule,
    String? sourceReference,
  }) async {
    await ensureLoaded();

    _validateJournalEntry(lines);

    final totalDebit =
        lines.fold<double>(0.0, (sum, line) => sum + line.debitAmount);
    final totalCredit =
        lines.fold<double>(0.0, (sum, line) => sum + line.creditAmount);

    return JournalEntry(
      entryNumber: _generateEntryNumber(),
      date: date,
      description: description,
      type: type,
      sourceModule: sourceModule,
      sourceReference: sourceReference,
      lines: lines,
      totalDebit: totalDebit,
      totalCredit: totalCredit,
      status: JournalEntryStatus.draft,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  Future<void> postJournalEntry(JournalEntry entry) async {
    await ensureLoaded();

    _validateJournalEntry(entry.lines);

    if (!entry.isBalanced) {
      throw Exception(
          'Journal entry is not balanced. Debits: \$${entry.totalDebit.toStringAsFixed(2)}, Credits: \$${entry.totalCredit.toStringAsFixed(2)}');
    }

    final persistedEntry = await _persistEntry(entry.copyWith(
      status: JournalEntryStatus.posted,
      createdAt: entry.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    ));

    _journalEntries.add(persistedEntry);
    _journalEntries.sort((a, b) => b.date.compareTo(a.date));
    _syncNextEntryNumber();
    notifyListeners();
  }

  Future<void> postAutomaticEntry({
    required DateTime date,
    required String description,
    required JournalEntryType type,
    required List<JournalLine> lines,
    String? sourceModule,
    String? sourceReference,
  }) async {
    final entry = await createJournalEntry(
      date: date,
      description: description,
      type: type,
      lines: lines,
      sourceModule: sourceModule,
      sourceReference: sourceReference,
    );

    await postJournalEntry(entry);
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
    await ensureLoaded();

    final receiptAccount = _resolveSalesReceiptAccount();
    final revenueAccount = _requireAccount(
      _chartOfAccountsService.salesRevenue,
      '4100 - Ingresos por Ventas',
    );
    final ivaDebitAccount = _requireAccount(
      _chartOfAccountsService.ivaDebit,
      '2150 - IVA Débito Fiscal',
    );

    final entryDescription = 'Venta POS $invoiceNumber - $customerName';
    final now = DateTime.now();

    final lines = <JournalLine>[
      _buildDebitLine(
        account: receiptAccount,
        description: entryDescription,
        amount: total,
        createdAt: now,
      ),
      _buildCreditLine(
        account: revenueAccount,
        description: 'Ingreso por venta $invoiceNumber',
        amount: subtotal,
        createdAt: now,
      ),
    ];

    if (ivaAmount.abs() >= 0.01) {
      lines.add(
        _buildCreditLine(
          account: ivaDebitAccount,
          description: 'IVA débito venta $invoiceNumber',
          amount: ivaAmount,
          createdAt: now,
        ),
      );
    }

    final totalCost = salesLines?.fold<double>(
          0.0,
          (sum, line) => sum + line.cost,
        ) ??
        0.0;

    if (totalCost.abs() >= 0.01) {
      final cogsAccount = _requireAccount(
        _chartOfAccountsService.costOfGoodsSold,
        '5100 - Costo de Ventas',
      );
      final inventoryAccount = _requireAccount(
        _chartOfAccountsService.inventory,
        '1150 - Inventarios de Mercaderías',
      );

      final costDescription = salesLines == null || salesLines.isEmpty
          ? 'Costo de ventas $invoiceNumber'
          : 'Costo de ventas ${_summarizeSalesLines(salesLines)}';

      lines.add(
        _buildDebitLine(
          account: cogsAccount,
          description: costDescription,
          amount: totalCost,
          createdAt: now,
        ),
      );
      lines.add(
        _buildCreditLine(
          account: inventoryAccount,
          description: 'Salida inventario venta $invoiceNumber',
          amount: totalCost,
          createdAt: now,
        ),
      );
    }

    await postAutomaticEntry(
      date: date,
      description: entryDescription,
      type: JournalEntryType.sales,
      lines: lines,
      sourceModule: 'Sales',
      sourceReference: invoiceNumber,
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
    await ensureLoaded();

    final inventoryAccount = _requireAccount(
      _chartOfAccountsService.inventory,
      '1150 - Inventarios de Mercaderías',
    );
    final ivaCreditAccount = _requireAccount(
      _chartOfAccountsService.ivaCredit,
      '1180 - IVA Crédito Fiscal',
    );
    final payableAccount = _resolvePurchaseLiabilityAccount();

    final entryDescription = 'Compra $invoiceNumber - $supplierName';
    final now = DateTime.now();

    final lines = <JournalLine>[
      _buildDebitLine(
        account: inventoryAccount,
        description: 'Ingreso inventario $invoiceNumber',
        amount: subtotal,
        createdAt: now,
      ),
    ];

    if (ivaAmount.abs() >= 0.01) {
      lines.add(
        _buildDebitLine(
          account: ivaCreditAccount,
          description: 'IVA crédito compra $invoiceNumber',
          amount: ivaAmount,
          createdAt: now,
        ),
      );
    }

    lines.add(
      _buildCreditLine(
        account: payableAccount,
        description: 'Factura $invoiceNumber - $supplierName',
        amount: total,
        createdAt: now,
      ),
    );

    await postAutomaticEntry(
      date: date,
      description: entryDescription,
      type: JournalEntryType.purchase,
      lines: lines,
      sourceModule: 'Purchases',
      sourceReference: invoiceNumber,
    );
  }

  void _validateJournalEntry(List<JournalLine> lines) {
    if (lines.isEmpty) {
      throw Exception('Journal entry must have at least one line');
    }

    if (lines.length < 2) {
      throw Exception(
          'Journal entry must have at least two lines (double-entry)');
    }

    final totalDebit =
        lines.fold<double>(0.0, (sum, line) => sum + line.debitAmount);
    final totalCredit =
        lines.fold<double>(0.0, (sum, line) => sum + line.creditAmount);

    if ((totalDebit - totalCredit).abs() > 0.01) {
      throw Exception(
          'Journal entry is not balanced. Debits: \$${totalDebit.toStringAsFixed(2)}, Credits: \$${totalCredit.toStringAsFixed(2)}');
    }

    for (final line in lines) {
      if (line.debitAmount > 0 && line.creditAmount > 0) {
        throw Exception(
            'Journal line cannot have both debit and credit amounts');
      }
      if (line.debitAmount == 0 && line.creditAmount == 0) {
        throw Exception('Journal line must have either debit or credit amount');
      }
      if (line.debitAmount < 0 || line.creditAmount < 0) {
        throw Exception('Journal line amounts cannot be negative');
      }

      final account = _chartOfAccountsService.getAccountById(line.accountId);
      if (account == null) {
        throw Exception('Account with ID ${line.accountId} not found');
      }
    }
  }

  List<JournalEntry> getEntriesByType(JournalEntryType type) {
    return _journalEntries.where((entry) => entry.type == type).toList();
  }

  List<JournalEntry> getEntriesByDateRange(
      DateTime startDate, DateTime endDate) {
    return _journalEntries
        .where((entry) =>
            entry.date.isAfter(startDate.subtract(const Duration(days: 1))) &&
            entry.date.isBefore(endDate.add(const Duration(days: 1))))
        .toList();
  }

  List<JournalEntry> getEntriesBySource(
      String sourceModule, String sourceReference) {
    return _journalEntries
        .where((entry) =>
            entry.sourceModule == sourceModule &&
            entry.sourceReference == sourceReference)
        .toList();
  }

  List<JournalEntry> searchEntries(String query) {
    if (query.isEmpty) return _journalEntries;

    final lowerQuery = query.toLowerCase();
    return _journalEntries
        .where((entry) =>
            entry.entryNumber.toLowerCase().contains(lowerQuery) ||
            entry.description.toLowerCase().contains(lowerQuery) ||
            (entry.sourceModule?.toLowerCase().contains(lowerQuery) ?? false) ||
            (entry.sourceReference?.toLowerCase().contains(lowerQuery) ??
                false))
        .toList();
  }

  Future<void> reverseEntry(String entryId) async {
    await ensureLoaded();

    final entryIndex =
        _journalEntries.indexWhere((entry) => entry.id == entryId);
    if (entryIndex == -1) {
      throw Exception('Journal entry not found');
    }

    final originalEntry = _journalEntries[entryIndex];
    if (originalEntry.status == JournalEntryStatus.reversed) {
      throw Exception('Journal entry is already reversed');
    }

    final reverseLines = originalEntry.lines
        .map((line) => line.copyWith(
              debitAmount: line.creditAmount,
              creditAmount: line.debitAmount,
              createdAt: DateTime.now(),
            ))
        .toList();

    if (originalEntry.id == null) {
      throw Exception(
          'Journal entry cannot be reversed because it is missing an identifier');
    }

    await _databaseService.update('journal_entries', originalEntry.id!, {
      'status': JournalEntryStatus.reversed.name,
    });

    _journalEntries[entryIndex] = originalEntry.copyWith(
      status: JournalEntryStatus.reversed,
      updatedAt: DateTime.now(),
    );

    final reverseEntry = await createJournalEntry(
      date: DateTime.now(),
      description: 'REVERSO: ${originalEntry.description}',
      type: originalEntry.type,
      lines: reverseLines,
      sourceModule: originalEntry.sourceModule,
      sourceReference: '${originalEntry.sourceReference}-REV',
    );

    final persistedReverse = await _persistEntry(reverseEntry.copyWith(
      status: JournalEntryStatus.posted,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ));

    _journalEntries.add(persistedReverse);
    _journalEntries.sort((a, b) => b.date.compareTo(a.date));
    _syncNextEntryNumber();
    notifyListeners();
  }

  Future<JournalEntry> _persistEntry(JournalEntry entry) async {
    final entryPayload = {
      'entry_number': entry.entryNumber,
      'date': entry.date.toUtc().toIso8601String(),
      'description': entry.description,
      'type': entry.type.name,
      'source_module': entry.sourceModule,
      'source_reference': entry.sourceReference,
      'status': entry.status.name,
      'total_debit': entry.totalDebit,
      'total_credit': entry.totalCredit,
    };

    final linesPayload = entry.lines
        .map((line) => {
              'account_id': line.accountId,
              'account_code': line.accountCode,
              'account_name': line.accountName,
              'description': line.description,
              'debit': line.debitAmount, // Use new column name
              'credit': line.creditAmount, // Use new column name
            })
        .toList();

    final entryId =
        await _databaseService.createJournalEntry(entryPayload, linesPayload);

    final now = DateTime.now();
    final persistedLines = entry.lines
        .map((line) => line.copyWith(
              journalEntryId: entryId,
              createdAt: line.createdAt ?? now,
            ))
        .toList();

    return entry.copyWith(
      id: entryId,
      lines: persistedLines,
      createdAt: entry.createdAt ?? now,
      updatedAt: now,
    );
  }

  JournalEntry _mapEntryFromFirestore(
    Map<String, dynamic> rawEntry,
    String entryId,
    List<JournalLine> lines,
  ) {
    final data = Map<String, dynamic>.from(rawEntry);
    data['id'] = entryId;
    data['lines'] = lines.map((line) => line.toJson()).toList();
    data['date'] = _toDate(data['date']) ?? DateTime.now();
    data['created_at'] = _toDate(data['created_at']);
    data['updated_at'] = _toDate(data['updated_at']);
    data['total_debit'] = data['total_debit'] ??
        lines.fold<double>(0.0, (sum, line) => sum + line.debitAmount);
    data['total_credit'] = data['total_credit'] ??
        lines.fold<double>(0.0, (sum, line) => sum + line.creditAmount);

    return JournalEntry.fromJson(data);
  }

  JournalLine _mapLineFromFirestore(
      Map<String, dynamic> rawLine, String entryId) {
    final data = Map<String, dynamic>.from(rawLine);
    data['id'] = data['id']?.toString();
    data['entry_id'] = entryId;
    data['account_code'] = data['account_code']?.toString();
    data['account_name'] = data['account_name']?.toString();
    data['description'] = data['description']?.toString();
    data['created_at'] = _toDate(data['created_at']);
    return JournalLine.fromJson(data);
  }

  DateTime? _toDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    final typeLabel = value.runtimeType.toString();
    if (typeLabel == 'Timestamp') {
      try {
        return value.toDate();
      } catch (_) {
        return null;
      }
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  void _syncNextEntryNumber() {
    final regex = RegExp(r'JE\d{6}-(\d{4})');
    int maxNumber = 0;
    for (final entry in _journalEntries) {
      final match = regex.firstMatch(entry.entryNumber);
      if (match != null) {
        final value = int.tryParse(match.group(1) ?? '0') ?? 0;
        if (value > maxNumber) {
          maxNumber = value;
        }
      }
    }
    _nextEntryNumber = maxNumber + 1;
  }

  String _generateEntryNumber() {
    final now = DateTime.now();
    final yearMonth = '${now.year}${now.month.toString().padLeft(2, '0')}';
    final number = _nextEntryNumber.toString().padLeft(4, '0');
    _nextEntryNumber++;
    return 'JE$yearMonth-$number';
  }

  Account _resolveSalesReceiptAccount() {
    final candidates = [
      _chartOfAccountsService.cashAccount,
      _chartOfAccountsService.bankAccount,
      _chartOfAccountsService.accountsReceivable,
    ];

    for (final account in candidates) {
      if (account != null && account.id != null && account.id!.isNotEmpty) {
        return account;
      }
    }

    throw Exception(
        'No se encontró una cuenta de caja/banco/cuentas por cobrar para registrar la venta.');
  }

  Account _resolvePurchaseLiabilityAccount() {
    final candidates = [
      _chartOfAccountsService.accountsPayable,
      _chartOfAccountsService.bankAccount,
      _chartOfAccountsService.cashAccount,
    ];

    for (final account in candidates) {
      if (account != null && account.id != null && account.id!.isNotEmpty) {
        return account;
      }
    }

    throw Exception(
        'No se encontró una cuenta de proveedor/pago para registrar la compra.');
  }

  Account _requireAccount(Account? account, String codeDescription) {
    if (account == null || account.id == null || account.id!.isEmpty) {
      throw Exception(
          'La cuenta requerida "$codeDescription" no está disponible.');
    }
    return account;
  }

  JournalLine _buildDebitLine({
    required Account account,
    required String description,
    required double amount,
    DateTime? createdAt,
  }) {
    final value = _normalizeAmount(amount);
    if (value <= 0) {
      throw Exception('Los débitos deben tener un monto positivo.');
    }

    return JournalLine(
      accountId: account.id!,
      accountCode: account.code,
      accountName: account.name,
      description: description,
      debitAmount: value,
      creditAmount: 0,
      createdAt: createdAt,
    );
  }

  JournalLine _buildCreditLine({
    required Account account,
    required String description,
    required double amount,
    DateTime? createdAt,
  }) {
    final value = _normalizeAmount(amount);
    if (value <= 0) {
      throw Exception('Los créditos deben tener un monto positivo.');
    }

    return JournalLine(
      accountId: account.id!,
      accountCode: account.code,
      accountName: account.name,
      description: description,
      debitAmount: 0,
      creditAmount: value,
      createdAt: createdAt,
    );
  }

  double _normalizeAmount(double value) {
    return (value * 100).roundToDouble() / 100;
  }

  String _summarizeSalesLines(List<SalesLineEntry> salesLines) {
    final names = salesLines
        .where((line) => line.productName.isNotEmpty)
        .map((line) => line.productName)
        .toSet()
        .toList();

    if (names.isEmpty) {
      return 'POS';
    }

    if (names.length <= 3) {
      return names.join(', ');
    }

    final displayed = names.take(3).join(', ');
    return '$displayed y ${names.length - 3} más';
  }
}

class SalesLineEntry {
  final String productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final double cost;

  SalesLineEntry({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.cost,
  });
}
