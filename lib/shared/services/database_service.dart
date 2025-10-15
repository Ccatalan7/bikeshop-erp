import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DatabaseService extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;

  // Generic CRUD operations
  Future<List<Map<String, dynamic>>> select(
    String table, {
    String? where,
    List<String>? whereIn,
    String? orderBy,
    bool descending = false,
    int? limit,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🔍 DB Query: $table | where: $where | whereIn: ${whereIn?.length} items | orderBy: $orderBy | limit: $limit');
      }
      
      // Use dynamic to handle different builder types in the chain
      dynamic query = _client.from(table).select();

      // Handle simple WHERE clause
      if (where != null && where.contains('=')) {
        final parts = where.split('=');
        final field = parts[0].trim();
        final value = parts.sublist(1).join('=').trim();
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
      
      if (kDebugMode) {
        debugPrint('✅ DB Result: ${(data as List).length} rows from $table');
      }
      
      return (data as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Database select error on $table: $e');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> selectById(String table, String id) async {
    try {
      final data =
          await _client.from(table).select().eq('id', id).maybeSingle();
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
                  'entry_id': entryId, // Correct column name from core_schema.sql
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
  Future<void> adjustStock(
    String productId,
    int quantity,
    String type,
    String reference,
  ) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await _client.from('stock_movements').insert({
        'product_id': productId,
        'quantity': quantity,
        'type': type,
        'reference': reference,
        'date': now,
        'created_at': now,
        'updated_at': now,
      });

      final product = await _client
          .from('products')
          .select('inventory_qty')
          .eq('id', productId)
          .maybeSingle();
      final productMap =
          product == null ? null : Map<String, dynamic>.from(product as Map);
      final currentQty =
          productMap == null ? 0 : (productMap['inventory_qty'] as int? ?? 0);
      final newQty =
          type == 'IN' ? currentQty + quantity : currentQty - quantity;

      await _client.from('products').update({
        'inventory_qty': newQty,
        'updated_at': now,
      }).eq('id', productId);

      notifyListeners();
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
    String searchTerm,
  ) async {
    try {
      final data = await _client
          .from(table)
          .select()
          .ilike(searchColumn, '%${searchTerm.trim()}%');
      return List<Map<String, dynamic>>.from(data as List);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Search error: $e');
      }
      rethrow;
    }
  }

  // Generic RPC call for custom PostgreSQL functions
  Future<dynamic> rpc(String functionName, {Map<String, dynamic>? params}) async {
    try {
      if (kDebugMode) {
        debugPrint('🔧 RPC Call: $functionName | params: $params');
      }
      final result = await _client.rpc(functionName, params: params);
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
}
