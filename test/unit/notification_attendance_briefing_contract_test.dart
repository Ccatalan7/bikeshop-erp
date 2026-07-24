import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('current-presence briefing uses only real open markings', () {
    final service = File(
      'lib/modules/hr/services/hr_service.dart',
    ).readAsStringSync();
    final panel = File(
      'lib/shared/widgets/notifications_panel.dart',
    ).readAsStringSync();
    final registry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');

    final methodStart = service.indexOf('getCurrentAttendanceBriefing()');
    final methodEnd = service.indexOf(
      'Future<List<Map<String, dynamic>>> getCheckedInEmployees()',
      methodStart,
    );
    expect(methodStart, isNot(-1));
    expect(methodEnd, greaterThan(methodStart));
    final projection = service.substring(methodStart, methodEnd);

    expect(projection, contains(".from('attendances')"));
    expect(projection, contains(".eq('tenant_id', tenantId)"));
    expect(projection, contains(".eq('status', 'ongoing')"));
    expect(projection, contains(".isFilter('check_out', null)"));
    expect(projection, isNot(contains('planned_shifts')));
    expect(projection, isNot(contains('get_checked_in_employees')));

    expect(panel, contains("title: 'Ahora en el local'"));
    expect(panel, contains("'Jornada en curso'"));
    expect(panel, contains("'Revisar marcación'"));
    expect(panel, contains("query['attendanceId'] = attendanceId"));
    expect(panel, contains("'employeeId': attendance.employeeId"));
    expect(panel, contains('_loadAttendances(silent: true)'));
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
        'do not infer a published or default shift while planning data is not '
        'operationally reliable',
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
