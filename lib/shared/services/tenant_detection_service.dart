import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/tenant.dart';

/// Service for detecting tenant from URL and managing tenant operations
/// Supports both subdomain-based and custom domain routing
class TenantDetectionService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Main domain patterns for subdomain extraction
  /// Works with ANY hosting provider (Firebase, Vercel, Netlify, custom domains, etc.)
  /// Add your production domain here when deploying
  static const List<String> mainDomains = [
    // Production domain (add your domain here)
    'bikeshop-erp.app',

    // Vercel preview/production domains
    'bikeshop-erp.vercel.app',

    // Firebase Hosting domains
    'project-vinabike.web.app',
    'project-vinabike.firebaseapp.com',
    'vinabike-store.web.app',
    'vinabike-store.firebaseapp.com',

    // Netlify domains (if using Netlify)
    'bikeshop-erp.netlify.app',

    // Development
    'localhost',
    '127.0.0.1',
  ];

  /// PERFORMANCE OPTIMIZATION: Hardcoded tenant IDs for known production domains
  /// This skips the DB query entirely for domains we control, saving ~674ms
  /// Add your production domains here when deploying to new tenants
  static const Map<String, String> _knownDomainTenants = {
    'vinabike.cl': '5443b130-cc28-45af-a420-cd500b288890',
    'www.vinabike.cl': '5443b130-cc28-45af-a420-cd500b288890',
    'vinabike-store.web.app': '5443b130-cc28-45af-a420-cd500b288890',
    'vinabike-store.firebaseapp.com': '5443b130-cc28-45af-a420-cd500b288890',
    // Local debugging (User's Phone)
    '192.168.12.169': '5443b130-cc28-45af-a420-cd500b288890',
  };

  /// Extract subdomain from current URL
  ///
  /// Examples:
  ///   vinabike.bikeshop-erp.app → "vinabike"
  ///   joesbikes.bikeshop-erp.app → "joesbikes"
  ///   bikeshop-erp.app → null (main domain, no subdomain)
  ///   localhost:8080 → null (development, no subdomain)
  String? extractSubdomain(String host) {
    if (!kIsWeb) return null;

    // Remove port if present
    final cleanHost = host.split(':').first.toLowerCase();

    // Check each main domain pattern
    for (final mainDomain in mainDomains) {
      // Exact match = no subdomain
      if (cleanHost == mainDomain) {
        return null;
      }

      // Check if this is a subdomain of the main domain
      if (cleanHost.endsWith('.$mainDomain')) {
        // Extract subdomain part
        final subdomain = cleanHost.substring(
          0,
          cleanHost.length - mainDomain.length - 1,
        );

        // Validate subdomain format
        if (_isValidSubdomain(subdomain)) {
          return subdomain;
        }
      }
    }

    // Not a recognized subdomain pattern
    return null;
  }

  /// Validate subdomain format (lowercase alphanumeric and hyphens)
  bool _isValidSubdomain(String subdomain) {
    final regex = RegExp(r'^[a-z0-9][a-z0-9-]*[a-z0-9]$');
    return regex.hasMatch(subdomain) && subdomain.length >= 2;
  }

  /// OPTIMIZED: Get tenant by subdomain OR custom domain in a single query
  Future<Tenant?> _getTenantBySubdomainOrDomain(
      String? subdomain, String domain) async {
    final sw = Stopwatch()..start();
    try {
      // Use OR filter to check both in one query
      var query = _supabase.from('tenants').select().eq('is_active', true);

      if (subdomain != null && subdomain.isNotEmpty) {
        query = query.or('subdomain.eq.$subdomain,custom_domain.eq.$domain');
      } else {
        // If subdomain is null, only check custom_domain
        query = query.eq('custom_domain', domain);
      }

      final response = await query.maybeSingle();
      debugPrint(
          '⏱️ [TenantDetection] DB query took: ${sw.elapsedMilliseconds}ms');

      if (response == null) {
        return null;
      }

      return Tenant.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  /// Get tenant by subdomain from database
  Future<Tenant?> getTenantBySubdomain(String subdomain) async {
    try {
      final response = await _supabase
          .from('tenants')
          .select()
          .eq('subdomain', subdomain)
          .eq('is_active', true)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return Tenant.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  /// Get tenant by custom domain from database
  Future<Tenant?> getTenantByCustomDomain(String domain) async {
    try {
      final response = await _supabase
          .from('tenants')
          .select()
          .eq('custom_domain', domain)
          .eq('is_active', true)
          .maybeSingle();

      if (response == null) {
        return null;
      }

      return Tenant.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  /// Detect tenant from current URL
  /// Tries subdomain first, then custom domain lookup, then authenticated user's tenant
  Future<Tenant?> detectTenant() async {
    // For non-web platforms (macOS, Windows, iOS, Android)
    if (!kIsWeb) {
      // First try authenticated user's tenant
      final user = _supabase.auth.currentUser;
      if (user != null) {
        final tenantFromAuth = await _getTenantFromAuthenticatedUser(user.id);
        if (tenantFromAuth != null) {
          debugPrint('📱 [TenantDetection] Using authenticated user tenant');
          return tenantFromAuth;
        }
      }

      // For public store mobile app, default to Viñabike tenant
      // This allows the store to work without authentication
      const defaultTenantId =
          '5443b130-cc28-45af-a420-cd500b288890'; // Viñabike
      debugPrint('📱 [TenantDetection] Using default mobile tenant (Viñabike)');
      return Tenant(
        id: defaultTenantId,
        shopName: 'Vinabike',
        subdomain: 'vinabike',
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }

    final host = Uri.base.host;
    final normalizedHost = host.toLowerCase();
    final hostWithoutWww = normalizedHost.startsWith('www.')
        ? normalizedHost.substring(4)
        : normalizedHost;

    // Development: Check for FORCE_SUBDOMAIN environment variable
    const forceSubdomain = String.fromEnvironment('FORCE_SUBDOMAIN');
    if (forceSubdomain.isNotEmpty) {
      final tenant = await getTenantBySubdomain(forceSubdomain);
      if (tenant != null) {
        return tenant;
      }
    }

    // PERFORMANCE OPTIMIZATION: Check hardcoded known domains FIRST
    // This skips the DB query entirely for production domains, saving ~674ms
    final knownTenantId = _knownDomainTenants[normalizedHost];
    if (knownTenantId != null) {
      debugPrint(
          '⚡ [TenantDetection] Using hardcoded tenant for $normalizedHost');
      // Return a minimal Tenant object with just the ID - that's all we need
      return Tenant(
        id: knownTenantId,
        shopName: 'Vinabike', // Default, actual name loaded from settings
        subdomain: 'vinabike',
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }

    // WILDCARD OPTIMIZATION: Check for Firebase Preview Channels
    // matches: vinabike-store--mobile-test-i0dyo35h.web.app
    if (normalizedHost.startsWith('vinabike-store--') &&
        normalizedHost.endsWith('.web.app')) {
      debugPrint(
          '⚡ [TenantDetection] Using hardcoded tenant for PREVIEW CHANNEL');
      return Tenant(
        id: '5443b130-cc28-45af-a420-cd500b288890',
        shopName: 'Vinabike',
        subdomain: 'vinabike',
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }

    // OPTIMIZED: Single query that checks BOTH subdomain AND custom_domain
    // This reduces 2 DB calls to 1 for most cases
    String? subdomain;

    // Special handling for Firebase Hosting site-specific domains AND Preview Channels
    // matches: vinabike-store.web.app, project-vinabike--mobile-test.web.app, etc.
    if (host.contains('vinabike') &&
        (host.endsWith('.web.app') || host.endsWith('.firebaseapp.com'))) {
      subdomain = 'vinabike';
    } else {
      subdomain = extractSubdomain(hostWithoutWww);
    }

    // Single optimized query: check subdomain OR custom_domain in one call
    final tenant =
        await _getTenantBySubdomainOrDomain(subdomain, hostWithoutWww);
    if (tenant != null) {
      if (!kReleaseMode) {
        debugPrint(
            '🔍 Auto-detected tenant: ${tenant.shopName} (${tenant.id})');
      }
      return tenant;
    }

    // FALLBACK: On localhost/ERP domain, use authenticated user's tenant
    final isLocalOrErpDomain = hostWithoutWww.contains('localhost') ||
        hostWithoutWww.contains('127.0.0.1') ||
        hostWithoutWww == 'project-vinabike.web.app' ||
        hostWithoutWww == 'project-vinabike.firebaseapp.com';

    if (isLocalOrErpDomain) {
      final user = _supabase.auth.currentUser;
      if (user != null) {
        final tenantFromAuth = await _getTenantFromAuthenticatedUser(user.id);
        if (tenantFromAuth != null) {
          return tenantFromAuth;
        }
      }
    }

    return null;
  }

  /// Get tenant from authenticated user's profile
  Future<Tenant?> _getTenantFromAuthenticatedUser(String userId) async {
    try {
      // First get the user's tenant_id from user_profiles
      final profileResponse = await _supabase
          .from('user_profiles')
          .select('tenant_id')
          .eq('user_id', userId)
          .maybeSingle();

      if (profileResponse == null || profileResponse['tenant_id'] == null) {
        return null;
      }

      final tenantId = profileResponse['tenant_id'] as String;

      // Now fetch the full tenant record
      final tenantResponse = await _supabase
          .from('tenants')
          .select()
          .eq('id', tenantId)
          .eq('is_active', true)
          .maybeSingle();

      if (tenantResponse == null) {
        return null;
      }

      return Tenant.fromJson(tenantResponse);
    } catch (e) {
      return null;
    }
  }

  /// Check if subdomain is available for registration
  Future<bool> isSubdomainAvailable(String subdomain) async {
    try {
      // Validate format first
      if (!_isValidSubdomain(subdomain)) {
        return false;
      }

      // Check reserved subdomains
      final reserved = await _supabase
          .from('reserved_subdomains')
          .select('subdomain')
          .eq('subdomain', subdomain)
          .maybeSingle();

      if (reserved != null) {
        return false;
      }

      // Check existing tenants
      final existing = await _supabase
          .from('tenants')
          .select('id')
          .eq('subdomain', subdomain)
          .maybeSingle();

      return existing == null;
    } catch (e) {
      return false;
    }
  }

  /// Generate subdomain from shop name
  /// Converts to lowercase, replaces spaces with hyphens, removes special chars
  String generateSubdomain(String shopName) {
    return shopName
        .toLowerCase()
        .trim()
        .replaceAll(
            RegExp(r'[^a-z0-9]+'), '-') // Replace non-alphanumeric with dash
        .replaceAll(RegExp(r'^-+|-+$'), '') // Remove leading/trailing dashes
        .replaceAll(RegExp(r'-+'), '-'); // Replace multiple dashes with single
  }

  /// Generate unique subdomain with fallback numbers
  Future<String?> generateUniqueSubdomain(String shopName) async {
    String baseSubdomain = generateSubdomain(shopName);

    // Try base subdomain first
    if (await isSubdomainAvailable(baseSubdomain)) {
      return baseSubdomain;
    }

    // Try with numbers 1-99
    for (int i = 1; i <= 99; i++) {
      final candidate = '$baseSubdomain-$i';
      if (await isSubdomainAvailable(candidate)) {
        return candidate;
      }
    }

    // Failed to find unique subdomain
    debugPrint(
        '[TenantDetection] Failed to generate unique subdomain for: $shopName');
    return null;
  }
}
