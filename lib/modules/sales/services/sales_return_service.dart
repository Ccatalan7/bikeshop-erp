import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/sales_models.dart';
import '../models/sales_return.dart';

class SalesReturnService {
  SalesReturnService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  Future<bool> isEnabled() async {
    try {
      final row = await _client
          .from('sales_return_control_settings')
          .select('control_mode')
          .maybeSingle();
      return row?['control_mode'] == 'enforce';
    } on PostgrestException catch (error) {
      if (error.code == '42P01' || error.code == 'PGRST205') return false;
      rethrow;
    }
  }

  Future<List<SalesReturnableLine>> getReturnableLines(Invoice invoice) async {
    final rows = await _client
        .from('sales_return_lines')
        .select(
            'source_line_index,returned_quantity,sales_returns!inner(status,sales_invoice_id)')
        .eq('sales_returns.sales_invoice_id', invoice.id!)
        .eq('sales_returns.status', 'posted');
    final returned = <int, int>{};
    for (final row in rows) {
      final index = (row['source_line_index'] as num?)?.round() ?? -1;
      returned[index] = (returned[index] ?? 0) +
          ((row['returned_quantity'] as num?)?.round() ?? 0);
    }
    return invoice.items.indexed
        .where((entry) =>
            !entry.$2.isService &&
            entry.$2.productId != null &&
            entry.$2.quantity > 0 &&
            entry.$2.quantity == entry.$2.quantity.roundToDouble())
        .map((entry) => SalesReturnableLine.fromInvoiceItem(
            entry.$1, entry.$2, returned[entry.$1] ?? 0))
        .where((line) => line.remainingQuantity > 0)
        .toList(growable: false);
  }

  Future<List<SalesReturnRecord>> getHistory(String invoiceId) async {
    final headers = await _client
        .from('sales_returns')
        .select('id,return_number,status,returned_at,reason,void_reason')
        .eq('sales_invoice_id', invoiceId)
        .order('returned_at', ascending: false);
    if (headers.isEmpty) return const [];
    final returnIds =
        headers.map((row) => row['id'].toString()).toList(growable: false);
    final lineRows = await _client
        .from('sales_return_lines')
        .select('id,sales_return_id,product_name,returned_quantity,disposition')
        .inFilter('sales_return_id', returnIds);
    final lineIds =
        lineRows.map((row) => row['id'].toString()).toList(growable: false);
    final quarantineRows = lineIds.isEmpty
        ? const <Map<String, dynamic>>[]
        : await _client
            .from('sales_return_quarantine')
            .select('id,sales_return_line_id,status,resolution_id')
            .inFilter('sales_return_line_id', lineIds);
    final quarantineByLine = {
      for (final row in quarantineRows)
        row['sales_return_line_id'].toString(): Map<String, dynamic>.from(row),
    };
    final linesByReturn = <String, List<SalesReturnHistoryLine>>{};
    for (final row in lineRows) {
      final id = row['id'].toString();
      final quarantine = quarantineByLine[id];
      final line = SalesReturnHistoryLine(
        id: id,
        productName: row['product_name']?.toString() ?? 'Producto',
        quantity: (row['returned_quantity'] as num?)?.round() ?? 0,
        disposition: row['disposition']?.toString() ?? '',
        quarantineId: quarantine?['id']?.toString(),
        quarantineStatus: quarantine?['status']?.toString(),
        resolutionId: quarantine?['resolution_id']?.toString(),
      );
      linesByReturn
          .putIfAbsent(row['sales_return_id'].toString(), () => [])
          .add(line);
    }
    return headers
        .map((row) => SalesReturnRecord(
              id: row['id'].toString(),
              number: row['return_number']?.toString() ?? '',
              status: row['status']?.toString() ?? '',
              returnedAt: DateTime.parse(row['returned_at'].toString()),
              reason: row['reason']?.toString() ?? '',
              voidReason: row['void_reason']?.toString(),
              lines: linesByReturn[row['id'].toString()] ?? const [],
            ))
        .toList(growable: false);
  }

  Future<SalesReturnResult> create({
    required String invoiceId,
    required List<SalesReturnLineDraft> lines,
    required DateTime returnedAt,
    required String reason,
    required String idempotencyKey,
    String? notes,
  }) async {
    final response = await _client.rpc('create_sales_return', params: {
      'p_sales_invoice_id': invoiceId,
      'p_lines': lines.map((line) => line.toRpcJson()).toList(),
      'p_returned_at': returnedAt.toUtc().toIso8601String(),
      'p_reason': reason.trim(),
      'p_notes': _nullable(notes),
      'p_idempotency_key': idempotencyKey,
    });
    return SalesReturnResult.fromJson(
        Map<String, dynamic>.from(response as Map));
  }

  Future<void> voidReturn(String id, String reason, String key) =>
      _client.rpc('void_sales_return', params: {
        'p_sales_return_id': id,
        'p_reason': reason.trim(),
        'p_idempotency_key': key,
      });

  Future<QuarantineResolutionResult> resolveQuarantine({
    required String quarantineId,
    required String disposition,
    required String reason,
    required String idempotencyKey,
  }) async {
    final response =
        await _client.rpc('resolve_sales_return_quarantine', params: {
      'p_quarantine_id': quarantineId,
      'p_disposition': disposition,
      'p_resolved_at': DateTime.now().toUtc().toIso8601String(),
      'p_reason': reason.trim(),
      'p_notes': null,
      'p_idempotency_key': idempotencyKey,
    });
    return QuarantineResolutionResult.fromJson(
        Map<String, dynamic>.from(response as Map));
  }

  Future<void> voidResolution(String id, String reason, String key) =>
      _client.rpc('void_sales_return_quarantine_resolution', params: {
        'p_resolution_id': id,
        'p_reason': reason.trim(),
        'p_idempotency_key': key,
      });

  String? _nullable(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
