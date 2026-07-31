import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'cart_lock.dart';

/// One saved basket line.
///
/// Deliberately only an identifier and a quantity. Price, title, stock and tax
/// classification are re-read from the catalog on restore, because a basket
/// that survives a reload must never be able to carry a stale price into
/// checkout — the whole point of persisting is that time passes in between.
@immutable
class PersistedCartLine {
  const PersistedCartLine({required this.productId, required this.quantity});

  final String productId;
  final int quantity;

  Map<String, dynamic> toJson() => {'id': productId, 'q': quantity};

  static PersistedCartLine? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id']?.toString().trim() ?? '';
    final rawQuantity = raw['q'];
    if (id.isEmpty || rawQuantity is! num) return null;
    final numericQuantity = rawQuantity.toDouble();
    if (!numericQuantity.isFinite ||
        numericQuantity < 1 ||
        numericQuantity != numericQuantity.roundToDouble()) {
      return null;
    }
    final quantity = numericQuantity.toInt();
    return PersistedCartLine(productId: id, quantity: quantity);
  }
}

@immutable
class PersistedCart {
  const PersistedCart({
    required this.tenantId,
    required this.savedAt,
    required this.lines,
    this.revision,
    this.appliedMutations = const <String, DateTime>{},
  });

  final String tenantId;
  final DateTime savedAt;
  final List<PersistedCartLine> lines;
  final String? revision;

  /// Semantic mutation IDs already represented by this document.
  ///
  /// They make an applied write idempotent even when its acknowledgement is
  /// lost. Empty line lists remain durable tombstones so checkout consumption
  /// cannot erase the lineage while another tab is still reconciling. Each
  /// timestamp lets the provider compact lineage at the cart retention bound.
  final Map<String, DateTime> appliedMutations;

  Set<String> get appliedMutationIds =>
      Set<String>.unmodifiable(appliedMutations.keys);

  Map<String, dynamic> toJson() => {
        'v': CartStore.schemaVersion,
        'tenant': tenantId,
        'saved_at': savedAt.toUtc().toIso8601String(),
        'lines': lines.map((line) => line.toJson()).toList(),
        if (revision != null) 'revision': revision,
        if (appliedMutations.isNotEmpty)
          'applied_mutations': [
            for (final mutation in appliedMutations.entries)
              {
                'id': mutation.key,
                'at': mutation.value.toUtc().toIso8601String(),
              },
          ],
      };

  static PersistedCart? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final rawVersion = raw['v'];
    if (rawVersion is! num) return null;
    final numericVersion = rawVersion.toDouble();
    if (!numericVersion.isFinite ||
        numericVersion != numericVersion.roundToDouble() ||
        numericVersion.toInt() != CartStore.schemaVersion) {
      return null;
    }
    final tenantId = raw['tenant']?.toString().trim() ?? '';
    if (tenantId.isEmpty) return null;
    final savedAt = DateTime.tryParse(raw['saved_at']?.toString() ?? '');
    if (savedAt == null) return null;
    final rawRevision = raw['revision']?.toString().trim();
    final revision =
        rawRevision == null || rawRevision.isEmpty ? null : rawRevision;
    final rawLines = raw['lines'];
    if (rawLines is! List) return null;
    final linesByProduct = <String, PersistedCartLine>{};
    for (final entry in rawLines) {
      final line = PersistedCartLine.fromJson(entry);
      if (line == null) return null;
      final existing = linesByProduct[line.productId];
      // A canonical writer emits one row per product. A duplicated row means
      // the local payload is stale or malformed: retain the strongest single
      // intent instead of multiplying the requested quantity.
      if (existing == null || line.quantity > existing.quantity) {
        linesByProduct[line.productId] = line;
      }
    }
    final rawAppliedMutations = raw['applied_mutations'];
    if (rawAppliedMutations != null && rawAppliedMutations is! List) {
      return null;
    }
    final appliedMutations = <String, DateTime>{};
    for (final entry in rawAppliedMutations as List? ?? const <Object?>[]) {
      final String operationId;
      final DateTime appliedAt;
      if (entry is String) {
        // Transitional support for the first local operation-ID encoding.
        // Its document timestamp is the strongest available age bound.
        operationId = entry.trim();
        appliedAt = savedAt.toUtc();
      } else if (entry is Map) {
        operationId = entry['id']?.toString().trim() ?? '';
        final parsedAppliedAt =
            DateTime.tryParse(entry['at']?.toString() ?? '');
        if (parsedAppliedAt == null) return null;
        appliedAt = parsedAppliedAt.toUtc();
      } else {
        return null;
      }
      if (operationId.isEmpty) return null;
      final previous = appliedMutations[operationId];
      if (previous == null || appliedAt.isAfter(previous)) {
        appliedMutations[operationId] = appliedAt;
      }
    }
    return PersistedCart(
      tenantId: tenantId,
      savedAt: savedAt,
      lines: List<PersistedCartLine>.unmodifiable(linesByProduct.values),
      revision: revision,
      appliedMutations: Map<String, DateTime>.unmodifiable(appliedMutations),
    );
  }
}

