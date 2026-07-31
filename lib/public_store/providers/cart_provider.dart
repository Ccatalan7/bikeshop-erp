import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../shared/models/product.dart';
import '../models/public_commerce_product_projection.dart';
import '../models/storefront_tax_summary.dart';
import '../services/cart_store.dart';
import '../services/meta_pixel_service.dart';

/// Re-reads the authoritative catalog rows for a restored basket.
///
/// Supplied by the composition root so the provider stays free of Supabase and
/// remains unit-testable.
typedef CartProductLoader = Future<List<Product>> Function(
  List<String> productIds,
);

typedef _CartMutationApplier = void Function(
  List<CartItem> items,
  Map<String, Product>? authoritativeProducts,
);

enum _CartBaselineState {
  unknown,
  loading,
  ready,
  fault,
}

class _QueuedCartMutation {
  _QueuedCartMutation({
    required this.scopeGeneration,
    required this.operationId,
    required this.createdAt,
    required this.productIds,
    required this.apply,
  });

  final int scopeGeneration;
  final String operationId;
  final DateTime createdAt;
  final Set<String> productIds;
  final _CartMutationApplier apply;
}

class _CartProjection {
  const _CartProjection({
    required this.items,
    required this.productsById,
    required this.dropped,
    required this.needsCanonicalWrite,
  });

  final List<CartItem> items;
  final Map<String, Product> productsById;
  final int dropped;
  final bool needsCanonicalWrite;
}

class _CartPersistenceOutcome {
  const _CartPersistenceOutcome({
    required this.items,
    required this.dropped,
    required this.document,
  });

  final List<CartItem> items;
  final int dropped;
  final PersistedCart? document;
}

class CartItem {
  final Product product;
  int quantity;

  CartItem({
    required this.product,
    required this.quantity,
  });

  PublicCommerceProductProjection get commerce =>
      PublicCommerceProductProjection.fromProduct(
        product,
        categoryPath: product.categoryName,
      );

  double get subtotal => commerce.price * quantity;

  StorefrontTaxLineInput get taxInput => StorefrontTaxLineInput(
        label: commerce.title,
        grossUnitPrice: commerce.price,
        quantity: quantity,
        taxRate: product.taxRate,
      );
}

class CartProvider with ChangeNotifier {
  CartProvider({
    CartStore? store,
    DateTime Function()? now,
  })  : _store = store ?? SharedPreferencesCartStore(),
        _now = now ?? DateTime.now;

  final CartStore _store;
  final DateTime Function() _now;
  final List<CartItem> _items = [];

  String? _tenantId;
  CartProductLoader? _productLoader;
  _CartBaselineState _baselineState = _CartBaselineState.unknown;
  Future<void>? _restoreFlight;
  int _scopeGeneration = 0;
  int _stateRevision = 0;
  Future<void> _persistenceQueue = Future<void>.value();
  final List<CartItem> _serializedItems = [];
  final List<_QueuedCartMutation> _pendingMutations = [];

  /// Lines that were saved but could no longer be honoured — the product was
  /// unpublished, deleted or went out of stock while the basket was away.
  /// Surfaced so the cart can say so instead of quietly shrinking.
  int _droppedOnRestore = 0;
  int get droppedOnRestore => _droppedOnRestore;

  void acknowledgeDroppedLines() {
    if (_droppedOnRestore == 0) return;
    _droppedOnRestore = 0;
    notifyListeners();
  }

  List<CartItem> get items => List.unmodifiable(_items);

  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  /// Product-derived, line-by-line fiscal breakdown. Payment method never
  /// participates in tax classification.
  StorefrontTaxSummary get taxSummary => StorefrontTaxSummary.calculate(
        _items.map((item) => item.taxInput),
      );

  /// Gross catalog amount known independently from the fiscal classification.
  ///
  /// This remains available when a product is missing its tax rate because
  /// public catalog prices already include tax. It is `null` when a price,
  /// quantity, or aggregate cannot be represented safely in whole CLP.
  int? get grossMerchandiseAmountClp =>
      StorefrontTaxSummary.calculateGrossAmount(
        _items.map((item) => item.taxInput),
      );

  /// Fiscally validated total amount (what the customer pays).
  ///
  /// `null` is deliberately different from zero: an invalid tax breakdown is
  /// an unknown checkout total and must never be rendered or transmitted as
  /// `$0`.
  double? get total {
    final summary = taxSummary;
    return summary.isValid ? summary.grossAmount.toDouble() : null;
  }

  bool get hasValidTaxClassification => taxSummary.isValid;

  String? get taxCheckoutBlockMessage => taxSummary.checkoutBlockMessage;

  /// Net amount extracted from affected gross lines and preserved as gross for
  /// exempt lines. Invalid carts return `null` and are blocked before checkout.
  double? get subtotal {
    final summary = taxSummary;
    return summary.isValid ? summary.netAmount.toDouble() : null;
  }

  /// IVA extracted per affected line using whole-CLP rounding.
  double? get ivaAmount {
    final summary = taxSummary;
    return summary.isValid ? summary.taxAmount.toDouble() : null;
  }

  bool get isEmpty => _items.isEmpty;

