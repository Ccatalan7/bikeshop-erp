import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../modules/bikeshop/services/bikeshop_service.dart';
import '../../modules/inventory/services/category_service.dart';
import '../../modules/inventory/services/brand_service.dart';
import '../../modules/purchases/services/purchase_service.dart';
import '../../modules/tasks/services/task_service.dart';
import 'authority_scoped_cache.dart';
import 'erp_employee_directory_service.dart';

typedef DataPreloadTimerFactory = Timer Function(
  Duration delay,
  VoidCallback callback,
);

Timer _createDataPreloadTimer(Duration delay, VoidCallback callback) =>
    Timer(delay, callback);

String? _currentSupabaseUserId() =>
    Supabase.instance.client.auth.currentUser?.id;

@visibleForTesting
class DataPreloadBatchEvidence {
  static const int requiredOwnerCount = 7;

  static bool isComplete({
    required ErpAuthorityScopeKey expectedScope,
    required Iterable<ErpAuthorityScopeKey?> outcomes,
  }) {
    final materialized = outcomes.toList(growable: false);
    return materialized.length == requiredOwnerCount &&
        materialized.every((scope) => scope == expectedScope);
  }
}

@visibleForTesting
class DataPreloadRetryController {
  DataPreloadRetryController({
    List<Duration> retryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 3),
    ],
    DataPreloadTimerFactory timerFactory = _createDataPreloadTimer,
  })  : assert(retryDelays.every((delay) => !delay.isNegative)),
        _retryDelays = List<Duration>.unmodifiable(retryDelays),
        _timerFactory = timerFactory;

  final List<Duration> _retryDelays;
  final DataPreloadTimerFactory _timerFactory;
  Timer? _timer;
  int _attemptCount = 0;
  int _timerGeneration = 0;

  int get attemptCount => _attemptCount;
  int get maxAttempts => _retryDelays.length + 1;
  bool get hasScheduledRetry => _timer != null;

  bool beginAttempt() {
    cancelPending();
    if (_attemptCount >= maxAttempts) return false;
    _attemptCount++;
    return true;
  }

  bool scheduleRetry({
    required bool Function() canRun,
    required VoidCallback retry,
  }) {
    if (_timer != null ||
        _attemptCount == 0 ||
        _attemptCount > _retryDelays.length) {
      return false;
    }

    final generation = ++_timerGeneration;
    _timer = _timerFactory(_retryDelays[_attemptCount - 1], () {
      if (generation != _timerGeneration) return;
      _timer = null;
      if (canRun()) retry();
    });
    return true;
  }

  void cancelPending() {
    _timerGeneration++;
    _timer?.cancel();
    _timer = null;
  }

  void reset() {
    cancelPending();
    _attemptCount = 0;
  }
}

@visibleForTesting
class DataPreloadAuthorityScope {
  final AuthorityCacheScope _scope = AuthorityCacheScope();

  String? get userId => _scope.key?.userId;
  String? get tenantId => _scope.key?.tenantId;
  int get generation => _scope.generation;
  AuthorityCacheLease? capture() => _scope.capture();
  void invalidate() => _scope.invalidate();

  bool bind({
    required String? userId,
    required String? tenantId,
  }) =>
      _scope.bind(userId: userId, tenantId: tenantId);

  bool owns({
    required int generation,
    required String userId,
    required String tenantId,
  }) {
    final lease = AuthorityCacheLease(
      scope: ErpAuthorityScopeKey(userId: userId, tenantId: tenantId),
      generation: generation,
    );
    return _scope.owns(lease);
  }

  bool ownsLease(AuthorityCacheLease lease) => _scope.owns(lease);
}

@visibleForTesting
class DataPreloadRunCoordinator {
  DataPreloadRunCoordinator(this.authority);

  final DataPreloadAuthorityScope authority;
  Future<void>? _inFlight;
  AuthorityCacheLease? _inFlightLease;

  bool get isRunning => _inFlight != null;

