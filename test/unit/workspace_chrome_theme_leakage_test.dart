import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/settings/services/appearance_service.dart';
import 'package:vinabike_erp/shared/themes/workspace_chrome_theme.dart';
import 'package:vinabike_erp/shared/widgets/workspace_shell_scope.dart';

void main() {
  group('compact workspace chrome theme boundary', () {
    for (final palette in AppearanceService.sidebarPalettes) {
      test(
        '${palette.code} drawer roles do not inherit global light or dark colors',
        () {
          final chrome = WorkspaceChromeTheme.resolve(
            palette: palette,
            brightness: Brightness.light,
          );
          final fromLight = WorkspaceChromeTheme.sidebarTheme(
            ThemeData.light(useMaterial3: true),
            chrome,
          );
          final fromDark = WorkspaceChromeTheme.sidebarTheme(
            ThemeData.dark(useMaterial3: true),
            chrome,
          );

          final lightRoles = _CompactChromeRoles.fromTheme(fromLight);
          final darkRoles = _CompactChromeRoles.fromTheme(fromDark);

          expect(
            lightRoles,
            darkRoles,
            reason:
                'The global app brightness must not recolor the navy drawer, '
                'its mode switch, search field, labels, icons, hover, or '
                'selected states.',
          );

          _expectChromeRoleQuality(
            roles: lightRoles,
            chrome: chrome,
            reasonPrefix: '${palette.code}/global-light',
          );
          _expectChromeRoleQuality(
            roles: darkRoles,
            chrome: chrome,
            reasonPrefix: '${palette.code}/global-dark',
          );
        },
      );
    }

    test(
      'the compact drawer search consumes the scoped semantic roles',
      () {
        final source =
            File('lib/shared/widgets/main_layout.dart').readAsStringSync();
        final themeSource = File(
          'lib/shared/themes/workspace_chrome_theme.dart',
        ).readAsStringSync();
        // 2026-08-20 · el conmutador Navegación/Herramientas se retiró: el
        // drawer es sólo navegación. Lo que sigue vivo —y lo que este contrato
        // protege— es que su buscador consuma los roles del chrome y no la
        // tinta clara de la app.
        final search = _between(
          source,
          'Widget _buildCompactNavigationSearch(',
          'Widget _buildCompactSearchResults(',
        );

        expect(
          source,
          isNot(contains('Widget _buildDrawerModeSwitch(')),
        );
        expect(search, contains('decoration: InputDecoration('));
        expect(search, contains('prefixIcon: const Icon('));
        expect(search, isNot(contains('fillColor:')));
        expect(search, isNot(contains('enabledBorder:')));
        expect(search, isNot(contains('focusedBorder:')));
        expect(
          themeSource,
          contains('inputDecorationTheme: InputDecorationTheme('),
        );
        expect(
          themeSource,
          contains('fillColor: colorScheme.surfaceContainerHighest'),
        );
        expect(
            themeSource, contains('prefixIconColor: chrome.mutedForeground'));
        expect(themeSource, contains('focusedBorder: fieldBorder.copyWith('));

        for (final implementation in <String>[search]) {
          expect(implementation, isNot(contains('Colors.white')));
          expect(implementation, isNot(contains('Colors.black')));
          expect(implementation, isNot(contains('ThemeData.light')));
          expect(implementation, isNot(contains('ThemeData.dark')));
          expect(
            RegExp(r'Color\\(0x[0-9A-Fa-f]+\\)').hasMatch(implementation),
            isFalse,
            reason:
                'Compact chrome controls must not patch leakage with literals.',
          );
        }
      },
    );
  });
}

@immutable
class _CompactChromeRoles {
  const _CompactChromeRoles({
    required this.modeAndSearchSurface,
    required this.modeAndSearchOutline,
    required this.selectedLabel,
    required this.unselectedLabelAndHint,
    required this.bodyLabel,
    required this.icon,
    required this.hover,
    required this.focus,
    required this.highlight,
    required this.splash,
    required this.selectedSurface,
  });

