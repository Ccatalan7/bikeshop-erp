import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/pages/intelligent_purchasing_surfaces.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// La barra de necesidad: resumen de criterios, separador y la CTA «Criterios».
///
/// **Lo que defiende.** El contrato pide «nombre + cantidad+unidad en mono +
/// separador `|` + resumen de criterios» y, a la derecha, «Editar necesidad»
/// más la CTA textual «Criterios» (NOTES §44-47, §214-216). El widget declaraba
/// `onOpenCriteria` y **nadie se lo pasaba**: el botón era código muerto, así
/// que una necesidad interpretada se veía igual que una escrita a mano.
///
/// La CTA sólo aparece cuando hay algo que desplegar: un botón que abre una
/// lista vacía miente, y esa condición es justo la que se rompe sin querer.

Future<void> pumpBar(
  WidgetTester tester, {
  required String criteriaSummary,
  VoidCallback? onOpenCriteria,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: SupplyNeedBar(
          title: 'Neumáticos 27,5',
          quantityLabel: '10 unidades',
          criteriaSummary: criteriaSummary,
          editing: false,
          onEdit: () {},
          onCancel: () {},
          onOpenCriteria: onOpenCriteria,
          editor: const SizedBox.shrink(),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('con criterios: resumen, separador y la CTA', (tester) async {
    var opened = 0;
    await pumpBar(
      tester,
      criteriaSummary: 'ancho: mayor a 2,0 · Económicos pero con buen margen',
      onOpenCriteria: () => opened++,
    );

    expect(find.text('10 unidades'), findsOneWidget);
    expect(
      find.text('ancho: mayor a 2,0 · Económicos pero con buen margen'),
      findsOneWidget,
    );
    // El separador que el contrato nombra, y que no estaba.
    expect(find.text('|'), findsOneWidget);

    final criterios = find.byKey(const ValueKey('open-need-criteria'));
    expect(criterios, findsOneWidget);
    await tester.tap(criterios);
    await tester.pump();
    expect(opened, 1, reason: 'la CTA tiene que llamar a quien la pasó');
  });

  testWidgets('sin criterios no hay CTA ni separador colgando',
      (tester) async {
    await pumpBar(tester, criteriaSummary: 'Solicitud directa');

    // El origen sigue ocupando la ranura cuando no hay criterios: es lo único
    // cierto que queda por decir.
    expect(find.text('Solicitud directa'), findsOneWidget);
    expect(find.byKey(const ValueKey('open-need-criteria')), findsNothing);
  });

  testWidgets('con la ranura vacía no se dibuja separador', (tester) async {
    await pumpBar(tester, criteriaSummary: '');

    expect(find.text('|'), findsNothing);
    expect(find.text('10 unidades'), findsOneWidget);
  });
}
