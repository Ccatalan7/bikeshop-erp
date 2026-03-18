import 'package:intl/intl.dart';

class MonthlyIncomeExpensePoint {
  final DateTime periodStart;
  final DateTime periodEnd;
  final double income;
  final double expense;

  MonthlyIncomeExpensePoint({
    required this.periodStart,
    required this.periodEnd,
    required this.income,
    required this.expense,
  });

  double get netIncome => income - expense;

  String monthLabel({String locale = 'es'}) {
    final formatter = DateFormat('MMM yyyy', locale);
    return formatter.format(periodStart);
  }

  String periodLabel({String locale = 'es'}) {
    // Check if it's a daily view (same start and end date)
    if (periodStart.day == periodEnd.day &&
        periodStart.month == periodEnd.month &&
        periodStart.year == periodEnd.year) {
      // Daily format: "Lun 23 Oct"
      final formatter = DateFormat('EEE d MMM', locale);
      return formatter.format(periodStart);
    } else {
      // Monthly format: "Oct 2025"
      final formatter = DateFormat('MMM yyyy', locale);
      return formatter.format(periodStart);
    }
  }
}

class ExpenseBreakdownItem {
  final String accountId;
  final String accountCode;
  final String accountName;
  final double amount;
  final String breakdownKey;
  final bool isOther;

  ExpenseBreakdownItem({
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.amount,
    String? breakdownKey,
    this.isOther = false,
  }) : breakdownKey = breakdownKey ?? accountId;

  double get displayAmount => amount.abs();
}

/// Detail item for period drill-down (when clicking on a bar in the chart)
class PeriodDetailItem {
  final String id;
  final String documentNumber;
  final String description;
  final String
      secondaryText; // customer_name for income, account_name for expense
  final double amount;
  final DateTime transactionDate;
  final String
      sourceType; // 'sales_payment', 'purchase_payment', 'expense', 'journal_entry'

  PeriodDetailItem({
    required this.id,
    required this.documentNumber,
    required this.description,
    required this.secondaryText,
    required this.amount,
    required this.transactionDate,
    required this.sourceType,
    this.accountId,
    this.accountCode,
  });

  final String? accountId;
  final String? accountCode;

  bool get isIncome =>
      sourceType == 'sales_payment' ||
      (sourceType == 'journal_entry' && amount > 0);
}
