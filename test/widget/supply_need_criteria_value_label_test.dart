import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/widgets/supply_need_refinement_editor.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/vb_short_select.dart';

/// Un bloque con los dos controles que conviven en la misma columna: una lista
/// cerrada y un texto libre. Es donde se ve si el rótulo tiene un dueño o dos.
SpecTemplate _plantilla() => SpecTemplate(
      id: 'tpl-pastillas',
      key: 'brake_pad',
      name: 'Pastillas',
      technicalFamily: 'brake_pad',
      fields: <SpecTemplateField>[
        SpecTemplateField(
          specDefinitionId: 'def-compound',
          sectionKey: 'tecnica',
          sortOrder: 1,
          isRequired: false,
          visibilityRules: const <Map<String, dynamic>>[],
          definition: const SpecDefinition(
            id: 'def-compound',
            key: 'compound_type',
            label: 'Compuesto',
            dataType: 'single_select',
            options: <String>['Metálico', 'Orgánico'],
            sortOrder: 1,
          ),
        ),
        SpecTemplateField(
          specDefinitionId: 'def-shape',
          sectionKey: 'tecnica',
          sortOrder: 2,
          isRequired: false,
          visibilityRules: const <Map<String, dynamic>>[],
          definition: const SpecDefinition(
            id: 'def-shape',
            key: 'pad_shape_code',
            label: 'Código de Forma (Pastilla)',
            dataType: 'text',
            options: <String>[],
            sortOrder: 2,
          ),
        ),
      ],
    );

Future<void> _montar(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SupplyNeedRefinementEditor(
            template: _plantilla(),
            title: 'Criterios de Pastillas BR-MT200',
            categoryLabel: 'pastillas',
            criteria: const SupplyNeedCriteria(
              predicates: <SupplyNeedPredicate>[],
              categoryId: 'cat-pads',
              categoryPath: 'Componentes / Frenos / Pastillas',
              revisionNo: 1,
              technicalFamily: 'brake_pad',
            ),
            busy: false,
            onSave: (_) {},
            onCancel: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // **Un rótulo, un dueño.** En el bloque apilado del teléfono, el select
  // llevaba su «Valor» encima con el rótulo de S-05 y el campo de texto lo
  // llevaba dentro de la caja: dos formas de nombrar lo mismo, una al lado de
  // la otra. Ahora los dos usan `VbShortSelect.labelled`.
  testWidgets('en teléfono el texto libre rotula igual que la lista',
      (tester) async {
    await _montar(tester, const Size(390, 900));

    final rotulos = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .where((texto) => texto == 'Valor')
        .length;
    expect(rotulos, 2,
        reason: 'los dos campos del bloque llevan su rótulo, y el mismo');

    // El del texto libre está por fuera de la caja, como el de la lista.
    final campo = find.byKey(const ValueKey(
      'need-refinement-value-pad_shape_code-0',
    ));
    expect(campo, findsOneWidget);
    expect(tester.widget<TextField>(campo).decoration?.labelText, isNull,
        reason: 'el rótulo dejó de vivir dentro de la decoración del campo');
  });

  testWidgets('apilado y sin desbordes en teléfono', (tester) async {
    await _montar(tester, const Size(390, 900));
    expect(tester.takeException(), isNull);
    // Apilado: la condición queda arriba del valor, no al lado.
    final condicion = tester.getTopLeft(find.byKey(
      const ValueKey('need-refinement-operator-pad_shape_code'),
    ));
    final valor = tester.getTopLeft(find.byKey(
      const ValueKey('need-refinement-value-pad_shape_code-0'),
    ));
    expect(valor.dy, greaterThan(condicion.dy));
    expect(valor.dx, closeTo(condicion.dx, 1));
  });

  for (final ancho in <double>[1455, 834]) {
    testWidgets('la tabla de $ancho conserva una sola altura por columna',
        (tester) async {
      await _montar(tester, Size(ancho, 900));
      expect(tester.takeException(), isNull);

      final libre = tester.getSize(find.byKey(const ValueKey(
        'need-refinement-value-pad_shape_code-0',
      )));
      expect(libre.height, VbShortSelect.fieldHeight,
          reason: 'el campo libre crecía por su cuenta y su fila quedaba más '
              'alta que las vecinas: la tabla dejaba de leerse como filas');

      // Y en ancho el rótulo por campo no aparece: lo dice la cabecera.
      final rotulos = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data ?? '')
          .where((texto) => texto == 'Valor')
          .length;
      expect(rotulos, 2,
          reason: 'la cabecera nombra la columna y el campo libre conserva su '
              'texto de adentro, que en ancho es su única pista');
    });
  }
}
