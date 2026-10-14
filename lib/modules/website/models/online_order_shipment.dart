import 'dart:typed_data';

import '../../../shared/utils/shop_time.dart';
import 'website_models.dart';

/// A Chilean carrier the shop ships with, and the public page where a
/// customer follows a package. None of these pages takes the code in the
/// link (checked 2026-10-13), so the email tells the customer to paste it.
class ShippingCarrier {
  const ShippingCarrier(this.code, this.label, this.trackingUrl);

  final String code;
  final String label;
  final String? trackingUrl;

  static const correosChile = ShippingCarrier(
    'correos_chile',
    'Correos de Chile',
    'https://www.correos.cl/web/guest/seguimiento-en-linea',
  );
  static const other = ShippingCarrier('other', 'Otro transportista', null);

  static const all = <ShippingCarrier>[
    correosChile,
    ShippingCarrier(
        'chilexpress', 'Chilexpress', 'https://www.chilexpress.cl/'),
    ShippingCarrier('starken', 'Starken', 'https://www.starken.cl/seguimiento'),
    ShippingCarrier(
      'blue_express',
      'Blue Express',
      'https://www.blue.cl/enviar/seguimiento',
    ),
    ShippingCarrier('pullman_cargo', 'Pullman Cargo', null),
    other,
  ];

  static ShippingCarrier byCode(String? code) => all.firstWhere(
        (carrier) => carrier.code == code?.trim().toLowerCase(),
        orElse: () => other,
      );

  /// The carrier a free-text name refers to («CORREOS CHILE», «chilexpress»).
  static ShippingCarrier fromName(String? name) {
    final key = _plain(name ?? '').replaceAll(' ', '');
    if (key.isEmpty) return other;
    if (key.contains('correos')) return correosChile;
    for (final carrier in all) {
      final label = _plain(carrier.label).replaceAll(' ', '');
      if (carrier != other && (key.contains(label) || label.contains(key))) {
        return carrier;
      }
    }
    if (key.contains('blue')) return byCode('blue_express');
    return other;
  }
}

/// What the AI read on the photo of a shipping receipt. Every field is a
/// reading, not a fact: the dialog shows it against the order before anything
/// is recorded.
class ShipmentReceiptReading {
  const ShipmentReceiptReading({
    required this.isShippingReceipt,
    required this.carrier,
    this.trackingVerified = false,
    this.trackingCandidates = const [],
    this.trackingCloseUp,
    this.carrierName,
    this.service,
    this.trackingNumber,
    this.admittedAt,
    this.branch,
    this.cost,
    this.recipientName,
    this.recipientRut,
    this.recipientAddress,
    this.recipientComuna,
    this.orderReference,
    this.documentType,
    this.documentNumber,
    this.confidence,
    this.raw = const {},
  });

  final bool isShippingReceipt;
  final ShippingCarrier carrier;
  final String? carrierName;
  final String? service;
  final String? trackingNumber;

  /// Whether the close-ups of the code agreed. A run of zeros is where a
  /// reading slips (2026-10-13: the whole photo gave «77000000099» for a
  /// printed «770000000099» most times), and the customer gets that code.
  final bool trackingVerified;

  /// The different codes the readings gave, when they disagree.
  final List<String> trackingCandidates;

  /// The code as printed, cropped and enlarged from the photo.
  final Uint8List? trackingCloseUp;

  /// UTC instant of the admission, from the shop-clock time on the receipt.
  final DateTime? admittedAt;
  final String? branch;
  final double? cost;
  final String? recipientName;
  final String? recipientRut;
  final String? recipientAddress;
  final String? recipientComuna;
  final String? orderReference;

  /// The tax document the receipt is, as an expense names it: «receipt» for
  /// a boleta (all of it is expense), «invoice» for a factura (its IVA is a
  /// credit). Null when the receipt does not say.
  final String? documentType;

  /// The folio of that boleta or factura, never the tracking code.
  final String? documentNumber;
  final double? confidence;
  final Map<String, dynamic> raw;

