import 'package:flutter/foundation.dart';
import '../../shared/models/tenant.dart';
import '../../shared/services/tenant_detection_service.dart';

/// Manages the detected tenant for the public store
/// This is separate from the authenticated user's tenant (used in admin/ERP)
/// 
/// Public store visitors are anonymous and don't have a logged-in tenant
/// Instead, we detect which store they're viewing from the URL subdomain
class PublicStoreTenantProvider extends ChangeNotifier {
  final TenantDetectionService _detectionService;

  Tenant? _currentTenant;
  bool _isLoading = false;
  String? _error;

  PublicStoreTenantProvider(this._detectionService);

  // Getters
  Tenant? get currentTenant => _currentTenant;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasTenant => _currentTenant != null;
  bool get hasError => _error != null && !_isLoading; // Error state (not loading, has error)
  String? get tenantId => _currentTenant?.id;
  String? get shopName => _currentTenant?.shopName;
  String? get subdomain => _currentTenant?.subdomain;
  String? get logoUrl => _currentTenant?.logoUrl;
  String? get currency => _currentTenant?.currency;

  /// Detect tenant from current URL
  /// Call this once when the public store loads
  Future<void> detectTenant() async {
    if (_isLoading) return; // Prevent duplicate detection
    
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _currentTenant = await _detectionService.detectTenant();
      
      if (_currentTenant == null) {
        _error = 'No se encontró la tienda. Verifica la URL.';
        if (!kReleaseMode) {
          debugPrint('🏪 [TenantProvider] ❌ No tenant detected');
        }
      } else if (!kReleaseMode) {
        debugPrint('🏪 [TenantProvider] ✅ Detected: ${_currentTenant!.shopName}');
      }
    } catch (e) {
      _error = 'Error cargando la tienda: $e';
      _currentTenant = null;
      if (!kReleaseMode) {
        debugPrint('🏪 [TenantProvider] ❌ Error: $e');
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Set tenant manually (useful for testing or admin preview)
  void setTenant(Tenant tenant) {
    _currentTenant = tenant;
    _error = null;
    _isLoading = false;
    notifyListeners();
  }

  /// Clear tenant (e.g., when navigating away from public store)
  void clearTenant() {
    _currentTenant = null;
    _error = null;
    _isLoading = false;
    notifyListeners();
  }

  /// Retry detection (for error recovery)
  Future<void> retry() async {
    await detectTenant();
  }

  @override
  void dispose() {
    super.dispose();
  }
}
