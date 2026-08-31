import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vinabike_erp/modules/purchases/widgets/supplier_concentration_table.dart';
import 'package:vinabike_erp/shared/services/supplier_need_portal_search.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// **Lo que la ficha no puede preguntar, dicho en la fila.**
///
/// «Falta confirmar» no decía qué falta. Con las exigencias fuera de plantilla
/// —«sellados», «a ambos lados»— el operador tenía que abrir cada fila y leerla
/// entera. Acá se separa por **cómo se sabe**, que es lo que permite comparar.
Future<void> _pump(
  WidgetTester tester,
  List<SupplyRequirementFinding> findings,
) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.resolve(
      preset: AppearancePresets.all.first,
      brightness: Brightness.light,
    ),
    home: Scaffold(
      body: SupplierRequirementFindings(findings: findings),
    ),
  ));
  await tester.pump();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('lo dicho por el proveedor y lo leído por la IA no se confunden',
      (tester) async {
    await _pump(tester, const <SupplyRequirementFinding>[
      SupplyRequirementFinding(
        label: 'sellados',
        affirmed: true,
        status: SupplyRequirementStatus.proven,
      ),
      SupplyRequirementFinding(
        label: 'kevlar',
        affirmed: true,
        status: SupplyRequirementStatus.inferred,
        quote: 'COMPUESTO ORGANICO',
      ),
    ]);

    expect(find.textContaining('sellados: lo dice el proveedor'), findsOneWidget);
    expect(find.textContaining('kevlar: leído por IA, sin confirmar'),
        findsOneWidget);
    expect(find.textContaining('kevlar: lo dice el proveedor'), findsNothing,
        reason: 'una lectura de la IA jamás se dibuja como cumplimiento');
  });

  testWidgets('la cita del proveedor se puede LEER, no sólo oír',
      (tester) async {
    await _pump(tester, const <SupplyRequirementFinding>[
      SupplyRequirementFinding(
        label: 'kevlar',
        affirmed: true,
        status: SupplyRequirementStatus.inferred,
        quote: 'COMPUESTO ORGANICO',
      ),
    ]);
    expect(
      find.bySemanticsLabel(
        RegExp('kevlar: leído por IA, sin confirmar. Cita: COMPUESTO ORGANICO'),
      ),
      findsOneWidget,
    );
    // Y en pantalla: el operador que compara con los ojos necesita ver de
    // dónde salió la lectura para poder desmentirla.
    expect(find.text('COMPUESTO ORGANICO'), findsNothing,
        reason: 'plegada hasta que la pidan');
    await tester.tap(
      find.byKey(const ValueKey('portal-requirement-findings-toggle')),
    );
    await tester.pump();
    expect(find.text('kevlar: «COMPUESTO ORGANICO»'), findsOneWidget);
  });

  testWidgets('lo que no consta se puede ver, no sólo contar', (tester) async {
    await _pump(tester, const <SupplyRequirementFinding>[
      SupplyRequirementFinding(
        label: 'sellados',
        affirmed: true,
        status: SupplyRequirementStatus.unknown,
      ),
      SupplyRequirementFinding(
        label: 'tapones',
        affirmed: false,
        status: SupplyRequirementStatus.unknown,
      ),
    ]);
    expect(find.text('no constan 2 exigencias'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('portal-requirement-findings-toggle')),
    );
    await tester.pump();
    expect(find.text('sellados: no consta'), findsOneWidget);
    expect(find.text('sin tapones: no consta'), findsOneWidget,
        reason: 'un número no dice cuáles faltan');
  });

  testWidgets('una frase que ya viene negada no se niega dos veces',
      (tester) async {
    await _pump(tester, const <SupplyRequirementFinding>[
      SupplyRequirementFinding(
        label: 'sin tapones',
        affirmed: false,
        status: SupplyRequirementStatus.proven,
      ),
    ]);
    expect(find.text('sin tapones: lo dice el proveedor'), findsOneWidget);
    expect(find.textContaining('sin sin'), findsNothing);
  });

  testWidgets('una duda se explica y no esconde la fila', (tester) async {
    await _pump(tester, const <SupplyRequirementFinding>[
      SupplyRequirementFinding(
        label: 'sellados',
        affirmed: true,
        status: SupplyRequirementStatus.doubted,
        quote: 'RODAMIENTO 6902',
      ),
    ]);
    expect(find.textContaining('sellados: la IA lo duda'), findsOneWidget);
  });

  testWidgets('la polaridad del pedido se lee en la etiqueta', (tester) async {
    await _pump(tester, const <SupplyRequirementFinding>[
      SupplyRequirementFinding(
        label: 'aletas',
        affirmed: false,
        status: SupplyRequirementStatus.contradicted,
      ),
    ]);
    expect(find.textContaining('sin aletas: el proveedor dice lo contrario'),
        findsOneWidget);
  });

  testWidgets('lo que no consta se cuenta, no se disfraza', (tester) async {
    await _pump(tester, const <SupplyRequirementFinding>[
      SupplyRequirementFinding(
        label: 'sellados',
        affirmed: true,
        status: SupplyRequirementStatus.unknown,
      ),
      SupplyRequirementFinding(
        label: 'kevlar',
        affirmed: true,
        status: SupplyRequirementStatus.unknown,
      ),
    ]);
    expect(find.text('no constan 2 exigencias'), findsOneWidget);
  });
}
