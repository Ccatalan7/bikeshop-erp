import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service for managing multi-tenant operations
///
/// Handles tenant context and provides utilities for:
/// - Getting current user's tenant_id
/// - Fetching tenant details
/// - Tenant-aware data operations
///
/// NOTE: This is a SINGLETON to ensure cache is shared across all callers.
class TenantService extends ChangeNotifier {
  // Singleton pattern
  static final TenantService _instance = TenantService._internal();
  factory TenantService() => _instance;
  TenantService._internal()
      : _supabase = Supabase.instance.client,
        _currentUserIdOverride = null,
        _profileLookupOverride = null;

  @visibleForTesting
  TenantService.testing({
    required String? Function() currentUserId,
    required Future<List<Map<String, dynamic>>> Function(String userId)
        profileLookup,
  })  : _supabase = null,
        _currentUserIdOverride = currentUserId,
        _profileLookupOverride = profileLookup;

  final SupabaseClient? _supabase;
  final String? Function()? _currentUserIdOverride;
  final Future<List<Map<String, dynamic>>> Function(String userId)?
      _profileLookupOverride;

  // Public Store mobile optimization: when enabled (via dart-define), skip any
  // auth-based tenant lookup. Store mode should use TenantDetectionService.
  static const bool _ignoreAuthForPublicStore =
      bool.fromEnvironment('PUBLIC_STORE_IGNORE_AUTH');

  // Cache for tenant_id to avoid repeated database queries
  String? _cachedTenantId;
  String? _cachedUserId;
  String? _cachedUserRole;
  Map<String, dynamic>? _cachedUserPermissions;

  // Pending requests are owned by one user/session generation. A lookup from a
  // prior auth scope can finish, but it cannot be reused by or write into the
  // next scope.
  Future<String?>? _pendingQuery;
  String? _pendingQueryUserId;
  int? _pendingQueryGeneration;
  int _resolutionGeneration = 0;

  String? get _currentUserId =>
      _currentUserIdOverride?.call() ?? _supabase?.auth.currentUser?.id;

  /// Current auth user id (or null when signed out). Exposed for capability
  /// fingerprints that must bind a cached authorization to the exact
  /// identity that produced it.
  String? get currentAuthUserId => _currentUserId;

  /// Get the current user's tenant_id from user_profiles table
  /// This is the single source of truth for tenant_id
  ///
  /// OPTIMIZED: Uses caching to prevent multiple database queries
  Future<String?> getTenantId() async {
    if (_ignoreAuthForPublicStore) {
      if (!kReleaseMode) {
        debugPrint(
            '🏪 [TenantService] PUBLIC_STORE_IGNORE_AUTH enabled; skipping user_profiles lookup');
      }
      return null;
    }

    final userId = _currentUserId;
    if (userId == null) {
      if (_pendingQuery != null) {
        _invalidatePendingResolution();
      }
      return null;
    }

    // FAST PATH: Return cached value immediately if same user
    // We check _cachedUserId to ensure we have a result (even if null) for this user
    if (_cachedUserId == userId) {
      return _cachedTenantId;
    }

    // Only callers from the exact same user and generation may share work.
    final pending = _pendingQuery;
    if (pending != null &&
        _pendingQueryUserId == userId &&
        _pendingQueryGeneration == _resolutionGeneration) {
      return pending;
    }

    final generation = ++_resolutionGeneration;
    final query = _fetchTenantId(userId, generation);
    _pendingQuery = query;
    _pendingQueryUserId = userId;
    _pendingQueryGeneration = generation;

    try {
      return await query;
    } finally {
      if (_pendingQueryGeneration == generation) {
        _pendingQuery = null;
        _pendingQueryUserId = null;
        _pendingQueryGeneration = null;
      }
    }
  }

  /// Internal method to fetch tenant_id from database
  Future<String?> _fetchTenantId(String userId, int generation) async {
    try {
      if (!kReleaseMode) {
        debugPrint('[TenantService] Querying user_profiles...');
      }
      final profileLookup = _profileLookupOverride;
      final profiles = profileLookup != null
          ? await profileLookup(userId)
          : List<Map<String, dynamic>>.from(
              await _supabase!
                  .from('user_profiles')
                  .select('tenant_id, role, permissions')
                  .eq('user_id', userId)
                  .eq('is_active', true)
                  .limit(2),
            );

      if (!_canApplyResolution(userId, generation)) return null;
      if (profiles.length != 1) {
        if (!kReleaseMode) {
          debugPrint(
            '[TenantService] Active profile resolution failed closed',
          );
        }
        _cachedTenantId = null;
        _cachedUserRole = null;
        _cachedUserPermissions = null;
        _cachedUserId = userId;
        return null;
      }

      final profile = profiles.single;
      var tid = profile['tenant_id'] as String?;
      if (tid != null && tid.isEmpty) tid = null;

      _cachedTenantId = tid;
      _cachedUserRole = profile['role'] as String?;
      final permissions = profile['permissions'];
      _cachedUserPermissions = permissions is Map
          ? Map<String, dynamic>.unmodifiable(
              Map<String, dynamic>.from(permissions),
            )
          : null;
      _cachedUserId = userId;
      if (!kReleaseMode) {
        debugPrint('[TenantService] Got tenant_id: $_cachedTenantId');
      }
      return _cachedTenantId;
    } catch (e) {
      if (!kReleaseMode) {
        debugPrint('❌ Error getting tenant_id: $e');
      }
      return null;
    }
  }

