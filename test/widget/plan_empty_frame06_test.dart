import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/purchases/pages/intelligent_purchasing_decision_surfaces.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// Frame 06 — el plan vacío, que es el único frame que cabe entero.
///
/// **El hueco.** El contrato abre ese frame con «"Plan borrador" + cápsula
/// pequeña "vacío" al lado» (NOTES §107-108) y el estado vacío no tenía título
/// propio: el paso 4 no decía qué era hasta que tenía líneas.
///
/// **Y lo que el contrato prohíbe acá:** «Sin "Volver a comparar" ni "Registrar
/// compra local" **en la barra superior**». La segunda sí existe, pero abajo,
/// en la fila de acciones junto a «Elegir candidato». Confundir las dos
/// posiciones es el error fácil, así que se afirma la de arriba por su clave.

Future<void> pumpEmpty(WidgetTester tester, {bool compact = false}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: SizedBox(
          width: compact ? 390 : 1100,
          child: SingleChildScrollView(
            child: PlanEmptyInline(
              compact: compact,
              onChooseCandidate: () {},
              onRegisterLocalPurchase: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('el vacío se presenta con su título y su cápsula',
      (tester) async {
    await pumpEmpty(tester);

    expect(find.text('Plan borrador'), findsOneWidget);
    expect(find.text('vacío'), findsOneWidget);
    expect(find.text('Todavía no hay productos elegidos'), findsOneWidget);
  });

  testWidgets('la barra superior del plan no aparece en el vacío',
      (tester) async {
    await pumpEmpty(tester);

    // Las dos acciones de la cabecera con líneas tienen sus propias claves:
    // si alguien monta `PlanDraftHeader` sobre el vacío, esto se pone rojo.
    expect(find.byKey(const ValueKey('plan-back-to-compare')), findsNothing);
    expect(
      find.byKey(const ValueKey('plan-register-local-purchase')),
      findsNothing,
    );
    // La de la fila de acciones sí está, que es otra cosa y otra posición.
    expect(
      find.byKey(const ValueKey('register-local-purchase')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('plan-empty-choose-candidate')),
      findsOneWidget,
    );
  });

  testWidgets('en compacto conserva título y cápsula', (tester) async {
    await pumpEmpty(tester, compact: true);

    expect(find.text('Plan borrador'), findsOneWidget);
    expect(find.text('vacío'), findsOneWidget);
    // La fila de cabeceras es de escritorio: en compacto no se dibuja.
    expect(find.text('Producto'), findsNothing);
  });
}