enum CartConsumptionStatus {
  applied,
  conflict,
  unavailable,
}

@immutable
class CartConsumptionResult {
  const CartConsumptionResult({
    required this.status,
    required this.document,
  });

  final CartConsumptionStatus status;

  /// Freshest document observed by the operation. `null` is a valid empty
  /// basket for an applied result, or an unreadable/unavailable document when
  /// the operation could not establish a safe state.
  final PersistedCart? document;

  bool get applied => status == CartConsumptionStatus.applied;
}

typedef CartConsumptionPreparation = Future<bool> Function(
  PersistedCart? proposedDocument,
);

/// Minimal injectable key/value boundary used to verify storage failures
/// deterministically. The platform implementation reloads and reads back every
/// mutation before reporting success.
abstract interface class CartPreferencesBackend {
  Future<String?> read(String key);
  Future<bool> write(String key, String value);
  Future<bool> remove(String key);
}

class SharedPreferencesCartBackend implements CartPreferencesBackend {
  const SharedPreferencesCartBackend();

  @override
  Future<String?> read(String key) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    return preferences.getString(key);
  }

  @override
  Future<bool> write(String key, String value) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.setString(key, value)) return false;
    await preferences.reload();
    return preferences.getString(key) == value;
  }

  @override
  Future<bool> remove(String key) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.remove(key)) return false;
    await preferences.reload();
    return preferences.getString(key) == null;
  }
}

/// Durable home for the visitor's basket.
abstract class CartStore {
  static const int schemaVersion = 1;
  static const Duration allowedFutureSkew = Duration(minutes: 5);

  /// A basket older than this is discarded rather than restored. Prices,
  /// availability and the visitor's intent all go stale; silently reviving a
  /// month-old basket is a surprise, not a convenience.
  static const Duration maxAge = Duration(days: 7);

  Future<PersistedCart?> read();
  Future<void> write(PersistedCart cart);
  Future<void> clear();

  /// Subtracts ordered quantities from a freshly-read durable basket.
  ///
  /// Stores that cannot provide compare-before-write semantics fail closed.
  Future<CartConsumptionResult> consumeOrderedLines({
    required String tenantId,
    required List<PersistedCartLine> orderedLines,
    required String expectedRevision,
    CartConsumptionPreparation? prepare,
  }) async {
    final document = await read();
    return CartConsumptionResult(
      status: CartConsumptionStatus.unavailable,
      document: document?.tenantId == tenantId.trim() ? document : null,
    );
  }
}

/// Optional capability for stores that isolate each tenant at the storage-key
/// boundary.
///
/// Kept separate from [CartStore] so existing lightweight stores that use
/// `implements CartStore` remain source-compatible. [CartProvider] detects this
/// capability and otherwise applies a safe single-document fallback.
abstract interface class TenantScopedCartStore {
  Future<PersistedCart?> readForTenant(String tenantId);
  Future<void> writeForTenant(String tenantId, PersistedCart cart);
  Future<void> clearForTenant(String tenantId);
}

