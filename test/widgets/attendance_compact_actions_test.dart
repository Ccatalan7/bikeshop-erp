import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/hr/widgets/attendance_compact_actions.dart';

void main() {
  for (final width in const [320.0, 375.0, 599.0]) {
    testWidgets('compact attendance actions fit at ${width.toInt()} px',
        (tester) async {
      await tester.binding.setSurfaceSize(Size(width, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: AttendanceCompactActions(
                canAccessPayroll: true,
                onOpenPayroll: () {},
                onGeneratePayroll: () {},
                onCreateAttendance: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Nóminas'), findsOneWidget);
      expect(find.text('Preparar nómina'), findsOneWidget);
      expect(find.text('Nuevo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('payroll actions are not constructed without authority',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AttendanceCompactActions(
            canAccessPayroll: false,
            onOpenPayroll: () {},
            onGeneratePayroll: () {},
            onCreateAttendance: () {},
          ),
        ),
      ),
    );

    expect(find.text('Nóminas'), findsNothing);
    expect(find.text('Preparar nómina'), findsNothing);
    expect(find.text('Nuevo'), findsOneWidget);
  });
}
