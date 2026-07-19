import 'package:supabase_flutter/supabase_flutter.dart';

class SalesInvoiceVoidException implements Exception {
  const SalesInvoiceVoidException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SalesInvoiceVoidResult {
  const SalesInvoiceVoidResult({
    required this.invoiceId,
    required this.invoiceNumber,
    required this.operationId,
    required this.replayed,
  });

  final String invoiceId;
  final String invoiceNumber;
  final String operationId;
  final bool replayed;

  factory SalesInvoiceVoidResult.fromJson(Map<String, dynamic> json) {
    return SalesInvoiceVoidResult(
      invoiceId: json['invoice_id']?.toString() ?? '',
      invoiceNumber: json['invoice_number']?.toString() ?? '',
      operationId: json['operation_id']?.toString() ?? '',
      replayed: json['replayed'] == true,
    );
  }
}

class SalesInvoiceVoidService {
  SalesInvoiceVoidService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<SalesInvoiceVoidResult> voidInvoice({
    required String invoiceId,
    required String reason,
    required String idempotencyKey,
  }) async {
    try {
      final response = await _client.rpc(
        'void_sales_invoice',
        params: {
          'p_invoice_id': invoiceId,
          'p_reason': reason.trim(),
          'p_idempotency_key': idempotencyKey,
        },
      );
      return SalesInvoiceVoidResult.fromJson(
        Map<String, dynamic>.from(response as Map),
      );
    } on PostgrestException catch (error) {
      throw SalesInvoiceVoidException(error.message);
    } catch (_) {
      throw const SalesInvoiceVoidException(
        'No se pudo descartar la factura. Recarga e inténtalo nuevamente.',
      );
    }
  }
}
