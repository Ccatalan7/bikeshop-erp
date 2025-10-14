// =====================================================
// Purchase Service - Status Transition Methods
// =====================================================
// Add these methods to the existing PurchaseService class
// These handle the 5-status workflow with both payment models
// =====================================================

import 'package:supabase_flutter/supabase_flutter.dart';

class PurchaseServiceExtensions {
  final SupabaseClient _supabase = Supabase.instance.client;

  // =====================================================
  // Status Transition Methods
  // =====================================================

  /// Update invoice status (simple status change, no side effects)
  Future<void> updateInvoiceStatus(String invoiceId, String newStatus) async {
    await _supabase
        .from('purchase_invoices')
        .update({
          'status': newStatus,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', invoiceId);
  }

  /// Mark invoice as sent to supplier (Borrador → Enviada)
  Future<void> markAsSent(String invoiceId) async {
    await _supabase
        .from('purchase_invoices')
        .update({
          'status': 'sent',
          'sent_date': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', invoiceId);
  }

  /// Confirm invoice (Enviada → Confirmada)
  /// Creates accounting entry via trigger
  Future<void> confirmInvoice({
    required String invoiceId,
    required String supplierInvoiceNumber,
    required DateTime supplierInvoiceDate,
  }) async {
    await _supabase
        .from('purchase_invoices')
        .update({
          'status': 'confirmed',
          'confirmed_date': DateTime.now().toUtc().toIso8601String(),
          'supplier_invoice_number': supplierInvoiceNumber,
          'supplier_invoice_date': supplierInvoiceDate.toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', invoiceId);
  }

  /// Mark invoice as received (Confirmada → Recibida OR Pagada → Recibida)
  /// Increases inventory via trigger
  Future<void> markAsReceived(String invoiceId) async {
    await _supabase
        .from('purchase_invoices')
        .update({
          'status': 'received',
          'received_date': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', invoiceId);
  }

  /// Register payment for invoice
  /// Payment tracking trigger will update status automatically
  Future<void> registerPayment({
    required String invoiceId,
    required double amount,
    required String paymentMethod,
    required DateTime paymentDate,
    String? bankAccountId,
    String? reference,
    String? notes,
  }) async {
    await _supabase.from('purchase_payments').insert({
      'invoice_id': invoiceId,
      'amount': amount,
      'payment_method_id': paymentMethod,
      'date': paymentDate.toUtc().toIso8601String(),
      'reference': reference,
      'notes': notes,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  // =====================================================
  // Reversal Methods (backward transitions)
  // =====================================================

  /// Revert to draft (Enviada → Borrador)
  Future<void> revertToDraft(String invoiceId) async {
    await _supabase
        .from('purchase_invoices')
        .update({
          'status': 'draft',
          'sent_date': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', invoiceId);
  }

  /// Revert to sent (Confirmada → Enviada)
  /// Deletes accounting entry via trigger
  Future<void> revertToSent(String invoiceId) async {
    await _supabase
        .from('purchase_invoices')
        .update({
          'status': 'sent',
          'confirmed_date': null,
          'supplier_invoice_number': null,
          'supplier_invoice_date': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', invoiceId);
  }

  /// Revert to confirmed (Recibida → Confirmada for standard model)
  /// Reverses inventory via trigger
  Future<void> revertToConfirmed(String invoiceId) async {
    await _supabase
        .from('purchase_invoices')
        .update({
          'status': 'confirmed',
          'received_date': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', invoiceId);
  }

  /// Revert to paid (Recibida → Pagada for prepayment model)
  /// Reverses inventory via trigger
  Future<void> revertToPaid(String invoiceId) async {
    await _supabase
        .from('purchase_invoices')
        .update({
          'status': 'paid',
          'received_date': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', invoiceId);
  }

  /// Delete payment (and its journal entry)
  /// Payment tracking trigger will update invoice status automatically
  Future<void> deletePayment(String paymentId) async {
    await _supabase
        .from('purchase_payments')
        .delete()
        .eq('id', paymentId);
  }

  /// Get payments for an invoice
  Future<List<Map<String, dynamic>>> getInvoicePayments(String invoiceId) async {
    final response = await _supabase
        .from('purchase_payments')
        .select()
        .eq('invoice_id', invoiceId)
        .order('date', ascending: false);
    
    return List<Map<String, dynamic>>.from(response);
  }

  /// Get the most recent payment for an invoice
  Future<Map<String, dynamic>?> getLastPayment(String invoiceId) async {
    final payments = await getInvoicePayments(invoiceId);
    return payments.isNotEmpty ? payments.first : null;
  }

  /// Cancel invoice (sets status to cancelled)
  Future<void> cancelInvoice(String invoiceId, {String? reason}) async {
    await _supabase
        .from('purchase_invoices')
        .update({
          'status': 'cancelled',
          'notes': reason != null 
            ? 'ANULADA: $reason' 
            : 'ANULADA',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', invoiceId);
  }
}

// =====================================================
// Usage Instructions
// =====================================================
/*

1. Add these methods to the existing PurchaseService class in purchase_service.dart

2. Frontend usage examples:

// Mark as sent
await purchaseService.markAsSent(invoice.id!);

// Confirm with supplier's invoice details
await purchaseService.confirmInvoice(
  invoiceId: invoice.id!,
  supplierInvoiceNumber: 'FC-12345',
  supplierInvoiceDate: DateTime.now(),
);

// Mark as received (triggers inventory increase)
await purchaseService.markAsReceived(invoice.id!);

// Register payment
await purchaseService.registerPayment(
  invoiceId: invoice.id!,
  amount: invoice.total,
  paymentMethod: 'Transferencia',
  paymentDate: DateTime.now(),
  reference: 'TRF-001',
);

// Delete payment (undo payment)
final lastPayment = await purchaseService.getLastPayment(invoice.id!);
if (lastPayment != null) {
  await purchaseService.deletePayment(lastPayment['id']);
}

// Revert to previous status
await purchaseService.revertToSent(invoice.id!);  // Confirmada → Enviada
await purchaseService.revertToConfirmed(invoice.id!);  // Recibida → Confirmada

*/
