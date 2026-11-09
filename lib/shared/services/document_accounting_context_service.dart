import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'tenant_service.dart';

class DocumentAccountingContext {
  final List<DocumentPaymentRecord> payments;
  final List<DocumentJournalEntryRecord> journalEntries;

  const DocumentAccountingContext({
    this.payments = const [],
    this.journalEntries = const [],
  });

  static const empty = DocumentAccountingContext();
}

enum DocumentPaymentSourceType {
  salesPayment,
  purchasePayment,
  expense,
  unknown,
}

class DocumentPaymentRecord {
  final String id;
  final String number;
  final DateTime date;
  final String? reference;
  final String status;
  final String methodName;
  final double amount;
  final DocumentPaymentSourceType sourceType;

  const DocumentPaymentRecord({
    required this.id,
    required this.number,
    required this.date,
    required this.status,
    required this.methodName,
    required this.amount,
    this.reference,
    this.sourceType = DocumentPaymentSourceType.unknown,
  });
}

class DocumentJournalEntryRecord {
  final String id;
  final String entryNumber;
  final DateTime date;
  final String description;
  final String status;
  final String sourceModule;
  final String sourceReference;
  final double totalDebit;
  final double totalCredit;
  final List<DocumentJournalLineRecord> lines;

  const DocumentJournalEntryRecord({
    required this.id,
    required this.entryNumber,
    required this.date,
    required this.description,
    required this.status,
    required this.sourceModule,
    required this.sourceReference,
    required this.totalDebit,
    required this.totalCredit,
    required this.lines,
  });
}

class DocumentJournalLineRecord {
  final String accountCode;
  final String accountName;
  final String description;
  final double debitAmount;
  final double creditAmount;

  const DocumentJournalLineRecord({
    required this.accountCode,
    required this.accountName,
    required this.description,
    required this.debitAmount,
    required this.creditAmount,
  });
}

/// Payments, linked expenses and journal of one document.
///
/// Every server trip costs ~250 ms from the shop (measured 2026-11-08), so the
/// independent reads go out together: the old chain of up to eight trips one
/// after another kept «Cargando pagos y diario...» on screen for ~2 s on every
/// invoice. The tenant comes from [TenantService], which resolves the one
/// active profile once per signed-in user instead of once per document.
class DocumentAccountingContextService {
  DocumentAccountingContextService({
    SupabaseClient? client,
    TenantService? tenantService,
  })  : _client = client ?? Supabase.instance.client,
        _tenantServiceOverride = tenantService;

  final SupabaseClient _client;
  final TenantService? _tenantServiceOverride;

  TenantService get _tenantService => _tenantServiceOverride ?? TenantService();

  Future<DocumentAccountingContext> loadSalesInvoice({
    required String invoiceId,
    required String invoiceNumber,
  }) async {
    final tenantId = await _resolveTenantId();
    if (tenantId == null) return DocumentAccountingContext.empty;
    final (payments, journalEntries) = await (
      _loadPayments(
        table: 'sales_payments',
        invoiceId: invoiceId,
        tenantId: tenantId,
        paymentPrefix: 'COB',
        sourceType: DocumentPaymentSourceType.salesPayment,
      ),
      _loadJournalEntries(
        sourceModule: 'sales_invoices',
        sourceReferences: [invoiceNumber, invoiceId],
        tenantId: tenantId,
      ),
    ).wait;

    return DocumentAccountingContext(
      payments: payments,
      journalEntries: journalEntries,
    );
  }

  /// Loads the accounting evidence owned by one received payment. Revenue,
  /// IVA and inventory remain on the invoice journal; this context contains
  /// only the receivable-settlement journal sourced by the payment UUID.
  Future<DocumentAccountingContext> loadSalesPayment({
    required String paymentId,
  }) async {
    final tenantId = await _resolveTenantId();
    if (tenantId == null) return DocumentAccountingContext.empty;
    final journalEntries = await _loadJournalEntries(
      sourceModule: 'sales_payments',
      sourceReferences: [paymentId],
      tenantId: tenantId,
    );
    return DocumentAccountingContext(journalEntries: journalEntries);
  }

