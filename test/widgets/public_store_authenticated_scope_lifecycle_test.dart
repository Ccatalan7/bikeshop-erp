import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/public_store/providers/cart_provider.dart';
import 'package:vinabike_erp/public_store/providers/public_store_tenant_provider.dart';
import 'package:vinabike_erp/public_store/services/cart_store.dart';
import 'package:vinabike_erp/public_store/services/public_inventory_service.dart';
import 'package:vinabike_erp/public_store/utils/public_store_tenant_resolver.dart';
import 'package:vinabike_erp/public_store/widgets/erp_mounted_storefront_scope_boundary.dart';
import 'package:vinabike_erp/shared/models/tenant.dart';
import 'package:vinabike_erp/shared/services/tenant_detection_service.dart';

const _tenantA = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
const _tenantB = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(
        detectSessionInUri: false,
      ),
    );
  });

  test(
    'authenticated ERP authority replaces detected and manually pinned scopes',
    () async {
      final detection = _ControlledTenantDetectionService()
        ..complete(_tenant(_tenantB));
      final provider = PublicStoreTenantProvider(detection);
      addTearDown(provider.dispose);

      await provider.detectTenant();
      expect(provider.tenantId, _tenantB);
      expect(provider.scopeSource, PublicStoreTenantScopeSource.detected);

      expect(
        provider.projectAuthenticatedTenantForStorefront(_tenantA),
        isTrue,
      );
      _expectAuthenticatedScope(provider, _tenantA);

      provider.setTenant(_tenant(_tenantB));
      expect(provider.tenantId, _tenantB);
      expect(provider.scopeSource, PublicStoreTenantScopeSource.manual);

      expect(
        provider.projectAuthenticatedTenantForStorefront(_tenantA),
        isTrue,
        reason:
            'An ERP-mounted storefront cannot let a test/admin pin override '
            'the authenticated tenant owner.',
      );
      _expectAuthenticatedScope(provider, _tenantA);
    },
  );

  testWidgets(
    'fresh checkout projects tenant A before restore and before its consumer',
    (tester) async {
      final provider = PublicStoreTenantProvider(
        _ControlledTenantDetectionService(),
      )..setTenant(_tenant(_tenantB));
      final events = <String>[];
      provider.addListener(() {
        if (provider.matchesAuthenticatedTenantScope(_tenantA)) {
          events.add('project');
        }
      });
      final cartStore = _ControlledCartStore(
        onRead: (tenantId) => events.add('restore:$tenantId'),
      );
      final cart = CartProvider(store: cartStore);
      final inventory = PublicInventoryService();
      final authority = _TestAuthoritySource(
        currentUserId: 'user-a',
        cachedTenantId: _tenantA,
      );
      addTearDown(provider.dispose);
      addTearDown(cart.dispose);
      addTearDown(inventory.dispose);
      addTearDown(authority.dispose);

      await tester.pumpWidget(
        _boundaryHost(
          provider: provider,
          cart: cart,
          inventory: inventory,
          authority: authority,
          onConsumerBuild: () => events.add('consumer'),
        ),
      );
      await _pumpUntil(
        tester,
        () => cartStore.readStarted.isCompleted,
      );

      _expectAuthenticatedScope(provider, _tenantA);
      expect(cartStore.lastReadTenantId, _tenantA);
      expect(find.byKey(const ValueKey('storefront-consumer')), findsNothing);
      expect(events, containsAllInOrder(['project', 'restore:$_tenantA']));

      cartStore.completeRead();
      await _pumpUntil(
        tester,
        () => find
            .byKey(const ValueKey('storefront-consumer'))
            .evaluate()
            .isNotEmpty,
      );

      expect(find.text('consumer:$_tenantA'), findsOneWidget);
      expect(events.last, 'consumer');
    },
  );

  testWidgets(
    'session A to B ignores the obsolete asynchronous tenant A result',
    (tester) async {
      final provider = PublicStoreTenantProvider(
        _ControlledTenantDetectionService(),
      );
      final cartStore = _ControlledCartStore.immediate();
      final cart = CartProvider(store: cartStore);
      final inventory = PublicInventoryService();
      final authority = _TestAuthoritySource(currentUserId: 'user-a');
      addTearDown(provider.dispose);
      addTearDown(cart.dispose);
      addTearDown(inventory.dispose);
      addTearDown(authority.dispose);

      await tester.pumpWidget(
        _boundaryHost(
          provider: provider,
          cart: cart,
          inventory: inventory,
          authority: authority,
        ),
      );
      await _pumpUntil(tester, () => authority.hasPendingResolution('user-a'));

      authority.changeSession(userId: 'user-b');
      await _pumpUntil(tester, () => authority.hasPendingResolution('user-b'));

      authority.completeResolution('user-b', _tenantB);
      await _pumpUntil(
        tester,
        () => find.text('consumer:$_tenantB').evaluate().isNotEmpty,
      );
      _expectAuthenticatedScope(provider, _tenantB);

      authority.completeResolution('user-a', _tenantA);
      await tester.pump();
      await tester.pump();

      _expectAuthenticatedScope(provider, _tenantB);
      expect(find.text('consumer:$_tenantB'), findsOneWidget);
      expect(find.text('consumer:$_tenantA'), findsNothing);
    },
  );

  testWidgets(
    'logout clears scope and hides the previously authorized consumer',
    (tester) async {
      final provider = PublicStoreTenantProvider(
        _ControlledTenantDetectionService(),
      );
      final cart = CartProvider(store: _ControlledCartStore.immediate());
      final inventory = PublicInventoryService();
      final authority = _TestAuthoritySource(
        currentUserId: 'user-a',
        cachedTenantId: _tenantA,
      );
      addTearDown(provider.dispose);
      addTearDown(cart.dispose);
      addTearDown(inventory.dispose);
      addTearDown(authority.dispose);

      await tester.pumpWidget(
        _boundaryHost(
          provider: provider,
          cart: cart,
          inventory: inventory,
          authority: authority,
        ),
      );
      await _pumpUntil(
        tester,
        () => find.text('consumer:$_tenantA').evaluate().isNotEmpty,
      );
      _expectAuthenticatedScope(provider, _tenantA);

      authority.changeSession(userId: null);
      await _pumpUntil(tester, () => provider.scope == null);

      expect(provider.scope, isNull);
      expect(provider.tenantId, isNull);
      expect(provider.currentTenant, isNull);
      expect(provider.scopeSource, isNull);
      expect(provider.hasTenant, isFalse);
      expect(provider.hasTenantScope, isFalse);
      expect(find.byKey(const ValueKey('storefront-loading')), findsOneWidget);
      expect(find.byKey(const ValueKey('storefront-consumer')), findsNothing);
    },
  );

  test(
    'legacy hasTenant remains hydration-safe while hasTenantScope tracks IDs',
    () {
      final provider = PublicStoreTenantProvider(
        _ControlledTenantDetectionService(),
      );
      addTearDown(provider.dispose);

      expect(provider.hasTenant, isFalse);
      expect(provider.hasTenantScope, isFalse);

      provider.setTenant(_tenant(_tenantB));
      expect(provider.hasTenant, isTrue);
      expect(provider.hasTenantScope, isTrue);
      expect(provider.currentTenant, isNotNull);

      provider.clearTenant();
      provider.projectAuthenticatedTenantForStorefront(_tenantA);

      expect(
        provider.hasTenant,
        isFalse,
        reason: 'Existing callers use hasTenant as the guarantee that '
            'currentTenant is hydrated.',
      );
      expect(provider.hasTenantScope, isTrue);
      expect(provider.currentTenant, isNull);
      expect(provider.tenantId, _tenantA);
    },
  );
}

