import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/services/spec_engine_service.dart';
import 'package:vinabike_erp/modules/purchases/models/intelligent_purchasing_models.dart';
import 'package:vinabike_erp/modules/purchases/widgets/purchase_visual_language.dart';
import 'package:vinabike_erp/modules/purchases/widgets/supply_need_refinement_editor.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// **Un criterio que no se ve no deja de existir — tampoco cuando lo esconde
/// una regla de visibilidad.**
///
/// En producción, «Motor de centro sellado con eje cuadrado» abría `Criterios`
/// mostrando tres campos, con `Guardar criterios` **habilitado sin tocar nada** y
/// la consecuencia en pantalla, como si el operador hubiera cambiado algo. La
/// causa: el formulario recolecta sólo los campos visibles, pero declaraba
/// expresable **todo** el template; el predicado vigente de un campo oculto no
/// se recolectaba ni se arrastraba, y el borrador quedaba distinto del guardado.

SpecTemplateField _field(
  String key,
  String label, {
  List<String> options = const <String>[],
  String dataType = 'single_select',
  List<Map<String, dynamic>> visibility = const <Map<String, dynamic>>[],
}) =>
    SpecTemplateField(
      specDefinitionId: 'def-$key',
      sectionKey: 'general',
      sortOrder: 1,
      isRequired: false,
      visibilityRules: visibility,
      definition: SpecDefinition(
        id: 'def-$key',
        key: key,
        label: label,
        dataType: dataType,
        options: options,
        sortOrder: 1,
      ),
    );

/// Ficha del motor de centro: `spindle_length_mm` sólo se ofrece cuando la
/// construcción es «Cubetas y canastillo». Con `Rodamiento sellado` está oculto.
SpecTemplate _motorTemplate() => SpecTemplate(
      id: 'tpl-bb',
      key: 'bottom_bracket',
      name: 'Motor de centro',
      technicalFamily: 'bottom_bracket',
      fields: <SpecTemplateField>[
        _field('bb_shell_standard', 'Caja de motor',
            options: const <String>['BSA', 'Italiano']),
        _field('bb_construction', 'Construcción', options: const <String>[
          'Rodamiento sellado',
          'Cubetas y canastillo'
        ]),
        _field('spindle_length_mm', 'Largo del eje', options: const <String>[
          '113',
          '118'
        ], visibility: const <Map<String, dynamic>>[
          <String, dynamic>{
            'field': 'bb_construction',
            'operator': 'eq',
            'value': 'Cubetas y canastillo',
          },
        ]),
        _field('includes_spindle', 'Incluye eje', dataType: 'boolean'),
      ],
    );

/// La ficha vigente trae los dos: uno visible y uno que la regla esconde.
const _criteria = SupplyNeedCriteria(
  predicates: <SupplyNeedPredicate>[
    SupplyNeedPredicate(
      field: 'bb_construction',
      operator: 'eq',
      values: <Object>['Rodamiento sellado'],
    ),
    SupplyNeedPredicate(
      field: 'spindle_length_mm',
      operator: 'eq',
      values: <Object>['113'],
    ),
  ],
  categoryId: 'cat-bb',
  categoryPath: 'Transmisión / Motor',
  revisionNo: 3,
  technicalFamily: 'bottom_bracket',
);

List<SupplyNeedPredicate>? _guardado;
int _previewCalls = 0;

Future<void> _pump(WidgetTester tester) async {
  _guardado = null;
  _previewCalls = 0;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1400, 1000);
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
            template: _motorTemplate(),
            title: 'Criterios de Motor de centro',
            categoryLabel: 'motores',
            criteria: _criteria,
            busy: false,
            onSave: (predicates) => _guardado = predicates,
            onCancel: () {},
            previewFor: (predicates) {
              _previewCalls += 1;
              return const SupplyNeedEditPreview(
                reviewed: 9,
                confirmed: 2,
                unverified: 0,
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('abrir sin tocar nada no habilita Guardar ni previsualiza',
      (tester) async {
    await _pump(tester);

    // El campo oculto no se dibuja: la regla de la ficha manda.
    expect(find.text('Largo del eje'), findsNothing);
    expect(find.text('Construcción'), findsOneWidget);

    // Y aun así, nada cambió.
    expect(
      tester
          .widget<PurchasePrimaryButton>(
            find.byKey(const ValueKey('need-criteria-save')),
          )
          .onPressed,
      isNull,
      reason: 'Guardar sigue deshabilitado si el operador no tocó nada',
    );
    expect(
        find.byKey(const ValueKey('need-criteria-consequence')), findsNothing);
    expect(
        find.byKey(const ValueKey('need-criteria-preview-rows')), findsNothing);
    expect(_previewCalls, 0);
  });

  testWidgets('y al guardar un cambio, el criterio oculto viaja intacto',
      (tester) async {
    await _pump(tester);

    // Se cambia SÓLO la caja de motor.
    await tester.tap(find.text('Sin especificar').first);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('BSA').last);
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const ValueKey('need-criteria-save')));
    await tester.pump();

    final porCampo = <String, Object>{
      for (final predicate in _guardado ?? const <SupplyNeedPredicate>[])
        predicate.field: predicate.values.single,
    };
    expect(porCampo['bb_shell_standard'], 'BSA');
    expect(porCampo['bb_construction'], 'Rodamiento sellado');
    expect(
      porCampo['spindle_length_mm'],
      '113',
      reason: 'el criterio oculto no lo puede borrar un cambio en otro campo',
    );
  });

  testWidgets('si otro valor lo revela, aparece con su valor vigente',
      (tester) async {
    await _pump(tester);

    // Cambiar la construcción a «Cubetas y canastillo» destapa el largo de eje.
    await tester.tap(find.text('Rodamiento sellado').last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Cubetas y canastillo').last);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Largo del eje'), findsOneWidget);
    // Y aparece con lo que la ficha ya tenía, no vacío: sembrarlo desde cero
    // habría borrado el criterio al primer guardado.
    expect(find.text('113'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('need-criteria-save')));
    await tester.pump();
    final porCampo = <String, Object>{
      for (final predicate in _guardado ?? const <SupplyNeedPredicate>[])
        predicate.field: predicate.values.single,
    };
    expect(porCampo['bb_construction'], 'Cubetas y canastillo');
    expect(porCampo['spindle_length_mm'], '113');
  });

  testWidgets('y si otro valor lo esconde, se conserva en vez de borrarse',
      (tester) async {
    await _pump(tester);

    // Destapar y volver a tapar: el criterio tiene que sobrevivir al viaje.
    await tester.tap(find.text('Rodamiento sellado').last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Cubetas y canastillo').last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Largo del eje'), findsOneWidget);

    await tester.tap(find.text('Cubetas y canastillo').last);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Rodamiento sellado').last);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Largo del eje'), findsNothing);

    // Nada cambió respecto de lo guardado, así que Guardar vuelve a apagarse.
    expect(
      tester
          .widget<PurchasePrimaryButton>(
            find.byKey(const ValueKey('need-criteria-save')),
          )
          .onPressed,
      isNull,
    );
  });
}
