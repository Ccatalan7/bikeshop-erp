import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../modules/website/models/public_order_access.dart';
import '../../shared/utils/web_url.dart' as web_url;

abstract interface class CheckoutSessionStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class BrowserCheckoutSessionStorage implements CheckoutSessionStorage {
  const BrowserCheckoutSessionStorage();

  @override
  Future<String?> read(String key) async =>
      web_url.getSessionStorageValueStrict(key);

  @override
  Future<void> write(String key, String value) async {
    web_url.setSessionStorageValueStrict(key, value);
  }
}

class MemoryCheckoutSessionStorage implements CheckoutSessionStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    if (value.isEmpty) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }
}

/// Native checkout storage backed by the platform's protected credential
/// vault.
///
/// The snapshot contains customer PII and an order-view bearer token, so plain
/// preferences are not an acceptable crash-recovery backend. Web deliberately
/// keeps its separate same-origin, tab-lifetime sessionStorage contract.
class SecureCheckoutSessionStorage implements CheckoutSessionStorage {
  const SecureCheckoutSessionStorage();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) {
    if (value.isEmpty) {
      return _storage.delete(key: key);
    }
    return _storage.write(key: key, value: value);
  }
}

@immutable
class CheckoutHandoffSnapshot {
  const CheckoutHandoffSnapshot({
    required this.paymentMethod,
    required this.deliveryType,
  });

  final String paymentMethod;
  final String deliveryType;

  Map<String, dynamic> toJson() => {
        'payment_method': paymentMethod,
        'delivery_type': deliveryType,
      };

  static CheckoutHandoffSnapshot? fromJson(Object? value) {
    if (value is! Map) return null;
    final json = Map<String, dynamic>.from(value);
    final paymentMethod = json['payment_method']?.toString() ?? '';
    final deliveryType = json['delivery_type']?.toString() ?? '';
    if (!const {'mercadopago', 'transfer'}.contains(paymentMethod) ||
        !const {'shipping', 'pickup'}.contains(deliveryType)) {
      return null;
    }
    return CheckoutHandoffSnapshot(
      paymentMethod: paymentMethod,
      deliveryType: deliveryType,
    );
  }
}

enum CheckoutCartConsumptionStatus {
  consuming,
  preserved,
  applied,
}

enum CheckoutCartOutcomeState {
  preserved,
  applied,
}

@immutable
class CheckoutCartOutcome {
  const CheckoutCartOutcome({
    required this.tenantId,
    required this.orderId,
    required this.state,
    required this.finalizedAt,
    this.reason,
    this.acknowledgedAt,
  });

  final String tenantId;
  final String orderId;
  final CheckoutCartOutcomeState state;
  final DateTime finalizedAt;
  final String? reason;
  final DateTime? acknowledgedAt;

  bool get showsWarning =>
      state == CheckoutCartOutcomeState.preserved && acknowledgedAt == null;

  CheckoutCartOutcome acknowledge(DateTime value) => CheckoutCartOutcome(
        tenantId: tenantId,
        orderId: orderId,
        state: state,
        finalizedAt: finalizedAt,
        reason: reason,
        acknowledgedAt: value.toUtc(),
      );

  Map<String, dynamic> toJson() => {
        'v': 2,
        'tenant_id': tenantId,
        'order_id': orderId,
        'state': state.name,
        'finalized_at': finalizedAt.toUtc().toIso8601String(),
        if (reason != null) 'reason': reason,
        if (acknowledgedAt != null)
          'acknowledged_at': acknowledgedAt!.toUtc().toIso8601String(),
      };
}

typedef CheckoutCartConsumer = Future<bool> Function(
  CheckoutSessionSnapshot snapshot,
);

@immutable
class CheckoutSessionSnapshot {
  const CheckoutSessionSnapshot._({
    required this.tenantId,
    required this.savedAt,
    required this.idempotencyKey,
    required this.orderData,
    required this.orderItems,
    required this.handoff,
    required this.cartRevision,
    required this.receipt,
    required this.cartConsumptionClosedAt,
    required this.cartConsumptionStatus,
    required this.cartConsumptionClaimId,
  });

  static const int schemaVersion = 1;
  static final RegExp _uuidV4Pattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  final String tenantId;
  final DateTime savedAt;
  final String idempotencyKey;
  final Map<String, dynamic> orderData;
  final List<Map<String, dynamic>> orderItems;
  final CheckoutHandoffSnapshot handoff;
  final String? cartRevision;
  final PublicOrderCheckoutAccess? receipt;
  final DateTime? cartConsumptionClosedAt;
  final CheckoutCartConsumptionStatus? cartConsumptionStatus;
  final String? cartConsumptionClaimId;

  factory CheckoutSessionSnapshot.create({
    required String tenantId,
    required DateTime savedAt,
    required String idempotencyKey,
    required Map<String, dynamic> orderData,
    required List<Map<String, dynamic>> orderItems,
    required CheckoutHandoffSnapshot handoff,
    required String cartRevision,
  }) {
    if (cartRevision.trim().isEmpty) {
      throw const FormatException(
        'La revisión durable del carrito es obligatoria.',
      );
    }
    final snapshot = _parse(
      {
        'v': schemaVersion,
        'tenant_id': tenantId,
        'saved_at': savedAt.toUtc().toIso8601String(),
        'idempotency_key': idempotencyKey,
        'order_data': orderData,
        'order_items': orderItems,
        'handoff': handoff.toJson(),
        'cart_revision': cartRevision,
      },
      expectedTenantId: tenantId,
    );
    if (snapshot == null) {
      throw const FormatException('Estado durable de checkout inválido');
    }
    return snapshot;
  }

  CheckoutSessionSnapshot withReceipt(PublicOrderCheckoutAccess value) {
    return CheckoutSessionSnapshot._(
      tenantId: tenantId,
      savedAt: savedAt,
      idempotencyKey: idempotencyKey,
      orderData: orderData,
      orderItems: orderItems,
      handoff: handoff,
      cartRevision: cartRevision,
      receipt: value,
      cartConsumptionClosedAt: cartConsumptionClosedAt,
      cartConsumptionStatus: cartConsumptionStatus,
      cartConsumptionClaimId: cartConsumptionClaimId,
    );
  }

