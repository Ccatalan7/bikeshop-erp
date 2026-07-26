import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/inventory/widgets/product_sku_field_row.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'recomposes at canonical boundaries without compressing the command',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final controller = TextEditingController();
      addTearDown(controller.dispose);

      for (final width in <double>[384, 599, 600, 899, 900, 1440]) {
        await _pumpSkuRow(
          tester,
          width: width,
          controller: controller,
        );

        final fieldRect =
            tester.getRect(find.byKey(ProductSkuFieldRow.fieldKey));
        final buttonRect =
            tester.getRect(find.byKey(ProductSkuFieldRow.generateButtonKey));

        expect(
          tester.takeException(),
          isNull,
          reason: '$width px must not overflow',
        );
        expect(
          buttonRect.height,
          greaterThanOrEqualTo(48),
          reason: '$width px must retain a 48 px touch target',
        );

        if (width < 600) {
          expect(buttonRect.top, greaterThan(fieldRect.bottom));
          expect(buttonRect.width, closeTo(fieldRect.width, 0.01));
        } else {
          expect(buttonRect.left, greaterThan(fieldRect.right));
          expect(buttonRect.top, closeTo(fieldRect.top, 0.01));
        }
      }
    },
  );

  testWidgets(
    'keeps long generation labels usable at increased text scale',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final controller = TextEditingController();
      addTearDown(controller.dispose);
      var generationRequests = 0;

      for (final width in <double>[384, 599, 600, 899, 900]) {
        await _pumpSkuRow(
          tester,
          width: width,
          controller: controller,
          textScale: 1.3,
          buttonLabel: 'Siguiente AE',
          onGenerate: () => generationRequests += 1,
        );

        final buttonFinder = find.byKey(ProductSkuFieldRow.generateButtonKey);
        expect(tester.takeException(), isNull);
        expect(tester.getSize(buttonFinder).height, greaterThanOrEqualTo(48));
        expect(find.text('Siguiente AE'), findsOneWidget);

        await tester.tap(buttonFinder);
        await tester.pump();
      }

      expect(generationRequests, 5);
    },
  );
}

Future<void> _pumpSkuRow(
  WidgetTester tester, {
  required double width,
  required TextEditingController controller,
  double textScale = 1,
  String buttonLabel = 'Generar',
  VoidCallback? onGenerate,
}) async {
  tester.view.physicalSize = Size(width, 824);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Form(
                child: ProductSkuFieldRow(
                  controller: controller,
                  labelText: 'SKU interno',
                  hintText: 'Ej. BIC-MTB-TRK-001',
                  buttonLabel: buttonLabel,
                  isGenerating: false,
                  onGenerate: onGenerate ?? () {},
                  validator: (value) =>
                      value == null || value.isEmpty ? 'SKU requerido' : null,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
