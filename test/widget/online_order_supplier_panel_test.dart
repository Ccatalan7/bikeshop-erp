import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vinabike_erp/modules/sales/models/customer_quote.dart';
import 'package:vinabike_erp/modules/sales/services/customer_quote_service.dart';
import 'package:vinabike_erp/modules/website/widgets/online_order_supplier_panel.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// A direct purchase (no quote) that is paid and waits for a chain the
/// supplier brings (20261120210000), as `online_order_on_order_detail_v1`
/// answers it.
class _FakeDirectOrder implements CustomerQuoteService {
  bool arrived = false;
  bool refunded = false;
  int checks = 0;
  String? refundReference;

  Map<String, dynamic> get _order => {
        'id': 'o-9',
        'number': 'WEB-26-00031',
        'status': refunded ? 'cancelled' : 'confirmed',
        'payment_status': refunded ? 'refunded' : 'paid',
        'payment_method': 'mercadopago',
        'delivery_type': 'shipping',
        'total': 45000,
        'paid_at': '2026-11-20T13:00:00Z',
        'waiting': !arrived,
        'quote_id': null,
        'sales_invoice_id': arrived ? 'inv-9' : null,
        'items': [
          {
            'id': 'i-1',
            'product_name': 'Cadena SRAM 12v',
            'quantity': 2,
            'fulfillment': 'on_order',
            'arrived_at': arrived ? '2026-11-24T15:00:00Z' : null,
            'supplier_id': 's-1',
            'supplier_name': 'MKR Imports',
            'lead_days_min': 3,
            'lead_days_max': 5,
          },
        ],
        'purchases': [
          {
            'id': 'p-1',
            'supplier_id': 's-1',
            'supplier_name': 'MKR Imports',
            'purchase_invoice_id': 'ped-9',
            'number': 'PED-202611-00077',
            'status': 'draft',
            'total': 21420,
          },
        ],
      };

  @override
  Future<CustomerQuoteOrder?> fetchOnlineOrderOnOrder(String orderId) async =>
      CustomerQuoteOrder.fromJson(_order);

  @override
  Future<QuoteOrderArrivals> checkOnlineOrderArrivals(String orderId) async {
    checks++;
    arrived = true;
    return const QuoteOrderArrivals(
        waiting: false, arrived: 1, invoiceId: 'inv-9');
  }

  @override
  Future<CustomerQuoteOrder> cancelOnlineOrderOnOrder(
    String orderId, {
    required String operationKey,
    required String reason,
    required String refundReference,
    required DateTime refundedAt,
  }) async {
    refunded = true;
    this.refundReference = refundReference;
    return CustomerQuoteOrder.fromJson(_order);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  Widget app(Widget panel, {Brightness brightness = Brightness.light}) {
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: panel,
          ),
        ),
      ),
      GoRoute(
        path: '/purchases/assistant',
        builder: (context, state) =>
            Scaffold(body: Text('Asistente ${state.uri.query}')),
      ),
    ]);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.resolve(
        preset: AppearancePresets.vinabike,
        brightness: brightness,
      ),
      routerConfig: router,
    );
  }

  testWidgets(
      'a paid direct purchase shows its supplier order, checks the arrival '
      'and opens the purchase in Compras', (tester) async {
    final orders = _FakeDirectOrder();
    var changed = 0;
    await tester.pumpWidget(app(OnlineOrderSupplierPanel(
      orderId: 'o-9',
      service: orders,
      onChanged: () => changed++,
    )));
    await tester.pumpAndSettle();

    expect(find.text('MKR Imports'), findsOneWidget);
    expect(find.text('Enviar al proveedor'), findsOneWidget);
    expect(find.text('Revisar si llegó'), findsOneWidget);
    expect(find.text('Anular y devolver'), findsOneWidget);

    await tester.tap(find.text('Revisar si llegó'));
    await tester.pumpAndSettle();
    expect(orders.checks, 1);
    expect(changed, 1);
    expect(find.text('Revisar si llegó'), findsNothing,
        reason: 'nothing is left to wait for');
    expect(find.text('Anular y devolver'), findsNothing,
        reason: 'with a sale the refund belongs to Correcciones');

    await tester.tap(find.text('Enviar al proveedor'));
    await tester.pumpAndSettle();
    expect(find.text('Asistente supplier=s-1&order=ped-9'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Anular y devolver» records the refund the team made',
      (tester) async {
    final orders = _FakeDirectOrder();
    await tester.pumpWidget(app(OnlineOrderSupplierPanel(
      orderId: 'o-9',
      service: orders,
    )));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Anular y devolver'));
    await tester.pumpAndSettle();
    expect(find.text('Anular y devolver WEB-26-00031'), findsOneWidget);
    await tester.enterText(
        find.byKey(const ValueKey('customer-quote-refund-reason')),
        'El distribuidor no la tenía');
    await tester.enterText(
        find.byKey(const ValueKey('customer-quote-refund-reference')),
        'MP-DEV-1');
    await tester.pump();
    await tester.tap(find.text('Anular y registrar la devolución'));
    await tester.pumpAndSettle();

    expect(orders.refundReference, 'MP-DEV-1');
    expect(find.text('Pedido anulado y devolución registrada'), findsOneWidget);
    expect(find.text('Anular y devolver'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in const [1280.0, 390.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('fits at ${width.toInt()} in ${brightness.name}',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(app(
          OnlineOrderSupplierPanel(orderId: 'o-9', service: _FakeDirectOrder()),
          brightness: brightness,
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Enviar al proveedor'), findsOneWidget);
      });
    }
  }
}
