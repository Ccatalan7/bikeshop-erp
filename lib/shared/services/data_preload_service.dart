import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../modules/bikeshop/services/bikeshop_service.dart';
import '../../modules/inventory/services/category_service.dart';
import '../../modules/inventory/services/brand_service.dart';
import '../../modules/purchases/services/purchase_service.dart';
import '../../modules/hr/services/hr_service.dart';
import '../../modules/tasks/services/task_service.dart';

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
  bool _isPreloading = false;
  bool _hasPreloaded = false;
  bool _isEnabled = true; // Can be disabled for public store
  String? _preloadError;

  // Preload status
  bool get isPreloading => _isPreloading;
  bool get hasPreloaded => _hasPreloaded;
  bool get isEnabled => _isEnabled;
  String? get preloadError => _preloadError;

  // Service references (set via initialize)
  BikeshopService? _bikeshopService;
  CategoryService? _categoryService;
  BrandService? _brandService;
  PurchaseService? _purchaseService;
  HRService? _hrService;
  TaskService? _taskService;

  StreamSubscription<AuthState>? _authSubscription;

  /// Disable preloading (call this on public store hosts)
  void disable() {
    _isEnabled = false;
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
    HRService? hrService,
    TaskService? taskService,
    bool isPublicStore = false, // NEW: Skip preload on public store
  }) {
    // Skip everything if this is a public store context
    if (isPublicStore) {
      if (!kReleaseMode && !_isInitialized) {
        debugPrint(
            '🏪 [DataPreloadService] Public store detected - skipping preload');
      }
      _isEnabled = false;
      _isInitialized = true;
      return;
    }

    // Prevent duplicate initialization
    if (_isInitialized) return;

    // Cleanup any existing subscription (safety check)
    _authSubscription?.cancel();

    _bikeshopService = bikeshopService;
    _categoryService = categoryService;
    _brandService = brandService;
    _purchaseService = purchaseService;
    _hrService = hrService;
    _taskService = taskService;

    // Listen to auth state changes
    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (!_isEnabled) return;

      if (data.event == AuthChangeEvent.signedIn && !_hasPreloaded) {
        if (!kReleaseMode) {
          debugPrint(
              '🚀 [DataPreloadService] User signed in - starting preload...');
        }
        preloadAllData();
      } else if (data.event == AuthChangeEvent.signedOut) {
        // Reset state on sign out
        _hasPreloaded = false;
        _preloadError = null;
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
  Future<void> preloadAllData() async {
    if (!_isEnabled) return;

    if (_isPreloading) {
      if (!kReleaseMode) {
        debugPrint('⏳ [DataPreloadService] Already preloading, skipping...');
      }
      return;
    }

    _isPreloading = true;
    _preloadError = null;
    notifyListeners();

    final stopwatch = Stopwatch()..start();

    try {
      if (!kReleaseMode) {
        debugPrint('🚀 [DataPreloadService] Starting lightweight preload...');
      }

      // Keep login preload constrained to lightweight/shared caches.
      // Large list datasets such as products, customers, and invoices should
      // stay module-owned and load on demand when the user actually opens that
      // workflow.
      await Future.wait([
        // Taller module
        _preloadJobs(),
        _preloadBikes(),
        _preloadCategories(),
        _preloadBrands(),
        _preloadSuppliers(),
        // HR
        _preloadEmployees(),
        // Tasks
        _preloadTasks(),
      ], eagerError: false); // Continue even if one fails

      stopwatch.stop();
      _hasPreloaded = true;

      if (!kReleaseMode) {
        debugPrint(
            '✅ [DataPreloadService] Preload complete in ${stopwatch.elapsedMilliseconds}ms');
      }
    } catch (e) {
      stopwatch.stop();
      _preloadError = e.toString();
      if (!kReleaseMode) {
        debugPrint(
            '❌ [DataPreloadService] Preload failed after ${stopwatch.elapsedMilliseconds}ms: $e');
      }
    } finally {
      _isPreloading = false;
      notifyListeners();
    }
  }

  /// Force refresh all cached data
  Future<void> refreshAllData() async {
    if (!_isEnabled) return;
    _hasPreloaded = false;
    await preloadAllData();
  }

  // Individual preload methods with error handling

  Future<void> _preloadJobs() async {
    try {
      final jobs = await _bikeshopService?.getJobs(includeCompleted: true);
      if (!kReleaseMode) {
        debugPrint('📦 [Preload] Jobs: ${jobs?.length ?? 0} items');
      }
    } catch (e) {
      if (!kReleaseMode) {
        debugPrint('⚠️ [Preload] Jobs failed: $e');
      }
    }
  }

  Future<void> _preloadBikes() async {
    try {
      final bikes = await _bikeshopService?.getBikes();
      if (!kReleaseMode) {
        debugPrint('📦 [Preload] Bikes: ${bikes?.length ?? 0} items');
      }
    } catch (e) {
      if (!kReleaseMode) {
        debugPrint('⚠️ [Preload] Bikes failed: $e');
      }
    }
  }

  Future<void> _preloadCategories() async {
    try {
      final categories = await _categoryService?.getCategories();
      if (!kReleaseMode) {
        debugPrint('📦 [Preload] Categories: ${categories?.length ?? 0} items');
      }
    } catch (e) {
      if (!kReleaseMode) {
        debugPrint('⚠️ [Preload] Categories failed: $e');
      }
    }
  }

  Future<void> _preloadBrands() async {
    try {
      final brands = await _brandService?.getBrands();
      if (!kReleaseMode) {
        debugPrint('📦 [Preload] Brands: ${brands?.length ?? 0} items');
      }
    } catch (e) {
      if (!kReleaseMode) {
        debugPrint('⚠️ [Preload] Brands failed: $e');
      }
    }
  }

  Future<void> _preloadSuppliers() async {
    try {
      final suppliers = await _purchaseService?.getSuppliers();
      if (!kReleaseMode) {
        debugPrint('📦 [Preload] Suppliers: ${suppliers?.length ?? 0} items');
      }
    } catch (e) {
      if (!kReleaseMode) {
        debugPrint('⚠️ [Preload] Suppliers failed: $e');
      }
    }
  }

  Future<void> _preloadEmployees() async {
    try {
      final employees = await _hrService?.getEmployees();
      if (!kReleaseMode) {
        debugPrint('📦 [Preload] Employees: ${employees?.length ?? 0} items');
      }
    } catch (e) {
      if (!kReleaseMode) {
        debugPrint('⚠️ [Preload] Employees failed: $e');
      }
    }
  }

  Future<void> _preloadTasks() async {
    try {
      await _taskService?.fetchTasks();
      if (!kReleaseMode) {
        debugPrint(
            '📦 [Preload] Tasks: ${_taskService?.tasks.length ?? 0} items');
      }
    } catch (e) {
      if (!kReleaseMode) {
        debugPrint('⚠️ [Preload] Tasks failed: $e');
      }
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