  CheckoutSessionSnapshot claimCartConsumption({
    required String claimId,
    required DateTime startedAt,
  }) {
    final normalizedClaimId = claimId.trim();
    if (receipt == null ||
        cartConsumptionStatus != null ||
        normalizedClaimId.isEmpty) {
      throw StateError('No se puede reclamar este consumo del carrito.');
    }
    return CheckoutSessionSnapshot._(
      tenantId: tenantId,
      savedAt: savedAt,
      idempotencyKey: idempotencyKey,
      orderData: orderData,
      orderItems: orderItems,
      handoff: handoff,
      cartRevision: cartRevision,
      receipt: receipt,
      cartConsumptionClosedAt: startedAt.toUtc(),
      cartConsumptionStatus: CheckoutCartConsumptionStatus.consuming,
      cartConsumptionClaimId: normalizedClaimId,
    );
  }

  /// Closes cart subtraction before touching the cart.
  ///
  /// `preserved` is the safe durable default: after this boundary the
  /// subtraction must never be retried, even after a crash. It is promoted to
  /// `applied` only after the compare-before-write operation succeeds.
  CheckoutSessionSnapshot closeCartConsumption(DateTime closedAt) {
    if (receipt == null) {
      throw StateError(
        'No se puede cerrar el consumo antes de guardar el recibo.',
      );
    }
    return CheckoutSessionSnapshot._(
      tenantId: tenantId,
      savedAt: savedAt,
      idempotencyKey: idempotencyKey,
      orderData: orderData,
      orderItems: orderItems,
      handoff: handoff,
      cartRevision: cartRevision,
      receipt: receipt,
      cartConsumptionClosedAt: closedAt.toUtc(),
      cartConsumptionStatus: CheckoutCartConsumptionStatus.preserved,
      cartConsumptionClaimId: cartConsumptionClaimId,
    );
  }

  CheckoutSessionSnapshot markCartConsumptionPreserved() {
    if (receipt == null || cartConsumptionStatus == null) {
      throw StateError(
        'No se puede preservar un consumo que no fue reclamado.',
      );
    }
    return CheckoutSessionSnapshot._(
      tenantId: tenantId,
      savedAt: savedAt,
      idempotencyKey: idempotencyKey,
      orderData: orderData,
      orderItems: orderItems,
      handoff: handoff,
      cartRevision: cartRevision,
      receipt: receipt,
      cartConsumptionClosedAt: cartConsumptionClosedAt,
      cartConsumptionStatus: CheckoutCartConsumptionStatus.preserved,
      cartConsumptionClaimId: cartConsumptionClaimId,
    );
  }

  CheckoutSessionSnapshot markCartConsumptionApplied() {
    if (receipt == null ||
        cartConsumptionClosedAt == null ||
        cartConsumptionStatus == null) {
      throw StateError(
        'No se puede confirmar un consumo que no fue cerrado.',
      );
    }
    return CheckoutSessionSnapshot._(
      tenantId: tenantId,
      savedAt: savedAt,
      idempotencyKey: idempotencyKey,
      orderData: orderData,
      orderItems: orderItems,
      handoff: handoff,
      cartRevision: cartRevision,
      receipt: receipt,
      cartConsumptionClosedAt: cartConsumptionClosedAt,
      cartConsumptionStatus: CheckoutCartConsumptionStatus.applied,
      cartConsumptionClaimId: cartConsumptionClaimId,
    );
  }

  Map<String, dynamic> toJson() => {
        'v': schemaVersion,
        'tenant_id': tenantId,
        'saved_at': savedAt.toUtc().toIso8601String(),
        'idempotency_key': idempotencyKey,
        'order_data': orderData,
        'order_items': orderItems,
        'handoff': handoff.toJson(),
        if (cartRevision != null) 'cart_revision': cartRevision,
        if (receipt != null)
          'receipt': {
            'order_id': receipt!.orderId,
            'access_token': receipt!.accessToken,
            'expires_at': receipt!.expiresAt.toUtc().toIso8601String(),
            'replay': receipt!.isReplay,
          },
        if (cartConsumptionClosedAt != null)
          'cart_consumption_closed_at':
              cartConsumptionClosedAt!.toUtc().toIso8601String(),
        if (cartConsumptionStatus != null)
          'cart_consumption_status': cartConsumptionStatus!.name,
        if (cartConsumptionClaimId != null)
          'cart_consumption_claim_id': cartConsumptionClaimId,
      };

  static CheckoutSessionSnapshot? decode(
    String raw, {
    required String expectedTenantId,
  }) {
    try {
      return _parse(
        jsonDecode(raw),
        expectedTenantId: expectedTenantId,
      );
    } catch (_) {
      return null;
    }
  }

