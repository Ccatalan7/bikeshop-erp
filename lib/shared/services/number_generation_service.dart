import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'tenant_service.dart';

/// Service for generating human-friendly sequential document numbers
/// Format: PREFIX-NNNN (e.g., FV-0143, AS-0324)
class NumberGenerationService {
  final SupabaseClient _client = Supabase.instance.client;
  final TenantService _tenantService = TenantService();

  /// Generate next number for any document type
  Future<String> getNextNumber(
    String documentType, {
    String? customPrefix,
  }) async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('Tenant ID not found');
      }

      final response = await _client.rpc('get_next_document_number', params: {
        'p_tenant_id': tenantId,
        'p_document_type': documentType,
        'p_prefix': customPrefix,
      });

      return response as String;
    } catch (e) {
      if (kDebugMode) print('Error generating document number: $e');
      rethrow;
    }
  }

  // Convenience methods for each document type
  
  /// Generate sales invoice number (e.g., FV-0143)
  Future<String> nextSalesInvoiceNumber() => getNextNumber('sales_invoice');

  /// Generate purchase invoice number (e.g., FC-0089)
  Future<String> nextPurchaseInvoiceNumber() => getNextNumber('purchase_invoice');

  /// Generate payment number (e.g., PV-0215 for sales, PC-0067 for purchases)
  Future<String> nextPaymentNumber({required bool isSales}) =>
      getNextNumber(isSales ? 'sales_payment' : 'purchase_payment');

  /// Generate journal entry number (e.g., AS-0324)
  Future<String> nextJournalEntryNumber() => getNextNumber('journal_entry');

  /// Generate mechanic job number (e.g., PG-0052)
  Future<String> nextMechanicJobNumber() => getNextNumber('mechanic_job');

  /// Generate stock adjustment number (e.g., AJ-0018)
  Future<String> nextStockAdjustmentNumber() => getNextNumber('stock_adjustment');
}
