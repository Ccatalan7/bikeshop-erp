import 'financial_report.dart';
import 'report_line.dart';

/// Balance Sheet (Balance General)
/// Shows company financial position at a point in time
class BalanceSheet extends FinancialReport {
  // ASSETS
  final List<ReportLine> currentAssets; // Activos Circulantes
  final double totalCurrentAssets;

  final List<ReportLine> fixedAssets; // Activos Fijos
  final double totalFixedAssets;

  final List<ReportLine> otherAssets; // Otros Activos
  final double totalOtherAssets;

  final double totalAssets; // Total Activos

  // LIABILITIES
  final List<ReportLine> currentLiabilities; // Pasivos Circulantes
  final double totalCurrentLiabilities;

  final List<ReportLine> longTermLiabilities; // Pasivos Largo Plazo
  final double totalLongTermLiabilities;

  final double totalLiabilities; // Total Pasivos

  // EQUITY
  final List<ReportLine> equity; // Patrimonio
  final double totalEquity;

  // Period net income (from Income Statement)
  final double periodNetIncome;

  const BalanceSheet({
    required super.startDate,
    required super.endDate,
    required super.companyName,
    required super.generatedAt,
    required this.currentAssets,
    required this.totalCurrentAssets,
    required this.fixedAssets,
    required this.totalFixedAssets,
    required this.otherAssets,
    required this.totalOtherAssets,
    required this.totalAssets,
    required this.currentLiabilities,
    required this.totalCurrentLiabilities,
    required this.longTermLiabilities,
    required this.totalLongTermLiabilities,
    required this.totalLiabilities,
    required this.equity,
    required this.totalEquity,
    required this.periodNetIncome,
  });

  @override
  String get title => 'Balance General';

  @override
  String get subtitle => 'Al ${_formatDate(endDate)}';

  /// Check if accounting equation is balanced
  /// Assets = Liabilities + Equity
  bool get isBalanced {
    final difference = (totalAssets - (totalLiabilities + totalEquity)).abs();
    return difference < 1.00; // Tolerance of 1 peso for rounding
  }

  /// Difference between assets and liabilities + equity
  double get accountingEquationDifference =>
      totalAssets - (totalLiabilities + totalEquity);

  /// Current ratio (liquidity metric)
  /// Current Assets / Current Liabilities
  double get currentRatio => totalCurrentLiabilities > 0
      ? totalCurrentAssets / totalCurrentLiabilities
      : 0;

  /// Quick ratio (acid test - excludes inventory)
  /// (Current Assets - Inventory) / Current Liabilities
  double get quickRatio {
    // Find inventory account
    final inventory = currentAssets.firstWhere(
      (line) =>
          line.code.startsWith('114') ||
          line.name.toLowerCase().contains('inventario'),
      orElse: () => ReportLine.blank(),
    );
    final quickAssets = totalCurrentAssets - inventory.amount;
    return totalCurrentLiabilities > 0
        ? quickAssets / totalCurrentLiabilities
        : 0;
  }

  /// Working capital
  /// Current Assets - Current Liabilities
  double get workingCapital => totalCurrentAssets - totalCurrentLiabilities;

  /// Debt to equity ratio
  /// Total Liabilities / Total Equity
  double get debtToEquityRatio =>
      totalEquity > 0 ? totalLiabilities / totalEquity : 0;

  /// Debt ratio (leverage)
  /// Total Liabilities / Total Assets
  double get debtRatio => totalAssets > 0 ? totalLiabilities / totalAssets : 0;

  /// Equity ratio
  /// Total Equity / Total Assets
  double get equityRatio => totalAssets > 0 ? totalEquity / totalAssets : 0;

  /// Return on equity (ROE) - requires period net income
  /// Net Income / Total Equity
  double get returnOnEquity =>
      totalEquity > 0 ? (periodNetIncome / totalEquity) * 100 : 0;

  /// Return on assets (ROA) - requires period net income
  /// Net Income / Total Assets
  double get returnOnAssets =>
      totalAssets > 0 ? (periodNetIncome / totalAssets) * 100 : 0;

