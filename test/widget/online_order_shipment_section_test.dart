import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/online_order_shipment.dart';
import 'package:vinabike_erp/modules/website/models/website_models.dart';
import 'package:vinabike_erp/modules/website/services/online_order_shipment_service.dart';
import 'package:vinabike_erp/modules/website/widgets/online_order_shipment_section.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

// Invented shipped order (2026-10-13 shipping receipt flow).
OnlineOrder _order({String? carrier, String? tracking, bool isTest = false}) {
  final createdAt = DateTime(2026, 10, 12, 15, 52);
  return OnlineOrder(
    id: '9e700000-0000-4000-8000-000000000031',
    tenantId: '9e700000-0000-4000-8000-000000000001',
    orderNumber: 'WEB-26-00031',
    customerEmail: 'cliente@example.invalid',
    customerName: 'Cliente de Prueba',
    deliveryType: 'shipping',
    shippingCarrier: carrier,
    trackingNumber: tracking,
    subtotal: 9244,
    taxAmount: 1756,
    shippingCost: 6990,
    discountAmount: 0,
    total: 17990,
    status: 'shipped',
    paymentStatus: 'paid',
    isTest: isTest,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

class _Shipments implements OnlineOrderShipmentReader {
  _Shipments(this.shipments);

  List<OnlineOrderShipment> shipments;
  ShipmentExpenseDraft? expense;

  @override
  Future<List<OnlineOrderShipment>> loadForOrder(String orderId) async =>
      shipments;

  @override
  Future<String?> receiptUrl(String path) async => null;

  @override
  Future<ShipmentExpenseOptions> expenseOptions(String carrier) async =>
      const ShipmentExpenseOptions(
        supplierName: 'Correos de Chile',
        accountId: 'account-transport',
        categoryName: 'Gastos por Transporte',
        paymentMethodId: 'pm-cash',
        paymentMethods: [(id: 'pm-cash', code: 'cash', name: 'Efectivo')],
      );

  @override
  Future<OnlineOrderShipment> recordExpense({
    required String shipmentId,
    required ShipmentExpenseDraft expense,
  }) async {
    this.expense = expense;
    final registered =
        _shipment(expenseId: 'expense-1', expenseNumber: 'GTO-00231');
    shipments = [registered];
    return registered;
  }
}

OnlineOrderShipment _shipment({
  String? expenseId,
  String? expenseNumber,
  String? documentType,
  String? documentNumber,
}) =>
    OnlineOrderShipment(
      id: 'shipment-1',
      orderId: '9e700000-0000-4000-8000-000000000031',
      carrier: 'Correos de Chile',
      carrierCode: 'correos_chile',
      service: 'Paquete Express AM',
      trackingNumber: '770000000001',
      trackingUrl: 'https://www.correos.cl/web/guest/seguimiento-en-linea',
      admittedAt: DateTime.utc(2026, 10, 13, 20, 43),
      cost: 6240,
      receiptPath: 'tenant/evidence/online_order_shipment/x/boleta.jpg',
      createdAt: DateTime.utc(2026, 10, 13, 21),
      expenseId: expenseId,
      expenseNumber: expenseNumber,
      documentType: documentType,
      documentNumber: documentNumber,
    );

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.resolve(
      preset: AppearancePresets.vinabike,
      brightness: Brightness.light,
    ),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the sheet shows the receipt: carrier, code, cost and link',
      (tester) async {
    await _pump(
      tester,
      OnlineOrderShipmentSection(
        order: _order(carrier: 'Correos de Chile', tracking: '770000000001'),
        service: _Shipments([
          OnlineOrderShipment(
            id: 'shipment-1',
            orderId: '9e700000-0000-4000-8000-000000000031',
            carrier: 'Correos de Chile',
            carrierCode: 'correos_chile',
            service: 'Paquete Express AM',
            trackingNumber: '770000000001',
            trackingUrl:
                'https://www.correos.cl/web/guest/seguimiento-en-linea',
            admittedAt: DateTime.utc(2026, 10, 13, 20, 43),
            cost: 6240,
            receiptPath: 'tenant/evidence/online_order_shipment/x/boleta.jpg',
            createdAt: DateTime.utc(2026, 10, 13, 21),
          ),
        ]),
      ),
    );

    expect(find.text('ENVÍO'), findsOneWidget);
    expect(find.text('Correos de Chile'), findsOneWidget);
    expect(find.text('Paquete Express AM'), findsOneWidget);
    expect(find.text('770000000001'), findsOneWidget);
    final costLine = tester
        .widget<Text>(find.textContaining('Pagado al transportista'))
        .data!;
    expect(costLine, contains('6.240'));
    expect(costLine, contains('cobrado al cliente'));
    expect(costLine, contains('6.990'));
    expect(find.text('Seguir envío'), findsOneWidget);
    expect(find.bySemanticsLabel('Ver la boleta del envío'), findsOneWidget);
    expect(find.byTooltip('Copiar número de seguimiento'), findsOneWidget);
    expect(find.text('Registrar gasto'), findsOneWidget);
  });

  testWidgets('a test order offers no expense', (tester) async {
    await _pump(
      tester,
      OnlineOrderShipmentSection(
        order: _order(
          carrier: 'Correos de Chile',
          tracking: '770000000001',
          isTest: true,
        ),
        service: _Shipments([_shipment()]),
      ),
    );

    expect(find.text('Registrar gasto'), findsNothing);
  });

  testWidgets('a shipment with its expense links to it', (tester) async {
    await _pump(
      tester,
      OnlineOrderShipmentSection(
        order: _order(carrier: 'Correos de Chile', tracking: '770000000001'),
        service: _Shipments([
          _shipment(expenseId: 'expense-1', expenseNumber: 'GTO-00231'),
        ]),
      ),
    );

    expect(find.text('Gasto GTO-00231'), findsOneWidget);
    expect(find.text('Registrar gasto'), findsNothing);
  });

  // 2026-10-13: a shipment registered before the option, or with it off,
  // gets its expense from the card, with what the AI read on the receipt.
  testWidgets('the expense of an earlier shipment is registered from the card',
      (tester) async {
    final service = _Shipments([
      _shipment(documentType: 'invoice', documentNumber: 'F-0001'),
    ]);
    await _pump(
      tester,
      OnlineOrderShipmentSection(
        order: _order(carrier: 'Correos de Chile', tracking: '770000000001'),
        service: service,
      ),
    );

    await tester.tap(find.text('Registrar gasto'));
    await tester.pumpAndSettle();
    expect(find.text('Registrar el gasto del envío'), findsOneWidget);
    expect(
        find.text('Correos de Chile · Gastos por Transporte'), findsOneWidget);
    expect(find.textContaining('IVA crédito'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('shipment-expense-save')));
    await tester.pumpAndSettle();

    expect(service.expense?.toInput(), {
      'payment_method_id': 'pm-cash',
      'document_type': 'invoice',
      'document_number': 'F-0001',
    });
    expect(find.text('Gasto GTO-00231 registrado.'), findsOneWidget);
    expect(find.text('Gasto GTO-00231'), findsOneWidget);
  });

  testWidgets('an order shipped by hand shows the carrier and code it has',
      (tester) async {
    await _pump(
      tester,
      OnlineOrderShipmentSection(
        order: _order(carrier: 'Starken', tracking: 'ST123456'),
        service: _Shipments(const []),
      ),
    );

    expect(find.text('Starken'), findsOneWidget);
    expect(find.text('ST123456'), findsOneWidget);
    expect(find.text('Seguir envío'), findsNothing);
  });
}
