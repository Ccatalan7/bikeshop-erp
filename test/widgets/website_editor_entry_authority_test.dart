import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/website/models/website_editor_capability.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_navigation_guard.dart';
import 'package:vinabike_erp/public_store/providers/cart_provider.dart';
import 'package:vinabike_erp/public_store/providers/public_store_tenant_provider.dart';
import 'package:vinabike_erp/public_store/services/public_inventory_service.dart';
import 'package:vinabike_erp/public_store/services/public_store_scroll_state.dart';
import 'package:vinabike_erp/public_store/widgets/public_store_layout.dart';
import 'package:vinabike_erp/shared/models/tenant.dart';
import 'package:vinabike_erp/shared/services/tenant_detection_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

const _grantedA = WebsiteEditorCapabilitySnapshot(
  identity: 'user-a',
  activeTenantId: 'tenant-1',
  storefrontTenantId: 'tenant-1',
  hasAuthority: true,
);
const _grantedB = WebsiteEditorCapabilitySnapshot(
  identity: 'user-b',
  activeTenantId: 'tenant-2',
  storefrontTenantId: 'tenant-2',
  hasAuthority: true,
);
const _deniedAnon = WebsiteEditorCapabilitySnapshot(
  identity: 'anon',
  activeTenantId: '',
  storefrontTenantId: 'tenant-1',
  hasAuthority: false,
);

/// Injects the single capability truth for gate tests; everything else is
/// the real WebsiteService.
class _FakeCapabilityWebsiteService extends WebsiteService {
  _FakeCapabilityWebsiteService({
    required super.supabase,
    required super.tenantService,
    required super.httpClient,
    this.syncSnapshot,
  });

  WebsiteEditorCapabilitySnapshot? syncSnapshot;
  Completer<WebsiteEditorCapabilitySnapshot>? pendingResolve;
  int revalidationEmissions = 0;

  @override
  WebsiteEditorCapabilitySnapshot? editorCapabilitySync(
    String? storefrontTenantId,
  ) =>
      syncSnapshot;

  @override
  Future<WebsiteEditorCapabilitySnapshot> resolveEditorCapability(
    String? storefrontTenantId,
  ) {
    final pending = pendingResolve;
    if (pending != null) {
      // A successful resolution warms the identity caches, exactly like
      // TenantService.getTenantId does in production.
      return pending.future.then((snapshot) {
        syncSnapshot = snapshot;
        return snapshot;
      });
    }
    return Future.value(syncSnapshot ?? _deniedAnon);
  }

  @override
  void requestActiveCmsPageOriginRevalidation() {
    revalidationEmissions++;
    super.requestActiveCmsPageOriginRevalidation();
  }
}

SupabaseClient _gateSupabaseClient() => SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (request) async => http.Response(jsonEncode([]), 200,
            headers: {'content-type': 'application/json'}),
      ),
    );

MockClient _gateHttpClient() => MockClient(
      (request) async => throw StateError('no edge calls in gate tests'),
    );

_FakeCapabilityWebsiteService _service({
  WebsiteEditorCapabilitySnapshot? sync,
}) {
  return _FakeCapabilityWebsiteService(
    supabase: _gateSupabaseClient(),
    tenantService: TenantService.testing(
      currentUserId: () => null,
      profileLookup: (_) async => const [],
    ),
    httpClient: _gateHttpClient(),
    syncSnapshot: sync,
  );
}

/// Mutable auth identity holder so the `testing` constructor's closure can
/// observe user switches after construction.
class _UserBox {
  String? userId;
}

/// A TenantService whose auth user can change and that can emit the same
/// notification its real auth-stream subscription would.
class _MutableTenantService extends TenantService {
  _MutableTenantService(_UserBox box)
      : _box = box,
        super.testing(
          currentUserId: () => box.userId,
          profileLookup: (_) async => const [],
        );

  final _UserBox _box;

  void setUser(String? id) => _box.userId = id;
  void emitAuthChange() => notifyListeners();
  bool get hasAuthListeners => hasListeners;
}

/// TenantService whose profile lookup GRANTS tenant-1 admin for whichever
/// user is active, with a real auth-notification path (epoch source).
class _ProfiledTenantService extends TenantService {
  _ProfiledTenantService(_UserBox box)
      : super.testing(
          currentUserId: () => box.userId,
          profileLookup: (_) async => const [
            {'tenant_id': 'tenant-1', 'role': 'admin', 'permissions': null},
          ],
        );

  void emitAuthChange() {
    clearCache();
    notifyListeners();
  }
}

SupabaseClient _gatedPagesSupabase(
  Completer<http.Response> gate,
  Completer<void> requestStarted,
) =>
    SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) {
        if (request.url.path.contains('rpc/load_editor_page_with_blocks')) {
          if (!requestStarted.isCompleted) requestStarted.complete();
          return gate.future.then(
            (raw) => http.Response(
              raw.body,
              raw.statusCode,
              headers: raw.headers,
              request: request,
            ),
          );
        }
        return Future.value(http.Response(jsonEncode([]), 200,
            headers: {'content-type': 'application/json'}));
      }),
    );

/// Derives the capability from the CURRENT TenantService identity so the
/// standalone lifecycle test exercises the real relay:
/// TenantService notification → WebsiteService wake → layout lease sync.
class _AuthLifecycleWebsiteService extends WebsiteService {
  _AuthLifecycleWebsiteService({
    required super.supabase,
    required _MutableTenantService tenantService,
    required super.httpClient,
  })  : mutableTenant = tenantService,
        super(tenantService: tenantService);

  final _MutableTenantService mutableTenant;
  int revalidationEmissions = 0;

  @override
  WebsiteEditorCapabilitySnapshot? editorCapabilitySync(
    String? storefrontTenantId,
  ) {
    final user = mutableTenant.currentAuthUserId;
    if (user == null) {
      return WebsiteEditorCapabilitySnapshot(
        identity: 'anon',
        activeTenantId: '',
        storefrontTenantId: storefrontTenantId ?? '',
        hasAuthority: false,
      );
    }
    return WebsiteEditorCapabilitySnapshot(
      identity: user,
      activeTenantId: 'tenant-1',
      storefrontTenantId: storefrontTenantId ?? '',
      hasAuthority: true,
    );
  }

  @override
  Future<WebsiteEditorCapabilitySnapshot> resolveEditorCapability(
    String? storefrontTenantId,
  ) async =>
      editorCapabilitySync(storefrontTenantId)!;

