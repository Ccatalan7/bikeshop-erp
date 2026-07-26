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
}

String _between(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  final end = source.indexOf(endMarker, start + startMarker.length);
  expect(start, isNot(-1), reason: 'Missing marker: $startMarker');
  expect(end, greaterThan(start), reason: 'Missing marker: $endMarker');
  return source.substring(start, end);
}
