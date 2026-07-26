import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/widgets/client_logbook_responsive_frame.dart';

void main() {
  Future<void> pumpFrame(
    WidgetTester tester, {
    required double width,
    double height = 824,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ClientLogbookResponsiveFrame(
            desktopIdentity: ColoredBox(
              key: ValueKey('desktop-identity'),
              color: Colors.red,
            ),
            compactIdentity: SizedBox(
              key: ValueKey('compact-identity'),
              height: 64,
            ),
            content: ColoredBox(
              key: ValueKey('logbook-content'),
              color: Colors.blue,
            ),
          ),
        ),
      ),
    );
  }

  for (final width in [384.0, 599.0, 600.0, 899.0]) {
    testWidgets(
      'client logbook gives the workspace full width at ${width.toInt()}',
      (tester) async {
        await pumpFrame(tester, width: width);

        expect(
          find.byKey(const ValueKey('client-logbook-compact-frame')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('compact-identity')), findsOneWidget);
        expect(find.byKey(const ValueKey('desktop-identity')), findsNothing);

        final content = tester.getRect(
          find.byKey(const ValueKey('logbook-content')),
        );
        expect(content.left, 0);
        expect(content.width, width);
        expect(content.top, 64);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final width in [900.0, 1440.0]) {
    testWidgets(
      'client logbook preserves the desktop identity rail at ${width.toInt()}',
      (tester) async {
        await pumpFrame(tester, width: width, height: 900);

        expect(
          find.byKey(const ValueKey('client-logbook-desktop-frame')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('desktop-identity')), findsOneWidget);
        expect(find.byKey(const ValueKey('compact-identity')), findsNothing);

        final identity = tester.getRect(
          find.byKey(const ValueKey('desktop-identity')),
        );
        final content = tester.getRect(
          find.byKey(const ValueKey('logbook-content')),
        );
        expect(identity.width, 256);
        expect(content.left, 257);
        expect(content.width, width - 257);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
