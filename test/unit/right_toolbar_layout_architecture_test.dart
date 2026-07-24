import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('one global right toolbar stays anchored in both appearance modes', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final registry = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();

    expect(
      mainSource,
      contains('class _WorkspaceShell extends StatefulWidget'),
    );
    expect(
      RegExp(r'RightToolbar\(key: _toolbarKey\)').allMatches(mainSource).length,
      1,
    );
    expect(
      mainSource,
      contains('Expanded(child: _buildWorkspaceStack())'),
    );
    expect(
      mainSource,
      matches(
        RegExp(
          r'Positioned\(\s*top:\s*0,\s*right:\s*0,\s*bottom:\s*0,',
          multiLine: true,
        ),
      ),
    );
    expect(registry, contains('Right toolbar shell'));
    expect(registry, contains('stretch the hosting row vertically'));
    expect(
      registry,
      contains('hidden workspace must never consume a file handoff'),
    );
  });
}
