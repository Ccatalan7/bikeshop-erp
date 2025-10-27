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

  /// Get tenant by subdomain from database
  Future<Tenant?> getTenantBySubdomain(String subdomain) async {
    try {
      debugPrint('[TenantDetection] Querying tenant by subdomain: $subdomain');
      
      final response = await _supabase
          .from('tenants')
          .select()
          .eq('subdomain', subdomain)
          .eq('is_active', true)
          .maybeSingle();

      if (response == null) {
        debugPrint('[TenantDetection] No tenant found for subdomain: $subdomain');
        return null;
      }

      final tenant = Tenant.fromJson(response);
      debugPrint('[TenantDetection] Found tenant: ${tenant.shopName} (${tenant.id})');
      return tenant;
    } catch (e) {
      debugPrint('[TenantDetection] Error fetching tenant by subdomain: $e');
      return null;
    }
  }

  /// Get tenant by custom domain from database
  Future<Tenant?> getTenantByCustomDomain(String domain) async {
    try {
      debugPrint('[TenantDetection] Querying tenant by custom domain: $domain');
      
      final response = await _supabase
          .from('tenants')
          .select()
          .eq('custom_domain', domain)
          .eq('is_active', true)
          .maybeSingle();

      if (response == null) {
        debugPrint('[TenantDetection] No tenant found for custom domain: $domain');
        return null;
      }

      final tenant = Tenant.fromJson(response);
      debugPrint('[TenantDetection] Found tenant: ${tenant.shopName} (${tenant.id})');
      return tenant;
    } catch (e) {
      debugPrint('[TenantDetection] Error fetching tenant by custom domain: $e');
      return null;
    }
  }

  /// Detect tenant from current URL
  /// Tries subdomain first, then custom domain lookup
  Future<Tenant?> detectTenant() async {
    if (!kIsWeb) {
      debugPrint('[TenantDetection] Not running on web, skipping detection');
      return null;
    }

    final host = Uri.base.host;
    debugPrint('[TenantDetection] Detecting tenant for host: $host');

    // Try subdomain extraction first
    final subdomain = extractSubdomain(host);
    if (subdomain != null) {
      debugPrint('[TenantDetection] Extracted subdomain: $subdomain');
      final tenant = await getTenantBySubdomain(subdomain);
      if (tenant != null) {
        return tenant;
      }
    }

    // Try custom domain lookup
    final tenant = await getTenantByCustomDomain(host);
    if (tenant != null) {
      return tenant;
    }

    debugPrint('[TenantDetection] No tenant found for host: $host');
    return null;
  }

  /// Check if subdomain is available for registration
  Future<bool> isSubdomainAvailable(String subdomain) async {
    try {
      // Validate format first
      if (!_isValidSubdomain(subdomain)) {
        debugPrint('[TenantDetection] Invalid subdomain format: $subdomain');
        return false;
      }

      // Check reserved subdomains
      final reserved = await _supabase
          .from('reserved_subdomains')
          .select('subdomain')
          .eq('subdomain', subdomain)
          .maybeSingle();

      if (reserved != null) {
        debugPrint('[TenantDetection] Subdomain is reserved: $subdomain');
        return false;
      }

      // Check existing tenants
      final existing = await _supabase
          .from('tenants')
          .select('id')
          .eq('subdomain', subdomain)
          .maybeSingle();

      final isAvailable = existing == null;
      debugPrint('[TenantDetection] Subdomain "$subdomain" available: $isAvailable');
      return isAvailable;
    } catch (e) {
      debugPrint('[TenantDetection] Error checking subdomain availability: $e');
      return false;
    }
  }

  /// Generate subdomain from shop name
  /// Converts to lowercase, replaces spaces with hyphens, removes special chars
  String generateSubdomain(String shopName) {
    return shopName
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-') // Replace non-alphanumeric with dash
        .replaceAll(RegExp(r'^-+|-+$'), '')     // Remove leading/trailing dashes
        .replaceAll(RegExp(r'-+'), '-');        // Replace multiple dashes with single
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
    debugPrint('[TenantDetection] Failed to generate unique subdomain for: $shopName');
    return null;
  }
}
