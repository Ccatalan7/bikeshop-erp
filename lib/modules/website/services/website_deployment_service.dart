import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/services/tenant_service.dart';

/// Service to manage website deployment status and configuration
class WebsiteDeploymentService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TenantService _tenantService = TenantService();

  String? _websiteSubdomain;
  String? _websiteUrl;
  String? _websiteStatus; // not_configured, pending, deployed, failed
  DateTime? _deployedAt;
  String? _errorMessage;
  bool _isLoading = false;

  // Getters
  String? get websiteSubdomain => _websiteSubdomain;
  String? get websiteUrl => _websiteUrl;
  String? get websiteStatus => _websiteStatus;
  DateTime? get deployedAt => _deployedAt;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;
  bool get isConfigured => _websiteStatus != null && _websiteStatus != 'not_configured';
  bool get isDeployed => _websiteStatus == 'deployed';
  bool get isPending => _websiteStatus == 'pending';
  bool get hasFailed => _websiteStatus == 'failed';

  /// Load website deployment configuration for current tenant
  Future<void> loadConfiguration() async {
    _isLoading = true;
    notifyListeners();

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Usuario no autenticado');

      // Get tenant_id from user metadata
      final tenantId = _tenantService.currentTenantId;
      if (tenantId == null) throw Exception('No tenant ID found');

      // Load website configuration
      final response = await _supabase
          .from('company_settings')
          .select('*')
          .eq('tenant_id', tenantId)
          .eq('key', 'website_config')
          .maybeSingle();

      if (response != null) {
        _websiteSubdomain = response['website_subdomain'] as String?;
        _websiteUrl = response['website_url'] as String?;
        _websiteStatus = response['website_status'] as String?;
        _errorMessage = response['website_error_message'] as String?;
        
        if (response['website_deployed_at'] != null) {
          _deployedAt = DateTime.parse(response['website_deployed_at'] as String);
        }
      } else {
        // Not configured yet
        _websiteStatus = 'not_configured';
      }
    } catch (e) {
      debugPrint('Error loading website configuration: $e');
      _websiteStatus = 'not_configured';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Check if subdomain is available
  Future<bool> checkSubdomainAvailability(String subdomain) async {
    try {
      final response = await _supabase
          .from('company_settings')
          .select('id')
          .eq('website_subdomain', subdomain)
          .maybeSingle();

      return response == null;
    } catch (e) {
      debugPrint('Error checking subdomain availability: $e');
      return false;
    }
  }

  /// Request website deployment
  /// 
  /// This marks the website as "pending" deployment.
  /// An admin must run the deployment script manually or use Supabase Edge Function.
  Future<void> requestDeployment({
    required String shopName,
    required String subdomain,
    String? description,
    String template = 'modern-store',
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Usuario no autenticado');

      // Get tenant_id from user metadata
      final tenantId = _tenantService.currentTenantId;
      if (tenantId == null) throw Exception('No tenant ID found');

      // Save configuration and mark as pending
      await _supabase.from('company_settings').upsert({
        'tenant_id': tenantId,
        'key': 'website_config',
        'value': shopName,
        'website_subdomain': subdomain,
        'website_status': 'pending',
        'website_enabled': true,
        'website_url': 'https://$subdomain.web.app',
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Save template and description as separate settings
      if (description != null) {
        await _supabase.from('company_settings').upsert({
          'tenant_id': tenantId,
          'key': 'website_description',
          'value': description,
        });
      }

      await _supabase.from('company_settings').upsert({
        'tenant_id': tenantId,
        'key': 'website_template',
        'value': template,
      });

      // Reload configuration
      await loadConfiguration();

      debugPrint('Deployment requested for subdomain: $subdomain');
    } catch (e) {
      debugPrint('Error requesting deployment: $e');
      rethrow;
    }
  }

  /// Update deployment status (called by deployment script or Edge Function)
  Future<void> updateDeploymentStatus({
    required String status,
    String? url,
    String? errorMessage,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Usuario no autenticado');

      final tenantId = _tenantService.currentTenantId;
      if (tenantId == null) throw Exception('No tenant ID found');

      final updateData = <String, dynamic>{
        'website_status': status,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (url != null) {
        updateData['website_url'] = url;
      }

      if (status == 'deployed') {
        updateData['website_deployed_at'] = DateTime.now().toIso8601String();
      }

      if (errorMessage != null) {
        updateData['website_error_message'] = errorMessage;
      }

      await _supabase
          .from('company_settings')
          .update(updateData)
          .eq('tenant_id', tenantId)
          .eq('key', 'website_config');

      await loadConfiguration();
    } catch (e) {
      debugPrint('Error updating deployment status: $e');
      rethrow;
    }
  }

  /// Cancel pending deployment
  Future<void> cancelDeployment() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Usuario no autenticado');

      final tenantId = _tenantService.currentTenantId;
      if (tenantId == null) throw Exception('No tenant ID found');

      await _supabase
          .from('company_settings')
          .update({
            'website_status': 'not_configured',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('tenant_id', tenantId)
          .eq('key', 'website_config');

      await loadConfiguration();
    } catch (e) {
      debugPrint('Error canceling deployment: $e');
      rethrow;
    }
  }

  /// Get deployment instructions for admin
  String getDeploymentInstructions() {
    if (_websiteSubdomain == null) {
      return 'No hay configuración de sitio web';
    }

    return '''
Para desplegar este sitio web, ejecuta:

PowerShell (Windows):
.\\scripts\\deploy_tenant_website.ps1 -TenantId "{TENANT_ID}"

Node.js (Cross-platform):
node scripts/deploy_tenant_website.js {TENANT_ID}

Subdominio: $_websiteSubdomain
URL final: https://$_websiteSubdomain.web.app
''';
  }
}
