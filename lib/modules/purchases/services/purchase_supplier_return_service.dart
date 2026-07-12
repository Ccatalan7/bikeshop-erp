import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/purchase_supplier_return.dart';

class PurchaseSupplierReturnService {
  PurchaseSupplierReturnService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<PurchaseReturnableReceipt>> getReturnableReceipts(
    String invoiceId,
  ) async {
    final rawReceipts = await _client
        .from('purchase_receipts')
        .select('id,receipt_number,received_at')
        .eq('purchase_invoice_id', invoiceId)
        .eq('status', 'posted')
        .order('received_at', ascending: false);
    if (rawReceipts.isEmpty) return const [];

    final receiptIds =
        rawReceipts.map((row) => row['id'].toString()).toList(growable: false);
    final rawLines = await _client
        .from('purchase_receipt_lines')
        .select(
          'id,receipt_id,product_name,product_sku,accepted_quantity,'
          'source_line_index,purchase_receipt_line_movements!inner(id)',
        )
        .inFilter('receipt_id', receiptIds)
        .gt('accepted_quantity', 0)
        .order('source_line_index');
    if (rawLines.isEmpty) return const [];

    final lineIds =
        rawLines.map((row) => row['id'].toString()).toList(growable: false);
    final rawReturns = await _client
        .from('purchase_supplier_return_lines')
        .select(
          'purchase_receipt_line_id,returned_quantity,purchase_supplier_returns!inner(status)',
        )
        .inFilter('purchase_receipt_line_id', lineIds)
        .eq('purchase_supplier_returns.status', 'posted');
    final returnedByLine = <String, int>{};
    for (final raw in rawReturns) {
      final lineId = raw['purchase_receipt_line_id'].toString();
      returnedByLine[lineId] = (returnedByLine[lineId] ?? 0) +
          ((raw['returned_quantity'] as num?)?.toInt() ?? 0);
    }

    final linesByReceipt = <String, List<PurchaseSupplierReturnLineDraft>>{};
    for (final raw in rawLines) {
      final lineId = raw['id'].toString();
      final receiptId = raw['receipt_id'].toString();
      final accepted = (raw['accepted_quantity'] as num?)?.toInt() ?? 0;
      final returned = returnedByLine[lineId] ?? 0;
      if (returned >= accepted) continue;
      linesByReceipt.putIfAbsent(receiptId, () => []).add(
            PurchaseSupplierReturnLineDraft(
              receiptLineId: lineId,
              productName: raw['product_name']?.toString() ?? 'Producto',
              productSku: raw['product_sku']?.toString(),
              acceptedQuantity: accepted,
              previouslyReturnedQuantity: returned,
            ),
          );
    }

    return rawReceipts
        .map((raw) {
          final id = raw['id'].toString();
          return PurchaseReturnableReceipt(
            id: id,
            receiptNumber: raw['receipt_number']?.toString() ?? '',
            receivedAt: DateTime.parse(raw['received_at'].toString()),
            lines: List.unmodifiable(linesByReceipt[id] ?? const []),
          );
        })
        .where((receipt) => receipt.lines.isNotEmpty)
        .toList(growable: false);
  }

  Future<PurchaseSupplierReturnResult> createSupplierReturn({
    required String receiptId,
    required List<PurchaseSupplierReturnLineDraft> lines,
    required DateTime returnedAt,
    required String reason,
    required String idempotencyKey,
    String? shipmentReference,
    String? notes,
  }) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('El motivo de la devolución es obligatorio.');
    }
    if (lines.isEmpty) {
      throw ArgumentError('Selecciona al menos un producto para devolver.');
    }
    for (final line in lines) {
      final error = line.validate();
      if (error != null) throw ArgumentError(error);
    }
    final response = await _client.rpc(
      'create_purchase_supplier_return',
      params: {
        'p_purchase_receipt_id': receiptId,
        'p_lines': lines.map((line) => line.toRpcJson()).toList(),
        'p_returned_at': returnedAt.toUtc().toIso8601String(),
        'p_reason': reason.trim(),
        'p_shipment_reference': _nullableText(shipmentReference),
        'p_notes': _nullableText(notes),
        'p_idempotency_key': idempotencyKey,
      },
    );
    return PurchaseSupplierReturnResult.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  Future<List<PurchaseSupplierReturnRecord>> getSupplierReturns(
    String invoiceId,
  ) async {
    final rows = await _client
        .from('purchase_supplier_returns')
        .select(
          'id,return_number,status,returned_at,reason,shipment_reference,'
          'void_reason,purchase_supplier_return_lines(returned_quantity)',
        )
        .eq('purchase_invoice_id', invoiceId)
        .order('returned_at', ascending: false);
    return rows
        .map(
          (row) => PurchaseSupplierReturnRecord.fromJson(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList(growable: false);
  }

  Future<PurchaseSupplierReturnVoidResult> voidSupplierReturn({
    required String supplierReturnId,
    required String reason,
    required String idempotencyKey,
  }) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('El motivo de anulación es obligatorio.');
    }
    final response = await _client.rpc(
      'void_purchase_supplier_return',
      params: {
        'p_supplier_return_id': supplierReturnId,
        'p_reason': reason.trim(),
        'p_idempotency_key': idempotencyKey,
      },
    );
    return PurchaseSupplierReturnVoidResult.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  String? _nullableText(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
