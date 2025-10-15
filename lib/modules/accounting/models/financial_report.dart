import 'report_line.dart';

/// Base class for all financial reports
/// Provides common properties and behavior
abstract class FinancialReport {
  final DateTime startDate;
  final DateTime endDate;
  final String companyName;
  final DateTime generatedAt;

  const FinancialReport({
    required this.startDate,
    required this.endDate,
    required this.companyName,
    required this.generatedAt,
  });

  /// Report title (e.g., "Estado de Resultados", "Balance General")
  String get title;

  /// Report subtitle with period information
  String get subtitle {
    if (_isSameDay(startDate, endDate)) {
      return 'Al ${_formatDate(endDate)}';
    }
    return 'Del ${_formatDate(startDate)} al ${_formatDate(endDate)}';
  }

  /// All report lines (to be implemented by subclasses)
  List<ReportLine> get allLines;

  /// Convert to JSON for serialization
  Map<String, dynamic> toJson();

  /// Helper to format date in Chilean format (DD/MM/YYYY)
  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  /// Helper to check if two dates are the same day
  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Get period description (e.g., "Octubre 2025", "Q3 2025", "Año 2025")
  String get periodDescription {
    if (_isSameDay(startDate, endDate)) {
      return _formatDate(endDate);
    }

    // Same month
    if (startDate.year == endDate.year && startDate.month == endDate.month) {
      return '${_getMonthName(startDate.month)} ${startDate.year}';
    }

    // Quarter
    if (_isQuarter(startDate, endDate)) {
      final quarter = ((startDate.month - 1) ~/ 3) + 1;
      return 'Q$quarter ${startDate.year}';
    }

    // Full year
    if (startDate.month == 1 &&
        startDate.day == 1 &&
        endDate.month == 12 &&
        endDate.day == 31 &&
        startDate.year == endDate.year) {
      return 'Año ${startDate.year}';
    }

    // Custom range
    return '${_formatDate(startDate)} - ${_formatDate(endDate)}';
  }

  /// Get Spanish month name
  String _getMonthName(int month) {
    const months = [
      'Enero',
      'Febrero',
      'Marzo',
      'Abril',
      'Mayo',
      'Junio',
      'Julio',
      'Agosto',
      'Septiembre',
      'Octubre',
      'Noviembre',
      'Diciembre'
    ];
    return months[month - 1];
  }

  /// Check if date range is a quarter
  bool _isQuarter(DateTime start, DateTime end) {
    if (start.year != end.year) return false;
    if (start.day != 1) return false;

    final quarterStarts = [1, 4, 7, 10]; // January, April, July, October
    final quarterEnds = [3, 6, 9, 12]; // March, June, September, December

    for (int i = 0; i < 4; i++) {
      if (start.month == quarterStarts[i] && end.month == quarterEnds[i]) {
        // Check if it's the last day of the end month
        final lastDay = DateTime(end.year, end.month + 1, 0).day;
        return end.day == lastDay;
      }
    }
    return false;
  }

  @override
  String toString() {
    return '$title - $subtitle';
  }
}

/// Enum for report types
enum ReportType {
  incomeStatement('Estado de Resultados'),
  balanceSheet('Balance General'),
  trialBalance('Balance de Comprobación'),
  cashFlow('Flujo de Efectivo');

  const ReportType(this.displayName);
  final String displayName;
}

/// Period preset for quick date range selection
enum ReportPeriod {
  currentMonth('Mes Actual'),
  lastMonth('Mes Anterior'),
  currentQuarter('Trimestre Actual'),
  lastQuarter('Trimestre Anterior'),
  currentYear('Año Actual'),
  lastYear('Año Anterior'),
  yearToDate('Año a la Fecha'),
  custom('Personalizado');

  const ReportPeriod(this.displayName);
  final String displayName;

  /// Get date range for this period
  DateRange getDateRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (this) {
      case ReportPeriod.currentMonth:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        return DateRange(start, end);

      case ReportPeriod.lastMonth:
        final start = DateTime(now.year, now.month - 1, 1);
        final end = DateTime(now.year, now.month, 0, 23, 59, 59);
        return DateRange(start, end);

      case ReportPeriod.currentQuarter:
        final quarterMonth = ((now.month - 1) ~/ 3) * 3 + 1;
        final start = DateTime(now.year, quarterMonth, 1);
        final end = DateTime(now.year, quarterMonth + 3, 0, 23, 59, 59);
        return DateRange(start, end);

      case ReportPeriod.lastQuarter:
        final quarterMonth = ((now.month - 1) ~/ 3) * 3 + 1;
        final start = DateTime(now.year, quarterMonth - 3, 1);
        final end = DateTime(now.year, quarterMonth, 0, 23, 59, 59);
        return DateRange(start, end);

      case ReportPeriod.currentYear:
        final start = DateTime(now.year, 1, 1);
        final end = DateTime(now.year, 12, 31, 23, 59, 59);
        return DateRange(start, end);

      case ReportPeriod.lastYear:
        final start = DateTime(now.year - 1, 1, 1);
        final end = DateTime(now.year - 1, 12, 31, 23, 59, 59);
        return DateRange(start, end);

      case ReportPeriod.yearToDate:
        final start = DateTime(now.year, 1, 1);
        return DateRange(start, today);

      case ReportPeriod.custom:
        return DateRange(today, today);
    }
  }
}

/// Simple date range class
class DateRange {
  final DateTime start;
  final DateTime end;

  const DateRange(this.start, this.end);

  bool contains(DateTime date) {
    return date.isAfter(start) && date.isBefore(end) ||
        date.isAtSameMomentAs(start) ||
        date.isAtSameMomentAs(end);
  }

  Duration get duration => end.difference(start);

  @override
  String toString() {
    return '${start.toString().split(' ')[0]} - ${end.toString().split(' ')[0]}';
  }
}
