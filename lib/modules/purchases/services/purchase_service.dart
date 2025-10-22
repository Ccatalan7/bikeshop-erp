import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/models/supplier.dart' as shared_supplier;
import '../../../shared/services/database_service.dart';
import '../../accounting/services/accounting_service.dart';
import '../models/purchase_invoice.dart';
import '../models/purchase_payment.dart';

class PurchaseService extends ChangeNotifier {
  PurchaseService(this._db);

  final DatabaseService _db;
  static AccountingService? _accountingService;

  // Helper to get Supabase client
  SupabaseClient get _supabase => Supabase.instance.client;

  List<shared_supplier.Supplier> _supplierCache = const [];
  List<PurchaseInvoice> _invoiceCache = const [];
  List<PurchasePayment> _paymentCache = const [];
  bool _suppliersLoaded = false;
  bool _invoicesLoaded = false;
  bool _paymentsLoaded = false;

  static void setAccountingService(AccountingService accountingService) {
    _accountingService = accountingService;
  }

  Future<List<shared_supplier.Supplier>> getSuppliers({
    bool forceRefresh = false,
    bool activeOnly = false,
  }) async {
    if (_suppliersLoaded && !forceRefresh) {
      return activeOnly
          ? _supplierCache.where((s) => s.isActive).toList()
          : _supplierCache;
    }
    try {
      final data = await _db.select('suppliers');
      _supplierCache = data
          .map((row) => shared_supplier.Supplier.fromJson(row))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      _suppliersLoaded = true;
      return activeOnly
          ? _supplierCache.where((s) => s.isActive).toList()
          : _supplierCache;
    } catch (e) {
      throw Exception('No se pudieron cargar los proveedores: $e');
    }
  }

  Future<shared_supplier.Supplier?> getSupplier(String id) async {
    if (id.isEmpty) return null;
    if (!_suppliersLoaded) {
      await getSuppliers(forceRefresh: true);
    }
    try {
      return _supplierCache.firstWhere((supplier) => supplier.id == id);
    } catch (_) {}

    try {
      final data = await _db.selectById('suppliers', id);
      if (data == null) return null;
      return shared_supplier.Supplier.fromJson(data);
    } catch (e) {
      debugPrint('PurchaseService: error obteniendo proveedor $id -> $e');
      return null;
    }
  }

  Future<shared_supplier.Supplier> createSupplier(String name) async {
    try {
      final result = await _db.insert('suppliers', {
        'name': name,
      });
      final supplier = shared_supplier.Supplier.fromJson(result);
      _supplierCache = [..._supplierCache, supplier];
      notifyListeners();
      return supplier;
    } catch (e) {
      throw Exception('No se pudo crear el proveedor: $e');
    }
  }

  Future<shared_supplier.Supplier> saveSupplier(
      shared_supplier.Supplier supplier) async {
    try {
      final payload = supplier.toJson();
      if (supplier.id.isEmpty) {
        final inserted = await _db.insert('suppliers', payload..remove('id'));
        final created = shared_supplier.Supplier.fromJson(inserted);
        await getSuppliers(forceRefresh: true);
        notifyListeners();
        return created;
      } else {
        payload.remove('created_at');
        await _db.update('suppliers', supplier.id, payload);
        await getSuppliers(forceRefresh: true);
        notifyListeners();
        final refreshed = await getSupplier(supplier.id);
        return refreshed ?? supplier;
      }
    } catch (e) {
      throw Exception('No se pudo guardar el proveedor: $e');
    }
  }

  Future<void> deleteSupplier(String id) async {
    try {
      await _db.delete('suppliers', id);
      await getSuppliers(forceRefresh: true);
      notifyListeners();
    } catch (e) {
      throw Exception('No se pudo eliminar el proveedor: $e');
    }
  }

  Future<List<PurchaseInvoice>> getPurchaseInvoices(
      {bool forceRefresh = false}) async {
    if (_invoicesLoaded && !forceRefresh) return _invoiceCache;
    try {
      final data = await _db.select('purchase_invoices');
      _invoiceCache = data.map((row) => PurchaseInvoice.fromJson(row)).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      _invoicesLoaded = true;
      return _invoiceCache;
    } catch (e) {
      throw Exception('No se pudieron cargar las facturas de compra: $e');
    }
  }

  Future<PurchaseInvoice?> getPurchaseInvoice(String id) async {
    try {
      final data = await _db.selectById('purchase_invoices', id);
      if (data == null) return null;
      return PurchaseInvoice.fromJson(data);
    } catch (e) {
      throw Exception('No se pudo obtener la factura: $e');
    }
  }

