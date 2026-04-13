import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/database_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../accounting/services/accounting_service.dart';
import '../../accounting/widgets/accounting_dashboard_section.dart';
import '../models/sales_models.dart';

class SalesService extends ChangeNotifier {
  static const _invoicesCollection = 'sales_invoices';
  static const _paymentsCollection = 'sales_payments';

  SalesService(
      this._databaseService, this._accountingService, this._tenantService);

  DatabaseService _databaseService;
  AccountingService _accountingService;
  final TenantService _tenantService;

  RealtimeChannel? _invoiceChannel;
  RealtimeChannel? _paymentChannel;

  final List<Invoice> _invoices = [];
  final List<Payment> _payments = [];

  bool _isLoadingInvoices = false;
  bool _isLoadingPayments = false;
  String? _invoiceError;
  String? _paymentError;
  Timer? _realtimeNotifyDebounce; // Debounce realtime notifications
  final Map<String, DateTime> _justSavedInvoiceIds = {}; // ID -> Timestamp

  // ============================================================
  // CACHING - Avoid refetching on every page navigation
  // ============================================================
  DateTime? _invoicesCacheTime;
  DateTime? _paymentsCacheTime;
  static const Duration _cacheMaxAge = Duration(minutes: 5);

  // Public getters for cached data (instant UI access)
  List<Invoice> get cachedInvoices => List.unmodifiable(_invoices);
  List<Payment> get cachedPayments => List.unmodifiable(_payments);
  bool get hasInvoicesCache =>
      _invoices.isNotEmpty && _invoicesCacheTime != null;
  bool get hasPaymentsCache =>
      _payments.isNotEmpty && _paymentsCacheTime != null;

  /// Check if cache is still valid
  bool _isCacheValid(DateTime? cacheTime) {
    if (cacheTime == null) return false;
    return DateTime.now().difference(cacheTime) < _cacheMaxAge;
  }

  /// Invalidate invoice cache (call after create/update/delete)
  void invalidateInvoicesCache() {
    _invoicesCacheTime = null;
    debugPrint('🗑️ [SalesService] Invoices cache invalidated');
  }

  /// Invalidate payment cache (call after create/update/delete)
  void invalidatePaymentsCache() {
    _paymentsCacheTime = null;
    debugPrint('🗑️ [SalesService] Payments cache invalidated');
  }

  UnmodifiableListView<Invoice> get invoices => UnmodifiableListView(_invoices);
  UnmodifiableListView<Payment> get payments => UnmodifiableListView(_payments);

  bool get isLoadingInvoices => _isLoadingInvoices;
  bool get isLoadingPayments => _isLoadingPayments;

  String? get invoiceError => _invoiceError;
  String? get paymentError => _paymentError;

  void updateDependencies(
      DatabaseService databaseService, AccountingService accountingService) {
    _databaseService = databaseService;
    _accountingService = accountingService;
    _ensureRealtimeSubscriptions();
  }

  Future<void> loadInvoices({bool forceRefresh = false}) async {
    // Return cached data if valid
    if (!forceRefresh &&
        _isCacheValid(_invoicesCacheTime) &&
        _invoices.isNotEmpty) {
      debugPrint(
          '📦 [SalesService] Using cached invoices (${_invoices.length} items)');
      return;
    }

    if (_isLoadingInvoices) return;

    _isLoadingInvoices = true;
    _invoiceError = null;
    notifyListeners();

    try {
      final data = await _databaseService.select(_invoicesCollection);
      final invoices = data.map((raw) => Invoice.fromJson(raw)).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

      _invoices
        ..clear()
        ..addAll(invoices);
      _invoicesCacheTime = DateTime.now();
      debugPrint('✅ [SalesService] Cached ${invoices.length} invoices');
      _ensureRealtimeSubscriptions();
    } catch (e) {
      debugPrint('SalesService.loadInvoices error: $e');
      _invoiceError = 'No se pudieron cargar las facturas.';
    } finally {
      _isLoadingInvoices = false;
      notifyListeners();
    }
  }

