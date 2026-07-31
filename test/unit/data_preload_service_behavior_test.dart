import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/bikeshop/models/bikeshop_models.dart';
import 'package:vinabike_erp/modules/bikeshop/services/bikeshop_service.dart';
import 'package:vinabike_erp/modules/inventory/models/brand_models.dart';
import 'package:vinabike_erp/modules/inventory/services/brand_service.dart';
import 'package:vinabike_erp/modules/inventory/services/category_service.dart';
import 'package:vinabike_erp/modules/purchases/services/purchase_service.dart';
import 'package:vinabike_erp/modules/tasks/models/task_model.dart';
import 'package:vinabike_erp/modules/tasks/services/task_service.dart';
import 'package:vinabike_erp/shared/services/authority_scoped_cache.dart';
import 'package:vinabike_erp/shared/services/data_preload_service.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';
import 'package:vinabike_erp/shared/services/erp_employee_directory_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

const _userA = '00000000-0000-4000-8000-000000000001';
const _scopeA = ErpAuthorityScopeKey(
  userId: _userA,
  tenantId: 'tenant-a',
);
const _scopeB = ErpAuthorityScopeKey(
  userId: _userA,
  tenantId: 'tenant-b',
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
      httpClient: MockClient(
        (request) async => http.Response(
          '[]',
          200,
          headers: const {'content-type': 'application/json'},
          request: request,
        ),
      ),
    );
  });

  setUp(() async {
    await _installAuthenticatedTestSession(_userA);
  });

  test('coherent A accepts seven successful empty owner publications',
      () async {
    var currentUserId = _userA;
    final harness = _PreloadHarness(
      currentUserId: () => currentUserId,
      brand: _BrandMode.coherent,
    );
    final preload = DataPreloadService(
      retryDelays: const [],
      currentUserId: () => currentUserId,
    );
    addTearDown(() {
      preload.dispose();
      harness.dispose();
    });

    harness.initialize(preload);
    await preload.preloadAllData();

    expect(preload.hasPreloaded, isTrue);
    expect(preload.preloadError, isNull);
  });

  test('A/B disagreement exhausts bounded retries without a brand query',
      () async {
    var currentUserId = _userA;
    final timers = <_ManualTimer>[];
    final harness = _PreloadHarness(
      currentUserId: () => currentUserId,
      brand: _BrandMode.resolvesTenantB,
    );
    final preload = DataPreloadService(
      retryDelays: const [
        Duration(milliseconds: 10),
        Duration(milliseconds: 20),
      ],
      timerFactory: (delay, callback) {
        final timer = _ManualTimer(callback);
        timers.add(timer);
        return timer;
      },
      currentUserId: () => currentUserId,
    );
    addTearDown(() {
      preload.dispose();
      harness.dispose();
    });

    harness.initialize(preload);
    await preload.preloadAllData();
    expect(timers, hasLength(1));

    timers[0].fire();
    await preload.preloadAllData();
    expect(timers, hasLength(2));

    timers[1].fire();
    await preload.preloadAllData();

    expect(harness.brandDatabase.selectCalls, 0);
    expect(preload.hasPreloaded, isFalse);
    expect(preload.isPreloading, isFalse);
    expect(
      preload.preloadError,
      'No se pudieron precargar todos los datos requeridos.',
    );
  });

  test('mixed A+B owner evidence cannot complete the batch', () async {
    var currentUserId = _userA;
    final harness = _PreloadHarness(
      currentUserId: () => currentUserId,
      brand: _BrandMode.reportsTenantB,
    );
    final preload = DataPreloadService(
      retryDelays: const [],
      currentUserId: () => currentUserId,
    );
    addTearDown(() {
      preload.dispose();
      harness.dispose();
    });

    harness.initialize(preload);
    await preload.preloadAllData();

    expect(preload.hasPreloaded, isFalse);
    expect(preload.preloadError, isNotNull);
  });

  test('current user change before commit suppresses status and retry',
      () async {
    var currentUserId = _userA;
    final brandStarted = Completer<void>();
    final brandGate = Completer<void>();
    final timers = <_ManualTimer>[];
    final harness = _PreloadHarness(
      currentUserId: () => currentUserId,
      brand: _BrandMode.coherent,
      brandStarted: brandStarted,
      brandGate: brandGate,
    );
    final preload = DataPreloadService(
      retryDelays: const [Duration(milliseconds: 10)],
      timerFactory: (delay, callback) {
        final timer = _ManualTimer(callback);
        timers.add(timer);
        return timer;
      },
      currentUserId: () => currentUserId,
    );
    addTearDown(() {
      preload.dispose();
      harness.dispose();
    });

    harness.initialize(preload);
    final request = preload.preloadAllData();
    await brandStarted.future;
    currentUserId = '00000000-0000-4000-8000-000000000002';
    brandGate.complete();
    await request;

    expect(preload.hasPreloaded, isFalse);
    expect(preload.preloadError, isNull);
    expect(timers, isEmpty);
  });

  test('refresh reinstalls the lease authority before loading owners',
      () async {
    var currentUserId = _userA;
    final harness = _PreloadHarness(
      currentUserId: () => currentUserId,
      brand: _BrandMode.coherent,
    );
    final preload = DataPreloadService(
      retryDelays: const [],
      currentUserId: () => currentUserId,
    );
    addTearDown(() {
      preload.dispose();
      harness.dispose();
    });

    harness.initialize(preload);
    await preload.preloadAllData();
    expect(preload.hasPreloaded, isTrue);

    final brand = harness.brand as _EvidenceBrandService;
    final bindsBeforeRefresh = brand.bindCalls;
    brand.dropAuthority();
    expect(brand.authorityScope, isNull);

    await preload.refreshAllData();

    expect(brand.bindCalls, greaterThan(bindsBeforeRefresh));
    expect(brand.authorityScope, _scopeA);
    expect(preload.hasPreloaded, isTrue);
  });
}