  bool get isNotEmpty => _items.isNotEmpty;

  @visibleForTesting
  Future<void> debugWaitForPersistence() => _persistenceQueue;

  void addProduct(Product product, {int quantity = 1}) {
    if (quantity <= 0) return;
    final requestedQuantity = _boundedQuantity(product, quantity);
    if (requestedQuantity <= 0) return;

    // Check if product already in cart
    final existingIndex =
        _items.indexWhere((item) => item.product.id == product.id);
    var addedQuantity = requestedQuantity;

    if (existingIndex >= 0) {
      // Increase quantity
      final existing = _items[existingIndex];
      final previousQuantity = existing.quantity;
      final nextQuantity = _boundedQuantity(
        product,
        previousQuantity + requestedQuantity,
      );
      addedQuantity = nextQuantity - previousQuantity;
      if (addedQuantity <= 0) return;
      existing.quantity = nextQuantity;
    } else {
      // Add new item
      _items.add(CartItem(product: product, quantity: requestedQuantity));
    }

    final commerce = PublicCommerceProductProjection.fromProduct(
      product,
      categoryPath: product.categoryName,
    );
    MetaPixelService.instance.trackAddToCart(
      contentId: MetaPixelService.catalogContentId(
        sku: product.sku,
        productId: product.id,
      ),
      contentName: commerce.title,
      itemPrice: commerce.price,
      quantity: addedQuantity,
    );
    _queueMutation(
      productIds: {product.id},
      (items, authoritativeProducts) => _addQuantityTo(
        items,
        product,
        addedQuantity,
        authoritativeProducts: authoritativeProducts,
      ),
    );
    notifyListeners();
  }

  void removeProduct(String productId) {
    _items.removeWhere((item) => item.product.id == productId);
    _queueMutation(
      (items, _) => items.removeWhere(
        (item) => item.product.id == productId,
      ),
    );
    notifyListeners();
  }

  void updateQuantity(String productId, int quantity) {
    if (quantity <= 0) {
      removeProduct(productId);
      return;
    }

    final index = _items.indexWhere((item) => item.product.id == productId);
    if (index >= 0) {
      final bounded = _boundedQuantity(_items[index].product, quantity);
      if (bounded <= 0) {
        removeProduct(productId);
        return;
      }
      final product = _items[index].product;
      _items[index].quantity = bounded;
      _queueMutation(
        productIds: {product.id},
        (items, authoritativeProducts) => _setQuantityIn(
          items,
          product,
          bounded,
          authoritativeProducts: authoritativeProducts,
        ),
      );
      notifyListeners();
    }
  }

  void incrementQuantity(String productId) {
    final index = _items.indexWhere((item) => item.product.id == productId);
    if (index >= 0) {
      final item = _items[index];
      final incremented = _boundedQuantity(item.product, item.quantity + 1);
      if (incremented == item.quantity) return;
      item.quantity = incremented;
      _queueMutation(
        productIds: {item.product.id},
        (items, authoritativeProducts) => _addQuantityTo(
          items,
          item.product,
          1,
          authoritativeProducts: authoritativeProducts,
        ),
      );
      notifyListeners();
    }
  }

  void decrementQuantity(String productId) {
    final index = _items.indexWhere((item) => item.product.id == productId);
    if (index >= 0) {
      final product = _items[index].product;
      if (_items[index].quantity > 1) {
        _items[index].quantity--;
      } else {
        _items.removeAt(index);
      }
      _queueMutation(
        productIds: {product.id},
        (items, authoritativeProducts) => _addQuantityTo(
          items,
          product,
          -1,
          authoritativeProducts: authoritativeProducts,
        ),
      );
      notifyListeners();
    }
  }

  void clear() {
    _items.clear();
    _droppedOnRestore = 0;
    _queueMutation((items, _) => items.clear());
    notifyListeners();
  }

  int getProductQuantity(String productId) {
    try {
      final item = _items.firstWhere(
        (item) => item.product.id == productId,
      );
      return item.quantity;
    } catch (e) {
      return 0;
    }
  }

  bool hasProduct(String productId) {
    return _items.any((item) => item.product.id == productId);
  }

  // ==========================================================================
  // PERSISTENCE
  //
  // The basket used to live only in memory, so every reload, restored tab or
  // mistaken Back emptied it — while the empty-state copy promised the
  // opposite ("El carro mantendrá las cantidades..."). What is stored is only
  // an id and a quantity: the catalog row is re-read on restore, so a basket
  // that sat overnight can never present yesterday's price at checkout.
  // ==========================================================================

