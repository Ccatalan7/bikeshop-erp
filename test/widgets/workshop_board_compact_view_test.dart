import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/widgets/workshop_board_compact_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpBoard(
    WidgetTester tester, {
    required double width,
    WorkshopBoardCompactSession? session,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 824));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 824),
            textScaler: const TextScaler.linear(1.3),
          ),
          child: Scaffold(
            body: WorkshopBoardCompactView(
              session: session,
              groups: const [
                WorkshopBoardCompactGroup(
                  id: 'pending',
                  label: 'Pendiente',
                  color: Colors.blue,
                  children: [
                    SizedBox(
                      key: ValueKey('pending-job'),
                      height: 112,
                      child: Text('PG-1'),
                    ),
                  ],
                ),
                WorkshopBoardCompactGroup(
                  id: 'active',
                  label: 'En curso',
                  color: Colors.green,
                  children: [
                    SizedBox(
                      key: ValueKey('active-job'),
                      height: 112,
                      child: Text('PG-2'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [384.0, 599.0, 600.0, 899.0]) {
    testWidgets('uses the full compact width without overflow at $width',
        (tester) async {
      await pumpBoard(tester, width: width);

      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('workshop-board-compact-view')),
            )
            .width,
        width,
      );
      expect(
        tester
            .getSize(
              find.byKey(const ValueKey('workshop-board-status-selector')),
            )
            .height,
        greaterThanOrEqualTo(48),
      );
      expect(find.byKey(const ValueKey('pending-job')), findsOneWidget);
      expect(find.byKey(const ValueKey('active-job')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('changes board status in place instead of horizontal scrolling',
      (tester) async {
    await pumpBoard(tester, width: 384);

    await tester.tap(
      find.byKey(const ValueKey('workshop-board-status-selector')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('En curso').last);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pending-job')), findsNothing);
    expect(find.byKey(const ValueKey('active-job')), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restores the parent-owned board group after remount',
      (tester) async {
    final session = WorkshopBoardCompactSession();
    await pumpBoard(tester, width: 384, session: session);

    await tester.tap(
      find.byKey(const ValueKey('workshop-board-status-selector')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('En curso').last);
    await tester.pumpAndSettle();

    expect(session.selectedGroupId, 'active');
    expect(find.byKey(const ValueKey('active-job')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpBoard(tester, width: 384, session: session);

    expect(find.byKey(const ValueKey('active-job')), findsOneWidget);
    expect(find.byKey(const ValueKey('pending-job')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
