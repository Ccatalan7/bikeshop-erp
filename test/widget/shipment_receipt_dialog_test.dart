import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:vinabike_erp/modules/website/models/online_order_shipment.dart';
import 'package:vinabike_erp/modules/website/models/website_models.dart';
import 'package:vinabike_erp/modules/website/services/online_order_shipment_service.dart';
import 'package:vinabike_erp/modules/website/widgets/shipment_receipt_dialog.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

// Invented order and receipt (2026-10-13 shipping receipt flow).
OnlineOrder _order({String email = 'cliente@example.invalid'}) {
  final createdAt = DateTime(2026, 10, 12, 15, 52);
  return OnlineOrder(
    id: '9e600000-0000-4000-8000-000000000031',
    tenantId: '9e600000-0000-4000-8000-000000000001',
    orderNumber: 'WEB-26-00031',
    customerEmail: email,
    customerName: 'Camila Andrea Fuentes',
    deliveryType: 'shipping',
    shippingAddressLine1: 'Pasaje Los Aromos 456',
    shippingCity: 'Ñuñoa',
    subtotal: 9244,
    taxAmount: 1756,
    shippingCost: 6990,
    discountAmount: 0,
    total: 17990,
    status: 'confirmed',
    paymentStatus: 'paid',
    version: 4,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

Map<String, dynamic> _reading({String recipient = 'CAMILA ANDREA FUENTES'}) => {
      'is_shipping_receipt': true,
      'carrier_code': 'correos_chile',
      'service': 'PAQUETE EXPRESS AM',
      'tracking_number': '770000000001',
      'tracking_number_characters': '770000000001'.split(''),
      'admitted_at': '2026-10-13T17:43',
      'total_paid': 6240,
      'recipient_name': recipient,
      'recipient_comuna': 'ÑUÑOA',
      'recipient_address': 'PASAJE LOS AROMOS 456',
    };

class _FakeShipments implements OnlineOrderShipmentRecorder {
  _FakeShipments(this.reading);

  final Map<String, dynamic> reading;
  int uploads = 0;
  ShipmentDraft? draft;
  String? receiptPath;
  List<ShipmentReceiptCheck> checks = const [];
  String? operationKey;

  /// The close-ups agree unless the test says they did not.
  List<String?> closeUpVotes = const ['770000000001', '770000000001'];

  ShipmentDraft? previewedDraft;
  String deliveryMode = 'send';
  Object? previewError;

  @override
  Future<ShipmentEmailPreview> previewEmail({
    required OnlineOrder order,
    required ShipmentDraft draft,
  }) async {
    if (previewError != null) throw previewError!;
    previewedDraft = draft;
    return ShipmentEmailPreview(
      subject: 'Tu pedido ${order.orderNumber} ya fue enviado',
      html: '<html><body><h1>Tu pedido va en camino</h1>'
          '<p>Seguimiento ${draft.trackingNumber}</p></body></html>',
      deliveryMode: deliveryMode,
      recipient: order.customerEmail,
      recipientName: order.customerName,
      senderName: 'Ventas Tienda',
      senderEmail: 'ventas@example.invalid',
    );
  }

  @override
  Future<ShipmentReceiptReading> readReceipt(ShipmentReceiptFile file) async =>
      ShipmentReceiptReading.fromJson(reading)
          .withCloseUp(votes: closeUpVotes, closeUp: _png);

  @override
  Future<String> uploadReceipt({
    required String orderId,
    required ShipmentReceiptFile file,
  }) async {
    uploads++;
    return 'tenant/evidence/online_order_shipment/$orderId/boleta.jpg';
  }

  @override
  Future<OnlineOrderShipment> record({
    required OnlineOrder order,
    required String operationKey,
    required ShipmentDraft draft,
    String? receiptPath,
    ShipmentReceiptReading? reading,
    List<ShipmentReceiptCheck> checks = const [],
  }) async {
    this.draft = draft;
    this.receiptPath = receiptPath;
    this.checks = checks;
    this.operationKey = operationKey;
    return OnlineOrderShipment(
      id: 'shipment-1',
      orderId: order.id,
      carrier: draft.carrierLabel,
      trackingNumber: draft.trackingNumber,
      createdAt: DateTime.utc(2026, 10, 13, 21),
    );
  }
}

final _png = img.encodePng(img.Image(width: 12, height: 16));

Future<void> _open(
  WidgetTester tester,
  _FakeShipments service,
  void Function(OnlineOrderShipment?) onResult, {
  OnlineOrder? order,
}) async {
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.resolve(
      preset: AppearancePresets.vinabike,
      brightness: Brightness.light,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () async => onResult(await showShipmentReceiptDialog(
              context,
              order: order ?? _order(),
              customerRut: Future.value(null),
              service: service,
              picker: ({required bool camera}) async =>
                  (bytes: _png, name: 'boleta.png'),
            )),
            child: const Text('abrir'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

/// The photo is brought down in an isolate: wait for it in real time.
Future<void> _pickPhoto(WidgetTester tester) async {
  await tester.tap(find.text('Elegir foto o PDF'));
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pump();
    if (find.byKey(const ValueKey('shipment-tracking')).evaluate().isNotEmpty) {
      break;
    }
  }
  await tester.pumpAndSettle();
}

/// With a customer email the review continues to the email preview.
ButtonStyleButton _previewButton(WidgetTester tester) => tester
    .widget<ButtonStyleButton>(find.byKey(const ValueKey('shipment-preview')));

Future<void> _toPreview(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('shipment-preview')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a receipt for this order is registered from its email preview',
      (tester) async {
    final service = _FakeShipments(_reading());
    OnlineOrderShipment? result;
    await _open(tester, service, (value) => result = value);

    expect(find.text('Sube la foto de la boleta del envío'), findsOneWidget);
    await _pickPhoto(tester);

    expect(find.textContaining('La boleta es de este pedido'), findsOneWidget);
    expect(find.text('770000000001'), findsOneWidget);
    expect(find.text('Paquete Express AM'), findsOneWidget);
    expect(find.textContaining('Cobrado al cliente por el despacho'),
        findsOneWidget);
    expect(find.text('Ver el correo antes de enviar'), findsOneWidget);
    expect(find.byKey(const ValueKey('shipment-save')), findsNothing);

    // 2026-10-13: the owner sees the email before it goes, like a WhatsApp
    // template; nothing is uploaded or registered until then.
    await _toPreview(tester);
    expect(find.text('Así le llegará'), findsOneWidget);
    expect(find.text('Tu pedido WEB-26-00031 ya fue enviado'), findsOneWidget);
    expect(find.textContaining('cliente@example.invalid'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('shipment-email-preview')), findsOneWidget);
    expect(
      find.textContaining('Seguimiento 770000000001', findRichText: true),
      findsOneWidget,
    );
    expect(service.uploads, 0);
    expect(service.draft, isNull);
    expect(find.text('Registrar despacho y enviar correo'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('shipment-save')));
    await tester.pumpAndSettle();

    expect(service.uploads, 1);
    expect(service.draft!.toInput(), service.previewedDraft!.toInput(),
        reason: 'what is registered is what was previewed');
    expect(service.receiptPath, contains('/evidence/online_order_shipment/'));
    expect(service.draft!.carrier, ShippingCarrier.correosChile);
    expect(service.draft!.trackingNumber, '770000000001');
    expect(service.draft!.cost, 6240);
    expect(service.draft!.admittedAt, DateTime.utc(2026, 10, 13, 20, 43));
    expect(service.checks.map((check) => check.key),
        containsAll(['recipient', 'comuna', 'address']));
    expect(service.operationKey, startsWith('shipment:'));
    expect(result?.trackingNumber, '770000000001');
  });

  testWidgets('a receipt for someone else waits until the person checks it',
      (tester) async {
    final service = _FakeShipments(_reading(recipient: 'PEDRO PABLO SOTO'));
    await _open(tester, service, (_) {});
    await _pickPhoto(tester);

    expect(
      find.textContaining('no coincide con el pedido en destinatario'),
      findsOneWidget,
    );
    expect(_previewButton(tester).onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('shipment-acknowledge')));
    await tester.pumpAndSettle();
    expect(_previewButton(tester).onPressed, isNotNull);
  });

  // 2026-10-13: the whole photo read «77000000099» for a printed
  // «770000000099»; the close-up read it right. Disagreeing readings offer
  // every code and wait for the person.
  testWidgets('a code the readings disagree on is offered to choose',
      (tester) async {
    final service = _FakeShipments({
      ..._reading(),
      'tracking_number': '77000000001',
      'tracking_number_characters': '77000000001'.split(''),
    })
      ..closeUpVotes = const ['770000000001', '770000000001', '77000000001'];
    await _open(tester, service, (_) {});
    await _pickPhoto(tester);

    expect(find.text('Las lecturas no coinciden. ¿Cuál es?'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '77000000001'), findsOneWidget);
    // The close-ups' majority is what the field holds.
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('shipment-tracking')))
          .controller!
          .text,
      '770000000001',
    );
    expect(_previewButton(tester).onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('shipment-acknowledge')));
    await tester.pumpAndSettle();
    expect(_previewButton(tester).onPressed, isNotNull);
  });

  testWidgets('without a receipt the code is typed and nothing is uploaded',
      (tester) async {
    final service = _FakeShipments(_reading());
    await _open(tester, service, (_) {});

    await tester.tap(find.text('No tengo la boleta: escribir los datos'));
    await tester.pumpAndSettle();
    expect(_previewButton(tester).onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('shipment-tracking')),
      'ab 1234 5678 cl',
    );
    await tester.pumpAndSettle();
    await _toPreview(tester);
    await tester.tap(find.byKey(const ValueKey('shipment-save')));
    await tester.pumpAndSettle();

    expect(service.uploads, 0);
    expect(service.receiptPath, isNull);
    expect(service.draft!.trackingNumber, 'AB12345678CL');
  });

  testWidgets('going back from the preview keeps the review as it was',
      (tester) async {
    final service = _FakeShipments(_reading());
    await _open(tester, service, (_) {});
    await _pickPhoto(tester);
    await _toPreview(tester);

    await tester.tap(find.byKey(const ValueKey('shipment-preview-back')));
    await tester.pumpAndSettle();

    expect(find.text('Así le llegará'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('shipment-tracking')))
          .controller!
          .text,
      '770000000001',
    );
    expect(service.draft, isNull);
  });

  testWidgets('a preview that fails says why and nothing is registered',
      (tester) async {
    final service = _FakeShipments(_reading())
      ..previewError = const ShipmentReceiptException(
        'El pedido ya no espera despacho (está shipped).',
      );
    await _open(tester, service, (_) {});
    await _pickPhoto(tester);
    await _toPreview(tester);

    expect(find.text('El pedido ya no espera despacho (está shipped).'),
        findsOneWidget);
    expect(find.text('Así le llegará'), findsNothing);
    expect(service.uploads, 0);
    expect(service.draft, isNull);
  });

  testWidgets('emails in test mode are announced before registering',
      (tester) async {
    final service = _FakeShipments(_reading())..deliveryMode = 'dry_run';
    await _open(tester, service, (_) {});
    await _pickPhoto(tester);
    await _toPreview(tester);

    expect(find.textContaining('modo de prueba'), findsOneWidget);
    expect(find.text('Registrar despacho sin correo'), findsOneWidget);
  });

  testWidgets('an order without an email is registered with no preview',
      (tester) async {
    final service = _FakeShipments(_reading());
    await _open(tester, service, (_) {}, order: _order(email: ''));
    await _pickPhoto(tester);

    expect(find.byKey(const ValueKey('shipment-preview')), findsNothing);
    expect(find.text('Registrar despacho'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('shipment-save')));
    await tester.pumpAndSettle();

    expect(service.previewedDraft, isNull);
    expect(service.draft!.trackingNumber, '770000000001');
  });
}
