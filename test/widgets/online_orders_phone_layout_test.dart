import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/website/models/website_models.dart';
import 'package:vinabike_erp/modules/website/pages/online_orders_page.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/modules/website/widgets/online_order_sheet.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/utils/chilean_utils.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// The online orders page on a phone (dueño, 2026-10-13: «la UI móvil está
/// tratada como la mierda»): one row per order instead of the desktop table
/// in horizontal scroll, and the order full screen instead of a floating
/// window that cut the total and pushed the buttons off.
///
/// Set ORDERS_PHONE_SHOTS=<dir> and run with --update-goldens to write the
/// frames as PNG for a visual check; they are never compared in CI.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('es');
    await initializeDateFormatting('es_CL');
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
      httpClient: MockClient(
        (request) async => http.Response(
          '[]',
          200,
          headers: const {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
    // Real glyphs, so widths and wrapping are the ones a person sees.
    final loader = FontLoader('Roboto');
    for (final asset in const <String>[
      'assets/fonts/Barlow-Regular.ttf',
      'assets/fonts/Barlow-Medium.ttf',
      'assets/fonts/Barlow-SemiBold.ttf',
    ]) {
      loader.addFont(rootBundle.load(asset));
    }
    await loader.load();
  });

  final shotsDir = Platform.environment['ORDERS_PHONE_SHOTS'];

  for (final viewport in <({double width, double height, double textScale})>[
    (width: 360, height: 780, textScale: 1),
    (width: 390, height: 844, textScale: 1),
    (width: 390, height: 844, textScale: 1.3),
  ]) {
    for (final brightness in Brightness.values) {
      final label = '${viewport.width.toInt()}x${viewport.height.toInt()} '
          '${brightness.name} ${viewport.textScale}x';

      testWidgets('phone list and full-screen order at $label', (tester) async {
        tester.view.physicalSize = Size(viewport.width, viewport.height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _host(brightness: brightness, textScale: viewport.textScale),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull);
        expect(find.text('WEB-26-00021'), findsOneWidget);
        // The desktop table's header row is not drawn on a phone.
        expect(find.text('Email'), findsNothing);
        // A payment Mercado Pago confirmed reads paid, even before the sale.
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Text && widget.data?.toLowerCase() == 'pagado',
          ),
          findsWidgets,
        );
        expect(find.text('Falta la venta ERP'), findsOneWidget);

        if (shotsDir != null) {
          await expectLater(
            find.byType(OnlineOrdersPage),
            matchesGoldenFile(
              Uri.file('$shotsDir/lista-${label.replaceAll(' ', '-')}.png'),
            ),
          );
        }

        await tester.tap(find.text('WEB-26-00021'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(tester.takeException(), isNull);
        final dialog = find.byType(Dialog);
        expect(dialog, findsOneWidget);
        expect(_dialogSurfaceWidth(tester), viewport.width);
        // The band: total, payment with its method, delivery and the steps.
        expect(
          find.text(ChileanUtils.formatCurrency(17990)),
          findsWidgets,
        );
        expect(find.text('Pagado · Mercado Pago'), findsOneWidget);
        expect(find.text('Despacho a domicilio'), findsWidgets);
        expect(
          find.bySemanticsLabel(RegExp('Pagado, hecho; Preparar, ahora')),
          findsOneWidget,
        );
        // The sheet: what to pick, who gets it, then payment and sale.
        for (final caption in ['PRODUCTOS', 'ENTREGAR A', 'PAGO Y VENTA']) {
          expect(find.text(caption), findsOneWidget, reason: caption);
        }
        expect(find.textContaining('AE0174 · 1 u.'), findsOneWidget);
        expect(find.text('Calle Sintética 123, Depto 4'), findsOneWidget);
        expect(find.text('Falta crearla'), findsOneWidget);
        // The bar: both ways to reach the customer and the next step.
        expect(find.byTooltip('Escribir por WhatsApp'), findsOneWidget);
        expect(find.byTooltip('Llamar al cliente'), findsOneWidget);
        expect(find.text('Revisar pago'), findsOneWidget);

        if (shotsDir != null) {
          await expectLater(
            dialog,
            matchesGoldenFile(
              Uri.file('$shotsDir/pedido-${label.replaceAll(' ', '-')}.png'),
            ),
          );
        }
      });
    }
  }

  testWidgets('a desktop keeps the table and a floating order', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(brightness: Brightness.light));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(tester.takeException(), isNull);
    expect(find.text('Email'), findsOneWidget);

    await tester.tap(find.text('WEB-26-00021'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(_dialogSurfaceWidth(tester), lessThanOrEqualTo(1040));
    expect(find.byTooltip('Cerrar'), findsOneWidget);
    expect(find.text('Revisar pago'), findsOneWidget);

    if (shotsDir != null) {
      await expectLater(
        find.byType(Dialog),
        matchesGoldenFile(Uri.file('$shotsDir/pedido-escritorio.png')),
      );
    }
  });

  testWidgets('a short order keeps its sheet down to the action bar',
      (tester) async {
    // Taller than the order: no navy may show under the sheet.
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_host(brightness: Brightness.light));
    await tester.pump();
    await tester.tap(find.text('WEB-26-00021'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final viewport = tester.renderObject<RenderViewport>(
      find.descendant(
        of: find.byType(OnlineOrderSheet),
        matching: find.byType(Viewport),
      ),
    );
    final sheet = tester.renderObject<RenderSliver>(
      find.byType(DecoratedSliver),
    );
    expect(
      sheet.constraints.precedingScrollExtent + sheet.geometry!.scrollExtent,
      moreOrLessEquals(viewport.size.height),
    );
  });

  testWidgets('the next step runs from the bar and the band follows it',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final service = _OrdersFake([_confirmedPaidOrder()]);
    await tester.pumpWidget(
      _host(brightness: Brightness.light, service: service),
    );
    await tester.pump();
    await tester.tap(find.text('WEB-26-00022'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Comenzar preparación'), findsOneWidget);
    expect(find.text('Abrir venta'), findsOneWidget);

    await tester.tap(find.text('Comenzar preparación'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(service.transitions, ['processing']);
    expect(tester.takeException(), isNull);
    // Still open, now on the next step.
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Registrar despacho'), findsOneWidget);

    if (shotsDir != null) {
      await expectLater(
        find.byType(Dialog),
        matchesGoldenFile(Uri.file('$shotsDir/pedido-en-proceso.png')),
      );
    }
  });
}

/// The dialog's own surface, not the overlay the [Dialog] widget fills.
double _dialogSurfaceWidth(WidgetTester tester) => tester
    .getSize(
      find
          .descendant(
            of: find.byType(Dialog),
            matching: find.byType(Material),
          )
          .first,
    )
    .width;

Widget _host({
  required Brightness brightness,
  double textScale = 1,
  _OrdersFake? service,
}) {
  service ??= _OrdersFake([_paidOrderWaitingForItsSale()]);
  return ChangeNotifierProvider<WebsiteService>.value(
    value: service,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.resolve(
        preset: AppearancePresets.vinabike,
        brightness: brightness,
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: const Scaffold(body: OnlineOrdersPage(embedded: true)),
    ),
  );
}

/// A paid order still waiting for its ERP sale (synthetic data).
OnlineOrder _paidOrderWaitingForItsSale() {
  final createdAt = DateTime(2026, 10, 12, 15, 52);
  return OnlineOrder(
    id: '9e400000-0000-4000-8000-000000000021',
    tenantId: '9e400000-0000-4000-8000-000000000001',
    orderNumber: 'WEB-26-00021',
    customerEmail: 'cliente@example.invalid',
    customerName: 'Cliente de Prueba',
    customerPhone: '+56900000000',
    deliveryType: 'shipping',
    shippingAddressLine1: 'Calle Sintética 123',
    shippingAddressLine2: 'Depto 4',
    shippingCity: 'Viña del Mar',
    shippingState: 'Región de Valparaíso',
    shippingCountry: 'Chile',
    subtotal: 9244,
    taxAmount: 1756,
    shippingCost: 6990,
    discountAmount: 0,
    total: 17990,
    status: 'pending',
    paymentStatus: 'pending',
    paymentMethod: 'mercadopago',
    customerNotes: 'Nota de prueba para el despacho.',
    paymentProviderStatus: 'approved',
    paymentValidationOutcome: 'payment_validated',
    paymentProcessingState: 'pending',
    paymentProcessingEventId: 2,
    createdAt: createdAt,
    updatedAt: createdAt,
    items: [
      OnlineOrderItem(
        id: 'item-1',
        orderId: '9e400000-0000-4000-8000-000000000021',
        productName: 'Adaptador Tee 25.4/28.6 Manillar 28.6 160mm AE',
        productSku: 'AE0174',
        quantity: 1,
        unitPrice: 11000,
        subtotal: 11000,
        createdAt: createdAt,
      ),
    ],
  );
}

/// The same customer's next order, paid and sold, waiting to be prepared.
OnlineOrder _confirmedPaidOrder() {
  final paid = _paidOrderWaitingForItsSale();
  return paid.copyWith(
    id: '9e400000-0000-4000-8000-000000000022',
    orderNumber: 'WEB-26-00022',
    status: 'confirmed',
    paymentStatus: 'paid',
    paymentValidationOutcome: 'applied',
    paymentProcessingState: 'processed',
    salesInvoiceId: '9e400000-0000-4000-8000-0000000000aa',
  );
}

class _OrdersFake extends WebsiteService {
  _OrdersFake(this._fixtures);

  List<OnlineOrder> _fixtures;
  final List<String> transitions = [];

  @override
  List<OnlineOrder> get orders => _fixtures;

  @override
  Future<String?> updateOrderStatus(
    String orderId,
    String status, {
    required int expectedVersion,
    String? operationKey,
    String? trackingNumber,
    String? trackingUrl,
    String? carrier,
    String? notes,
  }) async {
    transitions.add(status);
    _fixtures = [
      for (final order in _fixtures)
        order.id == orderId
            ? order.copyWith(status: status, version: order.version + 1)
            : order,
    ];
    notifyListeners();
    return null;
  }

  @override
  bool get isLoading => false;

  @override
  Future<void> initializeOrders() async {}

  @override
  Future<void> loadOrders() async {}
}