  static CheckoutSessionSnapshot? _parse(
    Object? value, {
    required String expectedTenantId,
  }) {
    if (value is! Map) return null;
    final json = Map<String, dynamic>.from(value);
    if (json['v'] != schemaVersion) return null;

    final tenantId = json['tenant_id']?.toString().trim() ?? '';
    final expectedTenant = expectedTenantId.trim();
    final savedAt = DateTime.tryParse(json['saved_at']?.toString() ?? '');
    final idempotencyKey = json['idempotency_key']?.toString().trim() ?? '';
    if (tenantId.isEmpty ||
        tenantId != expectedTenant ||
        savedAt == null ||
        idempotencyKey.isEmpty ||
        !_uuidV4Pattern.hasMatch(idempotencyKey)) {
      return null;
    }

    final rawOrderData = json['order_data'];
    final rawOrderItems = json['order_items'];
    if (rawOrderData is! Map ||
        rawOrderItems is! List ||
        rawOrderItems.isEmpty) {
      return null;
    }

    final orderData = Map<String, dynamic>.from(rawOrderData);
    final orderItems = <Map<String, dynamic>>[];
    final productIds = <String>{};
    for (final rawItem in rawOrderItems) {
      if (rawItem is! Map) return null;
      final item = Map<String, dynamic>.from(rawItem);
      final productId = item['product_id']?.toString().trim() ?? '';
      if (productId.isEmpty || !productIds.add(productId)) return null;
      orderItems.add(item);
    }

    const monetaryFields = <String>{
      'subtotal',
      'tax_amount',
      'shipping_quote_cost',
      'shipping_cost',
      'discount_amount',
      'total',
    };
    if (orderData['tenant_id']?.toString() != tenantId ||
        orderData['checkout_idempotency_key']?.toString() != idempotencyKey ||
        orderData['customer_email']?.toString().trim().isEmpty != false ||
        orderData['customer_name']?.toString().trim().isEmpty != false ||
        orderData['customer_address']?.toString().trim().isEmpty != false ||
        orderData['status'] != 'pending' ||
        orderData['payment_status'] != 'pending' ||
        monetaryFields.any(
          (field) => !_isNonNegativeFiniteNumber(orderData[field]),
        ) ||
        orderItems.any(
          (item) =>
              item['tenant_id']?.toString() != tenantId ||
              (item['product_id']?.toString().trim().isEmpty ?? true) ||
              (item['product_name']?.toString().trim().isEmpty ?? true) ||
              item['quantity'] is! int ||
              (item['quantity'] as int) < 1 ||
              !_isNonNegativeFiniteNumber(item['unit_price']) ||
              !_isNonNegativeFiniteNumber(item['subtotal']),
        )) {
      return null;
    }

    final handoff = CheckoutHandoffSnapshot.fromJson(json['handoff']);
    if (handoff == null ||
        orderData['payment_method']?.toString() != handoff.paymentMethod ||
        orderData['delivery_type']?.toString() != handoff.deliveryType) {
      return null;
    }

    final rawCartRevision = json['cart_revision']?.toString().trim();
    final cartRevision = rawCartRevision == null || rawCartRevision.isEmpty
        ? null
        : rawCartRevision;

    PublicOrderCheckoutAccess? receipt;
    if (json['receipt'] != null) {
      try {
        receipt = PublicOrderCheckoutAccess.fromRpc(json['receipt']);
      } catch (_) {
        return null;
      }
    }

    final rawCartConsumptionClosedAt = json['cart_consumption_closed_at'];
    final rawCartConsumptionStatus = json['cart_consumption_status'];
    final rawCartConsumptionClaimId =
        json['cart_consumption_claim_id']?.toString().trim();
    DateTime? cartConsumptionClosedAt;
    CheckoutCartConsumptionStatus? cartConsumptionStatus;
    if (rawCartConsumptionClosedAt != null ||
        rawCartConsumptionStatus != null) {
      if (rawCartConsumptionClosedAt == null ||
          rawCartConsumptionStatus == null) {
        return null;
      }
      cartConsumptionClosedAt = DateTime.tryParse(
        rawCartConsumptionClosedAt.toString(),
      )?.toUtc();
      cartConsumptionStatus = switch (rawCartConsumptionStatus) {
        'consuming' => CheckoutCartConsumptionStatus.consuming,
        'preserved' => CheckoutCartConsumptionStatus.preserved,
        'applied' => CheckoutCartConsumptionStatus.applied,
        _ => null,
      };
      if (receipt == null ||
          cartConsumptionClosedAt == null ||
          cartConsumptionStatus == null ||
          (cartConsumptionStatus == CheckoutCartConsumptionStatus.consuming &&
              (rawCartConsumptionClaimId == null ||
                  rawCartConsumptionClaimId.isEmpty))) {
        return null;
      }
    }

    return CheckoutSessionSnapshot._(
      tenantId: tenantId,
      savedAt: savedAt.toUtc(),
      idempotencyKey: idempotencyKey,
      orderData: Map.unmodifiable(orderData),
      orderItems: List.unmodifiable(
        orderItems.map((item) => Map<String, dynamic>.unmodifiable(item)),
      ),
      handoff: handoff,
      cartRevision: cartRevision,
      receipt: receipt,
      cartConsumptionClosedAt: cartConsumptionClosedAt,
      cartConsumptionStatus: cartConsumptionStatus,
      cartConsumptionClaimId:
          rawCartConsumptionClaimId == null || rawCartConsumptionClaimId.isEmpty
              ? null
              : rawCartConsumptionClaimId,
    );
  }

  static bool _isNonNegativeFiniteNumber(Object? value) {
    if (value is! num) return false;
    final numeric = value.toDouble();
    return numeric.isFinite && numeric >= 0;
  }
}

class CheckoutSessionStore {
  CheckoutSessionStore({
    required CheckoutSessionStorage storage,
    DateTime Function()? now,
  })  : _storage = storage,
        _now = now ?? DateTime.now;

  factory CheckoutSessionStore.platform() => CheckoutSessionStore(
        storage: kIsWeb
            ? const BrowserCheckoutSessionStorage()
            : const SecureCheckoutSessionStorage(),
      );

  static const Duration maxAge = Duration(hours: 2);
  static const String _keyPrefix = 'vinabike.public-checkout.v1.';
  static const String _cartOutcomeKeyPrefix =
      'vinabike.public-cart-preserved.v1.';
  static const String _orderAccessKeyPrefix =
      'vinabike.public-order-access.v1.';

  /// Every read/modify/write for one tenant shares the same in-process lane,
  /// even when two widgets mounted distinct store instances over the same
  /// platform backend.
  static final Expando<Map<String, Future<void>>> _tenantLanes =
      Expando<Map<String, Future<void>>>();
  static final Map<_CheckoutCartFlightKey, Future<CheckoutCartOutcome>>
      _cartFlights = <_CheckoutCartFlightKey, Future<CheckoutCartOutcome>>{};

  final CheckoutSessionStorage _storage;
  final DateTime Function() _now;

  Future<CheckoutSessionSnapshot?> read(String tenantId) {
    final normalizedTenant = tenantId.trim();
    if (normalizedTenant.isEmpty) {
      return Future<CheckoutSessionSnapshot?>.value();
    }
    return _withTenantLock(
      normalizedTenant,
      () => _readUnlocked(normalizedTenant),
    );
  }

  /// Test-only escape hatch for seeding an exact persisted state.
  ///
  /// Production transitions must use the semantic compare-before-write
  /// operations below so a stale whole snapshot cannot regress durable state.
  @visibleForTesting
  Future<void> save(CheckoutSessionSnapshot snapshot) {
    final normalizedTenant = snapshot.tenantId.trim();
    if (normalizedTenant.isEmpty) {
      throw const FormatException('Estado durable de checkout inválido');
    }
    return _withTenantLock(
      normalizedTenant,
      () => _saveUnlocked(snapshot),
    );
  }

