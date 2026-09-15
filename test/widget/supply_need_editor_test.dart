import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/widgets/purchase_visual_language.dart';
import 'package:vinabike_erp/modules/purchases/widgets/supply_need_refinement_editor.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

SpecTemplate _tubeTemplate() => SpecTemplate(
      id: 'tpl-tube',
      key: 'tube',
      name: 'Cámaras',
      technicalFamily: 'tube',
      fields: <SpecTemplateField>[
        SpecTemplateField(
          specDefinitionId: 'def-valve',
          sectionKey: 'general',
          sortOrder: 1,
          isRequired: false,
          visibilityRules: const <Map<String, dynamic>>[],
          definition: const SpecDefinition(
            id: 'def-valve',
            key: 'valve_type',
            label: 'Tipo de válvula',
            dataType: 'select',
            options: <String>['presta', 'schrader'],
            sortOrder: 1,
          ),
        ),
      ],
    );

SpecTemplate _numericTemplate() => SpecTemplate(
      id: 'tpl-wheel',
      key: 'wheel',
      name: 'Ruedas',
      technicalFamily: 'wheel',
      fields: <SpecTemplateField>[
        SpecTemplateField(
          specDefinitionId: 'def-spokes',
          sectionKey: 'general',
          sortOrder: 1,
          isRequired: false,
          visibilityRules: const <Map<String, dynamic>>[],
          definition: const SpecDefinition(
            id: 'def-spokes',
            key: 'spoke_holes',
            label: 'Cantidad de rayos',
            dataType: 'number',
            options: <String>[],
            sortOrder: 1,
          ),
        ),
      ],
    );

SupplyNeedCriteria _criteria({
  bool withCategory = true,
  List<SupplyNeedPredicate>? predicates,
}) =>
    SupplyNeedCriteria(
      predicates: predicates ?? const <SupplyNeedPredicate>[],
      categoryId: withCategory ? 'cat-tubes' : null,
      categoryPath: 'Componentes / Ruedas / Cámaras',
      revisionNo: withCategory ? 3 : null,
      technicalFamily: 'tube',
    );

class _Saved {
  List<SupplyNeedPredicate>? predicates;
  bool cancelled = false;
}

Future<_Saved> _pump(
  WidgetTester tester, {
  SpecTemplate? template,
  bool withCategory = true,
  String? blockedReason,
  SupplyNeedEditPreview? preview,
  List<SupplyNeedPredicate>? predicates,
  Size size = const Size(1280, 900),
}) async {
  final saved = _Saved();
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
        body: SingleChildScrollView(
          child: SupplyNeedRefinementEditor(
            template: template,
            title: 'Criterios de Cámaras aro 700',
            categoryLabel: 'cámaras',
            criteria: _criteria(
              withCategory: withCategory,
              predicates: predicates,
            ),
            busy: false,
            preciseBlockedReason: blockedReason,
            previewFor: (_) => preview,
            onCancel: () => saved.cancelled = true,
            onSave: (value) => saved.predicates = value,
          ),
        ),
      ),
    ),
  );
  return saved;
}

