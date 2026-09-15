import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/messaging/models/message_delivery_state.dart';
import 'package:vinabike_erp/modules/messaging/widgets/message_delivery_indicator.dart';

void main() {
  for (final width in [384.0, 599.0, 600.0, 899.0, 900.0, 1440.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('queue check is honest and accessible at $width $brightness',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 824));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: const Scaffold(
              body: Center(
                  child: MessageDeliveryIndicator(
            state: MessageDeliveryState(
                stage: MessageDeliveryStage.queued, providerLabel: 'WhatsApp'),
          ))),
        ));
        expect(find.byIcon(Icons.done_rounded), findsOneWidget);
        expect(find.byIcon(Icons.done_all_rounded), findsNothing);
        expect(
            find.bySemanticsLabel(
                'Recibido por Viñabike; pendiente de envío a WhatsApp'),
            findsOneWidget);
        await tester.longPress(find.byType(MessageDeliveryIndicator));
        await tester.pumpAndSettle();
        expect(
            find.text('Recibido por Viñabike; pendiente de envío a WhatsApp'),
            findsOneWidget);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    }
  }
}