  /// Rehydrates the basket for [tenantId], revalidating every line.
  ///
  /// Safe to call more than once; only the first call for a tenant restores.
  Future<void> restore({
    required String tenantId,
    required CartProductLoader loadProducts,
  }) {
    final normalizedTenant = tenantId.trim();
    if (normalizedTenant.isEmpty) return Future<void>.value();

    final tenantChanged = _tenantId != null && _tenantId != normalizedTenant;
    if (tenantChanged) {
      _scopeGeneration++;
      _stateRevision++;
      _items.clear();
      _serializedItems.clear();
      _pendingMutations.clear();
      _droppedOnRestore = 0;
      _baselineState = _CartBaselineState.unknown;
    }
    _tenantId = normalizedTenant;
    _productLoader = loadProducts;
    if (tenantChanged) notifyListeners();

    if (_baselineState == _CartBaselineState.ready) {
      return Future<void>.value();
    }
    final existingFlight = _restoreFlight;
    if (existingFlight != null && !tenantChanged) return existingFlight;

    final scopeGeneration = _scopeGeneration;
    _baselineState = _CartBaselineState.loading;
    late final Future<void> operation;
    operation = _restoreBaseline(
      tenantId: normalizedTenant,
      scopeGeneration: scopeGeneration,
      loadProducts: loadProducts,
    ).whenComplete(() {
      if (identical(_restoreFlight, operation)) {
        _restoreFlight = null;
      }
    });
    _restoreFlight = operation;
    return operation;
  }

  Future<void> _restoreBaseline({
    required String tenantId,
    required int scopeGeneration,
    required CartProductLoader loadProducts,
  }) async {
    final PersistedCart? saved;
    try {
      saved = await _readStoredCart(tenantId);
    } catch (error) {
      debugPrint(
        '⚠️ [CartProvider] Could not read the saved cart: $error',
      );
      _markBaselineFault(tenantId, scopeGeneration);
      return;
    }
    if (!_ownsScope(tenantId, scopeGeneration)) return;

    var durable = saved;
    var durableWasCleared = false;
    for (var attempt = 0;
        durable != null && _isOutsideRetentionWindow(durable);
        attempt++) {
      if (attempt >= 8) {
        _markBaselineFault(tenantId, scopeGeneration);
        return;
      }
      try {
        final store = _store;
        if (store is AtomicTenantCartStore) {
          final exchange =
              await (store as AtomicTenantCartStore).compareAndSetForTenant(
            tenantId: tenantId,
            expected: durable,
            replacement: null,
          );
          if (exchange.applied) {
            durable = null;
            durableWasCleared = true;
          } else {
            // A newer tab won the race. Inspect that exact document rather
            // than deleting it based on the stale expiry decision.
            durable = exchange.document;
          }
        } else {
          await _clearStoredCart(tenantId);
          durable = null;
          durableWasCleared = true;
        }
      } catch (error) {
        debugPrint(
          '⚠️ [CartProvider] Could not discard an expired saved cart: $error',
        );
        _markBaselineFault(tenantId, scopeGeneration);
        return;
      }
    }
    if (!_ownsScope(tenantId, scopeGeneration)) return;

    final restoredItems = <CartItem>[];
    var dropped = 0;
    var needsCanonicalWrite = false;
    if (durable != null && durable.lines.isNotEmpty) {
      final List<Product> products;
      try {
        products = await loadProducts(
          durable.lines.map((line) => line.productId).toList(growable: false),
        );
      } catch (error) {
        // A transport failure is not proof the basket is gone. Semantic
        // mutations remain pending and a later mutation retries this baseline.
        debugPrint(
          '⚠️ [CartProvider] Could not revalidate the saved cart: $error',
        );
        _markBaselineFault(tenantId, scopeGeneration);
        return;
      }
      if (!_ownsScope(tenantId, scopeGeneration)) return;

      final byId = <String, Product>{
        for (final product in products) product.id: product,
      };
      for (final line in durable.lines) {
        final product = byId[line.productId];
        if (product == null) {
          dropped++;
          needsCanonicalWrite = true;
          continue;
        }
        final quantity = _restorableQuantity(product, line.quantity);
        if (quantity <= 0) {
          dropped++;
          needsCanonicalWrite = true;
          continue;
        }
        if (quantity < line.quantity) {
          dropped++;
          needsCanonicalWrite = true;
        }
        restoredItems.add(CartItem(product: product, quantity: quantity));
      }
      if (durable.revision?.trim().isEmpty != false) {
        needsCanonicalWrite = true;
      }
    } else if (durable != null && durable.revision?.trim().isEmpty != false) {
      needsCanonicalWrite = true;
    }

    await _commitRecoveredBaseline(
      tenantId: tenantId,
      scopeGeneration: scopeGeneration,
      restoredItems: restoredItems,
      dropped: dropped,
      hadDurableDocument: durable != null,
      needsCanonicalWrite: needsCanonicalWrite && !durableWasCleared,
      appliedMutationIds: durable?.appliedMutationIds ?? const <String>[],
    );
  }