  @override
  void requestActiveCmsPageOriginRevalidation() {
    revalidationEmissions++;
    super.requestActiveCmsPageOriginRevalidation();
  }
}

/// Always-cold capability whose async resolutions are manually completed —
/// one Completer PER request, in creation order — so a real A0 → B → A1
/// out-of-order completion race can be driven from the test.
class _SequencedResolveWebsiteService extends WebsiteService {
  _SequencedResolveWebsiteService({
    required super.supabase,
    required super.tenantService,
    required super.httpClient,
  });

  String identity = 'user-a';
  WebsiteEditorCapabilitySnapshot? syncSnapshot;
  final List<Completer<WebsiteEditorCapabilitySnapshot>> resolveRequests = [];
  int revalidationEmissions = 0;

  @override
  WebsiteEditorCapabilitySnapshot? editorCapabilitySync(
    String? storefrontTenantId,
  ) =>
      syncSnapshot;

  @override
  String get editorCapabilityRequestIdentity => identity;

  @override
  Future<WebsiteEditorCapabilitySnapshot> resolveEditorCapability(
    String? storefrontTenantId,
  ) {
    final completer = Completer<WebsiteEditorCapabilitySnapshot>();
    resolveRequests.add(completer);
    return completer.future.then((snapshot) {
      // Only the latest fetch may warm the cache; a superseded one is
      // blocked by TenantService's resolution-generation guard.
      if (identical(completer, resolveRequests.last)) {
        syncSnapshot = snapshot;
      }
      return snapshot;
    });
  }

  void poke() => notifyListeners();

  @override
  void requestActiveCmsPageOriginRevalidation() {
    revalidationEmissions++;
    super.requestActiveCmsPageOriginRevalidation();
  }
}