  bool bind({
    required String? userId,
    required String? tenantId,
  }) {
    final changed = authority.bind(userId: userId, tenantId: tenantId);
    if (changed) detach();
    return changed;
  }

  bool hasInFlightFor(AuthorityCacheLease lease) {
    final current = _inFlightLease;
    return _inFlight != null &&
        current != null &&
        current.generation == lease.generation &&
        current.scope == lease.scope;
  }

  void detach() {
    _inFlight = null;
    _inFlightLease = null;
  }

  void restartCurrentGeneration() {
    authority.invalidate();
    detach();
  }

  Future<void> run(
    Future<void> Function(AuthorityCacheLease lease) action, {
    VoidCallback? onStart,
    VoidCallback? onCurrentFinish,
  }) {
    final lease = authority.capture();
    if (lease == null) return Future<void>.value();

    final pending = _inFlight;
    if (pending != null && hasInFlightFor(lease)) return pending;

    Future<void> execution;
    try {
      execution = action(lease);
    } catch (error, stackTrace) {
      execution = Future<void>.error(error, stackTrace);
    }

    late final Future<void> request;
    request = execution.whenComplete(() {
      if (identical(_inFlight, request)) {
        _inFlight = null;
        _inFlightLease = null;
        onCurrentFinish?.call();
      }
    });
    _inFlight = request;
    _inFlightLease = lease;
    onStart?.call();
    return request;
  }
}

/// DataPreloadService - Loads critical data immediately after authentication
///
/// This service dramatically improves perceived performance by:
/// 1. Preloading data in parallel right after login
/// 2. Populating service caches before user navigates
/// 3. Making subsequent page navigation feel instant
///
/// IMPORTANT: This service should ONLY run on ERP/admin contexts,
/// NOT on the public store (vinabike.cl, vinabike-store.web.app)
///
/// Usage: Called automatically when user authenticates on ERP
class DataPreloadService extends ChangeNotifier {
  DataPreloadService({
    @visibleForTesting List<Duration> retryDelays = const [
      Duration(seconds: 1),
      Duration(seconds: 3),
    ],
    @visibleForTesting
    DataPreloadTimerFactory timerFactory = _createDataPreloadTimer,
    @visibleForTesting String? Function()? currentUserId,
  })  : _retryController = DataPreloadRetryController(
          retryDelays: retryDelays,
          timerFactory: timerFactory,
        ),
        _currentUserId = currentUserId ?? _currentSupabaseUserId;

  bool _hasPreloaded = false;
  bool _isEnabled = true; // Can be disabled for public store
  bool _isDisposed = false;
  String? _preloadError;

  // Preload status
  bool get isPreloading => _preloadCoordinator.isRunning;
  bool get hasPreloaded => _hasPreloaded;
  bool get isEnabled => _isEnabled;
  String? get preloadError => _preloadError;

  // Service references (set via initialize)
  BikeshopService? _bikeshopService;
  CategoryService? _categoryService;
  BrandService? _brandService;
  PurchaseService? _purchaseService;
  ErpEmployeeDirectoryService? _employeeDirectoryService;
  TaskService? _taskService;
  final DataPreloadAuthorityScope _authorityScope = DataPreloadAuthorityScope();
  final DataPreloadRetryController _retryController;
  final String? Function() _currentUserId;
  late final DataPreloadRunCoordinator _preloadCoordinator =
      DataPreloadRunCoordinator(_authorityScope);

  StreamSubscription<AuthState>? _authSubscription;

  String? get authorityUserId => _authorityScope.userId;
  String? get authorityTenantId => _authorityScope.tenantId;

  /// Disable preloading (call this on public store hosts)
  void disable() {
    _isEnabled = false;
    _retryController.reset();
    _preloadCoordinator.detach();
    _bindAuthority(userId: null, tenantId: null);
    _authSubscription?.cancel();
    _authSubscription = null;
  }

  bool _isInitialized = false;

