import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/hr/payroll/theme/payroll_tokens.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/themes/vinabike_theme_roles.dart';

void main() {
  group('Payroll visual tokens follow the mounted app theme', () {
    for (final preset in AppearancePresets.all) {
      for (final brightness in Brightness.values) {
        testWidgets('${preset.code}/${brightness.name}', (tester) async {
          late PayrollVisualTokens tokens;
          final theme = AppTheme.resolve(
            preset: preset,
            brightness: brightness,
          );

          await tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Builder(
                builder: (context) {
                  tokens = PayrollVisualTokens.of(context);
                  return const SizedBox.shrink();
                },
              ),
            ),
          );

          final scheme = theme.colorScheme;
          final roles = theme.extension<VinabikeThemeRoles>()!;
          // The resolver owns the canvas semantics through
          // scaffoldBackgroundColor: cool surfaceContainer in light,
          // preset-tinted surfaceContainerLowest in dark.
          expect(tokens.canvas, theme.scaffoldBackgroundColor);
          expect(
            tokens.canvas,
            brightness == Brightness.light
                ? scheme.surfaceContainer
                : scheme.surfaceContainerLowest,
          );
          expect(tokens.surface, scheme.surface);
          expect(tokens.surfaceSunken, scheme.surfaceContainerLow);
          // Selection consumes the canonical role, never a local blend.
          expect(tokens.surfaceSelected, roles.selectionContainer);
          expect(tokens.onSurfaceSelected, roles.onSelectionContainer);
          expect(tokens.onAccent, scheme.onPrimary);
          _expectContrast(tokens.onAccent, tokens.accent);
          _expectContrast(tokens.onSurfaceSelected, tokens.surfaceSelected);
          // The LIVE selection pair: History paints its selected content
          // with ink over the selection fill (onSurfaceSelected stays as
          // vocabulary for stronger treatments).
          _expectContrast(tokens.ink, tokens.surfaceSelected);
          // The selected/expanded meanings must never collapse into one
          // tint in any preset (F5.1 split).
          expect(tokens.surfaceSelected, isNot(tokens.surfaceSunken));
          expect(tokens.border, scheme.outlineVariant);
          expect(tokens.borderStrong, scheme.outline);
          expect(tokens.ink, scheme.onSurface);
          expect(tokens.inkMuted, scheme.onSurfaceVariant);
          expect(tokens.accent, scheme.primary);
          expect(tokens.shell, roles.shell.canvas);
          expect(tokens.brand, roles.shell.accent);
          expect(tokens.successSoft, roles.success.container);
          expect(tokens.warningSoft, roles.warning.container);
          expect(tokens.dangerSoft, scheme.errorContainer);

          _expectContrast(tokens.ink, tokens.surface);
          _expectContrast(tokens.successFg, tokens.successSoft);
          _expectContrast(tokens.warningFg, tokens.warningSoft);
          _expectContrast(tokens.dangerFg, tokens.dangerSoft);
          _expectContrast(tokens.neutralFg, tokens.neutralSoft);

          if (brightness == Brightness.dark) {
            expect(tokens.canvas, isNot(Colors.black));
            expect(tokens.surface, isNot(Colors.black));
            expect(tokens.surfaceSunken, isNot(Colors.black));
          }
        });
      }
    }
  });

  testWidgets('isolated compatibility hosts still follow brightness',
      (tester) async {
    late PayrollVisualTokens tokens;
    final theme = ThemeData.dark(useMaterial3: true);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) {
            tokens = PayrollVisualTokens.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(tokens.roles, isNull);
    expect(tokens.theme.brightness, Brightness.dark);
    expect(tokens.canvas.computeLuminance(), lessThan(0.2));
    _expectContrast(tokens.ink, tokens.surface);
  });
}

void _expectContrast(Color foreground, Color background) {
  expect(_contrast(foreground, background), greaterThanOrEqualTo(4.5));
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
