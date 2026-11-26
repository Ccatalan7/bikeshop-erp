import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/vb_searchable_select.dart';

Future<List<String>> _pump(
  WidgetTester tester, {
  required Size size,
  required List<String> chosen,
  List<VbSearchableSelectOption<String>> options = const [
    VbSearchableSelectOption(value: 'trek', label: 'Trek'),
    VbSearchableSelectOption(value: 'giant', label: 'Giant'),
  ],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final created = <String>[];
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.resolve(
      preset: AppearancePresets.all.first,
      brightness: Brightness.light,
    ),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 320,
          child: VbSearchableSelect<String>(
            value: null,
            options: options,
            onChanged: (value) => chosen.add(value ?? 'null'),
            onCreate: created.add,
            sheetTitle: 'Marca',
            label: 'Marca',
          ),
        ),
      ),
    ),
  ));
  return created;
}

void main() {
  testWidgets('typing a name that is not in the list offers to add it',
      (tester) async {
    final chosen = <String>[];
    final created =
        await _pump(tester, size: const Size(1440, 900), chosen: chosen);
    await tester.tap(find.bySemanticsLabel('Marca').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'trek');
    await tester.pumpAndSettle();
    // Lo escrito ya es una opción: no se ofrece agregarlo.
    expect(find.text('Agregar «trek»'), findsNothing);

    await tester.enterText(find.byType(TextField), '  Oxford ');
    await tester.pumpAndSettle();
    expect(find.text('Agregar «Oxford»'), findsOneWidget);
    // Sin coincidencias, Enter agrega.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(created, ['Oxford']);
    expect(chosen, isEmpty);
  });

  testWidgets('the phone sheet offers the same row', (tester) async {
    final chosen = <String>[];
    final created =
        await _pump(tester, size: const Size(400, 860), chosen: chosen);
    await tester.tap(find.bySemanticsLabel('Marca').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Gian');
    await tester.pumpAndSettle();
    expect(find.text('Giant'), findsWidgets);
    expect(find.text('Agregar «Gian»'), findsOneWidget);
    await tester.tap(find.text('Agregar «Gian»'));
    await tester.pumpAndSettle();
    expect(created, ['Gian']);
    expect(chosen, isEmpty);
  });

  testWidgets('an empty catalog still opens to add its first option',
      (tester) async {
    final chosen = <String>[];
    final created = await _pump(tester,
        size: const Size(1440, 900), chosen: chosen, options: const []);
    await tester.tap(find.bySemanticsLabel('Marca').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Oxford');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar «Oxford»'));
    await tester.pumpAndSettle();
    expect(created, ['Oxford']);
  });

  // La llanta ofrece las medidas del taller; las raras de la tabla ISO
  // aparecen al buscarlas (2026-11-25).
  for (final size in const [Size(1440, 900), Size(400, 860)]) {
    testWidgets(
        'an option listed only when searched appears when typed '
        '(${size.width.toInt()} px)', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final chosen = <int?>[];
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.resolve(
          preset: AppearancePresets.all.first,
          brightness: Brightness.light,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: VbSearchableSelect<int>(
                value: null,
                options: const [
                  VbSearchableSelectOption(value: 622, label: '622 (29″/700c)'),
                  VbSearchableSelectOption(value: 559, label: '559 (26″)'),
                  VbSearchableSelectOption(
                    value: 630,
                    label: '630 (27″)',
                    onlyWhenSearched: true,
                  ),
                ],
                onChanged: chosen.add,
                sheetTitle: 'Llanta',
                label: 'Llanta',
                // Lo que sólo aparece al buscar necesita la búsqueda.
                showSearch: false,
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.bySemanticsLabel('Llanta').last);
      await tester.pumpAndSettle();
      expect(find.text('622 (29″/700c)'), findsOneWidget);
      expect(find.text('630 (27″)'), findsNothing);

      await tester.enterText(find.byType(TextField), '27');
      await tester.pumpAndSettle();
      expect(find.text('630 (27″)'), findsOneWidget);
      await tester.tap(find.text('630 (27″)'));
      await tester.pumpAndSettle();
      expect(chosen, [630]);
    });
  }
}