  factory ShipmentReceiptReading.fromJson(Map<String, dynamic> json) {
    String? textOf(String key) {
      final value = json[key]?.toString().trim() ?? '';
      return value.isEmpty || value.toLowerCase() == 'null' ? null : value;
    }

    double? numberOf(String key) {
      final value = json[key];
      if (value is num) return value.toDouble();
      final digits = value?.toString().replaceAll(RegExp(r'[^0-9]'), '') ?? '';
      return digits.isEmpty ? null : double.parse(digits);
    }

    final carrierCode = textOf('carrier_code');
    final carrierName = textOf('carrier_name');
    var carrier = ShippingCarrier.byCode(carrierCode);
    if (carrier == ShippingCarrier.other) {
      carrier = ShippingCarrier.fromName(carrierName);
    }
    final rawConfidence = json['confidence'];
    final documentType = switch (_plain(textOf('document_type') ?? '')) {
      'boleta' => 'receipt',
      'factura' => 'invoice',
      _ => null,
    };
    final whole = normalizeTrackingNumber(textOf('tracking_number'));
    final rawCharacters = json['tracking_number_characters'];
    final spelled = rawCharacters is List
        ? normalizeTrackingNumber(rawCharacters.join())
        : null;
    return ShipmentReceiptReading(
      isShippingReceipt: json['is_shipping_receipt'] != false,
      carrier: carrier,
      carrierName: carrierName,
      service: textOf('service'),
      // The character-by-character reading wins when they disagree: it is
      // the one that counts repeated digits.
      trackingNumber: spelled ?? whole,
      admittedAt: parseShopClock(textOf('admitted_at')),
      branch: textOf('branch'),
      cost: numberOf('total_paid'),
      recipientName: textOf('recipient_name'),
      recipientRut: textOf('recipient_rut'),
      recipientAddress: textOf('recipient_address'),
      recipientComuna: textOf('recipient_comuna'),
      orderReference: textOf('order_reference'),
      documentType: documentType,
      documentNumber: documentType == null ? null : textOf('document_number'),
      confidence: rawConfidence is num ? rawConfidence.toDouble() : null,
      raw: Map<String, dynamic>.from(json),
    );
  }

  /// The reading after the close-ups of the code. The close-up is the one
  /// that sees the characters big: the code most of its readings gave wins,
  /// and it is verified only when at least two read it and none disagreed.
  /// Otherwise every code any reading gave is offered to choose from.
  ShipmentReceiptReading withCloseUp({
    required List<String?> votes,
    required Uint8List? closeUp,
  }) {
    final whole = normalizeTrackingNumber(raw['tracking_number']?.toString());
    final rawCharacters = raw['tracking_number_characters'];
    final spelled = rawCharacters is List
        ? normalizeTrackingNumber(rawCharacters.join())
        : null;
    final valid = votes.whereType<String>().toList(growable: false);
    final counts = <String, int>{};
    for (final vote in valid) {
      counts[vote] = (counts[vote] ?? 0) + 1;
    }
    String? focused;
    for (final entry in counts.entries) {
      if (focused == null || entry.value > counts[focused]!) {
        focused = entry.key;
      }
    }
    final verified = valid.length >= 2 && counts.length == 1;
    final candidates = <String>{
      ...valid,
      if (spelled != null) spelled,
      if (whole != null) whole,
    }.toList(growable: false);
    return ShipmentReceiptReading(
      isShippingReceipt: isShippingReceipt,
      carrier: carrier,
      carrierName: carrierName,
      service: service,
      trackingNumber: focused ?? trackingNumber,
      trackingVerified: verified,
      trackingCandidates:
          !verified && candidates.length > 1 ? candidates : const [],
      trackingCloseUp: closeUp,
      admittedAt: admittedAt,
      branch: branch,
      cost: cost,
      recipientName: recipientName,
      recipientRut: recipientRut,
      recipientAddress: recipientAddress,
      recipientComuna: recipientComuna,
      orderReference: orderReference,
      documentType: documentType,
      documentNumber: documentNumber,
      confidence: confidence,
      raw: raw,
    );
  }