enum _BrandMode {
  coherent,
  resolvesTenantB,
  reportsTenantB,
}

class _PreloadHarness {
  _PreloadHarness({
    required String? Function() currentUserId,
    required _BrandMode brand,
    Completer<void>? brandStarted,
    Completer<void>? brandGate,
  })  : database = _RecordingDatabaseService(),
        brandDatabase = _RecordingDatabaseService(),
        tenantA = _tenantServiceFor('tenant-a'),
        brandTenant = _tenantServiceFor(
          brand == _BrandMode.resolvesTenantB ? 'tenant-b' : 'tenant-a',
        ) {
    bikeshop = _EvidenceBikeshopService(database);
    category = CategoryService(database, tenantA);
    this.brand = brand == _BrandMode.resolvesTenantB
        ? BrandService(
            brandDatabase,
            tenantService: brandTenant,
          )
        : _EvidenceBrandService(
            brandDatabase,
            brandTenant,
            reportedScope: brand == _BrandMode.reportsTenantB ? _scopeB : null,
            started: brandStarted,
            gate: brandGate,
          );
    purchase = PurchaseService(database, tenantA);
    task = _EvidenceTaskService(
      Supabase.instance.client,
      tenantA,
    );
    directory = ErpEmployeeDirectoryService.forTesting(
      gateway: _EmptyDirectoryGateway(currentUserId),
    );
  }

  final _RecordingDatabaseService database;
  final _RecordingDatabaseService brandDatabase;
  final TenantService tenantA;
  final TenantService brandTenant;
  late final _EvidenceBikeshopService bikeshop;
  late final CategoryService category;
  late final BrandService brand;
  late final PurchaseService purchase;
  late final _EvidenceTaskService task;
  late final ErpEmployeeDirectoryService directory;

  void initialize(DataPreloadService preload) {
    preload.initialize(
      bikeshopService: bikeshop,
      categoryService: category,
      brandService: brand,
      purchaseService: purchase,
      employeeDirectoryService: directory,
      authorityTenantId: _scopeA.tenantId,
      taskService: task,
    );
  }

  void dispose() {
    bikeshop.dispose();
    category.dispose();
    brand.dispose();
    purchase.dispose();
    task.dispose();
    tenantA.dispose();
    if (!identical(brandTenant, tenantA)) brandTenant.dispose();
    database.dispose();
    brandDatabase.dispose();
  }
}

TenantService _tenantServiceFor(String tenantId) {
  return TenantService.testing(
    currentUserId: () => _userA,
    profileLookup: (_) async => [
      {
        'tenant_id': tenantId,
        'role': 'admin',
        'permissions': const <String, dynamic>{},
      },
    ],
  );
}

class _RecordingDatabaseService extends DatabaseService {
  int selectCalls = 0;

  @override
  Future<List<Map<String, dynamic>>> select(
    String table, {
    String? selectColumns,
    String? where,
    List<String>? whereIn,
    String? orderBy,
    bool descending = false,
    int? limit,
    int? offset,
    bool fetchAll = false,
  }) async {
    selectCalls++;
    return const [];
  }
}

