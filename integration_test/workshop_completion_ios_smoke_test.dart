import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:vinabike_erp/modules/bikeshop/services/job_completion_blocked.dart';
import 'package:vinabike_erp/modules/bikeshop/widgets/job_completion_blocked_dialog.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('blocked workshop close respects iPhone safe areas',
      (tester) async {
    var reviewRequests = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showJobCompletionBlocked(
                context,
                JobCompletionBlockedException([
                  for (var line = 1; line <= 12; line++)
                    '«Pieza $line» no calza con la bicicleta; revisa la medida.',
                ]),
                jobLabel: 'Trabajo de prueba',
                onReviewLines: () => reviewRequests++,
              ),
              child: const Text('Finalizar'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Finalizar'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(dialog, findsOneWidget);
    final context = tester.element(dialog);
    final media = MediaQuery.of(context);
    final box = tester.renderObject<RenderBox>(dialog);
    final rect = box.localToGlobal(Offset.zero) & box.size;
    expect(media.padding.top, greaterThan(0));
    expect(media.padding.bottom, greaterThan(0));
    expect(rect.top, greaterThanOrEqualTo(media.padding.top));
    expect(rect.bottom,
        lessThanOrEqualTo(media.size.height - media.padding.bottom));

    await tester.ensureVisible(find.textContaining('Pieza 12'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Pieza 12'), findsOneWidget);
    expect(find.text('Revisar líneas'), findsOneWidget);
    expect(await binding.takeScreenshot('workshop-completion-ios'), isNotEmpty);

    await tester.tap(find.text('Revisar líneas'));
    await tester.pumpAndSettle();
    expect(reviewRequests, 1);
  });
}