  Future<Invoice?> fetchInvoice(String id, {bool refresh = false}) async {
    debugPrint(
      '📥 [SalesService] fetchInvoice start | id=$id | refresh=$refresh | cacheSize=${_invoices.length}',
    );

    if (!refresh) {
      for (final invoice in _invoices) {
        if (invoice.id == id) {
          debugPrint(
            '📦 [SalesService] fetchInvoice cache hit | id=$id | itemCount=${invoice.items.length} | subtotal=${invoice.subtotal} | total=${invoice.total}',
          );
          return invoice;
        }
      }
    }

    try {
      final data = await _databaseService.selectById(_invoicesCollection, id);
      if (data == null) {
        debugPrint(
            '⚠️ [SalesService] fetchInvoice returned null from DB | id=$id');
        return null;
      }

      final rawItems = data['items'];
      final rawItemsCount = rawItems is List ? rawItems.length : -1;
      debugPrint(
        '🗄️ [SalesService] fetchInvoice DB result | id=$id | rawItemsCount=$rawItemsCount | subtotal=${data['subtotal']} | total=${data['total']} | status=${data['status']}',
      );

      final invoice = Invoice.fromJson(data);
      debugPrint(
        '✅ [SalesService] fetchInvoice parsed | id=$id | itemCount=${invoice.items.length} | subtotal=${invoice.subtotal} | total=${invoice.total}',
      );
      _upsertInvoice(invoice);
      return invoice;
    } catch (e) {
      debugPrint('SalesService.fetchInvoice error: $e');
      return null;
    }
  }

  Future<Invoice> saveInvoice(Invoice invoice) async {
    try {
      final payload = invoice.toFirestoreMap()
        ..remove('paid_amount')
        ..remove('balance');
      final isNew = invoice.id == null;

      final payloadItems = payload['items'];
      final payloadItemsCount = payloadItems is List ? payloadItems.length : -1;
      debugPrint(
        '💽 [SalesService] saveInvoice start | id=${invoice.id ?? 'NEW'} | isNew=$isNew | number=${invoice.invoiceNumber} | payloadItems=$payloadItemsCount | subtotal=${payload['subtotal']} | total=${payload['total']}',
      );

      // Check for duplicate invoice number
      if (invoice.invoiceNumber.isNotEmpty) {
        final existingInvoices = await _databaseService.select(
          _invoicesCollection,
          where: 'invoice_number=${invoice.invoiceNumber}',
        );

        // If we found an invoice with the same number that's NOT this invoice, throw error
        if (existingInvoices.isNotEmpty) {
          final existingId = existingInvoices.first['id'] as String?;
          if (isNew || existingId != invoice.id) {
            throw Exception(
                'Ya existe una factura con el número ${invoice.invoiceNumber}');
          }
        }
      }

      Map<String, dynamic> result;
      if (isNew) {
        // Add tenant_id for new invoices
        final invoiceData = _tenantService.addTenantId(payload);
        final invoiceDataItems = invoiceData['items'];
        final invoiceDataItemsCount =
            invoiceDataItems is List ? invoiceDataItems.length : -1;
        debugPrint(
          '📤 [SalesService] insert invoice | tenantId=${invoiceData['tenant_id']} | items=$invoiceDataItemsCount',
        );
        result =
            await _databaseService.insert(_invoicesCollection, invoiceData);
      } else {
        debugPrint(
          '📤 [SalesService] update invoice | id=${invoice.id} | items=$payloadItemsCount',
        );
        result = await _databaseService.update(
            _invoicesCollection, invoice.id!, payload);
      }

      final resultItems = result['items'];
      final resultItemsCount = resultItems is List ? resultItems.length : -1;
      debugPrint(
        '📥 [SalesService] saveInvoice raw result | id=${result['id']} | items=$resultItemsCount | subtotal=${result['subtotal']} | total=${result['total']} | status=${result['status']}',
      );

      final savedInvoice = Invoice.fromJson(result);
      debugPrint(
        '✅ [SalesService] saveInvoice parsed result | id=${savedInvoice.id ?? 'null'} | itemCount=${savedInvoice.items.length} | subtotal=${savedInvoice.subtotal} | total=${savedInvoice.total}',
      );
      _upsertInvoice(savedInvoice);

      // EXPLICIT SYNC: If this invoice is linked to a pega, sync items back to mechanic_job_items.
      // This is a reliable fallback in addition to the DB trigger (trg_sales_invoices_change).
      // The RPC ignores the flag guards since it runs outside the trigger transaction.
      if (savedInvoice.id != null) {
        try {
          await _databaseService.supabase.rpc(
            'sync_invoice_items_to_job',
            params: {'p_invoice_id': savedInvoice.id},
          );
          debugPrint(
              '🔁 [SalesService] sync_invoice_items_to_job called for ${savedInvoice.id}');
        } catch (e) {
          // Non-fatal: invoice was saved correctly, only pega sync failed
          debugPrint(
              '⚠️ [SalesService] sync_invoice_items_to_job failed (non-fatal): $e');
        }
      }

      // GUARD: Mark this invoice as "just saved" to ignore stale realtime updates for 5s
      if (savedInvoice.id != null) {
        _justSavedInvoiceIds[savedInvoice.id!] = DateTime.now();
        // Clean up old entries
        _justSavedInvoiceIds.removeWhere((key, value) =>
            DateTime.now().difference(value) > const Duration(seconds: 10));
      }

      await _accountingService.initialize();
      await _accountingService.journalEntries.loadJournalEntries();

      invalidateInvoicesCache();
      AccountingDashboardSection.invalidateCache();
      notifyListeners();
      return savedInvoice;
    } catch (e) {
      // Re-throw the exception with the original message if it's already formatted
      if (e.toString().contains('Ya existe una factura')) {
        rethrow;
      }
      throw Exception('No se pudo guardar la factura: $e');
    }
  }

