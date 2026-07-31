import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the return contract documented in
/// `.github/GUI_DESIGN_PRINCIPLES.md` section 6.
///
/// A routed detail is reachable from its own list, a dashboard card, a search
/// result, a related record or another module. Closing it with
/// `context.go(<some list route>)` does not navigate back: it replaces the
/// location, disposing the host route together with its query, filters,
/// selection, disclosures and scroll offset. The operator then has to rebuild
/// the work they were doing.
///
/// This test fails when a back affordance is wired straight to a fixed route,
/// which is the shape that produced the regression instead of the principle
/// being unknown.
void main() {
  test('back affordances return to their origin, not to a fixed route', () {
    final offenders = <String>[];

    for (final file in _dartFiles(Directory('lib'))) {
      final source = file.readAsStringSync();
      final lines = source.split('\n');

      for (var index = 0; index < lines.length; index++) {
        if (!_isBackAffordance(lines[index])) continue;

        // A back affordance owns the handler declared just above or below it,
        // so inspect a small window around the icon.
        final from = index - 8 < 0 ? 0 : index - 8;
        final to = index + 4 >= lines.length ? lines.length - 1 : index + 4;
        final window = lines.sublist(from, to + 1).join('\n');

        if (!_hardCodedGo.hasMatch(window)) continue;
        if (window.contains('ReturnNavigation')) continue;
        // A back arrow that carries an explicit destination label is a
        // navigation link, not a promise to return to the origin. Declaring
        // it keeps that decision deliberate and reviewable at the call site.
        if (window.contains('return-contract: explicit-destination')) continue;

        offenders.add('${file.path}:${index + 1}');
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'These back affordances replace the location with a fixed route '
          'instead of returning to whatever opened them, which discards the '
          "origin's filters, selection and scroll.\n"
          'Use ReturnNavigation.close(context, fallbackRoute: ...) from '
          'lib/shared/services/return_navigation.dart.\n'
          'Offenders:\n  ${offenders.join('\n  ')}',
    );
  });

  test('the shared return contract prefers history over a fixed route', () {
    final source =
        File('lib/shared/services/return_navigation.dart').readAsStringSync();

    expect(source, contains('canPop()'));
    expect(source, contains('router.pop('));
    expect(
      source.indexOf('router.pop('),
      lessThan(source.indexOf('router.go(fallbackRoute)')),
      reason: 'Popping the real history entry must be attempted first; the '
          'fallback route exists only for deep links with no history.',
    );
  });
}

final _hardCodedGo = RegExp(r"""context\.go\(\s*['"]/""");

bool _isBackAffordance(String line) {
  return line.contains('Icons.arrow_back') ||
      line.contains('Icons.arrow_back_ios') ||
      line.contains('Icons.arrow_back_ios_new_rounded');
}

Iterable<File> _dartFiles(Directory directory) sync* {
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) yield entity;
  }
}
