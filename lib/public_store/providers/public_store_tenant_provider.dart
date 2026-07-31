import 'package:flutter/foundation.dart';
import '../../shared/models/tenant.dart';
import '../../shared/services/tenant_detection_service.dart';

enum PublicStoreTenantScopeSource {
  detected,
  manual,
  authenticatedErp,
}

/// One storefront identity with an explicit authority source.
///
/// A public host owns a fully hydrated [Tenant] discovered from its URL. The
/// ERP-mounted storefront instead projects the authenticated tenant ID; it
/// must not fabricate the remaining [Tenant] fields merely to satisfy callers
/// that only need tenant-scoped publication data.
@immutable
class PublicStoreTenantScope {
  const PublicStoreTenantScope._({
    required this.source,
    required this.tenantId,
    this.tenant,
  });

  factory PublicStoreTenantScope.detected(Tenant tenant) {
    return PublicStoreTenantScope._(
      source: PublicStoreTenantScopeSource.detected,
      tenantId: tenant.id,
      tenant: tenant,
    );
  }

  factory PublicStoreTenantScope.manual(Tenant tenant) {
    return PublicStoreTenantScope._(
      source: PublicStoreTenantScopeSource.manual,
      tenantId: tenant.id,
      tenant: tenant,
    );
  }

  factory PublicStoreTenantScope.authenticatedErp(
    String tenantId, {
    Tenant? hydratedTenant,
  }) {
    assert(
      hydratedTenant == null || hydratedTenant.id == tenantId,
      'Hydrated tenant must match the authenticated ERP scope.',
    );
    return PublicStoreTenantScope._(
      source: PublicStoreTenantScopeSource.authenticatedErp,
      tenantId: tenantId,
      tenant: hydratedTenant,
    );
  }

  final PublicStoreTenantScopeSource source;
  final String tenantId;
  final Tenant? tenant;

  bool get isHydrated => tenant != null;
}

/// Owns the single tenant scope consumed by the public-store surface.
///
/// Anonymous public hosts establish the scope through URL detection. The
/// authenticated ERP shell projects its own tenant authority explicitly.
class PublicStoreTenantProvider extends ChangeNotifier {
  final TenantDetectionService _detectionService;

  PublicStoreTenantScope? _scope;
  bool _isLoading = false;
  String? _error;
  int _scopeGeneration = 0;

  PublicStoreTenantProvider(this._detectionService);

  // Getters
  PublicStoreTenantScope? get scope => _scope;
  PublicStoreTenantScopeSource? get scopeSource => _scope?.source;
  Tenant? get currentTenant => _scope?.tenant;
  bool get isLoading => _isLoading;
  String? get error => _error;
  // Preserve the historical contract: callers using `hasTenant` expect the
  // complete public-host Tenant model, not merely a tenant-scoped authority.
  bool get hasTenant => _scope?.isHydrated ?? false;
  bool get hasTenantScope => _scope != null;
  bool get hasHydratedTenant => _scope?.isHydrated ?? false;
  bool get isErpProjected =>
      _scope?.source == PublicStoreTenantScopeSource.authenticatedErp;
  bool get hasError =>
      _error != null && !_isLoading; // Error state (not loading, has error)
  String? get tenantId => _scope?.tenantId;
  String? get shopName => _scope?.tenant?.shopName;
  String? get subdomain => _scope?.tenant?.subdomain;
  String? get logoUrl => _scope?.tenant?.logoUrl;
  String? get currency => _scope?.tenant?.currency;

  /// Detect tenant from current URL
  /// Call this once when the public store loads
  Future<void> detectTenant() async {
    if (_isLoading) return; // Prevent duplicate detection
    final currentSource = _scope?.source;
    if (currentSource == PublicStoreTenantScopeSource.manual ||
        currentSource == PublicStoreTenantScopeSource.authenticatedErp) {
      return;
    }

    final requestGeneration = ++_scopeGeneration;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final detectedTenant = await _detectionService.detectTenant();
      if (requestGeneration != _scopeGeneration) return;

      if (detectedTenant == null) {
        _scope = null;
        _error = 'No se encontró la tienda. Verifica la URL.';
        if (!kReleaseMode) {
          debugPrint('🏪 [TenantProvider] ❌ No tenant detected');
        }
      } else {
        _scope = PublicStoreTenantScope.detected(detectedTenant);
        if (!kReleaseMode) {
          debugPrint(
            '🏪 [TenantProvider] ✅ Detected: ${detectedTenant.shopName}',
          );
        }
      }
    } catch (e) {
      if (requestGeneration != _scopeGeneration) return;
      _error = 'Error cargando la tienda: $e';
      _scope = null;
      if (!kReleaseMode) {
        debugPrint('🏪 [TenantProvider] ❌ Error: $e');
      }
    } finally {
      if (requestGeneration == _scopeGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Set tenant manually (useful for testing or admin preview)
  void setTenant(Tenant tenant) {
    _scopeGeneration++;
    _scope = PublicStoreTenantScope.manual(tenant);
    _error = null;
    _isLoading = false;
    notifyListeners();
  }

  /// Projects the authenticated tenant into the ERP-mounted storefront.
  ///
  /// This command is called only by the ERP shell, where authenticated tenancy
  /// is authoritative and URL/manual detection has no storefront-host meaning.
  /// Repeating the same authenticated projection is a notification no-op.
  bool projectAuthenticatedTenantForStorefront(String tenantId) {
    final normalized = tenantId.trim();
    if (normalized.isEmpty) return false;

    final currentScope = _scope;
    if (currentScope?.source == PublicStoreTenantScopeSource.authenticatedErp &&
        currentScope?.tenantId == normalized) {
      return false;
    }

    final matchingHydratedTenant =
        currentScope?.tenantId == normalized ? currentScope?.tenant : null;
    _scopeGeneration++;
    _scope = PublicStoreTenantScope.authenticatedErp(
      normalized,
      hydratedTenant: matchingHydratedTenant,
    );
    _error = null;
    _isLoading = false;
    notifyListeners();
    return true;
  }

  bool matchesAuthenticatedTenantScope(String tenantId) {
    final normalized = tenantId.trim();
    return normalized.isNotEmpty &&
        _scope?.source == PublicStoreTenantScopeSource.authenticatedErp &&
        _scope?.tenantId == normalized;
  }

  /// Clear tenant (e.g., when navigating away from public store)
  void clearTenant() {
    _scopeGeneration++;
    _scope = null;
    _error = null;
    _isLoading = false;
    notifyListeners();
  }

  /// Retry detection (for error recovery)
  Future<void> retry() async {
    await detectTenant();
  }
}
