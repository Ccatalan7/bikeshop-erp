import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class ErpChatPrincipalDirectoryGateway {
  String? get currentUserId;

  Future<Object?> getDirectory();
}

class SupabaseErpChatPrincipalDirectoryGateway
    implements ErpChatPrincipalDirectoryGateway {
  SupabaseErpChatPrincipalDirectoryGateway([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<Object?> getDirectory() {
    return _client.rpc('get_erp_chat_principal_directory');
  }
}

@immutable
class ErpChatPrincipalDirectoryEntry {
  const ErpChatPrincipalDirectoryEntry({
    required this.tenantId,
    required this.userId,
    required this.employeeId,
    required this.displayName,
    required this.role,
    required this.photoUrl,
  });

  final String tenantId;
  final String userId;
  final String? employeeId;
  final String displayName;
  final String role;
  final String? photoUrl;

  String get initials {
    final words = displayName
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.single[0].toUpperCase();
    return '${words.first[0]}${words.last[0]}'.toUpperCase();
  }
}

/// Minimal tenant-scoped directory of active ERP chat principals.
///
/// This projection intentionally remains separate from the employee directory:
/// an ERP owner may be a valid chat principal without owning an employee row.
class ErpChatPrincipalDirectoryService {
  ErpChatPrincipalDirectoryService({
    ErpChatPrincipalDirectoryGateway? gateway,
  }) : _gateway = gateway ?? SupabaseErpChatPrincipalDirectoryGateway();

  final ErpChatPrincipalDirectoryGateway _gateway;

  static const _roles = {
    'admin',
    'manager',
    'cashier',
    'mechanic',
    'accountant',
  };

  Future<List<ErpChatPrincipalDirectoryEntry>> getEntries({
    required String authorityTenantId,
  }) async {
    final tenantId = _normalized(authorityTenantId);
    final currentUserId = _normalized(_gateway.currentUserId);
    if (tenantId == null || currentUserId == null) {
      throw StateError('An active ERP user and tenant authority are required');
    }

    final response = await _gateway.getDirectory();
    if (response is! List) {
      throw const FormatException('Invalid ERP chat directory response');
    }

    final userIds = <String>{};
    final entries = <ErpChatPrincipalDirectoryEntry>[];
    for (final rawRow in response) {
      if (rawRow is! Map) {
        throw const FormatException('Invalid ERP chat directory row');
      }
      final row = Map<String, dynamic>.from(rawRow);
      const expectedKeys = {
        'tenant_id',
        'user_id',
        'employee_id',
        'display_name',
        'role',
        'photo_url',
      };
      if (!setEquals(row.keys.toSet(), expectedKeys)) {
        throw const FormatException('Unexpected ERP chat directory row shape');
      }

      final rowTenantId = _requiredString(row, 'tenant_id');
      final userId = _requiredString(row, 'user_id');
      final displayName = _requiredString(row, 'display_name');
      final role = _requiredString(row, 'role').toLowerCase();
      if (rowTenantId != tenantId ||
          !_roles.contains(role) ||
          !userIds.add(userId)) {
        throw const FormatException('Inconsistent ERP chat directory response');
      }

      entries.add(
        ErpChatPrincipalDirectoryEntry(
          tenantId: rowTenantId,
          userId: userId,
          employeeId: _optionalString(row, 'employee_id'),
          displayName: displayName,
          role: role,
          photoUrl: _optionalString(row, 'photo_url'),
        ),
      );
    }
    return List<ErpChatPrincipalDirectoryEntry>.unmodifiable(entries);
  }

  static String _requiredString(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Invalid ERP chat directory $key');
    }
    return value.trim();
  }

  static String? _optionalString(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value == null) return null;
    if (value is! String) {
      throw FormatException('Invalid ERP chat directory $key');
    }
    return _normalized(value);
  }

  static String? _normalized(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
