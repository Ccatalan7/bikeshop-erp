import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/strategic_dashboard_metrics.dart';
import 'database_service.dart';

enum StrategicDashboardPeriodPreset {
  thisMonth,
  previousMonth,
  last30Days,
  last90Days,
  last12Months,
  custom,
}

class StrategicDashboardDateWindow {
  const StrategicDashboardDateWindow({
    required this.startDate,
    required this.endDate,
  });

  final DateTime startDate;
  final DateTime endDate;

  factory StrategicDashboardDateWindow.forPreset(
    StrategicDashboardPeriodPreset preset, {
    required DateTime today,
  }) {
    final date = _dateOnly(today);
    switch (preset) {
      case StrategicDashboardPeriodPreset.thisMonth:
        return StrategicDashboardDateWindow(
          startDate: DateTime(date.year, date.month),
          endDate: date,
        );
      case StrategicDashboardPeriodPreset.previousMonth:
        final currentMonth = DateTime(date.year, date.month);
        return StrategicDashboardDateWindow(
          startDate: DateTime(date.year, date.month - 1),
          endDate: currentMonth.subtract(const Duration(days: 1)),
        );
      case StrategicDashboardPeriodPreset.last30Days:
        return StrategicDashboardDateWindow(
          startDate: date.subtract(const Duration(days: 29)),
          endDate: date,
        );
      case StrategicDashboardPeriodPreset.last90Days:
        return StrategicDashboardDateWindow(
          startDate: date.subtract(const Duration(days: 89)),
          endDate: date,
        );
      case StrategicDashboardPeriodPreset.last12Months:
        return StrategicDashboardDateWindow(
          startDate: DateTime(date.year - 1, date.month, date.day),
          endDate: date,
        );
      case StrategicDashboardPeriodPreset.custom:
        throw ArgumentError.value(
          preset,
          'preset',
          'El rango personalizado necesita fechas explícitas.',
        );
    }
  }

  factory StrategicDashboardDateWindow.custom(
    DateTime first,
    DateTime second,
  ) {
    final firstDate = _dateOnly(first);
    final secondDate = _dateOnly(second);
    return StrategicDashboardDateWindow(
      startDate: firstDate.isBefore(secondDate) ? firstDate : secondDate,
      endDate: firstDate.isBefore(secondDate) ? secondDate : firstDate,
    );
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}

class StrategicDashboardService {
  const StrategicDashboardService(this._databaseService);

  final DatabaseService _databaseService;

  static bool _timeZonesInitialized = false;
  static tz.Location? _businessLocation;

  static tz.Location get _santiago {
    if (!_timeZonesInitialized) {
      tzdata.initializeTimeZones();
      _timeZonesInitialized = true;
    }
    return _businessLocation ??= tz.getLocation('America/Santiago');
  }

  static DateTime businessToday({DateTime? nowUtc}) {
    final now = tz.TZDateTime.from(
      (nowUtc ?? DateTime.now()).toUtc(),
      _santiago,
    );
    return DateTime(now.year, now.month, now.day);
  }

  Future<StrategicDashboardMetrics> load({
    required StrategicDashboardDateWindow window,
  }) async {
    final start = tz.TZDateTime(
      _santiago,
      window.startDate.year,
      window.startDate.month,
      window.startDate.day,
    ).toUtc();
    final selectedEnd = tz.TZDateTime(
      _santiago,
      window.endDate.year,
      window.endDate.month,
      window.endDate.day + 1,
    ).toUtc();
    final now = DateTime.now().toUtc();
    final end = selectedEnd.isAfter(now) ? now : selectedEnd;
    final result = await _databaseService.rpc(
      'get_strategic_dashboard_metrics',
      params: {
        'p_start_date': start.toIso8601String(),
        'p_end_date': end.toIso8601String(),
      },
    );

    if (result is! Map) {
      throw const FormatException(
        'La respuesta de indicadores estratégicos no tiene el formato esperado.',
      );
    }

    return StrategicDashboardMetrics.fromJson(
      result.map((key, value) => MapEntry(key.toString(), value)),
    );
  }
}
