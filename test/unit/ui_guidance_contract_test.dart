import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void _expectNoLegacyBreakpointClaims(String sourceName, String source) {
  final contradictoryPatterns = <RegExp>[
    RegExp(
      r'\b(?:phone|mobile)\b[^\n]{0,48}<\s*900',
      caseSensitive: false,
    ),
    RegExp(
      r'\btablet\b[^\n]{0,48}600\s*[-–]\s*900',
      caseSensitive: false,
    ),
    RegExp(
      r'\bdesktop\b[^\n]{0,48}>\s*900',
      caseSensitive: false,
    ),
    RegExp(r'desktopBreakpoint\s*=\s*1200'),
  ];

  for (final pattern in contradictoryPatterns) {
    expect(
      pattern.hasMatch(source),
      isFalse,
      reason: '$sourceName contains a contradictory responsive claim: '
          '${pattern.pattern}',
    );
  }
}

void main() {
  test('repo keeps one mandatory and non-contradictory UI guidance chain', () {
    final agents = File('AGENTS.md').readAsStringSync();
    final copilot = File(
      '.github/copilot-instructions.md',
    ).readAsStringSync();
    final gui = File(
      '.github/GUI_DESIGN_PRINCIPLES.md',
    ).readAsStringSync();
    final mobileGuiFile = File(
      '.github/GUI_MOBILE_DESIGN_PRINCIPLES.md',
    );
    final mobileGui = mobileGuiFile.readAsStringSync();
    final surfaces = File(
      'docs/architecture/canonical-ui-surfaces.md',
    ).readAsStringSync();
    final workflow = File(
      '.github/workflows/erp-integrity-gate.yml',
    ).readAsStringSync();
    final flutterTestGate = File(
      'scripts/run_flutter_test_gate.sh',
    ).readAsStringSync();

    expect(agents, contains('.github/copilot-instructions.md'));
    expect(agents, contains('.github/GUI_DESIGN_PRINCIPLES.md'));
    expect(agents, contains('.github/GUI_MOBILE_DESIGN_PRINCIPLES.md'));
    expect(copilot, contains('.github/GUI_DESIGN_PRINCIPLES.md'));
    expect(copilot, contains('.github/GUI_MOBILE_DESIGN_PRINCIPLES.md'));
    expect(copilot, contains('canonical living UI playbook'));
    expect(copilot, contains('macOS desktop remains the operational priority'));
    expect(copilot, contains('require dedicated compositions'));

    expect(mobileGuiFile.existsSync(), isTrue);
    expect(gui, contains('GUI_MOBILE_DESIGN_PRINCIPLES.md'));
    expect(gui, contains('canonical owner of the shared visual language'));
    expect(mobileGui, contains('## Scope and ownership'));
    expect(
      mobileGui,
      contains('owns phone and tablet composition and interaction'),
    );
    expect(
      mobileGui,
      contains(
        'does not own business rules, commands, persistence, or routing',
      ),
    );
    expect(mobileGui, contains('GUI_DESIGN_PRINCIPLES.md'));
    expect(mobileGui, contains('docs/architecture/canonical-ui-surfaces.md'));
    expect(
      mobileGui,
      contains('phone: `<600px`'),
    );
    expect(
      mobileGui,
      contains('tablet: `600-899px`'),
    );
    expect(
      mobileGui,
      contains('desktop: `>=900px`'),
    );
    expect(mobileGui, contains('Every touch target must be at least `48px`'));
    expect(
      mobileGui,
      contains('effective application scale is `1.0` below `900px`'),
    );
    expect(
      mobileGui,
      contains('Keep the zoom wrapper topology stable across the boundary'),
    );
    expect(mobileGui, contains('virtual keyboard'));
    expect(mobileGui, contains('SafeArea'));
    expect(mobileGui, contains('search query'));
    expect(mobileGui, contains('scroll position'));
    expect(
      mobileGui,
      contains(
        'Never let a `LayoutBuilder` branch silently dispose an open draft.',
      ),
    );
    expect(
      mobileGui,
      contains('cross at least one responsive boundary'),
    );
    expect(mobileGui, contains('Loading, empty, error, and offline states'));
    expect(mobileGui, contains('approximately `384x824`'));
    expect(mobileGui, contains('`599px` and `600px`'));
    expect(mobileGui, contains('`899px` and `900px`'));
    expect(mobileGui, contains('approximately `1440x900`'));

    for (final field in <String>[
      '**Problem observed**',
      '**Cause**',
      '**Approved pattern**',
      '**Anti-pattern**',
      '**Reference implementation**',
      '**Minimum test**',
    ]) {
      expect(mobileGui, contains(field));
    }

    expect(
      surfaces,
      contains('compact inline Jobs workspace'),
    );
    expect(
      surfaces,
      contains('Trabajo`, `Ítems`, `Factura`, and proposal `PDF`'),
    );
    expect(
      surfaces,
      contains('resize never silently throws away a draft'),
    );
    expect(
      surfaces,
      contains('Only hosts that pass `onCloseRequested`'),
    );
    expect(surfaces, contains('`WindowZoomScope` / `WindowViewportMetrics`'));
    expect(
      surfaces,
      contains('Compact has an effective scale of `1.0` below `900px`'),
    );
    expect(
      surfaces,
      contains('hardware panel resolution is first converted to logical'),
    );
    expect(
      surfaces,
      contains('keeps `_WorkspaceShell` in one stable slot'),
    );
    expect(
      RegExp(r'without a transient\s+empty reload').hasMatch(surfaces),
      isTrue,
    );

    expect(gui, contains('Anchored Popovers, Menus & Pickers'));
    expect(gui, contains('OverlayPortal.overlayChildLayoutBuilder'));
    expect(gui, contains('Rect.fromPoints(topLeft, bottomRight)'));
    expect(gui, contains('tester.takeException()'));
    expect(gui, contains('Living UI Learning Rule'));

    expect(copilot, isNot(contains('## Responsive Surface Contract')));
    expect(copilot, isNot(contains('`384x824`')));
    expect(copilot, isNot(contains('phone is `<600px`')));
    _expectNoLegacyBreakpointClaims('Copilot instructions', copilot);
    _expectNoLegacyBreakpointClaims('general GUI guide', gui);
    _expectNoLegacyBreakpointClaims('mobile GUI guide', mobileGui);

    expect(
      copilot,
      isNot(
        contains(
          'Use `CompositedTransformFollower` for overlay '
          '(NOT `Positioned` with absolute coordinates)',
        ),
      ),
    );
    expect(
      copilot,
      isNot(
        contains(
          'Use `CompositedTransformFollower` + `LayerLink` for overlay',
        ),
      ),
    );

    expect(
      workflow,
      contains('- ".github/GUI_MOBILE_DESIGN_PRINCIPLES.md"'),
    );
    expect(
      workflow,
      contains('- "docs/architecture/canonical-ui-surfaces.md"'),
    );
    expect(
      workflow,
      contains('bash scripts/run_flutter_test_gate.sh flutter'),
    );
    expect(
      flutterTestGate,
      contains(r'"$flutter_bin" test --machine'),
    );
  });
}