  /// Creates the only active checkout attempt for this tenant.
  ///
  /// Production callers use this compare-before-write boundary instead of
  /// [save], which remains available for tests and explicit state seeding.
  Future<CheckoutSessionSnapshot> createPendingIfAbsent(
    CheckoutSessionSnapshot snapshot,
  ) {
    final normalizedTenant = snapshot.tenantId.trim();
    if (normalizedTenant.isEmpty || snapshot.receipt != null) {
      throw const FormatException('Estado pendiente de checkout inválido');
    }
    return _withTenantLock(normalizedTenant, () async {
      final current = await _readUnlocked(normalizedTenant);
      if (current != null) {
        throw StateError(
          'Ya existe una recuperación activa para esta tienda.',
        );
      }
      await _saveUnlocked(snapshot);
      return snapshot;
    });
  }

  /// Attaches the order receipt only to the attempt that created it.
  ///
  /// The current snapshot is re-read inside the tenant lane, so a stale widget
  /// cannot overwrite a newer recovery attempt or reopen terminal cart state.
  Future<CheckoutSessionSnapshot> attachReceiptIfMatches({
    required String tenantId,
    required String idempotencyKey,
    required PublicOrderCheckoutAccess receipt,
  }) {
    final normalizedTenant = tenantId.trim();
    final normalizedAttempt = idempotencyKey.trim();
    if (normalizedTenant.isEmpty || normalizedAttempt.isEmpty) {
      throw const FormatException('Identidad durable de checkout inválida');
    }
    return _withTenantLock(normalizedTenant, () async {
      final current = await _readUnlocked(normalizedTenant);
      if (current == null || current.idempotencyKey != normalizedAttempt) {
        throw StateError(
          'El recibo no corresponde a la recuperación activa.',
        );
      }

      final existing = current.receipt;
      if (existing != null) {
        final sameReceipt = existing.orderId == receipt.orderId &&
            existing.accessToken == receipt.accessToken &&
            existing.expiresAt.toUtc() == receipt.expiresAt.toUtc() &&
            existing.isReplay == receipt.isReplay;
        if (!sameReceipt) {
          throw StateError(
            'La recuperación activa ya pertenece a otro recibo.',
          );
        }
        return current;
      }

      final updated = current.withReceipt(receipt);
      await _saveUnlocked(updated);
      return updated;
    });
  }

  Future<void> clear(String tenantId) {
    final normalizedTenant = tenantId.trim();
    if (normalizedTenant.isEmpty) return Future<void>.value();
    return _withTenantLock(
      normalizedTenant,
      () => _clearUnlocked(normalizedTenant),
    );
  }

  /// Removes only the pre-RPC attempt that lost its exit-guard ownership.
  /// A newer attempt or any snapshot that already owns a receipt survives.
  Future<bool> clearPendingIfMatches({
    required String tenantId,
    required String idempotencyKey,
  }) {
    final normalizedTenant = tenantId.trim();
    final normalizedAttempt = idempotencyKey.trim();
    if (normalizedTenant.isEmpty || normalizedAttempt.isEmpty) {
      return Future<bool>.value(false);
    }
    return _withTenantLock(normalizedTenant, () async {
      final snapshot = await _readUnlocked(normalizedTenant);
      if (snapshot == null ||
          snapshot.receipt != null ||
          snapshot.idempotencyKey != normalizedAttempt) {
        return false;
      }
      await _clearUnlocked(normalizedTenant);
      return true;
    });
  }

  /// Persists an order-scoped bearer independently from the active checkout
  /// receipt. Native uses the protected vault and web keeps its deliberate
  /// tab-scoped sessionStorage boundary.
  Future<void> saveOrderAccess({
    required String tenantId,
    required PublicOrderCheckoutAccess access,
  }) {
    final normalizedTenant = tenantId.trim();
    if (normalizedTenant.isEmpty) {
      throw const FormatException('Tienda de credencial inválida');
    }
    return _withTenantLock(
      normalizedTenant,
      () => _saveOrderAccessUnlocked(
        tenantId: normalizedTenant,
        access: access,
      ),
    );
  }

  Future<PublicOrderCheckoutAccess?> readOrderAccess({
    required String tenantId,
    required String orderId,
  }) {
    final normalizedTenant = tenantId.trim();
    final normalizedOrderId = orderId.trim();
    if (normalizedTenant.isEmpty || normalizedOrderId.isEmpty) {
      return Future<PublicOrderCheckoutAccess?>.value();
    }
    return _withTenantLock(
      normalizedTenant,
      () => _readOrderAccessUnlocked(
        tenantId: normalizedTenant,
        orderId: normalizedOrderId,
      ),
    );
  }

  Future<void> forgetOrderAccess({
    required String tenantId,
    required String orderId,
  }) {
    final normalizedTenant = tenantId.trim();
    final normalizedOrderId = orderId.trim();
    if (normalizedTenant.isEmpty || normalizedOrderId.isEmpty) {
      return Future<void>.value();
    }
    return _withTenantLock(
      normalizedTenant,
      () => _clearKeyUnlocked(
        _orderAccessKey(normalizedTenant, normalizedOrderId),
        failureMessage: 'No se pudo retirar la credencial segura del pedido.',
      ),
    );
  }

  /// The first terminal cart outcome wins and remains after receipt retirement.
  /// This is both the preserved-warning record and the applied tombstone that
  /// prevents a repeated callback from manufacturing a false warning.
  Future<CheckoutCartOutcome?> readCartOutcome({
    required String tenantId,
    required String orderId,
  }) {
    final normalizedTenant = tenantId.trim();
    final normalizedOrderId = orderId.trim();
    if (normalizedTenant.isEmpty || normalizedOrderId.isEmpty) {
      return Future<CheckoutCartOutcome?>.value();
    }
    return _withTenantLock(
      normalizedTenant,
      () => _readCartOutcomeUnlocked(
        tenantId: normalizedTenant,
        orderId: normalizedOrderId,
      ),
    );
  }

