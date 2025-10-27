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
      debugPrint('[PublicStoreTenantProvider] Starting tenant detection...');
      _currentTenant = await _detectionService.detectTenant();
      
      if (_currentTenant == null) {
        _error = 'No se encontró la tienda. Verifica la URL.';
        debugPrint('[PublicStoreTenantProvider] No tenant detected');
      } else {
        debugPrint('[PublicStoreTenantProvider] Tenant detected: ${_currentTenant!.shopName}');
      }
    } catch (e) {
      _error = 'Error cargando la tienda: $e';
      debugPrint('[PublicStoreTenantProvider] Error detecting tenant: $e');
      _currentTenant = null;
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
    debugPrint('[PublicStoreTenantProvider] Tenant set manually: ${tenant.shopName}');
    notifyListeners();
  }

  /// Clear tenant (e.g., when navigating away from public store)
  void clearTenant() {
    _currentTenant = null;
    _error = null;
    _isLoading = false;
    debugPrint('[PublicStoreTenantProvider] Tenant cleared');
    notifyListeners();
  }

  /// Retry detection (for error recovery)
  Future<void> retry() async {
    debugPrint('[PublicStoreTenantProvider] Retrying tenant detection...');
    await detectTenant();
  }

  @override
  void dispose() {
    debugPrint('[PublicStoreTenantProvider] Disposed');
    super.dispose();
  }
}
