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

  ExpenseBreakdownItem({
    required this.accountId,
    required this.accountCode,
    required this.accountName,
    required this.amount,
  });

  double get displayAmount => amount.abs();
}