  Future<void> _commitRecoveredBaseline({
    required String tenantId,
    required int scopeGeneration,
    required List<CartItem> restoredItems,
    required int dropped,
    required bool hadDurableDocument,
    required bool needsCanonicalWrite,
    required Iterable<String> appliedMutationIds,
  }) async {
    final precedingOperations = _persistenceQueue.catchError((Object _) {});
    final operation = precedingOperations.then((_) async {
      if (!_ownsScope(tenantId, scopeGeneration) ||
          _baselineState != _CartBaselineState.loading) {
        return;
      }

      // Establish the freshly revalidated base in memory before attempting the
      // canonical write. If storage fails, the visitor still sees recovered
      // lines plus every optimistic command, while those commands stay pending.
      final appliedMutationIdSet = appliedMutationIds.toSet();
      _pendingMutations.removeWhere(
        (command) =>
            command.scopeGeneration == scopeGeneration &&
            (_isOutsideMutationWindow(command.createdAt) ||
                appliedMutationIdSet.contains(command.operationId)),
      );
      _serializedItems
        ..clear()
        ..addAll(_cloneItems(restoredItems));
      _droppedOnRestore = dropped;
      _rebuildVisibleItems();

      final commands = _pendingMutations
          .where((entry) => entry.scopeGeneration == scopeGeneration)
          .toList(growable: false);
      final serializedCandidate = _cloneItems(restoredItems);
      for (final command in commands) {
        command.apply(serializedCandidate, null);
      }

      var committedItems = serializedCandidate;
      var committedDropped = dropped;
      final store = _store;
      if (store is AtomicTenantCartStore) {
        final outcome = await _persistCommandsAtomically(
          tenantId: tenantId,
          generation: scopeGeneration,
          commands: commands,
        );
        committedItems = outcome.items;
        committedDropped = outcome.dropped;
      } else {
        final shouldWrite = needsCanonicalWrite || commands.isNotEmpty;
        if (shouldWrite) {
          if (serializedCandidate.isEmpty) {
            // Avoid manufacturing a removal failure for a known-absent key.
            if (hadDurableDocument || commands.isNotEmpty) {
              await _clearStoredCart(tenantId);
            }
          } else {
            await _writeStoredCart(
              tenantId,
              _snapshotOf(
                serializedCandidate,
                tenantId: tenantId,
              ),
            );
          }
        }
      }
      if (!_ownsScope(tenantId, scopeGeneration)) return;

      _serializedItems
        ..clear()
        ..addAll(_cloneItems(committedItems));
      for (final command in commands) {
        _pendingMutations.remove(command);
      }
      _baselineState = _CartBaselineState.ready;
      _droppedOnRestore = committedDropped;
      _rebuildVisibleItems();
    });
    final guarded = operation.catchError((Object error) {
      debugPrint(
        '⚠️ [CartProvider] Could not commit recovered cart: $error',
      );
      _markBaselineFault(tenantId, scopeGeneration);
    });
    _persistenceQueue = guarded;
    await guarded;

    if (_ownsScope(tenantId, scopeGeneration) &&
        _baselineState == _CartBaselineState.ready &&
        _hasPendingMutations(scopeGeneration)) {
      _schedulePendingPersistence();
    }
  }

  void _markBaselineFault(String tenantId, int scopeGeneration) {
    if (_ownsScope(tenantId, scopeGeneration)) {
      _baselineState = _CartBaselineState.fault;
    }
  }

  bool _hasPendingMutations(int scopeGeneration) {
    return _pendingMutations.any(
      (entry) => entry.scopeGeneration == scopeGeneration,
    );
  }

  Future<void> _ensureBaselineReady() async {
    final tenantId = _tenantId;
    final loadProducts = _productLoader;
    if (tenantId == null || tenantId.isEmpty || loadProducts == null) {
      return;
    }
    if (_baselineState == _CartBaselineState.loading) {
      await _restoreFlight;
    } else if (_baselineState != _CartBaselineState.ready) {
      await restore(tenantId: tenantId, loadProducts: loadProducts);
    }
  }

  /// Never restore more units than the shop can actually deliver today.
  int _restorableQuantity(Product product, int requested) {
    return _boundedQuantity(product, requested);
  }

  int _boundedQuantity(Product product, int requested) {
    if (requested <= 0) return 0;
    if (!product.tracksInventory) return requested;
    final available = product.availableStockQuantity;
    if (available <= 0) return 0;
    return requested > available ? available : requested;
  }

  bool _isOutsideRetentionWindow(PersistedCart document) {
    return _isOutsideMutationWindow(document.savedAt);
  }

  bool _isOutsideMutationWindow(DateTime timestamp) {
    final now = _now().toUtc();
    final normalized = timestamp.toUtc();
    return normalized.isAfter(now.add(CartStore.allowedFutureSkew)) ||
        now.difference(normalized) > CartStore.maxAge;
  }

  bool _ownsScope(String tenantId, int generation) =>
      _tenantId == tenantId && _scopeGeneration == generation;

  Future<PersistedCart?> _readStoredCart(String tenantId) async {
    final store = _store;
    if (store is TenantScopedCartStore) {
      return (store as TenantScopedCartStore).readForTenant(tenantId);
    }
    final document = await store.read();
    return document?.tenantId == tenantId ? document : null;
  }

  Future<void> _writeStoredCart(
    String tenantId,
    PersistedCart document,
  ) {
    final store = _store;
    if (store is TenantScopedCartStore) {
      return (store as TenantScopedCartStore)
          .writeForTenant(tenantId, document);
    }
    if (document.tenantId != tenantId) {
      throw ArgumentError('El carrito no corresponde a esta tienda.');
    }
    return store.write(document);
  }