  Future<void> deleteInvoice(String invoiceId) async {
    try {
      await _databaseService.delete(_invoicesCollection, invoiceId);
      _invoices.removeWhere((invoice) => invoice.id == invoiceId);
      invalidateInvoicesCache();
      AccountingDashboardSection.invalidateCache();
      notifyListeners();
    } catch (e) {
      throw Exception('No se pudo eliminar la factura.');
    }
  }

  Future<void> loadPayments(
      {String? invoiceId, bool forceRefresh = false}) async {
    // Return cached data if valid
    if (!forceRefresh &&
        _isCacheValid(_paymentsCacheTime) &&
        _payments.isNotEmpty &&
        invoiceId == null) {
      return;
    }

    if (_isLoadingPayments) return;

    _isLoadingPayments = true;
    _paymentError = null;
    notifyListeners();

    try {
      final data = await _databaseService.select(_paymentsCollection);

      final payments = data.map(Payment.fromJson).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

      _payments
        ..clear()
        ..addAll(payments);
      _paymentsCacheTime = DateTime.now();
      if (invoiceId != null) {
        // Mantener caché completa; las vistas filtrarán por factura según sea necesario.
      }
      _ensureRealtimeSubscriptions();
    } catch (e) {
      _paymentError = 'No se pudieron cargar los pagos.';
    } finally {
      _isLoadingPayments = false;
      notifyListeners();
    }
  }

