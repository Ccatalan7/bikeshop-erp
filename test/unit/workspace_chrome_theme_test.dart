import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/settings/services/appearance_service.dart';
import 'package:vinabike_erp/shared/themes/workspace_chrome_theme.dart';
import 'package:vinabike_erp/shared/widgets/workspace_shell_scope.dart';

void main() {
  test('every sidebar palette resolves accessible semantic chrome roles', () {
    for (final palette in AppearanceService.sidebarPalettes) {
      for (final brightness in Brightness.values) {
        final chrome = WorkspaceChromeTheme.resolve(
          palette: palette,
          brightness: brightness,
        );

        expect(
          _contrast(chrome.foreground, chrome.canvas),
          greaterThanOrEqualTo(4.5),
          reason: '${palette.code}/${brightness.name} foreground',
        );
        expect(
          _contrast(chrome.mutedForeground, chrome.canvas),
          greaterThanOrEqualTo(4.5),
          reason: '${palette.code}/${brightness.name} muted foreground',
        );
        expect(
          _contrast(chrome.onAccent, chrome.accent),
          greaterThanOrEqualTo(4.5),
          reason: '${palette.code}/${brightness.name} accent',
        );

        if (palette.code == 'vinabike') {
          expect(chrome.canvas, WorkspaceChromeStyleData.vinabike.canvas);
        } else {
          expect(chrome.canvas, palette.background);
          expect(chrome.raised, palette.backgroundAlt);
          expect(chrome.accent, palette.accent);
        }
      }
    }
  });

  test(
    'scoped chrome theme owns its complete neutral and component role families',
    () {
      for (final palette in AppearanceService.sidebarPalettes) {
        for (final baseTheme in <ThemeData>[
          ThemeData.light(useMaterial3: true),
          ThemeData.dark(useMaterial3: true),
        ]) {
          final chrome = WorkspaceChromeTheme.resolve(
            palette: palette,
            brightness: baseTheme.brightness,
          );
          final themed = WorkspaceChromeTheme.sidebarTheme(baseTheme, chrome);
          final scheme = themed.colorScheme;

          expect(scheme.surface, chrome.canvas);
          expect(scheme.surfaceContainerHighest, chrome.raised);
          expect(scheme.outline, chrome.edge);
          expect(scheme.outlineVariant, chrome.edge);
          expect(scheme.onSurface, chrome.foreground);
          expect(scheme.onSurfaceVariant, chrome.mutedForeground);
          expect(themed.inputDecorationTheme.fillColor, chrome.raised);
          expect(themed.inputDecorationTheme.prefixIconColor,
              chrome.mutedForeground);
          expect(themed.inputDecorationTheme.suffixIconColor,
              chrome.mutedForeground);
          expect(themed.textSelectionTheme.cursorColor, chrome.accent);

          expect(
            _contrast(scheme.onPrimaryContainer, scheme.primaryContainer),
            greaterThanOrEqualTo(4.5),
            reason: '${palette.code}/${baseTheme.brightness.name} selection',
          );
          expect(
            _contrast(scheme.onTertiaryContainer, scheme.tertiaryContainer),
            greaterThanOrEqualTo(4.5),
            reason: '${palette.code}/${baseTheme.brightness.name} warning',
          );
          expect(
            _contrast(scheme.onErrorContainer, scheme.errorContainer),
            greaterThanOrEqualTo(4.5),
            reason: '${palette.code}/${baseTheme.brightness.name} error',
          );
        }
      }
    },
  );

  test('legacy palette consumers delegate to the complete component resolver',
      () {
    for (final palette in AppearanceService.sidebarPalettes) {
      for (final baseTheme in <ThemeData>[
        ThemeData.light(useMaterial3: true),
        ThemeData.dark(useMaterial3: true),
      ]) {
        final themed = buildSidebarPaletteTheme(baseTheme, palette);

        expect(themed.colorScheme.surface, palette.background);
        expect(
            themed.colorScheme.surfaceContainerHighest, palette.backgroundAlt);
        expect(themed.colorScheme.outlineVariant, palette.border);
        expect(themed.inputDecorationTheme.fillColor, palette.backgroundAlt);
        expect(themed.inputDecorationTheme.prefixIconColor,
            palette.mutedForeground);
      }
    }
  });

  test('authenticated shell is the only workspace chrome owner', () {
    final main = File('lib/main.dart').readAsStringSync();
    final tabBar =
        File('lib/shared/widgets/workspace_tab_bar.dart').readAsStringSync();
    final sharedTheme = File('lib/shared/themes/workspace_chrome_theme.dart')
        .readAsStringSync();
    final shellScope = File('lib/shared/widgets/workspace_shell_scope.dart')
        .readAsStringSync();

    final shell = _between(
      main,
      'class _WorkspaceShellState',
      'class _WorkspaceRouterView',
    );
    expect(shell, contains('WorkspaceChromeTheme.resolve('));
    expect(RegExp(r'WorkspaceChromeStyle\(').allMatches(shell), hasLength(1));
    expect(tabBar, isNot(contains('return WorkspaceChromeStyle(')));
    expect(sharedTheme, isNot(contains('payroll_tokens')));
    expect(shellScope, isNot(contains('payroll_tokens')));
  });
}

double _contrast(Color first, Color second) {
  final lighter =
      first.computeLuminance() >= second.computeLuminance() ? first : second;
  final darker = lighter == first ? second : first;
  return (lighter.computeLuminance() + 0.05) /
      (darker.computeLuminance() + 0.05);
}

String _between(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, isNonNegative, reason: 'Missing start marker: $start');
  expect(endIndex, isNonNegative, reason: 'Missing end marker: $end');
  return source.substring(startIndex, endIndex);
}
