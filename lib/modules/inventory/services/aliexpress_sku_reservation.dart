import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'product_image_fingerprint_service.dart';

/// Which invoice row is asking for a canonical `AE0xxx`.
///
/// The reservation RPC is idempotent **by operation key**, which is what makes
/// a lost response safe to retry. That same property is what turns a key that
/// is not row-exact into a silent SKU collision: two rows reserving under one
/// key get one answer twice.
///
/// The identity is therefore built from what actually distinguishes one line of
/// one document from another, and from nothing that changes between app runs:
///
/// * the document fingerprint — folio, date, supplier;
/// * [sourceRowIndex] — the only field that separates two **byte-identical**
///   rows of the same invoice, which is exactly the case a title/listing/variant
///   key cannot tell apart;
/// * the supplier listing and variant, so re-importing the same order reserves
///   the same SKU instead of burning the sequence;
/// * [generation], bumped only when a granted SKU turns out to be taken, so the
///   retry is a genuinely new reservation and never a replay of the taken one.
class AliExpressSkuRowIdentity {
  const AliExpressSkuRowIdentity({
    required this.documentFingerprint,
    required this.sourceRowIndex,
    this.listingId = '',
    this.variantKey = '',
    this.generation = 0,
  });

  final String documentFingerprint;
  final int sourceRowIndex;
  final String listingId;
  final String variantKey;
  final int generation;

  /// Same row, next attempt. Used only after a foreign collision.
  AliExpressSkuRowIdentity nextGeneration() => AliExpressSkuRowIdentity(
        documentFingerprint: documentFingerprint,
        sourceRowIndex: sourceRowIndex,
        listingId: listingId,
        variantKey: variantKey,
        generation: generation + 1,
      );

  /// Stable across generations: this is *which row*, not *which attempt*.
  String get rowKey => <String>[
        documentFingerprint,
        'row=$sourceRowIndex',
      ].join('');

  /// The idempotency key sent to the database.
  String get operationKey {
    final identity = <String>[
      'v2',
      documentFingerprint,
      'row=$sourceRowIndex',
      'listing=$listingId',
      'variant=$variantKey',
      'generation=$generation',
    ].join('');
    final digest = ProductImageFingerprintService.contentDigest(
      Uint8List.fromList(utf8.encode(identity)),
    );
    return 'aliexpress-ocr-row-v2-${digest.substring(0, 32)}';
  }
}

/// One row's granted, database-owned SKU.
class AliExpressSkuGrant {
  const AliExpressSkuGrant({
    required this.sku,
    required this.operationKey,
    required this.generation,
  });

  final String sku;
  final String operationKey;
  final int generation;
}

typedef AliExpressSkuReserveCall = Future<List<String>> Function({
  required int count,
  required String operationKey,
});

typedef AliExpressSkuTakenCheck = Future<bool> Function(String sku);

/// Owns every `AE0xxx` handed to a review session.
///
/// Two guarantees, both mechanical rather than hopeful:
///
/// * **Serialised.** Requests run one at a time. The shared AE namespace is a
///   sequence; letting two rows race on it is how a batch reservation and a row
///   reservation could interleave onto the same number.
/// * **Distinct.** Every SKU it has ever handed out in this session is
///   remembered. A number that reappears — because the RPC replayed, because
///   another creator took it, because the sequence was reset — is refused and
///   re-requested under a new generation rather than shown to the operator.
class AliExpressSkuReservationAuthority {
  AliExpressSkuReservationAuthority({
    required AliExpressSkuReserveCall reserve,
    required AliExpressSkuTakenCheck isSkuTaken,
    this.maxCollisionRetries = 5,
  })  : _reserve = reserve,
        _isSkuTaken = isSkuTaken;

  final AliExpressSkuReserveCall _reserve;
  final AliExpressSkuTakenCheck _isSkuTaken;
  final int maxCollisionRetries;

  final Map<String, AliExpressSkuGrant> _granted =
      <String, AliExpressSkuGrant>{};
  final Set<String> _issuedSkus = <String>{};
  Future<void> _serial = Future<void>.value();

  int _calls = 0;

  /// Reservation RPCs actually spent. A same-row replay must not raise it.
  int get reservationCalls => _calls;

  /// What this row already holds, without asking anyone.
  AliExpressSkuGrant? reservationFor(AliExpressSkuRowIdentity identity) =>
      _granted[identity.rowKey];

  /// Reserves — or replays — this row's SKU.
  ///
  /// Calls are queued: the returned future completes in submission order and no
  /// two requests are ever in flight against the sequence at once.
  Future<AliExpressSkuGrant> reserveFor(
    AliExpressSkuRowIdentity identity,
  ) {
    final completer = Completer<AliExpressSkuGrant>();
    _serial = _serial.then((_) async {
      try {
        completer.complete(await _reserveNow(identity));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  /// Forgets this row's grant so the next request asks for a new number.
  ///
  /// The abandoned SKU stays in the issued set: it was published to at least
  /// one operator, and handing it to another row later would recreate exactly
  /// the collision this class exists to prevent.
  AliExpressSkuRowIdentity invalidate(AliExpressSkuRowIdentity identity) {
    final previous = _granted.remove(identity.rowKey);
    return previous == null
        ? identity.nextGeneration()
        : AliExpressSkuRowIdentity(
            documentFingerprint: identity.documentFingerprint,
            sourceRowIndex: identity.sourceRowIndex,
            listingId: identity.listingId,
            variantKey: identity.variantKey,
            generation: previous.generation + 1,
          );
  }

  void reset() {
    _granted.clear();
    _issuedSkus.clear();
  }

  Future<AliExpressSkuGrant> _reserveNow(
    AliExpressSkuRowIdentity identity,
  ) async {
    final existing = _granted[identity.rowKey];
    // A retry of the same row costs nothing and returns the same number: the
    // operator already wrote it on the box.
    if (existing != null) return existing;

    var attempt = identity;
    for (var retry = 0; retry < maxCollisionRetries; retry++) {
      _calls++;
      final skus = await _reserve(count: 1, operationKey: attempt.operationKey);
      if (skus.length != 1) {
        throw StateError('La reserva SKU devolvió una cantidad inesperada.');
      }
      final sku = skus.single.trim();
      if (sku.isEmpty) {
        throw StateError('La reserva SKU devolvió un código vacío.');
      }
      final alreadyIssuedHere = _issuedSkus.contains(sku);
      if (alreadyIssuedHere || await _isSkuTaken(sku)) {
        _issuedSkus.add(sku);
        attempt = attempt.nextGeneration();
        continue;
      }
      final granted = AliExpressSkuGrant(
        sku: sku,
        operationKey: attempt.operationKey,
        generation: attempt.generation,
      );
      _granted[identity.rowKey] = granted;
      _issuedSkus.add(sku);
      return granted;
    }
    throw StateError(
      'No se pudo obtener un SKU AE libre después de $maxCollisionRetries '
      'intentos.',
    );
  }
}