  /// What is kept with the shipment: the reading without the sender's data,
  /// which the prompt never asks for.
  Map<String, dynamic> toExtracted() => {
        'is_shipping_receipt': isShippingReceipt,
        'carrier_code': carrier.code,
        if (carrierName != null) 'carrier_name': carrierName,
        if (service != null) 'service': service,
        if (trackingNumber != null) 'tracking_number': trackingNumber,
        'tracking_verified': trackingVerified,
        if (trackingCandidates.isNotEmpty)
          'tracking_candidates': trackingCandidates,
        if (admittedAt != null) 'admitted_at': admittedAt!.toIso8601String(),
        if (branch != null) 'branch': branch,
        if (cost != null) 'total_paid': cost,
        if (recipientName != null) 'recipient_name': recipientName,
        if (recipientRut != null) 'recipient_rut': recipientRut,
        if (recipientAddress != null) 'recipient_address': recipientAddress,
        if (recipientComuna != null) 'recipient_comuna': recipientComuna,
        if (orderReference != null) 'order_reference': orderReference,
        if (documentType != null) 'document_type': documentType,
        if (documentNumber != null) 'document_number': documentNumber,
        if (confidence != null) 'confidence': confidence,
      };
}

/// A tracking code as carriers print it, without the spaces people add.
String? normalizeTrackingNumber(String? value) {
  final compact = (value ?? '').replaceAll(RegExp(r'\s'), '').toUpperCase();
  return compact.isEmpty ? null : compact;
}

/// A tracking code that looks like one: letters, digits and dashes, 6 to 40.
bool isPlausibleTrackingNumber(String? value) =>
    RegExp(r'^[A-Z0-9-]{6,40}$').hasMatch(normalizeTrackingNumber(value) ?? '');

/// «2026-10-13T17:43» or «13/10/2026 17:43» on the shop's clock, as UTC.
DateTime? parseShopClock(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{1,2}):(\d{2}))?')
      .firstMatch(text);
  final chilean =
      RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{4})(?:\s+(\d{1,2}):(\d{2}))?')
          .firstMatch(text);
  final int year;
  final int month;
  final int day;
  final String? hour;
  final String? minute;
  if (iso != null) {
    year = int.parse(iso.group(1)!);
    month = int.parse(iso.group(2)!);
    day = int.parse(iso.group(3)!);
    hour = iso.group(4);
    minute = iso.group(5);
  } else if (chilean != null) {
    day = int.parse(chilean.group(1)!);
    month = int.parse(chilean.group(2)!);
    year = int.parse(chilean.group(3)!);
    hour = chilean.group(4);
    minute = chilean.group(5);
  } else {
    return null;
  }
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return shopClockToUtc(
    year,
    month,
    day,
    int.tryParse(hour ?? '') ?? 0,
    int.tryParse(minute ?? '') ?? 0,
  );
}

/// The admission a receipt can really have: not before the order existed
/// and not in the future, a day either way. A year misread (2026-10-13: a
/// receipt of that day read as «13/10/2020») is taken to this year or the
/// last when its day and hour fit; otherwise it is dropped. `misread` is
/// what the AI read when it was changed, to say so.
({DateTime? at, DateTime? misread}) plausibleAdmission(
  DateTime? read, {
  required DateTime orderCreatedAt,
  DateTime? now,
}) {
  if (read == null) return (at: null, misread: null);
  final today = (now ?? DateTime.now()).toUtc();
  final earliest = orderCreatedAt.toUtc().subtract(const Duration(days: 1));
  final latest = today.add(const Duration(days: 1));
  bool fits(DateTime value) =>
      !value.isBefore(earliest) && !value.isAfter(latest);
  if (fits(read)) return (at: read, misread: null);
  final clock = shopTime(read);
  final thisYear = shopTime(today).year;
  for (final year in [thisYear, thisYear - 1]) {
    final candidate = shopClockToUtc(
      year,
      clock.month,
      clock.day,
      clock.hour,
      clock.minute,
    );
    if (shopTime(candidate).day == clock.day && fits(candidate)) {
      return (at: candidate, misread: read);
    }
  }
  return (at: null, misread: read);
}

enum ShipmentCheckStatus { match, mismatch, unknown }

/// One thing the receipt says compared with the order.
class ShipmentReceiptCheck {
  const ShipmentReceiptCheck({
    required this.key,
    required this.label,
    required this.status,
    required this.onReceipt,
    this.onOrder,
  });

  final String key;
  final String label;
  final ShipmentCheckStatus status;
  final String onReceipt;
  final String? onOrder;

  Map<String, dynamic> toJson() => {
        'status': status.name,
        'receipt': onReceipt,
        if (onOrder != null) 'order': onOrder,
      };
}

