import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/services/service_wizard_service.dart';
import 'package:vinabike_erp/modules/bikeshop/widgets/service_wizard_dialog.dart';

ServiceProfileQuestion _question(
  String key,
  String label,
  List<String> values, {
  bool required = false,
  int order = 0,
}) =>
    ServiceProfileQuestion(
      id: key,
      key: key,
      label: label,
      questionType: values.isEmpty ? 'text' : 'single_select',
      isRequired: required,
      isAdvanced: false,
      options: [
        for (final value in values)
          ServiceQuestionOption(value: value, label: value.toUpperCase()),
      ],
      sortOrder: order,
    );

const _layers = {
  'which_wheel': ServiceConfigurationLayer.target,
  'valve_type': ServiceConfigurationLayer.bike,
  'hole_count': ServiceConfigurationLayer.bike,
  'tire_condition': ServiceConfigurationLayer.diagnosis,
  'lacing_pattern': ServiceConfigurationLayer.service,
};

void main() {
  // Paso G3 (2026-09-27): «Configurar» bajo la línea agrupa cada pregunta por
  // su destino, muestra lo que la ficha ya confirma y aplica sin diálogo.
  testWidgets('el panel agrupa por destino y aplica sin cerrar una ruta',
      (tester) async {
    tester.view.physicalSize = const Size(1800, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final profile = ServiceWizardProfile(
      id: 'wheels',
      name: 'Enrayado + Centrado',
      serviceFamily: 'wheels',
      questions: [
        _question('which_wheel', '¿Qué rueda?', ['front', 'rear'],
            required: true, order: 1),
        _question('valve_type', 'Válvula', ['presta', 'schrader'], order: 2),
        _question('hole_count', 'Perforaciones', ['28', '32'], order: 3),
        _question('tire_condition', 'Neumático', ['ok', 'worn'], order: 4),
        _question('lacing_pattern', 'Patrón de armado', ['2x', '3x'], order: 5),
      ],
    );

    ServiceWizardResult? applied;
    Map<String, dynamic>? draft;
    var cancelled = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ServiceConfigurationEditor(
            productName: 'Enrayado + Centrado',
            profile: profile,
            initialAnswers: const {'valve_type': 'presta'},
            hiddenQuestionKeys: const {'valve_type'},
            presentation: ServiceConfigurationPresentation.inline,
            layerOf: (key) => _layers[key] ?? ServiceConfigurationLayer.service,
            layerCopy: const {
              ServiceConfigurationLayer.bike:
                  ServiceConfigurationLayerCopy('Ficha de la Phoenix 04D'),
            },
            onConfirm: (result) => applied = result,
            onCancel: () => cancelled = true,
            onDraftChanged: (value) => draft = value,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Aplica a *'), findsOneWidget,
        reason: 'la rueda de la línea no es una pregunta más');
    expect(find.text('¿Qué rueda?'), findsNothing);
    expect(find.text('Ficha de la Phoenix 04D'), findsOneWidget);
    expect(find.text('Diagnóstico'), findsOneWidget);
    expect(find.text('De este servicio'), findsOneWidget);

    expect(find.text('PRESTA'), findsOneWidget,
        reason: 'lo que la ficha confirma se ve, aunque no se pregunte');
    expect(find.text('confirmado en la ficha'), findsOneWidget);

    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(top('Aplica a *'), lessThan(top('Ficha de la Phoenix 04D')));
    expect(top('Perforaciones'), lessThan(top('Diagnóstico')));
    expect(top('Neumático'), lessThan(top('De este servicio')));
    expect(top('De este servicio'), lessThan(top('Patrón de armado')));

    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(applied, isNull, reason: 'falta elegir la rueda');
    expect(find.text('Elige a qué rueda aplica.'), findsOneWidget);

    expect(draft, isNull, reason: 'abrir el panel no es un cambio');
    await tester.tap(find.text('REAR'));
    await tester.pumpAndSettle();
    expect(draft?['which_wheel'], 'rear',
        reason: 'el formulario guarda lo no aplicado para no perderlo');
    await tester.tap(find.byKey(const ValueKey('service_configuration_apply')));
    await tester.pumpAndSettle();
    expect(applied?.answers['which_wheel'], 'rear');
    expect(applied?.answers['valve_type'], 'presta',
        reason: 'lo confirmado viaja aunque no se haya preguntado');

    await tester
        .tap(find.byKey(const ValueKey('service_configuration_cancel')));
    expect(cancelled, isTrue);
  });

  testWidgets('Sí / No se eligen con teclado y dicen cuál está elegido',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ServiceConfigurationEditor(
          productName: 'Purga de frenos',
          profile: const ServiceWizardProfile(
            id: 'brake',
            name: 'Purga de frenos',
            serviceFamily: 'brake',
            questions: [
              ServiceProfileQuestion(
                id: 'pad_contaminated',
                key: 'pad_contaminated',
                label: '¿Pastillas contaminadas?',
                questionType: 'boolean',
                isRequired: false,
                isAdvanced: false,
                options: [],
                sortOrder: 1,
              ),
            ],
          ),
          initialAnswers: const {'pad_contaminated': true},
          presentation: ServiceConfigurationPresentation.inline,
          onConfirm: (_) {},
          onCancel: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ChoiceChip), findsNWidgets(2));
    expect(
      tester.getSemantics(find.widgetWithText(ChoiceChip, 'Sí')),
      matchesSemantics(
        isSelected: true,
        hasSelectedState: true,
        isButton: true,
        hasTapAction: true,
        hasFocusAction: true,
        isFocusable: true,
        hasEnabledState: true,
        isEnabled: true,
        label: 'Sí',
      ),
    );
    semantics.dispose();
  });

  testWidgets('una respuesta vieja que ya no es opción se pregunta de nuevo',
      (tester) async {
    // Antes del paso F.2 el fluido se guardaba `dot`, que no dice si es DOT 4
    // o DOT 5.1 y ya no es opción del desplegable.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ServiceConfigurationEditor(
            productName: 'Sangrado',
            profile: ServiceWizardProfile(
              id: 'bleed',
              name: 'Sangrado',
              serviceFamily: 'brake',
              questions: [
                _question('fluid_type', 'Tipo de fluido',
                    ['aceite_mineral', 'dot_4', 'dot_5_1'],
                    order: 1),
              ],
            ),
            initialAnswers: const {'fluid_type': 'dot'},
            presentation: ServiceConfigurationPresentation.inline,
            layerOf: (_) => ServiceConfigurationLayer.bike,
            onConfirm: (_) {},
            onCancel: () {},
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('Selecciona una opción'), findsOneWidget);
  });
}
