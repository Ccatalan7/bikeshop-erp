import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/dev/purchase_receiving_preview.dart';
import 'package:vinabike_erp/modules/purchases/pages/purchase_receiving_page.dart';

void main() {
  testWidgets('preview mounts the real receiving workspace with fake data',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const PurchaseReceivingPreviewApp());
    await tester.pumpAndSettle();

    expect(find.text('PREVIEW LOCAL'), findsOneWidget);
    expect(find.text('Datos ficticios · sin conexión ni escrituras'),
        findsOneWidget);
    expect(find.byType(PurchaseReceivingWorkspace), findsOneWidget);
    expect(find.text('Recepción de productos'), findsOneWidget);
    expect(find.text('Factura 51611 · Comercial Ciclo'), findsOneWidget);
    expect(find.text('Cámara 10TEN Butyl 26'), findsOneWidget);
    expect(find.byType(Image), findsNWidgets(4));
    expect(
      Theme.of(tester.element(find.byType(PurchaseReceivingWorkspace)))
          .brightness,
      Brightness.light,
    );
  });

  testWidgets('simulated submit never leaves the preview harness',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const PurchaseReceivingPreviewApp());
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(FilledButton, 'Registrar recepción'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Registrar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('PREVIEW-001 simulada'), findsOneWidget);
    expect(
      find.text('Todas las líneas ya tienen recepción completa.'),
      findsOneWidget,
    );
    expect(find.byType(PurchaseReceivingWorkspace), findsOneWidget);
  });
}
