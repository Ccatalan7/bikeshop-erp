import 'package:flutter/foundation.dart';

import '../../../shared/models/supplier.dart' as shared_supplier;
import '../../../shared/services/database_service.dart';
import '../../accounting/services/accounting_service.dart';
import '../models/purchase_invoice.dart';

class PurchaseService extends ChangeNotifier {
  PurchaseService(this._db);

  final DatabaseService _db;
  static AccountingService? _accountingService;

  List<shared_supplier.Supplier> _supplierCache = const [];
  List<PurchaseInvoice> _invoiceCache = const [];
  bool _suppliersLoaded = false;
  bool _invoicesLoaded = false;

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

  Future<shared_supplier.Supplier> saveSupplier(shared_supplier.Supplier supplier) async {
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

  Future<List<PurchaseInvoice>> getPurchaseInvoices({bool forceRefresh = false}) async {
    if (_invoicesLoaded && !forceRefresh) return _invoiceCache;
    try {
      final data = await _db.select('purchase_invoices');
      _invoiceCache = data
          .map((row) => PurchaseInvoice.fromJson(row))
          .toList()
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
        final payload = invoice.toJson()
          ..remove('id');
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
        throw Exception(
          'Solo se pueden eliminar facturas en estado Borrador. '
          'Esta factura está en estado: ${invoice.status.displayName}. '
          'Usa "Volver a Borrador" primero si necesitas eliminarla.'
        );
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
}
