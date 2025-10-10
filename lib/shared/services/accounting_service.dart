import 'package:flutter/foundation.dart';

class JournalEntry {
  final String id;
  final String description;
  final DateTime date;
  final List<JournalLine> lines;
  final String? reference;
  final String? source; // POS, Invoice, etc.
  final bool isPosted;

  const JournalEntry({
    required this.id,
    required this.description,
    required this.date,
    required this.lines,
    this.reference,
    this.source,
    this.isPosted = false,
  });

  double get totalDebits => lines.fold(0.0, (sum, line) => sum + line.debit);
  double get totalCredits => lines.fold(0.0, (sum, line) => sum + line.credit);
  bool get isBalanced => (totalDebits - totalCredits).abs() < 0.01;
}

class JournalLine {
  final String accountCode;
  final String accountName;
  final double debit;
  final double credit;
  final String? description;

  const JournalLine({
    required this.accountCode,
    required this.accountName,
    required this.debit,
    required this.credit,
    this.description,
  });
}

class AccountingService extends ChangeNotifier {
  final List<JournalEntry> _journalEntries = [];
  
  List<JournalEntry> get journalEntries => List.unmodifiable(_journalEntries);

  // Tax rate for Chile (IVA)
  static const double ivaRate = 0.19;

  Future<String> createPOSJournalEntry({
    required String transactionId,
    required double subtotal,
    required double taxAmount,
    required double total,
    required double totalCost,
    required String paymentAccountCode,
    required String paymentAccountName,
  }) async {
    if (kDebugMode) print('AccountingService: Creating POS journal entry for transaction $transactionId');

    final entryId = 'JE-POS-${DateTime.now().millisecondsSinceEpoch}';
    
    final lines = <JournalLine>[
      // Debit: Cash/Bank (payment method)
      JournalLine(
        accountCode: paymentAccountCode,
        accountName: paymentAccountName,
        debit: total,
        credit: 0,
        description: 'Venta POS',
      ),
      // Credit: Sales Revenue (excluding tax)
      JournalLine(
        accountCode: '4101',
        accountName: 'Ventas Mercaderías',
        debit: 0,
        credit: subtotal,
        description: 'Venta POS',
      ),
      // Credit: IVA Débito Fiscal
      JournalLine(
        accountCode: '2103',
        accountName: 'IVA Débito Fiscal',
        debit: 0,
        credit: taxAmount,
        description: 'IVA Venta POS',
      ),
      // Debit: Cost of Goods Sold
      JournalLine(
        accountCode: '5101',
        accountName: 'Costo de Ventas',
        debit: totalCost,
        credit: 0,
        description: 'Costo POS',
      ),
      // Credit: Inventory
      JournalLine(
        accountCode: '1201',
        accountName: 'Inventario Mercaderías',
        debit: 0,
        credit: totalCost,
        description: 'Salida Inventario POS',
      ),
    ];

    final entry = JournalEntry(
      id: entryId,
      description: 'Venta POS #$transactionId',
      date: DateTime.now(),
      lines: lines,
      reference: transactionId,
      source: 'POS',
      isPosted: true,
    );

    if (!entry.isBalanced) {
      throw Exception('Journal entry is not balanced: Debits=${entry.totalDebits}, Credits=${entry.totalCredits}');
    }

    _journalEntries.add(entry);
    notifyListeners();

    return entryId;
  }

  Future<List<JournalEntry>> getPOSEntries() async {
    return _journalEntries.where((entry) => entry.source == 'POS').toList();
  }

  // Calculate tax amount from net amount
  static double calculateTax(double netAmount) {
    return netAmount * ivaRate;
  }

  // Calculate net amount from gross amount (includes tax)
  static double calculateNetFromGross(double grossAmount) {
    return grossAmount / (1 + ivaRate);
  }

  // Calculate gross amount from net amount
  static double calculateGrossFromNet(double netAmount) {
    return netAmount * (1 + ivaRate);
  }
}