  /// Initialize with service references and start listening to auth
  /// Set isPublicStore=true to skip preloading (for customer-facing pages)
  void initialize({
    required BikeshopService bikeshopService,
    required CategoryService categoryService,
    required BrandService brandService,
    PurchaseService? purchaseService,
    ErpEmployeeDirectoryService? employeeDirectoryService,
    String? authorityTenantId,
    TaskService? taskService,
    bool isPublicStore = false, // NEW: Skip preload on public store
  }) {
    // Skip everything if this is a public store context
    if (isPublicStore) {
      if (!kReleaseMode && !_isInitialized) {
        debugPrint(
            '🏪 [DataPreloadService] Public store detected - skipping preload');
      }
      disable();
      _isInitialized = true;
      return;
    }

    _bikeshopService = bikeshopService;
    _categoryService = categoryService;
    _brandService = brandService;
    _purchaseService = purchaseService;
    _employeeDirectoryService =
        employeeDirectoryService ?? ErpEmployeeDirectoryService();
    _taskService = taskService;
    final nextUserId = _currentUserId();
    final nextTenantId = authorityTenantId?.trim();

    if (_isInitialized) {
      if (!_bindAuthority(
        userId: nextUserId,
        tenantId: nextTenantId,
      )) {
        return;
      }
      _hasPreloaded = false;
      _preloadError = null;
      notifyListeners();
      if (Supabase.instance.client.auth.currentUser != null) {
        unawaited(preloadAllData());
      }
      return;
    }

    _bindAuthority(
      userId: nextUserId,
      tenantId: nextTenantId,
    );

    // Cleanup any existing subscription (safety check)
    _authSubscription?.cancel();

    // Listen to auth state changes
    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!_isEnabled) return;

