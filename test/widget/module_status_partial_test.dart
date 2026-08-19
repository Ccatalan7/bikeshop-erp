import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/pages/intelligent_purchasing_surfaces.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/themes/vinabike_theme_roles.dart';

/// El estado que anuncia la cabecera del módulo, con su punto semántico.
///
/// **La mentira que corrige.** El contrato nombra tres estados —«Analizando»,
/// «Listo» y «Resultados parciales» (NOTES §36-37)— y el frame 08 muestra el
/// tercero **con punto ámbar** justo cuando hay una precisión pendiente
/// (§132). La app decía «Listo» con la pregunta abierta en pantalla: afirmaba
/// que el análisis estaba completo mientras el propio módulo pedía un dato
/// para poder comparar. Y el punto era siempre del mismo color, así que no
/// aportaba nada.

Future<void> pumpBand(
  WidgetTester tester, {
  required String statusLabel,
  required bool statusPartial,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: PurchaseProcessBand(
          active: PurchaseStep.providers,
          meta: const {PurchaseStep.providers: '6 opciones'},
          enabled: const {PurchaseStep.need, PurchaseStep.providers},
          onGo: (_) {},
          compact: false,
          statusLabel: statusLabel,
          statusPartial: statusPartial,
        ),
      ),
    ),
  );
  await tester.pump();
}

/// El punto de estado.
///
/// La banda dibuja cinco círculos: éste y los cuatro badges numerados de paso.
/// Se distingue por su tamaño —7 frente a los 20 del badge— y no por su orden,
/// que cambiaría si algún día se reordena la cabecera.
Color dotColour(WidgetTester tester) {
  final dots = tester
      .widgetList<Container>(find.byType(Container))
      .where((c) => c.constraints?.maxWidth == 7)
      .map((c) => c.decoration)
      .whereType<BoxDecoration>()
      .where((d) => d.shape == BoxShape.circle && d.color != null)
      .toList();
  expect(dots, hasLength(1), reason: 'la banda dibuja un solo punto de estado');
  return dots.single.color!;
}

void main() {
  testWidgets('el estado parcial se dice y se tiñe', (tester) async {
    await pumpBand(
      tester,
      statusLabel: 'Resultados parciales',
      statusPartial: true,
    );

    expect(find.text('Resultados parciales'), findsOneWidget);

    final context = tester.element(find.byType(PurchaseProcessBand));
    final roles = VinabikeThemeRoles.of(context);
    expect(
      dotColour(tester),
      roles.warning.accent,
      reason: 'el contrato pide punto ámbar, no el acento de siempre',
    );
  });

  testWidgets('cerrado, el punto vuelve al acento neutro', (tester) async {
    await pumpBand(tester, statusLabel: 'Listo', statusPartial: false);

    final context = tester.element(find.byType(PurchaseProcessBand));
    final roles = VinabikeThemeRoles.of(context);
    expect(find.text('Listo'), findsOneWidget);
    expect(dotColour(tester), isNot(roles.warning.accent));
  });
}
