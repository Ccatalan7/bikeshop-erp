import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../modules/bikeshop/services/bikeshop_service.dart';
import '../../modules/crm/services/customer_service.dart';
import '../../modules/inventory/services/inventory_service.dart';
import '../../modules/inventory/services/category_service.dart';
import '../../modules/inventory/services/brand_service.dart';
import '../../modules/sales/services/sales_service.dart';
import '../../modules/purchases/services/purchase_service.dart';
import '../../modules/hr/services/hr_service.dart';

/// DataPreloadService - Loads critical data immediately after authentication
/// 
/// This service dramatically improves perceived performance by:
/// 1. Preloading data in parallel right after login
/// 2. Populating service caches before user navigates
/// 3. Making subsequent page navigation feel instant
/// 
/// Usage: Called automatically when user authenticates
class DataPreloadService extends ChangeNotifier {
  bool _isPreloading = false;
  bool _hasPreloaded = false;
  String? _preloadError;
  DateTime? _lastPreloadTime;
  
  // Preload status
  bool get isPreloading => _isPreloading;
  bool get hasPreloaded => _hasPreloaded;
  String? get preloadError => _preloadError;
  
  // Service references (set via initialize)
  BikeshopService? _bikeshopService;
  CustomerService? _customerService;
  InventoryService? _inventoryService;
  CategoryService? _categoryService;
  BrandService? _brandService;
  SalesService? _salesService;
  PurchaseService? _purchaseService;
  HRService? _hrService;
  
  StreamSubscription<AuthState>? _authSubscription;
  
  /// Initialize with service references and start listening to auth
  void initialize({
    required BikeshopService bikeshopService,
    required CustomerService customerService,
    required InventoryService inventoryService,
    required CategoryService categoryService,
    required BrandService brandService,
    SalesService? salesService,
    PurchaseService? purchaseService,
    HRService? hrService,
  }) {
    _bikeshopService = bikeshopService;
    _customerService = customerService;
    _inventoryService = inventoryService;
    _categoryService = categoryService;
    _brandService = brandService;
    _salesService = salesService;
    _purchaseService = purchaseService;
    _hrService = hrService;
    
    // Listen to auth state changes
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn && !_hasPreloaded) {
        debugPrint('🚀 [DataPreloadService] User signed in - starting preload...');
        preloadAllData();
      } else if (data.event == AuthChangeEvent.signedOut) {
        // Reset state on sign out
        _hasPreloaded = false;
        _preloadError = null;
        _lastPreloadTime = null;
      }
    });
    
    // If user is already logged in, preload immediately
    if (Supabase.instance.client.auth.currentUser != null && !_hasPreloaded) {
      debugPrint('🚀 [DataPreloadService] User already logged in - starting preload...');
      preloadAllData();
    }
  }
  
  /// Preload all critical data in parallel
  Future<void> preloadAllData() async {
    if (_isPreloading) {
      debugPrint('⏳ [DataPreloadService] Already preloading, skipping...');
      return;
    }
    
    _isPreloading = true;
    _preloadError = null;
    notifyListeners();
    
    final stopwatch = Stopwatch()..start();
    
    try {
      debugPrint('🚀 [DataPreloadService] Starting parallel preload...');
      
      // Load all data in parallel for maximum speed
      await Future.wait([
        // Taller module
        _preloadJobs(),
        _preloadBikes(),
        // CRM
        _preloadCustomers(),
        // Inventory
        _preloadProducts(),
        _preloadCategories(),
        _preloadBrands(),
        // Sales
        _preloadSalesInvoices(),
        // Purchases
        _preloadPurchaseInvoices(),
        _preloadSuppliers(),
        // HR
        _preloadEmployees(),
      ], eagerError: false); // Continue even if one fails
      
      stopwatch.stop();
      _hasPreloaded = true;
      _lastPreloadTime = DateTime.now();
      
      debugPrint('✅ [DataPreloadService] Preload complete in ${stopwatch.elapsedMilliseconds}ms');
      
    } catch (e) {
      stopwatch.stop();
      _preloadError = e.toString();
      debugPrint('❌ [DataPreloadService] Preload failed after ${stopwatch.elapsedMilliseconds}ms: $e');
    } finally {
      _isPreloading = false;
      notifyListeners();
    }
  }
  
  /// Force refresh all cached data
  Future<void> refreshAllData() async {
    _hasPreloaded = false;
    await preloadAllData();
  }
  
  // Individual preload methods with error handling
  
  Future<void> _preloadJobs() async {
    try {
      final jobs = await _bikeshopService?.getJobs(includeCompleted: true);
      debugPrint('📦 [Preload] Jobs: ${jobs?.length ?? 0} items');
    } catch (e) {
      debugPrint('⚠️ [Preload] Jobs failed: $e');
    }
  }
  
  Future<void> _preloadBikes() async {
    try {
      final bikes = await _bikeshopService?.getBikes();
      debugPrint('📦 [Preload] Bikes: ${bikes?.length ?? 0} items');
    } catch (e) {
      debugPrint('⚠️ [Preload] Bikes failed: $e');
    }
  }
  
  Future<void> _preloadCustomers() async {
    try {
      final customers = await _customerService?.getCustomers();
      debugPrint('📦 [Preload] Customers: ${customers?.length ?? 0} items');
    } catch (e) {
      debugPrint('⚠️ [Preload] Customers failed: $e');
    }
  }
  
  Future<void> _preloadProducts() async {
    try {
      final products = await _inventoryService?.getProducts();
      debugPrint('📦 [Preload] Products: ${products?.length ?? 0} items');
    } catch (e) {
      debugPrint('⚠️ [Preload] Products failed: $e');
    }
  }
  
  Future<void> _preloadCategories() async {
    try {
      final categories = await _categoryService?.getCategories();
      debugPrint('📦 [Preload] Categories: ${categories?.length ?? 0} items');
    } catch (e) {
      debugPrint('⚠️ [Preload] Categories failed: $e');
    }
  }
  
  Future<void> _preloadBrands() async {
    try {
      final brands = await _brandService?.getBrands();
      debugPrint('📦 [Preload] Brands: ${brands?.length ?? 0} items');
    } catch (e) {
      debugPrint('⚠️ [Preload] Brands failed: $e');
    }
  }
  
  Future<void> _preloadSalesInvoices() async {
    try {
      await _salesService?.loadInvoices();
      debugPrint('📦 [Preload] Sales Invoices: ${_salesService?.invoices.length ?? 0} items');
    } catch (e) {
      debugPrint('⚠️ [Preload] Sales Invoices failed: $e');
    }
  }
  
  Future<void> _preloadPurchaseInvoices() async {
    try {
      final invoices = await _purchaseService?.getPurchaseInvoices();
      debugPrint('📦 [Preload] Purchase Invoices: ${invoices?.length ?? 0} items');
    } catch (e) {
      debugPrint('⚠️ [Preload] Purchase Invoices failed: $e');
    }
  }
  
  Future<void> _preloadSuppliers() async {
    try {
      final suppliers = await _purchaseService?.getSuppliers();
      debugPrint('📦 [Preload] Suppliers: ${suppliers?.length ?? 0} items');
    } catch (e) {
      debugPrint('⚠️ [Preload] Suppliers failed: $e');
    }
  }
  
  Future<void> _preloadEmployees() async {
    try {
      final employees = await _hrService?.getEmployees();
      debugPrint('📦 [Preload] Employees: ${employees?.length ?? 0} items');
    } catch (e) {
      debugPrint('⚠️ [Preload] Employees failed: $e');
    }
  }
  
  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