      if (data.event == AuthChangeEvent.signedIn) {
        final sessionUserId = data.session?.user.id;
        if (_authorityScope.userId != sessionUserId) {
          _bindAuthority(userId: null, tenantId: null);
          _hasPreloaded = false;
          _preloadError = null;
          notifyListeners();
          return;
        }
        if (!_hasPreloaded && _authorityScope.tenantId?.isNotEmpty == true) {
          if (!kReleaseMode) {
            debugPrint(
                '🚀 [DataPreloadService] User signed in - starting preload...');
          }
          preloadAllData();
        }
      } else if (data.event == AuthChangeEvent.signedOut) {
        // Reset state on sign out
        _bindAuthority(userId: null, tenantId: null);
        _hasPreloaded = false;
        _preloadError = null;
        notifyListeners();
      }
    });

    // If user is already logged in, preload immediately
    if (Supabase.instance.client.auth.currentUser != null && !_hasPreloaded) {
      if (!kReleaseMode) {
        debugPrint(
            '🚀 [DataPreloadService] User already logged in - starting preload...');
      }
      preloadAllData();
    }

    _isInitialized = true;
  }

  /// Preload all critical data in parallel
  Future<void> preloadAllData() {
    if (!_isEnabled) return Future<void>.value();
    final lease = _authorityScope.capture();
    if (lease == null || !_ownsCurrentAuthority(lease)) {
      return Future<void>.value();
    }

    if (_preloadCoordinator.hasInFlightFor(lease)) {
      if (!kReleaseMode) {
        debugPrint(
          '⏳ [DataPreloadService] Sharing preload for the current authority...',
        );
      }
      return _preloadCoordinator.run(_runPreload);
    }
    if (!_retryController.beginAttempt()) return Future<void>.value();

    return _preloadCoordinator.run(
      _runPreload,
      onStart: () {
        if (!_ownsCurrentAuthority(lease)) return;
        _preloadError = null;
        if (!_isDisposed) notifyListeners();
      },
      onCurrentFinish: () {
        if (_ownsCurrentAuthority(lease)) notifyListeners();
      },
    );
  }

  Future<void> _runPreload(AuthorityCacheLease lease) async {
    final stopwatch = Stopwatch()..start();
    final authorityTenantId = lease.scope.tenantId;

    try {
      if (!_ownsCurrentAuthority(lease)) return;
      _bindCacheOwnersToAuthority(lease.scope);
      if (!_ownsCurrentAuthority(lease)) return;

      if (!kReleaseMode) {
        debugPrint('🚀 [DataPreloadService] Starting lightweight preload...');
      }

      // Keep login preload constrained to lightweight/shared caches.
      // Large list datasets such as products, customers, and invoices should
      // stay module-owned and load on demand when the user actually opens that
      // workflow.
      final outcomes = await Future.wait<ErpAuthorityScopeKey?>([
        // Taller module
        _preloadJobs(),
        _preloadBikes(),
        _preloadCategories(),
        _preloadBrands(),
        _preloadSuppliers(),
        // Redacted coworker directory
        _preloadEmployeeDirectory(lease, authorityTenantId),
        // Tasks
        _preloadTasks(),
      ], eagerError: false); // Collect evidence from every cache owner.

      stopwatch.stop();
      if (!_ownsCurrentAuthority(lease)) return;
      if (!DataPreloadBatchEvidence.isComplete(
        expectedScope: lease.scope,
        outcomes: outcomes,
      )) {
        _recordIncompletePreload(lease);
        return;
      }

      _retryController.cancelPending();
      _hasPreloaded = true;
      _preloadError = null;

      if (!kReleaseMode) {
        debugPrint(
            '✅ [DataPreloadService] Preload complete in ${stopwatch.elapsedMilliseconds}ms');
      }
    } catch (_) {
      stopwatch.stop();
      if (!_ownsCurrentAuthority(lease)) return;
      _recordIncompletePreload(lease);
      if (!kReleaseMode) {
        debugPrint(
          '❌ [DataPreloadService] Preload failed after '
          '${stopwatch.elapsedMilliseconds}ms',
        );
      }
    }
  }

  void _recordIncompletePreload(AuthorityCacheLease lease) {
    if (!_ownsCurrentAuthority(lease)) return;
    _hasPreloaded = false;
    final scheduled = _retryController.scheduleRetry(
      canRun: () => _ownsCurrentAuthority(lease),
      retry: () => unawaited(preloadAllData()),
    );
    _preloadError = scheduled
        ? 'No se pudieron precargar todos los datos requeridos. '
            'Se reintentará automáticamente.'
        : 'No se pudieron precargar todos los datos requeridos.';
  }

  bool _bindAuthority({
    required String? userId,
    required String? tenantId,
  }) {
    final changed = _preloadCoordinator.bind(
      userId: userId,
      tenantId: tenantId,
    );
    if (!changed) return false;
    _retryController.reset();
    _bindCacheOwnersToAuthority(
      ErpAuthorityScopeKey.from(userId: userId, tenantId: tenantId),
    );
    return true;
  }

  void _bindCacheOwnersToAuthority(ErpAuthorityScopeKey? scope) {
    _bikeshopService?.bindAuthorityScope(
      userId: scope?.userId,
      tenantId: scope?.tenantId,
    );
    _categoryService?.bindAuthorityScope(
      userId: scope?.userId,
      tenantId: scope?.tenantId,
    );
    _brandService?.bindAuthorityScope(
      userId: scope?.userId,
      tenantId: scope?.tenantId,
    );
    _purchaseService?.bindSupplierAuthorityScope(
      userId: scope?.userId,
      tenantId: scope?.tenantId,
    );
    _taskService?.bindAuthorityScope(
      userId: scope?.userId,
      tenantId: scope?.tenantId,
    );
    _employeeDirectoryService?.clear();
  }

  bool _ownsCurrentAuthority(AuthorityCacheLease lease) =>
      _isEnabled &&
      !_isDisposed &&
      _authorityScope.ownsLease(lease) &&
      _currentUserId() == lease.scope.userId;

  /// Force refresh all cached data
  Future<void> refreshAllData() async {
    if (!_isEnabled) return;
    _retryController.reset();
    _preloadCoordinator.restartCurrentGeneration();
    _hasPreloaded = false;
    _preloadError = null;
    await preloadAllData();
  }

  // Individual preload methods with error handling

  Future<ErpAuthorityScopeKey?> _preloadJobs() async {
    final service = _bikeshopService;
    if (service == null) return null;
    try {
      final jobs = await service.getJobs(
        includeCompleted: true,
        forceRefresh: true,
      );
      if (!kReleaseMode) {
        debugPrint('📦 [Preload] Jobs: ${jobs.length} items');
      }
      return service.authorityScope;
    } catch (_) {
      if (!kReleaseMode) {
        debugPrint('⚠️ [Preload] Jobs failed');
      }
      return null;
    }
  }

  Future<ErpAuthorityScopeKey?> _preloadBikes() async {
    final service = _bikeshopService;
    if (service == null) return null;
    try {
      final bikes = await service.getBikes(forceRefresh: true);
      if (!kReleaseMode) {
        debugPrint('📦 [Preload] Bikes: ${bikes.length} items');
      }
      return service.authorityScope;
    } catch (_) {
      if (!kReleaseMode) {
        debugPrint('⚠️ [Preload] Bikes failed');
      }
      return null;
    }
  }

  Future<ErpAuthorityScopeKey?> _preloadCategories() async {
    final service = _categoryService;
    if (service == null) return null;
    try {
      final categories = await service.getCategories(forceRefresh: true);
      if (!kReleaseMode) {
        debugPrint('📦 [Preload] Categories: ${categories.length} items');
      }
      return service.authorityScope;
    } catch (_) {
      if (!kReleaseMode) {
        debugPrint('⚠️ [Preload] Categories failed');
      }
      return null;
    }
  }

  Future<ErpAuthorityScopeKey?> _preloadBrands() async {
    final service = _brandService;
    if (service == null) return null;
    try {
      final brands = await service.getBrands(forceRefresh: true);
      if (!kReleaseMode) {
        debugPrint('📦 [Preload] Brands: ${brands.length} items');
      }
      return service.authorityScope;
    } catch (_) {
      if (!kReleaseMode) {
        debugPrint('⚠️ [Preload] Brands failed');
      }
      return null;
    }
  }

  Future<ErpAuthorityScopeKey?> _preloadSuppliers() async {
    final service = _purchaseService;
    if (service == null) return null;
    try {
      final suppliers = await service.getSuppliers(forceRefresh: true);
      if (!kReleaseMode) {
        debugPrint('📦 [Preload] Suppliers: ${suppliers.length} items');
      }
      return service.supplierAuthorityScope;
    } catch (_) {
      if (!kReleaseMode) {
        debugPrint('⚠️ [Preload] Suppliers failed');
      }
      return null;
    }
  }

  Future<ErpAuthorityScopeKey?> _preloadEmployeeDirectory(
    AuthorityCacheLease lease,
    String authorityTenantId,
  ) async {
    final service = _employeeDirectoryService;
    if (service == null) return null;
    try {
      final employees = await service.getEntries(
        authorityTenantId: authorityTenantId,
        forceRefresh: true,
      );
      if (!kReleaseMode) {
        debugPrint(
          '📦 [Preload] Employee directory: ${employees.length} items',
        );
      }
      return _ownsCurrentAuthority(lease) ? lease.scope : null;
    } catch (_) {
      if (!kReleaseMode) {
        debugPrint('⚠️ [Preload] Employee directory failed');
      }
      return null;
    }
  }

  Future<ErpAuthorityScopeKey?> _preloadTasks() async {
    final service = _taskService;
    if (service == null) return null;
    try {
      final publishedScope = await service.fetchTasksForPreload();
      if (publishedScope == null) return null;
      if (!kReleaseMode) {
        debugPrint('📦 [Preload] Tasks: ${service.tasks.length} items');
      }
      return publishedScope;
    } catch (_) {
      if (!kReleaseMode) {
        debugPrint('⚠️ [Preload] Tasks failed');
      }
      return null;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _isEnabled = false;
    _retryController.reset();
    _preloadCoordinator.detach();
    _authSubscription?.cancel();
    super.dispose();
  }
}
