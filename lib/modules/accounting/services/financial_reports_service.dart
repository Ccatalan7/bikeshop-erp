import 'package:flutter/foundation.dart';

import '../../../shared/services/database_service.dart';
import '../models/financial_report.dart';
import '../models/report_line.dart';
import '../models/income_statement.dart';
import '../models/balance_sheet.dart';
import '../models/dashboard_metrics.dart';

/// Service for generating professional financial reports
/// Uses SQL functions from core_schema.sql for calculations
class FinancialReportsService extends ChangeNotifier {
  final DatabaseService _databaseService;
  String _companyName = 'Vinabike';

  FinancialReportsService(this._databaseService);

  /// Set company name for reports
  void setCompanyName(String name) {
    _companyName = name;
    notifyListeners();
  }

  /// Generate Income Statement (Estado de Resultados)
  Future<IncomeStatement> generateIncomeStatement({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      debugPrint('📊 Generating Income Statement: $startDate to $endDate');

      // Call SQL function to get income statement data
      final result = await _databaseService.rpc(
        'get_income_statement_data',
        params: {
          'p_start_date': startDate.toIso8601String(),
          'p_end_date': endDate.toIso8601String(),
        },
      );

      debugPrint('✅ Income Statement data received: ${result.length} rows');

      // Group data by category
      final operatingIncome = <ReportLine>[];
      final nonOperatingIncome = <ReportLine>[];
      final costOfSales = <ReportLine>[];
      final operatingExpenses = <ReportLine>[];
      final financialExpenses = <ReportLine>[];
      final taxes = <ReportLine>[];

      double totalOperatingIncome = 0;
      double totalNonOperatingIncome = 0;
      double totalCostOfSales = 0;
      double totalOperatingExpenses = 0;
      double totalFinancialExpenses = 0;
      double totalTaxes = 0;

      for (final row in result) {
        final category = row['category']?.toString() ?? '';
        final amount = _parseDouble(row['amount']) ?? 0.0;

        final line = ReportLine.account(
          code: row['account_code']?.toString() ?? '',
          name: row['account_name']?.toString() ?? '',
          amount: amount.abs(), // Store as positive, will negate for display
          category: category,
        );

        switch (category) {
          case 'operatingIncome':
            operatingIncome.add(line);
            totalOperatingIncome += amount;
            break;
          case 'nonOperatingIncome':
            nonOperatingIncome.add(line);
            totalNonOperatingIncome += amount;
            break;
          case 'costOfGoodsSold':
            costOfSales.add(line);
            totalCostOfSales += amount;
            break;
          case 'operatingExpense':
            operatingExpenses.add(line);
            totalOperatingExpenses += amount;
            break;
          case 'financialExpense':
            financialExpenses.add(line);
            totalFinancialExpenses += amount;
            break;
          case 'taxExpense':
            taxes.add(line);
            totalTaxes += amount;
            break;
        }
      }

      // Calculate totals and margins
      final grossProfit = totalOperatingIncome - totalCostOfSales;
      final operatingProfit = grossProfit - totalOperatingExpenses;
      final profitBeforeTax =
          operatingProfit + totalNonOperatingIncome - totalFinancialExpenses;
      final netIncome = profitBeforeTax - totalTaxes;

      debugPrint('📈 Income Statement Summary:');
      debugPrint('   Revenue: \$${totalOperatingIncome.toStringAsFixed(2)}');
      debugPrint('   Gross Profit: \$${grossProfit.toStringAsFixed(2)}');
      debugPrint(
          '   Operating Profit: \$${operatingProfit.toStringAsFixed(2)}');
      debugPrint('   Net Income: \$${netIncome.toStringAsFixed(2)}');

      return IncomeStatement(
        startDate: startDate,
        endDate: endDate,
        companyName: _companyName,
        generatedAt: DateTime.now(),
        operatingIncome: operatingIncome,
        totalOperatingIncome: totalOperatingIncome,
        nonOperatingIncome: nonOperatingIncome,
        totalNonOperatingIncome: totalNonOperatingIncome,
        costOfSales: costOfSales,
        totalCostOfSales: totalCostOfSales,
        operatingExpenses: operatingExpenses,
        totalOperatingExpenses: totalOperatingExpenses,
        financialExpenses: financialExpenses,
        totalFinancialExpenses: totalFinancialExpenses,
        taxes: taxes,
        totalTaxes: totalTaxes,
        grossProfit: grossProfit,
        operatingProfit: operatingProfit,
        profitBeforeTax: profitBeforeTax,
        netIncome: netIncome,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ Error generating Income Statement: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Generate Balance Sheet (Balance General)
  Future<BalanceSheet> generateBalanceSheet({
    required DateTime asOfDate,
    DateTime? periodStartDate, // For calculating period net income
  }) async {
    try {
      debugPrint('📊 Generating Balance Sheet as of: $asOfDate');

      // Call SQL function to get balance sheet data
      final result = await _databaseService.rpc(
        'get_balance_sheet_data',
        params: {
          'p_as_of_date': asOfDate.toIso8601String(),
        },
      );

      debugPrint('✅ Balance Sheet data received: ${result.length} rows');

      // Group data by account type and category
      final currentAssets = <ReportLine>[];
      final fixedAssets = <ReportLine>[];
      final otherAssets = <ReportLine>[];
      final currentLiabilities = <ReportLine>[];
      final longTermLiabilities = <ReportLine>[];
      final equity = <ReportLine>[];

      double totalCurrentAssets = 0;
      double totalFixedAssets = 0;
      double totalOtherAssets = 0;
      double totalCurrentLiabilities = 0;
      double totalLongTermLiabilities = 0;
      double totalEquity = 0;

      for (final row in result) {
        final accountType = row['account_type']?.toString() ?? '';
        final category = row['category']?.toString() ?? '';
        final amount = _parseDouble(row['amount']) ?? 0.0;

        final line = ReportLine.account(
          code: row['account_code']?.toString() ?? '',
          name: row['account_name']?.toString() ?? '',
          amount: amount,
          category: category,
        );

        // Categorize by type and category
        switch (accountType) {
          case 'asset':
            switch (category) {
              case 'currentAsset':
                currentAssets.add(line);
                totalCurrentAssets += amount;
                break;
              case 'fixedAsset':
                fixedAssets.add(line);
                totalFixedAssets += amount;
                break;
              case 'otherAsset':
                otherAssets.add(line);
                totalOtherAssets += amount;
                break;
            }
            break;

          case 'liability':
            switch (category) {
              case 'currentLiability':
                currentLiabilities.add(line);
                totalCurrentLiabilities += amount;
                break;
              case 'longTermLiability':
                longTermLiabilities.add(line);
                totalLongTermLiabilities += amount;
                break;
            }
            break;

          case 'equity':
            equity.add(line);
            totalEquity += amount;
            break;
        }
      }

      final totalAssets =
          totalCurrentAssets + totalFixedAssets + totalOtherAssets;
      final totalLiabilities =
          totalCurrentLiabilities + totalLongTermLiabilities;

      // Calculate period net income if period start is provided
      double periodNetIncome = 0;
      if (periodStartDate != null) {
        final netIncomeResult = await _databaseService.rpc(
          'calculate_net_income',
          params: {
            'p_start_date': periodStartDate.toIso8601String(),
            'p_end_date': asOfDate.toIso8601String(),
          },
        );
        periodNetIncome = _parseDouble(netIncomeResult) ?? 0.0;
      }

      debugPrint('📊 Balance Sheet Summary:');
      debugPrint('   Total Assets: \$${totalAssets.toStringAsFixed(2)}');
      debugPrint(
          '   Total Liabilities: \$${totalLiabilities.toStringAsFixed(2)}');
      debugPrint('   Total Equity: \$${totalEquity.toStringAsFixed(2)}');
      debugPrint(
          '   Balanced: ${(totalAssets - (totalLiabilities + totalEquity)).abs() < 1.00}');

      return BalanceSheet(
        startDate: periodStartDate ?? asOfDate,
        endDate: asOfDate,
        companyName: _companyName,
        generatedAt: DateTime.now(),
        currentAssets: currentAssets,
        totalCurrentAssets: totalCurrentAssets,
        fixedAssets: fixedAssets,
        totalFixedAssets: totalFixedAssets,
        otherAssets: otherAssets,
        totalOtherAssets: totalOtherAssets,
        totalAssets: totalAssets,
        currentLiabilities: currentLiabilities,
        totalCurrentLiabilities: totalCurrentLiabilities,
        longTermLiabilities: longTermLiabilities,
        totalLongTermLiabilities: totalLongTermLiabilities,
        totalLiabilities: totalLiabilities,
        equity: equity,
        totalEquity: totalEquity,
        periodNetIncome: periodNetIncome,
      );
    } catch (e, stackTrace) {
      debugPrint('❌ Error generating Balance Sheet: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Generate Trial Balance (Balance de Comprobación)
  Future<List<ReportLine>> generateTrialBalance({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      debugPrint('📊 Generating Trial Balance: $startDate to $endDate');

      final result = await _databaseService.rpc(
        'get_trial_balance',
        params: {
          'p_start_date': startDate.toIso8601String(),
          'p_end_date': endDate.toIso8601String(),
        },
      );

      debugPrint('✅ Trial Balance data received: ${result.length} rows');

      final lines = <ReportLine>[];
      for (final row in result) {
        lines.add(ReportLine.account(
          code: row['account_code']?.toString() ?? '',
          name: row['account_name']?.toString() ?? '',
          amount: _parseDouble(row['balance']) ?? 0.0,
          category: row['account_category']?.toString(),
        ));
      }

      return lines;
    } catch (e, stackTrace) {
      debugPrint('❌ Error generating Trial Balance: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Verify accounting equation (for validation)
  Future<Map<String, dynamic>> verifyAccountingEquation({
    required DateTime asOfDate,
  }) async {
    try {
      final result = await _databaseService.rpc(
        'verify_accounting_equation',
        params: {
          'p_as_of_date': asOfDate.toIso8601String(),
        },
      );

      if (result is List && result.isNotEmpty) {
        final data = result.first;
        return {
          'is_balanced': data['is_balanced'] as bool? ?? false,
          'total_assets': _parseDouble(data['total_assets']) ?? 0.0,
          'total_liabilities': _parseDouble(data['total_liabilities']) ?? 0.0,
          'total_equity': _parseDouble(data['total_equity']) ?? 0.0,
          'difference': _parseDouble(data['difference']) ?? 0.0,
        };
      }

      return {
        'is_balanced': false,
        'total_assets': 0.0,
        'total_liabilities': 0.0,
        'total_equity': 0.0,
        'difference': 0.0,
      };
    } catch (e) {
      debugPrint('❌ Error verifying accounting equation: $e');
      rethrow;
    }
  }

  /// Helper to parse double from dynamic value
  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  /// Dashboard helpers -----------------------------------------------------

  Future<List<MonthlyIncomeExpensePoint>> getIncomeExpenseTimeseries({
    int months = 12,
  }) async {
    final safeMonths = months < 1 ? 1 : months;
    debugPrint('📊 Fetching income/expense timeseries for $safeMonths months');

    final result = await _databaseService.rpc(
      'get_income_expense_timeseries',
      params: {'p_months': safeMonths},
    );

    if (result is! List) {
      return const [];
    }

    return result.map((row) {
      final map = Map<String, dynamic>.from(row as Map);
      final start = _parseDate(map['period_start']);
      final end = _parseDate(map['period_end']);
      return MonthlyIncomeExpensePoint(
        periodStart: start ?? DateTime.now(),
        periodEnd: end ?? DateTime.now(),
        income: _parseDouble(map['income']) ?? 0,
        expense: _parseDouble(map['expense']) ?? 0,
      );
    }).toList()
      ..sort((a, b) => a.periodStart.compareTo(b.periodStart));
  }

  Future<List<ExpenseBreakdownItem>> getExpenseBreakdown({
    required DateTime startDate,
    required DateTime endDate,
    int limit = 6,
  }) async {
    debugPrint(
        '📊 Fetching expense breakdown from $startDate to $endDate (limit $limit)');

    final result = await _databaseService.rpc(
      'get_expense_breakdown',
      params: {
        'p_start_date': startDate.toIso8601String(),
        'p_end_date': endDate.toIso8601String(),
        'p_limit': limit,
      },
    );

    if (result is! List) {
      return const [];
    }

    return result.map((row) {
      final map = Map<String, dynamic>.from(row as Map);
      return ExpenseBreakdownItem(
        accountId: map['account_id']?.toString() ?? '',
        accountCode: map['account_code']?.toString() ?? '',
        accountName: map['account_name']?.toString() ?? '',
        amount: _parseDouble(map['amount']) ?? 0,
      );
    }).toList();
  }
}
