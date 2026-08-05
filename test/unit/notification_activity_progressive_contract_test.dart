import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('activity timeline expands explicitly in batches without pagination',
      () {
    final panel = File(
      'lib/shared/widgets/notifications_panel.dart',
    ).readAsStringSync();
    final section = _between(
      panel,
      'class _ActivitySection extends StatefulWidget',
      'class _ActivityFilterMenu extends StatelessWidget',
    );
    final registry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();

    expect(section, contains('static const int _activityBatchSize = 12;'));
    expect(section, contains('int _visibleLimit = _activityBatchSize;'));
    expect(section, contains('_visibleLimit += _activityBatchSize'));
    expect(section, contains("'Mostrar \$nextBatchCount más'"));
    expect(
      section,
      contains("'\${visibleItems.length} de '"),
    );
    expect(section, isNot(contains('PageView(')));
    expect(section, isNot(contains('ChoiceChip(')));
    expect(section, isNot(contains('FilterChip(')));
    expect(registry, contains('avoid automatic infinite scrolling'));
    expect(registry, contains('numbered pagination'));
  });

  test('activity limit resets when the period or filter changes', () {
    final panel = File(
      'lib/shared/widgets/notifications_panel.dart',
    ).readAsStringSync();
    final section = _between(
      panel,
      'class _ActivitySection extends StatefulWidget',
      'class _ActivityFilterMenu extends StatelessWidget',
    );

    expect(section, contains('void didUpdateWidget('));
    expect(section, contains('oldWidget.filter != widget.filter'));
    expect(
      section,
      contains('oldWidget.digest.period != widget.digest.period'),
    );
    expect(
      section,
      contains('oldWidget.digest.startDate != widget.digest.startDate'),
    );
    expect(
      section,
      contains('oldWidget.digest.endDate != widget.digest.endDate'),
    );
    expect(section, isNot(contains('oldWidget.digest.endsAt')));
    expect(section, contains('_visibleLimit = _activityBatchSize;'));
  });

  test('the open disclosure is owned by the list, one row at a time', () {
    final panel = File(
      'lib/shared/widgets/notifications_panel.dart',
    ).readAsStringSync();
    final section = _between(
      panel,
      'class _ActivitySection extends StatefulWidget',
      'class _ActivityFilterMenu extends StatelessWidget',
    );

    // A single nullable id can only ever describe one open row.
    expect(section, contains('String? _expandedNotificationId;'));
    expect(
      section,
      contains('_expandedNotificationId = opening ? notificationId : null'),
    );
    // Changing filter or period closes it together with the visible window.
    expect(section, contains('_expandedNotificationId = null;'));
    expect(section, isNot(contains('Set<String>')));
    expect(section, isNot(contains('List<String> _expanded')));
  });

  test('opening a record and opening its disclosure share one read writer', () {
    final panel = File(
      'lib/shared/widgets/notifications_panel.dart',
    ).readAsStringSync();

    expect(panel, contains('void _markActivityRead('));
    expect(panel, contains('onExpand: _markActivityRead,'));
    expect(panel, contains('_markActivityRead(item);'));
    // The single-notification writer is reached from exactly one place, so
    // both paths cannot drift apart.
    expect('markNotificationRead('.allMatches(panel).length, 1);
  });

  test('the enriched row reads the payload already on the notification', () {
    final panel = File(
      'lib/shared/widgets/notifications_panel.dart',
    ).readAsStringSync();
    final builder = _between(
      panel,
      'List<_BriefingActivityItem> _buildActivity(',
      'String _conversationName(',
    );

    expect(panel, contains('Map<String, dynamic> _notificationPayload('));
    expect(builder, contains('_notificationPayload(row)'));
    // No read of any kind may enter the row-building path.
    expect(builder, isNot(contains('await ')));
    expect(builder, isNot(contains('Future')));
    expect(builder, isNot(contains('.load')));
  });

  test('the disclosure never asserts frozen lifecycle state', () {
    final panel = File(
      'lib/shared/widgets/notifications_panel.dart',
    ).readAsStringSync();
    final detail = _between(
      panel,
      '_ActivityDetail? _erpActivityDetail(',
      'List<_ActivityDetailField> _optionalField(',
    );

    // These payload keys are a snapshot taken at insert time; the record may
    // have moved on, so the briefing must not restate them as current.
    for (final frozen in const [
      'priority',
      'status',
      'payment_status',
      'posting_status',
      'supplier_rut',
      'subtotal',
      'tax_amount',
    ]) {
      expect(
        detail,
        isNot(contains("'$frozen'")),
        reason: '$frozen is a frozen snapshot, not current truth',
      );
    }
  });

  test('the disclosure introduces no literal colour', () {
    final panel = File(
      'lib/shared/widgets/notifications_panel.dart',
    ).readAsStringSync();
    final row = _between(
      panel,
      'class _ActivityRow extends StatelessWidget',
      'class _QuietState extends StatelessWidget',
    );

    expect(row, isNot(contains('Color(0x')));
    expect(row, isNot(contains('Colors.')));
    expect(row, contains('colorScheme.surfaceContainerLow'));
    // `T-03`: no shadow, and no selection bar in a list without selection.
    expect(row, isNot(contains('BoxShadow')));
    expect(row, isNot(contains('boxShadow')));
  });

  test('the disclosure affordance is labelled and is not a second target', () {
    final panel = File(
      'lib/shared/widgets/notifications_panel.dart',
    ).readAsStringSync();
    final indicator = _between(
      panel,
      'class _ActivityDisclosureIndicator extends StatelessWidget',
      'class _ActivityDetailBody extends StatelessWidget',
    );

    expect(indicator, contains("'Detalles'"));
    expect(indicator, contains("'Ocultar'"));
    expect(indicator, contains('Semantics('));
    // The row owns the gesture; the indicator must not add one of its own.
    expect(indicator, isNot(contains('onTap')));
    expect(indicator, isNot(contains('GestureDetector')));
    expect(indicator, isNot(contains('InkWell')));
    // Measured exception: a Tooltip mounts an OverlayPortal, and this file
    // composes inside LayoutBuilder.
    expect(indicator, isNot(contains('Tooltip(')));
  });
}

String _between(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  final end = source.indexOf(endMarker, start + startMarker.length);
  expect(start, isNot(-1), reason: 'Missing marker: $startMarker');
  expect(end, greaterThan(start), reason: 'Missing marker: $endMarker');
  return source.substring(start, end);
}
