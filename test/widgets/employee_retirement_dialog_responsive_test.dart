import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/hr/widgets/employee_retirement_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final size in const [Size(390, 844), Size(1440, 900)]) {
    testWidgets(
      'retirement consequence confirmation fits ${size.width.toInt()} px',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        bool? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: FilledButton(
                    onPressed: () async {
                      result = await showEmployeeRetirementDialog(
                        context,
                        workerName:
                            'Trabajadora con un nombre deliberadamente largo',
                      );
                    },
                    child: const Text('Abrir'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Abrir'));
        await tester.pumpAndSettle();

        expect(find.text('Desvincular trabajador'), findsOneWidget);
        expect(find.text('Cancelar'), findsOneWidget);
        expect(find.text('Desvincular'), findsOneWidget);
        expect(find.textContaining('historial se conservarán'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(result, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
