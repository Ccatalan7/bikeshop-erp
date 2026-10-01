import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/bikeshop/services/job_completion_blocked.dart';
import 'package:vinabike_erp/modules/bikeshop/widgets/job_completion_blocked_dialog.dart';

void main() {
  test('server details identify every line and the next correction', () {
    const serverError = PostgrestException(
      message: 'No se cerró el trabajo',
      code: '23514',
      hint: 'job_completion_blocked',
      details: '{"problems":['
          '{"item_name":"Llanta FOSS 29", "key":"rearSpokeHoles", '
          '"value":32, "reason":"line_without_bike"},'
          '{"item_name":"Neumático Voltage", "key":"rearWheelBsdMm", '
          '"value":584, "reason":"incompatible", '
          '"requires_key":"rearRimBsdMm", "requires_value":"622", '
          '"requires_source":"job_rim"}]}',
    );

    final blocked = jobCompletionBlockFrom(serverError)!;
    expect(blocked.problems, hasLength(2));
    expect(blocked.problems.first, contains('Llanta FOSS 29'));
    expect(blocked.problems.first, contains('Asígnala a su bici'));
    expect(blocked.problems.last, contains('Neumático Voltage'));
    expect(blocked.problems.last, contains('la llanta que instala el trabajo'));
    expect(blocked.toString(), contains('sigue abierto'));
  });

  test('only the exact semantic error is treated as a blocked completion', () {
    expect(
      jobCompletionBlockFrom(const PostgrestException(
        message: 'lock',
        code: '55P03',
        hint: 'job_completion_retry',
      )),
      isNull,
    );
    expect(
      jobCompletionBlockFrom(const PostgrestException(
        message: 'other check',
        code: '23514',
      )),
      isNull,
    );
    expect(
      jobCompletionBlockFrom(const PostgrestException(
        message: 'No se cerró',
        code: '23514',
        hint: 'job_completion_blocked',
        details: 'bad response',
      ))!
          .problems
          .single,
      contains('Revisa la línea marcada'),
    );
  });

  testWidgets('phone dialog keeps corrections readable and opens their editor',
      (tester) async {
    var reviewRequests = 0;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showJobCompletionBlocked(
              context,
              const JobCompletionBlockedException([
                '«Llanta FOSS 29» no dice de qué bicicleta es. Asígnala a su bici.',
                '«Neumático Voltage» no calza con la llanta de esta rueda. Corrige la medida.',
              ]),
              jobLabel: 'Trabajo 24',
              onReviewLines: () => reviewRequests++,
            ),
            child: const Text('Finalizar'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Finalizar'));
    await tester.pumpAndSettle();

    expect(find.text('Trabajo 24 sin cerrar'), findsOneWidget);
    expect(find.textContaining('El estado y la ficha no cambiaron'),
        findsOneWidget);
    expect(find.textContaining('Llanta FOSS 29'), findsOneWidget);
    expect(find.textContaining('Neumático Voltage'), findsOneWidget);
    await tester.tap(find.text('Cerrar'));
    await tester.pumpAndSettle();
    expect(reviewRequests, 0);

    await tester.tap(find.text('Finalizar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revisar líneas'));
    await tester.pumpAndSettle();
    expect(reviewRequests, 1);
    expect(find.text('Finalizar'), findsOneWidget);
  });

  testWidgets('compact phone can reach the last of many blocked lines',
      (tester) async {
    var reviewRequests = 0;
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(1.3),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showJobCompletionBlocked(
              context,
              JobCompletionBlockedException([
                for (var line = 1; line <= 12; line++)
                  '«Pieza $line» no calza con la bicicleta; revisa la medida.',
              ]),
              onReviewLines: () => reviewRequests++,
            ),
            child: const Text('Finalizar'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Finalizar'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.textContaining('Pieza 12'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pieza 12'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Revisar líneas'));
    await tester.pumpAndSettle();
    expect(reviewRequests, 1);
  });
}
