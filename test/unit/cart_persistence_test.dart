import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vinabike_erp/public_store/providers/cart_provider.dart';
import 'package:vinabike_erp/public_store/services/cart_lock.dart';
import 'package:vinabike_erp/public_store/services/cart_store.dart';
import 'package:vinabike_erp/shared/models/product.dart';

/// In-memory stand-in for SharedPreferences.
class _FakeCartStore extends CartStore {
  _FakeCartStore([this.stored]);

  PersistedCart? stored;
  int clearCount = 0;
  bool failReads = false;
  void Function(PersistedCart?)? onWrite;

  @override
  Future<PersistedCart?> read() async {
    if (failReads) throw StateError('simulated cart read failure');
    return stored;
  }

  @override
  Future<void> write(PersistedCart cart) async {
    stored = cart.lines.isEmpty ? null : cart;
    onWrite?.call(stored);
  }

  @override
  Future<void> clear() async {
    clearCount++;
    stored = null;
  }
}

class _ControlledConsumptionCartStore extends _FakeCartStore {
  _ControlledConsumptionCartStore(
    super.stored, {
    this.pauseBeforeConsumptionCommit = false,
  });

  final bool pauseBeforeConsumptionCommit;
  final Completer<void> consumptionPrepared = Completer<void>();
  final Completer<void> releaseConsumption = Completer<void>();
  final Completer<PersistedCart?> writeAfterConsumption =
      Completer<PersistedCart?>();
  bool _consumptionApplied = false;

  @override
  Future<void> write(PersistedCart cart) async {
    await super.write(cart);
    if (_consumptionApplied && !writeAfterConsumption.isCompleted) {
      writeAfterConsumption.complete(stored);
    }
  }

  @override
  Future<CartConsumptionResult> consumeOrderedLines({
    required String tenantId,
    required List<PersistedCartLine> orderedLines,
    required String expectedRevision,
    CartConsumptionPreparation? prepare,
  }) async {
    final current = stored;
    if (current != null && current.tenantId != tenantId) {
      return CartConsumptionResult(
        status: CartConsumptionStatus.unavailable,
        document: current,
      );
    }
    if (current?.revision != expectedRevision) {
      return CartConsumptionResult(
        status: CartConsumptionStatus.conflict,
        document: current,
      );
    }

    final requestedByProduct = <String, int>{};
    for (final line in orderedLines) {
      requestedByProduct.update(
        line.productId,
        (quantity) => quantity + line.quantity,
        ifAbsent: () => line.quantity,
      );
    }
    final remaining = <PersistedCartLine>[
      for (final line in current?.lines ?? const <PersistedCartLine>[])
        if (line.quantity - (requestedByProduct[line.productId] ?? 0) > 0)
          PersistedCartLine(
            productId: line.productId,
            quantity: line.quantity - (requestedByProduct[line.productId] ?? 0),
          ),
    ];
    final proposed = remaining.isEmpty
        ? null
        : PersistedCart(
            tenantId: tenantId,
            savedAt: DateTime.now().toUtc(),
            lines: remaining,
            revision: 'revision-consumed',
          );
    if (prepare != null && !await prepare(proposed)) {
      return CartConsumptionResult(
        status: CartConsumptionStatus.unavailable,
        document: current,
      );
    }

    if (!consumptionPrepared.isCompleted) {
      consumptionPrepared.complete();
    }
    if (pauseBeforeConsumptionCommit) {
      await releaseConsumption.future;
    }
    stored = proposed;
    _consumptionApplied = true;
    return CartConsumptionResult(
      status: CartConsumptionStatus.applied,
      document: proposed,
    );
  }
}

class _ControlledPreferencesBackend implements CartPreferencesBackend {
  final Map<String, String> values = <String, String>{};
  bool failWrites = false;
  bool failRemoves = false;
  final Set<String> failRemoveKeys = <String>{};
  bool applyThenRejectNextWrite = false;
  bool applyThenThrowWithReadFailureNextWrite = false;
  bool applyThenThrowWithReadFailureNextRemove = false;
  int readFailuresAfterAmbiguousWrite = 1;
  int readFailuresRemaining = 0;

  @override
  Future<String?> read(String key) async {
    if (readFailuresRemaining > 0) {
      readFailuresRemaining--;
      throw StateError('simulated cart readback failure');
    }
    return values[key];
  }

  @override
  Future<bool> write(String key, String value) async {
    if (failWrites) return false;
    values[key] = value;
    if (applyThenThrowWithReadFailureNextWrite) {
      applyThenThrowWithReadFailureNextWrite = false;
      readFailuresRemaining = readFailuresAfterAmbiguousWrite;
      throw StateError('simulated lost write acknowledgement');
    }
    if (applyThenRejectNextWrite) {
      applyThenRejectNextWrite = false;
      return false;
    }
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    if (failRemoves || failRemoveKeys.contains(key)) return false;
    values.remove(key);
    if (applyThenThrowWithReadFailureNextRemove) {
      applyThenThrowWithReadFailureNextRemove = false;
      readFailuresRemaining = 1;
      throw StateError('simulated lost remove acknowledgement');
    }
    return true;
  }
}

class _RejectingCartLockCoordinator implements CartLockCoordinator {
  const _RejectingCartLockCoordinator();

  @override
  Future<void> synchronized(
    String resourceName,
    Future<void> Function() action,
  ) {
    throw UnsupportedError('simulated unavailable Web Locks API');
  }
}

const _tenant = 'tenant-vinabike';

Product _product({
  required String id,
  String name = 'Cadena',
  double price = 13600,
  int stock = 20,
  bool trackStock = true,
  ProductType type = ProductType.product,
}) {
  return Product(
    id: id,
    name: name,
    sku: id.toUpperCase(),
    price: price,
    cost: 0,
    stockQuantity: stock,
    trackStock: trackStock,
    productType: type,
    category: ProductCategory.other,
    taxRate: 19,
    createdAt: DateTime.utc(2026, 7, 18),
    updatedAt: DateTime.utc(2026, 7, 18),
  );
}

PersistedCart _saved(
  List<PersistedCartLine> lines, {
  String tenantId = _tenant,
  Duration age = Duration.zero,
}) {
  return PersistedCart(
    tenantId: tenantId,
    savedAt: DateTime.now().toUtc().subtract(age),
    lines: lines,
    revision: 'revision-1',
  );
}

