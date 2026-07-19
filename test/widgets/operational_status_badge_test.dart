import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/widgets/interactive_table_field.dart';
import 'package:vinabike_erp/shared/widgets/operational_status_badge.dart';

void main() {
  Widget app(Widget child) => MaterialApp(
        home: Scaffold(
          body: Center(child: child),
        ),
      );

  testWidgets('actionable badge uses the Jobs interaction and chevron',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      app(
        OperationalStatusBadge(
          label: 'Confirmado',
          accentColor: const Color(0xFF4B7087),
          compact: true,
          onTap: () => taps += 1,
        ),
      ),
    );

    expect(find.text('CONFIRMADO'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    expect(find.byType(InteractiveTableField), findsOneWidget);
    expect(find.byTooltip('Cambiar estado y ver acciones'), findsOneWidget);

    await tester.tap(find.text('CONFIRMADO'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('terminal badge stays passive and has no fake dropdown',
      (tester) async {
    await tester.pumpWidget(
      app(
        const OperationalStatusBadge(
          label: 'Entregado',
          accentColor: Color(0xFF5F7D68),
          compact: true,
        ),
      ),
    );

    expect(find.text('ENTREGADO'), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
    expect(find.byType(InteractiveTableField), findsNothing);
  });

  testWidgets('passive provider-owned status can still explain its trigger',
      (tester) async {
    const message = 'Mercado Pago actualiza este estado automáticamente.';
    await tester.pumpWidget(
      app(
        const OperationalStatusBadge(
          label: 'Pendiente',
          accentColor: Color(0xFF9A742F),
          compact: true,
          tooltip: message,
        ),
      ),
    );

    expect(find.byTooltip(message), findsOneWidget);
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsNothing);
  });
}