  Future<void> markCartPreservationWarning({
    required String tenantId,
    required String orderId,
  }) async {
    final normalizedTenant = tenantId.trim();
    final normalizedOrderId = orderId.trim();
    if (normalizedTenant.isEmpty || normalizedOrderId.isEmpty) {
      throw ArgumentError(
        'La tienda y el pedido son obligatorios para guardar la advertencia.',
      );
    }
    await _withTenantLock(
      normalizedTenant,
      () => _recordCartOutcomeUnlocked(
        CheckoutCartOutcome(
          tenantId: normalizedTenant,
          orderId: normalizedOrderId,
          state: CheckoutCartOutcomeState.preserved,
          finalizedAt: _now().toUtc(),
          reason: 'explicit_warning',
        ),
      ),
    );
  }

  Future<bool> hasCartPreservationWarning({
    required String tenantId,
    required String orderId,
  }) async {
    final outcome = await readCartOutcome(
      tenantId: tenantId,
      orderId: orderId,
    );
    return outcome?.showsWarning ?? false;
  }

  /// Acknowledgement hides the banner but retains the terminal tombstone.
  Future<bool> acknowledgeCartPreservationWarning({
    required String tenantId,
    required String orderId,
  }) {
    final normalizedTenant = tenantId.trim();
    final normalizedOrderId = orderId.trim();
    if (normalizedTenant.isEmpty || normalizedOrderId.isEmpty) {
      return Future<bool>.value(false);
    }
    return _withTenantLock(normalizedTenant, () async {
      final outcome = await _readCartOutcomeUnlocked(
        tenantId: normalizedTenant,
        orderId: normalizedOrderId,
      );
      if (outcome == null ||
          outcome.state != CheckoutCartOutcomeState.preserved ||
          outcome.acknowledgedAt != null) {
        return false;
      }
      await _writeCartOutcomeUnlocked(outcome.acknowledge(_now()));
      return true;
    });
  }

  /// Atomically claims and completes cart subtraction for this exact order.
  ///
  /// A synchronous root single-flight lets checkout and confirmation share the
  /// same future. The durable `consuming` claim makes a process death
  /// conservative: a later process records `preserved` and never subtracts
  /// again.
  Future<CheckoutCartOutcome> consumeCartOnce({
    required String tenantId,
    required String orderId,
    required CheckoutCartConsumer consume,
  }) {
    final normalizedTenant = tenantId.trim();
    final normalizedOrderId = orderId.trim();
    if (normalizedTenant.isEmpty || normalizedOrderId.isEmpty) {
      throw ArgumentError('La tienda y el pedido son obligatorios.');
    }
    final flightKey = _CheckoutCartFlightKey(
      storage: _storage,
      tenantId: normalizedTenant,
      orderId: normalizedOrderId,
    );
    final existing = _cartFlights[flightKey];
    if (existing != null) return existing;

    final operation = _runCartConsumption(
      tenantId: normalizedTenant,
      orderId: normalizedOrderId,
      consume: consume,
    );
    _cartFlights[flightKey] = operation;
    void releaseFlight() {
      if (identical(_cartFlights[flightKey], operation)) {
        _cartFlights.remove(flightKey);
      }
    }

    operation.then<void>(
      (_) => releaseFlight(),
      onError: (Object _, StackTrace __) => releaseFlight(),
    );
    return operation;
  }

  /// Resolves the cart result needed by a confirmation route without starting
  /// a new subtraction.
  ///
  /// A live checkout subtraction is awaited outside the tenant lane. A
  /// durable `consuming` claim without a live owner is treated as an
  /// interrupted process and closed conservatively as `preserved`.
  Future<CheckoutCartOutcome?> settleCartOutcomeForPresentation({
    required String tenantId,
    required String orderId,
  }) async {
    final normalizedTenant = tenantId.trim();
    final normalizedOrderId = orderId.trim();
    if (normalizedTenant.isEmpty || normalizedOrderId.isEmpty) return null;

    final flightKey = _CheckoutCartFlightKey(
      storage: _storage,
      tenantId: normalizedTenant,
      orderId: normalizedOrderId,
    );
    final existingFlight = _cartFlights[flightKey];
    if (existingFlight != null) return existingFlight;

    Future<CheckoutCartOutcome>? racedFlight;
    final settled = await _withTenantLock(
      normalizedTenant,
      () async {
        // The flight may have started after the first synchronous lookup. Do
        // not await it while holding the lane it needs to finalize.
        racedFlight = _cartFlights[flightKey];
        if (racedFlight != null) return null;

        final existingOutcome = await _readCartOutcomeUnlocked(
          tenantId: normalizedTenant,
          orderId: normalizedOrderId,
        );
        if (existingOutcome != null) return existingOutcome;

        final snapshot = await _readUnlocked(normalizedTenant);
        if (snapshot?.receipt?.orderId != normalizedOrderId) return null;

        switch (snapshot!.cartConsumptionStatus) {
          case CheckoutCartConsumptionStatus.applied:
            return _recordCartOutcomeUnlocked(
              CheckoutCartOutcome(
                tenantId: normalizedTenant,
                orderId: normalizedOrderId,
                state: CheckoutCartOutcomeState.applied,
                finalizedAt: _now().toUtc(),
              ),
            );
          case CheckoutCartConsumptionStatus.preserved:
            return _recordCartOutcomeUnlocked(
              CheckoutCartOutcome(
                tenantId: normalizedTenant,
                orderId: normalizedOrderId,
                state: CheckoutCartOutcomeState.preserved,
                finalizedAt: _now().toUtc(),
                reason: 'legacy_preserved',
              ),
            );
          case CheckoutCartConsumptionStatus.consuming:
            final outcome = await _recordCartOutcomeUnlocked(
              CheckoutCartOutcome(
                tenantId: normalizedTenant,
                orderId: normalizedOrderId,
                state: CheckoutCartOutcomeState.preserved,
                finalizedAt: _now().toUtc(),
                reason: 'interrupted',
              ),
            );
            try {
              await _saveUnlocked(
                snapshot.markCartConsumptionPreserved(),
              );
            } catch (_) {
              // The terminal outcome already prevents a second subtraction.
            }
            return outcome;
          case null:
            return null;
        }
      },
    );
    final liveOutcome = racedFlight;
    if (liveOutcome != null) return liveOutcome;
    return settled;
  }