  Future<void> _clearStoredCart(String tenantId) {
    final store = _store;
    if (store is TenantScopedCartStore) {
      return (store as TenantScopedCartStore).clearForTenant(tenantId);
    }
    return store.clear();
  }

  /// Waits for the optimistic mutation queue and returns the exact durable
  /// revision represented by [orderedLines].
  ///
  /// Checkout persists this opaque revision before its first order RPC. A
  /// later callback may subtract the ordered quantities only while the durable
  /// cart still has this exact revision, preventing newly-added units of the
  /// same SKU from being mistaken for units in the completed order.
  Future<String> captureDurableCheckoutRevision({
    required String tenantId,
    required List<PersistedCartLine> orderedLines,
  }) async {
    final normalizedTenant = tenantId.trim();
    if (normalizedTenant.isEmpty || _tenantId != normalizedTenant) {
      throw StateError('El carrito no corresponde a esta tienda.');
    }

    // Recover an unknown/faulted baseline before any full-document write. One
    // retry also covers a persistence failure discovered while awaiting the
    // optimistic queue.
    for (var attempt = 0; attempt < 2; attempt++) {
      await _ensureBaselineReady();
      await _persistenceQueue;
      if (_baselineState == _CartBaselineState.ready &&
          _hasPendingMutations(_scopeGeneration)) {
        _schedulePendingPersistence();
        await _persistenceQueue;
      }
      if (_baselineState == _CartBaselineState.ready &&
          !_hasPendingMutations(_scopeGeneration)) {
        break;
      }
    }

    final generation = _scopeGeneration;
    final stateRevision = _stateRevision;
    if (_baselineState != _CartBaselineState.ready ||
        _hasPendingMutations(generation)) {
      throw StateError('No se pudo confirmar el carrito guardado.');
    }

    var document = await _readStoredCart(normalizedTenant);
    if (!_ownsScope(normalizedTenant, generation) ||
        _stateRevision != stateRevision) {
      throw StateError('El carrito cambió mientras se preparaba el checkout.');
    }
    if (document != null && _isOutsideRetentionWindow(document)) {
      final store = _store;
      if (store is AtomicTenantCartStore) {
        final exchange =
            await (store as AtomicTenantCartStore).compareAndSetForTenant(
          tenantId: normalizedTenant,
          expected: document,
          replacement: null,
        );
        document = exchange.document;
      } else {
        await _clearStoredCart(normalizedTenant);
        document = null;
      }
      if (!_ownsScope(normalizedTenant, generation) ||
          _stateRevision != stateRevision) {
        throw StateError(
          'El carrito cambió mientras se preparaba el checkout.',
        );
      }
    }
    final revision = document?.revision?.trim() ?? '';
    if (document == null ||
        document.tenantId != normalizedTenant ||
        revision.isEmpty ||
        !_hasExactLines(document.lines, orderedLines)) {
      throw StateError(
        'El carrito guardado no coincide con el pedido preparado.',
      );
    }
    return revision;
  }

  /// Removes only the quantities belonging to a completed durable order.
  ///
  /// The persisted document, not [_items], is the compare-before-write source
  /// of truth. This preserves lines added by another tab. If freshness or
  /// exact catalog rehydration cannot be guaranteed, the operation fails
  /// closed and keeps the basket unchanged.
  Future<CartConsumptionResult> consumeOrderedLines({
    required String tenantId,
    required List<PersistedCartLine> orderedLines,
    required String expectedRevision,
  }) async {
    final normalizedTenant = tenantId.trim();
    if (normalizedTenant.isEmpty || _tenantId != normalizedTenant) {
      return const CartConsumptionResult(
        status: CartConsumptionStatus.unavailable,
        document: null,
      );
    }
    await _ensureBaselineReady();
    final loader = _productLoader;
    if (_tenantId != normalizedTenant ||
        loader == null ||
        _baselineState != _CartBaselineState.ready) {
      return const CartConsumptionResult(
        status: CartConsumptionStatus.unavailable,
        document: null,
      );
    }

    // A completed-order consume is a state transition even when its result is
    // an empty basket. Invalidate any restore that captured an older durable
    // document before its catalog revalidation completed.
    _stateRevision++;
    final generation = _scopeGeneration;
    List<CartItem>? preparedItems;
    final precedingWrites = _persistenceQueue.catchError((Object _) {});

    Future<CartConsumptionResult> runSerializedConsumption() async {
      await precedingWrites;
      if (!_ownsScope(normalizedTenant, generation) ||
          _baselineState != _CartBaselineState.ready) {
        return const CartConsumptionResult(
          status: CartConsumptionStatus.unavailable,
          document: null,
        );
      }

      try {
        final result = await _store.consumeOrderedLines(
          tenantId: normalizedTenant,
          orderedLines: orderedLines,
          expectedRevision: expectedRevision,
          prepare: (proposedDocument) async {
            final projected = await _projectDocumentExactly(
              proposedDocument,
              tenantId: normalizedTenant,
              generation: generation,
              loadProducts: loader,
            );
            if (projected == null) return false;
            preparedItems = projected;
            return true;
          },
        );
        if (!_ownsScope(normalizedTenant, generation)) {
          return CartConsumptionResult(
            status: CartConsumptionStatus.unavailable,
            document: result.document,
          );
        }

        if (result.status == CartConsumptionStatus.applied) {
          final projected = preparedItems;
          if (projected == null) {
            return CartConsumptionResult(
              status: CartConsumptionStatus.unavailable,
              document: result.document,
            );
          }
          _replaceSerializedItems(projected);
          _rebuildVisibleItems();
          return result;
        }

        if (result.status == CartConsumptionStatus.conflict) {
          final currentItems = await _projectDocumentExactly(
            result.document,
            tenantId: normalizedTenant,
            generation: generation,
            loadProducts: loader,
          );
          if (currentItems != null &&
              _ownsScope(normalizedTenant, generation)) {
            _replaceSerializedItems(currentItems);
            _rebuildVisibleItems();
          }
        }
        return result;
      } catch (error) {
        debugPrint(
          '⚠️ [CartProvider] Could not consume completed-order lines: $error',
        );
        return const CartConsumptionResult(
          status: CartConsumptionStatus.unavailable,
          document: null,
        );
      }
    }

    // Enqueue the whole read/prepare/validate/write/rehydrate operation.
    // Mutations scheduled behind it remain optimistic in [_items], but are
    // replayed over the consumed durable base before their own write executes.
    final operation = runSerializedConsumption();
    _persistenceQueue = operation.then<void>((_) {}).catchError(
      (Object error) {
        debugPrint(
          '⚠️ [CartProvider] Cart-consumption queue failed: $error',
        );
      },
    );
    return operation;
  }