/// The receipt against the order it is registered on: who it goes to, their
/// RUT, the comuna, the street and number, and the order number when the
/// receipt carries one. A receipt for another customer is the mistake this
/// catches (two packages leave the same afternoon).
List<ShipmentReceiptCheck> checkReceiptAgainstOrder({
  required OnlineOrder order,
  required ShipmentReceiptReading reading,
  String? customerRut,
}) {
  final checks = <ShipmentReceiptCheck>[];

  final receiptName = reading.recipientName;
  if (receiptName != null) {
    final a = _tokens(receiptName);
    final b = _tokens(order.customerName);
    final shared = a.intersection(b).length;
    final needed = [a.length, b.length, 2].reduce((x, y) => x < y ? x : y);
    checks.add(ShipmentReceiptCheck(
      key: 'recipient',
      label: 'Destinatario',
      status: b.isEmpty
          ? ShipmentCheckStatus.unknown
          : shared >= needed && needed > 0
              ? ShipmentCheckStatus.match
              : ShipmentCheckStatus.mismatch,
      onReceipt: receiptName,
      onOrder: order.customerName,
    ));
  }

  final receiptRut = reading.recipientRut;
  if (receiptRut != null) {
    final known = customerRut?.trim() ?? '';
    checks.add(ShipmentReceiptCheck(
      key: 'rut',
      label: 'RUT',
      status: known.isEmpty
          ? ShipmentCheckStatus.unknown
          : _rutKey(known) == _rutKey(receiptRut)
              ? ShipmentCheckStatus.match
              : ShipmentCheckStatus.mismatch,
      onReceipt: receiptRut,
      onOrder: known.isEmpty ? null : known,
    ));
  }

  final receiptComuna = reading.recipientComuna;
  if (receiptComuna != null) {
    final city = order.shippingCity?.trim() ?? '';
    final where = city.isNotEmpty
        ? city
        : [order.shippingAddressLine1, order.customerAddress]
            .whereType<String>()
            .join(' ');
    final comuna = _plain(receiptComuna);
    final orderPlace = _plain(where);
    final same = orderPlace == comuna ||
        (city.isEmpty
            ? ' $orderPlace '.contains(' $comuna ')
            : orderPlace.contains(comuna) || comuna.contains(orderPlace));
    checks.add(ShipmentReceiptCheck(
      key: 'comuna',
      label: 'Comuna',
      // An address typed without its comuna says nothing against the receipt.
      status: same
          ? ShipmentCheckStatus.match
          : orderPlace.isEmpty || city.isEmpty
              ? ShipmentCheckStatus.unknown
              : ShipmentCheckStatus.mismatch,
      onReceipt: receiptComuna,
      onOrder: city.isEmpty ? null : city,
    ));
  }

  final receiptAddress = reading.recipientAddress;
  if (receiptAddress != null) {
    final orderAddress = (order.shippingAddressLine1?.trim().isNotEmpty == true
            ? order.shippingAddressLine1
            : order.customerAddress)
        ?.trim();
    ShipmentCheckStatus status = ShipmentCheckStatus.unknown;
    if (orderAddress != null && orderAddress.isNotEmpty) {
      final receiptNumbers = _numbers(receiptAddress);
      final orderNumbers = _numbers(orderAddress);
      final sameNumber = receiptNumbers.intersection(orderNumbers).isNotEmpty;
      final sameStreet = _streetTokens(receiptAddress)
          .intersection(_streetTokens(orderAddress))
          .isNotEmpty;
      status = sameNumber && sameStreet
          ? ShipmentCheckStatus.match
          : ShipmentCheckStatus.mismatch;
    }
    checks.add(ShipmentReceiptCheck(
      key: 'address',
      label: 'Dirección',
      status: status,
      onReceipt: receiptAddress,
      onOrder: orderAddress,
    ));
  }

  final reference = reading.orderReference;
  if (reference != null) {
    final number = _plain(order.orderNumber).replaceAll(' ', '');
    // The serial after the last separator («00031» of «WEB-26-00031»).
    final serial =
        RegExp(r'(\d+)\s*$').firstMatch(order.orderNumber)?.group(1) ?? number;
    final written = _plain(reference).replaceAll(' ', '');
    checks.add(ShipmentReceiptCheck(
      key: 'order',
      label: 'Pedido',
      status: written.contains(number) ||
              (serial.length >= 4 && written.contains(serial))
          ? ShipmentCheckStatus.match
          : ShipmentCheckStatus.mismatch,
      onReceipt: reference,
      onOrder: order.orderNumber,
    ));
  }

  return checks;
}