  Future<bool> clearReceiptIfMatches({
    required String tenantId,
    required String orderId,
    bool requireTerminalCartOutcome = false,
  }) {
    final normalizedTenant = tenantId.trim();
    final normalizedOrderId = orderId.trim();
    if (normalizedTenant.isEmpty || normalizedOrderId.isEmpty) {
      return Future<bool>.value(false);
    }
    return _withTenantLock(normalizedTenant, () async {
      final snapshot = await _readUnlocked(normalizedTenant);
      final receipt = snapshot?.receipt;
      if (receipt?.orderId != normalizedOrderId) return false;
      if (requireTerminalCartOutcome &&
          await _readCartOutcomeUnlocked(
                tenantId: normalizedTenant,
                orderId: normalizedOrderId,
              ) ==
              null) {
        return false;
      }

      // Credential durability is verified before the active receipt can be
      // retired. A failed write leaves the receipt untouched.
      await _saveOrderAccessUnlocked(
        tenantId: normalizedTenant,
        access: receipt!,
      );
      final latest = await _readUnlocked(normalizedTenant);
      if (latest?.idempotencyKey != snapshot!.idempotencyKey ||
          latest?.receipt?.orderId != normalizedOrderId ||
          latest?.receipt?.accessToken != receipt.accessToken) {
        return false;
      }
      await _clearUnlocked(normalizedTenant);
      return true;
    });
  }

  Future<CheckoutSessionSnapshot?> takeTransferReceiptIfMatches({
    required String tenantId,
    required String orderId,
    bool requireTerminalCartOutcome = false,
  }) {
    final normalizedTenant = tenantId.trim();
    final normalizedOrderId = orderId.trim();
    if (normalizedTenant.isEmpty || normalizedOrderId.isEmpty) {
      return Future<CheckoutSessionSnapshot?>.value();
    }
    return _withTenantLock(normalizedTenant, () async {
      final snapshot = await _readUnlocked(normalizedTenant);
      final receipt = snapshot?.receipt;
      if (receipt?.orderId != normalizedOrderId ||
          snapshot!.handoff.paymentMethod != 'transfer') {
        return null;
      }
      if (requireTerminalCartOutcome &&
          await _readCartOutcomeUnlocked(
                tenantId: normalizedTenant,
                orderId: normalizedOrderId,
              ) ==
              null) {
        return null;
      }
      await _saveOrderAccessUnlocked(
        tenantId: normalizedTenant,
        access: receipt!,
      );
      final latest = await _readUnlocked(normalizedTenant);
      if (latest?.idempotencyKey != snapshot.idempotencyKey ||
          latest?.receipt?.orderId != normalizedOrderId ||
          latest?.receipt?.accessToken != receipt.accessToken) {
        return null;
      }
      await _clearUnlocked(normalizedTenant);
      return snapshot;
    });
  }

  Future<CheckoutCartOutcome> _runCartConsumption({
    required String tenantId,
    required String orderId,
    required CheckoutCartConsumer consume,
  }) async {
    final decision = await _withTenantLock(
      tenantId,
      () => _claimCartConsumptionUnlocked(
        tenantId: tenantId,
        orderId: orderId,
      ),
    );
    if (decision.outcome != null) return decision.outcome!;

    final claimed = decision.snapshot!;
    var applied = false;
    try {
      applied = await consume(claimed);
    } catch (_) {
      applied = false;
    }

    return _withTenantLock(tenantId, () async {
      final terminal = await _recordCartOutcomeUnlocked(
        CheckoutCartOutcome(
          tenantId: tenantId,
          orderId: orderId,
          state: applied
              ? CheckoutCartOutcomeState.applied
              : CheckoutCartOutcomeState.preserved,
          finalizedAt: _now().toUtc(),
          reason: applied ? null : 'cart_unavailable',
        ),
      );

      final current = await _readUnlocked(tenantId);
      if (current?.receipt?.orderId == orderId &&
          current!.cartConsumptionStatus ==
              CheckoutCartConsumptionStatus.consuming &&
          current.cartConsumptionClaimId == claimed.cartConsumptionClaimId) {
        final updated = terminal.state == CheckoutCartOutcomeState.applied
            ? current.markCartConsumptionApplied()
            : current.markCartConsumptionPreserved();
        try {
          await _saveUnlocked(updated);
        } catch (_) {
          // The independent terminal outcome is already verified and remains
          // authoritative even if the active recovery snapshot cannot be
          // promoted before a crash.
        }
      }
      return terminal;
    });
  }