  factory _CompactChromeRoles.fromTheme(ThemeData theme) {
    final scheme = theme.colorScheme;
    return _CompactChromeRoles(
      modeAndSearchSurface: scheme.surfaceContainerHighest,
      modeAndSearchOutline: scheme.outlineVariant,
      selectedLabel: scheme.onPrimaryContainer,
      unselectedLabelAndHint: scheme.onSurfaceVariant,
      bodyLabel: theme.textTheme.bodyMedium?.color,
      icon: theme.iconTheme.color,
      hover: theme.hoverColor,
      focus: theme.focusColor,
      highlight: theme.highlightColor,
      splash: theme.splashColor,
      selectedSurface: scheme.primaryContainer,
    );
  }

  final Color modeAndSearchSurface;
  final Color modeAndSearchOutline;
  final Color selectedLabel;
  final Color unselectedLabelAndHint;
  final Color? bodyLabel;
  final Color? icon;
  final Color hover;
  final Color focus;
  final Color highlight;
  final Color splash;
  final Color selectedSurface;

  @override
  bool operator ==(Object other) {
    return other is _CompactChromeRoles &&
        modeAndSearchSurface == other.modeAndSearchSurface &&
        modeAndSearchOutline == other.modeAndSearchOutline &&
        selectedLabel == other.selectedLabel &&
        unselectedLabelAndHint == other.unselectedLabelAndHint &&
        bodyLabel == other.bodyLabel &&
        icon == other.icon &&
        hover == other.hover &&
        focus == other.focus &&
        highlight == other.highlight &&
        splash == other.splash &&
        selectedSurface == other.selectedSurface;
  }

  @override
  int get hashCode => Object.hash(
        modeAndSearchSurface,
        modeAndSearchOutline,
        selectedLabel,
        unselectedLabelAndHint,
        bodyLabel,
        icon,
        hover,
        focus,
        highlight,
        splash,
        selectedSurface,
      );
}

void _expectChromeRoleQuality({
  required _CompactChromeRoles roles,
  required WorkspaceChromeStyleData chrome,
  required String reasonPrefix,
}) {
  final maximumChromeSurfaceLuminance =
      _max(chrome.canvas.computeLuminance(), chrome.raised.computeLuminance()) +
          0.08;

  expect(
    roles.modeAndSearchSurface.computeLuminance(),
    lessThanOrEqualTo(maximumChromeSurfaceLuminance),
    reason: '$reasonPrefix mode/search surface escaped the dark chrome family',
  );
  expect(
    _contrast(chrome.foreground, roles.modeAndSearchSurface),
    greaterThanOrEqualTo(4.5),
    reason: '$reasonPrefix primary label contrast',
  );
  expect(
    _contrast(roles.unselectedLabelAndHint, roles.modeAndSearchSurface),
    greaterThanOrEqualTo(4.5),
    reason: '$reasonPrefix unselected label/search hint contrast',
  );
  expect(
    _contrast(roles.selectedLabel, roles.selectedSurface),
    greaterThanOrEqualTo(4.5),
    reason: '$reasonPrefix selected mode contrast',
  );
  expect(
    roles.bodyLabel,
    chrome.foreground,
    reason: '$reasonPrefix typed search text/body label',
  );
  expect(
    roles.icon,
    chrome.mutedForeground,
    reason: '$reasonPrefix search/navigation icon',
  );
  expect(
    roles.modeAndSearchOutline,
    chrome.edge,
    reason: '$reasonPrefix mode/search boundary',
  );

  final hoveredSurface = Color.alphaBlend(roles.hover, chrome.canvas);
  expect(
    hoveredSurface,
    isNot(chrome.canvas),
    reason: '$reasonPrefix hover must remain visibly distinguishable',
  );
  expect(
    _contrast(chrome.foreground, hoveredSurface),
    greaterThanOrEqualTo(4.5),
    reason: '$reasonPrefix hovered label contrast',
  );
}

double _contrast(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter =
      firstLuminance >= secondLuminance ? firstLuminance : secondLuminance;
  final darker =
      firstLuminance >= secondLuminance ? secondLuminance : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

double _max(double first, double second) => first > second ? first : second;

String _between(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, isNonNegative, reason: 'Missing start marker: $start');
  expect(endIndex, isNonNegative, reason: 'Missing end marker: $end');
  return source.substring(startIndex, endIndex);
}