  /// Manually trigger synchronization of invoice items to a linked job
  /// Useful when linking a job AFTER an invoice has been created/saved
  Future<void> triggerInvoiceSync(String invoiceId) async {
    try {
      await _databaseService.rpc(
        'sync_invoice_items_to_job',
        params: {'p_invoice_id': invoiceId},
      );
      // debugPrint('✅ Manually triggered invoice sync for $invoiceId');
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to trigger invoice sync: $e');
      }
      // Don't rethrow - this is a maintenance op
    }
  }

  /// Trigger the full invoice -> linked job sync after mechanic_jobs.invoice_id
  /// has been written. This is required for newly linked invoices because the
  /// initial save happens before the job points back to the invoice.
  Future<void> triggerLinkedJobSync(String invoiceId) async {
    try {
      await _databaseService.rpc(
        'sync_invoice_items_to_job',
        params: {'p_invoice_id': invoiceId},
      );
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to trigger invoice item sync: $e');
      }
    }

    try {
      await _databaseService.rpc(
        'sync_invoice_status_to_job',
        params: {'p_invoice_id': invoiceId},
      );
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to trigger invoice status sync: $e');
      }
    }
  }

  Future<Payment> registerPayment(Payment payment) async {
    try {
      final payload = payment.toFirestoreMap();
      final isNew = payment.id == null;
      Map<String, dynamic> result;

      if (isNew) {
        result = await _databaseService.insert(_paymentsCollection, payload);
      } else {
        result = await _databaseService.update(
            _paymentsCollection, payment.id!, payload);
      }

      final savedPayment = Payment.fromJson(result);
      _upsertPayment(savedPayment);

      await fetchInvoice(savedPayment.invoiceId, refresh: true);
      await loadPayments(forceRefresh: true);
      await _accountingService.initialize();
      await _accountingService.journalEntries.loadJournalEntries();

      invalidatePaymentsCache();
      invalidateInvoicesCache(); // Invoice balance changes when payment added
      AccountingDashboardSection.invalidateCache();
      notifyListeners();
      return savedPayment;
    } catch (e) {
      // Propagate actual error for debugging
      rethrow;
    }
  }

  Future<void> deletePayment(String paymentId) async {
    try {
      await _databaseService.delete(_paymentsCollection, paymentId);
      _payments.removeWhere((payment) => payment.id == paymentId);
      await _accountingService.initialize();
      await _accountingService.journalEntries.loadJournalEntries();
      invalidatePaymentsCache();
      invalidateInvoicesCache(); // Invoice balance changes when payment deleted
      AccountingDashboardSection.invalidateCache();
      notifyListeners();
    } catch (e) {
      throw Exception('No se pudo eliminar el pago.');
    }
  }

  List<Invoice> searchInvoices(String term) {
    if (term.isEmpty) return invoices;
    final search = term.toLowerCase();
    return _invoices.where((invoice) {
      final customerName = invoice.customerName?.toLowerCase() ?? '';
      final reference = invoice.reference?.toLowerCase() ?? '';
      final invoiceNumber = invoice.invoiceNumber.toLowerCase();
      return customerName.contains(search) ||
          reference.contains(search) ||
          invoiceNumber.contains(search);
    }).toList();
  }

  Future<List<Invoice>> getInvoicesForCustomer({
    required String customerId,
    bool forceRefresh = false,
  }) async {
    List<Invoice> sortCustomerInvoices(Iterable<Invoice> source) {
      final invoices = source
          .where((invoice) => invoice.customerId == customerId)
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      return invoices;
    }

    if (!forceRefresh && _isCacheValid(_invoicesCacheTime)) {
      return sortCustomerInvoices(_invoices);
    }

    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        return [];
      }

      final response = await Supabase.instance.client
          .from(_invoicesCollection)
          .select()
          .eq('tenant_id', tenantId)
          .eq('customer_id', customerId)
          .order('date', ascending: false);

      if ((response as List).isEmpty) {
        return [];
      }

      return response.map((data) => Invoice.fromJson(data)).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
    } catch (e) {
      debugPrint('SalesService.getInvoicesForCustomer error: $e');
      return [];
    }
  }

  /// Get pending invoices for a specific customer
  /// Returns invoices with status 'sent', 'confirmed' and balance > 0
  /// Used for POS invoice payment mode
  Future<List<Invoice>> getPendingInvoices({
    required String customerId,
  }) async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        return [];
      }

      // Query invoices where:
      // - customer_id = customerId
      // - status IN ('sent', 'confirmed') - unpaid invoices
      // - balance > 0
      // - tenant_id = current tenant
      final response = await Supabase.instance.client
          .from(_invoicesCollection)
          .select()
          .eq('tenant_id', tenantId)
          .eq('customer_id', customerId)
          .or('status.eq.sent,status.eq.confirmed')
          .gt('balance', 0)
          .order('date', ascending: false);

      if ((response as List).isEmpty) {
        return [];
      }

      return (response as List)
          .map((data) => Invoice.fromJson(data as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  List<Payment> getPaymentsForInvoice(String invoiceId) {
    return _payments.where((payment) => payment.invoiceId == invoiceId).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<Invoice?> updateInvoiceStatus(
      String invoiceId, InvoiceStatus status) async {
    try {
      final payload = {
        'status': status.name,
      };
      final result = await _databaseService.update(
          _invoicesCollection, invoiceId, payload);
      final updated = Invoice.fromJson(result);
      _upsertInvoice(updated);

      // GUARD: Mark this invoice as "just saved" to ignore stale realtime updates for 5s
      _justSavedInvoiceIds[invoiceId] = DateTime.now();

      await _accountingService.initialize();
      await _accountingService.journalEntries.loadJournalEntries();

      final refreshed = await fetchInvoice(invoiceId, refresh: true);

      if (status == InvoiceStatus.paid) {
        await loadPayments(forceRefresh: true);
      }

      notifyListeners();
      return refreshed ?? updated;
    } catch (e) {
      rethrow;
    }
  }

  void _ensureRealtimeSubscriptions() async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        return;
      }

      final client = Supabase.instance.client;

      // Unsubscribe existing channels first
      await _invoiceChannel?.unsubscribe();
      await _paymentChannel?.unsubscribe();

      _invoiceChannel = client
          .channel('sales_invoices_stream')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: _invoicesCollection,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'tenant_id',
              value: tenantId,
            ),
            callback: _handleInvoiceChange,
          )
          .subscribe();

      _paymentChannel = client
          .channel('sales_payments_stream')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: _paymentsCollection,
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'tenant_id',
              value: tenantId,
            ),
            callback: _handlePaymentChange,
          )
          .subscribe();

      if (!kReleaseMode) {}
    } catch (e) {
      if (!kReleaseMode) {}
    }
  }

  void _handleInvoiceChange(PostgresChangePayload payload) {
    try {
      switch (payload.eventType) {
        case PostgresChangeEvent.insert:
        case PostgresChangeEvent.update:
          final dynamic rawNew = payload.newRecord;
          if (rawNew is Map) {
            final id = rawNew['id']?.toString();
            if (id != null) {
              // Fetch full invoice with all fields (especially items JSONB)

              // GUARD: Skip if this invoice was just saved locally (within 5 seconds)
              // to avoid partial updates overwriting cache with missing data

              // GUARD: Skip if this invoice was just saved locally (within 5 seconds)
              final lastSaved = _justSavedInvoiceIds[id];
              if (lastSaved != null &&
                  DateTime.now().difference(lastSaved) <
                      const Duration(seconds: 5)) {
                return;
              }

              _fetchAndUpdateInvoice(id);
            }
          }
          break;
        case PostgresChangeEvent.delete:
          final dynamic rawOld = payload.oldRecord;
          final id = rawOld is Map ? rawOld['id']?.toString() : null;
          if (id != null) {
            _invoices.removeWhere((element) => element.id == id);
            _debouncedNotify(); // Debounced to prevent spam
          }
          break;
        default:
          break;
      }
    } catch (e) {}
  }

  /// Debounced notifyListeners - prevents excessive UI rebuilds from realtime
  void _debouncedNotify() {
    _realtimeNotifyDebounce?.cancel();
    _realtimeNotifyDebounce = Timer(const Duration(milliseconds: 500), () {
      notifyListeners();
    });
  }

  void _handlePaymentChange(PostgresChangePayload payload) {
    try {
      switch (payload.eventType) {
        case PostgresChangeEvent.insert:
        case PostgresChangeEvent.update:
          final dynamic rawNew = payload.newRecord;
          if (rawNew is Map) {
            final id = rawNew['id']?.toString();
            if (id != null) {
              _fetchAndUpdatePayment(id);
            }
          }
          break;
        case PostgresChangeEvent.delete:
          final dynamic rawOld = payload.oldRecord;
          final id = rawOld is Map ? rawOld['id']?.toString() : null;
          if (id != null) {
            _payments.removeWhere((element) => element.id == id);
            _debouncedNotify(); // Debounced to prevent spam
          }
          break;
        default:
          break;
      }
    } catch (e) {}
  }

  @override
  void dispose() {
    _realtimeNotifyDebounce?.cancel();
    _invoiceChannel?.unsubscribe();
    _paymentChannel?.unsubscribe();
    super.dispose();
  }

  void clearCache() {
    _invoices.clear();
    _payments.clear();
    notifyListeners();
  }

  Future<void> _fetchAndUpdateInvoice(String id) async {
    try {
      final data = await _databaseService.selectById(_invoicesCollection, id);
      if (data != null) {
        final invoice = Invoice.fromJson(data);
        _upsertInvoice(invoice);
        _debouncedNotify();
      }
    } catch (e) {}
  }

  Future<void> _fetchAndUpdatePayment(String id) async {
    try {
      final data = await _databaseService.selectById(_paymentsCollection, id);
      if (data != null) {
        final payment = Payment.fromJson(data);
        _upsertPayment(payment);
        _debouncedNotify();
      }
    } catch (e) {}
  }

  void _upsertInvoice(Invoice invoice) {
    final index = _invoices.indexWhere((element) => element.id == invoice.id);
    if (index >= 0) {
      _invoices[index] = invoice;
    } else {
      _invoices.add(invoice);
      _invoices.sort((a, b) => b.date.compareTo(a.date));
    }
  }

  void _upsertPayment(Payment payment) {
    final index = _payments.indexWhere((element) => element.id == payment.id);
    if (index >= 0) {
      _payments[index] = payment;
    } else {
      _payments.add(payment);
      _payments.sort((a, b) => b.date.compareTo(a.date));
    }
  }
}
