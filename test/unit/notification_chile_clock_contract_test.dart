import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:vinabike_erp/shared/utils/shop_time.dart';

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
    // The shop's zone has one owner (2026-10-14).
    expect(
      panel,
      contains('tz.Location _chileBriefingLocation() => shopLocation();'),
    );
    expect(registry, contains('live `America/Santiago` clock'));
  });

  test('America/Santiago clock honors winter and summer offsets', () {
    final santiago = shopLocation();

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