  Future<DocumentAccountingContext> loadPurchaseInvoice({
    required String invoiceId,
    required String invoiceNumber,
  }) async {
    final tenantId = await _resolveTenantId();
    if (tenantId == null) return DocumentAccountingContext.empty;
    final (payments, linkedExpenses, journalEntries) = await (
      _loadPayments(
        table: 'purchase_payments',
        invoiceId: invoiceId,
        tenantId: tenantId,
        paymentPrefix: 'PAG',
        sourceType: DocumentPaymentSourceType.purchasePayment,
      ),
      _loadLinkedPurchaseExpenses(
        purchaseInvoiceId: invoiceId,
        tenantId: tenantId,
      ),
      _loadJournalEntries(
        sourceModule: 'purchase_invoices',
        sourceReferences: [invoiceNumber, invoiceId],
        tenantId: tenantId,
      ),
    ).wait;

    return DocumentAccountingContext(
      payments: [...payments, ...linkedExpenses]
        ..sort((left, right) => right.date.compareTo(left.date)),
      journalEntries: journalEntries,
    );
  }

  /// Loads the accounts-payable settlement journal owned by one supplier
  /// payment. The purchase invoice remains the owner of inventory, expense,
  /// recoverable IVA and the original accounts-payable recognition.
  Future<DocumentAccountingContext> loadPurchasePayment({
    required String paymentId,
  }) async {
    final tenantId = await _resolveTenantId();
    if (tenantId == null) return DocumentAccountingContext.empty;
    final journalEntries = await _loadJournalEntries(
      sourceModule: 'purchase_payments',
      sourceReferences: [paymentId],
      tenantId: tenantId,
    );
    return DocumentAccountingContext(journalEntries: journalEntries);
  }

