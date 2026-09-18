import '../models/bank_reconciliation_models.dart';

/// Chilean banking days, for acquirer settlement windows.
///
/// Transbank credits a sale a fixed number of banking days later, and a
/// holiday (18 September, 16 July…) moves the deposit. The settlement windows
/// keep one day of grace, so the movable holidays that Chile shifts to a
/// Monday are approximated by their legal date.
class BankBusinessCalendar {
  const BankBusinessCalendar();

  static const List<(int, int)> _fixedHolidays = <(int, int)>[
    (1, 1),
    (5, 1),
    (5, 21),
    (6, 29),
    (7, 16),
    (8, 15),
    (9, 18),
    (9, 19),
    (10, 12),
    (10, 31),
    (11, 1),
    (12, 8),
    (12, 25),
  ];

  bool isBusinessDay(BankCivilDate date) {
    final weekday = date.utcDate.weekday;
    if (weekday == DateTime.saturday || weekday == DateTime.sunday) {
      return false;
    }
    for (final (month, day) in _fixedHolidays) {
      if (date.month == month && date.day == day) return false;
    }
    final goodFriday = _easterSunday(date.year).addDays(-2);
    return date != goodFriday;
  }

  BankCivilDate addBusinessDays(BankCivilDate source, int count) {
    var date = source;
    var remaining = count;
    final step = count >= 0 ? 1 : -1;
    remaining = remaining.abs();
    while (remaining > 0) {
      date = date.addDays(step);
      if (isBusinessDay(date)) remaining--;
    }
    return date;
  }

  /// Banking days from [from] to [to]; negative when [to] is earlier.
  int businessDaysBetween(BankCivilDate from, BankCivilDate to) {
    if (from == to) return 0;
    final forward = from.compareTo(to) < 0;
    var date = from;
    var count = 0;
    while (date != to) {
      date = date.addDays(forward ? 1 : -1);
      if (isBusinessDay(date)) count++;
    }
    return forward ? count : -count;
  }

  static BankCivilDate _easterSunday(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = ((h + l - 7 * m + 114) % 31) + 1;
    return BankCivilDate(year, month, day);
  }
}
