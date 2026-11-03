import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vinabike_erp/modules/sales/models/customer_quote.dart';
import 'package:vinabike_erp/modules/sales/services/customer_quote_service.dart';
import 'package:vinabike_erp/modules/sales/widgets/customer_quote_detail_view.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';
import 'package:vinabike_erp/shared/widgets/vb_button.dart';
import 'package:vinabike_public_core/public_store/documents/quote_offer_pdf.dart';

/// Answers like `customer_quote_detail_v1` and `customer_quote_cancel_v1`,
/// without a database.
class _FakeQuotes implements CustomerQuoteService {
  Map<String, dynamic> quote = {
    'id': 'q-1',
    'quote_number': 'COT-26-00001',
    'status': 'confirming',
    'source': 'web',
    'customer_name': 'Ana Pérez',
    'customer_phone': '+56912345678',
    'preferred_channel': 'whatsapp',
    'notify_email': false,
    'notify_whatsapp': true,
    'requested_at': '2026-11-02T12:00:00Z',
    'version': 1,
  };
  String? cancelReason;

  Map<String, dynamic> get _payload => {
        'quote': quote,
        'settings': {
          'offer_validity_hours': 72,
          'on_order_prepay_percent': 100
        },
        'requested': const [],
        'offers': const [],
        'tasks': const [],
        'messages': const [],
        'events': const [],
      };

  @override
  Future<CustomerQuoteDetail> fetchDetail(String quoteId) async =>
      CustomerQuoteDetail.fromJson(_payload);