  Future<List<DocumentPaymentRecord>> _loadPayments({
    required String table,
    required String invoiceId,
    required String tenantId,
    required String paymentPrefix,
    required DocumentPaymentSourceType sourceType,
  }) async {
    try {
      // The method's name rides in the same trip; a method of another tenant
      // never names a payment here.
      final response = await _client
          .from(table)
          .select('*, payment_methods(name)')
          .eq('tenant_id', tenantId)
          .eq('invoice_id', invoiceId)
          .eq('payment_methods.tenant_id', tenantId)
          .order('date', ascending: false);

      final rows = (response as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .where((row) => row['deleted_at'] == null)
          .toList();

      return rows.map((row) {
        final id = row['id']?.toString() ?? '';
        return DocumentPaymentRecord(
          id: id,
          number: _shortDocumentNumber(paymentPrefix, id),
          date: _parseDate(row['date']),
          reference: _blankToNull(row['reference']),
          status: 'Pagada',
          methodName: _methodName(row['payment_methods']),
          amount: _toDouble(row['amount']),
          sourceType: sourceType,
        );
      }).toList();
    } catch (e) {
      debugPrint('DocumentAccountingContextService._loadPayments error: $e');
      return const [];
    }
  }

  Future<List<DocumentPaymentRecord>> _loadLinkedPurchaseExpenses({
    required String purchaseInvoiceId,
    required String tenantId,
  }) async {
    try {
      final response = await _client
          .from('expense_links')
          .select(
            'expense_id, link_kind, allocated_amount, notes, expenses(id, expense_number, supplier_name, issue_date, total_amount, payment_status, payment_method_id, payment_methods(name))',
          )
          .eq('tenant_id', tenantId)
          .eq('purchase_invoice_id', purchaseInvoiceId)
          .eq('expenses.payment_methods.tenant_id', tenantId)
          .order('created_at', ascending: false);

      final rows = (response as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();

      return rows.map((row) {
        final expense = _parseNestedMap(row['expenses']) ?? const {};
        final expenseId =
            expense['id']?.toString() ?? row['expense_id']?.toString() ?? '';
        final linkKind = _linkKindLabel(row['link_kind']?.toString());
        final supplierName = _blankToNull(expense['supplier_name']);
        final amount = _toDouble(row['allocated_amount']) > 0
            ? _toDouble(row['allocated_amount'])
            : _toDouble(expense['total_amount']);

        return DocumentPaymentRecord(
          id: expenseId,
          number:
              expense['expense_number']?.toString().trim().isNotEmpty == true
                  ? expense['expense_number'].toString()
                  : _shortDocumentNumber('GTO', expenseId),
          date: _parseDate(expense['issue_date']),
          reference: [
            linkKind,
            if (supplierName != null) supplierName,
          ].join(' · '),
          status: _expensePaymentStatusLabel(
            expense['payment_status']?.toString(),
          ),
          methodName: _methodName(expense['payment_methods']),
          amount: amount,
          sourceType: DocumentPaymentSourceType.expense,
        );
      }).toList();
    } catch (e) {
      debugPrint(
        'DocumentAccountingContextService._loadLinkedPurchaseExpenses error: $e',
      );
      return const [];
    }
  }

  static String _methodName(dynamic embedded) =>
      _blankToNull(_parseNestedMap(embedded)?['name']) ?? 'Sin método';

  /// `journal_lines` has two identical foreign keys to `journal_entries`
  /// (`journal_lines_entry_id_fkey` and `journal_lines_journal_entry_id_fkey`),
  /// so the embed has to name one of them.
  @visibleForTesting
  static const journalLinesEmbed =
      'journal_lines!journal_lines_entry_id_fkey(*)';

  /// Entries of [sourceModule] whose source is any of [references], each with
  /// its `journal_lines` rows, in one trip. If the database stops answering
  /// that embed (the named key renamed or dropped), it reads entries and then
  /// lines in two trips, as before, instead of showing an empty journal.
  Future<List<Map<String, dynamic>>> _queryJournalEntryRows({
    required String sourceModule,
    required List<String> references,
    required String tenantId,
  }) async {
    try {
      final response = await _client
          .from('journal_entries')
          .select('*, $journalLinesEmbed')
          .eq('tenant_id', tenantId)
          .eq('source_module', sourceModule)
          .inFilter('source_reference', references)
          .eq('journal_lines.tenant_id', tenantId)
          .order('entry_date', ascending: false);
      return (response as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
    } on PostgrestException catch (error) {
      debugPrint(
        'DocumentAccountingContextService: journal in one trip failed '
        '(${error.code}); reading entries and lines apart.',
      );
    }

    final responses = await Future.wait([
      for (final reference in references)
        _client
            .from('journal_entries')
            .select()
            .eq('tenant_id', tenantId)
            .eq('source_module', sourceModule)
            .eq('source_reference', reference)
            .order('entry_date', ascending: false),
    ]);
    final entriesById = <String, Map<String, dynamic>>{};
    for (final response in responses) {
      for (final row in response as List) {
        final entry = Map<String, dynamic>.from(row as Map);
        final id = entry['id']?.toString();
        if (id != null && id.isNotEmpty) entriesById[id] = entry;
      }
    }
    if (entriesById.isEmpty) return const [];

    final lineResponse = await _client
        .from('journal_lines')
        .select()
        .eq('tenant_id', tenantId)
        .inFilter('entry_id', entriesById.keys.toList());
    for (final row in lineResponse as List) {
      final line = Map<String, dynamic>.from(row as Map);
      final entryId =
          line['entry_id']?.toString() ?? line['journal_entry_id']?.toString();
      final entry = entryId == null ? null : entriesById[entryId];
      if (entry == null) continue;
      final lines = (entry['journal_lines'] as List?) ?? <dynamic>[];
      entry['journal_lines'] = lines..add(line);
    }
    return entriesById.values.toList();
  }

  static DocumentJournalLineRecord _journalLine(Map<String, dynamic> line) =>
      DocumentJournalLineRecord(
        accountCode: line['account_code']?.toString() ?? '',
        accountName: line['account_name']?.toString() ?? '',
        description: line['description']?.toString() ?? '',
        debitAmount: _toDouble(line['debit_amount'] ?? line['debit']),
        creditAmount: _toDouble(line['credit_amount'] ?? line['credit']),
      );

  Future<List<DocumentJournalEntryRecord>> _loadJournalEntries({
    required String sourceModule,
    required List<String?> sourceReferences,
    required String tenantId,
  }) async {
    final uniqueRefs = sourceReferences
        .whereType<String>()
        .map((ref) => ref.trim())
        .where((ref) => ref.isNotEmpty)
        .toSet()
        .toList();
    if (uniqueRefs.isEmpty) return const [];

    try {
      final entryRows = await _queryJournalEntryRows(
        sourceModule: sourceModule,
        references: uniqueRefs,
        tenantId: tenantId,
      );
      if (entryRows.isEmpty) return const [];

      final entriesById = <String, Map<String, dynamic>>{
        for (final entry in entryRows)
          if (entry['id']?.toString().isNotEmpty == true)
            entry['id'].toString(): entry,
      };

      final entries = entriesById.values.map((entry) {
        final id = entry['id']?.toString() ?? '';
        final lines = [
          for (final raw in (entry['journal_lines'] as List?) ?? const [])
            _journalLine(Map<String, dynamic>.from(raw as Map)),
        ];
        final totalDebit = _toDouble(entry['total_debit']);
        final totalCredit = _toDouble(entry['total_credit']);

        return DocumentJournalEntryRecord(
          id: id,
          entryNumber: entry['entry_number']?.toString() ?? '',
          date: _parseDate(entry['entry_date'] ?? entry['date']),
          description: entry['description']?.toString() ??
              entry['notes']?.toString() ??
              '',
          status: entry['status']?.toString() ?? 'posted',
          sourceModule: entry['source_module']?.toString() ?? sourceModule,
          sourceReference: entry['source_reference']?.toString() ?? '',
          totalDebit: totalDebit > 0
              ? totalDebit
              : lines.fold<double>(0, (sum, line) => sum + line.debitAmount),
          totalCredit: totalCredit > 0
              ? totalCredit
              : lines.fold<double>(0, (sum, line) => sum + line.creditAmount),
          lines: [...lines]
            ..sort((a, b) => a.accountCode.compareTo(b.accountCode)),
        );
      }).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

      return entries;
    } catch (e) {
      debugPrint(
          'DocumentAccountingContextService._loadJournalEntries error: $e');
      return const [];
    }
  }

  static String _shortDocumentNumber(String prefix, String id) {
    if (id.isEmpty) return '$prefix-000000';
    final compact = id.replaceAll('-', '').toUpperCase();
    final suffix = compact.length <= 6
        ? compact.padLeft(6, '0')
        : compact.substring(compact.length - 6);
    return '$prefix-$suffix';
  }

  /// The one active profile's tenant, fail-closed, as [TenantService] owns it.
  Future<String?> _resolveTenantId() async {
    final tenantId = (await _tenantService.getTenantId())?.trim();
    return tenantId?.isNotEmpty == true ? tenantId : null;
  }

  static DateTime _parseDate(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }

  static double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0;
    }
    return 0;
  }

  static String? _blankToNull(dynamic value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static Map<String, dynamic>? _parseNestedMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, dynamic val) => MapEntry(key.toString(), val));
    }
    return null;
  }

  static String _expensePaymentStatusLabel(String? value) {
    switch (value) {
      case 'paid':
        return 'Pagada';
      case 'partial':
        return 'Parcial';
      case 'scheduled':
        return 'Programada';
      case 'void':
        return 'Anulada';
      case 'pending':
      default:
        return 'Pendiente';
    }
  }

  static String _linkKindLabel(String? value) {
    switch (value) {
      case 'delivery':
        return 'Entrega / transporte';
      case 'import_cost':
        return 'Costo de importación';
      default:
        return 'Gasto relacionado';
    }
  }
}