  Future<List<CartItem>?> _projectDocumentExactly(
    PersistedCart? document, {
    required String tenantId,
    required int generation,
    required CartProductLoader loadProducts,
  }) async {
    if (!_ownsScope(tenantId, generation)) return null;
    if (document == null) return <CartItem>[];
    if (document.tenantId != tenantId) return null;

    final ids =
        document.lines.map((line) => line.productId).toList(growable: false);
    final List<Product> products;
    try {
      products = await loadProducts(ids);
    } catch (error) {
      debugPrint(
        '⚠️ [CartProvider] Could not rehydrate consumed cart: $error',
      );
      return null;
    }
    if (!_ownsScope(tenantId, generation)) return null;

    final byId = <String, Product>{
      for (final product in products) product.id: product,
    };
    final projected = <CartItem>[];
    for (final line in document.lines) {
      final product = byId[line.productId];
      if (product == null) return null;
      final quantity = _restorableQuantity(product, line.quantity);
      if (quantity != line.quantity) return null;
      projected.add(CartItem(product: product, quantity: quantity));
    }
    return projected;
  }

  Future<_CartProjection?> _projectDocumentForPersistence(
    PersistedCart? document, {
    required String tenantId,
    required int generation,
    required CartProductLoader loadProducts,
    required Set<String> commandProductIds,
  }) async {
    if (!_ownsScope(tenantId, generation)) return null;
    if (document != null && document.tenantId != tenantId) return null;

    final ids = <String>{
      ...?document?.lines.map((line) => line.productId),
      ...commandProductIds,
    }.toList(growable: false);
    final List<Product> products;
    try {
      products = ids.isEmpty ? const <Product>[] : await loadProducts(ids);
    } catch (error) {
      debugPrint(
        '⚠️ [CartProvider] Could not revalidate the latest saved cart: $error',
      );
      return null;
    }
    if (!_ownsScope(tenantId, generation)) return null;

    final byId = <String, Product>{
      for (final product in products) product.id: product,
    };
    final projected = <CartItem>[];
    var dropped = 0;
    var needsCanonicalWrite =
        document != null && document.revision?.trim().isEmpty != false;
    for (final line in document?.lines ?? const <PersistedCartLine>[]) {
      final product = byId[line.productId];
      if (product == null) {
        dropped++;
        needsCanonicalWrite = true;
        continue;
      }
      final quantity = _restorableQuantity(product, line.quantity);
      if (quantity <= 0) {
        dropped++;
        needsCanonicalWrite = true;
        continue;
      }
      if (quantity != line.quantity) {
        dropped++;
        needsCanonicalWrite = true;
      }
      projected.add(CartItem(product: product, quantity: quantity));
    }
    return _CartProjection(
      items: projected,
      productsById: Map<String, Product>.unmodifiable(byId),
      dropped: dropped,
      needsCanonicalWrite: needsCanonicalWrite,
    );
  }

