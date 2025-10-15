/// Model for a single line in a financial report
/// Supports hierarchical display with indentation levels
class ReportLine {
  final String code;
  final String name;
  final double amount;
  final int level; // 0=total, 1=subtotal, 2=account, 3=subaccount
  final bool isBold;
  final bool showAmount;
  final String? parentCode;
  final String? category;

  const ReportLine({
    required this.code,
    required this.name,
    required this.amount,
    this.level = 2,
    this.isBold = false,
    this.showAmount = true,
    this.parentCode,
    this.category,
  });

  /// Helper getters for line types
  bool get isTotal => level == 0;
  bool get isSubtotal => level == 1;
  bool get isAccount => level == 2;
  bool get isSubaccount => level == 3;

  /// Factory for creating total lines
  factory ReportLine.total({
    required String name,
    required double amount,
    String? code,
  }) {
    return ReportLine(
      code: code ?? 'TOTAL',
      name: name,
      amount: amount,
      level: 0,
      isBold: true,
      showAmount: true,
    );
  }

  /// Factory for creating subtotal lines
  factory ReportLine.subtotal({
    required String name,
    required double amount,
    String? code,
    String? category,
  }) {
    return ReportLine(
      code: code ?? 'SUBTOTAL',
      name: name,
      amount: amount,
      level: 1,
      isBold: true,
      showAmount: true,
      category: category,
    );
  }

  /// Factory for creating account lines
  factory ReportLine.account({
    required String code,
    required String name,
    required double amount,
    String? parentCode,
    String? category,
  }) {
    return ReportLine(
      code: code,
      name: name,
      amount: amount,
      level: 2,
      isBold: false,
      showAmount: true,
      parentCode: parentCode,
      category: category,
    );
  }

  /// Factory for creating blank separator lines
  factory ReportLine.blank() {
    return const ReportLine(
      code: '',
      name: '',
      amount: 0,
      level: 2,
      isBold: false,
      showAmount: false,
    );
  }

  /// Factory from database result
  factory ReportLine.fromJson(Map<String, dynamic> json) {
    return ReportLine(
      code: json['account_code']?.toString() ?? '',
      name: json['account_name']?.toString() ?? '',
      amount: _parseDouble(json['amount']) ?? 0.0,
      level: json['level'] as int? ?? 2,
      isBold: json['is_bold'] as bool? ?? false,
      showAmount: json['show_amount'] as bool? ?? true,
      parentCode: json['parent_code']?.toString(),
      category: json['category']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'name': name,
      'amount': amount,
      'level': level,
      'is_bold': isBold,
      'show_amount': showAmount,
      'parent_code': parentCode,
      'category': category,
    };
  }

  ReportLine copyWith({
    String? code,
    String? name,
    double? amount,
    int? level,
    bool? isBold,
    bool? showAmount,
    String? parentCode,
    String? category,
  }) {
    return ReportLine(
      code: code ?? this.code,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      level: level ?? this.level,
      isBold: isBold ?? this.isBold,
      showAmount: showAmount ?? this.showAmount,
      parentCode: parentCode ?? this.parentCode,
      category: category ?? this.category,
    );
  }

  @override
  String toString() {
    return 'ReportLine($code: $name = \$$amount)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReportLine &&
        other.code == code &&
        other.name == name &&
        other.amount == amount &&
        other.level == level;
  }

  @override
  int get hashCode {
    return Object.hash(code, name, amount, level);
  }
}

/// Helper function to parse double from dynamic value
double? _parseDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
