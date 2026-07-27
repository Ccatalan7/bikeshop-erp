import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void _expectContainsAll(
  String sourceName,
  String source,
  Iterable<String> required,
) {
  for (final value in required) {
    expect(
      source,
      contains(value),
      reason: '$sourceName must contain the canonical guidance: $value',
    );
  }
}

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

void _expectNoLegacyVisualRecipes(String sourceName, String source) {
  final legacyPatterns = <RegExp>[
    RegExp(
      r'Colors\.(?:blue|green|orange|amber|purple|teal|red|grey|white)\b',
    ),
    RegExp(r'#[0-9a-f]{6}\b', caseSensitive: false),
    RegExp(r'one restrained accent', caseSensitive: false),
    RegExp(r'(?:maximum|max)\s+2\s*[-–]\s*3 colors', caseSensitive: false),
    RegExp(r'1 primary action\b[^\n]{0,24}per screen', caseSensitive: false),
    RegExp(r'2\s*[-–]\s*3 secondary actions', caseSensitive: false),
    RegExp(r'green snackbar|snackbar \(green\)', caseSensitive: false),
    RegExp(r'preserve established[^\n]{0,60}palette', caseSensitive: false),
    RegExp(r'same flat[^\n]{0,60}visual grammar', caseSensitive: false),
  ];

  for (final pattern in legacyPatterns) {
    expect(
      pattern.hasMatch(source),
      isFalse,
      reason: '$sourceName still contains a legacy visual recipe: '
          '${pattern.pattern}',
    );
  }
}

