class Account {
  final int? id;
  final String code;
  final String name;
  final AccountType type;
  final int? parentId;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  Account({
    this.id,
    required this.code,
    required this.name,
    required this.type,
    this.parentId,
    this.isActive = true,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id'],
      code: json['code'],
      name: json['name'],
      type: AccountType.values.firstWhere(
        (e) => e.toString().split('.').last == json['type'],
      ),
      parentId: json['parent_id'],
      isActive: json['is_active'] ?? true,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'type': type.toString().split('.').last,
      'parent_id': parentId,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Account copyWith({
    int? id,
    String? code,
    String? name,
    AccountType? type,
    int? parentId,
    bool? isActive,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Account(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      type: type ?? this.type,
      parentId: parentId ?? this.parentId,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

enum AccountType {
  asset,
  liability,
  equity,
  income,
  expense,
}

enum AccountCategory {
  currentAssets,
  fixedAssets,
  currentLiabilities,
  longTermLiabilities,
  equity,
  revenue,
  operatingExpenses,
  financialExpenses,
}

// Chart of Account is essentially the same as Account but with additional metadata
typedef ChartOfAccount = Account;

class JournalEntry {
  final int? id;
  final String description;
  final DateTime date;
  final String? reference;
  final JournalEntryStatus status;
  final JournalEntryType type;
  final List<JournalLine> lines;
  final DateTime createdAt;
  final DateTime updatedAt;

  JournalEntry({
    this.id,
    required this.description,
    required this.date,
    this.reference,
    this.status = JournalEntryStatus.draft,
    this.type = JournalEntryType.manual,
    this.lines = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory JournalEntry.fromJson(Map<String, dynamic> json) {
    return JournalEntry(
      id: json['id'],
      description: json['description'],
      date: DateTime.parse(json['date']),
      reference: json['reference'],
      status: JournalEntryStatus.values.firstWhere(
        (e) => e.toString().split('.').last == json['status'],
        orElse: () => JournalEntryStatus.draft,
      ),
      type: JournalEntryType.values.firstWhere(
        (e) => e.toString().split('.').last == json['type'],
        orElse: () => JournalEntryType.manual,
      ),
      lines: (json['lines'] as List<dynamic>?)
              ?.map((line) => JournalLine.fromJson(line))
              .toList() ??
          [],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'description': description,
      'date': date.toIso8601String(),
      'reference': reference,
      'status': status.toString().split('.').last,
      'type': type.toString().split('.').last,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  double get totalDebits {
    return lines.fold(0.0, (sum, line) => sum + line.debit);
  }

  double get totalCredits {
    return lines.fold(0.0, (sum, line) => sum + line.credit);
  }

  bool get isBalanced {
    return (totalDebits - totalCredits).abs() < 0.01;
  }

  JournalEntry copyWith({
    int? id,
    String? description,
    DateTime? date,
    String? reference,
    JournalEntryStatus? status,
    JournalEntryType? type,
    List<JournalLine>? lines,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return JournalEntry(
      id: id ?? this.id,
      description: description ?? this.description,
      date: date ?? this.date,
      reference: reference ?? this.reference,
      status: status ?? this.status,
      type: type ?? this.type,
      lines: lines ?? this.lines,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

enum JournalEntryStatus {
  draft,
  posted,
  reversed,
}

enum JournalEntryType {
  manual,
  sale,
  purchase,
  payment,
  adjustment,
  payroll,
  closing,
}

class JournalLine {
  final int? id;
  final int? entryId;
  final int accountId;
  final String? accountCode;
  final String? accountName;
  final double debit;
  final double credit;
  final String? description;

  JournalLine({
    this.id,
    this.entryId,
    required this.accountId,
    this.accountCode,
    this.accountName,
    this.debit = 0.0,
    this.credit = 0.0,
    this.description,
  });

  factory JournalLine.fromJson(Map<String, dynamic> json) {
    return JournalLine(
      id: json['id'],
      entryId: json['entry_id'],
      accountId: json['account_id'],
      accountCode: json['account_code'],
      accountName: json['account_name'],
      debit: (json['debit'] as num).toDouble(),
      credit: (json['credit'] as num).toDouble(),
      description: json['description'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'entry_id': entryId,
      'account_id': accountId,
      'debit': debit,
      'credit': credit,
      'description': description,
    };
  }

  JournalLine copyWith({
    int? id,
    int? entryId,
    int? accountId,
    String? accountCode,
    String? accountName,
    double? debit,
    double? credit,
    String? description,
  }) {
    return JournalLine(
      id: id ?? this.id,
      entryId: entryId ?? this.entryId,
      accountId: accountId ?? this.accountId,
      accountCode: accountCode ?? this.accountCode,
      accountName: accountName ?? this.accountName,
      debit: debit ?? this.debit,
      credit: credit ?? this.credit,
      description: description ?? this.description,
    );
  }
}
