import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/purchase_receipt.dart';

class PurchaseReceivingService {
  PurchaseReceivingService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<PurchaseReceiptControlMode> getControlMode() async {
    try {
      final row = await _client
          .from('purchase_receipt_control_settings')
          .select('control_mode')
          .maybeSingle();
      return PurchaseReceiptControlModeX.fromDatabase(row?['control_mode']);
    } on PostgrestException catch (error) {
      if (PurchaseReceivingBackendCompatibility.isSchemaUnavailable(error)) {
        return PurchaseReceiptControlMode.disabled;
      }
      rethrow;
    }
  }

  Future<Map<int, int>> getPreviouslyReceivedByLine(String invoiceId) async {
    final rows = await _client
        .from('purchase_receipt_lines')
        .select(
            'source_line_index,accepted_quantity,purchase_receipts!inner(status)')
        .eq('purchase_invoice_id', invoiceId)
        .eq('purchase_receipts.status', 'posted');
    final totals = <int, int>{};
    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw);
      final index = (row['source_line_index'] as num).toInt();
      final accepted = (row['accepted_quantity'] as num?)?.toInt() ?? 0;
      totals[index] = (totals[index] ?? 0) + accepted;
    }
    return totals;
  }

  Future<List<PurchaseReceiptRecord>> getHistory(String invoiceId) async {
    final headers = await _client
        .from('purchase_receipts')
        .select(
            'id,receipt_number,status,received_at,delivery_reference,location_label,void_reason')
        .eq('purchase_invoice_id', invoiceId)
        .order('received_at', ascending: false);
    if (headers.isEmpty) return const [];

    final ids = headers.map((row) => row['id'].toString()).toList();
    final lines = await _client
        .from('purchase_receipt_lines')
        .select(
            'receipt_id,accepted_quantity,damaged_quantity,rejected_quantity,shortage_quantity')
        .inFilter('receipt_id', ids);
    final accepted = <String, int>{};
    final discrepancies = <String, int>{};
    for (final row in lines) {
      final id = row['receipt_id'].toString();
      accepted[id] = (accepted[id] ?? 0) +
          ((row['accepted_quantity'] as num?)?.round() ?? 0);
      discrepancies[id] = (discrepancies[id] ?? 0) +
          ((row['damaged_quantity'] as num?)?.round() ?? 0) +
          ((row['rejected_quantity'] as num?)?.round() ?? 0) +
          ((row['shortage_quantity'] as num?)?.round() ?? 0);
    }

    return headers.map((row) {
      final id = row['id'].toString();
      return PurchaseReceiptRecord(
        id: id,
        number: row['receipt_number']?.toString() ?? '',
        status: row['status']?.toString() ?? '',
        receivedAt: DateTime.parse(row['received_at'].toString()),
        acceptedQuantity: accepted[id] ?? 0,
        discrepancyQuantity: discrepancies[id] ?? 0,
        deliveryReference: row['delivery_reference']?.toString(),
        locationLabel: row['location_label']?.toString(),
        voidReason: row['void_reason']?.toString(),
      );
    }).toList(growable: false);
  }

  Future<void> voidReceipt({
    required String receiptId,
    required String reason,
    required String idempotencyKey,
  }) async {
    await _client.rpc('void_purchase_goods_receipt', params: {
      'p_receipt_id': receiptId,
      'p_reason': reason.trim(),
      'p_idempotency_key': idempotencyKey,
    });
  }

  Future<PurchaseReceiptResult> createReceipt({
    required String invoiceId,
    required List<PurchaseReceiptLineDraft> lines,
    required DateTime receivedAt,
    required String idempotencyKey,
    String? deliveryReference,
    String? locationLabel,
    String? notes,
  }) async {
    if (lines.isEmpty) {
      throw ArgumentError('La recepción necesita al menos una línea.');
    }
    for (final line in lines) {
      final error = line.validate();
      if (error != null) throw ArgumentError(error);
    }
    final response = await _client.rpc(
      'create_purchase_goods_receipt',
      params: {
        'p_purchase_invoice_id': invoiceId,
        'p_lines': lines.map((line) => line.toRpcJson()).toList(),
        'p_received_at': receivedAt.toUtc().toIso8601String(),
        'p_delivery_reference': _nullableText(deliveryReference),
        'p_location_label': _nullableText(locationLabel),
        'p_notes': _nullableText(notes),
        'p_idempotency_key': idempotencyKey,
      },
    );
    return PurchaseReceiptResult.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  String? _nullableText(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}

class PurchaseReceivingBackendCompatibility {
  const PurchaseReceivingBackendCompatibility._();

  static bool isSchemaUnavailable(PostgrestException error) {
    return error.code == '42P01' ||
        error.code == 'PGRST205' ||
        error.message.contains('purchase_receipt_control_settings');
  }
}
