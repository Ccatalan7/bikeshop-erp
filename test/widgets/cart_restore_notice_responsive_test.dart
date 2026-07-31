import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/widgets/cart_restore_notice.dart';

void main() {
  for (final width in [320.0, 375.0, 599.0]) {
    testWidgets(
      'restore notice keeps a 48px action without overflow at ${width.toInt()}',
      (tester) async {
        await tester.binding.setSurfaceSize(Size(width, 500));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final dropped = ValueNotifier<int>(1);
        addTearDown(dropped.dispose);

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(useMaterial3: true),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: ValueListenableBuilder<int>(
                  valueListenable: dropped,
                  builder: (context, value, _) {
                    if (value == 0) return const SizedBox.shrink();
                    return CartRestoreNotice(
                      dropped: value,
                      onAcknowledged: () => dropped.value = 0,
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        final button = find.ancestor(
          of: find.text('Entendido'),
          matching: find.byType(TextButton),
        );
        expect(button, findsOneWidget);
        final size = tester.getSize(button);
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
        expect(find.textContaining('Ajustamos 1 producto'), findsOneWidget);

        await tester.tap(button);
        await tester.pump();

        expect(find.text('Entendido'), findsNothing);
        expect(dropped.value, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
