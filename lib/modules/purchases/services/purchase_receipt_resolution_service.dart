import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/purchase_receipt_resolution.dart';

class PurchaseReceiptResolutionService {
  PurchaseReceiptResolutionService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<PurchaseReceiptResolutionCase>> getCasesForReceipt(
    String receiptId,
  ) =>
      _getCases(
        filterColumn: 'purchase_receipt_id',
        filterValue: receiptId,
      );

  Future<List<PurchaseReceiptResolutionCase>> getCasesForInvoice(
    String invoiceId,
  ) =>
      _getCases(
        filterColumn: 'purchase_invoice_id',
        filterValue: invoiceId,
      );

  Future<List<PurchaseReceiptResolutionCase>> _getCases({
    required String filterColumn,
    required String filterValue,
  }) async {
    try {
      final rawCases = await _client
          .from('purchase_receipt_resolution_case_view')
          .select()
          .eq(filterColumn, filterValue)
          .order('created_at')
          .order('source_line_index')
          .order('discrepancy_kind');
      if (rawCases.isEmpty) return const [];

      final caseIds =
          rawCases.map((row) => row['id'].toString()).toList(growable: false);
      final rawAllocations = await _client
          .from('purchase_receipt_resolution_allocation_view')
          .select()
          .inFilter('case_id', caseIds)
          .order('created_at');
      final allocationsByCase =
          <String, List<PurchaseReceiptResolutionAllocation>>{};
      for (final raw in rawAllocations) {
        final allocation = _allocation(Map<String, dynamic>.from(raw));
        allocationsByCase
            .putIfAbsent(allocation.caseId, () => [])
            .add(allocation);
      }

      return rawCases.map((raw) {
        final row = Map<String, dynamic>.from(raw);
        final id = row['id']?.toString() ?? '';
        return PurchaseReceiptResolutionCase(
          id: id,
          number: row['case_number']?.toString() ?? '',
          purchaseInvoiceId: row['purchase_invoice_id']?.toString() ?? '',
          purchaseReceiptId: row['purchase_receipt_id']?.toString() ?? '',
          purchaseReceiptNumber: row['receipt_number']?.toString(),
          purchaseReceiptLineId:
              row['purchase_receipt_line_id']?.toString() ?? '',
          sourceLineIndex: _integer(row['source_line_index']),
          sourceLineKey: row['source_line_key']?.toString() ?? '',
          productId: row['product_id']?.toString(),
          productName: row['product_name']?.toString() ?? 'Producto',
          purchaseTreatment:
              row['purchase_treatment']?.toString() ?? 'inventory',
          productSku: row['product_sku']?.toString(),
          kind: PurchaseReceiptDiscrepancyKindX.fromDatabase(
            row['discrepancy_kind'],
          ),
          reportedQuantity: _integer(row['discrepancy_quantity']),
          resolvedQuantity: _integer(row['resolved_quantity']),
          openQuantity: _integer(row['open_quantity']),
          effectiveStatus: row['effective_status']?.toString() ?? 'open',
          discrepancyReason: row['discrepancy_reason']?.toString(),
          createdAt: _date(row['created_at']),
          allocations: List.unmodifiable(allocationsByCase[id] ?? const []),
        );
      }).toList(growable: false);
    } on PostgrestException catch (error) {
      if (_isSchemaUnavailable(error)) return const [];
      rethrow;
    }
  }

  Future<PurchaseReceiptLossResolutionResult> resolveWithDocumentedLoss({
    required String invoiceId,
    required String caseId,
    required int quantity,
    required DateTime effectiveAt,
    required String reason,
    required String idempotencyKey,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('La cantidad a pérdida debe ser positiva.');
    }
    if (reason.trim().isEmpty) {
      throw ArgumentError('El motivo de la pérdida es obligatorio.');
    }
    final response = await _client.rpc(
      'resolve_purchase_receipt_with_documented_loss',
      params: {
        'p_purchase_invoice_id': invoiceId,
        'p_cases': [
          {'case_id': caseId, 'quantity': quantity},
        ],
        'p_effective_at': effectiveAt.toUtc().toIso8601String(),
        'p_reason': reason.trim(),
        'p_idempotency_key': idempotencyKey,
      },
    );
    return PurchaseReceiptLossResolutionResult.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  Future<void> voidDocumentedLoss({
    required String resolutionGroupId,
    required String reason,
    required String idempotencyKey,
  }) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('El motivo de anulación es obligatorio.');
    }
    await _client.rpc(
      'void_purchase_receipt_documented_loss',
      params: {
        'p_resolution_group_id': resolutionGroupId,
        'p_reason': reason.trim(),
        'p_idempotency_key': idempotencyKey,
      },
    );
  }

  PurchaseReceiptResolutionAllocation _allocation(
    Map<String, dynamic> row,
  ) {
    return PurchaseReceiptResolutionAllocation(
      id: row['id']?.toString() ?? '',
      caseId: row['case_id']?.toString() ?? '',
      resolutionGroupId: row['resolution_group_id']?.toString() ?? '',
      outcome: PurchaseReceiptResolutionOutcomeX.fromDatabase(row['outcome']),
      quantity: _integer(row['resolved_quantity']),
      effectiveStatus: row['effective_status']?.toString() ?? 'voided',
      isEffective: row['is_effective'] == true,
      createdAt: _date(row['created_at']),
      purchaseCreditNoteId: row['purchase_credit_note_id']?.toString(),
      purchaseCreditNoteLineId: row['purchase_credit_note_line_id']?.toString(),
      purchaseCreditNoteNumber: row['purchase_credit_note_number']?.toString(),
      laterPurchaseReceiptId: row['later_receipt_id']?.toString(),
      laterPurchaseReceiptLineId: row['later_receipt_line_id']?.toString(),
      laterPurchaseReceiptNumber: row['later_receipt_number']?.toString(),
      supplierReturnId: row['supplier_return_id']?.toString(),
      supplierReturnNumber: row['supplier_return_number']?.toString(),
      supplierReturnStatus: row['supplier_return_status']?.toString(),
      supplierRefunds: _refunds(row['supplier_refunds']),
      lossJournalEntryId: row['journal_entry_id']?.toString(),
      lossJournalEntryNumber: row['journal_entry_number']?.toString(),
      lossOperationId: row['operation_id']?.toString(),
      reason: row['reason']?.toString(),
      voidReason: row['void_reason']?.toString(),
    );
  }

  int _integer(Object? value) => (value as num?)?.round() ?? 0;

  List<PurchaseReceiptSupplierRefundReference> _refunds(Object? value) {
    if (value is! List) return const [];
    return value.whereType<Map>().map(
      (raw) {
        final row = Map<String, dynamic>.from(raw);
        return PurchaseReceiptSupplierRefundReference(
          id: row['id']?.toString() ?? '',
          number: row['refund_number']?.toString() ?? '',
          status: row['status']?.toString() ?? '',
          amount: (row['amount'] as num?)?.toDouble() ?? 0,
          refundedAt: DateTime.tryParse(
            row['refunded_at']?.toString() ?? '',
          ),
        );
      },
    ).toList(growable: false);
  }

  DateTime _date(Object? value) {
    return DateTime.tryParse(value?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  bool _isSchemaUnavailable(PostgrestException error) {
    return error.code == '42P01' || error.code == 'PGRST205';
  }
}
