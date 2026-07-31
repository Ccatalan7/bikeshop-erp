import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/themes/vinabike_theme_roles.dart';
import 'package:vinabike_erp/shared/themes/workspace_chrome_theme.dart';

void main() {
  group('preset x brightness resolver', () {
    for (final preset in AppearancePresets.all) {
      for (final brightness in Brightness.values) {
        test('${preset.code}/${brightness.name} resolves complete roles', () {
          final theme = AppTheme.resolve(
            preset: preset,
            brightness: brightness,
          );
          final scheme = theme.colorScheme;
          final roles = theme.extension<VinabikeThemeRoles>();

          expect(theme.brightness, brightness);
          expect(scheme.brightness, brightness);
          expect(roles, isNotNull);
          expect(roles!.presetCode, preset.code);
          expect(roles.brightness, brightness);
          expect(scheme.primary, preset.contentSeedFor(brightness).primary);
          expect(scheme.surfaceContainerLowest, isNot(scheme.surfaceContainer));
          expect(
              scheme.surfaceContainerLow, isNot(scheme.surfaceContainerHigh));
          expect(
            scheme.surfaceContainerHigh,
            isNot(scheme.surfaceContainerHighest),
          );

          _expectContrast(
            scheme.onPrimary,
            scheme.primary,
            '${preset.code}/${brightness.name} primary',
          );
          _expectContrast(
            scheme.onSurface,
            scheme.surface,
            '${preset.code}/${brightness.name} surface',
          );
          _expectContrast(
            scheme.onSurfaceVariant,
            scheme.surfaceContainerLow,
            '${preset.code}/${brightness.name} secondary text',
          );
          _expectToneContrast(
            roles.success,
            '${preset.code}/${brightness.name} success',
          );
          _expectToneContrast(
            roles.warning,
            '${preset.code}/${brightness.name} warning',
          );
          _expectToneContrast(
            roles.info,
            '${preset.code}/${brightness.name} info',
          );
          _expectToneContrast(
            roles.neutral,
            '${preset.code}/${brightness.name} neutral',
          );

          final chrome = WorkspaceChromeTheme.resolveFromTheme(theme);
          expect(chrome.canvas, preset.shell.canvas);
          expect(chrome.raised, preset.shell.raised);
          expect(chrome.edge, preset.shell.edge);
          expect(chrome.foreground, preset.shell.foreground);
          expect(chrome.mutedForeground, preset.shell.mutedForeground);
          expect(chrome.accent, preset.shell.accent);
          expect(chrome.onAccent, preset.shell.onAccent);
          expect(chrome.dirty, preset.shell.dirty);
          expect(chrome.attention, preset.shell.attention);

          expect(
            theme.inputDecorationTheme.fillColor,
            scheme.surface,
          );
          expect(theme.dialogTheme.backgroundColor, scheme.surfaceContainerLow);
          expect(
            theme.bottomSheetTheme.modalBackgroundColor,
            scheme.surfaceContainerLow,
          );
          expect(
            theme.searchBarTheme.backgroundColor?.resolve({}),
            scheme.surfaceContainerLow,
          );
          expect(
            theme.datePickerTheme.backgroundColor,
            scheme.surfaceContainerLow,
          );
          expect(
            theme.datePickerTheme.headerBackgroundColor,
            scheme.primary,
          );
          _expectContrast(
            theme.datePickerTheme.headerHelpStyle!.color!,
            theme.datePickerTheme.headerBackgroundColor!,
            '${preset.code}/${brightness.name} date picker header help',
          );
          expect(
            theme.datePickerTheme.dayBackgroundColor?.resolve(
              const <WidgetState>{WidgetState.selected},
            ),
            scheme.primary,
          );
          expect(
            theme.timePickerTheme.backgroundColor,
            scheme.surfaceContainerLow,
          );
          expect(
            WidgetStateProperty.resolveAs<Color?>(
              theme.timePickerTheme.hourMinuteColor,
              const <WidgetState>{WidgetState.selected},
            ),
            roles.selectionContainer,
          );
          expect(
            (theme.tooltipTheme.decoration as BoxDecoration?)?.color,
            scheme.inverseSurface,
          );
          expect(
            theme.segmentedButtonTheme.style?.backgroundColor?.resolve(
              const <WidgetState>{WidgetState.selected},
            ),
            roles.selectionContainer,
          );
          _expectContrast(
            theme.segmentedButtonTheme.style!.foregroundColor!.resolve(
              const <WidgetState>{WidgetState.selected},
            )!,
            roles.selectionContainer,
            '${preset.code}/${brightness.name} segmented selection',
          );
          _expectContrast(
            theme.datePickerTheme.dayForegroundColor!.resolve(
              const <WidgetState>{WidgetState.selected},
            )!,
            scheme.primary,
            '${preset.code}/${brightness.name} selected date',
          );
          _expectContrast(
            WidgetStateProperty.resolveAs<Color?>(
              theme.timePickerTheme.hourMinuteTextColor,
              const <WidgetState>{WidgetState.selected},
            )!,
            roles.selectionContainer,
            '${preset.code}/${brightness.name} selected time',
          );
          expect(theme.tabBarTheme.labelColor, scheme.primary);
          expect(theme.badgeTheme.backgroundColor, scheme.error);
          expect(theme.badgeTheme.textColor, scheme.onError);
          _expectContrast(
            theme.badgeTheme.textColor!,
            theme.badgeTheme.backgroundColor!,
            '${preset.code}/${brightness.name} badge',
          );
          expect(theme.sliderTheme.activeTrackColor, scheme.primary);
          expect(
            theme.navigationBarTheme.backgroundColor,
            scheme.surfaceContainerLow,
          );
          expect(
            theme.navigationDrawerTheme.backgroundColor,
            scheme.surfaceContainerLow,
          );
          expect(theme.bannerTheme.backgroundColor, scheme.surface);
          _expectContrast(
            theme.bannerTheme.contentTextStyle!.color!,
            theme.bannerTheme.backgroundColor!,
            '${preset.code}/${brightness.name} banner content',
          );
          _expectContrast(
            theme.textButtonTheme.style!.foregroundColor!.resolve(
              const <WidgetState>{},
            )!,
            theme.bannerTheme.backgroundColor!,
            '${preset.code}/${brightness.name} banner text action',
          );
          final scrollbarTrack =
              theme.scrollbarTheme.trackColor!.resolve(const <WidgetState>{})!;
          final scrollbarThumb =
              theme.scrollbarTheme.thumbColor!.resolve(const <WidgetState>{})!;
          final scrollbarHoverThumb = theme.scrollbarTheme.thumbColor!.resolve(
            const <WidgetState>{WidgetState.hovered},
          )!;
          final scrollbarDraggedThumb =
              theme.scrollbarTheme.thumbColor!.resolve(
            const <WidgetState>{WidgetState.dragged},
          )!;
          _expectUiContrast(
            scrollbarThumb,
            scrollbarTrack,
            '${preset.code}/${brightness.name} scrollbar resting',
          );
          _expectContrast(
            scrollbarHoverThumb,
            scrollbarTrack,
            '${preset.code}/${brightness.name} scrollbar hover',
          );
          expect(
            _contrast(scrollbarDraggedThumb, scrollbarTrack),
            greaterThanOrEqualTo(7),
            reason:
                '${preset.code}/${brightness.name} scrollbar dragged contrast',
          );
          expect(scrollbarHoverThumb, isNot(scrollbarThumb));
          expect(scrollbarDraggedThumb, isNot(scrollbarHoverThumb));
          expect(
            theme.filledButtonTheme.style?.backgroundColor?.resolve({}),
            scheme.primary,
          );
          expect(
            theme.filledButtonTheme.style?.foregroundColor?.resolve({}),
            scheme.onPrimary,
          );
          _expectContrast(
            theme.snackBarTheme.contentTextStyle!.color!,
            scheme.inverseSurface,
            '${preset.code}/${brightness.name} snackbar content',
          );
          _expectContrast(
            theme.snackBarTheme.actionTextColor!,
            scheme.inverseSurface,
            '${preset.code}/${brightness.name} snackbar action',
          );
        });
      }
    }

    test('dark content surfaces remain chromatic and preset-aware', () {
      final canvases = <Color>{};
      final primaries = <Color>{};

      for (final preset in AppearancePresets.all) {
        final theme = AppTheme.resolve(
          preset: preset,
          brightness: Brightness.dark,
        );
        canvases.add(theme.scaffoldBackgroundColor);
        primaries.add(theme.colorScheme.primary);
        expect(theme.scaffoldBackgroundColor, isNot(Colors.black));
      }

      expect(canvases, hasLength(AppearancePresets.all.length));
      expect(primaries, hasLength(AppearancePresets.all.length));
    });

    test('light content surfaces keep the canonical Design hierarchy', () {
      for (final preset in AppearancePresets.all) {
        final theme = AppTheme.resolve(
          preset: preset,
          brightness: Brightness.light,
        );
        final scheme = theme.colorScheme;

        expect(theme.scaffoldBackgroundColor, const Color(0xFFEEF1F5));
        expect(scheme.surface, const Color(0xFFFFFFFF));
        expect(scheme.surfaceContainerLow, const Color(0xFFF7F8FA));
        expect(scheme.surfaceContainer, const Color(0xFFEEF1F5));
        expect(scheme.surfaceContainerHigh, const Color(0xFFEEF1F4));
        expect(scheme.surfaceContainerHighest, const Color(0xFFE2E7ED));
      }
    });

    test('persisted preset codes and compatibility sidebar catalog stay stable',
        () {
      expect(
        AppearancePresets.all.map((preset) => preset.code).toList(),
        const [
          'vinabike',
          'midnight',
          'aubergine',
          'graphite_copper',
          'evergreen',
          'pacific',
        ],
      );
      expect(
        AppearancePresets.sidebarPalettes
            .map((palette) => palette.code)
            .toList(),
        AppearancePresets.all.map((preset) => preset.code).toList(),
      );
      expect(AppearancePresets.byCode('missing'), AppearancePresets.vinabike);
    });
  });

  test('only the canonical authenticated ERP MaterialApp uses preset resolver',
      () {
    final source = File('lib/main.dart').readAsStringSync();
    final authenticatedApp = _between(
      source,
      '// Canonical authenticated ERP theme owner.',
      'home: _WorkspaceDeepLinkBridge(',
    );
    final initializationApp = _between(
      source,
      'if ((authService.isInitializing || isWaitingForStaffCheck)',
      '// Public store or not authenticated = single router',
    );

    expect(
      RegExp(r'AppTheme\.resolve\(').allMatches(authenticatedApp),
      hasLength(2),
    );
    expect(authenticatedApp, contains('appearanceService.appearancePreset'));
    expect(authenticatedApp, contains('Brightness.light'));
    expect(authenticatedApp, contains('Brightness.dark'));
    expect(initializationApp, contains('AppTheme.lightTheme'));
    expect(initializationApp, contains('AppTheme.darkTheme'));
  });
}

void _expectToneContrast(VinabikeSemanticTone tone, String reason) {
  _expectContrast(tone.onAccent, tone.accent, '$reason accent');
  _expectContrast(tone.onContainer, tone.container, '$reason container');
}

void _expectContrast(Color foreground, Color background, String reason) {
  expect(
    _contrast(foreground, background),
    greaterThanOrEqualTo(4.5),
    reason: reason,
  );
}

void _expectUiContrast(Color foreground, Color background, String reason) {
  expect(
    _contrast(foreground, background),
    greaterThanOrEqualTo(3),
    reason: reason,
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

String _between(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(startIndex, isNonNegative, reason: 'Missing start marker: $start');
  expect(endIndex, isNonNegative, reason: 'Missing end marker: $end');
  return source.substring(startIndex, endIndex);
}
