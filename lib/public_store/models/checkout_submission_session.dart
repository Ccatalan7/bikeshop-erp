import '../../modules/website/models/public_order_access.dart';

typedef CheckoutOrderCreator = Future<PublicOrderCheckoutAccess> Function(
  String idempotencyKey,
);

typedef CheckoutOrderHandoff = Future<void> Function(
  PublicOrderCheckoutAccess receipt,
);

enum CheckoutSubmissionPhase {
  ready,
  creatingOrder,
  outcomeUnknown,
  orderCreated,
  handingOff,
  handoffFailed,
  handedOff,
}

/// Owns the one-way boundary between attempting and confirming order creation.
///
/// Before a receipt exists, retrying uses the same idempotency key so the
/// backend can replay an outcome that was committed before a transport error.
/// After a receipt exists, this session never invokes the creator again:
/// retries resume only the account/payment/navigation handoff.
class CheckoutSubmissionSession {
  CheckoutSubmissionSession({required this.idempotencyKey});

  factory CheckoutSubmissionSession.restorePending({
    required String idempotencyKey,
    required CheckoutOrderCreator creator,
  }) {
    return CheckoutSubmissionSession(idempotencyKey: idempotencyKey)
      .._originalCreator = creator
      .._phase = CheckoutSubmissionPhase.outcomeUnknown;
  }

  factory CheckoutSubmissionSession.restoreReceipt({
    required String idempotencyKey,
    required PublicOrderCheckoutAccess receipt,
  }) {
    return CheckoutSubmissionSession(idempotencyKey: idempotencyKey)
      .._receipt = receipt
      .._phase = CheckoutSubmissionPhase.orderCreated;
  }

  final String idempotencyKey;

  CheckoutSubmissionPhase _phase = CheckoutSubmissionPhase.ready;
  CheckoutSubmissionPhase get phase => _phase;

  PublicOrderCheckoutAccess? _receipt;
  PublicOrderCheckoutAccess? get receipt => _receipt;
  bool get hasReceipt => _receipt != null;

  CheckoutOrderCreator? _originalCreator;
  bool get hasCreationAttempt => _originalCreator != null;
  bool get hasStarted => hasReceipt || hasCreationAttempt;

  Future<PublicOrderCheckoutAccess>? _creationInFlight;

  Future<PublicOrderCheckoutAccess> ensureOrderCreated(
    CheckoutOrderCreator create,
  ) {
    final existing = _receipt;
    if (existing != null) return Future.value(existing);

    final inFlight = _creationInFlight;
    if (inFlight != null) return inFlight;

    // The first closure captures the original payload. An outcome-unknown
    // retry must replay that payload with the same key even if the form or cart
    // changed meanwhile.
    final originalCreator = _originalCreator ??= create;
    final pending = _createOrder(originalCreator);
    _creationInFlight = pending;
    return pending;
  }

  Future<PublicOrderCheckoutAccess> retryOriginalOrder() {
    final existing = _receipt;
    if (existing != null) return Future.value(existing);

    final originalCreator = _originalCreator;
    if (originalCreator == null) {
      throw StateError('Cannot retry before the first creation attempt.');
    }
    return ensureOrderCreated(originalCreator);
  }

  Future<PublicOrderCheckoutAccess> _createOrder(
    CheckoutOrderCreator create,
  ) async {
    _phase = CheckoutSubmissionPhase.creatingOrder;
    try {
      final created = await create(idempotencyKey);
      _receipt = created;
      _originalCreator = null;
      _phase = CheckoutSubmissionPhase.orderCreated;
      return created;
    } catch (error, stackTrace) {
      _phase = CheckoutSubmissionPhase.outcomeUnknown;
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      _creationInFlight = null;
    }
  }

  Future<void> handOff(CheckoutOrderHandoff handoff) async {
    final created = _receipt;
    if (created == null) {
      throw StateError('Cannot hand off an order before it has a receipt.');
    }

    _phase = CheckoutSubmissionPhase.handingOff;
    try {
      await handoff(created);
      _phase = CheckoutSubmissionPhase.handedOff;
    } catch (error, stackTrace) {
      _phase = CheckoutSubmissionPhase.handoffFailed;
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
