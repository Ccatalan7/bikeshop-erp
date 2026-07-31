import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/erp_employee_directory_entry.dart';

abstract class ErpEmployeeDirectoryGateway {
  String? get currentUserId;

  Future<Object?> getDirectory();
}

class SupabaseErpEmployeeDirectoryGateway
    implements ErpEmployeeDirectoryGateway {
  SupabaseErpEmployeeDirectoryGateway([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  String? get currentUserId => _client.auth.currentUser?.id;

  @override
  Future<Object?> getDirectory() {
    return _client.rpc('get_erp_employee_directory');
  }
}

/// Auth-user-scoped cache for the redacted ERP coworker directory.
///
/// The RPC owns tenant resolution and returns `user_id` only for a bilateral,
/// active ERP account link. This client still validates the complete response
/// before publishing it and discards late loads after an Auth scope change.
class ErpEmployeeDirectoryService {
  factory ErpEmployeeDirectoryService() => _instance;

  ErpEmployeeDirectoryService.forTesting({
    required ErpEmployeeDirectoryGateway gateway,
    DateTime Function()? now,
  })  : _gateway = gateway,
        _now = now ?? DateTime.now;

  ErpEmployeeDirectoryService._({
    required ErpEmployeeDirectoryGateway gateway,
    DateTime Function()? now,
  })  : _gateway = gateway,
        _now = now ?? DateTime.now;

  static final ErpEmployeeDirectoryService _instance =
      ErpEmployeeDirectoryService._(
    gateway: SupabaseErpEmployeeDirectoryGateway(),
  );

  static const _allowedStatuses = {
    'active',
    'inactive',
    'on_leave',
  };
  static const _cacheTtl = Duration(minutes: 2);

  final ErpEmployeeDirectoryGateway _gateway;
  final DateTime Function() _now;

  String? _scopeKey;
  List<ErpEmployeeDirectoryEntry>? _cachedEntries;
  DateTime? _cacheLoadedAt;
  Future<List<ErpEmployeeDirectoryEntry>>? _inFlight;
  int _scopeGeneration = 0;

  Future<List<ErpEmployeeDirectoryEntry>> getEntries({
    required String authorityTenantId,
    bool forceRefresh = false,
  }) {
    final userId = _normalized(_gateway.currentUserId);
    final tenantId = _normalized(authorityTenantId);
    if (userId == null || tenantId == null) {
      clear();
      return Future<List<ErpEmployeeDirectoryEntry>>.error(
        StateError('An active ERP user and tenant authority are required'),
      );
    }

    final scopeKey = '$userId:$tenantId';
    _bindScope(scopeKey);
    if (forceRefresh) {
      _cachedEntries = null;
      _cacheLoadedAt = null;
    }
    final cached = _cachedEntries;
    final cacheLoadedAt = _cacheLoadedAt;
    final cacheAge =
        cacheLoadedAt == null ? null : _now().difference(cacheLoadedAt);
    final cacheIsFresh =
        cacheAge != null && !cacheAge.isNegative && cacheAge < _cacheTtl;
    if (!forceRefresh && cached != null && cacheIsFresh) {
      return SynchronousFuture(cached);
    }

    final pending = _inFlight;
    if (pending != null) return pending;

    final generation = _scopeGeneration;
    late final Future<List<ErpEmployeeDirectoryEntry>> request;
    request = _loadAndValidate(
      expectedUserId: userId,
      expectedScopeKey: scopeKey,
      generation: generation,
    ).whenComplete(() {
      if (identical(_inFlight, request)) {
        _inFlight = null;
      }
    });
    _inFlight = request;
    return request;
  }

  Future<ErpEmployeeDirectoryEntry?> findByUserId(
    String userId, {
    required String authorityTenantId,
    bool forceRefresh = false,
  }) async {
    final normalizedUserId = _normalized(userId);
    if (normalizedUserId == null) return null;
    final entries = await getEntries(
      authorityTenantId: authorityTenantId,
      forceRefresh: forceRefresh,
    );
    for (final entry in entries) {
      if (entry.userId == normalizedUserId) return entry;
    }
    return null;
  }

  void clear() {
    _scopeGeneration++;
    _scopeKey = null;
    _cachedEntries = null;
    _cacheLoadedAt = null;
    _inFlight = null;
  }

  void _bindScope(String scopeKey) {
    if (_scopeKey == scopeKey) return;
    _scopeGeneration++;
    _scopeKey = scopeKey;
    _cachedEntries = null;
    _cacheLoadedAt = null;
    _inFlight = null;
  }

  Future<List<ErpEmployeeDirectoryEntry>> _loadAndValidate({
    required String expectedUserId,
    required String expectedScopeKey,
    required int generation,
  }) async {
    final response = await _gateway.getDirectory();
    final entries = _parseResponse(response);
    if (_scopeGeneration != generation ||
        _scopeKey != expectedScopeKey ||
        _normalized(_gateway.currentUserId) != expectedUserId) {
      throw StateError('ERP employee directory scope changed during load');
    }
    _cachedEntries = entries;
    _cacheLoadedAt = _now();
    return entries;
  }

  List<ErpEmployeeDirectoryEntry> _parseResponse(Object? response) {
    if (response is! List) {
      throw const FormatException('Invalid ERP employee directory response');
    }

    final entries = <ErpEmployeeDirectoryEntry>[];
    final employeeIds = <String>{};
    final userIds = <String>{};
    for (final rawRow in response) {
      if (rawRow is! Map) {
        throw const FormatException('Invalid ERP employee directory row');
      }
      final row = Map<String, dynamic>.from(rawRow);
      const expectedKeys = {
        'employee_id',
        'user_id',
        'first_name',
        'last_name',
        'job_title',
        'system_role',
        'status',
        'photo_url',
        'department_id',
      };
      if (!setEquals(row.keys.toSet(), expectedKeys)) {
        throw const FormatException(
          'Unexpected ERP employee directory row shape',
        );
      }

      final employeeId = _requiredString(row, 'employee_id');
      final userId = _optionalString(row, 'user_id');
      final firstName = _requiredString(row, 'first_name');
      final lastName = _requiredString(row, 'last_name');
      final jobTitle = _optionalString(row, 'job_title');
      final systemRole = _optionalString(row, 'system_role');
      final status = _requiredString(row, 'status').toLowerCase();
      final photoUrl = _optionalString(row, 'photo_url');
      final departmentId = _optionalString(row, 'department_id');

      if (!_allowedStatuses.contains(status) ||
          !employeeIds.add(employeeId) ||
          (userId != null && !userIds.add(userId))) {
        throw const FormatException(
          'Inconsistent ERP employee directory response',
        );
      }

      entries.add(
        ErpEmployeeDirectoryEntry(
          employeeId: employeeId,
          userId: userId,
          firstName: firstName,
          lastName: lastName,
          jobTitle: jobTitle,
          systemRole: systemRole,
          status: status,
          photoUrl: photoUrl,
          departmentId: departmentId,
        ),
      );
    }
    return List<ErpEmployeeDirectoryEntry>.unmodifiable(entries);
  }

  String _requiredString(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Invalid ERP employee directory $key');
    }
    return value.trim();
  }

  String? _optionalString(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value == null) return null;
    if (value is! String) {
      throw FormatException('Invalid ERP employee directory $key');
    }
    return _normalized(value);
  }

  static String? _normalized(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
