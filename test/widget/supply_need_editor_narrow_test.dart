import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/widgets/supply_need_refinement_editor.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

SpecTemplate _tubeTemplate() => SpecTemplate(
      id: 'tpl-tube',
      key: 'tube',
      name: 'Cámaras',
      technicalFamily: 'tube',
      fields: <SpecTemplateField>[
        for (final definition in const <List<String>>[
          <String>['wheel_size', 'Tamaño de rueda'],
          <String>['valve_length_mm', 'Largo de válvula'],
          <String>['valve_type', 'Tipo de válvula'],
          <String>['width_in', 'Ancho mínimo'],
          <String>['material', 'Material'],
          <String>['pack_count', 'Unidades por pack'],
          <String>['brand_line', 'Línea'],
        ])
          SpecTemplateField(
            specDefinitionId: 'def-${definition[0]}',
            sectionKey: 'general',
            sortOrder: 1,
            isRequired: false,
            visibilityRules: const <Map<String, dynamic>>[],
            definition: SpecDefinition(
              id: 'def-${definition[0]}',
              key: definition[0],
              label: definition[1],
              dataType: 'single_select',
              options: const <String>['700c', '650b'],
              sortOrder: 1,
            ),
          ),
      ],
    );

Widget _editor() => SupplyNeedRefinementEditor(
      template: _tubeTemplate(),
      title: 'Criterios de Cámaras aro 700',
      categoryLabel: 'cámaras',
      criteria: const SupplyNeedCriteria(
        predicates: <SupplyNeedPredicate>[
          SupplyNeedPredicate(
            field: 'wheel_size',
            operator: 'eq',
            values: <Object>['700c'],
          ),
        ],
        categoryId: 'cat-tubes',
        categoryPath: 'Componentes / Ruedas / Cámaras',
        revisionNo: 3,
        technicalFamily: 'tube',
      ),
      busy: false,
      onSave: (_) {},
      onCancel: () {},
    );

Future<void> _pumpShell(
  WidgetTester tester, {
  Size size = const Size(700, 865),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.dark,
      ),
      home: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 190),
              Expanded(
                child: SingleChildScrollView(
                  key: const ValueKey('need-criteria-editor-scroll'),
                  child: _editor(),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('la ficha larga no desborda a 700x865', (tester) async {
    await _pumpShell(tester);

    expect(tester.takeException(), isNull);
    expect(
      find.byKey(const ValueKey('need-criteria-editor-scroll')),
      findsOneWidget,
    );
    expect(find.text('Característica'), findsOneWidget);
  });

  testWidgets('se llega a las acciones al final de la ficha', (tester) async {
    await _pumpShell(tester);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('need-criteria-save')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Guardar criterios'), findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.byKey(const ValueKey('need-inline-description')), findsNothing);
  });

  testWidgets('en teléfono cada spec es un bloque alcanzable', (tester) async {
    await _pumpShell(tester, size: const Size(390, 844));

    expect(find.text('Característica'), findsNothing);
    expect(find.text('Tamaño de rueda'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('need-criteria-save')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('en escritorio cada spec ocupa una fila de la tabla',
      (tester) async {
    await _pumpShell(tester, size: const Size(1440, 900));

    expect(tester.takeException(), isNull);
    expect(find.text('Característica'), findsOneWidget);
    expect(find.text('Condición'), findsOneWidget);
    expect(find.text('Valor'), findsOneWidget);
  });
}