void main() {
  testWidgets('la ficha no mezcla descripción ni cantidad', (tester) async {
    await _pump(tester, template: _tubeTemplate());

    expect(find.text('Criterios de Cámaras aro 700'), findsOneWidget);
    expect(find.text('Ficha técnica: cámaras'), findsOneWidget);
    expect(find.byKey(const ValueKey('need-inline-description')), findsNothing);
    expect(find.byKey(const ValueKey('need-inline-quantity')), findsNothing);
    expect(find.text('Cambiar lo que estoy buscando'), findsNothing);
    expect(find.text('Cantidad necesaria'), findsNothing);
  });

  testWidgets('es una tabla alineada en escritorio', (tester) async {
    await _pump(tester, template: _tubeTemplate());

    final characteristic = find.text('Característica');
    final condition = find.text('Condición');
    final value = find.text('Valor');
    expect(characteristic, findsOneWidget);
    expect(condition, findsOneWidget);
    expect(value, findsOneWidget);
    expect(
        tester.getTopLeft(characteristic).dy, tester.getTopLeft(condition).dy);
    expect(tester.getTopLeft(condition).dy, tester.getTopLeft(value).dy);
    expect(find.text('Tipo de válvula'), findsOneWidget);
  });

  testWidgets('tablet conserva las columnas estables', (tester) async {
    await _pump(
      tester,
      template: _tubeTemplate(),
      size: const Size(834, 900),
    );

    expect(find.text('Característica'), findsOneWidget);
    expect(find.text('Condición'), findsOneWidget);
    expect(find.text('Valor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('teléfono apila un bloque por característica', (tester) async {
    await _pump(
      tester,
      template: _tubeTemplate(),
      size: const Size(390, 844),
    );

    expect(find.text('Característica'), findsNothing);
    expect(find.text('Tipo de válvula'), findsOneWidget);
    expect(find.text('Condición'), findsOneWidget);
    expect(find.text('Valor'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin cambios no permite guardar', (tester) async {
    await _pump(tester, template: _tubeTemplate());

    final button = tester.widget<PurchasePrimaryButton>(
      find.byKey(const ValueKey('need-criteria-save')),
    );
    expect(button.onPressed, isNull);
    expect(
      find.byKey(const ValueKey('need-criteria-consequence')),
      findsNothing,
    );
  });

  testWidgets('sin ninguna confirmada el rótulo no dice que cumplen',
      (tester) async {
    await _pump(
      tester,
      template: _tubeTemplate(),
      preview: const SupplyNeedEditPreview(
        reviewed: 18,
        confirmed: 0,
        unverified: 4,
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('need-refinement-value-valve_type')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('presta').last);
    await tester.pumpAndSettle();

    expect(
      find.text(
        'De 18 revisadas quedarían 4, ninguna confirmada: quedan por '
        'verificar. No se consulta al proveedor otra vez.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('cambiar una spec previsualiza y guarda sólo predicados',
      (tester) async {
    final saved = await _pump(
      tester,
      template: _tubeTemplate(),
      preview: const SupplyNeedEditPreview(
        reviewed: 18,
        confirmed: 3,
        unverified: 5,
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('need-refinement-value-valve_type')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('presta').last);
    await tester.pumpAndSettle();

    // La corrida real: 18 filas leídas, 8 sobrevivientes, 3 con la válvula
    // declarada. El rótulo anterior decía «8 cumplen» y era falso.
    expect(
      find.text(
        'De 18 revisadas quedarían 8: 3 cumplen y 5 quedan por verificar. '
        'No se consulta al proveedor otra vez.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('need-criteria-save')));
    await tester.pump();

    expect(saved.predicates, hasLength(1));
    expect(saved.predicates!.single.field, 'valve_type');
    expect(saved.predicates!.single.values, <Object>['presta']);
  });

  testWidgets('un entero reabierto como decimal no crea un cambio falso',
      (tester) async {
    await _pump(
      tester,
      template: _numericTemplate(),
      predicates: const <SupplyNeedPredicate>[
        SupplyNeedPredicate(
          field: 'spoke_holes',
          operator: 'eq',
          values: <Object>[29],
        ),
      ],
    );

    final button = tester.widget<PurchasePrimaryButton>(
      find.byKey(const ValueKey('need-criteria-save')),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('cambiar la condición conserva el valor recién escrito',
      (tester) async {
    final saved = await _pump(tester, template: _numericTemplate());

    await tester.enterText(
      find.byKey(const ValueKey('need-refinement-value-spoke_holes-0')),
      '31',
    );
    await tester.tap(
      find.byKey(const ValueKey('need-refinement-operator-spoke_holes')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mínimo').last);
    await tester.pumpAndSettle();

    expect(find.text('31'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('need-criteria-save')));
    await tester.pump();

    expect(saved.predicates, hasLength(1));
    expect(saved.predicates!.single.operator, 'gte');
    expect(saved.predicates!.single.values, <Object>[31.0]);
  });

  testWidgets('cancelar no guarda ni arrastra lo escrito', (tester) async {
    final saved = await _pump(tester, template: _tubeTemplate());

    await tester.tap(find.text('Cancelar'));
    await tester.pump();

    expect(saved.predicates, isNull, reason: 'cancelar no puede persistir');
    expect(saved.cancelled, isTrue);
  });

  testWidgets('sin categoría se explica que no hay ficha editable',
      (tester) async {
    await _pump(
      tester,
      withCategory: false,
      blockedReason:
          'Falta identificar la categoría; cambia lo que estás buscando.',
    );

    expect(
      find.text(
        'Falta identificar la categoría; cambia lo que estás buscando.',
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('need-refinement-value-valve_type')),
      findsNothing,
    );
  });
}
