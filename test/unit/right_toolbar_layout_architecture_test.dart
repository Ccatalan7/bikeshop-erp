import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('right toolbar stays top-anchored in both appearance modes', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final registry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();

    expect(
      mainSource,
      contains(
        'if (!appearanceService.rightToolbarOverContent) {\n'
        '        return Row(\n'
        '          crossAxisAlignment: CrossAxisAlignment.stretch,',
      ),
    );
    expect(
      mainSource,
      contains(
        'Positioned(\n'
        '            top: 0,\n'
        '            right: 0,\n'
        '            bottom: 0,',
      ),
    );
    expect(registry, contains('Right toolbar shell'));
    expect(registry, contains('stretch the hosting row vertically'));
  });
}
