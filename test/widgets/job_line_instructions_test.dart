import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/widgets/job_line_instructions.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

// La instrucción de una línea (20260929040000): la descripción del catálogo se
// lee tal como está escrita, sin casillas. La de «Mantención Maza» es la del
// catálogo real: sus dos viñetas son advertencias al cliente y sus pasos van
// sin marca, con finales de línea de Windows.
const _maza = '-SIN CONTAR POSIBLE CAMBIO DE EJE\r\n'
    '-VIÑABIKE SE GUARDA EL DERECHO A DIAGNOSTICAR UN POSIBLE CAMBIO DE MAZA\r\n'
    'Desarme\r\nLimpieza\r\nEngrasado\r\nInstalación\r\n\r\n'
    'Si es necesario: Cambio de Rodamientos';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: brightness,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('los renglones se leen tal como están, sin los vacíos', () {
    expect(JobLineInstructions.linesOf(_maza), [
      '-SIN CONTAR POSIBLE CAMBIO DE EJE',
      '-VIÑABIKE SE GUARDA EL DERECHO A DIAGNOSTICAR UN POSIBLE CAMBIO DE MAZA',
      'Desarme',
      'Limpieza',
      'Engrasado',
      'Instalación',
      'Si es necesario: Cambio de Rodamientos',
    ]);
    expect(const JobLineInstructions().isEmpty, isTrue);
    expect(const JobLineInstructions(notes: '  ').isEmpty, isTrue);
    expect(const JobLineInstructions(notes: 'Cliente pide urgencia').isEmpty,
        isFalse);
  });

  testWidgets(
      'qué incluye se lee, sin casillas: advertencias y pasos como están '
      'escritos', (tester) async {
    await _pump(
      tester,
      const JobLineInstructions(
        catalogDescription: _maza,
        notes: 'El cliente dice que suena al pedalear',
      ),
    );

    expect(find.text('Qué incluye'), findsOneWidget);
    expect(find.text('Del catálogo, como está hoy · lo que ve el cliente'), findsOneWidget);
    expect(find.text('-SIN CONTAR POSIBLE CAMBIO DE EJE'), findsOneWidget);
    expect(find.text('Desarme'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);

    // Siete renglones: se ven cuatro y el resto se abre.
    expect(find.text('Engrasado'), findsNothing);
    await tester.tap(find.text('Ver todo (7 renglones)'));
    await tester.pumpAndSettle();
    expect(find.text('Engrasado'), findsOneWidget);
    expect(find.text('Si es necesario: Cambio de Rodamientos'), findsOneWidget);
    expect(find.text('Ver menos'), findsOneWidget);

    expect(find.text('Indicaciones de este trabajo'), findsOneWidget);
    expect(find.text('El cliente dice que suena al pedalear'), findsOneWidget);
  });

  testWidgets(
      'a ancho de teléfono, los renglones largos se parten sin '
      'desbordar', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(
      tester,
      const JobLineInstructions(
        catalogDescription: _maza,
        notes: 'REQUIERE MANTENCION EN MAZA TRASERA POR SOLTURA, REVISAR EN '
            'EL MOMENTO ESTADO DE LA MAZA',
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Ver todo (7 renglones)'), findsOneWidget);
    expect(
      tester.getSize(find.byType(JobLineInstructions)).width,
      lessThanOrEqualTo(390 - 32),
    );
  });

  testWidgets('en oscuro, sólo indicaciones', (tester) async {
    await _pump(
      tester,
      const JobLineInstructions(notes: 'Revisar también la rueda trasera'),
      brightness: Brightness.dark,
    );
    expect(find.text('Qué incluye'), findsNothing);
    expect(find.text('Indicaciones de este trabajo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
