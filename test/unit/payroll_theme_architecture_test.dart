import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _allowedStaticPayrollTokenMembers = <String>{
  // Geometry.
  'rTag',
  'rControl',
  'rField',
  'rPanel',
  'rSheet',
  'rPill',

  // Density and layout metrics.
  'moduleCommandH',
  'queueStripH',
  'tableHeaderH',
  'tableColsH',
  'rowH',
  'moneyBarH',
  'ctaH',
  'ctaHDense',
  'fieldH',
  'touchMin',
  'touchMobile',
  'workspacePad',
  'cardPadH',
  'gapBlocks',
  'gapCards',
  'bpDesktop',
  'bpTablet',

  // Motion.
  'fast',
  'base',
  'pane',
  'curve',
};

void main() {
  test('Payroll consumes mounted visual roles instead of static visual tokens',
      () {
    final violations = <_Violation>[];

    for (final file in _payrollSourceFiles()) {
      final source = file.readAsStringSync();
      final code = _stripDartComments(source);

      for (final match in RegExp(r'\bPayrollTokens\s*\.\s*([A-Za-z_]\w*)')
          .allMatches(code)) {
        final member = match.group(1)!;
        if (!_allowedStaticPayrollTokenMembers.contains(member)) {
          violations.add(
            _violation(
              file: file,
              source: source,
              offset: match.start,
              rule: 'static PayrollTokens visual member .$member',
            ),
          );
        }
      }

      _collectMatches(
        violations: violations,
        file: file,
        source: source,
        code: code,
        pattern: RegExp(r'\bPayrollTokensDark\b'),
        rule: 'PayrollTokensDark',
      );
      _collectMatches(
        violations: violations,
        file: file,
        source: source,
        code: code,
        pattern: RegExp(
          r'\bPayrollStateTone\s*\.\s*(?:success|warning|danger|neutral)\b',
        ),
        rule: 'static PayrollStateTone semantic tone',
      );
      _collectMatches(
        violations: violations,
        file: file,
        source: source,
        code: code,
        pattern: RegExp(
          r'\bColor\s*\(\s*0[xX][0-9A-Fa-f_]+\s*\)',
        ),
        rule: 'literal Color(0x...)',
      );

      for (final match
          in RegExp(r'\bColors\s*\.\s*([A-Za-z_]\w*)').allMatches(code)) {
        if (match.group(1) == 'transparent') {
          continue;
        }
        violations.add(
          _violation(
            file: file,
            source: source,
            offset: match.start,
            rule: 'Colors.${match.group(1)}',
          ),
        );
      }

      _collectMatches(
        violations: violations,
        file: file,
        source: source,
        code: code,
        pattern: RegExp(r'\bTheme\s*\('),
        rule: 'local Theme island',
      );
    }

    violations.sort((left, right) {
      final pathOrder = left.path.compareTo(right.path);
      if (pathOrder != 0) {
        return pathOrder;
      }
      final lineOrder = left.line.compareTo(right.line);
      if (lineOrder != 0) {
        return lineOrder;
      }
      return left.rule.compareTo(right.rule);
    });

    if (violations.isNotEmpty) {
      fail(
        'Payroll theme architecture violations '
        '(${violations.length}):\n${violations.join('\n')}',
      );
    }
  });

  test('accent fills live in PayrollAccentAction or carry an explicit marker',
      () {
    // Structural contract (Codex adversarial audit 2026-07-30): every
    // accent-FILLED interactive control is owned by PayrollAccentAction,
    // which pairs the fill with `visual.onAccent` by construction. Outside
    // that owner, a `visual.accent` fill is only legal as a decorative or
    // selection indicator carrying an explicit `// accent-fill:` marker on
    // the line above its color argument. There is no window heuristic: the
    // raw fill itself is the violation, independent of where any foreground
    // lives.
    final violations = <_Violation>[];
    for (final file in _payrollSourceFiles()) {
      if (_normalizedPath(file.path).endsWith('payroll_accent_action.dart')) {
        continue;
      }
      violations.addAll(
        _accentFillViolations(
          path: _normalizedPath(file.path),
          source: file.readAsStringSync(),
        ),
      );
    }

    expect(
      violations,
      isEmpty,
      reason: 'Raw accent fills must move into PayrollAccentAction (or carry '
          'an explicit // accent-fill: marker when they are a decorative or '
          'selection indicator):\n${violations.join('\n')}',
    );
  });

  test('feature code never paints content with scheme.onPrimary', () {
    // `visual.onAccent` is the only on-accent vocabulary. A feature-local
    // `scheme.onPrimary` bypasses it and rots silently when the owner
    // changes.
    final violations = <_Violation>[];
    for (final file in _payrollSourceFiles()) {
      if (_normalizedPath(file.path).endsWith('payroll_accent_action.dart')) {
        continue;
      }
      final source = file.readAsStringSync();
      final code = _stripDartComments(source);
      for (final match in RegExp(r'scheme\.onPrimary\b').allMatches(code)) {
        violations.add(
          _violation(
            file: file,
            source: source,
            offset: match.start,
            rule: 'scheme.onPrimary (use visual.onAccent)',
          ),
        );
      }
      // The public scheme escape hatch also re-opens the accent alias
      // (visual.scheme.primary renders identically to visual.accent), so
      // feature code resolves everything through the named getters.
      for (final match in RegExp(r'visual\.scheme\b').allMatches(code)) {
        violations.add(
          _violation(
            file: file,
            source: source,
            offset: match.start,
            rule: 'visual.scheme escape (use the named PayrollVisualTokens '
                'getters)',
          ),
        );
      }
    }
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('PayrollAccentAction itself is frozen to the on-accent contract', () {
    // The owner is exempt from the outside-guards, so it needs its own
    // direct contract: interactive fill = visual.accent; label and spinner
    // foreground = visual.onAccent; hover/focus overlays derive from
    // visual.onAccent. A mutation of the owner to scheme.onPrimary renders
    // identically to visual.onAccent, so only this source contract can
    // catch it; the rendered matrix in
    // payroll_accent_action_contract_test.dart catches the visible role
    // mutations (onSurface/surface/canvas/ink).
    final source = File(
      'lib/modules/hr/payroll/surfaces/payroll_accent_action.dart',
    ).readAsStringSync();
    final code = _stripDartComments(source);

    // Required snippets (whitespace-flexible).
    const requirements = <String, String>{
      // Interactive fill is the accent role.
      r'interactive\s*\?\s*visual\.accent\b':
          'interactive fill must be visual.accent',
      // Busy fill is the dimmed accent, never another family.
      r'visual\.accent\.withValues\(alpha:\s*0\.55\)':
          'busy fill must dim visual.accent',
      // Foreground pair is onAccent / inkDisabled.
      r'interactive\s*\|\|\s*busy\s*\?\s*visual\.onAccent\s*:\s*visual\.inkDisabled':
          'foreground must be visual.onAccent / visual.inkDisabled',
      // The busy spinner paints with onAccent.
      r'CircularProgressIndicator\([\s\S]{0,120}?color:\s*visual\.onAccent':
          'busy spinner must use visual.onAccent',
      // Hover/focus overlays derive from onAccent.
      r'hoverColor:[\s\S]{0,80}?visual\.onAccent\.withValues\(alpha:\s*0\.12\)':
          'hover overlay must derive from visual.onAccent',
      r'focusColor:[\s\S]{0,80}?visual\.onAccent\.withValues\(alpha:\s*0\.16\)':
          'focus overlay must derive from visual.onAccent',
    };
    requirements.forEach((pattern, reason) {
      expect(RegExp(pattern).hasMatch(code), isTrue, reason: reason);
    });

    // Explicit mutation detectors: each forbidden shape below is exactly
    // what a regression to onPrimary/onSurface/surface/canvas/ink would
    // introduce inside the owner.
    const prohibitions = <String, String>{
      r'scheme\.onPrimary\b':
          'owner must use visual.onAccent, not scheme.onPrimary',
      r'scheme\.onSurface\b':
          'owner must not paint content with scheme.onSurface',
      r'colorScheme\.': 'owner resolves roles only through PayrollVisualTokens',
      r'color:\s*visual\.surface\b':
          'visual.surface is never an on-accent foreground here (disabled '
              'fills go through the disabledStyle switch)',
      r'color:\s*visual\.canvas\b':
          'visual.canvas is never a foreground in the owner',
      r'color:\s*visual\.ink\b':
          'visual.ink is never an interactive foreground in the owner',
      r'foreground\s*=[^;]*visual\.(?:surface|canvas|ink)\b':
          'the foreground pair must never resolve to a surface/ink role',
      r'(?:hoverColor|focusColor):[\s\S]{0,80}?visual\.(?:surface|canvas|ink)\b':
          'overlays must never derive from a surface/ink role',
    };
    prohibitions.forEach((pattern, reason) {
      expect(RegExp(pattern).hasMatch(code), isFalse, reason: reason);
    });
  });

  test('the accent-fill scanner catches every mutation shape', () {
    List<_Violation> scan(String source) =>
        _accentFillViolations(path: 'fixture.dart', source: source);

    // A raw Material fill is flagged even when the foreground lives more
    // than 31 lines away: there is no window to escape.
    final farApart = StringBuffer()
      ..writeln('final a = Material(')
      ..writeln('  color: visual.accent,');
    for (var i = 0; i < 40; i++) {
      farApart.writeln('  child2: null, // filler');
    }
    farApart
      ..writeln('  child: Text(x, style: TextStyle(color: visual.surface)),')
      ..writeln(');');
    expect(scan(farApart.toString()), isNotEmpty);

    // A conditional fill branch is flagged.
    expect(
      scan('final b = BoxDecoration(\n'
          '  color: enabled\n'
          '      ? visual.accent\n'
          '      : visual.surface,\n'
          ');\n'),
      isNotEmpty,
    );

    // backgroundColor in a button style is flagged.
    expect(
      scan('final c = FilledButton.styleFrom(\n'
          '  backgroundColor: visual.accent,\n'
          ');\n'),
      isNotEmpty,
    );

    // An accent border beside a legitimate surface fill is NOT a fill, even
    // though Border appears immediately next to the color argument.
    expect(
      scan('final d = BoxDecoration(\n'
          '  color: visual.surface,\n'
          '  border: Border.all(\n'
          '    color: focused ? visual.accent : visual.border,\n'
          '  ),\n'
          ');\n'),
      isEmpty,
    );

    // A foreground variable defined BEFORE the fill cannot hide it.
    expect(
      scan('final foreground = visual.surface;\n'
          'final e = Material(\n'
          '  color: visual.accent,\n'
          '  child: Text(x),\n'
          ');\n'),
      isNotEmpty,
    );

    // The explicit marker excuses a selection indicator.
    expect(
      scan('final f = BoxDecoration(\n'
          '  // accent-fill: selection\n'
          '  color: selected ? visual.accent : visual.border,\n'
          ');\n'),
      isEmpty,
    );

    // ColoredBox fills are covered too.
    expect(
      scan('final g = ColoredBox(color: visual.accent);\n'),
      isNotEmpty,
    );

    // Direct Container/AnimatedContainer/Ink/ShapeDecoration fills are
    // covered too — one fixture per family.
    expect(
      scan('final h = Container(\n'
          '  height: 40,\n'
          '  color: visual.accent,\n'
          ');\n'),
      isNotEmpty,
    );
    expect(
      scan('final i = AnimatedContainer(\n'
          '  duration: PayrollTokens.fast,\n'
          '  color: enabled ? visual.accent : visual.surface,\n'
          ');\n'),
      isNotEmpty,
    );
    expect(
      scan('final j = Ink(\n'
          '  color: visual.accent,\n'
          '  child: child,\n'
          ');\n'),
      isNotEmpty,
    );
    expect(
      scan('final k = ShapeDecoration(\n'
          '  color: visual.accent,\n'
          '  shape: shape,\n'
          ');\n'),
      isNotEmpty,
    );

    // A Container whose fill is a surface role stays clean even when a
    // nested icon legitimately paints with accent.
    expect(
      scan('final l = Container(\n'
          '  color: visual.surface,\n'
          '  child: Icon(Icons.check, color: visual.accent),\n'
          ');\n'),
      isEmpty,
    );

    // Cross-review hardening fixtures: theme-filled buttons, copyWith,
    // gradients, Card and string-spoofed markers.
    expect(
      scan('final m = FilledButton(\n'
          '  onPressed: onTap,\n'
          '  child: Text(label),\n'
          ');\n'),
      isNotEmpty,
    );
    expect(
      scan('// accent-fill: dialog-action\n'
          'final n = FilledButton(\n'
          '  onPressed: onTap,\n'
          '  child: Text(label),\n'
          ');\n'),
      isEmpty,
    );
    expect(
      scan('final o = base.copyWith(color: visual.accent);\n'),
      isNotEmpty,
    );
    expect(
      scan('final p = BoxDecoration(\n'
          '  gradient: LinearGradient(\n'
          '    colors: [visual.accent, visual.accentSoft],\n'
          '  ),\n'
          ');\n'),
      isNotEmpty,
    );
    expect(
      scan('final q = Card(\n'
          '  color: visual.accent,\n'
          '  child: child,\n'
          ');\n'),
      isNotEmpty,
    );
    // A marker inside a string literal must not whitewash the next line.
    expect(
      scan("final s = '// accent-fill: spoof';\n"
          'final r = ColoredBox(color: visual.accent);\n'),
      isNotEmpty,
    );
  });

  test(
      'PayrollTokens static inventory is frozen: new visual values belong to '
      'the resolver/roles pipeline', () {
    // Legacy Design-reference statics stay exactly as delivered (geometry,
    // density, motion AND the historical color/typography constants that the
    // exempted tokens file still hosts as documentation of the exact Design
    // values). Adding ANY new static member here is how visual drift starts;
    // a new color/style must be born at the canonical theme boundary
    // (VinabikeThemeResolver/VinabikeThemeRoles) and be consumed through
    // PayrollVisualTokens instead.
    const frozenFields = <String>{
      'accent',
      'accentBorder',
      'accentSoft',
      'avatarAmber',
      'avatarCyan',
      'avatarPlateBg',
      'avatarSky',
      'base',
      'bodyM',
      'bodyS',
      'border',
      'borderStrong',
      'bpDesktop',
      'bpTablet',
      'brand',
      'canvas',
      'cardPadH',
      'cardTitle',
      'ctaH',
      'ctaHDense',
      'curve',
      'dangerBorder',
      'dangerFg',
      'dangerSoft',
      'dirtyTabDot',
      'fast',
      'fieldH',
      'fontBody',
      'fontHeading',
      'fontMono',
      'gapBlocks',
      'gapCards',
      'groupLabor',
      'ink',
      'inkDisabled',
      'inkFaint',
      'inkMuted',
      'label',
      'labelStrong',
      'moduleCommandH',
      'moduleTitle',
      'moneyBar',
      'moneyBarH',
      'monoM',
      'monoS',
      'neutralBorder',
      'neutralFg',
      'neutralSoft',
      'numBar',
      'numCard',
      'numRow',
      'onBrand',
      'onShell',
      'onShellMuted',
      'overlay',
      'overline',
      'pane',
      'queueStripH',
      'rControl',
      'rField',
      'rPanel',
      'rPill',
      'rSheet',
      'rTag',
      'railAttentionDot',
      'raised',
      'recordTitle',
      'rowH',
      'sectionTitle',
      'shell',
      'shellDeep',
      'shellEdge',
      'shellRaised',
      'sidebarLabel',
      'sidebarSubdot',
      'successBorder',
      'successFg',
      'successSoft',
      'surface',
      'surfaceSelected',
      'surfaceSunken',
      'tabCloseIcon',
      'tabHairline',
      'tableColsH',
      'tableHeaderH',
      'tabular',
      'touchMin',
      'touchMobile',
      'warningBorder',
      'warningFg',
      'warningSoft',
      'workspacePad',
    };
    const frozenMethods = <String>{
      '_body',
      '_heading',
      '_mono',
      'avatarInitials',
      'badgeDigits',
      'railLogo',
      'selectedRing',
    };

    final source = File('lib/modules/hr/payroll/theme/payroll_tokens.dart')
        .readAsStringSync();
    final classBody = source.split('class PayrollTokens')[1].split('class ')[0];
    final fields = RegExp(r'static\s+(?:const|final)\s+[\w<>,\s]+?\b(\w+)\s*=')
        .allMatches(classBody)
        .map((match) => match.group(1)!)
        .toSet();
    final methods = RegExp(r'static\s+[\w<>]+\s+(\w+)\s*\(')
        .allMatches(classBody)
        .map((match) => match.group(1)!)
        .toSet();

    expect(
      fields.difference(frozenFields),
      isEmpty,
      reason: 'New PayrollTokens statics are forbidden; add the value to the '
          'canonical theme pipeline instead.',
    );
    expect(
      frozenFields.difference(fields),
      isEmpty,
      reason: 'A frozen PayrollTokens static disappeared; geometry/motion and '
          'the Design reference values must not be deleted silently.',
    );
    expect(methods, frozenMethods);
  });

  test('comment stripping preserves code and line numbers', () {
    const source = '''
PayrollTokens.rPanel;
// PayrollTokens.canvas; Colors.red; Theme(data: theme, child: child);
/*
 * Color(0xFF000000);
 * /* PayrollStateTone.danger */
 */
final url = 'https://example.test/payroll';
PayrollTokens.accent;
''';

    final code = _stripDartComments(source);

    expect('\n'.allMatches(code).length, '\n'.allMatches(source).length);
    expect(code, contains('PayrollTokens.rPanel'));
    expect(code, contains('https://example.test/payroll'));
    expect(code, contains('PayrollTokens.accent'));
    expect(code, isNot(contains('PayrollTokens.canvas')));
    expect(code, isNot(contains('Colors.red')));
    expect(code, isNot(contains('Color(0xFF000000)')));
    expect(code, isNot(contains('PayrollStateTone.danger')));
    expect(code, isNot(contains('Theme(data:')));
  });
}

List<File> _payrollSourceFiles() {
  final files = Directory('lib/modules/hr/payroll')
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .where(
        (file) =>
            _normalizedPath(file.path) !=
            'lib/modules/hr/payroll/theme/payroll_tokens.dart',
      )
      .toList()
    ..add(File('lib/modules/hr/pages/payroll_reconciliation_page.dart'))
    ..sort((left, right) => left.path.compareTo(right.path));

  return files;
}

void _collectMatches({
  required List<_Violation> violations,
  required File file,
  required String source,
  required String code,
  required RegExp pattern,
  required String rule,
}) {
  for (final match in pattern.allMatches(code)) {
    violations.add(
      _violation(
        file: file,
        source: source,
        offset: match.start,
        rule: rule,
      ),
    );
  }
}

_Violation _violation({
  required File file,
  required String source,
  required int offset,
  required String rule,
}) {
  final line = 1 + '\n'.allMatches(source.substring(0, offset)).length;
  final lines = source.split('\n');
  final excerpt = line <= lines.length ? lines[line - 1].trim() : '';

  return _Violation(
    path: _normalizedPath(file.path),
    line: line,
    rule: rule,
    excerpt: excerpt,
  );
}

String _normalizedPath(String path) => path.replaceAll('\\', '/');

/// Structural accent-fill scanner: flags `visual.accent` resolved as the
/// top-level `color:` argument of Material/BoxDecoration/ColoredBox or as any
/// `backgroundColor:` value, unless the `color:`/`backgroundColor:` line (or
/// the line above it) carries an explicit `// accent-fill:` marker.
List<_Violation> _accentFillViolations({
  required String path,
  required String source,
}) {
  final markerLines = <int>{};
  final rawLines = source.split('\n');
  final commentOnly = RegExp(r'^\s*//');
  for (var index = 0; index < rawLines.length; index++) {
    final line = rawLines[index];
    if (commentOnly.hasMatch(line) && line.contains('accent-fill:')) {
      markerLines.add(index + 1);
    }
  }
  final code = _stripDartComments(source);
  final violations = <_Violation>[];

  int lineOf(int offset) =>
      1 + '\n'.allMatches(code.substring(0, offset)).length;

  void flag(int keyOffset, String rule) {
    final keyLine = lineOf(keyOffset);
    // The marker must live in the contiguous comment block directly above
    // the flagged argument (comment-only lines; strings cannot spoof it).
    var probe = keyLine - 1;
    while (probe >= 1 &&
        probe <= rawLines.length &&
        commentOnly.hasMatch(rawLines[probe - 1])) {
      if (markerLines.contains(probe)) return;
      probe--;
    }
    if (markerLines.contains(keyLine)) return;
    final lines = source.split('\n');
    violations.add(
      _Violation(
        path: path,
        line: keyLine,
        rule: rule,
        excerpt: keyLine <= lines.length ? lines[keyLine - 1].trim() : '',
      ),
    );
  }

  for (final match in RegExp(
    r'\b(Material|BoxDecoration|ShapeDecoration|ColoredBox|Card|'
    r'AnimatedContainer|Container|Ink)\s*\(',
  ).allMatches(code)) {
    final owner = match.group(1)!;
    final open = match.end - 1;
    final close = _matchingParen(code, open);
    if (close == null) continue;
    final arg = _topLevelArgument(code, open + 1, close, 'color');
    if (arg == null) continue;
    final value = code.substring(arg.valueStart, arg.valueEnd);
    if (RegExp(r'visual\.accent\b').hasMatch(value)) {
      flag(arg.keyStart, '$owner accent fill outside PayrollAccentAction');
    }
  }

  for (final match in RegExp(r'backgroundColor:').allMatches(code)) {
    final valueEnd = _topLevelValueEnd(code, match.end);
    if (RegExp(r'visual\.accent\b')
        .hasMatch(code.substring(match.end, valueEnd))) {
      flag(
          match.start,
          'backgroundColor accent fill outside '
          'PayrollAccentAction');
    }
  }

  // Aliasing hardening (Codex cross-review): copyWith/gradient shapes and
  // theme-filled button families cannot smuggle an accent fill either.
  // Accent as a TEXT color on a neutral surface is legitimate, so copyWith
  // over the known typography getters is excluded; everything else (a
  // decoration or an aliased receiver) flags.
  final textStyleReceiver = RegExp(
    r'visual\.(?:overline|labelStrong|label|bodyM|bodyS|monoS|monoM|'
    r'numRow|numCard|numBar|cardTitle|sectionTitle|moduleTitle|'
    r'recordTitle)$',
  );
  for (final match in RegExp(
    r'([A-Za-z_][\w.]*)\s*\.copyWith\(\s*color:[^;]{0,120}?visual\.accent\b',
    dotAll: true,
  ).allMatches(code)) {
    if (textStyleReceiver.hasMatch(match.group(1)!)) continue;
    flag(match.start, 'copyWith accent fill outside PayrollAccentAction');
  }
  for (final match in RegExp(
    r'gradient:[\s\S]{0,160}?visual\.accent\b',
  ).allMatches(code)) {
    flag(match.start, 'gradient accent fill outside PayrollAccentAction');
  }
  // A bare FilledButton/ElevatedButton is accent-filled by the resolver's
  // global theme without any `visual.accent` token in source. Inline CTAs
  // must use PayrollAccentAction; standard M3 dialog actions carry the
  // explicit `// accent-fill: dialog-action` marker.
  for (final match
      in RegExp(r'\b(?:FilledButton|ElevatedButton)(?:\.icon)?\s*\(')
          .allMatches(code)) {
    flag(
      match.start,
      'theme-filled button outside PayrollAccentAction (mark dialog '
      'actions with // accent-fill: dialog-action)',
    );
  }

  return violations;
}

class _NamedArgument {
  const _NamedArgument(this.keyStart, this.valueStart, this.valueEnd);
  final int keyStart;
  final int valueStart;
  final int valueEnd;
}

/// Finds `name:` at argument depth 0 of the span and returns its value slice.
_NamedArgument? _topLevelArgument(
  String code,
  int start,
  int end,
  String name,
) {
  var depth = 0;
  var index = start;
  var atArgumentStart = true;
  while (index < end) {
    final char = code.codeUnitAt(index);
    if (char == 0x27 || char == 0x22) {
      index = _skipString(code, index);
      atArgumentStart = false;
      continue;
    }
    if (char == 0x28 || char == 0x5B || char == 0x7B) {
      depth++;
      index++;
      atArgumentStart = false;
      continue;
    }
    if (char == 0x29 || char == 0x5D || char == 0x7D) {
      depth--;
      index++;
      continue;
    }
    if (depth == 0 && char == 0x2C) {
      atArgumentStart = true;
      index++;
      continue;
    }
    if (depth == 0 &&
        atArgumentStart &&
        code.startsWith(RegExp(r'\s*' + name + r':'), index)) {
      final keyStart = RegExp(r'\s*').matchAsPrefix(code, index)!.end;
      final colon = code.indexOf(':', index);
      final valueStart = colon + 1;
      final valueEnd = _topLevelValueEnd(code, valueStart);
      return _NamedArgument(keyStart, valueStart, valueEnd);
    }
    if (!RegExp(r'\s').hasMatch(String.fromCharCode(char))) {
      atArgumentStart = false;
    }
    index++;
  }
  return null;
}

/// Returns the offset just before the comma/closing bracket that ends the
/// value starting at [start], honouring nesting and string literals.
int _topLevelValueEnd(String code, int start) {
  var depth = 0;
  var index = start;
  while (index < code.length) {
    final char = code.codeUnitAt(index);
    if (char == 0x27 || char == 0x22) {
      index = _skipString(code, index);
      continue;
    }
    if (char == 0x28 || char == 0x5B || char == 0x7B) depth++;
    if (char == 0x29 || char == 0x5D || char == 0x7D) {
      if (depth == 0) return index;
      depth--;
    }
    if (char == 0x2C && depth == 0) return index;
    index++;
  }
  return code.length;
}

/// Returns the index just past the matching closing parenthesis for the
/// opening parenthesis at [open], or null when unbalanced.
int? _matchingParen(String code, int open) {
  var depth = 0;
  var index = open;
  while (index < code.length) {
    final char = code.codeUnitAt(index);
    if (char == 0x27 || char == 0x22) {
      index = _skipString(code, index);
      continue;
    }
    if (char == 0x28) depth++;
    if (char == 0x29) {
      depth--;
      if (depth == 0) return index;
    }
    index++;
  }
  return null;
}

/// Returns the index just past a string literal starting at [start].
int _skipString(String code, int start) {
  final quote = code.codeUnitAt(start);
  var index = start + 1;
  while (index < code.length) {
    final char = code.codeUnitAt(index);
    if (char == 0x5C) {
      index += 2;
      continue;
    }
    if (char == quote) return index + 1;
    index++;
  }
  return code.length;
}

/// Replaces Dart comments with whitespace while retaining every newline.
///
/// String literals are copied verbatim so URL-like `//` and prose containing
/// `/*` are not mistaken for comments. Nested block comments are supported.
String _stripDartComments(String source) {
  final output = StringBuffer();
  var index = 0;
  var blockDepth = 0;
  var quote = -1;
  var tripleQuoted = false;
  var rawString = false;

  while (index < source.length) {
    final current = source.codeUnitAt(index);
    final next = index + 1 < source.length ? source.codeUnitAt(index + 1) : -1;

    if (blockDepth > 0) {
      if (current == 0x2F && next == 0x2A) {
        output.write('  ');
        blockDepth++;
        index += 2;
      } else if (current == 0x2A && next == 0x2F) {
        output.write('  ');
        blockDepth--;
        index += 2;
      } else {
        output.write(current == 0x0A || current == 0x0D
            ? String.fromCharCode(current)
            : ' ');
        index++;
      }
      continue;
    }

    if (quote != -1) {
      if (!rawString && current == 0x5C) {
        output.writeCharCode(current);
        index++;
        if (index < source.length) {
          output.writeCharCode(source.codeUnitAt(index));
          index++;
        }
        continue;
      }

      if (tripleQuoted &&
          current == quote &&
          next == quote &&
          index + 2 < source.length &&
          source.codeUnitAt(index + 2) == quote) {
        output.writeCharCode(quote);
        output.writeCharCode(quote);
        output.writeCharCode(quote);
        index += 3;
        quote = -1;
        tripleQuoted = false;
        rawString = false;
        continue;
      }

      output.writeCharCode(current);
      index++;
      if (!tripleQuoted && current == quote) {
        quote = -1;
        rawString = false;
      }
      continue;
    }

    if (current == 0x2F && next == 0x2F) {
      output.write('  ');
      index += 2;
      while (index < source.length) {
        final commentChar = source.codeUnitAt(index);
        if (commentChar == 0x0A || commentChar == 0x0D) {
          break;
        }
        output.write(' ');
        index++;
      }
      continue;
    }

    if (current == 0x2F && next == 0x2A) {
      output.write('  ');
      blockDepth = 1;
      index += 2;
      continue;
    }

    if (current == 0x27 || current == 0x22) {
      quote = current;
      tripleQuoted = index + 2 < source.length &&
          source.codeUnitAt(index + 1) == current &&
          source.codeUnitAt(index + 2) == current;
      rawString = index > 0 &&
          (source.codeUnitAt(index - 1) == 0x72 ||
              source.codeUnitAt(index - 1) == 0x52) &&
          (index == 1 || !_isIdentifierCodeUnit(source.codeUnitAt(index - 2)));

      output.writeCharCode(current);
      index++;
      if (tripleQuoted) {
        output.writeCharCode(current);
        output.writeCharCode(current);
        index += 2;
      }
      continue;
    }

    output.writeCharCode(current);
    index++;
  }

  return output.toString();
}

bool _isIdentifierCodeUnit(int value) {
  return value == 0x5F ||
      value == 0x24 ||
      (value >= 0x30 && value <= 0x39) ||
      (value >= 0x41 && value <= 0x5A) ||
      (value >= 0x61 && value <= 0x7A);
}

class _Violation {
  const _Violation({
    required this.path,
    required this.line,
    required this.rule,
    required this.excerpt,
  });

  final String path;
  final int line;
  final String rule;
  final String excerpt;

  @override
  String toString() => '$path:$line [$rule] $excerpt';
}