void main() {
  group('cart persistence', () {
    test('parser fails closed for malformed versions, line lists and rows', () {
      final base = <String, Object?>{
        'v': CartStore.schemaVersion,
        'tenant': _tenant,
        'saved_at': DateTime.now().toUtc().toIso8601String(),
        'lines': [
          {'id': 'chain', 'q': 2},
        ],
      };

      expect(PersistedCart.fromJson({...base, 'v': '1'}), isNull);
      expect(PersistedCart.fromJson({...base, 'v': 1.5}), isNull);
      expect(PersistedCart.fromJson({...base}..remove('lines')), isNull);
      expect(PersistedCart.fromJson({...base, 'lines': 'not-a-list'}), isNull);
      expect(
        PersistedCart.fromJson({
          ...base,
          'applied_mutations': 'not-a-list',
        }),
        isNull,
      );
      expect(
        PersistedCart.fromJson({
          ...base,
          'applied_mutations': ['', 7],
        }),
        isNull,
      );
      expect(
        PersistedCart.fromJson({
          ...base,
          'lines': [
            {'id': 'chain', 'q': 2},
            {'id': 'tube', 'q': 1.5},
          ],
        }),
        isNull,
      );
    });

    test('duplicate IDs deliberately retain the strongest single quantity', () {
      final parsed = PersistedCart.fromJson({
        'v': CartStore.schemaVersion,
        'tenant': _tenant,
        'saved_at': DateTime.now().toUtc().toIso8601String(),
        'lines': [
          {'id': 'chain', 'q': 2},
          {'id': 'chain', 'q': 5},
        ],
      });

      expect(parsed, isNotNull);
      expect(parsed!.lines, hasLength(1));
      expect(parsed.lines.single.productId, 'chain');
      expect(parsed.lines.single.quantity, 5);
    });

    test('a basket survives a reload', () async {
      final store = _FakeCartStore();
      final first = CartProvider(store: store);
      await first.restore(
        tenantId: _tenant,
        loadProducts: (_) async => const [],
      );
      first.addProduct(_product(id: 'chain'), quantity: 2);

      // The write is fire-and-forget; let it land.
      await Future<void>.delayed(Duration.zero);
      expect(store.stored?.lines.single.productId, 'chain');
      expect(store.stored?.lines.single.quantity, 2);

      final reloaded = CartProvider(store: store);
      await reloaded.restore(
        tenantId: _tenant,
        loadProducts: (ids) async =>
            ids.map((id) => _product(id: id)).toList(growable: false),
      );

      expect(reloaded.itemCount, 2);
      expect(reloaded.items.single.product.id, 'chain');
    });

    test('restores the live price, never the saved one', () async {
      // The reason only ids and quantities are stored.
      final store = _FakeCartStore(
        _saved([const PersistedCartLine(productId: 'chain', quantity: 1)]),
      );
      final cart = CartProvider(store: store);

      await cart.restore(
        tenantId: _tenant,
        loadProducts: (ids) async => [_product(id: ids.single, price: 15900)],
      );

      expect(cart.total, 15900);
    });

    test('total uses the exact whole-CLP tax calculation', () async {
      final cart = CartProvider(store: _FakeCartStore());
      await cart.restore(
        tenantId: _tenant,
        loadProducts: (_) async => const [],
      );
      cart.addProduct(_product(id: 'chain', price: 1190), quantity: 3);

      expect(cart.total, cart.taxSummary.grossAmount.toDouble());
      expect(
        cart.taxSummary.netAmount + cart.taxSummary.taxAmount,
        cart.total,
      );
    });

    test('drops a line whose product no longer exists', () async {
      final store = _FakeCartStore(
        _saved(const [
          PersistedCartLine(productId: 'chain', quantity: 1),
          PersistedCartLine(productId: 'deleted', quantity: 1),
        ]),
      );
      final cart = CartProvider(store: store);

      await cart.restore(
        tenantId: _tenant,
        loadProducts: (_) async => [_product(id: 'chain')],
      );

      expect(cart.items.length, 1);
      expect(cart.droppedOnRestore, 1);
    });

    test('never restores more units than the shop can deliver', () async {
      final store = _FakeCartStore(
        _saved(const [PersistedCartLine(productId: 'chain', quantity: 9)]),
      );
      final cart = CartProvider(store: store);

      await cart.restore(
        tenantId: _tenant,
        loadProducts: (_) async => [_product(id: 'chain', stock: 3)],
      );

      expect(cart.items.single.quantity, 3);
      expect(cart.droppedOnRestore, 1);
    });

    test('a sold-out line is dropped, not restored at zero', () async {
      final store = _FakeCartStore(
        _saved(const [PersistedCartLine(productId: 'chain', quantity: 2)]),
      );
      final cart = CartProvider(store: store);

      await cart.restore(
        tenantId: _tenant,
        loadProducts: (_) async => [_product(id: 'chain', stock: 0)],
      );

      expect(cart.isEmpty, isTrue);
      expect(cart.droppedOnRestore, 1);
    });

    test('an untracked service restores whatever was saved', () async {
      final store = _FakeCartStore(
        _saved(const [PersistedCartLine(productId: 'mant', quantity: 2)]),
      );
      final cart = CartProvider(store: store);

      await cart.restore(
        tenantId: _tenant,
        loadProducts: (_) async => [
          _product(
            id: 'mant',
            stock: 0,
            trackStock: false,
            type: ProductType.service,
          ),
        ],
      );

      expect(cart.items.single.quantity, 2);
      expect(cart.droppedOnRestore, 0);
    });

    test('a basket from another shop is ignored without deleting it', () async {
      final store = _FakeCartStore(
        _saved(
          const [PersistedCartLine(productId: 'chain', quantity: 1)],
          tenantId: 'another-shop',
        ),
      );
      final cart = CartProvider(store: store);

      await cart.restore(
        tenantId: _tenant,
        loadProducts: (_) async => [_product(id: 'chain')],
      );

      expect(cart.isEmpty, isTrue);
      expect(store.clearCount, 0);
      expect(store.stored?.tenantId, 'another-shop');
    });

    test('tenant keys isolate carts and migrate only a matching legacy cart',
        () async {
      const tenantB = 'tenant-b';
      final preferences = _ControlledPreferencesBackend();
      final legacy = _saved(const [
        PersistedCartLine(productId: 'chain', quantity: 2),
      ]);
      preferences.values[SharedPreferencesCartStore.legacyStorageKey] =
          jsonEncode(legacy.toJson());
      final store = SharedPreferencesCartStore(preferences: preferences);

      expect(await store.readForTenant(tenantB), isNull);
      expect(
        preferences.values[SharedPreferencesCartStore.legacyStorageKey],
        isNotNull,
      );

      final migrated = await store.readForTenant(_tenant);
      expect(migrated?.lines.single.quantity, 2);
      expect(
        preferences.values[SharedPreferencesCartStore.legacyStorageKey],
        isNull,
      );
      expect(
        preferences
            .values[SharedPreferencesCartStore.storageKeyForTenant(_tenant)],
        isNotNull,
      );

      await store.writeForTenant(
        tenantB,
        PersistedCart(
          tenantId: tenantB,
          savedAt: DateTime.now().toUtc(),
          lines: const [
            PersistedCartLine(productId: 'tube', quantity: 1),
          ],
          revision: 'tenant-b-revision',
        ),
      );
      expect((await store.readForTenant(_tenant))?.lines.single.productId,
          'chain');
      expect(
        (await store.readForTenant(tenantB))?.lines.single.productId,
        'tube',
      );

      await store.clearForTenant(tenantB);
      expect(await store.readForTenant(tenantB), isNull);
      expect((await store.readForTenant(_tenant))?.lines.single.quantity, 2);
    });

    test('an incomplete legacy migration cannot resurrect a cleared cart',
        () async {
      final preferences = _ControlledPreferencesBackend()
        ..failRemoveKeys.add(SharedPreferencesCartStore.legacyStorageKey);
      final legacy = _saved(const [
        PersistedCartLine(productId: 'chain', quantity: 2),
      ]);
      final scopedKey = SharedPreferencesCartStore.storageKeyForTenant(_tenant);
      preferences.values[SharedPreferencesCartStore.legacyStorageKey] =
          jsonEncode(legacy.toJson());
      final store = SharedPreferencesCartStore(preferences: preferences);

      await expectLater(store.readForTenant(_tenant), throwsStateError);
      expect(preferences.values[scopedKey], isNotNull);
      expect(
        preferences.values[SharedPreferencesCartStore.legacyStorageKey],
        isNotNull,
      );

      // A failed cleanup must preserve the scoped canonical copy. Once
      // storage recovers, both copies are removed in legacy-first order.
      await expectLater(store.clearForTenant(_tenant), throwsStateError);
      expect(preferences.values[scopedKey], isNotNull);

      preferences.failRemoveKeys.clear();
      await store.clearForTenant(_tenant);

      expect(preferences.values[scopedKey], isNull);
      expect(
        preferences.values[SharedPreferencesCartStore.legacyStorageKey],
        isNull,
      );
      expect(await store.readForTenant(_tenant), isNull);
    });

    test('a corrupt unowned legacy value cannot block scoped cleanup',
        () async {
      final preferences = _ControlledPreferencesBackend();
      final scopedKey = SharedPreferencesCartStore.storageKeyForTenant(_tenant);
      final store = SharedPreferencesCartStore(preferences: preferences);
      await store.writeForTenant(
        _tenant,
        _saved(const [
          PersistedCartLine(productId: 'chain', quantity: 1),
        ]),
      );
      preferences.values[SharedPreferencesCartStore.legacyStorageKey] =
          '{"v":1,"tenant":"broken"';

      await store.clearForTenant(_tenant);

      expect(preferences.values[scopedKey], isNull);
      expect(
        preferences.values[SharedPreferencesCartStore.legacyStorageKey],
        isNull,
      );
      expect(await store.readForTenant(_tenant), isNull);
    });

    test('a rejected cross-tab lock cannot mutate durable cart bytes',
        () async {
      final preferences = _ControlledPreferencesBackend();
      final scopedKey = SharedPreferencesCartStore.storageKeyForTenant(_tenant);
      final original = _saved(const [
        PersistedCartLine(productId: 'chain', quantity: 1),
      ]);
      final originalBytes = jsonEncode(original.toJson());
      preferences.values[scopedKey] = originalBytes;
      final store = SharedPreferencesCartStore(
        preferences: preferences,
        lockCoordinator: const _RejectingCartLockCoordinator(),
      );

      await expectLater(
        store.compareAndSetForTenant(
          tenantId: _tenant,
          expected: original,
          replacement: null,
        ),
        throwsUnsupportedError,
      );

      expect(preferences.values[scopedKey], originalBytes);
    });

    test('a stale basket is discarded rather than silently revived', () async {
      final store = _FakeCartStore(
        _saved(
          const [PersistedCartLine(productId: 'chain', quantity: 1)],
          age: CartStore.maxAge + const Duration(days: 1),
        ),
      );
      final cart = CartProvider(store: store);

      await cart.restore(
        tenantId: _tenant,
        loadProducts: (_) async => [_product(id: 'chain')],
      );

      expect(cart.isEmpty, isTrue);
      expect(store.clearCount, 1);
    });

    test('a basket more than five minutes in the future is discarded',
        () async {
      final now = DateTime.utc(2026, 7, 28, 12);
      final store = _FakeCartStore(
        PersistedCart(
          tenantId: _tenant,
          savedAt: now.add(
            CartStore.allowedFutureSkew + const Duration(seconds: 1),
          ),
          lines: const [
            PersistedCartLine(productId: 'chain', quantity: 1),
          ],
          revision: 'future-revision',
        ),
      );
      final cart = CartProvider(store: store, now: () => now);

      await cart.restore(
        tenantId: _tenant,
        loadProducts: (_) async => [_product(id: 'chain')],
      );

      expect(cart.isEmpty, isTrue);
      expect(store.clearCount, 1);
      expect(store.stored, isNull);
    });

    test('a failed revalidation keeps the saved basket for the next try',
        () async {
      // A transport failure is not proof the basket is gone.
      final saved =
          _saved(const [PersistedCartLine(productId: 'chain', quantity: 1)]);
      final store = _FakeCartStore(saved);
      final cart = CartProvider(store: store);

      await cart.restore(
        tenantId: _tenant,
        loadProducts: (_) async => throw Exception('offline'),
      );

      expect(cart.isEmpty, isTrue);
      expect(store.stored, same(saved));
      expect(store.clearCount, 0);
    });

    test('a mutation during restore is replayed over the recovered baseline',
        () async {
      final store = _FakeCartStore(
        _saved(const [PersistedCartLine(productId: 'chain', quantity: 5)]),
      );
      final cart = CartProvider(store: store);

      final pending = cart.restore(
        tenantId: _tenant,
        loadProducts: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return [_product(id: 'chain')];
        },
      );
      cart.addProduct(_product(id: 'tube'), quantity: 1);
      await pending;

      expect(
        {
          for (final item in cart.items) item.product.id: item.quantity,
        },
        {'chain': 5, 'tube': 1},
      );
      expect(
        {
          for (final line in store.stored!.lines) line.productId: line.quantity,
        },
        {'chain': 5, 'tube': 1},
      );
    });

    test('a mutation from an unknown baseline waits for the tenant restore',
        () async {
      final store = _FakeCartStore(
        _saved(const [PersistedCartLine(productId: 'chain', quantity: 2)]),
      );
      final originalRevision = store.stored!.revision;
      final cart = CartProvider(store: store);

      cart.addProduct(_product(id: 'tube'));
      await Future<void>.delayed(Duration.zero);
      expect(store.stored?.revision, originalRevision);
      expect(store.stored?.lines.single.productId, 'chain');

      await cart.restore(
        tenantId: _tenant,
        loadProducts: (ids) async =>
            ids.map((id) => _product(id: id)).toList(growable: false),
      );

      expect(
        {
          for (final line in store.stored!.lines) line.productId: line.quantity,
        },
        {'chain': 2, 'tube': 1},
      );
      expect(
        {
          for (final item in cart.items) item.product.id: item.quantity,
        },
        {'chain': 2, 'tube': 1},
      );
    });

    test('read failure then mutation recovers and merges the durable baseline',
        () async {
      final store = _FakeCartStore(
        _saved(const [PersistedCartLine(productId: 'chain', quantity: 2)]),
      )..failReads = true;
      final writeObserved = Completer<void>();
      final cart = CartProvider(store: store);
      Future<List<Product>> loader(List<String> ids) async =>
          ids.map((id) => _product(id: id)).toList(growable: false);

      await cart.restore(tenantId: _tenant, loadProducts: loader);
      expect(store.stored!.lines.single.quantity, 2);

      store
        ..failReads = false
        ..onWrite = (_) {
          if (!writeObserved.isCompleted) writeObserved.complete();
        };
      cart.addProduct(_product(id: 'tube'));
      await writeObserved.future.timeout(const Duration(seconds: 1));

      expect(
        {
          for (final line in store.stored!.lines) line.productId: line.quantity,
        },
        {'chain': 2, 'tube': 1},
      );
      expect(
        {
          for (final item in cart.items) item.product.id: item.quantity,
        },
        {'chain': 2, 'tube': 1},
      );
    });

    test(
        'catalog failure then mutation retries revalidation before persistence',
        () async {
      final store = _FakeCartStore(
        _saved(const [PersistedCartLine(productId: 'chain', quantity: 3)]),
      );
      var catalogAvailable = false;
      final writeObserved = Completer<void>();
      final cart = CartProvider(store: store);
      Future<List<Product>> loader(List<String> ids) async {
        if (!catalogAvailable) throw StateError('catalog offline');
        return ids.map((id) => _product(id: id)).toList(growable: false);
      }

      await cart.restore(tenantId: _tenant, loadProducts: loader);
      catalogAvailable = true;
      store.onWrite = (_) {
        if (!writeObserved.isCompleted) writeObserved.complete();
      };
      cart.addProduct(_product(id: 'tube'));
      await writeObserved.future.timeout(const Duration(seconds: 1));

      expect(
        {
          for (final line in store.stored!.lines) line.productId: line.quantity,
        },
        {'chain': 3, 'tube': 1},
      );
      expect(
        {
          for (final item in cart.items) item.product.id: item.quantity,
        },
        {'chain': 3, 'tube': 1},
      );
    });

    test('a late restore from another tenant cannot cross the scope', () async {
      final store = _FakeCartStore(
        _saved(const [PersistedCartLine(productId: 'chain', quantity: 2)]),
      );
      final cart = CartProvider(store: store);
      final oldLoadStarted = Completer<void>();
      final releaseOldLoad = Completer<void>();

      final oldScope = cart.restore(
        tenantId: _tenant,
        loadProducts: (_) async {
          oldLoadStarted.complete();
          await releaseOldLoad.future;
          return [_product(id: 'chain')];
        },
      );
      await oldLoadStarted.future;
      await cart.restore(
        tenantId: 'tenant-b',
        loadProducts: (_) async => const [],
      );
      cart.addProduct(_product(id: 'tube'));
      await Future<void>.delayed(Duration.zero);
      releaseOldLoad.complete();
      await oldScope;

      expect(cart.items.single.product.id, 'tube');
      expect(cart.itemCount, 1);
      expect(store.stored?.tenantId, 'tenant-b');
    });

    test('tracked quantities are capped while services stay incrementable',
        () async {
      final cart = CartProvider(store: _FakeCartStore());
      await cart.restore(
        tenantId: _tenant,
        loadProducts: (_) async => const [],
      );

      cart.addProduct(_product(id: 'chain', stock: 2), quantity: 9);
      expect(cart.items.single.quantity, 2);
      cart.incrementQuantity('chain');
      expect(cart.items.single.quantity, 2);

      cart.addProduct(
        _product(
          id: 'service',
          stock: 0,
          trackStock: false,
          type: ProductType.service,
        ),
      );
      cart.incrementQuantity('service');
      expect(cart.getProductQuantity('service'), 2);
    });

    test('clearing the cart clears the saved copy', () async {
      final store = _FakeCartStore();
      final cart = CartProvider(store: store);
      await cart.restore(
        tenantId: _tenant,
        loadProducts: (ids) async =>
            ids.map((id) => _product(id: id)).toList(growable: false),
      );

      cart.addProduct(_product(id: 'chain'));
      await Future<void>.delayed(Duration.zero);
      expect(store.stored, isNotNull);

      cart.clear();
      await Future<void>.delayed(Duration.zero);
      expect(store.stored, isNull);
    });

    test('a rejected preferences write keeps commands pending for retry',
        () async {
      final preferences = _ControlledPreferencesBackend()..failWrites = true;
      final store = SharedPreferencesCartStore(preferences: preferences);
      final cart = CartProvider(store: store);
      await cart.restore(
        tenantId: _tenant,
        loadProducts: (ids) async =>
            ids.map((id) => _product(id: id)).toList(growable: false),
      );

      cart.addProduct(_product(id: 'chain'));
      await Future<void>.delayed(Duration.zero);
      expect(await store.readForTenant(_tenant), isNull);

      preferences.failWrites = false;
      cart.addProduct(_product(id: 'tube'));
      await Future<void>.delayed(Duration.zero);

      final persisted = await store.readForTenant(_tenant);
      expect(
        {
          for (final line in persisted!.lines) line.productId: line.quantity,
        },
        {'chain': 1, 'tube': 1},
      );
    });

    test('an applied write with a lost acknowledgement is not replayed',
        () async {
      final preferences = _ControlledPreferencesBackend()
        ..applyThenRejectNextWrite = true;
      final store = SharedPreferencesCartStore(preferences: preferences);
      final cart = CartProvider(store: store);
      Future<List<Product>> loader(List<String> ids) async =>
          ids.map((id) => _product(id: id)).toList(growable: false);
      await cart.restore(tenantId: _tenant, loadProducts: loader);

      cart.addProduct(_product(id: 'chain'));
      await cart.debugWaitForPersistence();
      cart.addProduct(_product(id: 'tube'));
      await cart.debugWaitForPersistence();

      final persisted = await store.readForTenant(_tenant);
      expect(
        {
          for (final line in persisted!.lines) line.productId: line.quantity,
        },
        {'chain': 1, 'tube': 1},
      );
    });

    test(
        'an applied throwing write survives a transient readback failure without replay',
        () async {
      final preferences = _ControlledPreferencesBackend()
        ..applyThenThrowWithReadFailureNextWrite = true;
      final store = SharedPreferencesCartStore(preferences: preferences);
      final cart = CartProvider(store: store);
      Future<List<Product>> loader(List<String> ids) async =>
          ids.map((id) => _product(id: id)).toList(growable: false);
      await cart.restore(tenantId: _tenant, loadProducts: loader);

      cart.addProduct(_product(id: 'chain'));
      await cart.debugWaitForPersistence();
      cart.addProduct(_product(id: 'tube'));
      await cart.debugWaitForPersistence();

      final persisted = await store.readForTenant(_tenant);
      expect(
        {
          for (final line in persisted!.lines) line.productId: line.quantity,
        },
        {'chain': 1, 'tube': 1},
      );
    });

    test('a persistently ambiguous applied write is idempotent after recovery',
        () async {
      final preferences = _ControlledPreferencesBackend()
        ..applyThenThrowWithReadFailureNextWrite = true
        ..readFailuresAfterAmbiguousWrite = 3;
      final store = SharedPreferencesCartStore(preferences: preferences);
      final cart = CartProvider(store: store);
      Future<List<Product>> loader(List<String> ids) async =>
          ids.map((id) => _product(id: id)).toList(growable: false);
      await cart.restore(tenantId: _tenant, loadProducts: loader);

      cart.addProduct(_product(id: 'chain'));
      await cart.debugWaitForPersistence();
      final ambiguouslyApplied = await store.readForTenant(_tenant);
      expect(ambiguouslyApplied!.lines.single.quantity, 1);
      expect(ambiguouslyApplied.appliedMutationIds, hasLength(1));

      // Recovery sees the persisted operation ID and retires the still-pending
      // command instead of applying its +1 for a second time.
      await cart.restore(tenantId: _tenant, loadProducts: loader);
      cart.addProduct(_product(id: 'tube'));
      await cart.debugWaitForPersistence();

      final persisted = await store.readForTenant(_tenant);
      expect(
        {
          for (final line in persisted!.lines) line.productId: line.quantity,
        },
        {'chain': 1, 'tube': 1},
      );
      expect(persisted.appliedMutationIds, hasLength(2));
    });

    test('an ambiguous pending command expires with its durable document',
        () async {
      final preferences = _ControlledPreferencesBackend()
        ..applyThenThrowWithReadFailureNextWrite = true
        ..readFailuresAfterAmbiguousWrite = 3;
      var now = DateTime.utc(2026, 7, 28, 12);
      final store = SharedPreferencesCartStore(
        preferences: preferences,
        now: () => now,
      );
      final cart = CartProvider(store: store, now: () => now);
      Future<List<Product>> loader(List<String> ids) async =>
          ids.map((id) => _product(id: id)).toList(growable: false);
      await cart.restore(tenantId: _tenant, loadProducts: loader);

      cart.addProduct(_product(id: 'chain'));
      await cart.debugWaitForPersistence();
      expect(
        (await store.readForTenant(_tenant))!.appliedMutationIds,
        hasLength(1),
      );

      now = now.add(CartStore.maxAge + const Duration(seconds: 1));
      await cart.restore(tenantId: _tenant, loadProducts: loader);
      cart.addProduct(_product(id: 'tube'));
      await cart.debugWaitForPersistence();

      final persisted = await store.readForTenant(_tenant);
      expect(
        {
          for (final line in persisted!.lines) line.productId: line.quantity,
        },
        {'tube': 1},
      );
      expect(persisted.appliedMutationIds, hasLength(1));
    });

    test('a fresh mutation compacts expired operation lineage', () async {
      final preferences = _ControlledPreferencesBackend();
      final now = DateTime.utc(2026, 7, 28, 12);
      final store = SharedPreferencesCartStore(
        preferences: preferences,
        now: () => now,
      );
      await store.writeForTenant(
        _tenant,
        PersistedCart(
          tenantId: _tenant,
          savedAt: now,
          lines: const [
            PersistedCartLine(productId: 'chain', quantity: 1),
          ],
          revision: 'revision-with-old-lineage',
          appliedMutations: {
            'old-operation':
                now.subtract(CartStore.maxAge + const Duration(seconds: 1)),
          },
        ),
      );
      final cart = CartProvider(store: store, now: () => now);
      await cart.restore(
        tenantId: _tenant,
        loadProducts: (ids) async =>
            ids.map((id) => _product(id: id)).toList(growable: false),
      );

      cart.addProduct(_product(id: 'tube'));
      await cart.debugWaitForPersistence();

      final persisted = await store.readForTenant(_tenant);
      expect(persisted!.appliedMutationIds, hasLength(1));
      expect(persisted.appliedMutationIds, isNot(contains('old-operation')));
    });

    test('a rejected preferences removal throws and preserves the document',
        () async {
      final preferences = _ControlledPreferencesBackend();
      final store = SharedPreferencesCartStore(preferences: preferences);
      await store.writeForTenant(
        _tenant,
        _saved(const [
          PersistedCartLine(productId: 'chain', quantity: 1),
        ]),
      );
      preferences.failRemoves = true;

      await expectLater(store.clearForTenant(_tenant), throwsStateError);
      expect(
        (await store.readForTenant(_tenant))?.lines.single.productId,
        'chain',
      );
    });

    test('an applied removal survives a transient readback failure', () async {
      final preferences = _ControlledPreferencesBackend();
      final store = SharedPreferencesCartStore(preferences: preferences);
      await store.writeForTenant(
        _tenant,
        _saved(const [
          PersistedCartLine(productId: 'chain', quantity: 1),
        ]),
      );
      preferences.applyThenThrowWithReadFailureNextRemove = true;

      await store.clearForTenant(_tenant);

      expect(await store.readForTenant(_tenant), isNull);
    });

    test('consumption waits for a loading baseline and cannot be revived',
        () async {
      final store = _ControlledConsumptionCartStore(
        _saved(const [
          PersistedCartLine(productId: 'chain', quantity: 2),
        ]),
      );
      final catalogLoadStarted = Completer<void>();
      final releaseCatalogLoad = Completer<void>();
      final cart = CartProvider(store: store);

      final restoring = cart.restore(
        tenantId: _tenant,
        loadProducts: (ids) async {
          if (!catalogLoadStarted.isCompleted) {
            catalogLoadStarted.complete();
          }
          await releaseCatalogLoad.future;
          return ids.map((id) => _product(id: id)).toList(growable: false);
        },
      );
      await catalogLoadStarted.future;

      var consumptionCompleted = false;
      final consuming = cart
          .consumeOrderedLines(
            tenantId: _tenant,
            orderedLines: const [
              PersistedCartLine(productId: 'chain', quantity: 2),
            ],
            expectedRevision: store.stored!.revision!,
          )
          .whenComplete(() => consumptionCompleted = true);
      await Future<void>.delayed(Duration.zero);
      expect(consumptionCompleted, isFalse);
      expect(store.consumptionPrepared.isCompleted, isFalse);
      expect(store.stored?.lines.single.quantity, 2);

      releaseCatalogLoad.complete();
      final result = await consuming;
      expect(result.status, CartConsumptionStatus.applied);
      expect(store.stored, isNull);

      await restoring;
      await Future<void>.delayed(Duration.zero);

      expect(cart.isEmpty, isTrue);
      expect(store.stored, isNull);
      expect(store.writeAfterConsumption.isCompleted, isFalse);
    });

    test('an addition during consumption is rebased without reviving old units',
        () async {
      final store = _ControlledConsumptionCartStore(
        _saved(const [
          PersistedCartLine(productId: 'chain', quantity: 2),
        ]),
        pauseBeforeConsumptionCommit: true,
      );
      final cart = CartProvider(store: store);
      Future<List<Product>> loader(List<String> ids) async =>
          ids.map((id) => _product(id: id)).toList(growable: false);
      await cart.restore(tenantId: _tenant, loadProducts: loader);

      final consuming = cart.consumeOrderedLines(
        tenantId: _tenant,
        orderedLines: const [
          PersistedCartLine(productId: 'chain', quantity: 2),
        ],
        expectedRevision: store.stored!.revision!,
      );
      await store.consumptionPrepared.future;

      // The old basket is A×2. This click expresses one new unit while the
      // durable consume is in flight; it must not snapshot and restore A×3.
      cart.addProduct(_product(id: 'chain'));
      expect(cart.getProductQuantity('chain'), 3);

      store.releaseConsumption.complete();
      final result = await consuming;
      final persisted = await store.writeAfterConsumption.future.timeout(
        const Duration(seconds: 1),
      );

      expect(result.status, CartConsumptionStatus.applied);
      expect(cart.getProductQuantity('chain'), 1);
      expect(persisted, isNotNull);
      expect(persisted!.lines.single.productId, 'chain');
      expect(persisted.lines.single.quantity, 1);
    });

    test(
        'fresh consumption subtracts partially and preserves a line from another provider',
        () async {
      SharedPreferences.setMockInitialValues({});
      final firstStore = SharedPreferencesCartStore();
      final secondStore = SharedPreferencesCartStore();
      final first = CartProvider(store: firstStore);
      final second = CartProvider(store: secondStore);
      Future<List<Product>> loader(List<String> ids) async =>
          ids.map((id) => _product(id: id)).toList(growable: false);

      await first.restore(tenantId: _tenant, loadProducts: loader);
      first.addProduct(_product(id: 'chain'), quantity: 3);
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final checkoutRevision =
          (await firstStore.readForTenant(_tenant))!.revision!;

      // A second provider represents another tab. It sees A×3, adds B and
      // persists A×3+B while the first provider's memory remains stale.
      await second.restore(tenantId: _tenant, loadProducts: loader);
      second.addProduct(_product(id: 'tube'));
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(first.hasProduct('tube'), isFalse);

      final result = await first.consumeOrderedLines(
        tenantId: _tenant,
        orderedLines: const [
          PersistedCartLine(productId: 'chain', quantity: 1),
        ],
        expectedRevision: checkoutRevision,
      );

      expect(result.status, CartConsumptionStatus.conflict);
      expect(first.getProductQuantity('chain'), 3);
      expect(first.getProductQuantity('tube'), 1);
      final persisted = await firstStore.readForTenant(_tenant);
      expect(
        {
          for (final line in persisted!.lines) line.productId: line.quantity,
        },
        {'chain': 3, 'tube': 1},
      );
    });

    test(
        'two restored providers rebase concurrent semantic additions instead of last-writer-wins',
        () async {
      SharedPreferences.setMockInitialValues({});
      final seedStore = SharedPreferencesCartStore();
      await seedStore.writeForTenant(
        _tenant,
        _saved(const [
          PersistedCartLine(productId: 'base', quantity: 1),
        ]),
      );

      final firstStore = SharedPreferencesCartStore();
      final secondStore = SharedPreferencesCartStore();
      final first = CartProvider(store: firstStore);
      final second = CartProvider(store: secondStore);
      var pausePersistenceLoads = false;
      var pausedLoads = 0;
      final bothLoadsStarted = Completer<void>();
      final releaseLoads = Completer<void>();
      Future<List<Product>> loader(List<String> ids) async {
        if (pausePersistenceLoads && ids.contains('base')) {
          pausedLoads++;
          if (pausedLoads == 2 && !bothLoadsStarted.isCompleted) {
            bothLoadsStarted.complete();
          }
          await releaseLoads.future;
        }
        return ids.map((id) => _product(id: id)).toList(growable: false);
      }

      await Future.wait([
        first.restore(tenantId: _tenant, loadProducts: loader),
        second.restore(tenantId: _tenant, loadProducts: loader),
      ]);
      pausePersistenceLoads = true;

      first.addProduct(_product(id: 'chain'));
      second.addProduct(_product(id: 'tube'));
      await bothLoadsStarted.future;
      releaseLoads.complete();
      await Future.wait([
        first.debugWaitForPersistence(),
        second.debugWaitForPersistence(),
      ]);

      final persisted = await seedStore.readForTenant(_tenant);
      expect(
        {
          for (final line in persisted!.lines) line.productId: line.quantity,
        },
        {'base': 1, 'chain': 1, 'tube': 1},
      );
    });

    test('an addition paused before CAS rebases after another tab clears',
        () async {
      final preferences = _ControlledPreferencesBackend();
      final seedStore = SharedPreferencesCartStore(preferences: preferences);
      await seedStore.writeForTenant(
        _tenant,
        _saved(const [
          PersistedCartLine(productId: 'base', quantity: 1),
        ]),
      );
      final addTab = CartProvider(
        store: SharedPreferencesCartStore(preferences: preferences),
      );
      final clearTab = CartProvider(
        store: SharedPreferencesCartStore(preferences: preferences),
      );
      var pauseAddPersistence = false;
      final addLoadStarted = Completer<void>();
      final releaseAddLoad = Completer<void>();
      Future<List<Product>> addLoader(List<String> ids) async {
        if (pauseAddPersistence && ids.contains('base')) {
          addLoadStarted.complete();
          await releaseAddLoad.future;
        }
        return ids.map((id) => _product(id: id)).toList(growable: false);
      }

      await Future.wait([
        addTab.restore(tenantId: _tenant, loadProducts: addLoader),
        clearTab.restore(
          tenantId: _tenant,
          loadProducts: (ids) async =>
              ids.map((id) => _product(id: id)).toList(growable: false),
        ),
      ]);

      pauseAddPersistence = true;
      addTab.addProduct(_product(id: 'tube'));
      await addLoadStarted.future;

      clearTab.clear();
      await clearTab.debugWaitForPersistence();
      final cleared = await seedStore.readForTenant(_tenant);
      expect(cleared, isNotNull);
      expect(cleared!.lines, isEmpty);

      releaseAddLoad.complete();
      await addTab.debugWaitForPersistence();

      final persisted = await seedStore.readForTenant(_tenant);
      expect(
        {
          for (final line in persisted!.lines) line.productId: line.quantity,
        },
        {'tube': 1},
      );
      expect(persisted.appliedMutationIds, hasLength(2));
    });

    test('a stale command uses freshly revalidated stock while rebasing',
        () async {
      final preferences = _ControlledPreferencesBackend();
      final seedStore = SharedPreferencesCartStore(preferences: preferences);
      await seedStore.writeForTenant(
        _tenant,
        _saved(const [
          PersistedCartLine(productId: 'chain', quantity: 1),
        ]),
      );
      var authoritativeStock = 2;
      Future<List<Product>> loader(List<String> ids) async => ids
          .map(
            (id) => _product(
              id: id,
              stock: id == 'chain' ? authoritativeStock : 20,
            ),
          )
          .toList(growable: false);
      final staleTab = CartProvider(
        store: SharedPreferencesCartStore(preferences: preferences),
      );
      await staleTab.restore(tenantId: _tenant, loadProducts: loader);

      // Another tab grows the same line after this provider captured stock=2.
      authoritativeStock = 10;
      await seedStore.writeForTenant(
        _tenant,
        PersistedCart(
          tenantId: _tenant,
          savedAt: DateTime.now().toUtc(),
          lines: const [
            PersistedCartLine(productId: 'chain', quantity: 3),
          ],
          revision: 'revision-other-tab',
        ),
      );

      staleTab.incrementQuantity('chain');
      await staleTab.debugWaitForPersistence();

      expect(
        (await seedStore.readForTenant(_tenant))!.lines.single.quantity,
        4,
      );
      expect(staleTab.getProductQuantity('chain'), 4);
    });

    test('a stale command cannot revive a product that is now sold out',
        () async {
      final preferences = _ControlledPreferencesBackend();
      final store = SharedPreferencesCartStore(preferences: preferences);
      await store.writeForTenant(
        _tenant,
        _saved(const [
          PersistedCartLine(productId: 'chain', quantity: 1),
        ]),
      );
      var authoritativeStock = 2;
      Future<List<Product>> loader(List<String> ids) async => ids
          .map((id) => _product(id: id, stock: authoritativeStock))
          .toList(growable: false);
      final staleTab = CartProvider(store: store);
      await staleTab.restore(tenantId: _tenant, loadProducts: loader);

      authoritativeStock = 0;
      staleTab.incrementQuantity('chain');
      await staleTab.debugWaitForPersistence();

      final persisted = await store.readForTenant(_tenant);
      expect(persisted, isNotNull);
      expect(persisted!.lines, isEmpty);
      expect(persisted.appliedMutationIds, hasLength(1));
      expect(staleTab.hasProduct('chain'), isFalse);
    });

    test('a ready tab cannot revive a basket that expires while left open',
        () async {
      final preferences = _ControlledPreferencesBackend();
      var now = DateTime.utc(2026, 7, 28, 12);
      final store = SharedPreferencesCartStore(
        preferences: preferences,
        now: () => now,
      );
      await store.writeForTenant(
        _tenant,
        PersistedCart(
          tenantId: _tenant,
          savedAt: now,
          lines: const [
            PersistedCartLine(productId: 'chain', quantity: 1),
          ],
          revision: 'revision-before-expiry',
        ),
      );
      Future<List<Product>> loader(List<String> ids) async =>
          ids.map((id) => _product(id: id)).toList(growable: false);
      final tab = CartProvider(store: store, now: () => now);
      await tab.restore(tenantId: _tenant, loadProducts: loader);

      now = now.add(CartStore.maxAge + const Duration(seconds: 1));
      tab.addProduct(_product(id: 'tube'));
      await tab.debugWaitForPersistence();

      final persisted = await store.readForTenant(_tenant);
      expect(
        {
          for (final line in persisted!.lines) line.productId: line.quantity,
        },
        {'tube': 1},
      );
      expect(tab.hasProduct('chain'), isFalse);
    });

    test('checkout cannot capture a revision after the open cart expires',
        () async {
      final preferences = _ControlledPreferencesBackend();
      var now = DateTime.utc(2026, 7, 28, 12);
      final store = SharedPreferencesCartStore(
        preferences: preferences,
        now: () => now,
      );
      await store.writeForTenant(
        _tenant,
        PersistedCart(
          tenantId: _tenant,
          savedAt: now,
          lines: const [
            PersistedCartLine(productId: 'chain', quantity: 1),
          ],
          revision: 'revision-before-expiry',
        ),
      );
      final tab = CartProvider(store: store, now: () => now);
      await tab.restore(
        tenantId: _tenant,
        loadProducts: (_) async => [_product(id: 'chain')],
      );

      now = now.add(CartStore.maxAge + const Duration(seconds: 1));

      await expectLater(
        tab.captureDurableCheckoutRevision(
          tenantId: _tenant,
          orderedLines: const [
            PersistedCartLine(productId: 'chain', quantity: 1),
          ],
        ),
        throwsStateError,
      );
      expect(await store.readForTenant(_tenant), isNull);
    });

    test('a stale provider cannot revive units consumed by another tab',
        () async {
      SharedPreferences.setMockInitialValues({});
      final seedStore = SharedPreferencesCartStore();
      await seedStore.writeForTenant(
        _tenant,
        _saved(const [
          PersistedCartLine(productId: 'chain', quantity: 1),
        ]),
      );
      final checkoutStore = SharedPreferencesCartStore();
      final staleStore = SharedPreferencesCartStore();
      final checkoutTab = CartProvider(store: checkoutStore);
      final staleTab = CartProvider(store: staleStore);
      Future<List<Product>> loader(List<String> ids) async =>
          ids.map((id) => _product(id: id)).toList(growable: false);
      await Future.wait([
        checkoutTab.restore(tenantId: _tenant, loadProducts: loader),
        staleTab.restore(tenantId: _tenant, loadProducts: loader),
      ]);

      final revision = (await checkoutStore.readForTenant(_tenant))!.revision!;
      final consumed = await checkoutTab.consumeOrderedLines(
        tenantId: _tenant,
        orderedLines: const [
          PersistedCartLine(productId: 'chain', quantity: 1),
        ],
        expectedRevision: revision,
      );
      expect(consumed.status, CartConsumptionStatus.applied);

      // This tab still displays the stale chain locally when the click occurs.
      // Its semantic "add tube" command must be rebased over durable empty,
      // never persisted as the stale whole-document {chain, tube}.
      staleTab.addProduct(_product(id: 'tube'));
      await staleTab.debugWaitForPersistence();

      final persisted = await seedStore.readForTenant(_tenant);
      expect(
        {
          for (final line in persisted!.lines) line.productId: line.quantity,
        },
        {'tube': 1},
      );
      expect(staleTab.hasProduct('chain'), isFalse);
      expect(staleTab.getProductQuantity('tube'), 1);
    });

    test('consumption preserves operation lineage after an ambiguous tab write',
        () async {
      final preferences = _ControlledPreferencesBackend()
        ..applyThenThrowWithReadFailureNextWrite = true
        ..readFailuresAfterAmbiguousWrite = 3;
      Future<List<Product>> loader(List<String> ids) async =>
          ids.map((id) => _product(id: id)).toList(growable: false);
      final originStore = SharedPreferencesCartStore(preferences: preferences);
      final originTab = CartProvider(store: originStore);
      await originTab.restore(tenantId: _tenant, loadProducts: loader);

      originTab.addProduct(_product(id: 'chain'));
      await originTab.debugWaitForPersistence();

      final checkoutStore =
          SharedPreferencesCartStore(preferences: preferences);
      final checkoutTab = CartProvider(store: checkoutStore);
      await checkoutTab.restore(tenantId: _tenant, loadProducts: loader);
      final revision = (await checkoutStore.readForTenant(_tenant))!.revision!;
      final consumed = await checkoutTab.consumeOrderedLines(
        tenantId: _tenant,
        orderedLines: const [
          PersistedCartLine(productId: 'chain', quantity: 1),
        ],
        expectedRevision: revision,
      );
      expect(consumed.status, CartConsumptionStatus.applied);
      expect(consumed.document, isNotNull);
      expect(consumed.document!.lines, isEmpty);
      expect(consumed.document!.appliedMutationIds, hasLength(1));

      // The origin still owns the uncertain +1 command in memory. The empty
      // consumption tombstone carries its ID, so recovery retires it.
      await originTab.restore(tenantId: _tenant, loadProducts: loader);
      originTab.addProduct(_product(id: 'tube'));
      await originTab.debugWaitForPersistence();

      final persisted = await originStore.readForTenant(_tenant);
      expect(
        {
          for (final line in persisted!.lines) line.productId: line.quantity,
        },
        {'tube': 1},
      );
      expect(persisted.appliedMutationIds, hasLength(2));
    });

    test('a changed revision preserves a newly-added unit of the same SKU',
        () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesCartStore();
      final cart = CartProvider(store: store);
      Future<List<Product>> loader(List<String> ids) async =>
          ids.map((id) => _product(id: id)).toList(growable: false);
      await cart.restore(tenantId: _tenant, loadProducts: loader);
      cart.addProduct(_product(id: 'chain'), quantity: 2);
      await Future<void>.delayed(const Duration(milliseconds: 1));

      final checkoutRevision = await cart.captureDurableCheckoutRevision(
        tenantId: _tenant,
        orderedLines: const [
          PersistedCartLine(productId: 'chain', quantity: 2),
        ],
      );

      // The post-handoff document contains a distinct new intent with the same
      // SKU. Quantity arithmetic alone cannot identify it safely.
      await store.writeForTenant(
        _tenant,
        PersistedCart(
          tenantId: _tenant,
          savedAt: DateTime.now().toUtc(),
          lines: const [
            PersistedCartLine(productId: 'chain', quantity: 1),
          ],
          revision: 'new-same-sku-intent',
        ),
      );

      final result = await cart.consumeOrderedLines(
        tenantId: _tenant,
        orderedLines: const [
          PersistedCartLine(productId: 'chain', quantity: 2),
        ],
        expectedRevision: checkoutRevision,
      );

      expect(result.status, CartConsumptionStatus.conflict);
      expect(
        (await store.readForTenant(_tenant))?.lines.single.quantity,
        1,
      );
      expect(cart.getProductQuantity('chain'), 1);
    });

    test(
        'mutation between fresh reads aborts the write and synchronizes current memory',
        () async {
      SharedPreferences.setMockInitialValues({});
      final seedStore = SharedPreferencesCartStore();
      await seedStore.writeForTenant(
        _tenant,
        _saved(const [
          PersistedCartLine(productId: 'chain', quantity: 1),
        ]),
      );

      var mutationCalls = 0;
      final guardedStore = SharedPreferencesCartStore(
        beforeCommitValidation: () async {
          mutationCalls++;
          await seedStore.writeForTenant(
            _tenant,
            _saved(const [
              PersistedCartLine(productId: 'chain', quantity: 1),
              PersistedCartLine(productId: 'tube', quantity: 1),
            ]),
          );
        },
      );
      final cart = CartProvider(store: guardedStore);
      Future<List<Product>> loader(List<String> ids) async =>
          ids.map((id) => _product(id: id)).toList(growable: false);
      await cart.restore(tenantId: _tenant, loadProducts: loader);
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final checkoutRevision =
          (await guardedStore.readForTenant(_tenant))!.revision!;

      final result = await cart.consumeOrderedLines(
        tenantId: _tenant,
        orderedLines: const [
          PersistedCartLine(productId: 'chain', quantity: 1),
        ],
        expectedRevision: checkoutRevision,
      );

      expect(mutationCalls, 1);
      expect(result.status, CartConsumptionStatus.conflict);
      expect(cart.getProductQuantity('chain'), 1);
      expect(cart.getProductQuantity('tube'), 1);
      final persisted = await seedStore.readForTenant(_tenant);
      expect(
        {
          for (final line in persisted!.lines) line.productId: line.quantity,
        },
        {'chain': 1, 'tube': 1},
      );
    });

    test('corrupt latest durable cart fails closed without emptying memory',
        () async {
      SharedPreferences.setMockInitialValues({});
      final seedStore = SharedPreferencesCartStore();
      await seedStore.writeForTenant(
        _tenant,
        _saved(const [
          PersistedCartLine(productId: 'chain', quantity: 1),
        ]),
      );

      final guardedStore = SharedPreferencesCartStore(
        beforeCommitValidation: () async {
          final preferences = await SharedPreferences.getInstance();
          await preferences.setString(
            SharedPreferencesCartStore.storageKeyForTenant(_tenant),
            '{"v":1,"tenant":"broken"',
          );
        },
      );
      final cart = CartProvider(store: guardedStore);
      await cart.restore(
        tenantId: _tenant,
        loadProducts: (ids) async =>
            ids.map((id) => _product(id: id)).toList(growable: false),
      );
      final checkoutRevision =
          (await guardedStore.readForTenant(_tenant))!.revision!;

      final result = await cart.consumeOrderedLines(
        tenantId: _tenant,
        orderedLines: const [
          PersistedCartLine(productId: 'chain', quantity: 1),
        ],
        expectedRevision: checkoutRevision,
      );

      expect(result.status, CartConsumptionStatus.unavailable);
      expect(result.document, isNull);
      expect(cart.getProductQuantity('chain'), 1);
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString(
          SharedPreferencesCartStore.storageKeyForTenant(_tenant),
        ),
        '{"v":1,"tenant":"broken"',
      );
    });
  });
}