  Future<_CheckoutCartClaimDecision> _claimCartConsumptionUnlocked({
    required String tenantId,
    required String orderId,
  }) async {
    final existingOutcome = await _readCartOutcomeUnlocked(
      tenantId: tenantId,
      orderId: orderId,
    );
    if (existingOutcome != null) {
      return _CheckoutCartClaimDecision.outcome(existingOutcome);
    }

    final snapshot = await _readUnlocked(tenantId);
    if (snapshot?.receipt?.orderId != orderId) {
      final outcome = await _recordCartOutcomeUnlocked(
        CheckoutCartOutcome(
          tenantId: tenantId,
          orderId: orderId,
          state: CheckoutCartOutcomeState.preserved,
          finalizedAt: _now().toUtc(),
          reason: 'snapshot_missing',
        ),
      );
      return _CheckoutCartClaimDecision.outcome(outcome);
    }

    switch (snapshot!.cartConsumptionStatus) {
      case CheckoutCartConsumptionStatus.applied:
        final outcome = await _recordCartOutcomeUnlocked(
          CheckoutCartOutcome(
            tenantId: tenantId,
            orderId: orderId,
            state: CheckoutCartOutcomeState.applied,
            finalizedAt: _now().toUtc(),
          ),
        );
        return _CheckoutCartClaimDecision.outcome(outcome);
      case CheckoutCartConsumptionStatus.preserved:
        final outcome = await _recordCartOutcomeUnlocked(
          CheckoutCartOutcome(
            tenantId: tenantId,
            orderId: orderId,
            state: CheckoutCartOutcomeState.preserved,
            finalizedAt: _now().toUtc(),
            reason: 'legacy_preserved',
          ),
        );
        return _CheckoutCartClaimDecision.outcome(outcome);
      case CheckoutCartConsumptionStatus.consuming:
        final outcome = await _recordCartOutcomeUnlocked(
          CheckoutCartOutcome(
            tenantId: tenantId,
            orderId: orderId,
            state: CheckoutCartOutcomeState.preserved,
            finalizedAt: _now().toUtc(),
            reason: 'interrupted',
          ),
        );
        try {
          await _saveUnlocked(snapshot.markCartConsumptionPreserved());
        } catch (_) {
          // The terminal tombstone is sufficient to prevent a second consume.
        }
        return _CheckoutCartClaimDecision.outcome(outcome);
      case null:
        break;
    }

    final cartRevision = snapshot.cartRevision?.trim() ?? '';
    if (cartRevision.isEmpty) {
      final preserved = snapshot.closeCartConsumption(_now());
      await _saveUnlocked(preserved);
      final outcome = await _recordCartOutcomeUnlocked(
        CheckoutCartOutcome(
          tenantId: tenantId,
          orderId: orderId,
          state: CheckoutCartOutcomeState.preserved,
          finalizedAt: _now().toUtc(),
          reason: 'baseline_missing',
        ),
      );
      return _CheckoutCartClaimDecision.outcome(outcome);
    }

    final claimed = snapshot.claimCartConsumption(
      claimId: const Uuid().v4(),
      startedAt: _now(),
    );
    await _saveUnlocked(claimed);
    return _CheckoutCartClaimDecision.claimed(claimed);
  }

  Future<CheckoutSessionSnapshot?> _readUnlocked(String tenantId) async {
    final key = _key(tenantId);
    final raw = await _storage.read(key);
    if (raw == null || raw.isEmpty) return null;

    final snapshot = CheckoutSessionSnapshot.decode(
      raw,
      expectedTenantId: tenantId,
    );
    final now = _now().toUtc();
    final isFresh = snapshot != null &&
        !snapshot.savedAt.isAfter(now.add(const Duration(minutes: 5))) &&
        now.difference(snapshot.savedAt) <= maxAge &&
        (snapshot.receipt == null || snapshot.receipt!.expiresAt.isAfter(now));
    if (isFresh) return snapshot;

    if (await _storage.read(key) == raw) {
      await _clearKeyUnlocked(
        key,
        failureMessage: 'No se pudo retirar la sesión segura del checkout.',
      );
    }
    return null;
  }

  Future<void> _saveUnlocked(CheckoutSessionSnapshot snapshot) async {
    final encoded = jsonEncode(snapshot.toJson());
    final verified = CheckoutSessionSnapshot.decode(
      encoded,
      expectedTenantId: snapshot.tenantId,
    );
    if (verified == null) {
      throw const FormatException('Estado durable de checkout inválido');
    }
    final key = _key(snapshot.tenantId);
    await _storage.write(key, encoded);
    if (await _storage.read(key) != encoded) {
      throw StateError('No se pudo guardar la sesión segura del checkout.');
    }
  }

  Future<void> _clearUnlocked(String tenantId) => _clearKeyUnlocked(
        _key(tenantId),
        failureMessage: 'No se pudo retirar la sesión segura del checkout.',
      );

  Future<void> _saveOrderAccessUnlocked({
    required String tenantId,
    required PublicOrderCheckoutAccess access,
  }) async {
    final orderId = access.orderId.trim();
    final tokenLength = access.accessToken.trim().length;
    if (orderId.isEmpty ||
        tokenLength < 40 ||
        tokenLength > 128 ||
        !access.expiresAt.isAfter(_now().toUtc())) {
      throw const FormatException('Credencial pública de pedido inválida');
    }
    final encoded = jsonEncode({
      'v': 1,
      'tenant_id': tenantId,
      'order_id': orderId,
      'access_token': access.accessToken.trim(),
      'expires_at': access.expiresAt.toUtc().toIso8601String(),
      'replay': access.isReplay,
    });
    final key = _orderAccessKey(tenantId, orderId);
    await _storage.write(key, encoded);
    if (await _storage.read(key) != encoded) {
      throw StateError(
        'No se pudo guardar la credencial segura del pedido.',
      );
    }
  }

