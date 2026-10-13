import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:vinabike_erp/modules/website/models/online_order_shipment.dart';
import 'package:vinabike_erp/modules/website/models/website_models.dart';
import 'package:vinabike_erp/modules/website/services/online_order_shipment_service.dart';

// Invented data only: the receipt reading mirrors the layout of a Correos de
// Chile admission receipt (2026-10-13), never a real customer.
OnlineOrder _order({
  String name = 'Camila Andrea Fuentes',
  String? city = 'Ñuñoa',
  String? address = 'Pasaje Los Aromos 456',
}) {
  final createdAt = DateTime(2026, 10, 12, 15, 52);
  return OnlineOrder(
    id: '9e500000-0000-4000-8000-000000000031',
    tenantId: '9e500000-0000-4000-8000-000000000001',
    orderNumber: 'WEB-26-00031',
    customerEmail: 'cliente@example.invalid',
    customerName: name,
    deliveryType: 'shipping',
    shippingAddressLine1: address,
    shippingCity: city,
    subtotal: 9244,
    taxAmount: 1756,
    shippingCost: 6990,
    discountAmount: 0,
    total: 17990,
    status: 'confirmed',
    paymentStatus: 'paid',
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}

Map<String, dynamic> _receipt({
  String recipient = 'CAMILA ANDREA FUENTES',
  String rut = '11.111.111-1',
  String comuna = 'NUNOA',
  String address = 'PASAJE LOS AROMOS 456',
}) =>
    {
      'is_shipping_receipt': true,
      'carrier_code': 'correos_chile',
      'carrier_name': 'Correos de Chile',
      'service': 'PAQUETE EXPRESS AM',
      'tracking_number': '7700 0000 0001',
      'admitted_at': '2026-10-13T17:43',
      'branch': 'SUCURSAL INVENTADA',
      'total_paid': '6.240',
      'recipient_name': recipient,
      'recipient_rut': rut,
      'recipient_comuna': comuna,
      'recipient_address': address,
      'confidence': 0.93,
    };

void main() {
  group('ShipmentReceiptReading', () {
    test('reads the carrier, the code without spaces and the paid amount', () {
      final reading = ShipmentReceiptReading.fromJson(_receipt());
      expect(reading.carrier, ShippingCarrier.correosChile);
      expect(reading.trackingNumber, '770000000001');
      expect(reading.cost, 6240);
      expect(reading.service, 'PAQUETE EXPRESS AM');
      expect(reading.isShippingReceipt, isTrue);
    });

    test('the admission time printed in Chile becomes its UTC instant', () {
      final reading = ShipmentReceiptReading.fromJson(_receipt());
      // October is daylight time in Chile (UTC−3).
      expect(reading.admittedAt, DateTime.utc(2026, 10, 13, 20, 43));
      expect(parseShopClock('13/10/2026 17:43'),
          DateTime.utc(2026, 10, 13, 20, 43));
      expect(parseShopClock('no es fecha'), isNull);
    });

    test('a carrier name the AI wrote by hand still finds its carrier', () {
      expect(ShippingCarrier.fromName('CHILEXPRESS S.A.').code, 'chilexpress');
      expect(ShippingCarrier.fromName('Correos Chile').code, 'correos_chile');
      expect(
          ShippingCarrier.fromName('Transportes Pérez'), ShippingCarrier.other);
    });

    test('what is kept never includes a sender field', () {
      final reading = ShipmentReceiptReading.fromJson({
        ..._receipt(),
        'sender_name': 'Persona Remitente',
        'sender_rut': '22.222.222-2',
      });
      final kept = reading.toExtracted();
      expect(kept.keys.where((key) => key.startsWith('sender')), isEmpty);
      expect(kept['tracking_number'], '770000000001');
    });
  });

  group('checkReceiptAgainstOrder', () {
    test('a receipt for this order matches on every line', () {
      final checks = checkReceiptAgainstOrder(
        order: _order(),
        reading: ShipmentReceiptReading.fromJson(_receipt()),
        customerRut: '11111111-1',
      );
      expect(
        {for (final check in checks) check.key: check.status},
        {
          'recipient': ShipmentCheckStatus.match,
          'rut': ShipmentCheckStatus.match,
          'comuna': ShipmentCheckStatus.match,
          'address': ShipmentCheckStatus.match,
        },
      );
    });

    test('another customer\'s receipt is caught', () {
      final checks = checkReceiptAgainstOrder(
        order: _order(),
        reading: ShipmentReceiptReading.fromJson(_receipt(
          recipient: 'PEDRO PABLO SOTO',
          rut: '33.333.333-3',
          comuna: 'MAIPU',
          address: 'AVENIDA INVENTADA 1200',
        )),
        customerRut: '11111111-1',
      );
      expect(
        checks.every((check) => check.status == ShipmentCheckStatus.mismatch),
        isTrue,
      );
    });

    test('an order without a RUT cannot contradict the receipt', () {
      final checks = checkReceiptAgainstOrder(
        order: _order(),
        reading: ShipmentReceiptReading.fromJson(_receipt()),
      );
      expect(
        checks.singleWhere((check) => check.key == 'rut').status,
        ShipmentCheckStatus.unknown,
      );
    });

    test('a different house number on the same street is a mismatch', () {
      final checks = checkReceiptAgainstOrder(
        order: _order(),
        reading: ShipmentReceiptReading.fromJson(
          _receipt(address: 'PASAJE LOS AROMOS 465'),
        ),
      );
      expect(
        checks.singleWhere((check) => check.key == 'address').status,
        ShipmentCheckStatus.mismatch,
      );
    });

    test('the order number written on the receipt is compared', () {
      final checks = checkReceiptAgainstOrder(
        order: _order(),
        reading: ShipmentReceiptReading.fromJson({
          ..._receipt(),
          'order_reference': 'Pedido web 00031',
        }),
      );
      expect(
        checks.singleWhere((check) => check.key == 'order').status,
        ShipmentCheckStatus.match,
      );
    });
  });

  group('reading the code from a close-up', () {
    ShipmentReceiptReading wholePhoto(String code) =>
        ShipmentReceiptReading.fromJson({
          ..._receipt(),
          'tracking_number': code,
          'tracking_number_characters': code.split(''),
        });

    test('agreeing close-ups verify the code, whatever the whole photo said',
        () {
      final reading = wholePhoto('77000000099').withCloseUp(
        votes: ['770000000099', '770000000099', null],
        closeUp: null,
      );
      expect(reading.trackingNumber, '770000000099');
      expect(reading.trackingVerified, isTrue);
      expect(reading.trackingCandidates, isEmpty);
    });

    test('a disagreeing close-up keeps the majority and offers the rest', () {
      final reading = wholePhoto('77000000099').withCloseUp(
        votes: ['770000000099', '77000000099', '770000000099'],
        closeUp: null,
      );
      expect(reading.trackingNumber, '770000000099');
      expect(reading.trackingVerified, isFalse);
      expect(reading.trackingCandidates,
          containsAll(['770000000099', '77000000099']));
    });

    test('one close-up alone, or none, never verifies', () {
      expect(
        wholePhoto('770000000099').withCloseUp(
            votes: ['770000000099', null, null],
            closeUp: null).trackingVerified,
        isFalse,
      );
      final none =
          wholePhoto('770000000099').withCloseUp(votes: [], closeUp: null);
      expect(none.trackingVerified, isFalse);
      expect(none.trackingNumber, '770000000099');
    });

    test('a close-up counts only when its two spellings agree', () {
      expect(
        focusedTrackingCode({
          'characters': '770000000099'.split(''),
          'length': 11,
          'groups_of_three': '770 000 000 099',
        }),
        '770000000099',
      );
      expect(
        focusedTrackingCode({
          'characters': '770000000099'.split(''),
          'groups_of_three': '770 000 000 99',
        }),
        isNull,
      );
    });

    test('the close-up is cut around the box and enlarged', () {
      final photo = img.Image(width: 400, height: 600);
      final bytes = Uint8List.fromList(img.encodeJpg(photo));
      final crop = cropTrackingCode(
        (bytes: bytes, box: const <num>[300, 200, 340, 800]),
      );
      expect(crop, isNotNull);
      final decoded = img.decodePng(crop!)!;
      expect(decoded.width, greaterThanOrEqualTo(900));
      expect(
        cropTrackingCode((bytes: bytes, box: const <num>[340, 200, 300, 800])),
        isNull,
      );
      expect(cropTrackingCode((bytes: bytes, box: const <num>[])), isNull);
    });
  });

  test('tracking codes are compact and plausible', () {
    expect(normalizeTrackingNumber(' ab 123 456 cl '), 'AB123456CL');
    expect(isPlausibleTrackingNumber('7700 0000 0001'), isTrue);
    expect(isPlausibleTrackingNumber('123'), isFalse);
    expect(isPlausibleTrackingNumber('770-000/01'), isFalse);
  });

  test('a carrier outside the list is registered by its typed name', () {
    const draft = ShipmentDraft(
      carrier: ShippingCarrier.other,
      carrierName: ' Transportes Pérez ',
      trackingNumber: 'TP000123',
    );
    expect(draft.carrierLabel, 'Transportes Pérez');
    const listed = ShipmentDraft(
      carrier: ShippingCarrier.correosChile,
      carrierName: 'ignored',
      trackingNumber: '770000000001',
    );
    expect(listed.carrierLabel, 'Correos de Chile');
  });
}
