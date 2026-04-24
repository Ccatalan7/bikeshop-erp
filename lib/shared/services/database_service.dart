import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'query_performance_service.dart';

class DatabaseService extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;

  SupabaseClient get supabase => _client;

  // Tables that should NOT have tenant_id auto-injected
  static const _excludedTables = {
    'tenants',
    'user_profiles',
    'reserved_subdomains',
    'user_invitations',
  };

  /// Automatically injects tenant_id for multi-tenant tables
  Future<void> _injectTenantId(
      String table, Map<String, dynamic> payload) async {
    // Skip if table is excluded from multi-tenancy
    if (_excludedTables.contains(table)) {
      return;
    }

    // Check if tenant_id already exists and is valid (not placeholder)
    final existingTenantId = payload['tenant_id'];
    final isPlaceholder = existingTenantId == null ||
        existingTenantId == '' ||
        existingTenantId == '00000000-0000-0000-0000-000000000000';

    // Skip injection if valid tenant_id already exists
    if (payload.containsKey('tenant_id') && !isPlaceholder) {
      return;
    }

    try {
      // Get tenant_id from current user's profile
      final userId = _client.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('⚠️ No authenticated user - cannot inject tenant_id');
        return;
      }

      final profileResponse = await _client
          .from('user_profiles')
          .select('tenant_id')
          .eq('user_id', userId)
          .maybeSingle();

      if (profileResponse != null && profileResponse['tenant_id'] != null) {
        payload['tenant_id'] = profileResponse['tenant_id'];
        debugPrint(
            '✅ Auto-injected tenant_id: ${payload['tenant_id']} into $table');
      } else {
        debugPrint('⚠️ User has no tenant_id in user_profiles');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to inject tenant_id: $e');
      // Don't rethrow - let RLS handle the error
    }
  }

  // Generic CRUD operations
  Future<List<Map<String, dynamic>>> select(
    String table, {
    String? selectColumns,
    String? where,
    List<String>? whereIn,
    String? orderBy,
    bool descending = false,
    int? limit,
    bool fetchAll = false, // New parameter to fetch all records with pagination
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      if (kDebugMode) {
        debugPrint(
            '🔍 DB Query: $table | where: $where | whereIn: ${whereIn?.length} items | orderBy: $orderBy | limit: $limit | fetchAll: $fetchAll');
      }

      // If fetchAll is true and no explicit limit, use pagination to get ALL records
      if (fetchAll && limit == null) {
        return await _selectWithPagination(
          table,
          selectColumns: selectColumns,
          where: where,
          whereIn: whereIn,
          orderBy: orderBy,
          descending: descending,
        );
      }

      // Use dynamic to handle different builder types in the chain
      dynamic query = selectColumns == null
          ? _client.from(table).select()
          : _client.from(table).select(selectColumns);

      // Handle simple WHERE clause
      if (where != null && where.contains('=')) {
        final parts = where.split('=');
        final field = parts[0].trim();
        final rawValue = parts.sublist(1).join('=').trim();
        // Parse numeric values properly for integer columns
        final dynamic value = int.tryParse(rawValue) ??
            double.tryParse(rawValue) ??
            (rawValue == 'true'
                ? true
                : rawValue == 'false'
                    ? false
                    : rawValue);
        query = query.eq(field, value);
      }

      // Handle WHERE IN clause
      if (where != null && whereIn != null && whereIn.isNotEmpty) {
        query = query.inFilter(where, whereIn);
      }

      // Handle ORDER BY
      if (orderBy != null) {
        query = query.order(orderBy, ascending: !descending);
      }

      // Handle LIMIT
      if (limit != null) {
        query = query.limit(limit);
      }

      final data = await query;

      stopwatch.stop();

      if (kDebugMode) {
        debugPrint(
            '✅ DB Result: ${data == null ? "NULL" : (data as List).length} rows from $table');
      }

      if (data == null) {
        _recordReadMetric(
          label: table,
          operation: 'select',
          rowCount: 0,
          data: const [],
          durationMs: stopwatch.elapsedMilliseconds,
        );
        return [];
      }

      final listData = data as List;

      _recordReadMetric(
        label: table,
        operation: 'select',
        rowCount: listData.length,
        data: data,
        durationMs: stopwatch.elapsedMilliseconds,
      );

      return listData
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Database select error on $table: $e');
      }
      rethrow;
    }
  }

  // Private helper for pagination (fetches all records in batches)
  Future<List<Map<String, dynamic>>> _selectWithPagination(
    String table, {
    String? selectColumns,
    String? where,
    List<String>? whereIn,
    String? orderBy,
    bool descending = false,
  }) async {
    const int batchSize = 1000;
    int offset = 0;
    List<Map<String, dynamic>> allRecords = [];
    final stopwatch = Stopwatch()..start();

    if (kDebugMode) {
      debugPrint(
          '📄 Starting paginated fetch for $table (batch size: $batchSize)');
    }

    while (true) {
      dynamic query = selectColumns == null
          ? _client.from(table).select()
          : _client.from(table).select(selectColumns);

      // Apply filters
      if (where != null && where.contains('=')) {
        final parts = where.split('=');
        final field = parts[0].trim();
        final value = parts.sublist(1).join('=').trim();
        query = query.eq(field, value);
      }

      if (where != null && whereIn != null && whereIn.isNotEmpty) {
        query = query.inFilter(where, whereIn);
      }

      // Apply ordering
      if (orderBy != null) {
        query = query.order(orderBy, ascending: !descending);
      }

      // Apply pagination
      query = query.range(offset, offset + batchSize - 1);

      final data = await query;
      if (data == null) {
        if (kDebugMode) {
          debugPrint('⚠️ DB returned null during pagination for $table');
        }
        break;
      }

      final listData = data as List;
      final batch =
          listData.map((row) => Map<String, dynamic>.from(row as Map)).toList();

      allRecords.addAll(batch);

      if (kDebugMode) {
        debugPrint(
            '📄 Fetched batch: ${batch.length} rows (total: ${allRecords.length})');
      }

      // If we got less than batchSize, we've reached the end
      if (batch.length < batchSize) {
        break;
      }

      offset += batchSize;
    }

    if (kDebugMode) {
      debugPrint(
          '✅ Completed paginated fetch for $table: ${allRecords.length} total rows');
    }

    stopwatch.stop();
    _recordReadMetric(
      label: table,
      operation: 'select_paginated',
      rowCount: allRecords.length,
      data: allRecords,
      durationMs: stopwatch.elapsedMilliseconds,
    );

    return allRecords;
  }

  /// Select records with specific pagination range (for UI pagination)
  Future<List<Map<String, dynamic>>> selectWithPagination(
    String table, {
    required int from,
    required int to,
    String? selectColumns,
    String? where,
    String? orderBy,
    bool descending = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      dynamic query = selectColumns == null
          ? _client.from(table).select()
          : _client.from(table).select(selectColumns);

      // Apply tenant filter
      final tenantId = await getTenantId();
      if (tenantId != null && !_isSystemTable(table)) {
        query = query.eq('tenant_id', tenantId);
      }

      // Apply additional filters
      if (where != null && where.contains('=')) {
        final parts = where.split('=');
        final field = parts[0].trim();
        final value = parts.sublist(1).join('=').trim();
        query = query.eq(field, value);
      }

      // Apply ordering
      if (orderBy != null) {
        query = query.order(orderBy, ascending: !descending);
      }

      // Apply range
      query = query.range(from, to);

      final data = await query as List;
      stopwatch.stop();
      _recordReadMetric(
        label: table,
        operation: 'select_range',
        rowCount: data.length,
        data: data,
        durationMs: stopwatch.elapsedMilliseconds,
      );
      return data.map((row) => Map<String, dynamic>.from(row as Map)).toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error in selectWithPagination: $e');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> selectById(
    String table,
    String id, {
    String? selectColumns,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      dynamic query = selectColumns == null
          ? _client.from(table).select()
          : _client.from(table).select(selectColumns);
      final data = await query.eq('id', id).maybeSingle();
      stopwatch.stop();
      _recordReadMetric(
        label: table,
        operation: 'select_by_id',
        rowCount: data == null ? 0 : 1,
        data: data,
        durationMs: stopwatch.elapsedMilliseconds,
      );
      return data != null ? Map<String, dynamic>.from(data as Map) : null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Database selectById error: $e');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> insert(String table, Map<String, dynamic> data,
      {bool applyTimestamps = true}) async {
    try {
      final payload = Map<String, dynamic>.from(data);

      // ⚠️ CRITICAL: Auto-inject tenant_id for multi-tenant tables
      await _injectTenantId(table, payload);

      if (applyTimestamps) {
        _applyTimestamps(payload, isInsert: true);
      }
      final result =
          await _client.from(table).insert(payload).select().single();
      notifyListeners();
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Database insert error: $e');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> update(
      String table, String id, Map<String, dynamic> data,
      {bool applyTimestamps = true}) async {
    try {
      final payload = Map<String, dynamic>.from(data);
      if (applyTimestamps) {
        _applyTimestamps(payload, isInsert: false);
      }
      final result = await _client
          .from(table)
          .update(payload)
          .eq('id', id)
          .select()
          .single();
      notifyListeners();
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Database update error: $e');
      }
      rethrow;
    }
  }

  Future<void> delete(String table, String id) async {
    try {
      await _client.from(table).delete().eq('id', id);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Database delete error: $e');
      }
      rethrow;
    }
  }

  /// Delete records matching a where clause (e.g., 'voucher_id', voucherId)
  Future<void> deleteWhere(String table, String column, String value) async {
    try {
      await _client.from(table).delete().eq(column, value);
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Database deleteWhere error: $e');
      }
      rethrow;
    }
  }

  Future<String?> ensureAccount({
    required String code,
    required String name,
    required String type,
    required String category,
    String? description,
    String? parentCode,
  }) async {
    try {
      final result = await _client.rpc('ensure_account', params: {
        'p_code': code,
        'p_name': name,
        'p_type': type,
        'p_category': category,
        'p_description': description,
        'p_parent_code': parentCode,
      });

      return result?.toString();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Database ensureAccount error: $e');
      }
      rethrow;
    }
  }

  // Accounting-specific operations
  Future<String> createJournalEntry(
    Map<String, dynamic> entry,
    List<Map<String, dynamic>> lines,
  ) async {
    try {
      _applyTimestamps(entry, isInsert: true);
      final insertedEntry =
          await _client.from('journal_entries').insert(entry).select().single();

      final entryId = insertedEntry['id'].toString();

      if (lines.isNotEmpty) {
        final now = DateTime.now().toUtc().toIso8601String();
        final mappedLines = lines
            .map((line) => {
                  ...line,
                  'entry_id':
                      entryId, // Correct column name from core_schema.sql
                  'created_at': line['created_at'] ?? now,
                  'updated_at': line['updated_at'] ?? now,
                })
            .toList();

        await _client.from('journal_lines').insert(mappedLines);
      }

      notifyListeners();
      return entryId;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Journal entry creation error: $e');
      }
      rethrow;
    }
  }

  // Inventory operations
  Future<Map<String, dynamic>> adjustStock(
    String productId,
    int quantity,
    String type,
    String reference, {
    String? adjustmentOrigin,
  }) async {
    try {
      final normalizedType = type.trim().toUpperCase();
      final result =
          await _client.rpc('apply_manual_stock_adjustment', params: {
        'p_product_id': productId,
        'p_quantity': quantity,
        'p_type': normalizedType,
        'p_reason': reference,
        'p_adjustment_origin': adjustmentOrigin,
      });

      notifyListeners();
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Stock adjustment error: $e');
      }
      rethrow;
    }
  }

  // Search operations
  Future<List<Map<String, dynamic>>> searchRecords(
    String table,
    String searchColumn,
    String searchTerm, {
    String? selectColumns,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      dynamic query = selectColumns == null
          ? _client.from(table).select()
          : _client.from(table).select(selectColumns);
      final data = await query.ilike(searchColumn, '%${searchTerm.trim()}%');
      final rows = List<Map<String, dynamic>>.from(data);
      stopwatch.stop();
      _recordReadMetric(
        label: table,
        operation: 'search:$searchColumn',
        rowCount: rows.length,
        data: rows,
        durationMs: stopwatch.elapsedMilliseconds,
      );
      return rows;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Search error: $e');
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> searchRecordsMultiToken(
    String table,
    List<String> columns,
    List<String> searchTerms, {
    int limit = 50,
    String? selectColumns,
  }) async {
    if (searchTerms.isEmpty || columns.isEmpty) return [];

    final stopwatch = Stopwatch()..start();
    try {
      dynamic query = selectColumns == null
          ? _client.from(table).select()
          : _client.from(table).select(selectColumns);

      // For every search token, it MUST be present in AT LEAST ONE of the columns
      for (final term in searchTerms) {
        final safeTerm = term.replaceAll('%', '\\%').replaceAll('_', '\\_');
        // e.g. "name.ilike.%term%,sku.ilike.%term%"
        final orFilter =
            columns.map((col) => '$col.ilike.%$safeTerm%').join(',');
        query = query.or(orFilter);
      }

      final data = await query.limit(limit);
      final rows = List<Map<String, dynamic>>.from(data);
      stopwatch.stop();
      _recordReadMetric(
        label: table,
        operation: 'search_multi',
        rowCount: rows.length,
        data: rows,
        durationMs: stopwatch.elapsedMilliseconds,
      );
      return rows;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('searchRecordsMultiToken error: $e');
      }
      rethrow;
    }
  }

  // Generic RPC call for custom PostgreSQL functions
  Future<dynamic> rpc(String functionName,
      {Map<String, dynamic>? params}) async {
    final stopwatch = Stopwatch()..start();
    try {
      if (kDebugMode) {
        debugPrint('🔧 RPC Call: $functionName | params: $params');
      }
      final result = await _client.rpc(functionName, params: params);
      stopwatch.stop();
      _recordReadMetric(
        label: 'rpc:$functionName',
        operation: 'rpc',
        rowCount: _estimateRowCount(result),
        data: result,
        durationMs: stopwatch.elapsedMilliseconds,
      );
      if (kDebugMode) {
        debugPrint('✅ RPC Result: $functionName completed');
      }
      return result;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ RPC error on $functionName: $e');
      }
      rethrow;
    }
  }

  void _applyTimestamps(Map<String, dynamic> data, {required bool isInsert}) {
    final now = DateTime.now().toUtc().toIso8601String();
    if (isInsert) {
      data['created_at'] ??= now;
    }
    data['updated_at'] = now;
  }

  /// Get current user's tenant ID
  Future<String?> getTenantId() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return null;

      final profileResponse = await _client
          .from('user_profiles')
          .select('tenant_id')
          .eq('user_id', userId)
          .maybeSingle();

      return profileResponse?['tenant_id'] as String?;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Error getting tenant_id: $e');
      }
      return null;
    }
  }

  /// Check if table should be excluded from tenant filtering
  bool _isSystemTable(String table) {
    return _excludedTables.contains(table);
  }

  void _recordReadMetric({
    required String label,
    required String operation,
    required int rowCount,
    required Object? data,
    required int durationMs,
  }) {
    if (!QueryPerformanceService.isEnabled) return;

    QueryPerformanceService.instance.recordRead(
      label: label,
      operation: operation,
      rowCount: rowCount,
      estimatedBytes: _estimatePayloadBytes(data),
      durationMs: durationMs,
    );
  }

  int _estimatePayloadBytes(Object? data) {
    if (!QueryPerformanceService.isEnabled || data == null) return 0;
    try {
      return utf8.encode(jsonEncode(data)).length;
    } catch (_) {
      return 0;
    }
  }

  int _estimateRowCount(Object? data) {
    if (data is List) return data.length;
    if (data is Map) return 1;
    return data == null ? 0 : 1;
  }
}