  Future<PublicOrderCheckoutAccess?> _readOrderAccessUnlocked({
    required String tenantId,
    required String orderId,
  }) async {
    final key = _orderAccessKey(tenantId, orderId);
    var raw = await _storage.read(key);
    if (raw == null || raw.isEmpty) {
      final legacyKey = '$_orderAccessKeyPrefix$orderId';
      final legacyRaw = await _storage.read(legacyKey);
      final legacyToken = legacyRaw?.trim() ?? '';
      if (legacyToken.isEmpty) return null;
      if (legacyToken.length < 40 || legacyToken.length > 128) {
        if (await _storage.read(legacyKey) == legacyRaw) {
          await _clearKeyUnlocked(
            legacyKey,
            failureMessage:
                'No se pudo retirar la credencial heredada inválida.',
          );
        }
        return null;
      }

      final migrated = PublicOrderCheckoutAccess(
        orderId: orderId,
        accessToken: legacyToken,
        expiresAt: _now().toUtc().add(const Duration(days: 30)),
        isReplay: false,
      );
      await _saveOrderAccessUnlocked(
        tenantId: tenantId,
        access: migrated,
      );
      raw = await _storage.read(key);
      if (raw == null || raw.isEmpty) {
        throw StateError(
          'No se pudo verificar la credencial migrada del pedido.',
        );
      }
      if (await _storage.read(legacyKey) == legacyRaw) {
        await _clearKeyUnlocked(
          legacyKey,
          failureMessage:
              'No se pudo retirar la credencial heredada del pedido.',
        );
      }
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          decoded['v'] != 1 ||
          decoded['tenant_id']?.toString() != tenantId ||
          decoded['order_id']?.toString() != orderId) {
        throw const FormatException('Credencial pública incorrecta');
      }
      final access = PublicOrderCheckoutAccess.fromRpc(decoded);
      if (!access.expiresAt.isAfter(_now().toUtc())) {
        throw const FormatException('Credencial pública vencida');
      }
      return access;
    } catch (_) {
      if (await _storage.read(key) == raw) {
        await _clearKeyUnlocked(
          key,
          failureMessage:
              'No se pudo retirar la credencial inválida del pedido.',
        );
      }
      return null;
    }
  }

  Future<CheckoutCartOutcome?> _readCartOutcomeUnlocked({
    required String tenantId,
    required String orderId,
  }) async {
    final key = _cartOutcomeKey(tenantId, orderId);
    final raw = await _storage.read(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          decoded['tenant_id']?.toString() != tenantId ||
          decoded['order_id']?.toString() != orderId) {
        throw const FormatException('Resultado de carrito incorrecto');
      }

      // v1 was the original unacknowledged preservation marker.
      if (decoded['v'] == 1) {
        final migrated = CheckoutCartOutcome(
          tenantId: tenantId,
          orderId: orderId,
          state: CheckoutCartOutcomeState.preserved,
          finalizedAt: _now().toUtc(),
          reason: 'legacy_marker',
        );
        await _writeCartOutcomeUnlocked(migrated);
        return migrated;
      }
      if (decoded['v'] != 2) {
        throw const FormatException('Versión de resultado desconocida');
      }
      final state = switch (decoded['state']) {
        'preserved' => CheckoutCartOutcomeState.preserved,
        'applied' => CheckoutCartOutcomeState.applied,
        _ => null,
      };
      final finalizedAt =
          DateTime.tryParse(decoded['finalized_at']?.toString() ?? '')?.toUtc();
      final acknowledgedAt = decoded['acknowledged_at'] == null
          ? null
          : DateTime.tryParse(
              decoded['acknowledged_at'].toString(),
            )?.toUtc();
      if (state == null ||
          finalizedAt == null ||
          (decoded['acknowledged_at'] != null && acknowledgedAt == null)) {
        throw const FormatException('Resultado de carrito inválido');
      }
      return CheckoutCartOutcome(
        tenantId: tenantId,
        orderId: orderId,
        state: state,
        finalizedAt: finalizedAt,
        reason: decoded['reason']?.toString(),
        acknowledgedAt: acknowledgedAt,
      );
    } catch (_) {
      if (await _storage.read(key) == raw) {
        await _clearKeyUnlocked(
          key,
          failureMessage:
              'No se pudo retirar el resultado inválido del carrito.',
        );
      }
      return null;
    }
  }

  Future<CheckoutCartOutcome> _recordCartOutcomeUnlocked(
    CheckoutCartOutcome proposed,
  ) async {
    final existing = await _readCartOutcomeUnlocked(
      tenantId: proposed.tenantId,
      orderId: proposed.orderId,
    );
    if (existing != null) return existing;
    await _writeCartOutcomeUnlocked(proposed);
    return proposed;
  }

  Future<void> _writeCartOutcomeUnlocked(
    CheckoutCartOutcome outcome,
  ) async {
    final encoded = jsonEncode(outcome.toJson());
    final key = _cartOutcomeKey(outcome.tenantId, outcome.orderId);
    await _storage.write(key, encoded);
    if (await _storage.read(key) != encoded) {
      throw StateError('No se pudo guardar el resultado durable del carrito.');
    }
  }

  Future<void> _clearKeyUnlocked(
    String key, {
    required String failureMessage,
  }) async {
    await _storage.write(key, '');
    final remaining = await _storage.read(key);
    if (remaining != null && remaining.isNotEmpty) {
      throw StateError(failureMessage);
    }
  }

  Future<T> _withTenantLock<T>(
    String tenantId,
    Future<T> Function() operation,
  ) async {
    final lanes = _tenantLanes[_storage] ??= <String, Future<void>>{};
    final previous = lanes[tenantId] ?? Future<void>.value();
    final release = Completer<void>();
    final tail = () async {
      try {
        await previous;
      } catch (_) {
        // A failed predecessor still releases the lane for the next operation.
      }
      await release.future;
    }();
    lanes[tenantId] = tail;

    try {
      try {
        await previous;
      } catch (_) {
        // The previous caller owns its own error; serialization must continue.
      }
      return await operation();
    } finally {
      if (!release.isCompleted) release.complete();
      if (identical(lanes[tenantId], tail)) {
        lanes.remove(tenantId);
      }
    }
  }

  String _key(String tenantId) => '$_keyPrefix${tenantId.trim()}';

  String _cartOutcomeKey(String tenantId, String orderId) {
    final tenantComponent = base64Url.encode(utf8.encode(tenantId));
    final orderComponent = base64Url.encode(utf8.encode(orderId));
    return '$_cartOutcomeKeyPrefix$tenantComponent.$orderComponent';
  }

  String _orderAccessKey(String tenantId, String orderId) {
    final tenantComponent = base64Url.encode(utf8.encode(tenantId));
    final orderComponent = base64Url.encode(utf8.encode(orderId));
    return '$_orderAccessKeyPrefix$tenantComponent.$orderComponent';
  }
}

class _CheckoutCartClaimDecision {
  const _CheckoutCartClaimDecision._({this.snapshot, this.outcome});

  factory _CheckoutCartClaimDecision.claimed(
    CheckoutSessionSnapshot snapshot,
  ) =>
      _CheckoutCartClaimDecision._(snapshot: snapshot);

  factory _CheckoutCartClaimDecision.outcome(
    CheckoutCartOutcome outcome,
  ) =>
      _CheckoutCartClaimDecision._(outcome: outcome);

  final CheckoutSessionSnapshot? snapshot;
  final CheckoutCartOutcome? outcome;
}

class _CheckoutCartFlightKey {
  const _CheckoutCartFlightKey({
    required this.storage,
    required this.tenantId,
    required this.orderId,
  });

  final CheckoutSessionStorage storage;
  final String tenantId;
  final String orderId;

  @override
  bool operator ==(Object other) =>
      other is _CheckoutCartFlightKey &&
      identical(other.storage, storage) &&
      other.tenantId == tenantId &&
      other.orderId == orderId;

  @override
  int get hashCode => Object.hash(
        identityHashCode(storage),
        tenantId,
        orderId,
      );
}
