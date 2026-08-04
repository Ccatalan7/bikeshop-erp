import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('daily briefing keeps live presence and valid closed markings', () {
    final service = File(
      'lib/modules/hr/services/hr_service.dart',
    ).readAsStringSync();
    final panel = File(
      'lib/shared/widgets/notifications_panel.dart',
    ).readAsStringSync();
    final registry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');

    final methodStart = service.indexOf('getDailyAttendanceBriefing({');
    final methodEnd = service.indexOf(
      'Future<List<Map<String, dynamic>>> getCheckedInEmployees()',
      methodStart,
    );
    expect(methodStart, isNot(-1));
    expect(methodEnd, greaterThan(methodStart));
    final projection = service.substring(methodStart, methodEnd);

    expect(projection, contains(".from('attendances')"));
    expect(
      RegExp(r"\.from\('attendances'\)").allMatches(projection),
      hasLength(1),
    );
    expect(projection, contains(".eq('tenant_id', tenantId)"));
    expect(
      projection,
      contains('and(status.eq.ongoing,check_out.is.null)'),
    );
    expect(projection, contains('status.in.(completed,approved)'));
    expect(projection, contains('check_out.not.is.null'));
    expect(projection, contains('check_out.gte.\$startsAtUtc'));
    expect(projection, contains('check_out.lt.\$endsAtUtc'));
    expect(projection, isNot(contains(".eq('status', 'active')")));
    expect(projection, isNot(contains('planned_shifts')));
    expect(projection, isNot(contains('get_checked_in_employees')));

    expect(panel, contains("title: 'Ahora en el local'"));
    expect(panel, contains("'Jornada en curso'"));
    expect(panel, contains("'Revisar marcación'"));
    expect(panel, contains("'Turnos finalizados hoy'"));
    expect(panel, contains("'Turno finalizado'"));
    expect(panel, contains("'Nadie está en el local ahora.'"));
    expect(panel, contains('checkOut ?? now'));
    expect(panel, contains('_chileClockTime(checkOut!)'));
    expect(
      panel,
      contains('period: NotificationDigestPeriod.today'),
    );
    expect(panel, contains('startsAt: todayWindow.startsAt'));
    expect(panel, contains('endsAt: todayWindow.endsAt'));
    expect(panel, contains("query['attendanceId'] = attendanceId"));
    expect(panel, contains("'employeeId': attendance.employeeId"));
    expect(
      panel,
      contains('_loadAttendances(silent: previousDay == nextDay)'),
    );
    expect(panel, contains('loadEpoch != _attendanceLoadEpoch'));

    final page = File(
      'lib/modules/hr/pages/attendances_page.dart',
    ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
    expect(page, contains('DateTimeRange(start: start, end: start)'));
    expect(
      page,
      contains('end: start.add(const Duration(days: 6))'),
    );

    expect(
      registry,
      contains(
        'retain each non-rejected `completed` or `approved` attendance whose '
        '`check_out` falls inside the current half-open `America/Santiago` '
        'business-day interval',
      ),
    );
    expect(
      registry,
      contains(
        '`planned_shifts` may enrich this projection only behind a future '
        'explicit data-quality gate',
      ),
    );
  });
}