const _pageBlocks = <Map<String, dynamic>>[
  {
    'id': 'block-1',
    'block_type': 'about',
    'block_data': {'title': 'Original'},
    'order_index': 0,
  },
];

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  group('editor authority rejection classifier', () {
    test('only auth/RLS rejections classify as authority loss', () {
      const rls = PostgrestException(message: 'denied', code: '42501');
      const jwtExpired = PostgrestException(message: 'jwt', code: 'PGRST301');
      const jwtInvalid = PostgrestException(message: 'jwt', code: 'PGRST302');
      const http401 = PostgrestException(message: 'auth', code: '401');
      const http403 = PostgrestException(message: 'auth', code: '403');
      expect(WebsiteService.isEditorAuthorityRejection(rls), isTrue);
      expect(WebsiteService.isEditorAuthorityRejection(jwtExpired), isTrue);
      expect(WebsiteService.isEditorAuthorityRejection(jwtInvalid), isTrue);
      expect(WebsiteService.isEditorAuthorityRejection(http401), isTrue);
      expect(WebsiteService.isEditorAuthorityRejection(http403), isTrue);
      expect(
        WebsiteService.isEditorAuthorityRejection(
          AuthApiException('forbidden', statusCode: '403'),
        ),
        isTrue,
      );
      expect(
        WebsiteService.isEditorAuthorityRejection(
          AuthSessionMissingException(),
        ),
        isTrue,
      );
      expect(
        WebsiteService.isEditorAuthorityRejection(
          AuthInvalidJwtException('bad token'),
        ),
        isTrue,
      );
      expect(
        WebsiteService.isEditorAuthorityRejection(
          const AuthException('unauthorized', statusCode: '401'),
        ),
        isTrue,
      );
    });

    test('transient failures NEVER classify as authority loss', () {
      const serverError = PostgrestException(message: 'boom', code: '500');
      const pgrstDown = PostgrestException(
        message: 'could not connect',
        code: 'PGRST000',
      );
      const noCode = PostgrestException(message: 'unknown');
      expect(WebsiteService.isEditorAuthorityRejection(serverError), isFalse);
      expect(WebsiteService.isEditorAuthorityRejection(pgrstDown), isFalse);
      expect(WebsiteService.isEditorAuthorityRejection(noCode), isFalse);
      expect(
        WebsiteService.isEditorAuthorityRejection(
          http.ClientException('network down'),
        ),
        isFalse,
      );
      // An AuthException SUBTYPE meaning "auth endpoint unreachable" — the
      // adversarial case: it must never classify as durable authority loss.
      expect(
        WebsiteService.isEditorAuthorityRejection(
          AuthRetryableFetchException(message: 'fetch failed'),
        ),
        isFalse,
      );
      expect(
        WebsiteService.isEditorAuthorityRejection(
          const AuthException('server melted', statusCode: '503'),
        ),
        isFalse,
      );
      // An AMBIGUOUS auth error (no explicit status/code) may wrap a network
      // failure: allowlist means it stays transient, never a durable deny.
      expect(
        WebsiteService.isEditorAuthorityRejection(
          const AuthException('JWT expired'),
        ),
        isFalse,
      );
      expect(
        WebsiteService.isEditorAuthorityRejection(
          AuthUnknownException(
            message: 'socket closed',
            originalError: Object(),
          ),
        ),
        isFalse,
      );
      expect(
        WebsiteService.isEditorAuthorityRejection(
          TimeoutException('slow origin'),
        ),
        isFalse,
      );
      expect(
        WebsiteService.isEditorAuthorityRejection(StateError('other')),
        isFalse,
      );
    });

    test(
        'a transient profile-lookup failure resolves as UNRESOLVED (throws), '
        'never as a durable denial', () async {
      final service = WebsiteService(
        supabase: _gateSupabaseClient(),
        tenantService: TenantService.testing(
          currentUserId: () => 'user-a',
          profileLookup: (_) async =>
              throw http.ClientException('profile lookup down'),
        ),
        httpClient: _gateHttpClient(),
      );
      expect(service.editorCapabilitySync('tenant-1'), isNull,
          reason: 'Cold cache stays cold after a failed lookup.');
      await expectLater(
        service.resolveEditorCapability('tenant-1'),
        throwsA(isA<WebsiteEditorCapabilityUnresolvedException>()),
        reason: 'Consumers must suspend/retry, not adopt a denial.');
    });

    test('a resolved profile without an active tenant is a DURABLE denial',
        () async {
      final service = WebsiteService(
        supabase: _gateSupabaseClient(),
        tenantService: TenantService.testing(
          currentUserId: () => 'user-a',
          profileLookup: (_) async => const [],
        ),
        httpClient: _gateHttpClient(),
      );
      final snapshot = await service.resolveEditorCapability('tenant-1');
      expect(snapshot.granted, isFalse);
      expect(snapshot.fingerprint, 'user-a|none|tenant-1|false');
      expect(service.editorCapabilitySync('tenant-1')?.granted, isFalse,
          reason: 'The durable denial is visible synchronously afterward.');
    });
  });

  group('lease unit semantics', () {
    test('URL commands are inert without a granted lease (fail closed)', () {
      final provider = WebsiteEditModeProvider();
      addTearDown(provider.dispose);

      provider.applyRouteModeCommand(WebsiteEditorMode.edit);
      expect(provider.mode, WebsiteEditorMode.public);

      provider.adoptEditorEntryLease(
        provider.editorEntryLeaseGeneration,
        _deniedAnon,
      );
      provider.applyRouteModeCommand(WebsiteEditorMode.edit);
      expect(provider.mode, WebsiteEditorMode.public);

      provider.revokeEditorEntryLease();
      provider.adoptEditorEntryLease(
        provider.editorEntryLeaseGeneration,
        _grantedA,
      );
      provider.applyRouteModeCommand(WebsiteEditorMode.edit);
      expect(provider.mode, WebsiteEditorMode.edit);
    });

    test('a stale generation adoption is ignored (anti-ABA)', () {
      final provider = WebsiteEditModeProvider();
      addTearDown(provider.dispose);

      final staleGeneration = provider.editorEntryLeaseGeneration;
      provider.suspendEditorEntryLease(); // A -> (revocation) bump
      expect(
        provider.adoptEditorEntryLease(staleGeneration, _grantedA),
        isFalse,
        reason: 'A response resolved for a previous generation must never '
            'grant after A -> B -> A.',
      );
      expect(provider.editorEntryLeaseGranted, isFalse);
    });

    test(
        'suspend hides but retains drafts; identity revoke discards every '
        'bucket even from the suspended-public state', () {
      final provider = WebsiteEditModeProvider();
      addTearDown(provider.dispose);
      provider.adoptEditorEntryLease(
        provider.editorEntryLeaseGeneration,
        _grantedA,
      );
      provider.enterEditMode(
        _pageBlocks,
        const <String, dynamic>{},
        pageId: 'page-a',
        pageSlug: 'page-a',
      );
      provider.updateBlockData('block-1', 'title', 'Draft A');
      provider.updateSiteSetting('store_name', 'Sitewide draft');
      provider.updatePageSeo(
        routeKey: 'page-a',
        metaTitle: 'Draft title',
        metaDescription: 'Draft description',
      );
      expect(provider.hasUnsavedChanges, isTrue);

      // Transient suspension of the SAME identity: hidden but retained.
      provider.suspendEditorEntryLease();
      expect(provider.mode, WebsiteEditorMode.public);
      expect(provider.hasUnsavedChanges, isTrue,
          reason: 'Same-identity transient failure keeps drafts for retry.');
      expect(provider.blocks, isNotEmpty);

      // Identity change: everything of identity A is discarded, even though
      // the mode was already public.
      provider.revokeEditorEntryLease();
      expect(provider.mode, WebsiteEditorMode.public);
      expect(provider.hasUnsavedChanges, isFalse);
      expect(provider.blocks, isEmpty);
      expect(provider.currentPageId, isNull);
      expect(provider.ownsPageDocument(pageId: 'page-a'), isFalse);
    });

    test(
        'suspended identity semantics: same-fingerprint regrant resumes '
        'drafts; a DIFFERENT granted identity or an authority downgrade '
        'clears every bucket', () {
      // A drafts -> transient suspend -> same fingerprint grant => preserved.
      final resumed = WebsiteEditModeProvider();
      addTearDown(resumed.dispose);
      resumed.adoptEditorEntryLease(
          resumed.editorEntryLeaseGeneration, _grantedA);
      resumed.enterEditMode(_pageBlocks, const <String, dynamic>{});
      resumed.updateBlockData('block-1', 'title', 'Draft A');
      resumed.suspendEditorEntryLease();
      expect(resumed.suspendedEditorLeaseFingerprint, _grantedA.fingerprint);
      resumed.adoptEditorEntryLease(
          resumed.editorEntryLeaseGeneration, _grantedA);
      expect(resumed.hasUnsavedChanges, isTrue,
          reason: 'The same identity resumes its retained drafts.');
      expect(resumed.blocks, isNotEmpty);

      // A drafts -> transient suspend -> B granted (same tenant) => zero
      // A buckets.
      final crossed = WebsiteEditModeProvider();
      addTearDown(crossed.dispose);
      crossed.adoptEditorEntryLease(
          crossed.editorEntryLeaseGeneration, _grantedA);
      crossed.enterEditMode(_pageBlocks, const <String, dynamic>{});
      crossed.updateBlockData('block-1', 'title', 'Draft A');
      crossed.suspendEditorEntryLease();
      crossed.adoptEditorEntryLease(
          crossed.editorEntryLeaseGeneration, _grantedB);
      expect(crossed.hasUnsavedChanges, isFalse,
          reason: 'Identity B must never inherit A\'s suspended drafts.');
      expect(crossed.blocks, isEmpty);
      expect(crossed.suspendedEditorLeaseFingerprint, isNull);

      // Authority true -> false for the same user clears too (fingerprint
      // encodes the authority bit, so it is a different identity).
      final downgraded = WebsiteEditModeProvider();
      addTearDown(downgraded.dispose);
      downgraded.adoptEditorEntryLease(
          downgraded.editorEntryLeaseGeneration, _grantedA);
      downgraded.enterEditMode(_pageBlocks, const <String, dynamic>{});
      downgraded.updateBlockData('block-1', 'title', 'Draft A');
      downgraded.suspendEditorEntryLease();
      const revokedAuthority = WebsiteEditorCapabilitySnapshot(
        identity: 'user-a',
        activeTenantId: 'tenant-1',
        storefrontTenantId: 'tenant-1',
        hasAuthority: false,
      );
      downgraded.adoptEditorEntryLease(
          downgraded.editorEntryLeaseGeneration, revokedAuthority);
      expect(downgraded.hasUnsavedChanges, isFalse);
      expect(downgraded.blocks, isEmpty);
    });

    test('a transient-only or same-value multi-update never enables Guardar',
        () {
      final provider = WebsiteEditModeProvider();
      addTearDown(provider.dispose);
      provider.enterEditMode(
        const <Map<String, dynamic>>[
          {
            'id': 'canvas-1',
            'block_type': 'canvas',
            'block_data': {
              'elements': <Map<String, dynamic>>[],
              'blockHeight': 400.0,
            },
            'order_index': 0,
          },
        ],
        const <String, dynamic>{},
      );

      provider.updateBlockDataMultiple('canvas-1', const {
        'activeElementId': 'transient-selection',
      });
      expect(provider.hasUnsavedChanges, isFalse);
      expect(provider.canUndo, isFalse);

      provider.updateBlockDataMultiple('canvas-1', const {
        'blockHeight': 400.0,
      });
      expect(provider.hasUnsavedChanges, isFalse,
          reason: 'A same-value multi-update is a no-op.');
      expect(provider.canUndo, isFalse);
    });

    test('leaveEditor commit closes the FSM with and without a draft', () {
      final withoutDraft = WebsiteEditModeProvider();
      addTearDown(withoutDraft.dispose);
      withoutDraft.enterEditMode(_pageBlocks, const <String, dynamic>{});
      expect(withoutDraft.isEditMode, isTrue);
      final cleanDecision = WebsiteEditorNavigationGuard.decisionForTesting(
        provider: withoutDraft,
        intent: WebsiteEditorNavigationIntent.leaveEditor,
        discardOnCommit: false,
      );
      expect(cleanDecision.commit(), isTrue);
      expect(withoutDraft.mode, WebsiteEditorMode.public,
          reason: 'An authorized exit without a draft still closes the FSM.');

      final withDraft = WebsiteEditModeProvider();
      addTearDown(withDraft.dispose);
      withDraft.enterEditMode(_pageBlocks, const <String, dynamic>{});
      withDraft.updateBlockData('block-1', 'title', 'Draft');
      final draftDecision = WebsiteEditorNavigationGuard.decisionForTesting(
        provider: withDraft,
        intent: WebsiteEditorNavigationIntent.leaveEditor,
        discardOnCommit: true,
      );
      expect(draftDecision.commit(), isTrue);
      expect(withDraft.mode, WebsiteEditorMode.public);
      expect(withDraft.hasUnsavedChanges, isFalse);
    });
  });

  group('layout gate integration', () {
    Future<
        ({
          GoRouter router,
          WebsiteEditModeProvider editMode,
          WebsiteService service,
        })> pumpStorefront(
      WidgetTester tester, {
      required String initialLocation,
      required WebsiteService service,
    }) async {
      await tester.binding.setSurfaceSize(const Size(2400, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      PublicStoreRuntimeConfig.isErpMounted = true;
      addTearDown(() => PublicStoreRuntimeConfig.isErpMounted = false);

      final editMode = WebsiteEditModeProvider();
      addTearDown(editMode.dispose);
      // The storefront tenant matches the granted fixtures so typed
      // lease-vs-request comparisons model a coherent identity.
      final tenant = PublicStoreTenantProvider(TenantDetectionService())
        ..setTenant(
          Tenant(
            id: 'tenant-1',
            shopName: 'Tienda gate',
            subdomain: 'gate',
            createdAt: DateTime.utc(2026, 7, 30),
            updatedAt: DateTime.utc(2026, 7, 30),
          ),
        );
      final cart = CartProvider();
      final inventory = PublicInventoryService();
      final scrollState = PublicStoreScrollState();

      final router = GoRouter(
        initialLocation: initialLocation,
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, navigationShell) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(size: const Size(700, 1200)),
              child: MultiProvider(
                providers: [
                  ChangeNotifierProvider.value(value: editMode),
                  ChangeNotifierProvider<WebsiteService>.value(value: service),
                  ChangeNotifierProvider.value(value: tenant),
                  ChangeNotifierProvider.value(value: cart),
                  ChangeNotifierProvider.value(value: inventory),
                  Provider.value(value: scrollState),
                ],
                child: PublicStoreLayout(child: navigationShell),
              ),
            ),
            branches: [
              StatefulShellBranch(routes: [
                GoRoute(
                  path: '/tienda',
                  builder: (context, state) => const SizedBox.shrink(),
                ),
              ]),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();
      return (router: router, editMode: editMode, service: service);
    }

    testWidgets('an anonymous ?edit=true deep link stays public (no chrome)',
        (tester) async {
      final harness = await pumpStorefront(
        tester,
        initialLocation: '/tienda?edit=true',
        service: _service(sync: _deniedAnon),
      );
      await tester.pump();
      expect(harness.editMode.mode, WebsiteEditorMode.public);
      expect(find.text('Editar página'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('an anonymous ?preview=true deep link stays public',
        (tester) async {
      final harness = await pumpStorefront(
        tester,
        initialLocation: '/tienda?preview=true',
        service: _service(sync: _deniedAnon),
      );
      await tester.pump();
      expect(harness.editMode.mode, WebsiteEditorMode.public);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'a cold unknown -> granted resolution enters the SAME URI exactly '
        'once; denied or error never enters', (tester) async {
      final service = _service(sync: null);
      service.pendingResolve = Completer<WebsiteEditorCapabilitySnapshot>();
      final harness = await pumpStorefront(
        tester,
        initialLocation: '/tienda?edit=true',
        service: service,
      );
      expect(harness.editMode.mode, WebsiteEditorMode.public,
          reason: 'Fail closed while the capability is unknown.');

      service.pendingResolve!.complete(_grantedA);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(harness.editMode.mode, WebsiteEditorMode.edit,
          reason: 'The pending command applies exactly once on late grant.');
      expect(service.revalidationEmissions, 1,
          reason: 'Exactly ONE central CMS revalidation per lease '
              'transition.');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'granted A -> identity B revokes: mode public and drafts of A are '
        'discarded before B is adopted', (tester) async {
      final service = _service(sync: _grantedA);
      final harness = await pumpStorefront(
        tester,
        initialLocation: '/tienda?edit=true',
        service: service,
      );
      await tester.pump();
      final editMode = harness.editMode;
      expect(editMode.mode, WebsiteEditorMode.edit);
      editMode.activatePageDocument(_pageBlocks, const <String, dynamic>{});
      await tester.pump();
      editMode.updateBlockData('block-1', 'title', 'Draft A');
      expect(editMode.hasUnsavedChanges, isTrue);

      // Identity switch (user/tenant change) — both identities granted.
      service.syncSnapshot = _grantedB;
      editMode.notifyListeners(); // Trigger a rebuild like any state change.
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(editMode.mode, WebsiteEditorMode.public,
          reason: 'B must never inherit A\'s editor mode.');
      expect(editMode.hasUnsavedChanges, isFalse,
          reason: 'B must never inherit A\'s drafts.');
      expect(editMode.blocks, isEmpty);
      expect(service.revalidationEmissions, greaterThanOrEqualTo(1));
      final emissionsAfterSwitch = service.revalidationEmissions;
      await tester.pump();
      expect(service.revalidationEmissions, emissionsAfterSwitch,
          reason: 'One coalesced emission per logical transition, not one '
              'per rebuild.');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'standalone auth lifecycle: a TenantService logout notification '
        'alone revokes and closes the editor with exactly one CMS signal, '
        'and dispose unsubscribes the relay', (tester) async {
      final box = _UserBox()..userId = 'user-a';
      final tenantService = _MutableTenantService(box);
      final service = _AuthLifecycleWebsiteService(
        supabase: _gateSupabaseClient(),
        tenantService: tenantService,
        httpClient: _gateHttpClient(),
      );
      final harness = await pumpStorefront(
        tester,
        initialLocation: '/tienda?edit=true',
        service: service,
      );
      await tester.pump();
      expect(harness.editMode.mode, WebsiteEditorMode.edit);
      expect(tenantService.hasAuthListeners, isTrue,
          reason: 'The service must relay identity notifications so the '
              'standalone storefront (main_store) rebuilds on auth events.');

      final baseline = service.revalidationEmissions;
      // The ONLY stimulus: the auth notification itself. No taps, no route
      // change, no other provider mutation.
      tenantService.setUser(null);
      tenantService.emitAuthChange();
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(harness.editMode.mode, WebsiteEditorMode.public,
          reason: 'Logout must revoke/close editor context without any '
              'other interaction.');
      expect(harness.editMode.isInEditorContext, isFalse);
      expect(harness.editMode.editorEntryLeaseGranted, isFalse);
      expect(service.revalidationEmissions, baseline + 1,
          reason: 'The auth wake must not emit its own CMS signal; the '
              'lease transition is the single emitter (exactly one).');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      service.dispose();
      expect(tenantService.hasAuthListeners, isFalse,
          reason: 'dispose must remove the TenantService listener.');
      tenantService.emitAuthChange(); // Inert after dispose: must not throw.
    });

    testWidgets(
        'cold identity A -> B -> A: stale A0 and B completions are dropped '
        'even though the recycled request key matches; only the LATEST A1 '
        'resolution can open the editor', (tester) async {
      final service = _SequencedResolveWebsiteService(
        supabase: _gateSupabaseClient(),
        tenantService: TenantService.testing(
          currentUserId: () => null,
          profileLookup: (_) async => const [],
        ),
        httpClient: _gateHttpClient(),
      );
      final harness = await pumpStorefront(
        tester,
        initialLocation: '/tienda?edit=true',
        service: service,
      );
      expect(harness.editMode.mode, WebsiteEditorMode.public);
      expect(service.resolveRequests.length, 1, reason: 'request A0');

      // Identity change to B while A0 is in flight.
      service.identity = 'user-b';
      service.poke();
      await tester.pump();
      expect(service.resolveRequests.length, 2, reason: 'request B');

      // Back to A: the request key string ('gen|user-a|tenant') is now
      // RECYCLED — identical to A0's — with the provider generation still
      // unchanged. Only the per-request serial distinguishes them.
      service.identity = 'user-a';
      service.poke();
      await tester.pump();
      expect(service.resolveRequests.length, 3, reason: 'request A1');

      // Out-of-order completions: the stale A0 (matching key!) first.
      service.resolveRequests[0].complete(_grantedA);
      await tester.pump();
      await tester.pump();
      expect(harness.editMode.mode, WebsiteEditorMode.public,
          reason: 'A0 is superseded; adopting it would be the ABA defect.');
      expect(harness.editMode.editorEntryLeaseGranted, isFalse);
      expect(service.revalidationEmissions, 0);

      service.resolveRequests[1].complete(_grantedB);
      await tester.pump();
      await tester.pump();
      expect(harness.editMode.mode, WebsiteEditorMode.public,
          reason: 'B was superseded by A1 as well.');
      expect(service.revalidationEmissions, 0);

      // Only the latest request may adopt and open.
      service.resolveRequests[2].complete(_grantedA);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(harness.editMode.mode, WebsiteEditorMode.edit,
          reason: 'A1 is the latest request: it adopts and applies the '
              'pending URL command exactly once.');
      expect(service.revalidationEmissions, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'a cold-cache identity switch revokes A BEFORE the await: B never '
        'sees one frame of A\'s chrome or drafts', (tester) async {
      final service = _SequencedResolveWebsiteService(
        supabase: _gateSupabaseClient(),
        tenantService: TenantService.testing(
          currentUserId: () => null,
          profileLookup: (_) async => const [],
        ),
        httpClient: _gateHttpClient(),
      )
        ..identity = 'user-a'
        ..syncSnapshot = _grantedA;
      final harness = await pumpStorefront(
        tester,
        initialLocation: '/tienda?edit=true',
        service: service,
      );
      await tester.pump();
      final editMode = harness.editMode;
      expect(editMode.mode, WebsiteEditorMode.edit);
      editMode.activatePageDocument(_pageBlocks, const <String, dynamic>{});
      await tester.pump();
      editMode.updateBlockData('block-1', 'title', 'Draft A');
      expect(editMode.hasUnsavedChanges, isTrue);

      // Identity B arrives with COLD caches: the resolve is async, but A
      // must disappear synchronously in this very build.
      service.syncSnapshot = null;
      service.identity = 'user-b';
      service.poke();
      await tester.pump();

      expect(editMode.mode, WebsiteEditorMode.public,
          reason: 'A is hidden/revoked BEFORE awaiting B\'s resolution.');
      expect(editMode.editorEntryLeaseGranted, isFalse);
      expect(editMode.hasUnsavedChanges, isFalse,
          reason: 'A\'s drafts are discarded on the identity change.');
      expect(editMode.blocks, isEmpty);

      // When B finally resolves granted, A's old ?edit=true command was
      // consumed by the identity change: B stays public until B issues a
      // deliberate new entry command.
      service.resolveRequests.last.complete(_grantedB);
      await tester.pump();
      await tester.pump();
      expect(editMode.mode, WebsiteEditorMode.public);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'a SAME-identity cold cache suspends before the await — chrome '
        'hidden, drafts retained — and a same-fingerprint regrant restores '
        'the session', (tester) async {
      final service = _SequencedResolveWebsiteService(
        supabase: _gateSupabaseClient(),
        tenantService: TenantService.testing(
          currentUserId: () => null,
          profileLookup: (_) async => const [],
        ),
        httpClient: _gateHttpClient(),
      )
        ..identity = 'user-a'
        ..syncSnapshot = _grantedA;
      final harness = await pumpStorefront(
        tester,
        initialLocation: '/tienda?edit=true',
        service: service,
      );
      await tester.pump();
      final editMode = harness.editMode;
      expect(editMode.mode, WebsiteEditorMode.edit);
      editMode.activatePageDocument(_pageBlocks, const <String, dynamic>{});
      await tester.pump();
      editMode.updateBlockData('block-1', 'title', 'Draft A');

      // The warm caches clear for the SAME identity (auth/role refresh in
      // flight): authority is unknown, so the projection fails closed NOW,
      // before the await — but the drafts survive hidden.
      service.syncSnapshot = null;
      service.poke();
      await tester.pump();

      expect(editMode.mode, WebsiteEditorMode.public,
          reason: 'Unknown authority may not keep showing Edit.');
      expect(editMode.editorEntryLeaseGranted, isFalse);
      expect(
        editMode.suspendedEditorLeaseFingerprint,
        _grantedA.fingerprint,
        reason: 'A suspension retains the identity of its hidden drafts.',
      );

      // The SAME fingerprint resolves granted again: session restored, and
      // the still-projected ?edit=true URI re-enters exactly once.
      service.resolveRequests.last.complete(_grantedA);
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(editMode.mode, WebsiteEditorMode.edit,
          reason: 'A same-fingerprint regrant resumes the session.');
      expect(editMode.hasUnsavedChanges, isTrue,
          reason: 'The retained draft is visible again.');
      expect(
        editMode.blocks.single['block_data']['title'],
        'Draft A',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'a resolution that completes AFTER an identity switch but BEFORE any '
        'rebuild is dropped (post-await identity revalidation)',
        (tester) async {
      final service = _SequencedResolveWebsiteService(
        supabase: _gateSupabaseClient(),
        tenantService: TenantService.testing(
          currentUserId: () => null,
          profileLookup: (_) async => const [],
        ),
        httpClient: _gateHttpClient(),
      )..identity = 'user-a';
      final harness = await pumpStorefront(
        tester,
        initialLocation: '/tienda?edit=true',
        service: service,
      );
      expect(service.resolveRequests.length, 1);

      // Identity switches WITHOUT any rebuild: same serial, same key, same
      // generation — only the captured identity context can catch this.
      service.identity = 'user-b';
      service.resolveRequests.single.complete(_grantedA);
      await tester.pump();
      await tester.pump();

      expect(harness.editMode.mode, WebsiteEditorMode.public,
          reason: 'A\'s grant completed inside B\'s window: dropped.');
      expect(harness.editMode.editorEntryLeaseGranted, isFalse);
      expect(service.revalidationEmissions, 0);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'an asynchronous revocation between builds consumes the pending URI '
        'command: B never inherits A\'s ?edit=true', (tester) async {
      final service = _SequencedResolveWebsiteService(
        supabase: _gateSupabaseClient(),
        tenantService: TenantService.testing(
          currentUserId: () => null,
          profileLookup: (_) async => const [],
        ),
        httpClient: _gateHttpClient(),
      )
        ..identity = 'user-a'
        ..syncSnapshot = _grantedA;
      final harness = await pumpStorefront(
        tester,
        initialLocation: '/tienda?edit=true',
        service: service,
      );
      await tester.pump();
      final editMode = harness.editMode;
      expect(editMode.mode, WebsiteEditorMode.edit);

      // The revocation happens OUTSIDE any build (auth event/OAuth), then B
      // becomes the warm identity.
      editMode.revokeEditorEntryLease();
      service.syncSnapshot = _grantedB;
      service.identity = 'user-b';
      service.poke();
      await tester.pump();
      await tester.pump();

      expect(editMode.editorEntryLease?.fingerprint, _grantedB.fingerprint,
          reason: 'B\'s lease is adopted…');
      expect(editMode.mode, WebsiteEditorMode.public,
          reason: '…but A\'s pending ?edit=true died with A\'s identity '
              'revision: B must issue its own entry command.');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'OAuth restore drops a stale grant after a coalesced A -> B -> A '
        'auth sequence (identity epoch)', (tester) async {
      final box = _UserBox()..userId = 'user-a';
      final tenantService = _MutableTenantService(box);
      final service = _SequencedResolveWebsiteService(
        supabase: _gateSupabaseClient(),
        tenantService: tenantService,
        httpClient: _gateHttpClient(),
      )..identity = 'user-a';
      final provider = WebsiteEditModeProvider();
      addTearDown(provider.dispose);

      final future = PublicStoreLayout.restoreEditorSessionAfterOAuth(
        editProvider: provider,
        websiteService: service,
        currentTenantId: () => 'tenant-1',
      );
      // Two coalesced auth events (A -> B -> A): the user id string ends up
      // equal, only the epoch reveals the churn.
      tenantService.emitAuthChange();
      tenantService.emitAuthChange();
      service.resolveRequests.single.complete(_grantedA);

      final outcome = await future;
      expect(outcome, WebsiteEditorOAuthRestoreOutcome.superseded);
      expect(provider.mode, WebsiteEditorMode.public);
      expect(provider.editorEntryLeaseGranted, isFalse);
      await tester.pump();
    });

    testWidgets(
        'OAuth restore on a transient failure suspends, retains drafts and '
        'never fabricates a denial', (tester) async {
      final service = _SequencedResolveWebsiteService(
        supabase: _gateSupabaseClient(),
        tenantService: TenantService.testing(
          currentUserId: () => null,
          profileLookup: (_) async => const [],
        ),
        httpClient: _gateHttpClient(),
      )..identity = 'user-a';
      final provider = WebsiteEditModeProvider();
      addTearDown(provider.dispose);
      provider.adoptEditorEntryLease(0, _grantedA);
      provider.enterPreviewMode(
        _pageBlocks,
        const <String, dynamic>{},
        pageId: 'page-a',
        pageSlug: 'page-a',
      );
      provider.updateBlockData('block-1', 'title', 'Draft A');

      final future = PublicStoreLayout.restoreEditorSessionAfterOAuth(
        editProvider: provider,
        websiteService: service,
        currentTenantId: () => 'tenant-1',
      );
      service.resolveRequests.single
          .completeError(http.ClientException('network down'));

      final outcome = await future;
      expect(outcome, WebsiteEditorOAuthRestoreOutcome.transient);
      expect(provider.mode, WebsiteEditorMode.public,
          reason: 'Unknown authority hides the editor projection.');
      expect(provider.editorEntryLeaseDenied, isFalse,
          reason: 'No fabricated denial.');
      expect(
        provider.suspendedEditorLeaseFingerprint,
        _grantedA.fingerprint,
        reason: 'The drafts stay retained for this identity\'s retry.',
      );
      await tester.pump();
    });

    testWidgets(
        'a programmatic open under a warm DENIED lease closes immediately: '
        'Public, zero chrome, zero draft', (tester) async {
      final service = _service(sync: _deniedAnon);
      final harness = await pumpStorefront(
        tester,
        initialLocation: '/tienda',
        service: service,
      );
      await tester.pump();
      final editMode = harness.editMode;
      // The bypass attempt: a programmatic open without authority.
      editMode.enterEditMode(_pageBlocks, const <String, dynamic>{});
      editMode.updateBlockData('block-1', 'title', 'Bypass draft');
      await tester.pump();
      await tester.pump();

      expect(editMode.mode, WebsiteEditorMode.public);
      expect(editMode.isInEditorContext, isFalse);
      expect(editMode.blocks, isEmpty);
      expect(editMode.hasUnsavedChanges, isFalse);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets('OAuth restore granted branch enters Edit exactly once',
        (tester) async {
      final service = _SequencedResolveWebsiteService(
        supabase: _gateSupabaseClient(),
        tenantService: TenantService.testing(
          currentUserId: () => null,
          profileLookup: (_) async => const [],
        ),
        httpClient: _gateHttpClient(),
      )..identity = 'user-a';
      final provider = WebsiteEditModeProvider();
      addTearDown(provider.dispose);

      final future = PublicStoreLayout.restoreEditorSessionAfterOAuth(
        editProvider: provider,
        websiteService: service,
        currentTenantId: () => 'tenant-1',
      );
      service.resolveRequests.single.complete(_grantedA);
      final outcome = await future;
      expect(outcome, WebsiteEditorOAuthRestoreOutcome.granted);
      expect(provider.mode, WebsiteEditorMode.edit);
      expect(provider.editorEntryLeaseGranted, isTrue);
      await tester.pump();
    });

    testWidgets(
        'OAuth restore denied branch revokes and closes a projected session',
        (tester) async {
      final service = _SequencedResolveWebsiteService(
        supabase: _gateSupabaseClient(),
        tenantService: TenantService.testing(
          currentUserId: () => null,
          profileLookup: (_) async => const [],
        ),
        httpClient: _gateHttpClient(),
      )..identity = 'anon';
      final provider = WebsiteEditModeProvider();
      addTearDown(provider.dispose);
      // A projected session without authority (e.g. restored programmatic
      // state) must not survive a durable denial.
      provider.enterPreviewMode(_pageBlocks, const <String, dynamic>{});
      provider.updateBlockData('block-1', 'title', 'Doomed draft');

      final future = PublicStoreLayout.restoreEditorSessionAfterOAuth(
        editProvider: provider,
        websiteService: service,
        currentTenantId: () => 'tenant-1',
      );
      service.resolveRequests.single.complete(_deniedAnon);
      final outcome = await future;
      expect(outcome, WebsiteEditorOAuthRestoreOutcome.denied);
      expect(provider.mode, WebsiteEditorMode.public);
      expect(provider.blocks, isEmpty);
      expect(provider.hasUnsavedChanges, isFalse);
      expect(provider.editorEntryLeaseDenied, isTrue);
      await tester.pump();
    });

    test(
        'a classified server rejection installs a durable denial for the '
        'SAME identity until new auth evidence clears it', () async {
      final box = _UserBox()..userId = 'user-a';
      final tenantService = _ProfiledTenantService(box);
      final gate = Completer<http.Response>();
      final requestStarted = Completer<void>();
      final service = WebsiteService(
        supabase: _gatedPagesSupabase(gate, requestStarted),
        tenantService: tenantService,
        httpClient: _gateHttpClient(),
      );
      addTearDown(service.dispose);
      await tenantService.getTenantId();
      expect(service.editorCapabilitySync('tenant-1')!.granted, isTrue);

      final pending =
          service.loadEditorPageWithBlocks('landing', tenantId: 'tenant-1');
      await requestStarted.future; // The RPC is genuinely in flight.
      gate.complete(http.Response(
          jsonEncode({'message': 'denied', 'code': '42501'}), 403,
          headers: {'content-type': 'application/json'}));
      await expectLater(
        pending,
        throwsA(isA<WebsiteEditorAuthorityException>()),
      );
      expect(service.editorCapabilitySync('tenant-1')!.granted, isFalse,
          reason: 'Durable typed denial: no revoke -> re-grant loop.');
      expect(await service.canOpenEditorForTenant('tenant-1'), isFalse);

      // New identity evidence replaces the denial.
      tenantService.emitAuthChange();
      await tenantService.getTenantId();
      expect(service.editorCapabilitySync('tenant-1')!.granted, isTrue);
    });

    test(
        'a LATE 42501 from identity A cannot latch a denial for the '
        'switched identity B nor revoke it', () async {
      final box = _UserBox()..userId = 'user-a';
      final tenantService = _ProfiledTenantService(box);
      final gate = Completer<http.Response>();
      final requestStarted = Completer<void>();
      final service = WebsiteService(
        supabase: _gatedPagesSupabase(gate, requestStarted),
        tenantService: tenantService,
        httpClient: _gateHttpClient(),
      );
      addTearDown(service.dispose);
      await tenantService.getTenantId();
      final pending =
          service.loadEditorPageWithBlocks('landing', tenantId: 'tenant-1');
      await requestStarted.future; // Context captured; RPC in flight.
      // Identity switch WHILE the editor read is in flight.
      box.userId = 'user-b';
      tenantService.emitAuthChange();
      gate.complete(http.Response(
          jsonEncode({'message': 'denied', 'code': '42501'}), 403,
          headers: {'content-type': 'application/json'}));

      // Superseded: a TYPED obsolete completion — the consumer discards
      // it silently and never revokes B.
      await expectLater(
        pending,
        throwsA(isA<WebsiteEditorReadSupersededException>()),
      );

      await tenantService.getTenantId(); // Warm B.
      expect(service.editorCapabilitySync('tenant-1')!.granted, isTrue,
          reason: 'B\'s capability is untouched by A\'s late rejection.');
    });

    testWidgets(
        'OAuth restore with a LIVE A session under a B request revokes '
        'BEFORE any await and returns superseded (one signal)',
        (tester) async {
      final service = _SequencedResolveWebsiteService(
        supabase: _gateSupabaseClient(),
        tenantService: TenantService.testing(
          currentUserId: () => null,
          profileLookup: (_) async => const [],
        ),
        httpClient: _gateHttpClient(),
      )..identity = 'user-b';
      final provider = WebsiteEditModeProvider();
      addTearDown(provider.dispose);
      provider.adoptEditorEntryLease(0, _grantedA);
      provider.enterPreviewMode(
        _pageBlocks,
        const <String, dynamic>{},
        pageId: 'page-a',
        pageSlug: 'page-a',
      );
      provider.updateBlockData('block-1', 'title', 'Draft A');

      final outcome = await PublicStoreLayout.restoreEditorSessionAfterOAuth(
        editProvider: provider,
        websiteService: service,
        currentTenantId: () => 'tenant-1',
      );

      expect(outcome, WebsiteEditorOAuthRestoreOutcome.superseded);
      expect(provider.mode, WebsiteEditorMode.public);
      expect(provider.blocks, isEmpty,
          reason: 'A\'s session and drafts die before B\'s await.');
      expect(service.resolveRequests, isEmpty,
          reason: 'No resolution is even STARTED for a foreign session.');
      expect(service.revalidationEmissions, 1,
          reason: 'Exactly one CMS transition for the takeover.');
      await tester.pump();
    });

    testWidgets(
        'OAuth restore denied outcome emits EXACTLY one CMS revalidation',
        (tester) async {
      final service = _SequencedResolveWebsiteService(
        supabase: _gateSupabaseClient(),
        tenantService: TenantService.testing(
          currentUserId: () => null,
          profileLookup: (_) async => const [],
        ),
        httpClient: _gateHttpClient(),
      )..identity = 'anon';
      final provider = WebsiteEditModeProvider();
      addTearDown(provider.dispose);
      provider.enterPreviewMode(_pageBlocks, const <String, dynamic>{});

      final future = PublicStoreLayout.restoreEditorSessionAfterOAuth(
        editProvider: provider,
        websiteService: service,
        currentTenantId: () => 'tenant-1',
      );
      service.resolveRequests.single.complete(_deniedAnon);
      final outcome = await future;
      expect(outcome, WebsiteEditorOAuthRestoreOutcome.denied);
      expect(service.revalidationEmissions, 1,
          reason: 'revoke + adopt coalesce into ONE transition.');
      await tester.pump();
    });

    testWidgets(
        'EPOCH MATRIX (layout): the same fingerprint at a NEW authorityEpoch '
        'is a takeover — drafts die, one CMS transition, the old URI command '
        'is consumed', (tester) async {
      const grantedAEpoch1 = WebsiteEditorCapabilitySnapshot(
        identity: 'user-a',
        activeTenantId: 'tenant-1',
        storefrontTenantId: 'tenant-1',
        hasAuthority: true,
        authorityEpoch: 1,
      );
      final service = _SequencedResolveWebsiteService(
        supabase: _gateSupabaseClient(),
        tenantService: TenantService.testing(
          currentUserId: () => null,
          profileLookup: (_) async => const [],
        ),
        httpClient: _gateHttpClient(),
      )
        ..identity = 'user-a'
        ..syncSnapshot = _grantedA;
      final harness = await pumpStorefront(
        tester,
        initialLocation: '/tienda?edit=true',
        service: service,
      );
      await tester.pump();
      final editMode = harness.editMode;
      expect(editMode.mode, WebsiteEditorMode.edit);
      editMode.activatePageDocument(_pageBlocks, const <String, dynamic>{});
      await tester.pump();
      editMode.updateBlockData('block-1', 'title', 'Draft A epoch 0');
      final emissionsBefore = service.revalidationEmissions;

      // Coalesced A -> B -> A: identical fingerprint, NEW epoch.
      service.syncSnapshot = grantedAEpoch1;
      service.poke();
      await tester.pump();
      await tester.pump();

      expect(editMode.mode, WebsiteEditorMode.public,
          reason: 'The old epoch\'s ?edit=true command died with it.');
      expect(editMode.blocks, isEmpty,
          reason: 'Epoch-0 drafts never survive into epoch 1.');
      expect(editMode.hasUnsavedChanges, isFalse);
      expect(editMode.editorEntryLease?.authorityEpoch, 1,
          reason: 'The NEW epoch lease is adopted after the takeover.');
      expect(service.revalidationEmissions, emissionsBefore + 1,
          reason: 'Exactly ONE CMS transition for the takeover.');
      final emissionsAfter = service.revalidationEmissions;
      await tester.pump();
      expect(service.revalidationEmissions, emissionsAfter);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    });

    testWidgets(
        'OAuth restore bound to an ISSUER fingerprint supersedes a grant '
        'for any other authority — even a valid one', (tester) async {
      final service = _SequencedResolveWebsiteService(
        supabase: _gateSupabaseClient(),
        tenantService: TenantService.testing(
          currentUserId: () => null,
          profileLookup: (_) async => const [],
        ),
        httpClient: _gateHttpClient(),
      )..identity = 'user-b';
      final provider = WebsiteEditModeProvider();
      addTearDown(provider.dispose);

      final future = PublicStoreLayout.restoreEditorSessionAfterOAuth(
        editProvider: provider,
        websiteService: service,
        currentTenantId: () => 'tenant-2',
        expectedIssuerFingerprint: _grantedA.fingerprint,
      );
      service.resolveRequests.single.complete(_grantedB);
      final outcome = await future;
      expect(outcome, WebsiteEditorOAuthRestoreOutcome.superseded,
          reason: 'B\'s valid grant can never redeem A\'s intent.');
      expect(provider.mode, WebsiteEditorMode.public);
      await tester.pump();
    });
  });
}