  Future<_CartPersistenceOutcome> _persistCommandsAtomically({
    required String tenantId,
    required int generation,
    required List<_QueuedCartMutation> commands,
  }) async {
    final store = _store;
    final loader = _productLoader;
    if (store is! AtomicTenantCartStore || loader == null) {
      throw StateError('El carrito no admite persistencia atómica.');
    }

    PersistedCart? current = await _readStoredCart(tenantId);
    for (var attempt = 0; attempt < 8; attempt++) {
      if (!_ownsScope(tenantId, generation)) {
        throw StateError('La tienda cambió durante la persistencia.');
      }
      if (current != null && _isOutsideRetentionWindow(current)) {
        final exchange =
            await (store as AtomicTenantCartStore).compareAndSetForTenant(
          tenantId: tenantId,
          expected: current,
          replacement: null,
        );
        current = exchange.document;
        continue;
      }
      final retainedAppliedMutations = <String, DateTime>{
        for (final mutation in current?.appliedMutations.entries ??
            const <MapEntry<String, DateTime>>[])
          if (!_isOutsideMutationWindow(mutation.value))
            mutation.key: mutation.value,
      };
      final activeCommands = commands
          .where(
            (command) => !_isOutsideMutationWindow(command.createdAt),
          )
          .toList(growable: false);
      final unappliedCommands = activeCommands
          .where(
            (command) =>
                !retainedAppliedMutations.containsKey(command.operationId),
          )
          .toList(growable: false);
      final commandProductIds = <String>{
        for (final command in unappliedCommands) ...command.productIds,
      };
      final projection = await _projectDocumentForPersistence(
        current,
        tenantId: tenantId,
        generation: generation,
        loadProducts: loader,
        commandProductIds: commandProductIds,
      );
      if (projection == null) {
        throw StateError('No se pudo validar el carrito más reciente.');
      }

      final candidate = _cloneItems(projection.items);
      for (final command in unappliedCommands) {
        command.apply(candidate, projection.productsById);
      }
      final shouldWrite =
          unappliedCommands.isNotEmpty || projection.needsCanonicalWrite;
      if (!shouldWrite) {
        return _CartPersistenceOutcome(
          items: candidate,
          dropped: projection.dropped,
          document: current,
        );
      }

      final nextAppliedMutations = <String, DateTime>{
        ...retainedAppliedMutations,
        for (final command in unappliedCommands)
          command.operationId: command.createdAt,
      };
      final replacement = _snapshotOf(
        candidate,
        tenantId: tenantId,
        appliedMutations: nextAppliedMutations,
      );
      final exchange =
          await (store as AtomicTenantCartStore).compareAndSetForTenant(
        tenantId: tenantId,
        expected: current,
        replacement: replacement,
      );
      if (exchange.applied) {
        return _CartPersistenceOutcome(
          items: candidate,
          dropped: projection.dropped,
          document: exchange.document,
        );
      }

      // Another tab committed while catalog truth was being revalidated.
      // Rehydrate its exact winner, replay these semantic commands, and retry.
      current = exchange.document;
    }
    throw StateError(
      'El carrito cambió demasiadas veces mientras se intentaba guardarlo.',
    );
  }

  void _replaceSerializedItems(List<CartItem> items) {
    _serializedItems
      ..clear()
      ..addAll(_cloneItems(items));
    _droppedOnRestore = 0;
  }

  void _rebuildVisibleItems() {
    final visibleItems = _cloneItems(_serializedItems);
    for (final pending in _pendingMutations) {
      if (pending.scopeGeneration == _scopeGeneration) {
        pending.apply(visibleItems, null);
      }
    }
    _items
      ..clear()
      ..addAll(visibleItems);
    notifyListeners();
  }

  List<CartItem> _cloneItems(Iterable<CartItem> items) {
    return [
      for (final item in items)
        CartItem(
          product: item.product,
          quantity: item.quantity,
        ),
    ];
  }

  PersistedCart _snapshotOf(
    Iterable<CartItem> items, {
    required String tenantId,
    Map<String, DateTime> appliedMutations = const <String, DateTime>{},
  }) {
    return PersistedCart(
      tenantId: tenantId,
      savedAt: _now().toUtc(),
      lines: [
        for (final item in items)
          PersistedCartLine(
            productId: item.product.id,
            quantity: item.quantity,
          ),
      ],
      revision: const Uuid().v4(),
      appliedMutations: Map<String, DateTime>.unmodifiable(appliedMutations),
    );
  }

  bool _hasExactLines(
    Iterable<PersistedCartLine> durable,
    Iterable<PersistedCartLine> expected,
  ) {
    final durableByProduct = <String, int>{
      for (final line in durable) line.productId: line.quantity,
    };
    final expectedByProduct = <String, int>{};
    for (final line in expected) {
      if (line.productId.trim().isEmpty || line.quantity < 1) return false;
      expectedByProduct.update(
        line.productId,
        (quantity) => quantity + line.quantity,
        ifAbsent: () => line.quantity,
      );
    }
    if (durableByProduct.length != expectedByProduct.length) return false;
    for (final entry in expectedByProduct.entries) {
      if (durableByProduct[entry.key] != entry.value) return false;
    }
    return true;
  }