@immutable
class CartCompareAndSetResult {
  const CartCompareAndSetResult({
    required this.applied,
    required this.document,
  });

  final bool applied;

  /// The committed replacement when [applied] is true, otherwise the newer
  /// document that prevented the exchange.
  final PersistedCart? document;
}

/// Optional capability for an indivisible tenant-document compare-and-swap.
///
/// The comparison and replacement happen under the same cross-context lock.
/// Callers can rebase semantic mutations over [CartCompareAndSetResult.document]
/// and retry without ever overwriting a newer tab's document.
abstract interface class AtomicTenantCartStore {
  Future<CartCompareAndSetResult> compareAndSetForTenant({
    required String tenantId,
    required PersistedCart? expected,
    required PersistedCart? replacement,
  });
}

class SharedPreferencesCartStore
    implements CartStore, TenantScopedCartStore, AtomicTenantCartStore {
  SharedPreferencesCartStore({
    @visibleForTesting this.beforeCommitValidation,
    CartPreferencesBackend? preferences,
    CartLockCoordinator? lockCoordinator,
    DateTime Function()? now,
  })  : _preferences = preferences ?? const SharedPreferencesCartBackend(),
        _lockCoordinator = lockCoordinator ?? createCartLockCoordinator(),
        _now = now ?? DateTime.now;

  @visibleForTesting
  static const String legacyStorageKey = 'public_store_cart_v1';
  static const String _tenantKeyPrefix = 'public_store_cart_v2.';
  static const String _storageLockName =
      'vinabike.public_store_cart.storage.v2';

  @visibleForTesting
  static String storageKeyForTenant(String tenantId) {
    final normalizedTenant = tenantId.trim();
    if (normalizedTenant.isEmpty) {
      throw ArgumentError.value(tenantId, 'tenantId', 'Tienda inválida');
    }
    final tenantComponent = base64Url.encode(utf8.encode(normalizedTenant));
    return '$_tenantKeyPrefix$tenantComponent';
  }

  static String _lockNameForTenant(String tenantId) {
    storageKeyForTenant(tenantId);
    return _storageLockName;
  }

  @visibleForTesting
  final Future<void> Function()? beforeCommitValidation;
  final CartPreferencesBackend _preferences;
  final CartLockCoordinator _lockCoordinator;
  final DateTime Function() _now;

  @override
  Future<PersistedCart?> read() async {
    return _decodeStrict(await _preferences.read(legacyStorageKey));
  }

  @override
  Future<PersistedCart?> readForTenant(String tenantId) async {
    final normalizedTenant = tenantId.trim();
    if (normalizedTenant.isEmpty) return null;
    PersistedCart? result;
    await _lockCoordinator.synchronized(
      _lockNameForTenant(normalizedTenant),
      () async {
        result = await _readForTenantUnlocked(normalizedTenant);
      },
    );
    return result;
  }

  Future<PersistedCart?> _readForTenantUnlocked(
    String normalizedTenant,
  ) async {
    final tenantKey = storageKeyForTenant(normalizedTenant);

    final scopedRaw = await _preferences.read(tenantKey);
    if (scopedRaw != null && scopedRaw.isNotEmpty) {
      final scoped = _decodeStrict(scopedRaw);
      if (scoped?.tenantId != normalizedTenant) {
        throw const FormatException(
          'El carrito guardado pertenece a otra tienda.',
        );
      }
      if (_isOutsideRetentionWindow(scoped!)) {
        await _removeTenantDocumentsUnlocked(
          normalizedTenant,
          failureMessage:
              'No se pudo retirar el carrito con fecha inválida o vencida.',
        );
        return null;
      }
      return scoped;
    }

    // One-time migration from the former same-origin global key. A document
    // belonging to another tenant is deliberately left untouched: opening one
    // storefront must never erase another storefront's basket.
    final legacyRaw = await _preferences.read(legacyStorageKey);
    if (legacyRaw == null || legacyRaw.isEmpty) return null;
    final legacy = _decodeStrict(legacyRaw)!;
    if (legacy.tenantId != normalizedTenant) return null;
    if (_isOutsideRetentionWindow(legacy)) {
      await _removeTenantDocumentsUnlocked(
        normalizedTenant,
        failureMessage:
            'No se pudo retirar el carrito con fecha inválida o vencida.',
      );
      return null;
    }

    await _writeRawAtKey(
      tenantKey,
      legacyRaw,
      failureMessage: 'No se pudo migrar el carrito guardado.',
    );
    await _removeVerified(
      legacyStorageKey,
      failureMessage: 'No se pudo completar la migración del carrito.',
    );
    return legacy;
  }

  @override
  Future<void> write(PersistedCart cart) async {
    await _lockCoordinator.synchronized(
      _storageLockName,
      () => _writeAtKey(legacyStorageKey, cart),
    );
  }

  @override
  Future<void> writeForTenant(
    String tenantId,
    PersistedCart cart,
  ) async {
    final normalizedTenant = tenantId.trim();
    if (normalizedTenant.isEmpty || cart.tenantId != normalizedTenant) {
      throw ArgumentError('El carrito no corresponde a esta tienda.');
    }
    await _lockCoordinator.synchronized(
      _lockNameForTenant(normalizedTenant),
      () => _writeAtKey(storageKeyForTenant(normalizedTenant), cart),
    );
  }

  Future<void> _writeAtKey(String key, PersistedCart cart) async {
    final encoded = jsonEncode(cart.toJson());
    final verified = PersistedCart.fromJson(jsonDecode(encoded));
    if (verified == null || verified.tenantId != cart.tenantId) {
      throw const FormatException('El carrito guardado no es válido.');
    }
    await _writeRawAtKey(
      key,
      encoded,
      failureMessage: 'No se pudo verificar el carrito guardado.',
    );
  }

  Future<void> _writeRawAtKey(
    String key,
    String encoded, {
    required String failureMessage,
  }) async {
    Object? writeError;
    StackTrace? writeStackTrace;
    var wrote = false;
    try {
      wrote = await _preferences.write(key, encoded);
    } catch (error, stackTrace) {
      writeError = error;
      writeStackTrace = stackTrace;
    }

    // A storage adapter can report a failed acknowledgement after the bytes
    // were already committed. Resolve that ambiguous outcome while the same
    // lock is still held so retrying the semantic command cannot double it.
    final String? observed;
    try {
      observed = await _readAfterMutation(key);
    } catch (_) {
      // The backend contract only returns true after its own durable readback.
      // A later diagnostic read failing cannot turn that acknowledgement into
      // an unknown outcome.
      if (writeError == null && wrote) return;
      rethrow;
    }
    if (observed == encoded) return;
    if (writeError != null) {
      Error.throwWithStackTrace(writeError, writeStackTrace!);
    }
    if (!wrote || observed != encoded) {
      throw StateError(failureMessage);
    }
  }

  @override
  Future<void> clear() async {
    await _lockCoordinator.synchronized(
      _storageLockName,
      () => _removeVerified(
        legacyStorageKey,
        failureMessage: 'No se pudo limpiar el carrito guardado.',
      ),
    );
  }

  @override
  Future<void> clearForTenant(String tenantId) async {
    final normalizedTenant = tenantId.trim();
    if (normalizedTenant.isEmpty) return;
    await _lockCoordinator.synchronized(
      _lockNameForTenant(normalizedTenant),
      () => _removeTenantDocumentsUnlocked(
        normalizedTenant,
        failureMessage: 'No se pudo limpiar el carrito guardado.',
      ),
    );
  }

  @override
  Future<CartCompareAndSetResult> compareAndSetForTenant({
    required String tenantId,
    required PersistedCart? expected,
    required PersistedCart? replacement,
  }) async {
    final normalizedTenant = tenantId.trim();
    if (normalizedTenant.isEmpty ||
        (expected != null && expected.tenantId != normalizedTenant) ||
        (replacement != null &&
            (replacement.tenantId != normalizedTenant ||
                replacement.revision?.trim().isEmpty != false))) {
      throw ArgumentError('El carrito no corresponde a esta tienda.');
    }

    late CartCompareAndSetResult result;
    await _lockCoordinator.synchronized(
      _lockNameForTenant(normalizedTenant),
      () async {
        final current = await _readForTenantUnlocked(normalizedTenant);
        if (!_sameDocument(current, expected)) {
          result = CartCompareAndSetResult(
            applied: false,
            document: current,
          );
          return;
        }

        final key = storageKeyForTenant(normalizedTenant);
        if (replacement == null) {
          if (current != null) {
            await _removeTenantDocumentsUnlocked(
              normalizedTenant,
              failureMessage: 'No se pudo retirar el carrito guardado.',
            );
          }
        } else {
          await _writeAtKey(key, replacement);
        }
        result = CartCompareAndSetResult(
          applied: true,
          document: replacement,
        );
      },
    );
    return result;
  }

  @override
  Future<CartConsumptionResult> consumeOrderedLines({
    required String tenantId,
    required List<PersistedCartLine> orderedLines,
    required String expectedRevision,
    CartConsumptionPreparation? prepare,
  }) async {
    final normalizedTenant = tenantId.trim();
    final normalizedRevision = expectedRevision.trim();
    if (normalizedTenant.isEmpty || normalizedRevision.isEmpty) {
      return const CartConsumptionResult(
        status: CartConsumptionStatus.unavailable,
        document: null,
      );
    }

    try {
      final firstDocument = await readForTenant(normalizedTenant);
      if (firstDocument?.revision != normalizedRevision) {
        return CartConsumptionResult(
          status: CartConsumptionStatus.conflict,
          document: firstDocument,
        );
      }

      final requestedByProduct = <String, int>{};
      for (final line in orderedLines) {
        final productId = line.productId.trim();
        if (productId.isEmpty || line.quantity < 1) {
          return CartConsumptionResult(
            status: CartConsumptionStatus.unavailable,
            document: firstDocument,
          );
        }
        requestedByProduct.update(
          productId,
          (quantity) => quantity + line.quantity,
          ifAbsent: () => line.quantity,
        );
      }
      if (requestedByProduct.isEmpty) {
        return CartConsumptionResult(
          status: CartConsumptionStatus.unavailable,
          document: firstDocument,
        );
      }

      final remainingLines = <PersistedCartLine>[];
      for (final line in firstDocument?.lines ?? const <PersistedCartLine>[]) {
        final orderedQuantity = requestedByProduct[line.productId] ?? 0;
        final remainingQuantity = line.quantity - orderedQuantity;
        if (remainingQuantity > 0) {
          remainingLines.add(
            PersistedCartLine(
              productId: line.productId,
              quantity: remainingQuantity,
            ),
          );
        }
      }
      final proposedDocument = PersistedCart(
        tenantId: normalizedTenant,
        savedAt: _now().toUtc(),
        lines: List<PersistedCartLine>.unmodifiable(remainingLines),
        revision: const Uuid().v4(),
        appliedMutations: {
          for (final mutation in firstDocument?.appliedMutations.entries ??
              const <MapEntry<String, DateTime>>[])
            if (!_isTimestampOutsideRetentionWindow(mutation.value))
              mutation.key: mutation.value,
        },
      );

      if (prepare != null && !await prepare(proposedDocument)) {
        return CartConsumptionResult(
          status: CartConsumptionStatus.unavailable,
          document: firstDocument,
        );
      }

      await beforeCommitValidation?.call();

      final exchange = await compareAndSetForTenant(
        tenantId: normalizedTenant,
        expected: firstDocument,
        replacement: proposedDocument,
      );
      if (!exchange.applied) {
        return CartConsumptionResult(
          status: CartConsumptionStatus.conflict,
          document: exchange.document,
        );
      }

      return CartConsumptionResult(
        status: CartConsumptionStatus.applied,
        document: exchange.document,
      );
    } catch (error) {
      debugPrint(
        '⚠️ [CartStore] Could not safely consume ordered lines: $error',
      );
      return const CartConsumptionResult(
        status: CartConsumptionStatus.unavailable,
        document: null,
      );
    }
  }

  PersistedCart? _decodeStrict(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = PersistedCart.fromJson(jsonDecode(raw));
      if (decoded == null) {
        throw const FormatException('El carrito guardado no es válido.');
      }
      return decoded;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('El carrito guardado no es válido.');
    }
  }

  bool _sameDocument(PersistedCart? left, PersistedCart? right) {
    if (identical(left, right)) return true;
    if (left == null || right == null) return false;
    return jsonEncode(left.toJson()) == jsonEncode(right.toJson());
  }

  bool _isOutsideRetentionWindow(PersistedCart cart) {
    return _isTimestampOutsideRetentionWindow(cart.savedAt);
  }

  bool _isTimestampOutsideRetentionWindow(DateTime timestamp) {
    final now = _now().toUtc();
    final normalized = timestamp.toUtc();
    return normalized.isAfter(now.add(CartStore.allowedFutureSkew)) ||
        now.difference(normalized) > CartStore.maxAge;
  }

  Future<void> _removeTenantDocumentsUnlocked(
    String normalizedTenant, {
    required String failureMessage,
  }) async {
    // A previous legacy migration may have committed the tenant-scoped copy
    // and then failed while deleting the old global key. Always remove a
    // matching residue together with the scoped document so a later read
    // cannot migrate it again and resurrect a cleared/consumed basket. Delete
    // the residue first: if that fails, the scoped canonical copy is preserved.
    final legacyRaw = await _preferences.read(legacyStorageKey);
    if (legacyRaw != null && legacyRaw.isNotEmpty) {
      PersistedCart? legacy;
      try {
        legacy = _decodeStrict(legacyRaw);
      } on FormatException {
        // A malformed global predecessor has no recoverable tenant ownership
        // and would block every future scoped read once this key is cleared.
        // Quarantine it through the same verified removal before touching the
        // valid scoped document.
        await _removeVerified(
          legacyStorageKey,
          failureMessage: failureMessage,
        );
      }
      if (legacy?.tenantId == normalizedTenant) {
        await _removeVerified(
          legacyStorageKey,
          failureMessage: failureMessage,
        );
      }
    }
    await _removeVerified(
      storageKeyForTenant(normalizedTenant),
      failureMessage: failureMessage,
    );
  }

  Future<String?> _readAfterMutation(String key) async {
    Object? lastError;
    StackTrace? lastStackTrace;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await _preferences.read(key);
      } catch (error, stackTrace) {
        lastError = error;
        lastStackTrace = stackTrace;
        if (attempt < 2) {
          await Future<void>.delayed(Duration.zero);
        }
      }
    }
    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  Future<void> _removeVerified(
    String key, {
    required String failureMessage,
  }) async {
    Object? removeError;
    StackTrace? removeStackTrace;
    var removed = false;
    try {
      removed = await _preferences.remove(key);
    } catch (error, stackTrace) {
      removeError = error;
      removeStackTrace = stackTrace;
    }
    final String? observed;
    try {
      observed = await _readAfterMutation(key);
    } catch (_) {
      if (removeError == null && removed) return;
      rethrow;
    }
    if (observed == null || observed.isEmpty) return;
    if (removeError != null) {
      Error.throwWithStackTrace(removeError, removeStackTrace!);
    }
    if (observed.isNotEmpty) {
      throw StateError(failureMessage);
    }
  }
}
