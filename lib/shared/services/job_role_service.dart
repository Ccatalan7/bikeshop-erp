import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/job_role.dart';
import '../services/database_service.dart';

class JobRoleService extends ChangeNotifier {
  final DatabaseService _db;
  final SupabaseClient _client = Supabase.instance.client;

  JobRoleService(this._db);

  // Get all job roles for current tenant
  Future<List<JobRole>> getJobRoles({bool activeOnly = true}) async {
    try {
      final data = await _db.select('job_roles', orderBy: 'sort_order');
      
      List<JobRole> roles = data.map((json) => JobRole.fromJson(json)).toList();
      
      if (activeOnly) {
        roles = roles.where((r) => r.isActive).toList();
      }
      
      return roles;
    } catch (e) {
      if (kDebugMode) print('❌ Error fetching job roles: $e');
      rethrow;
    }
  }

  // Get single job role by system_role code
  Future<JobRole?> getJobRoleByCode(String systemRole) async {
    try {
      final tenantId = await _getTenantId();
      if (tenantId == null) return null;
      
      final data = await _client
          .from('job_roles')
          .select()
          .eq('tenant_id', tenantId)
          .eq('system_role', systemRole)
          .maybeSingle();
      
      if (data == null) return null;
      return JobRole.fromJson(data);
    } catch (e) {
      if (kDebugMode) print('❌ Error fetching job role $systemRole: $e');
      return null;
    }
  }

  // Get suggested job titles for a role
  Future<List<String>> getSuggestedTitles(String systemRole) async {
    try {
      final role = await getJobRoleByCode(systemRole);
      return role?.suggestedTitles ?? [];
    } catch (e) {
      if (kDebugMode) print('❌ Error fetching suggested titles: $e');
      return [];
    }
  }

  // Get default permissions for a role
  Future<Map<String, dynamic>> getDefaultPermissions(String systemRole) async {
    try {
      final role = await getJobRoleByCode(systemRole);
      return role?.defaultPermissions ?? {};
    } catch (e) {
      if (kDebugMode) print('❌ Error fetching default permissions: $e');
      return {};
    }
  }

  // Get role options for dropdown (active roles only)
  Future<List<Map<String, String>>> getRoleOptions() async {
    try {
      final roles = await getJobRoles(activeOnly: true);
      return roles
          .map((r) => {
        'code': r.systemRole,
        'name': r.displayName,
              })
          .toList();
    } catch (e) {
      if (kDebugMode) print('❌ Error fetching role options: $e');
      return [];
    }
  }

  // Update job role (admin only)
  Future<void> updateJobRole(
      String systemRole, Map<String, dynamic> updates) async {
    try {
      final tenantId = await _getTenantId();
      if (tenantId == null) throw Exception('Tenant ID not found');

      await _client
          .from('job_roles')
          .update(updates)
          .eq('tenant_id', tenantId)
          .eq('system_role', systemRole);

      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('❌ Error updating job role: $e');
      rethrow;
    }
  }

  // Get tenant_id from current user
  Future<String?> _getTenantId() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return null;

      final profile = await _client
          .from('user_profiles')
          .select('tenant_id')
          .eq('user_id', userId)
          .maybeSingle();

      return profile?['tenant_id'];
    } catch (e) {
      if (kDebugMode) print('❌ Error getting tenant_id: $e');
      return null;
    }
  }
}
