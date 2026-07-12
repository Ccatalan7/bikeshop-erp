import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/sales_credit_note.dart';

class SalesCreditNoteService {
  SalesCreditNoteService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;
  final SupabaseClient _client;

  Future<bool> isEnabled() async {
    try {
      final row = await _client
          .from('sales_credit_note_control_settings')
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
          .from('sales_customer_refund_control_settings')
          .select('control_mode')
          .maybeSingle();
      return row?['control_mode'] == 'enforce';
    } on PostgrestException catch (error) {
      if (error.code == '42P01' || error.code == 'PGRST205') return false;
      rethrow;
    }
  }

  Future<List<SalesCreditNoteLineBalance>> getLineBalances(
      String invoiceId) async {
    final rows = await _client
        .from('sales_credit_note_line_balance_view')
        .select()
        .eq('sales_invoice_id', invoiceId)
        .order('source_line_index');
    return rows
        .map((row) =>
            SalesCreditNoteLineBalance.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<SalesCreditReturnOption>> getReturnOptions(
      String invoiceId) async {
    final returns = await _client
        .from('sales_return_lines')
        .select(
            'id,source_line_key,returned_quantity,sales_returns!inner(return_number,status,sales_invoice_id)')
        .eq('sales_returns.sales_invoice_id', invoiceId)
        .eq('sales_returns.status', 'posted');
    if (returns.isEmpty) return const [];
    final ids =
        returns.map((row) => row['id'].toString()).toList(growable: false);
    final credits = await _client
        .from('sales_credit_note_lines')
        .select(
            'sales_return_line_id,credited_quantity,sales_credit_notes!inner(status)')
        .inFilter('sales_return_line_id', ids)
        .eq('sales_credit_notes.status', 'posted');
    final used = <String, int>{};
    for (final row in credits) {
      final id = row['sales_return_line_id'].toString();
      used[id] =
          (used[id] ?? 0) + ((row['credited_quantity'] as num?)?.round() ?? 0);
    }
    return returns
        .map((row) {
          final id = row['id'].toString();
          final header = Map<String, dynamic>.from(row['sales_returns'] as Map);
          return SalesCreditReturnOption(
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

  Future<List<SalesCreditNoteRecord>> getHistory(String invoiceId) async {
    final rows = await _client
        .from('sales_credit_note_refund_balance_view')
        .select()
        .eq('sales_invoice_id', invoiceId)
        .order('issue_date', ascending: false);
    return rows
        .map((row) =>
            SalesCreditNoteRecord.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<SalesCustomerRefundRecord>> getRefunds(String invoiceId) async {
    final rows = await _client
        .from('sales_customer_refunds')
        .select(
            'id,sales_credit_note_id,refund_number,status,refunded_at,amount,reference,reason,void_reason,payment_methods(name)')
        .eq('sales_invoice_id', invoiceId)
        .order('refunded_at', ascending: false);
    return rows
        .map((row) =>
            SalesCustomerRefundRecord.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<SalesRefundPaymentMethod>> getRefundPaymentMethods() async {
    final rows = await _client
        .from('payment_methods')
        .select('id,name,requires_reference')
        .eq('is_active', true)
        .order('sort_order');
    return rows
        .map((row) =>
            SalesRefundPaymentMethod.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<SalesCreditNoteResult> create({
    required String invoiceId,
    required List<SalesCreditNoteLineDraft> lines,
    required DateTime issueDate,
    required String reasonCode,
    required String reason,
    required String idempotencyKey,
  }) async {
    final response = await _client.rpc('create_sales_credit_note', params: {
      'p_sales_invoice_id': invoiceId,
      'p_lines': lines.map((line) => line.toRpcJson()).toList(),
      'p_issue_date': issueDate.toUtc().toIso8601String(),
      'p_reason_code': reasonCode,
      'p_reason': reason.trim(),
      'p_idempotency_key': idempotencyKey,
    });
    return SalesCreditNoteResult.fromJson(
        Map<String, dynamic>.from(response as Map));
  }

  Future<void> voidNote(String id, String reason, String key) =>
      _client.rpc('void_sales_credit_note', params: {
        'p_credit_note_id': id,
        'p_reason': reason.trim(),
        'p_idempotency_key': key,
      });

  Future<SalesCustomerRefundResult> createRefund({
    required String creditNoteId,
    required DateTime refundedAt,
    required String paymentMethodId,
    required int amount,
    required String reference,
    required String reason,
    required String idempotencyKey,
  }) async {
    final response = await _client.rpc('create_sales_customer_refund', params: {
      'p_sales_credit_note_id': creditNoteId,
      'p_refunded_at': refundedAt.toUtc().toIso8601String(),
      'p_payment_method_id': paymentMethodId,
      'p_amount': amount,
      'p_reference': reference.trim(),
      'p_reason': reason.trim(),
      'p_idempotency_key': idempotencyKey,
    });
    return SalesCustomerRefundResult.fromJson(
        Map<String, dynamic>.from(response as Map));
  }

  Future<void> voidRefund(String id, String reason, String key) =>
      _client.rpc('void_sales_customer_refund', params: {
        'p_refund_id': id,
        'p_reason': reason.trim(),
        'p_idempotency_key': key,
      });
}
