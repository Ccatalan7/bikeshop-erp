import 'financial_report.dart';
import 'report_line.dart';

/// Income Statement (Estado de Resultados)
/// Shows company profitability over a period
class IncomeStatement extends FinancialReport {
  // Revenue sections
  final List<ReportLine> operatingIncome; // Ingresos Operacionales
  final double totalOperatingIncome;

  final List<ReportLine> nonOperatingIncome; // Ingresos No Operacionales
  final double totalNonOperatingIncome;

  // Cost and expense sections
  final List<ReportLine> costOfSales; // Costo de Ventas
  final double totalCostOfSales;

  final List<ReportLine> operatingExpenses; // Gastos Operacionales
  final double totalOperatingExpenses;

  final List<ReportLine> financialExpenses; // Gastos Financieros
  final double totalFinancialExpenses;

  // Tax section
  final List<ReportLine> taxes; // Impuestos
  final double totalTaxes;

  // Calculated totals
  final double grossProfit; // Utilidad Bruta
  final double operatingProfit; // Utilidad Operacional
  final double profitBeforeTax; // Utilidad Antes de Impuestos
  final double netIncome; // Utilidad Neta

  const IncomeStatement({
    required super.startDate,
    required super.endDate,
    required super.companyName,
    required super.generatedAt,
    required this.operatingIncome,
    required this.totalOperatingIncome,
    required this.nonOperatingIncome,
    required this.totalNonOperatingIncome,
    required this.costOfSales,
    required this.totalCostOfSales,
    required this.operatingExpenses,
    required this.totalOperatingExpenses,
    required this.financialExpenses,
    required this.totalFinancialExpenses,
    required this.taxes,
    required this.totalTaxes,
    required this.grossProfit,
    required this.operatingProfit,
    required this.profitBeforeTax,
    required this.netIncome,
  });

  @override
  String get title => 'Estado de Resultados';

  /// Total revenue (all income)
  double get totalRevenue => totalOperatingIncome + totalNonOperatingIncome;

  /// Total expenses (all costs and expenses)
  double get totalExpenses =>
      totalCostOfSales +
      totalOperatingExpenses +
      totalFinancialExpenses +
      totalTaxes;

  /// Gross profit margin (%)
  double get grossMargin =>
      totalOperatingIncome > 0 ? (grossProfit / totalOperatingIncome) * 100 : 0;

  /// Operating profit margin (%)
  double get operatingMargin =>
      totalOperatingIncome > 0 ? (operatingProfit / totalOperatingIncome) * 100 : 0;

  /// Net profit margin (%)
  double get netMargin =>
      totalRevenue > 0 ? (netIncome / totalRevenue) * 100 : 0;

  /// Check if company is profitable
  bool get isProfitable => netIncome > 0;

