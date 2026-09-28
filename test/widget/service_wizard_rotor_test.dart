import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/services/service_wizard_service.dart';
import 'package:vinabike_erp/modules/bikeshop/widgets/service_wizard_dialog.dart';

ServiceProfileQuestion _select(
        String key, String label, List<String> values, int order) =>
    ServiceProfileQuestion(
      id: key,
      key: key,
      label: label,
      questionType: 'single_select',
      isRequired: false,
      isAdvanced: false,
      options: [
        for (final value in values)
          ServiceQuestionOption(value: value, label: value),
      ],
      sortOrder: order,
    );

const _profile = ServiceWizardProfile(
  id: 'brake',
  name: 'Centrado de Rotor',
  serviceFamily: 'brakes',
  questions: [],
);

void main() {
  // Revisión C–F (2026-09-27): con la ficha sin tipo de freno, el rotor se
  // ocultaba siempre, incluso en «Centrado de Rotor». Ahora decide la
  // respuesta del tipo de freno en el mismo asistente.
  testWidgets(
      'el rotor se pregunta salvo que el freno respondido sea de llanta',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final profile = ServiceWizardProfile(
      id: _profile.id,
      name: _profile.name,
      serviceFamily: _profile.serviceFamily,
      questions: [
        _select('brake_type', 'Tipo de freno',
            ['hydraulic_disc', 'mechanical_disc', 'v_brake', 'cantilever'], 1),
        _select('rotor_size', 'Tamaño de rotor', ['140', '160', '180'], 2),
      ],
    );

    Future<ServiceWizardResult?> open(Map<String, dynamic> answers) async {
      ServiceWizardResult? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showServiceWizardDialog(
                  context,
                  productName: 'Centrado de Rotor',
                  productIsService: true,
                  profile: profile,
                  initialAnswers: answers,
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('abrir'));
      await tester.pumpAndSettle();
      final rotorVisible = find.text('Tamaño de rotor').evaluate().isNotEmpty;
      await tester.tap(find.text('Actualizar servicio'));
      await tester.pumpAndSettle();
      expect(rotorVisible, answers['brake_type'] == null,
          reason: 'sin tipo de freno respondido el rotor queda a la vista; '
              'con freno de llanta no se pregunta');
      return result;
    }

    final unknownBrake = await open({'rotor_size': '160'});
    expect(unknownBrake?.answers['rotor_size'], '160');

    final rimBrake = await open({'brake_type': 'v_brake', 'rotor_size': '160'});
    expect(rimBrake?.answers['brake_type'], 'v_brake');
    expect(rimBrake?.answers.containsKey('rotor_size'), isFalse,
        reason: 'un freno de llanta no deja un rotor que suba a la ficha');
  });
}