  void _addQuantityTo(
    List<CartItem> items,
    Product product,
    int quantityDelta, {
    Map<String, Product>? authoritativeProducts,
  }) {
    if (quantityDelta == 0) return;
    final index = items.indexWhere((item) => item.product.id == product.id);
    final authoritativeProduct = authoritativeProducts == null
        ? product
        : authoritativeProducts[product.id];
    if (index < 0) {
      if (quantityDelta < 1) return;
      // During durable replay, absence from the freshly-loaded catalog is
      // authoritative. Never revive a deleted, unpublished or sold-out item
      // from the Product snapshot captured by an older tab.
      if (authoritativeProduct == null) return;
      final bounded = _boundedQuantity(authoritativeProduct, quantityDelta);
      if (bounded > 0) {
        items.add(
          CartItem(product: authoritativeProduct, quantity: bounded),
        );
      }
      return;
    }

    final nextQuantity = items[index].quantity + quantityDelta;
    if (nextQuantity <= 0) {
      items.removeAt(index);
      return;
    }
    final currentProduct = items[index].product;
    items[index].quantity = _boundedQuantity(currentProduct, nextQuantity);
    if (items[index].quantity <= 0) {
      items.removeAt(index);
    }
  }

  void _setQuantityIn(
    List<CartItem> items,
    Product product,
    int quantity, {
    Map<String, Product>? authoritativeProducts,
  }) {
    final index = items.indexWhere((item) => item.product.id == product.id);
    final authoritativeProduct = authoritativeProducts == null
        ? product
        : authoritativeProducts[product.id];
    final effectiveProduct =
        index >= 0 ? items[index].product : authoritativeProduct;
    if (effectiveProduct == null) return;
    final bounded = _boundedQuantity(effectiveProduct, quantity);
    if (bounded <= 0) {
      if (index >= 0) items.removeAt(index);
      return;
    }
    if (index >= 0) {
      items[index].quantity = bounded;
    } else {
      items.add(CartItem(product: effectiveProduct, quantity: bounded));
    }
  }

  /// Queues the semantic mutation, not a whole-document snapshot.
  ///
  /// [_items] changes optimistically for responsive UI. The serialized copy is
  /// updated only when this command reaches the shared persistence queue. If a
  /// completed-order consume is ahead of it, the command is replayed over the
  /// consumed durable document, so the old ordered quantities cannot return
  /// and the visitor's new mutation cannot disappear.
  void _queueMutation(
    _CartMutationApplier apply, {
    Set<String> productIds = const <String>{},
  }) {
    _stateRevision++;
    final generation = _scopeGeneration;
    final pending = _QueuedCartMutation(
      scopeGeneration: generation,
      operationId: const Uuid().v4(),
      createdAt: _now().toUtc(),
      productIds: Set<String>.unmodifiable(productIds),
      apply: apply,
    );
    _pendingMutations.add(pending);

    final tenantId = _tenantId;
    if (tenantId == null || tenantId.isEmpty) return;
    switch (_baselineState) {
      case _CartBaselineState.ready:
        _schedulePendingPersistence();
      case _CartBaselineState.fault:
        _retryFaultedBaseline();
      case _CartBaselineState.unknown:
      case _CartBaselineState.loading:
        // The semantic command is durable intent in memory, but a full
        // document must never be written until the prior baseline is known.
        break;
    }
  }

  void _schedulePendingPersistence() {
    final tenantId = _tenantId;
    if (tenantId == null ||
        tenantId.isEmpty ||
        _baselineState != _CartBaselineState.ready) {
      return;
    }
    final generation = _scopeGeneration;
    final operation =
        _persistenceQueue.catchError((Object _) {}).then((_) async {
      if (!_ownsScope(tenantId, generation) ||
          _baselineState != _CartBaselineState.ready) {
        return;
      }

      // Include any earlier command whose write failed. A later interaction
      // then persists the complete optimistic intent rather than silently
      // dropping the first command.
      final commands = _pendingMutations
          .where((entry) => entry.scopeGeneration == generation)
          .toList(growable: false);
      if (commands.isEmpty) return;
      late final List<CartItem> serializedCandidate;
      final store = _store;
      if (store is AtomicTenantCartStore) {
        final outcome = await _persistCommandsAtomically(
          tenantId: tenantId,
          generation: generation,
          commands: commands,
        );
        serializedCandidate = outcome.items;
        _droppedOnRestore += outcome.dropped;
      } else {
        serializedCandidate = _cloneItems(_serializedItems);
        for (final command in commands) {
          command.apply(serializedCandidate, null);
        }
        await _writeStoredCart(
          tenantId,
          _snapshotOf(
            serializedCandidate,
            tenantId: tenantId,
          ),
        );
      }
      if (!_ownsScope(tenantId, generation)) return;

      _serializedItems
        ..clear()
        ..addAll(_cloneItems(serializedCandidate));
      for (final command in commands) {
        _pendingMutations.remove(command);
      }
      _rebuildVisibleItems();
    });
    _persistenceQueue = operation.catchError((Object error) {
      debugPrint(
        '⚠️ [CartProvider] Could not persist the cart: $error',
      );
      _markBaselineFault(tenantId, generation);
    });
  }

  void _retryFaultedBaseline() {
    final tenantId = _tenantId;
    final loadProducts = _productLoader;
    if (tenantId == null || tenantId.isEmpty || loadProducts == null) return;

    unawaited(() async {
      final activeFlight = _restoreFlight;
      if (activeFlight != null) await activeFlight;
      if (_tenantId == tenantId && _baselineState == _CartBaselineState.fault) {
        await restore(
          tenantId: tenantId,
          loadProducts: loadProducts,
        );
      }
    }());
  }
}