  @override
  List<ReportLine> get allLines {
    final lines = <ReportLine>[];

    // INGRESOS OPERACIONALES
    if (operatingIncome.isNotEmpty) {
      lines.add(ReportLine.subtotal(
        name: 'INGRESOS OPERACIONALES',
        amount: totalOperatingIncome,
        category: 'operatingIncome',
      ));
      lines.addAll(operatingIncome);
      lines.add(ReportLine.blank());
    }

    // INGRESOS NO OPERACIONALES
    if (nonOperatingIncome.isNotEmpty) {
      lines.add(ReportLine.subtotal(
        name: 'INGRESOS NO OPERACIONALES',
        amount: totalNonOperatingIncome,
        category: 'nonOperatingIncome',
      ));
      lines.addAll(nonOperatingIncome);
      lines.add(ReportLine.blank());
    }

    // TOTAL INGRESOS
    if (totalRevenue > 0) {
      lines.add(ReportLine.subtotal(
        name: 'TOTAL INGRESOS',
        amount: totalRevenue,
      ));
      lines.add(ReportLine.blank());
    }

    // COSTO DE VENTAS
    if (costOfSales.isNotEmpty) {
      lines.add(ReportLine.subtotal(
        name: 'COSTO DE VENTAS',
        amount: -totalCostOfSales, // Show as negative
        category: 'costOfSales',
      ));
      lines.addAll(costOfSales.map((line) => 
        line.copyWith(amount: -line.amount) // Show as negative
      ));
      lines.add(ReportLine.blank());
    }

    // UTILIDAD BRUTA
    lines.add(ReportLine.subtotal(
      name: 'UTILIDAD BRUTA',
      amount: grossProfit,
    ));
    lines.add(ReportLine.blank());

    // GASTOS OPERACIONALES
    if (operatingExpenses.isNotEmpty) {
      lines.add(ReportLine.subtotal(
        name: 'GASTOS OPERACIONALES',
        amount: -totalOperatingExpenses, // Show as negative
        category: 'operatingExpense',
      ));
      lines.addAll(operatingExpenses.map((line) => 
        line.copyWith(amount: -line.amount) // Show as negative
      ));
      lines.add(ReportLine.blank());
    }

    // UTILIDAD OPERACIONAL
    lines.add(ReportLine.subtotal(
      name: 'UTILIDAD OPERACIONAL',
      amount: operatingProfit,
    ));
    lines.add(ReportLine.blank());

    // GASTOS FINANCIEROS
    if (financialExpenses.isNotEmpty) {
      lines.add(ReportLine.subtotal(
        name: 'GASTOS FINANCIEROS',
        amount: -totalFinancialExpenses, // Show as negative
        category: 'financialExpense',
      ));
      lines.addAll(financialExpenses.map((line) => 
        line.copyWith(amount: -line.amount) // Show as negative
      ));
      lines.add(ReportLine.blank());
    }

    // UTILIDAD ANTES DE IMPUESTOS
    lines.add(ReportLine.subtotal(
      name: 'UTILIDAD ANTES DE IMPUESTOS',
      amount: profitBeforeTax,
    ));
    lines.add(ReportLine.blank());

    // IMPUESTOS
    if (taxes.isNotEmpty) {
      lines.add(ReportLine.subtotal(
        name: 'IMPUESTOS',
        amount: -totalTaxes, // Show as negative
        category: 'taxExpense',
      ));
      lines.addAll(taxes.map((line) => 
        line.copyWith(amount: -line.amount) // Show as negative
      ));
      lines.add(ReportLine.blank());
    }

    // UTILIDAD NETA (RESULTADO DEL EJERCICIO)
    lines.add(ReportLine.total(
      name: 'UTILIDAD NETA',
      amount: netIncome,
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
      'operating_income': operatingIncome.map((l) => l.toJson()).toList(),
      'total_operating_income': totalOperatingIncome,
      'non_operating_income': nonOperatingIncome.map((l) => l.toJson()).toList(),
      'total_non_operating_income': totalNonOperatingIncome,
      'cost_of_sales': costOfSales.map((l) => l.toJson()).toList(),
      'total_cost_of_sales': totalCostOfSales,
      'operating_expenses': operatingExpenses.map((l) => l.toJson()).toList(),
      'total_operating_expenses': totalOperatingExpenses,
      'financial_expenses': financialExpenses.map((l) => l.toJson()).toList(),
      'total_financial_expenses': totalFinancialExpenses,
      'taxes': taxes.map((l) => l.toJson()).toList(),
      'total_taxes': totalTaxes,
      'gross_profit': grossProfit,
      'operating_profit': operatingProfit,
      'profit_before_tax': profitBeforeTax,
      'net_income': netIncome,
      'gross_margin': grossMargin,
      'operating_margin': operatingMargin,
      'net_margin': netMargin,
    };
  }

  @override
  String toString() {
    return 'IncomeStatement($periodDescription: Net Income = \$${netIncome.toStringAsFixed(2)})';
  }
}