Widget _boundaryHost({
  required PublicStoreTenantProvider provider,
  required CartProvider cart,
  required PublicInventoryService inventory,
  required ErpMountedStorefrontAuthoritySource authority,
  VoidCallback? onConsumerBuild,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<PublicStoreTenantProvider>.value(value: provider),
      ChangeNotifierProvider<CartProvider>.value(value: cart),
      ChangeNotifierProvider<PublicInventoryService>.value(value: inventory),
    ],
    child: MaterialApp(
      home: ErpMountedStorefrontScopeBoundary(
        authoritySource: authority,
        loading: const SizedBox(
          key: ValueKey('storefront-loading'),
        ),
        child: Builder(
          builder: (context) {
            onConsumerBuild?.call();
            final tenantId = context.read<PublicStoreTenantProvider>().tenantId;
            return Text(
              'consumer:$tenantId',
              key: const ValueKey('storefront-consumer'),
            );
          },
        ),
      ),
    ),
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 30,
}) async {
  for (var pump = 0; pump < maxPumps; pump++) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('Condition was not reached after $maxPumps pumps.');
}

void _expectAuthenticatedScope(
  PublicStoreTenantProvider provider,
  String tenantId,
) {
  expect(provider.tenantId, tenantId);
  expect(provider.scopeSource, PublicStoreTenantScopeSource.authenticatedErp);
  expect(provider.isErpProjected, isTrue);
}

