import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('briefing defaults to today and exposes one calendar-period menu', () {
    final panel = File(
      'lib/shared/widgets/notifications_panel.dart',
    ).readAsStringSync();

    expect(
      panel,
      contains(
        'NotificationDigestPeriod _period = NotificationDigestPeriod.today;',
      ),
    );
    expect(
      panel,
      contains('PopupMenuButton<NotificationDigestPeriod>'),
    );
    expect(panel, contains('NotificationDigestPeriod.yesterday'));
    expect(panel, contains("return 'Ayer';"));
    expect(panel, contains('NotificationDigestPeriod.thisWeek'));
    expect(panel, contains('NotificationDigestPeriod.previousWeek'));
    expect(panel, contains('NotificationDigestPeriod.thisMonth'));
    expect(panel, contains('NotificationDigestPeriod.previousMonth'));
    expect(panel, contains('NotificationDigestPeriod.thisYear'));
    expect(panel, contains('NotificationDigestPeriod.custom'));
    expect(panel, contains('const PopupMenuDivider(height: 9)'));
    expect(panel, isNot(contains('NotificationDigestPeriod.sevenDays')));
    expect(panel, isNot(contains("label: '7 días'")));
    expect(panel, isNot(contains('ChoiceChip(')));
  });

  test('custom period uses a compact localized calendar and cancel keeps state',
      () {
    final panel = File(
      'lib/shared/widgets/notifications_panel.dart',
    ).readAsStringSync();
    final registry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();
    final method = _between(
      panel,
      'Future<void> _selectPeriod(',
      'Future<void> _markPeriodAlertsRead()',
    );

    expect(method, contains('showGeneralDialog<DateTimeRange>('));
    expect(panel, isNot(contains('showDateRangePicker(')));
    expect(method, contains('barrierColor: Colors.transparent'));
    expect(panel, isNot(contains('CompositedTransformTarget(')));
    expect(panel, isNot(contains('CompositedTransformFollower(')));
    expect(
      method,
      contains('ancestor: overlayBox'),
    );
    expect(method, contains('final anchorTopLeft = anchorBox.localToGlobal('));
    expect(
        method, contains('final anchorBottomRight = anchorBox.localToGlobal('));
    expect(
      method,
      contains('anchorBox.size.bottomRight(Offset.zero)'),
    );
    expect(
      method,
      contains('Rect.fromPoints(anchorTopLeft, anchorBottomRight)'),
    );
    expect(method, isNot(contains('anchorOrigin & anchorBox.size')));
    expect(panel, contains('var left = anchorRect.left'));
    expect(panel, contains('left = anchorRect.right - width'));
    expect(panel, contains('Positioned('));
    expect(method, contains('_AnchoredDateRangePopover('));
    expect(method, contains('firstDate: firstDate'));
    expect(method, contains('lastDate: today'));
    expect(panel, contains("const preferredWidth = 360.0;"));
    expect(panel, contains("const preferredHeight = 420.0;"));
    expect(panel, contains("child: const Text('Aplicar')"));
    expect(panel, contains("child: const Text('Cancelar')"));
    expect(panel, contains('if (date.isBefore(_rangeStart!))'));
    expect(panel, contains('_rangeEnd = date;'));
    expect(
      panel,
      contains(
        'final civilStart = '
        'DateTime.utc(start.year, start.month, start.day);',
      ),
    );
    expect(panel, contains('scopesRoute: true'));
    expect(panel, contains('explicitChildNodes: true'));
    expect(panel, contains("label: 'Rango personalizado'"));
    expect(registry, contains('compact popover anchored directly below'));
    expect(registry, contains('transparent dismissible barrier'));
    expect(method, contains('if (picked == null || !mounted) return;'));
    expect(
      method.indexOf('if (picked == null || !mounted) return;'),
      lessThan(method.indexOf('_period = nextPeriod')),
    );
  });

  test('period changes use ranged data, epochs, and adaptive presentation', () {
    final panel = File(
      'lib/shared/widgets/notifications_panel.dart',
    ).readAsStringSync();
    final mail = File(
      'lib/modules/mail/providers/mail_account_manager.dart',
    ).readAsStringSync();
    final registry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();

    expect(panel, contains('final loadEpoch = ++_periodLoadEpoch'));
    expect(panel, contains('loadEpoch != _periodLoadEpoch'));
    expect(panel, contains('_notifications.loadNotificationsForRange('));
    expect(panel, contains('_filesService.listFilesForRange('));
    expect(panel, contains('_notifications.markNotificationsReadForRange('));
    expect(panel, contains('_mail.briefingEmails'));
    expect(panel, contains('_activityPulseBuckets(digest, items)'));
    expect(panel, contains('totalDays > 90'));
    // The toolbar still abbreviates its alert label on a narrow host, but the
    // threshold moves with the text: a fixed 360 px overflowed the flex at
    // text scale 1.3, where a 384 px panel lands on exactly 360.0.
    expect(panel, contains('final compact = constraints.maxWidth <'));
    expect(
      panel,
      contains('MediaQuery.textScalerOf(context).scale(labelFontSize)'),
    );
    expect(panel, contains('360 * labelScale'));
    expect(panel,
        contains("compact ? '\$unreadAlerts' : '\$unreadAlerts nuevas'"));
    expect(
      mail,
      contains(
        'List<Email> get briefingEmails => '
        'List<Email>.unmodifiable(_unifiedEmails);',
      ),
    );
    expect(registry, contains('Esta semana'));
    expect(registry, contains('Semana anterior'));
    expect(registry, contains('inclusive custom calendar range'));
    expect(registry, contains('America/Santiago'));
  });
}

String _between(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  final end = source.indexOf(endMarker, start + startMarker.length);
  expect(start, isNot(-1), reason: 'Missing marker: $startMarker');
  expect(end, greaterThan(start), reason: 'Missing marker: $endMarker');
  return source.substring(start, end);
}
