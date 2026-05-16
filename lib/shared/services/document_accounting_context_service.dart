import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DocumentAccountingContext {
  final List<DocumentPaymentRecord> payments;
  final List<DocumentJournalEntryRecord> journalEntries;

  const DocumentAccountingContext({
    this.payments = const [],
    this.journalEntries = const [],
  });

  static const empty = DocumentAccountingContext();
}

class DocumentPaymentRecord {
  final String id;
  final String number;
  final DateTime date;
  final String? reference;
  final String status;
  final String methodName;
  final double amount;

  const DocumentPaymentRecord({
    required this.id,
    required this.number,
    required this.date,
    required this.status,
    required this.methodName,
    required this.amount,
    this.reference,
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

class DocumentAccountingContextService {
  DocumentAccountingContextService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<DocumentAccountingContext> loadSalesInvoice({
    required String invoiceId,
    required String invoiceNumber,
  }) async {
    final payments = await _loadPayments(
      table: 'sales_payments',
      invoiceId: invoiceId,
      paymentPrefix: 'COB',
    );
    final journalEntries = await _loadJournalEntries(
      sourceModule: 'sales_invoices',
      sourceReferences: [invoiceNumber, invoiceId],
    );

    return DocumentAccountingContext(
      payments: payments,
      journalEntries: journalEntries,
    );
  }

  Future<DocumentAccountingContext> loadPurchaseInvoice({
    required String invoiceId,
    required String invoiceNumber,
  }) async {
    final payments = await _loadPayments(
      table: 'purchase_payments',
      invoiceId: invoiceId,
      paymentPrefix: 'PAG',
    );
    final journalEntries = await _loadJournalEntries(
      sourceModule: 'purchase_invoices',
      sourceReferences: [invoiceNumber, invoiceId],
    );

    return DocumentAccountingContext(
      payments: payments,
      journalEntries: journalEntries,
    );
  }

  Future<List<DocumentPaymentRecord>> _loadPayments({
    required String table,
    required String invoiceId,
    required String paymentPrefix,
  }) async {
    try {
      final response = await _client
          .from(table)
          .select()
          .eq('invoice_id', invoiceId)
          .order('date', ascending: false);

      final rows = (response as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .where((row) => row['deleted_at'] == null)
          .toList();

      final methodIds = rows
          .map((row) => row['payment_method_id']?.toString())
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet();
      final methodsById = await _loadPaymentMethods(methodIds);

      return rows.map((row) {
        final id = row['id']?.toString() ?? '';
        final methodId = row['payment_method_id']?.toString();
        return DocumentPaymentRecord(
          id: id,
          number: _shortDocumentNumber(paymentPrefix, id),
          date: _parseDate(row['date']),
          reference: _blankToNull(row['reference']),
          status: 'Pagada',
          methodName: methodsById[methodId] ?? 'Sin método',
          amount: _toDouble(row['amount']),
        );
      }).toList();
    } catch (e) {
      debugPrint('DocumentAccountingContextService._loadPayments error: $e');
      return const [];
    }
  }

  Future<Map<String, String>> _loadPaymentMethods(Set<String> ids) async {
    if (ids.isEmpty) return const {};

    try {
      final response = await _client
          .from('payment_methods')
          .select('id,name')
          .inFilter('id', ids.toList());

      return {
        for (final row in response as List)
          (row as Map)['id'].toString():
              row['name']?.toString() ?? 'Sin método',
      };
    } catch (e) {
      debugPrint(
          'DocumentAccountingContextService._loadPaymentMethods error: $e');
      return const {};
    }
  }

  Future<List<DocumentJournalEntryRecord>> _loadJournalEntries({
    required String sourceModule,
    required List<String?> sourceReferences,
  }) async {
    final uniqueRefs = sourceReferences
        .whereType<String>()
        .map((ref) => ref.trim())
        .where((ref) => ref.isNotEmpty)
        .toSet()
        .toList();
    if (uniqueRefs.isEmpty) return const [];

    try {
      final entriesById = <String, Map<String, dynamic>>{};
      for (final reference in uniqueRefs) {
        final response = await _client
            .from('journal_entries')
            .select()
            .eq('source_module', sourceModule)
            .eq('source_reference', reference)
            .order('entry_date', ascending: false);

        for (final row in response as List) {
          final entry = Map<String, dynamic>.from(row as Map);
          final id = entry['id']?.toString();
          if (id != null && id.isNotEmpty) entriesById[id] = entry;
        }
      }

      if (entriesById.isEmpty) return const [];

      final entryIds = entriesById.keys.toList();
      final lineResponse = await _client
          .from('journal_lines')
          .select()
          .inFilter('entry_id', entryIds);

      final linesByEntry = <String, List<DocumentJournalLineRecord>>{};
      for (final row in lineResponse as List) {
        final line = Map<String, dynamic>.from(row as Map);
        final entryId = line['entry_id']?.toString() ??
            line['journal_entry_id']?.toString();
        if (entryId == null) continue;
        linesByEntry.putIfAbsent(entryId, () => []).add(
              DocumentJournalLineRecord(
                accountCode: line['account_code']?.toString() ?? '',
                accountName: line['account_name']?.toString() ?? '',
                description: line['description']?.toString() ?? '',
                debitAmount: _toDouble(line['debit_amount'] ?? line['debit']),
                creditAmount:
                    _toDouble(line['credit_amount'] ?? line['credit']),
              ),
            );
      }

      final entries = entriesById.values.map((entry) {
        final id = entry['id']?.toString() ?? '';
        final lines = linesByEntry[id] ?? const <DocumentJournalLineRecord>[];
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
}