  @override
  List<ReportLine> get allLines {
    final lines = <ReportLine>[];

    // ========== ACTIVOS ==========
    lines.add(ReportLine.total(
      name: 'ACTIVOS',
      amount: 0, // Header only
      code: 'ASSETS',
    ));
    lines.add(ReportLine.blank());

    // Activos Circulantes
    if (currentAssets.isNotEmpty) {
      lines.add(ReportLine.subtotal(
        name: 'Activos Circulantes',
        amount: totalCurrentAssets,
        category: 'currentAsset',
      ));
      lines.addAll(currentAssets);
      lines.add(ReportLine.blank());
    }

    // Activos Fijos
    if (fixedAssets.isNotEmpty) {
      lines.add(ReportLine.subtotal(
        name: 'Activos Fijos',
        amount: totalFixedAssets,
        category: 'fixedAsset',
      ));
      lines.addAll(fixedAssets);
      lines.add(ReportLine.blank());
    }

    // Otros Activos
    if (otherAssets.isNotEmpty) {
      lines.add(ReportLine.subtotal(
        name: 'Otros Activos',
        amount: totalOtherAssets,
        category: 'otherAsset',
      ));
      lines.addAll(otherAssets);
      lines.add(ReportLine.blank());
    }

    // TOTAL ACTIVOS
    lines.add(ReportLine.total(
      name: 'TOTAL ACTIVOS',
      amount: totalAssets,
    ));
    lines.add(ReportLine.blank());
    lines.add(ReportLine.blank());

    // ========== PASIVOS ==========
    lines.add(ReportLine.total(
      name: 'PASIVOS',
      amount: 0, // Header only
      code: 'LIABILITIES',
    ));
    lines.add(ReportLine.blank());

    // Pasivos Circulantes
    if (currentLiabilities.isNotEmpty) {
      lines.add(ReportLine.subtotal(
        name: 'Pasivos Circulantes',
        amount: totalCurrentLiabilities,
        category: 'currentLiability',
      ));
      lines.addAll(currentLiabilities);
      lines.add(ReportLine.blank());
    }

    // Pasivos Largo Plazo
    if (longTermLiabilities.isNotEmpty) {
      lines.add(ReportLine.subtotal(
        name: 'Pasivos Largo Plazo',
        amount: totalLongTermLiabilities,
        category: 'longTermLiability',
      ));
      lines.addAll(longTermLiabilities);
      lines.add(ReportLine.blank());
    }

    // TOTAL PASIVOS
    lines.add(ReportLine.total(
      name: 'TOTAL PASIVOS',
      amount: totalLiabilities,
    ));
    lines.add(ReportLine.blank());
    lines.add(ReportLine.blank());

    // ========== PATRIMONIO ==========
    lines.add(ReportLine.total(
      name: 'PATRIMONIO',
      amount: 0, // Header only
      code: 'EQUITY',
    ));
    lines.add(ReportLine.blank());

    if (equity.isNotEmpty) {
      lines.addAll(equity);
      lines.add(ReportLine.blank());
    }

    // TOTAL PATRIMONIO
    lines.add(ReportLine.total(
      name: 'TOTAL PATRIMONIO',
      amount: totalEquity,
    ));
    lines.add(ReportLine.blank());
    lines.add(ReportLine.blank());

    // ========== TOTAL PASIVOS + PATRIMONIO ==========
    lines.add(ReportLine.total(
      name: 'TOTAL PASIVOS + PATRIMONIO',
      amount: totalLiabilities + totalEquity,
    ));

    return lines;
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'company_name': companyName,
      'generated_at': generatedAt.toIso8601String(),
      'current_assets': currentAssets.map((l) => l.toJson()).toList(),
      'total_current_assets': totalCurrentAssets,
      'fixed_assets': fixedAssets.map((l) => l.toJson()).toList(),
      'total_fixed_assets': totalFixedAssets,
      'other_assets': otherAssets.map((l) => l.toJson()).toList(),
      'total_other_assets': totalOtherAssets,
      'total_assets': totalAssets,
      'current_liabilities': currentLiabilities.map((l) => l.toJson()).toList(),
      'total_current_liabilities': totalCurrentLiabilities,
      'long_term_liabilities':
          longTermLiabilities.map((l) => l.toJson()).toList(),
      'total_long_term_liabilities': totalLongTermLiabilities,
      'total_liabilities': totalLiabilities,
      'equity': equity.map((l) => l.toJson()).toList(),
      'total_equity': totalEquity,
      'period_net_income': periodNetIncome,
      'is_balanced': isBalanced,
      'accounting_equation_difference': accountingEquationDifference,
      'current_ratio': currentRatio,
      'quick_ratio': quickRatio,
      'working_capital': workingCapital,
      'debt_to_equity_ratio': debtToEquityRatio,
      'debt_ratio': debtRatio,
      'equity_ratio': equityRatio,
      'return_on_equity': returnOnEquity,
      'return_on_assets': returnOnAssets,
    };
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  String toString() {
    return 'BalanceSheet(${_formatDate(endDate)}: Assets = \$${totalAssets.toStringAsFixed(2)})';
  }
}