  Future<PurchaseInvoice> savePurchaseInvoice(PurchaseInvoice invoice) async {
    try {
      PurchaseInvoice saved;
      if (invoice.id == null) {
        final payload = invoice.toJson()..remove('id');
        final result = await _db.insert('purchase_invoices', payload);
        saved = PurchaseInvoice.fromJson(result);
      } else {
        final payload = invoice.toJson();
        payload.remove('created_at');
        await _db.update('purchase_invoices', invoice.id!, payload);
        final refreshed = await getPurchaseInvoice(invoice.id!);
        saved = refreshed ?? invoice;
      }

      await getPurchaseInvoices(forceRefresh: true);
      // NOTE: Accounting entries are now created automatically by database triggers
      // when invoice status changes to 'received'. No need to call _postAccountingEntry here.
      // await _postAccountingEntry(saved);
      notifyListeners();
      return saved;
    } catch (e) {
      throw Exception('No se pudo guardar la factura de compra: $e');
    }
  }

  Future<void> deletePurchaseInvoice(String id) async {
    try {
      // Check if invoice exists and get its status
      final invoice = await getPurchaseInvoice(id);
      if (invoice == null) {
        throw Exception('Factura no encontrada');
      }

      // Only allow deletion of draft invoices
      if (invoice.status != PurchaseInvoiceStatus.draft) {
        throw Exception('Solo se pueden eliminar facturas en estado Borrador. '
            'Esta factura está en estado: ${invoice.status.displayName}. '
            'Usa "Volver a Borrador" primero si necesitas eliminarla.');
      }

      await _db.delete('purchase_invoices', id);
      await getPurchaseInvoices(forceRefresh: true);
      notifyListeners();
    } catch (e) {
      throw Exception('No se pudo eliminar la factura: $e');
    }
  }

