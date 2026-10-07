import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/deferred_load_failure.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/deferred_load_notice.dart';
import 'package:vinabike_erp/shared/widgets/vb_button.dart';

void main() {
  Future<void> show(
    WidgetTester tester,
    ThemeData theme,
    DeferredLoadFailure failure, {
    double width = 380,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 520,
              child: DeferredLoadNotice(failure: failure),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('says what happened and offers the reload, light and dark',
      (tester) async {
    for (final brightness in Brightness.values) {
      await show(
        tester,
        AppTheme.resolve(
          preset: AppearancePresets.all.first,
          brightness: brightness,
        ),
        DeferredLoadFailure.newBuild,
      );
      expect(find.text('Hay una versión nueva del ERP'), findsOneWidget);
      expect(find.textContaining('Recarga la página'), findsOneWidget);
      expect(find.widgetWithText(VbButton, 'Recargar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    await show(
      tester,
      AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      DeferredLoadFailure.unavailable,
    );
    expect(find.text('Esta parte del ERP no se cargó'), findsOneWidget);
  });

  testWidgets('renders under a theme without the ERP roles, in a narrow column',
      (tester) async {
    // An error surface lands wherever the error does.
    await show(
      tester,
      ThemeData(),
      DeferredLoadFailure.unavailable,
      width: 240,
    );
    expect(find.text('Recargar'), findsOneWidget);
    expect(find.byType(VbButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one line for a part that repeats, like a block of the canvas',
      (tester) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.all.first,
            brightness: brightness,
          ),
          home: const Scaffold(
            body: SizedBox(
              width: 320,
              child: DeferredLoadNotice.compact(
                failure: DeferredLoadFailure.newBuild,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Hay una versión nueva del ERP'), findsOneWidget);
      expect(find.widgetWithText(VbButton, 'Recargar'), findsOneWidget);
      expect(find.textContaining('Recarga la página'), findsNothing);
      // The touch-height button (48) and its padding: a row, not a panel.
      expect(
        tester.getSize(find.byType(DeferredLoadNotice)).height,
        lessThanOrEqualTo(72),
      );
      expect(tester.takeException(), isNull);
    }
  });
}
