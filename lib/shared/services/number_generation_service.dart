import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'tenant_service.dart';

/// Service for generating human-friendly sequential document numbers
/// Format: PREFIX-NNNN (e.g., FV-0143, AS-0324)
/// 
/// IMPORTANT: Use preview methods for form display, real methods only when saving!
/// - previewXxxNumber() → Shows what number WILL be assigned (doesn't increment)
/// - nextXxxNumber() → Actually assigns and increments (use only when saving)
class NumberGenerationService {
  final SupabaseClient _client = Supabase.instance.client;
  final TenantService _tenantService = TenantService();

  /// Generate next number for any document type (INCREMENTS the counter)
  /// Use only when actually SAVING a document!
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

  /// Preview next number for any document type (does NOT increment)
  /// Use for form display - shows what number will be assigned when saved
  Future<String> previewNextNumber(
    String documentType, {
    String? customPrefix,
  }) async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('Tenant ID not found');
      }

      final response = await _client.rpc('preview_next_document_number', params: {
        'p_tenant_id': tenantId,
        'p_document_type': documentType,
        'p_prefix': customPrefix,
      });

      return response as String;
    } catch (e) {
      if (kDebugMode) print('Error previewing document number: $e');
      rethrow;
    }
  }

  // ============================================================
  // PREVIEW METHODS - Use for form display (doesn't increment)
  // ============================================================
  
  /// Preview sales invoice number (e.g., FV-0143)
  Future<String> previewSalesInvoiceNumber() => previewNextNumber('sales_invoice');

  /// Preview purchase invoice number (e.g., FC-0089)
  Future<String> previewPurchaseInvoiceNumber() => previewNextNumber('purchase_invoice');

  /// Preview payment number
  Future<String> previewPaymentNumber({required bool isSales}) =>
      previewNextNumber(isSales ? 'sales_payment' : 'purchase_payment');

  /// Preview journal entry number (e.g., AS-0324)
  Future<String> previewJournalEntryNumber() => previewNextNumber('journal_entry');

  /// Preview mechanic job number (e.g., PG-0052)
  Future<String> previewMechanicJobNumber() => previewNextNumber('mechanic_job');

  /// Preview stock adjustment number (e.g., AJ-0018)
  Future<String> previewStockAdjustmentNumber() => previewNextNumber('stock_adjustment');

  // ============================================================
  // ACTUAL METHODS - Use only when SAVING (increments counter)
  // ============================================================
  
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
