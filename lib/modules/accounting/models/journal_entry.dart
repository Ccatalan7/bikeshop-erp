class JournalEntry {
  final String? id;
  final String entryNumber;
  final DateTime date;
  final String description;
  final JournalEntryType type;
  final String? sourceModule;
  final String? sourceReference;
  final List<JournalLine> lines;
  final JournalEntryStatus status;
  final double totalDebit;
  final double totalCredit;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const JournalEntry({
    this.id,
    required this.entryNumber,
    required this.date,
    required this.description,
    required this.type,
    this.sourceModule,
    this.sourceReference,
    required this.lines,
    this.status = JournalEntryStatus.draft,
    required this.totalDebit,
    required this.totalCredit,
    this.createdAt,
    this.updatedAt,
  });

  factory JournalEntry.fromJson(Map<String, dynamic> json) {
    return JournalEntry(
      id: json['id']?.toString(),
      entryNumber: json['entry_number'] as String,
      date: _parseDate(json['entry_date'] ?? json['date']), // Support both column names
      description: json['notes'] ?? json['description'] ?? '', // Support both column names
      type: JournalEntryType.values.firstWhere(
        (e) => e.name == (json['entry_type'] ?? json['type']),
        orElse: () => JournalEntryType.manual,
      ),
      sourceModule: json['source_module'] as String?,
      sourceReference: json['source_reference'] as String?,
      lines: (json['lines'] as List?)
          ?.map((line) => JournalLine.fromJson(line))
          .toList() ?? [],
      status: JournalEntryStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => JournalEntryStatus.draft,
      ),
      totalDebit: _parseDouble(json['total_debit']) ?? 0.0,
      totalCredit: _parseDouble(json['total_credit']) ?? 0.0,
      createdAt: _parseNullableDate(json['created_at']),
      updatedAt: _parseNullableDate(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entry_number': entryNumber,
      'entry_date': date.toIso8601String(), // Use new column name
      'notes': description, // Use new column name
      'entry_type': type.name, // Use new column name
      'source_module': sourceModule,
      'source_reference': sourceReference,
      'lines': lines.map((line) => line.toJson()).toList(),
      'status': status.name,
      'total_debit': totalDebit,
      'total_credit': totalCredit,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  JournalEntry copyWith({
    String? id,
    String? entryNumber,
    DateTime? date,
    String? description,
    JournalEntryType? type,
    String? sourceModule,
    String? sourceReference,
    List<JournalLine>? lines,
    JournalEntryStatus? status,
    double? totalDebit,
    double? totalCredit,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return JournalEntry(
      id: id ?? this.id,
      entryNumber: entryNumber ?? this.entryNumber,
      date: date ?? this.date,
      description: description ?? this.description,
      type: type ?? this.type,
      sourceModule: sourceModule ?? this.sourceModule,
      sourceReference: sourceReference ?? this.sourceReference,
      lines: lines ?? this.lines,
      status: status ?? this.status,
      totalDebit: totalDebit ?? this.totalDebit,
      totalCredit: totalCredit ?? this.totalCredit,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  bool get isBalanced => (totalDebit - totalCredit).abs() < 0.01;

  @override
  String toString() {
    return 'JournalEntry(${entryNumber}: ${description})';
  }
}

class JournalLine {
  final String? id;
  final String? journalEntryId;
  final String accountId;
  final String accountCode;
  final String accountName;
  final String description;
  final double debitAmount;
  final double creditAmount;
  final DateTime? createdAt;

  const JournalLine({
    this.id,
    this.journalEntryId,
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.description,
    required this.debitAmount,
    required this.creditAmount,
    this.createdAt,
  });

  factory JournalLine.fromJson(Map<String, dynamic> json) {
    return JournalLine(
      id: json['id']?.toString(),
      journalEntryId: json['journal_entry_id']?.toString() ?? json['entry_id']?.toString(),
      accountId: json['account_id']?.toString() ?? '',
      accountCode: json['account_code']?.toString() ?? '',
      accountName: json['account_name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      debitAmount: _parseDouble(json['debit'] ?? json['debit_amount']) ?? 0.0, // Support both column names
      creditAmount: _parseDouble(json['credit'] ?? json['credit_amount']) ?? 0.0, // Support both column names
      createdAt: _parseNullableDate(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'journal_entry_id': journalEntryId, // Use new column name
      'account_id': accountId,
      'account_code': accountCode,
      'account_name': accountName,
      'description': description,
      'debit': debitAmount, // Use new column name
      'credit': creditAmount, // Use new column name
      'created_at': createdAt?.toIso8601String(),
    };
  }

  JournalLine copyWith({
    String? id,
    String? journalEntryId,
    String? accountId,
    String? accountCode,
    String? accountName,
    String? description,
    double? debitAmount,
    double? creditAmount,
    DateTime? createdAt,
  }) {
    return JournalLine(
      id: id ?? this.id,
      journalEntryId: journalEntryId ?? this.journalEntryId,
      accountId: accountId ?? this.accountId,
      accountCode: accountCode ?? this.accountCode,
      accountName: accountName ?? this.accountName,
      description: description ?? this.description,
      debitAmount: debitAmount ?? this.debitAmount,
      creditAmount: creditAmount ?? this.creditAmount,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  double get amount => debitAmount > 0 ? debitAmount : creditAmount;
  bool get isDebit => debitAmount > 0;
  bool get isCredit => creditAmount > 0;

  @override
  String toString() {
    return 'JournalLine(${accountCode}: ${isDebit ? 'Dr' : 'Cr'} \$${amount.toStringAsFixed(2)})';
  }
}

DateTime _parseDate(dynamic value) {
  if (value is DateTime) return value;
  if (value is String) return DateTime.parse(value);
  final timestamp = _resolveTimestamp(value);
  if (timestamp != null) {
    return timestamp;
  }
  throw ArgumentError('Unsupported date value: $value');
}

DateTime? _parseNullableDate(dynamic value) {
  if (value == null) return null;
  return _parseDate(value);
}

double? _parseDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

int _parseInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    return int.tryParse(value) ?? 0;
  }
  throw ArgumentError('Unsupported int value: $value');
}

DateTime? _resolveTimestamp(dynamic value) {
  final timestampType = value?.runtimeType.toString();
  if (timestampType == 'Timestamp') {
    final toDateMethod = value?.toDate;
    if (toDateMethod != null) {
      return toDateMethod();
    }
  }
  return null;
}

enum JournalEntryType {
  manual('Manual'),
  sales('Venta'),
  purchase('Compra'),
  payment('Pago'),
  receipt('Cobro'),
  adjustment('Ajuste'),
  closing('Cierre'),
  opening('Apertura');

  const JournalEntryType(this.displayName);
  final String displayName;
}

enum JournalEntryStatus {
  draft('Borrador'),
  posted('Contabilizado'),
  reversed('Reversado');

  const JournalEntryStatus(this.displayName);
  final String displayName;
}