  bool _canApplyResolution(String userId, int generation) {
    return generation == _resolutionGeneration && _currentUserId == userId;
  }

  void _invalidatePendingResolution() {
    _resolutionGeneration++;
    _pendingQuery = null;
    _pendingQueryUserId = null;
    _pendingQueryGeneration = null;
  }

  /// Clear the cached tenant_id (call on logout)
  void clearCache() {
    _invalidatePendingResolution();
    _cachedTenantId = null;
    _cachedUserId = null;
    _cachedUserRole = null;
    _cachedUserPermissions = null;
  }

  /// True when the profile cache holds a RESULT (even "no tenant") for the
  /// current auth user. A transient lookup failure never stamps the cache,
  /// so capability consumers can distinguish a durable denial (resolved,
  /// no authority) from an unresolved transient failure that must suspend
  /// and retry instead of denying.
  bool get hasResolvedProfileForCurrentUser {
    final userId = _currentUserId;
    return userId != null && _cachedUserId == userId;
  }

  /// Get the current user's tenant_id (synchronous - from cache)
  /// For immediate use, but may be null if not cached
  /// Prefer using getTenantId() for reliable results
  String? get currentTenantId {
    final userId = _currentUserId;
    if (userId == null) return null;
    if (_cachedUserId != userId) return null;
    return _cachedTenantId;
  }

  /// Get the current user's role
  String? get currentUserRole {
    final userId = _currentUserId;
    if (userId == null) return null;
    if (_cachedUserId != userId) return null;
    return _cachedUserRole;
  }

  /// Get the current user's permissions
  Map<String, dynamic>? get currentUserPermissions {
    final userId = _currentUserId;
    if (userId == null) return null;
    if (_cachedUserId != userId) return null;
    return _cachedUserPermissions;
  }

  /// Check if current user has a specific role
  bool hasRole(String role) {
    return currentUserRole == role;
  }

  /// Check if current user has any of the given roles
  bool hasAnyRole(List<String> roles) {
    final userRole = currentUserRole;
    if (userRole == null) return false;
    return roles.contains(userRole);
  }

  /// Check if current user has a specific permission
  bool hasPermission(String permissionKey) {
    final permissions = currentUserPermissions;
    if (permissions == null) return false;
    return permissions[permissionKey] == true;
  }

  /// Convenience: Check if user is a manager
  bool get isManager => hasRole('manager');

  /// Convenience: Check if user is a cashier
  bool get isCashier => hasRole('cashier');

  /// Convenience: Check if user is a mechanic
  bool get isMechanic => hasRole('mechanic');

  /// Convenience: Check if user is an accountant
  bool get isAccountant => hasRole('accountant');

  /// Fetch current tenant details
  Future<Map<String, dynamic>?> getCurrentTenant() async {
    final tenantId = await getTenantId(); // ✅ Use async version
    if (tenantId == null) {
      debugPrint('❌ No tenant_id found for current user');
      return null;
    }

    try {
      debugPrint('🔍 Fetching tenant with id: $tenantId');
      final response = await _supabase!
          .from('tenants')
          .select()
          .eq('id', tenantId)
          .eq('is_active', true)
          .maybeSingle(); // ✅ Use maybeSingle() instead of single() - returns null if not found

      if (response == null) {
        debugPrint('⚠️ No tenant found with id: $tenantId');
        debugPrint(
            '⚠️ This user may need to create a tenant or be assigned to one');
        return null;
      }

      debugPrint(
          '✅ Loaded tenant: ${response['shop_name']} (${response['subdomain']})');
      return response;
    } catch (e) {
      debugPrint('❌ Error fetching tenant: $e');
      return null;
    }
  }

  /// Ensure user has a tenant_id (throws if not)
  void ensureTenantId() {
    if (currentTenantId == null) {
      throw Exception('User does not have a tenant_id. Cannot proceed.');
    }
  }

  /// Add tenant_id to a data map for inserts/updates
  Map<String, dynamic> addTenantId(Map<String, dynamic> data) {
    ensureTenantId();
    data['tenant_id'] = currentTenantId;
    return data;
  }

  /// Subscribe to auth state changes and notify listeners
  /// IMPORTANT: This is guarded to prevent duplicate subscriptions on the singleton
  bool _isInitialized = false;
  StreamSubscription<AuthState>? _authSubscription;

  void initialize() {
    if (_isInitialized) return; // Prevent duplicate subscriptions
    _isInitialized = true;

    final supabase = _supabase;
    if (supabase == null) return;
    _authSubscription = supabase.auth.onAuthStateChange.listen((event) {
      if (event.event == AuthChangeEvent.signedIn ||
          event.event == AuthChangeEvent.signedOut ||
          event.event == AuthChangeEvent.userUpdated) {
        // Clear cache on auth state changes so we re-fetch for new user
        clearCache();
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _invalidatePendingResolution();
    _authSubscription?.cancel();
    super.dispose();
  }
}