  /// Update the status of a purchase invoice
  /// This triggers database triggers for inventory and accounting
  Future<PurchaseInvoice?> updateInvoiceStatus(
    String invoiceId,
    PurchaseInvoiceStatus status,
  ) async {
    try {
      final payload = {
        'status': status.name,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

      final result = await _db.update('purchase_invoices', invoiceId, payload);
      final updated = PurchaseInvoice.fromJson(result);

      // Update cache
      _invoiceCache = _invoiceCache.map((inv) {
        return inv.id == invoiceId ? updated : inv;
      }).toList();

      // Refresh accounting if service available
      if (_accountingService != null) {
        await _accountingService!.initialize();
        await _accountingService!.journalEntries.loadJournalEntries();
      }

      // Fetch fresh data from database
      final refreshed = await getPurchaseInvoice(invoiceId);

      notifyListeners();
      return refreshed ?? updated;
    } catch (e) {
      debugPrint('PurchaseService.updateInvoiceStatus error: $e');
      rethrow;
    }
  }

  /// Mark invoice as received (triggers inventory increase and accounting)
  Future<PurchaseInvoice?> markAsReceived(String invoiceId) async {
    return updateInvoiceStatus(invoiceId, PurchaseInvoiceStatus.received);
  }

  /// Mark invoice as paid
  Future<PurchaseInvoice?> markAsPaid(String invoiceId) async {
    return updateInvoiceStatus(invoiceId, PurchaseInvoiceStatus.paid);
  }

  /// Cancel invoice
  Future<PurchaseInvoice?> cancelInvoice(String invoiceId) async {
    return updateInvoiceStatus(invoiceId, PurchaseInvoiceStatus.cancelled);
  }

  /// Revert to draft (from received or paid)
  /// This reverses inventory and accounting changes
  Future<PurchaseInvoice?> revertToDraft(String invoiceId) async {
    try {
      // Reversal is handled by database triggers
      return updateInvoiceStatus(invoiceId, PurchaseInvoiceStatus.draft);
    } catch (e) {
      debugPrint('PurchaseService.revertToDraft error: $e');
      rethrow;
    }
  }

  /// Revert to received (from paid)
  /// This only changes status, keeps inventory/accounting
  Future<PurchaseInvoice?> revertToReceived(String invoiceId) async {
    try {
      return updateInvoiceStatus(invoiceId, PurchaseInvoiceStatus.received);
    } catch (e) {
      debugPrint('PurchaseService.revertToReceived error: $e');
      rethrow;
    }
  }

  Future<void> _postAccountingEntry(PurchaseInvoice invoice) async {
    try {
      if (_accountingService == null) return;
      if (invoice.status == PurchaseInvoiceStatus.draft) return;

      await _accountingService!.postPurchaseEntry(
        date: invoice.date,
        supplierName: invoice.supplierName ?? 'Proveedor',
        invoiceNumber: invoice.invoiceNumber,
        subtotal: invoice.subtotal,
        ivaAmount: invoice.ivaAmount,
        total: invoice.total,
      );
    } catch (e) {
      debugPrint('PurchaseService: error creando asiento contable -> $e');
    }
  }

  // =====================================================
  // Purchase Payments
  // =====================================================

  Future<List<PurchasePayment>> getPurchasePayments(
      {bool forceRefresh = false}) async {
    if (_paymentsLoaded && !forceRefresh) {
      return _paymentCache;
    }

    try {
      final data = await _db.select('purchase_payments');
      _paymentCache = data.map((row) => PurchasePayment.fromJson(row)).toList()
        ..sort((a, b) => b.date.compareTo(a.date)); // Most recent first

      _paymentsLoaded = true;
      notifyListeners();
      return _paymentCache;
    } catch (e) {
      throw Exception('No se pudieron cargar los pagos de compras: $e');
    }
  }

  Future<List<PurchasePayment>> getPaymentsForInvoice(String invoiceId) async {
    try {
      final data = await _db.select(
        'purchase_payments',
        where: 'invoice_id=$invoiceId',
      );

      return data.map((row) => PurchasePayment.fromJson(row)).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
    } catch (e) {
      throw Exception('No se pudieron cargar los pagos de la factura: $e');
    }
  }

  Future<PurchasePayment> createPayment(PurchasePayment payment) async {
    try {
      final payload = payment.toJson()..remove('id');
      final result = await _db.insert('purchase_payments', payload);
      final created = PurchasePayment.fromJson(result);

      // Refresh caches
      await getPurchasePayments(forceRefresh: true);
      await getPurchaseInvoices(forceRefresh: true);

      notifyListeners();
      return created;
    } catch (e) {
      throw Exception('No se pudo registrar el pago: $e');
    }
  }

  Future<void> deletePayment(String paymentId) async {
    try {
      await _db.delete('purchase_payments', paymentId);

      // Refresh caches
      await getPurchasePayments(forceRefresh: true);
      await getPurchaseInvoices(forceRefresh: true);

      notifyListeners();
    } catch (e) {
      throw Exception('No se pudo eliminar el pago: $e');
    }
  }

  // =====================================================
  // 5-Status Workflow Methods
  // =====================================================

  /// Mark invoice as sent to supplier (Draft → Sent)
  Future<void> markInvoiceAsSent(String invoiceId) async {
    try {
      await _supabase.from('purchase_invoices').update({
        'status': 'sent',
        'sent_date': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', invoiceId);

      await getPurchaseInvoices(forceRefresh: true);
      notifyListeners();
    } catch (e) {
      throw Exception('No se pudo marcar como enviada: $e');
    }
  }

  /// Confirm invoice with supplier details (Sent → Confirmed)
  Future<void> confirmInvoice({
    required String invoiceId,
    required String supplierInvoiceNumber,
    required DateTime supplierInvoiceDate,
  }) async {
    try {
      await _supabase.from('purchase_invoices').update({
        'status': 'confirmed',
        'confirmed_date': DateTime.now().toUtc().toIso8601String(),
        'supplier_invoice_number': supplierInvoiceNumber,
        'supplier_invoice_date': supplierInvoiceDate.toIso8601String(),
      }).eq('id', invoiceId);

      await getPurchaseInvoices(forceRefresh: true);
      notifyListeners();
    } catch (e) {
      throw Exception('No se pudo confirmar la factura: $e');
    }
  }

  /// Mark invoice as received (Confirmed → Received)
  /// Triggers inventory update via database trigger
  Future<void> markInvoiceAsReceived(String invoiceId) async {
    try {
      // DEBUG: Log the update data being sent
      final updateData = {
        'status': 'received',
        'received_date': DateTime.now().toUtc().toIso8601String(),
      };
      print(
          '🔵 DEBUG - markInvoiceAsReceived: Updating invoice $invoiceId with data: $updateData');

      await _supabase
          .from('purchase_invoices')
          .update(updateData)
          .eq('id', invoiceId);

      print(
          '✅ DEBUG - markInvoiceAsReceived: Successfully updated to received status');

      await getPurchaseInvoices(forceRefresh: true);
      notifyListeners();
    } catch (e) {
      print('❌ DEBUG - markInvoiceAsReceived ERROR: $e');
      print('   Invoice ID: $invoiceId');
      if (e is PostgrestException) {
        print('   Postgrest code: ${e.code}');
        print('   Postgrest message: ${e.message}');
        print('   Postgrest details: ${e.details}');
        print('   Postgrest hint: ${e.hint}');
      }
      throw Exception('No se pudo marcar como recibida: $e');
    }
  }

  /// Register payment for invoice
  /// Creates payment record and journal entry
  Future<void> registerInvoicePayment({
    required String invoiceId,
    required double amount,
    required String paymentMethod,
    required String bankAccountId,
    required DateTime paymentDate,
    String? reference,
    String? notes,
  }) async {
    try {
      final paymentData = {
        'invoice_id': invoiceId,
        'date': paymentDate.toIso8601String(),
        'amount': amount,
        'payment_method_id': paymentMethod,
        'reference': reference,
        'notes': notes,
      };

      await _db.insert('purchase_payments', paymentData);

      // Refresh caches
      await getPurchasePayments(forceRefresh: true);
      await getPurchaseInvoices(forceRefresh: true);

      notifyListeners();
    } catch (e) {
      throw Exception('No se pudo registrar el pago: $e');
    }
  }

  /// Revert invoice to Draft status
  /// Deletes journal entries and reverses inventory (via trigger)
  Future<void> revertInvoiceToDraft(String invoiceId) async {
    try {
      await _supabase
          .from('purchase_invoices')
          .update({'status': 'draft'}).eq('id', invoiceId);

      await getPurchaseInvoices(forceRefresh: true);
      notifyListeners();
    } catch (e) {
      throw Exception('No se pudo revertir a borrador: $e');
    }
  }

  /// Revert invoice to Sent status
  Future<void> revertInvoiceToSent(String invoiceId) async {
    try {
      await _supabase
          .from('purchase_invoices')
          .update({'status': 'sent'}).eq('id', invoiceId);

      await getPurchaseInvoices(forceRefresh: true);
      notifyListeners();
    } catch (e) {
      throw Exception('No se pudo revertir a enviada: $e');
    }
  }

  /// Revert invoice to Confirmed status
  Future<void> revertInvoiceToConfirmed(String invoiceId) async {
    try {
      // DEBUG: Log the revert action
      print(
          '🔵 DEBUG - revertInvoiceToConfirmed: Reverting invoice $invoiceId from paid to confirmed');

      await _supabase
          .from('purchase_invoices')
          .update({'status': 'confirmed'}).eq('id', invoiceId);

      print(
          '✅ DEBUG - revertInvoiceToConfirmed: Successfully reverted to confirmed status');

      await getPurchaseInvoices(forceRefresh: true);
      notifyListeners();
    } catch (e) {
      print('❌ DEBUG - revertInvoiceToConfirmed ERROR: $e');
      print('   Invoice ID: $invoiceId');
      if (e is PostgrestException) {
        print('   Postgrest code: ${e.code}');
        print('   Postgrest message: ${e.message}');
        print('   Postgrest details: ${e.details}');
        print('   Postgrest hint: ${e.hint}');
      }
      throw Exception('No se pudo revertir a confirmada: $e');
    }
  }

  /// Revert invoice to Paid status (for prepayment model)
  Future<void> revertInvoiceToPaid(String invoiceId) async {
    try {
      await _supabase
          .from('purchase_invoices')
          .update({'status': 'paid'}).eq('id', invoiceId);

      await getPurchaseInvoices(forceRefresh: true);
      notifyListeners();
    } catch (e) {
      throw Exception('No se pudo revertir a pagada: $e');
    }
  }

  /// Delete last payment and revert status
  /// Deletes payment record and associated journal entry
  Future<void> undoLastPayment(String invoiceId) async {
    try {
      // Get the invoice to check prepayment model
      final invoiceData = await _supabase
          .from('purchase_invoices')
          .select('prepayment_model')
          .eq('id', invoiceId)
          .single();

      final isPrepayment = invoiceData['prepayment_model'] == true;

      // Get last payment
      final payments = await _supabase
          .from('purchase_payments')
          .select()
          .eq('invoice_id', invoiceId)
          .order('date', ascending: false)
          .limit(1);

      if (payments.isEmpty) {
        throw Exception('No hay pagos para deshacer');
      }

      final paymentId = payments.first['id'];
      await _db.delete('purchase_payments', paymentId);

      // Check if there are remaining payments
      final remainingPayments = await _supabase
          .from('purchase_payments')
          .select()
          .eq('invoice_id', invoiceId);

      // If no payments left, revert status based on model
      if (remainingPayments.isEmpty) {
        final newStatus = isPrepayment ? 'confirmed' : 'received';
        await _supabase
            .from('purchase_invoices')
            .update({'status': newStatus}).eq('id', invoiceId);
      }

      // Refresh caches
      await getPurchasePayments(forceRefresh: true);
      await getPurchaseInvoices(forceRefresh: true);

      notifyListeners();
    } catch (e) {
      throw Exception('No se pudo deshacer el pago: $e');
    }
  }
}