void _expectNoUniversalSurfaceRecipe(String sourceName, String source) {
  final universalPatterns = <RegExp>[
    RegExp(r'use split[- ]pane only', caseSensitive: false),
    RegExp(r'crud forms[^\n]{0,48}(?:use|with) dialogs?', caseSensitive: false),
    RegExp(r'always place the search bar', caseSensitive: false),
    RegExp(r'circular avatar style', caseSensitive: false),
    RegExp(r'minTableWidth', caseSensitive: false),
    RegExp(r'every split-action command opens[^\n]*dialog',
        caseSensitive: false),
  ];

  for (final pattern in universalPatterns) {
    expect(
      pattern.hasMatch(source),
      isFalse,
      reason: '$sourceName turns a contextual surface into a universal recipe: '
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

    _expectContainsAll('AGENTS.md', agents, <String>[
      '.github/copilot-instructions.md',
      '.github/GUI_DESIGN_PRINCIPLES.md',
      '.github/GUI_MOBILE_DESIGN_PRINCIPLES.md',
      'Historical prompts, screenshots, feature plans',
      'never turn it into a universal',
    ]);

    _expectContainsAll('Copilot instructions', copilot, <String>[
      '.github/GUI_DESIGN_PRINCIPLES.md',
      '.github/GUI_MOBILE_DESIGN_PRINCIPLES.md',
      'macOS desktop remains the operational priority',
      'Phone and tablet remain',
      'first-class and require dedicated compositions',
      'None is a universal default',
      'preserve exact navigation context',
    ]);

    expect(mobileGuiFile.existsSync(), isTrue);
    _expectContainsAll('general GUI guide', gui, <String>[
      'canonical owner of the shared UI language',
      'Professional does not mean colorless, flat, or',
      'The target is the deliberate middle',
      'Design the task, not a favorite pattern',
      'No module name automatically implies',
      'Legacy consistency is not approval',
      'Purposeful color, not color quotas',
      'feature UI must consume centrally owned theme or design',
      'Avoid both extremes',
      'Chips and badges are compact semantic tools',
      'Metrics deserve prominent blocks only when they change a decision',
      'Back, close, and cancel return to the exact origin',
      'The following are decision aids, not mandatory mappings',
      'Do not put split panes everywhere',
      'A short atomic decision',
      'Motion should explain',
      'reduced-motion',
      'GUI_MOBILE_DESIGN_PRINCIPLES.md',
      'Reusable learning rule',
      'not a universal template',
    ]);

    _expectContainsAll('mobile GUI guide', mobileGui, <String>[
      'owns phone and tablet composition and interaction',
      'does not own business rules, commands, persistence, or routing',
      'phone: `<600px`',
      'tablet: `600-899px`',
      'desktop: `>=900px`',
      'Operational priority does not make the current desktop widget',
      'Width class does not prove input capability',
      'Every touch target must be at least `48px`',
      'An action rail is not a default card footer',
      'Compact does not mean narrow and centered',
      'A long list, by itself, does not force',
      'host exactly—not a generic root',
      'Text-first does not mean wrapping every command',
      'The same canonical command may use an anchored popover',
      'Compact motion and continuity',
      'They are evidence, not universal templates',
      'virtual keyboard',
      'SafeArea',
      'search query',
      'scroll position',
      'Never let a `LayoutBuilder` branch silently dispose an open draft.',
      'Loading, empty, error, and offline states',
      'Choose list, row, card, pane, or another container only',
      'Live projections refresh without replacing the workspace',
      'typed invalidation hint to the read-model owner',
      'private Broadcast topic derived from the durable row\'s tenant',
      'trusting a client tenant filter without auditing effective RLS',
      'before awaiting old-channel teardown',
      'failed-setup resume retry',
      'must never supersede an authoritative tenant resolution',
      'contained teardown failure',
      'test that never resolves its data futures',
      '20260726170500_fix_financial_projection_broadcast_authorization.sql',
      '20260726174500_enforce_sales_invoice_tenant_scope.sql',
      'approximately `384x824`',
      '`599px` and `600px`',
      '`899px` and `900px`',
      'approximately `1440x900`',
    ]);

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

    _expectContainsAll('canonical surface registry', surfaces, <String>[
      'GUI_DESIGN_PRINCIPLES.md',
      'GUI_MOBILE_DESIGN_PRINCIPLES.md',
      'Visual and navigation continuity invariant',
      'It is not a template or',
      'does not require sharing one container',
      'Back, close, and cancel return there',
      'Literal colors, radii, shadows, widget classes, and dimensions',
      'compact inline Jobs workspace',
      'resize never silently throws away a draft',
      'Compact has an effective scale of `1.0` below `900px`',
      'not protected visual precedent',
      'grouped task-manager list',
      '`FinancialProjectionRefreshCoordinator`',
      'keeps the last valid charts visible',
      'Cross-device invalidation uses one private Supabase Broadcast topic',
      '14 direct parent',
      'no Broadcast INSERT',
      'probe does not populate that durable-row flag',
      'before awaiting old-channel removal',
      'database-enforced non-null tenant',
      'authoritative tenant switch',
      'already in flight always wins',
    ]);

    _expectContainsAll('general overlay guidance', gui, <String>[
      'Anchored popovers, menus, and pickers',
      'OverlayPortal.overlayChildLayoutBuilder',
      'Rect.fromPoints(topLeft, bottomRight)',
      'tester.takeException()',
      'Mandatory regression gate',
    ]);

    for (final entry in <MapEntry<String, String>>[
      MapEntry<String, String>('Copilot instructions', copilot),
      MapEntry<String, String>('general GUI guide', gui),
      MapEntry<String, String>('mobile GUI guide', mobileGui),
      MapEntry<String, String>('canonical surface registry', surfaces),
    ]) {
      _expectNoLegacyBreakpointClaims(entry.key, entry.value);
      _expectNoLegacyVisualRecipes(entry.key, entry.value);
    }

    for (final entry in <MapEntry<String, String>>[
      MapEntry<String, String>('Copilot instructions', copilot),
      MapEntry<String, String>('general GUI guide', gui),
      MapEntry<String, String>('mobile GUI guide', mobileGui),
    ]) {
      _expectNoUniversalSurfaceRecipe(entry.key, entry.value);
    }

    expect(copilot, isNot(contains('`384x824`')));
    expect(copilot, isNot(contains('⚡` active')));
    expect(
      copilot,
      isNot(
        contains(
          'Use `CompositedTransformFollower` for overlay '
          '(NOT `Positioned` with absolute coordinates)',
        ),
      ),
    );

    _expectContainsAll('ERP integrity workflow', workflow, <String>[
      '- ".github/GUI_MOBILE_DESIGN_PRINCIPLES.md"',
      '- "docs/architecture/canonical-ui-surfaces.md"',
      'Verify canonical UI guidance contract',
      'flutter test test/unit/ui_guidance_contract_test.dart',
      'bash scripts/run_flutter_test_gate.sh flutter',
    ]);
    expect(
      flutterTestGate,
      contains(r'"$flutter_bin" test --machine'),
    );
  });
}
