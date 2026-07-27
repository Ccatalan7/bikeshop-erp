import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/bikeshop/widgets/workshop_mobile_payment_workspace.dart';
import 'package:vinabike_erp/modules/sales/models/sales_models.dart';

void main() {
  final invoice = Invoice(
    id: 'invoice-id',
    tenantId: 'tenant-id',
    invoiceNumber: 'FV-00902',
    customerName: 'Pablo Vaturana',
    date: DateTime(2026, 7, 26),
    total: 100000,
    paidAmount: 62000,
    balance: 38000,
  );

  Future<void> pumpWorkspace(
    WidgetTester tester, {
    required Size size,
    required VoidCallback onBack,
    EdgeInsets viewInsets = EdgeInsets.zero,
    EdgeInsets safePadding = EdgeInsets.zero,
    Widget? paymentForm,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) {
          final mediaQuery = MediaQuery.of(context);
          return MediaQuery(
            data: mediaQuery.copyWith(
              textScaler: const TextScaler.linear(1.3),
              padding: safePadding,
              viewPadding: safePadding,
              viewInsets: viewInsets,
            ),
            child: child!,
          );
        },
        home: WorkshopMobilePaymentWorkspace(
          invoice: invoice,
          onBack: onBack,
          paymentForm: paymentForm ??
              const SizedBox(
                key: ValueKey('canonical-payment-form'),
                height: 220,
              ),
        ),
      ),
    );
    await tester.pump();
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher.clearAllTestValues();
  });

  testWidgets('stays usable across the required responsive width matrix',
      (tester) async {
    final semantics = tester.ensureSemantics();

    const viewports = <Size>[
      Size(384, 824),
      Size(599, 824),
      Size(600, 824),
      Size(899, 824),
      Size(900, 900),
      Size(1440, 900),
    ];

    for (final viewport in viewports) {
      await pumpWorkspace(
        tester,
        size: viewport,
        onBack: () {},
        safePadding: const EdgeInsets.only(top: 24, bottom: 20),
      );

      expect(find.text('Registrar abono'), findsOneWidget);
      expect(find.text('Factura FV-00902 · Pablo Vaturana'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('canonical-payment-form')), findsOneWidget);

      final backSize = tester.getSize(
        find.byKey(const ValueKey('workshop-payment-back')),
      );
      expect(backSize.width, greaterThanOrEqualTo(48));
      expect(backSize.height, greaterThanOrEqualTo(48));

      final formHostRect = tester.getRect(
        find.byKey(const ValueKey('workshop-payment-form-host')),
      );
      final expectedHorizontalPadding = viewport.width < 600 ? 12.0 : 20.0;
      expect(formHostRect.left, closeTo(expectedHorizontalPadding, 0.01));
      expect(
        formHostRect.right,
        closeTo(viewport.width - expectedHorizontalPadding, 0.01),
      );

      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('workshop-payment-back')),
        ),
        matchesSemantics(
          label: 'Volver a Factura FV-00902',
          isButton: true,
        ),
      );
      expect(tester.takeException(), isNull);
    }
    semantics.dispose();
  });

  testWidgets('visible and system back share the same host callback',
      (tester) async {
    var backCount = 0;
    await pumpWorkspace(
      tester,
      size: const Size(384, 824),
      onBack: () => backCount += 1,
    );

    await tester.tap(find.byKey(const ValueKey('workshop-payment-back')));
    await tester.pump();
    expect(backCount, 1);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(backCount, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('payment controls scroll above the virtual keyboard',
      (tester) async {
    const keyboardInset = 300.0;
    final paymentForm = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TextField(
          key: ValueKey('payment-reference-field'),
          decoration: InputDecoration(labelText: 'Referencia'),
        ),
        const SizedBox(height: 540),
        FilledButton(
          key: const ValueKey('payment-submit'),
          onPressed: () {},
          child: const Text('Registrar pago'),
        ),
      ],
    );

    await pumpWorkspace(
      tester,
      size: const Size(384, 824),
      onBack: () {},
      viewInsets: const EdgeInsets.only(bottom: keyboardInset),
      safePadding: const EdgeInsets.only(top: 24, bottom: 20),
      paymentForm: paymentForm,
    );

    await tester.tap(find.byKey(const ValueKey('payment-reference-field')));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.drag(
      find.byKey(const ValueKey('workshop-payment-scroll')),
      const Offset(0, -1200),
    );
    await tester.pumpAndSettle();

    final submitRect =
        tester.getRect(find.byKey(const ValueKey('payment-submit')));
    expect(
      submitRect.bottom,
      lessThanOrEqualTo(824 - keyboardInset),
    );
    expect(submitRect.top, greaterThan(24));
    expect(tester.takeException(), isNull);
  });
}
