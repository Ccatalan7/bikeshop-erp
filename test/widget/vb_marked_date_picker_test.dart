import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/vb_marked_date_picker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pending = VbMarkedDateMarker(
    status: VbMarkedDateStatus.pending,
    label: 'Compras sin factura',
  );
  const invoiced = VbMarkedDateMarker(
    status: VbMarkedDateStatus.invoiced,
    label: 'Día ya facturado',
  );

  testWidgets(
    'muestra las marcas en sus celdas antes de seleccionar y no bloquea días sin marca',
    (tester) async {
      final result = ValueNotifier<DateTime?>(null);
      await _pumpHarness(
        tester,
        result: result,
        markers: {
          DateTime(2026, 8, 5, 23): pending,
          DateTime(2026, 8, 9): invoiced,
        },
      );

      await tester.tap(find.text('Abrir calendario'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('vb-marked-date-marker-2026-08-05')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('vb-marked-date-marker-2026-08-09')),
        findsOneWidget,
      );
      expect(find.text('Compras sin factura'), findsOneWidget);
      expect(find.text('Día ya facturado'), findsOneWidget);

      final pendingSemantics = tester.getSemantics(
        find.byKey(const ValueKey('vb-marked-date-day-2026-08-05')),
      );
      expect(pendingSemantics.label, contains('Compras sin factura'));

      // El 6 no tiene marca: ausencia significa «no consta», no
      // «deshabilitado». Sigue siendo una fecha seleccionable.
      await tester.tap(
        find.byKey(const ValueKey('vb-marked-date-day-2026-08-06')),
      );
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();

      expect(result.value, DateTime(2026, 8, 6));
    },
  );

  testWidgets('navega por mes y por año sin perder el owner', (tester) async {
    final result = ValueNotifier<DateTime?>(null);
    await _pumpHarness(
      tester,
      result: result,
      markers: {DateTime(2026, 9, 3): pending},
    );

    await tester.tap(find.text('Abrir calendario'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('vb-marked-date-marker-2026-09-03')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('vb-marked-date-next-month')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('vb-marked-date-marker-2026-09-03')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('vb-marked-date-month-year')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('vb-marked-date-year-picker')),
      findsOneWidget,
    );

    await tester.tap(find.text('2027'));
    await tester.pumpAndSettle();
    expect(find.text('September 2027'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      '390px ${brightness.name}: full-screen, leyenda y calendario sin overflow',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.reset);

        final result = ValueNotifier<DateTime?>(null);
        await _pumpHarness(
          tester,
          result: result,
          markers: {
            DateTime(2026, 8, 5): pending,
            DateTime(2026, 8, 9): invoiced,
          },
          brightness: brightness,
        );

        await tester.tap(find.text('Abrir calendario'));
        await tester.pumpAndSettle();

        expect(find.byType(Scaffold), findsWidgets);
        expect(
          find.byKey(const ValueKey('vb-marked-date-marker-2026-08-05')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('vb-marked-date-legend-pending')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('vb-marked-date-legend-invoiced')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
      },
    );
  }
}

Future<void> _pumpHarness(
  WidgetTester tester, {
  required ValueNotifier<DateTime?> result,
  required Map<DateTime, VbMarkedDateMarker> markers,
  Brightness brightness = Brightness.light,
}) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: brightness,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () async {
                result.value = await showVbMarkedDatePicker(
                  context: context,
                  initialDate: DateTime(2026, 8, 1),
                  firstDate: DateTime(2025),
                  lastDate: DateTime(2028, 12, 31),
                  currentDate: DateTime(2026, 8, 9),
                  markers: markers,
                  helpText: 'Elegir día de compra',
                  cancelText: 'Cancelar',
                  confirmText: 'Aceptar',
                );
              },
              child: const Text('Abrir calendario'),
            ),
          ),
        ),
      ),
    ),
  );
}