  @override
  Future<CustomerQuoteDetail> cancel(
    String quoteId, {
    required String operationKey,
    required String reason,
  }) async {
    cancelReason = reason;
    quote = {...quote, 'status': 'cancelled'};
    return CustomerQuoteDetail.fromJson(_payload);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// An accepted quote whose order is paid and waits for one tyre that comes
/// from the supplier (20261103010000), like `customer_quote_detail_v1`.
class _FakeOrderQuote implements CustomerQuoteService {
  bool arrived = false;
  bool refunded = false;
  int checks = 0;
  String? refundReference;

  Map<String, dynamic> get _payload => {
        'quote': {
          'id': 'q-2',
          'quote_number': 'COT-26-00002',
          'status': 'accepted',
          'source': 'web',
          'customer_name': 'Ana Pérez',
          'customer_email': 'ana@example.invalid',
          'notify_email': true,
          'notify_whatsapp': false,
          'requested_at': '2026-11-02T12:00:00Z',
          'version': 6,
        },
        'settings': {'offer_validity_hours': 72},
        'order': {
          'id': 'o-1',
          'number': 'WEB-26-00010',
          'status': refunded ? 'cancelled' : 'confirmed',
          'payment_status': refunded ? 'refunded' : 'paid',
          'payment_method': 'mercadopago',
          'delivery_type': 'pickup',
          'total': 75000,
          'paid_at': '2026-11-03T13:00:00Z',
          'waiting': !arrived,
          'invoice_number': arrived ? 'B-120' : null,
          'sales_invoice_id': arrived ? 'inv-1' : null,
          'items': [
            {
              'id': 'i-1',
              'product_name': 'Neumático 29 x 2.25',
              'quantity': 1,
              'fulfillment': 'stock',
            },
            {
              'id': 'i-2',
              'product_name': 'Neumático 29 x 2.40',
              'quantity': 1,
              'fulfillment': 'on_order',
              'arrived_at': arrived ? '2026-11-05T15:00:00Z' : null,
              'supplier_id': 's-1',
              'supplier_name': 'Proveedor de neumáticos',
              'lead_days_min': 3,
              'lead_days_max': 5,
            },
          ],
          'purchases': [
            {
              'id': 'p-1',
              'supplier_id': 's-1',
              'supplier_name': 'Proveedor de neumáticos',
              'purchase_invoice_id': 'ped-1',
              'number': 'PED-202611-00042',
              'status': 'draft',
              'total': 29750,
            },
          ],
        },
      };

  @override
  Future<CustomerQuoteDetail> fetchDetail(String quoteId) async =>
      CustomerQuoteDetail.fromJson(_payload);

  @override
  Future<CustomerQuoteDetail> cancelOrder(
    String quoteId, {
    required String operationKey,
    required String reason,
    required String refundReference,
    required DateTime refundedAt,
  }) async {
    refunded = true;
    this.refundReference = refundReference;
    return CustomerQuoteDetail.fromJson(_payload);
  }

  @override
  Future<QuoteOrderArrivals> checkOrderArrivals(String quoteId) async {
    checks++;
    arrived = true;
    return const QuoteOrderArrivals(
        waiting: false, arrived: 1, invoiceId: 'inv-1');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A sent offer the customer has not answered yet, and the document the ERP
/// draws its PDF from (`customer_quote_offer_document_v1`).
class _FakeOfferedQuote implements CustomerQuoteService {
  int documentReads = 0;

  Map<String, dynamic> get _payload => {
        'quote': {
          'id': 'q-3',
          'quote_number': 'COT-26-00003',
          'status': 'offered',
          'source': 'web',
          'customer_name': 'Pía Contreras',
          'customer_email': 'pia@example.invalid',
          'notify_email': true,
          'notify_whatsapp': false,
          'requested_at': '2026-11-02T12:00:00Z',
          'expires_at': '2026-11-10T03:00:00Z',
          'current_offer_id': 'of-1',
          'version': 3,
        },
        'settings': {'offer_validity_hours': 72},
        'requested': const [],
        'offers': [
          {
            'id': 'of-1',
            'offer_no': 1,
            'status': 'sent',
            'sent_at': '2026-11-03T15:00:00Z',
            'valid_until': '2026-11-10T03:00:00Z',
            'subtotal': 10084,
            'tax_amount': 1916,
            'total': 12000,
            'lines': [
              {
                'id': 'l-1',
                'line_no': 1,
                'product_name': 'Cámara 29 válvula presta',
                'quantity_requested': 2,
                'quantity_offered': 2,
                'availability': 'in_stock',
                'unit_price': 6000,
              },
            ],
          },
        ],
        'tasks': const [],
        'messages': const [],
        'events': const [],
      };

  @override
  Future<CustomerQuoteDetail> fetchDetail(String quoteId) async =>
      CustomerQuoteDetail.fromJson(_payload);

  @override
  Future<QuoteOfferPdfInput?> fetchOfferDocument(String quoteId) async {
    documentReads++;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es');
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
    // The icons too: without the font they are drawn as boxes.
    final icons =
        File('${Platform.environment['FLUTTER_ROOT'] ?? '.fvm/flutter_sdk'}'
            '/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (icons.existsSync()) {
      final bytes = icons.readAsBytesSync();
      await (FontLoader('MaterialIcons')
            ..addFont(Future.value(ByteData.view(bytes.buffer))))
          .load();
    }
  });

  /// Set QUOTE_SHOTS=<dir> and run with --update-goldens to write the frames
  /// as PNG for a visual check; they are never compared in CI.
  final shotsDir = Platform.environment['QUOTE_SHOTS'];

  // 2026-11-02: «Enviar oferta» crashed the app with `_dependents.isEmpty`.
  // The field's controller was disposed when `showDialog` resolved, which
  // happens as `pop` starts, while the exit transition still shows the field.
  // The dialog owns its controller now (GUI_DESIGN_PRINCIPLES: a routed sheet
  // owns its listenables).
  testWidgets(
      'a reason typed in the dialog cancels the quote and closing it does '
      'not throw', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final quotes = _FakeQuotes();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.vinabike,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: CustomerQuoteDetailView(quoteId: 'q-1', service: quotes),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Anular'));
    await tester.pumpAndSettle();
    final field = find.byKey(const ValueKey('customer-quote-dialog-text'));
    await tester.enterText(field, 'Prueba interna del sistema');
    await tester.pump();
    await tester.tap(find.text('Anular cotización'));
    // Frame by frame through the exit transition, which still has the field.
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(quotes.cancelReason, 'Prueba interna del sistema');
    expect(field, findsNothing);
    expect(find.text('Anular'), findsNothing,
        reason: 'a cancelled quote has nothing left to cancel');
  });

  // «PDF de la oferta» (20261103050000): the document the customer
  // downloads from the store, for the team to send by WhatsApp. Only a sent
  // offer has one; it is read from the database each time.
  testWidgets(
      'a sent offer has its PDF in the header; a quote still being '
      'confirmed has none', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget app(CustomerQuoteService service, String id) => MaterialApp(
          theme: AppTheme.resolve(
            preset: AppearancePresets.vinabike,
            brightness: Brightness.light,
          ),
          home: Scaffold(
            body: CustomerQuoteDetailView(
              key: ValueKey(id),
              quoteId: id,
              service: service,
            ),
          ),
        );

    final offered = _FakeOfferedQuote();
    await tester.pumpWidget(app(offered, 'q-3'));
    await tester.pumpAndSettle();
    expect(find.text('PDF de la oferta'), findsOneWidget);

    await tester.tap(find.text('PDF de la oferta'));
    await tester.pumpAndSettle();
    expect(offered.documentReads, 1);
    expect(find.text('Todavía no hay una oferta enviada.'), findsOneWidget);

    await tester.pumpWidget(app(_FakeQuotes(), 'q-1'));
    await tester.pumpAndSettle();
    expect(find.text('PDF de la oferta'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // The order block says where each line comes from, sends the supplier
  // order through Compras (its owner: message preview, WhatsApp, «enviado»)
  // and checks the arrival without waiting for the 10-minute job.
  testWidgets(
      'an accepted quote shows its order, checks the arrival and sends the '
      'supplier order from Compras', (tester) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final quotes = _FakeOrderQuote();
    Uri? opened;
    final router = GoRouter(routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(
          body: CustomerQuoteDetailView(quoteId: 'q-2', service: quotes),
        ),
      ),
      GoRoute(
        path: '/purchases/assistant',
        builder: (context, state) {
          opened = state.uri;
          return const Scaffold(body: Text('Asistente de compras'));
        },
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
      theme: AppTheme.resolve(
        preset: AppearancePresets.vinabike,
        brightness: Brightness.light,
      ),
      routerConfig: router,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Pedido WEB-26-00010'), findsOneWidget);
    expect(find.text('Pagado · falta que llegue'), findsOneWidget);
    expect(find.text('Del stock · apartado'), findsOneWidget);
    expect(find.text('A pedido'), findsOneWidget);
    expect(find.text('Por enviar'), findsOneWidget);

    await tester.tap(find.text('Revisar si llegó'));
    await tester.pumpAndSettle();
    expect(quotes.checks, 1);
    expect(find.text('Llegó todo: la venta quedó emitida.'), findsOneWidget);
    expect(find.text('Llegó · apartado'), findsOneWidget);
    expect(find.text('Revisar si llegó'), findsNothing,
        reason: 'nothing is left to wait for');

    await tester.tap(find.text('Enviar al proveedor'));
    await tester.pumpAndSettle();
    expect(opened?.path, '/purchases/assistant');
    expect(opened?.queryParameters, {'supplier': 's-1', 'order': 'ped-1'});
    expect(tester.takeException(), isNull);
  });

  for (final viewport in <({double width, double height, double textScale})>[
    (width: 1280, height: 1100, textScale: 1),
    (width: 390, height: 1500, textScale: 1),
    (width: 390, height: 1700, textScale: 1.3),
  ]) {
    for (final brightness in Brightness.values) {
      final label = '${viewport.width.toInt()}-${brightness.name}-'
          '${viewport.textScale}x';
      testWidgets('the order block fits at $label', (tester) async {
        tester.view.physicalSize = Size(viewport.width, viewport.height);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.resolve(
            preset: AppearancePresets.vinabike,
            brightness: brightness,
          ),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(viewport.textScale),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: CustomerQuoteDetailView(
                quoteId: 'q-2', service: _FakeOrderQuote()),
          ),
        ));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Pedido WEB-26-00010'), findsOneWidget);
        expect(find.text('Enviar al proveedor'), findsOneWidget);
        if (shotsDir != null) {
          await expectLater(
            find.byType(CustomerQuoteDetailView),
            matchesGoldenFile(
                Uri.file('$shotsDir/cotizacion-pedido-$label.png')),
          );
        }
      });
    }
  }

  // The header with «PDF de la oferta» next to the link, on a desk and on a
  // phone (where the actions wrap under the title).
  for (final width in const [1280.0, 390.0]) {
    for (final brightness in Brightness.values) {
      final label = '${width.toInt()}-${brightness.name}';
      testWidgets('a sent offer\'s header fits at $label', (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.resolve(
            preset: AppearancePresets.vinabike,
            brightness: brightness,
          ),
          home: Scaffold(
            body: CustomerQuoteDetailView(
                quoteId: 'q-3', service: _FakeOfferedQuote()),
          ),
        ));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('PDF de la oferta'), findsOneWidget);
        expect(find.text('Copiar enlace del cliente'), findsOneWidget);
        if (shotsDir != null) {
          await expectLater(
            find.byType(CustomerQuoteDetailView),
            matchesGoldenFile(
                Uri.file('$shotsDir/cotizacion-oferta-pdf-$label.png')),
          );
        }
      });
    }
  }

  // 20261103030000: a paid order still waiting is cancelled only after the
  // money went back; the dialog asks for the refund reference before it lets
  // the team confirm, and the order then reads «Anulado · devuelto».
  testWidgets('a paid order without a sale is cancelled with its refund',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final quotes = _FakeOrderQuote();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.vinabike,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: CustomerQuoteDetailView(quoteId: 'q-2', service: quotes),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Anular y devolver'));
    await tester.pumpAndSettle();
    expect(find.text('Anular y devolver WEB-26-00010'), findsOneWidget);
    final confirm =
        find.widgetWithText(VbButton, 'Anular y registrar la devolución');
    expect(tester.widget<VbButton>(confirm).onPressed, isNull,
        reason: 'nothing is recorded without a reason and a reference');

    await tester.enterText(
        find.byKey(const ValueKey('customer-quote-refund-reason')),
        'El proveedor no tiene la medida');
    await tester.enterText(
        find.byKey(const ValueKey('customer-quote-refund-reference')),
        'DEV-120');
    await tester.pump();
    await tester.tap(confirm);
    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 25));
    }
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(quotes.refundReference, 'DEV-120');
    expect(find.text('Anulado · devuelto'), findsOneWidget);
    expect(find.text('Anular y devolver'), findsNothing);
    expect(find.text('Revisar si llegó'), findsNothing,
        reason: 'a cancelled order waits for nothing');
  });
}