/// A shipping receipt registered on an order (`online_order_shipments`).
class OnlineOrderShipment {
  const OnlineOrderShipment({
    required this.id,
    required this.orderId,
    required this.carrier,
    required this.createdAt,
    this.carrierCode,
    this.service,
    this.trackingNumber,
    this.trackingUrl,
    this.admittedAt,
    this.branch,
    this.cost,
    this.receiptPath,
    this.checks = const {},
    this.expenseId,
    this.expenseNumber,
    this.documentType,
    this.documentNumber,
  });

  final String id;
  final String orderId;
  final String carrier;
  final String? carrierCode;
  final String? service;
  final String? trackingNumber;
  final String? trackingUrl;
  final DateTime? admittedAt;
  final String? branch;
  final double? cost;
  final String? receiptPath;
  final Map<String, dynamic> checks;
  final DateTime createdAt;

  /// The expense of what the carrier charged, when it was registered.
  final String? expenseId;
  final String? expenseNumber;

  /// The boleta or factura the AI read on the receipt («receipt» or
  /// «invoice») and its folio.
  final String? documentType;
  final String? documentNumber;

  factory OnlineOrderShipment.fromJson(Map<String, dynamic> json) {
    DateTime? dateOf(String key) {
      final value = json[key]?.toString();
      return value == null ? null : DateTime.tryParse(value);
    }

    final rawCost = json['cost'];
    final rawChecks = json['checks'];
    final expense = json['expense'];
    return OnlineOrderShipment(
      id: json['id'].toString(),
      orderId: json['order_id'].toString(),
      carrier: json['carrier']?.toString() ?? '',
      carrierCode: json['carrier_code']?.toString(),
      service: json['service']?.toString(),
      trackingNumber: json['tracking_number']?.toString(),
      trackingUrl: json['tracking_url']?.toString(),
      admittedAt: dateOf('admitted_at'),
      branch: json['branch']?.toString(),
      cost: rawCost is num ? rawCost.toDouble() : double.tryParse('$rawCost'),
      receiptPath: json['receipt_path']?.toString(),
      checks:
          rawChecks is Map ? Map<String, dynamic>.from(rawChecks) : const {},
      createdAt: dateOf('created_at') ?? DateTime.now().toUtc(),
      expenseId: json['expense_id']?.toString(),
      expenseNumber:
          (expense is Map ? expense['expense_number'] : null)?.toString() ??
              json['expense_number']?.toString(),
      documentType: switch (json['document_type']?.toString()) {
        'receipt' => 'receipt',
        'invoice' => 'invoice',
        _ => null,
      },
      documentNumber: json['document_number']?.toString(),
    );
  }
}

const _accents = {
  'á': 'a',
  'é': 'e',
  'í': 'i',
  'ó': 'o',
  'ú': 'u',
  'ü': 'u',
  'ñ': 'n',
};

String _plain(String value) {
  final lower = value.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final char = String.fromCharCode(rune);
    buffer.write(_accents[char] ?? char);
  }
  return buffer
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

Set<String> _tokens(String value) =>
    _plain(value).split(' ').where((token) => token.length >= 2).toSet();

String _rutKey(String value) =>
    value.toUpperCase().replaceAll(RegExp(r'[^0-9K]'), '');

Set<String> _numbers(String value) =>
    RegExp(r'\d+').allMatches(value).map((match) => match.group(0)!).toSet();

const _streetWords = {
  'av',
  'avda',
  'avenida',
  'calle',
  'pasaje',
  'psje',
  'pje',
  'camino',
  'numero',
  'nro',
  'no',
  'depto',
  'dpto',
  'casa',
  'block',
  'de',
  'del',
  'la',
  'las',
  'los',
  'el',
};

Set<String> _streetTokens(String value) => _tokens(value)
    .where((token) =>
        !_streetWords.contains(token) && !RegExp(r'^\d+$').hasMatch(token))
    .toSet();