Tenant _tenant(String id) {
  final timestamp = DateTime.utc(2026, 7, 30);
  return Tenant(
    id: id,
    shopName: 'Tenant $id',
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

class _ControlledTenantDetectionService extends TenantDetectionService {
  final Completer<Tenant?> _result = Completer<Tenant?>();

  void complete(Tenant? tenant) {
    if (!_result.isCompleted) _result.complete(tenant);
  }

  @override
  Future<Tenant?> detectTenant() => _result.future;
}

class _TestAuthoritySource extends ChangeNotifier
    implements ErpMountedStorefrontAuthoritySource {
  _TestAuthoritySource({
    this.currentUserId,
    this.cachedTenantId,
  });

  @override
  String? currentUserId;

  @override
  String? cachedTenantId;

  final Map<String, Completer<String?>> _resolutions = {};

  bool hasPendingResolution(String userId) => _resolutions.containsKey(userId);

  void completeResolution(String userId, String? tenantId) {
    final resolution = _resolutions[userId];
    if (resolution == null) {
      fail('No pending resolution for $userId.');
    }
    if (!resolution.isCompleted) resolution.complete(tenantId);
  }

  void changeSession({
    required String? userId,
    String? tenantId,
  }) {
    currentUserId = userId;
    cachedTenantId = tenantId;
    notifyListeners();
  }

  @override
  Future<String?> resolveTenantId() {
    final userId = currentUserId;
    if (userId == null) return Future<String?>.value();
    return _resolutions.putIfAbsent(userId, Completer<String?>.new).future;
  }
}

class _ControlledCartStore extends CartStore implements TenantScopedCartStore {
  _ControlledCartStore({
    this.onRead,
  }) : _readResult = Completer<PersistedCart?>();

  _ControlledCartStore.immediate()
      : onRead = null,
        _readResult = (Completer<PersistedCart?>()..complete());

  final void Function(String tenantId)? onRead;
  final Completer<PersistedCart?> _readResult;
  final Completer<void> readStarted = Completer<void>();
  String? lastReadTenantId;

  void completeRead([PersistedCart? cart]) {
    if (!_readResult.isCompleted) _readResult.complete(cart);
  }

  @override
  Future<PersistedCart?> readForTenant(String tenantId) {
    lastReadTenantId = tenantId;
    onRead?.call(tenantId);
    if (!readStarted.isCompleted) readStarted.complete();
    return _readResult.future;
  }

  @override
  Future<void> writeForTenant(String tenantId, PersistedCart cart) async {}

  @override
  Future<void> clearForTenant(String tenantId) async {}

  @override
  Future<PersistedCart?> read() => _readResult.future;

  @override
  Future<void> write(PersistedCart cart) async {}

  @override
  Future<void> clear() async {}
}