class _EvidenceBikeshopService extends BikeshopService {
  _EvidenceBikeshopService(super.database);

  final AuthorityCacheScope _testScope = AuthorityCacheScope();

  @override
  ErpAuthorityScopeKey? get authorityScope => _testScope.key;

  @override
  void bindAuthorityScope({
    required String? userId,
    required String? tenantId,
  }) {
    _testScope.bind(userId: userId, tenantId: tenantId);
  }

  @override
  Future<List<MechanicJob>> getJobs({
    String? customerId,
    String? bikeId,
    JobStatus? status,
    String? searchTerm,
    bool includeCompleted = true,
    bool includeDeleted = false,
    bool forceRefresh = false,
  }) async {
    return const [];
  }

  @override
  Future<List<Bike>> getBikes({
    String? customerId,
    String? searchTerm,
    bool forceRefresh = false,
  }) async {
    return const [];
  }
}

class _EvidenceBrandService extends BrandService {
  _EvidenceBrandService(
    super.database,
    TenantService tenantService, {
    this.reportedScope,
    this.started,
    this.gate,
  }) : super(tenantService: tenantService);

  final AuthorityCacheScope _testScope = AuthorityCacheScope();
  final ErpAuthorityScopeKey? reportedScope;
  final Completer<void>? started;
  final Completer<void>? gate;
  int bindCalls = 0;

  @override
  ErpAuthorityScopeKey? get authorityScope => reportedScope ?? _testScope.key;

  @override
  void bindAuthorityScope({
    required String? userId,
    required String? tenantId,
  }) {
    bindCalls++;
    _testScope.bind(userId: userId, tenantId: tenantId);
  }

  void dropAuthority() {
    _testScope.bind(userId: null, tenantId: null);
  }

  @override
  Future<List<ProductBrand>> getBrands({
    String? searchTerm,
    bool? activeOnly,
    bool forceRefresh = false,
  }) async {
    if (started != null && !started!.isCompleted) started!.complete();
    await gate?.future;
    return const [];
  }
}

class _EvidenceTaskService extends TaskService {
  _EvidenceTaskService(super.supabase, super.tenantService);

  final AuthorityCacheScope _testScope = AuthorityCacheScope();

  @override
  List<TaskModel> get tasks => const [];

  @override
  ErpAuthorityScopeKey? get authorityScope => _testScope.key;

  @override
  void bindAuthorityScope({
    required String? userId,
    required String? tenantId,
  }) {
    _testScope.bind(userId: userId, tenantId: tenantId);
  }

  @override
  Future<void> init({bool forceRefresh = false}) async {}

  @override
  Future<ErpAuthorityScopeKey?> fetchTasksForPreload() async {
    return _testScope.key;
  }
}

class _EmptyDirectoryGateway implements ErpEmployeeDirectoryGateway {
  _EmptyDirectoryGateway(this._currentUserId);

  final String? Function() _currentUserId;

  @override
  String? get currentUserId => _currentUserId();

  @override
  Future<Object?> getDirectory() async => const [];
}

class _ManualTimer implements Timer {
  _ManualTimer(this._callback);

  final void Function() _callback;
  bool _isActive = true;
  int _tick = 0;

  void fire() {
    if (!_isActive) return;
    _isActive = false;
    _tick++;
    _callback();
  }

  @override
  void cancel() {
    _isActive = false;
  }

  @override
  bool get isActive => _isActive;

  @override
  int get tick => _tick;
}

Future<void> _installAuthenticatedTestSession(String userId) async {
  final header = base64Url
      .encode(utf8.encode(jsonEncode({'alg': 'none', 'typ': 'JWT'})))
      .replaceAll('=', '');
  final payload = base64Url
      .encode(
        utf8.encode(
          jsonEncode({
            'exp': 4102444800,
            'sub': userId,
            'role': 'authenticated',
          }),
        ),
      )
      .replaceAll('=', '');
  final session = jsonEncode({
    'access_token': '$header.$payload.signature',
    'expires_in': 3600,
    'refresh_token': 'test-refresh-token',
    'token_type': 'bearer',
    'user': {
      'id': userId,
      'app_metadata': const <String, dynamic>{},
      'user_metadata': const <String, dynamic>{},
      'aud': 'authenticated',
      'created_at': '2026-07-28T00:00:00.000Z',
    },
  });
  await Supabase.instance.client.auth.recoverSession(session);
}
