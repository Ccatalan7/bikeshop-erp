import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  test('shared notification briefing renders live Chilean civil time', () {
    final panel = File(
      'lib/shared/widgets/notifications_panel.dart',
    ).readAsStringSync();
    final registry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();

    expect(panel, contains('class _ChileClock extends StatelessWidget'));
    expect(panel, contains("label: 'Hora de Chile, \$time'"));
    expect(panel, contains("'HORA CHILE'"));
    expect(panel, contains('Icons.schedule_rounded'));
    expect(panel, contains('now: _briefingNow'));
    expect(panel, contains('_scheduleBriefingTick();'));
    expect(
      panel,
      contains('final untilNextMinute = const Duration(minutes: 1)'),
    );
    expect(
      panel,
      contains(
        '_briefingChileLocation = '
        "tz.getLocation('America/Santiago')",
      ),
    );
    expect(registry, contains('live `America/Santiago` clock'));
  });

  test('America/Santiago clock honors winter and summer offsets', () {
    tzdata.initializeTimeZones();
    final santiago = tz.getLocation('America/Santiago');

    final winter = tz.TZDateTime.from(
      DateTime.utc(2026, 7, 24, 22, 40),
      santiago,
    );
    final summer = tz.TZDateTime.from(
      DateTime.utc(2026, 1, 24, 22, 40),
      santiago,
    );

    expect('${winter.hour}:${winter.minute}', '18:40');
    expect('${summer.hour}:${summer.minute}', '19:40');
  });
}
