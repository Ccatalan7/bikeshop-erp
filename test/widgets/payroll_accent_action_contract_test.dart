import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/hr/payroll/surfaces/payroll_accent_action.dart';
import 'package:vinabike_erp/modules/hr/payroll/theme/payroll_tokens.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/themes/vinabike_theme_roles.dart';

/// Rendered freeze of the PayrollAccentAction on-accent contract across the
/// full preset × brightness matrix. Together with the owner source contract
/// in payroll_theme_architecture_test.dart this makes an owner mutation to
/// onSurface/surface/canvas/ink (visible roles) or scheme.onPrimary (source
/// rule) impossible to land while green.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Future<void> pump(
    WidgetTester tester,
    ThemeData theme,
    Widget action,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        key: UniqueKey(),
        theme: theme,
        home:
            Scaffold(body: Center(child: SizedBox(width: 260, child: action))),
      ),
    );
    await tester.pump();
  }

  Material actionMaterial(WidgetTester tester) => tester.widget<Material>(
        find
            .descendant(
              of: find.byType(PayrollAccentAction),
              matching: find.byType(Material),
            )
            .first,
      );

  InkWell actionInkWell(WidgetTester tester) => tester.widget<InkWell>(
        find
            .descendant(
              of: find.byType(PayrollAccentAction),
              matching: find.byType(InkWell),
            )
            .first,
      );

  testWidgets('interactive, busy and disabled states follow the contract',
      (tester) async {
    // Visible-role mutation coverage: for every forbidden foreground role the
    // matrix must contain at least one cell where it differs from onAccent,
    // so the equality assertions below would catch that mutation.
    final distinguishable = <String, bool>{
      'onSurface (ink)': false,
      'surface': false,
      'canvas': false,
      'onSurfaceVariant (inkMuted)': false,
    };

    for (final preset in AppearancePresets.all) {
      for (final brightness in Brightness.values) {
        final theme = AppTheme.resolve(preset: preset, brightness: brightness);
        final scheme = theme.colorScheme;
        final roles = theme.extension<VinabikeThemeRoles>()!;
        final cell = '${preset.code}/${brightness.name}';

        distinguishable['onSurface (ink)'] =
            distinguishable['onSurface (ink)']! ||
                scheme.onSurface != scheme.onPrimary;
        distinguishable['surface'] =
            distinguishable['surface']! || scheme.surface != scheme.onPrimary;
        distinguishable['canvas'] = distinguishable['canvas']! ||
            theme.scaffoldBackgroundColor != scheme.onPrimary;
        distinguishable['onSurfaceVariant (inkMuted)'] =
            distinguishable['onSurfaceVariant (inkMuted)']! ||
                scheme.onSurfaceVariant != scheme.onPrimary;

        // Interactive: accent fill, onAccent label, onAccent-derived
        // overlays.
        await pump(
          tester,
          theme,
          PayrollAccentAction(label: 'Pagar', onTap: () {}),
        );
        expect(actionMaterial(tester).color, scheme.primary, reason: cell);
        final label = tester.widget<Text>(find.text('Pagar'));
        expect(label.style?.color, scheme.onPrimary, reason: cell);
        final inkWell = actionInkWell(tester);
        expect(
          inkWell.hoverColor,
          scheme.onPrimary.withValues(alpha: 0.12),
          reason: cell,
        );
        expect(
          inkWell.focusColor,
          scheme.onPrimary.withValues(alpha: 0.16),
          reason: cell,
        );

        // Busy: dimmed accent fill and an onAccent spinner.
        await pump(
          tester,
          theme,
          PayrollAccentAction(label: 'Pagar', onTap: () {}, busy: true),
        );
        expect(
          actionMaterial(tester).color,
          scheme.primary.withValues(alpha: 0.55),
          reason: cell,
        );
        final spinner = tester.widget<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator),
        );
        expect(spinner.color, scheme.onPrimary, reason: cell);

        // Disabled styles: canonical quiet fills with disabled foreground.
        final disabledFills = <PayrollAccentDisabledStyle, Color>{
          PayrollAccentDisabledStyle.surfaceBordered: scheme.surface,
          PayrollAccentDisabledStyle.sunkenBordered: scheme.surfaceContainerLow,
          PayrollAccentDisabledStyle.neutral: roles.neutral.container,
        };
        for (final entry in disabledFills.entries) {
          await pump(
            tester,
            theme,
            PayrollAccentAction(
              label: 'Pagar',
              onTap: () {},
              enabled: false,
              disabledStyle: entry.key,
            ),
          );
          expect(
            actionMaterial(tester).color,
            entry.value,
            reason: '$cell ${entry.key}',
          );
          final disabledLabel = tester.widget<Text>(find.text('Pagar'));
          expect(
            disabledLabel.style?.color,
            roles.disabledForeground,
            reason: '$cell ${entry.key}',
          );
          expect(actionInkWell(tester).onTap, isNull,
              reason: '$cell ${entry.key}');
        }

        expect(tester.takeException(), isNull, reason: cell);
      }
    }

    distinguishable.forEach((role, covered) {
      expect(
        covered,
        isTrue,
        reason: 'the matrix cannot distinguish a mutation to $role from '
            'onAccent — extend the matrix',
      );
    });
  });

  testWidgets('geometry parameters render exactly (call-site parity freeze)',
      (tester) async {
    final theme = AppTheme.resolve(
      preset: AppearancePresets.vinabike,
      brightness: Brightness.light,
    );

    await pump(
      tester,
      theme,
      PayrollAccentAction(label: 'Pagar', onTap: () {}, height: 32),
    );
    expect(tester.getSize(find.byType(PayrollAccentAction)).height, 32);

    await pump(
      tester,
      theme,
      PayrollAccentAction(
        label: 'Pagar',
        onTap: () {},
        height: PayrollTokens.touchMobile,
        borderRadius: 11,
      ),
    );
    // Igualdad EXACTA al token: un `>= 48` dejaría pasar el 50 que este
    // contrato existe para impedir.
    expect(tester.getSize(find.byType(PayrollAccentAction)).height,
        PayrollTokens.touchMobile);
    final shape = actionMaterial(tester).shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(11));

    await pump(
      tester,
      theme,
      IntrinsicWidth(
        child: PayrollAccentAction(
          label: 'Pagar',
          onTap: () {},
          minHeight: 28,
          verticalPadding: 5,
          horizontalPadding: 10,
        ),
      ),
    );
    expect(
      tester.getSize(find.byType(PayrollAccentAction)).height,
      greaterThanOrEqualTo(28),
    );
  });
}
