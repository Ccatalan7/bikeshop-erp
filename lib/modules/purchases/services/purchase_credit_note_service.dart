import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/purchase_credit_note.dart';

class PurchaseCreditNoteService {
  PurchaseCreditNoteService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  Future<bool> isEnabled() async {
    try {
      final row = await _client
          .from('purchase_credit_note_control_settings')
          .select('control_mode')
          .maybeSingle();
      return row?['control_mode'] == 'enforce';
    } on PostgrestException catch (error) {
      if (error.code == '42P01' || error.code == 'PGRST205') return false;
      rethrow;
    }
  }

  Future<bool> isRefundEnabled() async {
    try {
      final row = await _client
          .from('purchase_supplier_refund_control_settings')
          .select('control_mode')
          .maybeSingle();
      return row?['control_mode'] == 'enforce';
    } on PostgrestException catch (error) {
      if (error.code == '42P01' || error.code == 'PGRST205') return false;
      rethrow;
    }
  }

  Future<List<PurchaseCreditNoteLineBalance>> getLineBalances(
    String invoiceId,
  ) async {
    final rows = await _client
        .from('purchase_credit_note_line_balance_view')
        .select()
        .eq('purchase_invoice_id', invoiceId)
        .order('source_line_index');
    return rows
        .map((row) => PurchaseCreditNoteLineBalance.fromJson(
            Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<PurchaseCreditReturnOption>> getReturnOptions(
    String invoiceId,
  ) async {
    final returns = await _client
        .from('purchase_supplier_return_lines')
        .select(
            'id,source_line_key,returned_quantity,purchase_supplier_returns!inner(return_number,status,purchase_invoice_id)')
        .eq('purchase_supplier_returns.purchase_invoice_id', invoiceId)
        .eq('purchase_supplier_returns.status', 'posted');
    if (returns.isEmpty) return const [];
    final ids =
        returns.map((row) => row['id'].toString()).toList(growable: false);
    final credits = await _client
        .from('purchase_credit_note_lines')
        .select(
            'supplier_return_line_id,credited_quantity,purchase_credit_notes!inner(status)')
        .inFilter('supplier_return_line_id', ids)
        .eq('purchase_credit_notes.status', 'posted');
    final used = <String, int>{};
    for (final row in credits) {
      final id = row['supplier_return_line_id'].toString();
      used[id] =
          (used[id] ?? 0) + ((row['credited_quantity'] as num?)?.round() ?? 0);
    }
    return returns
        .map((row) {
          final id = row['id'].toString();
          final header = Map<String, dynamic>.from(
              row['purchase_supplier_returns'] as Map);
          return PurchaseCreditReturnOption(
            id: id,
            sourceLineKey: row['source_line_key'].toString(),
            returnNumber: header['return_number']?.toString() ?? '',
            returnedQuantity: (row['returned_quantity'] as num?)?.round() ?? 0,
            creditedQuantity: used[id] ?? 0,
          );
        })
        .where((option) => option.remainingQuantity > 0)
        .toList(growable: false);
  }

  Future<List<PurchaseCreditNoteRecord>> getHistory(String invoiceId) async {
    final rows = await _client
        .from('purchase_credit_note_refund_balance_view')
        .select()
        .eq('purchase_invoice_id', invoiceId)
        .order('issue_date', ascending: false);
    return rows
        .map((row) =>
            PurchaseCreditNoteRecord.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<PurchaseCreditNoteLineRecord>> getLines(String noteId) async {
    final rows = await _client
        .from('purchase_credit_note_lines')
        .select(
          'id,product_name,product_sku,credited_quantity,net_amount,'
          'tax_amount,total_amount,disposition',
        )
        .eq('purchase_credit_note_id', noteId)
        .order('source_line_index');
    return rows
        .map(
          (row) => PurchaseCreditNoteLineRecord.fromJson(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList(growable: false);
  }

  Future<List<PurchaseSupplierRefundRecord>> getRefunds(
      String invoiceId) async {
    final rows = await _client
        .from('purchase_supplier_refunds')
        .select(
            'id,purchase_credit_note_id,refund_number,status,refunded_at,amount,reference,reason,void_reason,payment_methods(name)')
        .eq('purchase_invoice_id', invoiceId)
        .order('refunded_at', ascending: false);
    return rows
        .map((row) => PurchaseSupplierRefundRecord.fromJson(
            Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<PurchaseRefundPaymentMethod>> getRefundPaymentMethods() async {
    final rows = await _client
        .from('payment_methods')
        .select('id,name,requires_reference')
        .eq('is_active', true)
        .order('sort_order');
    return rows
        .map((row) => PurchaseRefundPaymentMethod.fromJson(
            Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<PurchaseCreditNoteResult> create({
    required String invoiceId,
    required List<PurchaseCreditNoteLineDraft> lines,
    required DateTime issueDate,
    required String reasonCode,
    required String reason,
    required String idempotencyKey,
    String? supplierNumber,
  }) async {
    final resolvesReceiptDifference =
        lines.any((line) => line.receiptResolutionCaseId != null);
    final params = <String, dynamic>{
      'p_purchase_invoice_id': invoiceId,
      if (resolvesReceiptDifference)
        'p_cases': lines
            .map(
              (line) => {
                'case_id': line.receiptResolutionCaseId,
                'quantity': line.quantity,
              },
            )
            .toList()
      else
        'p_lines': lines.map((line) => line.toRpcJson()).toList(),
      'p_issue_date': issueDate.toUtc().toIso8601String(),
      'p_reason_code': reasonCode,
      'p_reason': reason.trim(),
      'p_supplier_credit_note_number': _nullable(supplierNumber),
      'p_idempotency_key': idempotencyKey,
    };
    final response = await _client.rpc(
      resolvesReceiptDifference
          ? 'resolve_purchase_receipt_with_credit_note'
          : 'create_purchase_credit_note',
      params: params,
    );
    return PurchaseCreditNoteResult.fromJson(
        Map<String, dynamic>.from(response as Map));
  }

  Future<void> voidNote(String id, String reason, String idempotencyKey) async {
    await _client.rpc('void_purchase_credit_note', params: {
      'p_credit_note_id': id,
      'p_reason': reason.trim(),
      'p_idempotency_key': idempotencyKey,
    });
  }

  Future<PurchaseSupplierRefundResult> createRefund({
    required String creditNoteId,
    required DateTime refundedAt,
    required String paymentMethodId,
    required int amount,
    required String reference,
    required String reason,
    required String idempotencyKey,
  }) async {
    final response =
        await _client.rpc('create_purchase_supplier_refund', params: {
      'p_purchase_credit_note_id': creditNoteId,
      'p_refunded_at': refundedAt.toUtc().toIso8601String(),
      'p_payment_method_id': paymentMethodId,
      'p_amount': amount,
      'p_reference': reference.trim(),
      'p_reason': reason.trim(),
      'p_idempotency_key': idempotencyKey,
    });
    return PurchaseSupplierRefundResult.fromJson(
        Map<String, dynamic>.from(response as Map));
  }

  Future<void> voidRefund(
      String id, String reason, String idempotencyKey) async {
    await _client.rpc('void_purchase_supplier_refund', params: {
      'p_refund_id': id,
      'p_reason': reason.trim(),
      'p_idempotency_key': idempotencyKey,
    });
  }

  String? _nullable(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
