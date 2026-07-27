import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/services/database_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../../shared/models/product.dart' show PurchaseTreatment;
import '../../../shared/models/tax_treatment.dart';
import '../../accounting/services/financial_projection_refresh_coordinator.dart';
import '../../accounting/services/accounting_service.dart';
import '../models/sales_models.dart';

@immutable
class SalesNegativeStockWarning {
  const SalesNegativeStockWarning({
    required this.productName,
    required this.projectedStock,
  });

  final String productName;
  final int projectedStock;
}

String formatSalesNegativeStockWarning(
  List<SalesNegativeStockWarning> warnings,
) {
  final visible = warnings
      .take(2)
      .map((warning) => '${warning.productName} (${warning.projectedStock})')
      .join(', ');
  final remaining = warnings.length - 2;
  return 'Factura confirmada. Stock negativo: $visible'
      '${remaining > 0 ? ' y $remaining más' : ''}.';
}

class _ProjectedStockAccumulator {
  _ProjectedStockAccumulator({required this.name, required this.stock});

  final String name;
  final int stock;
  int required = 0;
}

class SalesInvoiceDeletionException implements Exception {
  const SalesInvoiceDeletionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SalesService extends ChangeNotifier {
  static const _invoicesCollection = 'sales_invoices';
  static const _paymentsCollection = 'sales_payments';

  SalesService(
    this._databaseService,
    this._accountingService,
    this._tenantService, {
    FinancialProjectionRefreshCoordinator? financialProjectionRefresh,
  }) : _financialProjectionRefresh = financialProjectionRefresh ??
            FinancialProjectionRefreshCoordinator.fallback;

  DatabaseService _databaseService;
  AccountingService _accountingService;
  final TenantService _tenantService;
  final FinancialProjectionRefreshCoordinator _financialProjectionRefresh;

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
  bool get isInvoicesCacheFresh => _isCacheValid(_invoicesCacheTime);
  bool get isPaymentsCacheFresh => _isCacheValid(_paymentsCacheTime);

  void _recordFinancialChange(
    FinancialProjectionChangeKind kind, {
    String? entityId,
    String? tenantId,
  }) {
    _financialProjectionRefresh.recordCommitted(
      FinancialProjectionChange(
        kind: kind,
        origin: FinancialProjectionChangeOrigin.localCommit,
        entityId: entityId,
        tenantId: tenantId,
      ),
    );
  }

  /// Non-blocking staff-sales warning. Database posting remains authoritative
  /// and records the exact negative balance in the normal movement/trace flow.
  Future<List<SalesNegativeStockWarning>> previewNegativeStock(
    List<InvoiceItem> items,
  ) async {
    final requestedByProduct = <String, int>{};
    final productNames = <String, String>{};
    for (final item in items) {
      final productId = item.productId;
      if (productId == null ||
          !item.isCatalogProduct ||
          item.isService ||
          item.purchaseTreatment != PurchaseTreatment.inventory) {
        continue;
      }
      final quantity = item.quantity.round();
      if (quantity <= 0) continue;
      requestedByProduct.update(
        productId,
        (current) => current + quantity,
        ifAbsent: () => quantity,
      );
      productNames[productId] = item.productName?.trim().isNotEmpty == true
          ? item.productName!.trim()
          : 'Producto';
    }
    if (requestedByProduct.isEmpty) return const [];

    try {
      final impacts = await Future.wait(
        requestedByProduct.entries.map((entry) async {
          final response = await _databaseService.rpc(
            'preview_product_stock_impact',
            params: {
              'p_product_id': entry.key,
              'p_quantity': entry.value,
            },
          );
          if (response is Map) {
            return Map<String, dynamic>.from(response);
          }
          if (response is List &&
              response.length == 1 &&
              response.first is Map) {
            return Map<String, dynamic>.from(response.first as Map);
          }
          throw const FormatException('Respuesta de stock inválida.');
        }),
      );

      final byPhysicalProduct = <String, _ProjectedStockAccumulator>{};
      for (final impact in impacts) {
        if (impact['tracks_inventory'] == false) continue;
        final productId = impact['product_id']?.toString() ?? '';
        final requested = (impact['requested_quantity'] as num?)?.round() ?? 0;
        final isSet = impact['is_set'] == true;
        final rawComponents = impact['components'];

        if (isSet && rawComponents is List) {
          for (final raw in rawComponents) {
            if (raw is! Map) continue;
            final component = Map<String, dynamic>.from(raw);
            final componentId = component['product_id']?.toString() ?? '';
            if (componentId.isEmpty) continue;
            final required =
                (component['required_quantity'] as num?)?.round() ?? 0;
            final stock = (component['stock_quantity'] as num?)?.round() ?? 0;
            final accumulator = byPhysicalProduct.putIfAbsent(
              componentId,
              () => _ProjectedStockAccumulator(
                name: component['name']?.toString() ?? 'Componente',
                stock: stock,
              ),
            );
            accumulator.required += required;
          }
          continue;
        }

        if (productId.isEmpty) continue;
        final available = (impact['available_quantity'] as num?)?.round() ?? 0;
        final accumulator = byPhysicalProduct.putIfAbsent(
          productId,
          () => _ProjectedStockAccumulator(
            name: productNames[productId] ?? 'Producto',
            stock: available,
          ),
        );
        accumulator.required += requested;
      }

      return byPhysicalProduct.values
          .where((impact) => impact.stock - impact.required < 0)
          .map(
            (impact) => SalesNegativeStockWarning(
              productName: impact.name,
              projectedStock: impact.stock - impact.required,
            ),
          )
          .toList(growable: false);
    } catch (error) {
      debugPrint('Negative-stock preview unavailable (non-blocking): $error');
      return const [];
    }
  }

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
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null || tenantId.isEmpty) {
        throw StateError('No se pudo resolver la empresa activa.');
      }
      final data = await _databaseService.select(
        _invoicesCollection,
        where: 'tenant_id=$tenantId',
        orderBy: 'date',
        descending: true,
        fetchAll: true,
      );
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

  Future<Payment?> fetchPayment(String id, {bool refresh = false}) async {
    if (!refresh) {
      for (final payment in _payments) {
        if (payment.id == id && payment.deletedAt == null) return payment;
      }
    }

    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null || tenantId.isEmpty) {
      throw StateError('No se pudo resolver la empresa activa.');
    }

    final raw = await _databaseService.supabase
        .from(_paymentsCollection)
        .select()
        .eq('tenant_id', tenantId)
        .eq('id', id)
        .isFilter('deleted_at', null)
        .maybeSingle();
    if (raw == null) return null;

    final payment = Payment.fromJson(Map<String, dynamic>.from(raw));
    _upsertPayment(payment);
    notifyListeners();
    return payment;
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

      // The database trigger is the sole invoice -> workshop synchronizer.
      // Calling the RPC again here used to duplicate work and expand the
      // failure window after the invoice transaction had already committed.

      // GUARD: Mark this invoice as "just saved" to ignore stale realtime updates for 5s
      if (savedInvoice.id != null) {
        _justSavedInvoiceIds[savedInvoice.id!] = DateTime.now();
        // Clean up old entries
        _justSavedInvoiceIds.removeWhere((key, value) =>
            DateTime.now().difference(value) > const Duration(seconds: 10));
      }
      _recordFinancialChange(
        FinancialProjectionChangeKind.salesInvoice,
        entityId: savedInvoice.id,
        tenantId: savedInvoice.tenantId,
      );

      await _accountingService.initialize();
      await _accountingService.journalEntries.loadJournalEntries();

      invalidateInvoicesCache();
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

  Future<Invoice> createAtomicCheckout({
    required String source,
    required String checkoutKey,
    required DateTime saleDate,
    required TaxTreatment taxTreatment,
    required List<InvoiceItem> items,
    required List<SalesCheckoutPayment> payments,
    String? customerId,
    String? customerName,
    String? customerRut,
    String? reference,
  }) async {
    final response = await _databaseService.supabase.rpc(
      'create_atomic_sales_checkout',
      params: {
        'p_source': source,
        'p_checkout_key': checkoutKey,
        'p_customer_id': customerId,
        'p_customer_name': customerName,
        'p_customer_rut': customerRut,
        'p_reference': reference,
        'p_tax_treatment': taxTreatment.toValue(),
        'p_items': items
            .map((item) => {
                  'product_id': item.productId,
                  'quantity': item.quantity.round(),
                  'unit_price': item.unitPrice.round(),
                  'discount': item.discount.round(),
                })
            .toList(growable: false),
        'p_payments':
            payments.map((payment) => payment.toJson()).toList(growable: false),
        'p_sale_date': saleDate.toUtc().toIso8601String(),
      },
    );
    final payload = Map<String, dynamic>.from(response as Map);
    final invoiceId = payload['invoice_id']?.toString();
    if (invoiceId == null || invoiceId.isEmpty) {
      throw StateError('El checkout no devolvió una factura válida.');
    }
    _recordFinancialChange(
      FinancialProjectionChangeKind.salesInvoice,
      entityId: invoiceId,
      tenantId: _tenantService.currentTenantId,
    );
    invalidateInvoicesCache();
    invalidatePaymentsCache();
    final invoice = await fetchInvoice(invoiceId, refresh: true);
    if (invoice == null) {
      throw StateError('La factura atómica no pudo volver a cargarse.');
    }
    await loadPayments(forceRefresh: true);
    return invoice;
  }

  Future<void> deleteInvoice(String invoiceId) async {
    late final Map<String, dynamic> currentInvoice;
    try {
      final response = await _databaseService.supabase
          .from(_invoicesCollection)
          .select('id, invoice_number, status')
          .eq('id', invoiceId)
          .maybeSingle();
      if (response == null) {
        throw const SalesInvoiceDeletionException(
          'La factura ya no existe o no está disponible para este negocio.',
        );
      }
      currentInvoice = Map<String, dynamic>.from(response);
    } on SalesInvoiceDeletionException {
      rethrow;
    } catch (_) {
      throw const SalesInvoiceDeletionException(
        'No se pudo verificar el estado actual de la factura. Recarga e inténtalo nuevamente.',
      );
    }

    final invoiceNumber =
        currentInvoice['invoice_number']?.toString().trim().isNotEmpty == true
            ? currentInvoice['invoice_number'].toString().trim()
            : 'seleccionada';
    final currentStatus = InvoiceStatusX.fromName(currentInvoice['status']) ??
        InvoiceStatus.draft;
    if (!currentStatus.canBeDeleted) {
      throw SalesInvoiceDeletionException(
        currentStatus.deletionBlockedMessage(invoiceNumber),
      );
    }

    Map<String, dynamic>? linkedJob;
    try {
      final response = await _databaseService.supabase
          .from('mechanic_jobs')
          .select('id, job_number')
          .eq('invoice_id', invoiceId)
          .maybeSingle();
      if (response != null) {
        linkedJob = Map<String, dynamic>.from(response);
      }
    } catch (_) {
      throw const SalesInvoiceDeletionException(
        'No se pudo verificar si esta factura pertenece a un trabajo. Recarga e inténtalo nuevamente.',
      );
    }

    if (linkedJob != null) {
      final jobNumber = linkedJob['job_number']?.toString().trim();
      final label = jobNumber == null || jobNumber.isEmpty
          ? 'un trabajo de taller'
          : 'el trabajo $jobNumber';
      throw SalesInvoiceDeletionException(
        'Esta factura pertenece a $label y no se puede eliminar por separado. Adminístrala desde la ficha del trabajo.',
      );
    }

    try {
      await _databaseService.delete(_invoicesCollection, invoiceId);
      _invoices.removeWhere((invoice) => invoice.id == invoiceId);
      invalidateInvoicesCache();
      _recordFinancialChange(
        FinancialProjectionChangeKind.salesInvoice,
        entityId: invoiceId,
        tenantId: _tenantService.currentTenantId,
      );
      notifyListeners();
    } on PostgrestException catch (error) {
      if (error.code == '23514') {
        throw SalesInvoiceDeletionException(
          'La factura $invoiceNumber ya no es un borrador eliminable. Recarga la lista y usa su acción de corrección.',
        );
      }
      if (error.code == '23503') {
        throw SalesInvoiceDeletionException(
          'La factura $invoiceNumber está vinculada a otro registro y no se puede eliminar por separado.',
        );
      }
      throw const SalesInvoiceDeletionException(
        'No se pudo eliminar el borrador. Recarga e inténtalo nuevamente.',
      );
    } catch (_) {
      throw const SalesInvoiceDeletionException(
        'No se pudo eliminar el borrador. Recarga e inténtalo nuevamente.',
      );
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
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null || tenantId.isEmpty) {
        throw StateError('No se pudo resolver la empresa activa.');
      }
      final data = await _databaseService.select(
        _paymentsCollection,
        where: 'tenant_id=$tenantId',
        orderBy: 'date',
        descending: true,
        fetchAll: true,
      );

      final payments = data
          .map(Payment.fromJson)
          .where((payment) => payment.deletedAt == null)
          .toList()
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
      if (payment.id != null && payment.id!.isNotEmpty) {
        throw StateError(
          'Los pagos existentes se corrigen mediante el comando auditado.',
        );
      }
      final payload = payment.toFirestoreMap();
      final result =
          await _databaseService.insert(_paymentsCollection, payload);

      final savedPayment = Payment.fromJson(result);
      _upsertPayment(savedPayment);
      _recordFinancialChange(
        FinancialProjectionChangeKind.salesPayment,
        entityId: savedPayment.id,
        tenantId: savedPayment.tenantId,
      );

      await fetchInvoice(savedPayment.invoiceId, refresh: true);
      await loadPayments(forceRefresh: true);
      await _accountingService.initialize();
      await _accountingService.journalEntries.loadJournalEntries();

      invalidatePaymentsCache();
      invalidateInvoicesCache(); // Invoice balance changes when payment added
      notifyListeners();
      return savedPayment;
    } on PostgrestException catch (e) {
      if (_isPaymentIdempotencyConflict(e) && payment.idempotencyKey != null) {
        final existing = await _findPaymentByIdempotencyKey(payment);
        if (existing != null) {
          _upsertPayment(existing);
          _recordFinancialChange(
            FinancialProjectionChangeKind.salesPayment,
            entityId: existing.id,
            tenantId: existing.tenantId,
          );
          await fetchInvoice(existing.invoiceId, refresh: true);
          await loadPayments(forceRefresh: true);
          invalidatePaymentsCache();
          invalidateInvoicesCache();
          notifyListeners();
          return existing;
        }
      }
      rethrow;
    } catch (e) {
      // Propagate actual error for debugging
      rethrow;
    }
  }

  /// Registers a sales payment and applies the payment-terminal tax choice to
  /// the whole invoice in the same database transaction.
  ///
  /// Revenue and IVA remain invoice-owned; the payment journal only settles
  /// accounts receivable. The RPC also posts draft/sent invoices before cash
  /// settlement and protects retries with [Payment.idempotencyKey].
  Future<Payment> registerPaymentWithInvoiceTax(
    Payment payment,
    TaxTreatment taxTreatment,
  ) async {
    final idempotencyKey = payment.idempotencyKey?.trim();
    if (idempotencyKey == null || idempotencyKey.isEmpty) {
      throw ArgumentError('El pago requiere una clave idempotente.');
    }

    try {
      final response = await _databaseService.supabase.rpc(
        'register_sales_payment_with_invoice_tax',
        params: {
          'p_invoice_id': payment.invoiceId,
          'p_payment_method_id': payment.paymentMethodId,
          'p_idempotency_key': idempotencyKey,
          'p_amount': payment.amount.round(),
          'p_date': payment.date.toUtc().toIso8601String(),
          'p_reference': payment.reference,
          'p_notes': payment.notes,
          'p_tax_treatment': taxTreatment.toValue(),
        },
      );

      final payload = Map<String, dynamic>.from(response as Map);
      final rawPayment = payload['payment'];
      if (rawPayment is! Map) {
        throw StateError('El comando de pago no devolvió un pago válido.');
      }

      final savedPayment = Payment.fromJson(
        Map<String, dynamic>.from(rawPayment),
      );
      _upsertPayment(savedPayment);
      _recordFinancialChange(
        FinancialProjectionChangeKind.salesPayment,
        entityId: savedPayment.id,
        tenantId: savedPayment.tenantId,
      );
      await fetchInvoice(savedPayment.invoiceId, refresh: true);
      await loadPayments(forceRefresh: true);
      await _accountingService.initialize();
      await _accountingService.journalEntries.loadJournalEntries();
      invalidateInvoicesCache();
      invalidatePaymentsCache();
      notifyListeners();
      return savedPayment;
    } catch (e) {
      throw Exception('No se pudo registrar el pago: $e');
    }
  }

  /// Applies an explicit correction to an existing payment through the
  /// database-owned accounting command. The command preserves the payment and
  /// invoice identities, checks optimistic concurrency, records the reason and
  /// rebuilds settlement evidence only when a financial field changed.
  Future<SalesPaymentCorrectionResult> correctSalesPayment({
    required Payment current,
    required String paymentMethodId,
    required double amount,
    required DateTime date,
    required String? reference,
    required String? notes,
    required String reason,
    String? operationKey,
  }) async {
    final paymentId = current.id;
    if (paymentId == null || paymentId.isEmpty) {
      throw ArgumentError('El pago no tiene una identidad persistida.');
    }

    final key = operationKey?.trim().isNotEmpty == true
        ? operationKey!.trim()
        : const Uuid().v4();
    final params = <String, dynamic>{
      'p_payment_id': paymentId,
      'p_expected_updated_at': current.updatedAt.toUtc().toIso8601String(),
      'p_operation_key': key,
      'p_payment_method_id': paymentMethodId,
      'p_amount': amount.round(),
      'p_date': date.toUtc().toIso8601String(),
      'p_reference': _blankToNull(reference),
      'p_notes': _blankToNull(notes),
      'p_reason': reason.trim(),
    };

    dynamic raw;
    try {
      raw = await _databaseService.rpc(
        'correct_sales_payment',
        params: params,
      );
    } catch (error, stackTrace) {
      if (!_isOutcomeAmbiguous(error)) rethrow;
      try {
        raw = await _databaseService.rpc(
          'get_sales_payment_edit_operation',
          params: {'p_operation_key': key},
        );
      } catch (_) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      if (raw == null) Error.throwWithStackTrace(error, stackTrace);
    }

    final result = _parsePaymentCorrectionResult(raw);
    _upsertPayment(result.payment);
    invalidateInvoicesCache();
    invalidatePaymentsCache();
    _recordFinancialChange(
      FinancialProjectionChangeKind.salesPayment,
      entityId: result.payment.id,
      tenantId: result.payment.tenantId,
    );
    notifyListeners();

    // The correction is already committed and acknowledged at this point.
    // Cache/accounting refresh failures must not turn that durable success into
    // a false save failure or invite a second correction attempt.
    try {
      await fetchInvoice(result.payment.invoiceId, refresh: true);
      await loadPayments(forceRefresh: true);
      await _accountingService.initialize();
      await _accountingService.journalEntries.loadJournalEntries();
    } catch (error) {
      debugPrint(
        'SalesService.correctSalesPayment post-commit refresh failed: $error',
      );
    }
    return result;
  }

  Future<List<SalesPaymentEditEvent>> loadPaymentEditEvents(
    String paymentId,
  ) async {
    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null || tenantId.isEmpty) return const [];

    final response = await _databaseService.supabase
        .from('sales_payment_edit_events')
        .select()
        .eq('tenant_id', tenantId)
        .eq('payment_id', paymentId)
        .order('created_at', ascending: false);
    return (response as List)
        .map((row) => SalesPaymentEditEvent.fromJson(
              Map<String, dynamic>.from(row as Map),
            ))
        .toList(growable: false);
  }

  SalesPaymentCorrectionResult _parsePaymentCorrectionResult(dynamic raw) {
    if (raw is! Map || raw['payment'] is! Map || raw['event'] is! Map) {
      throw StateError('La respuesta de corrección del pago es inválida.');
    }
    final payment = Payment.fromJson(
      Map<String, dynamic>.from(raw['payment'] as Map),
    );
    final event = SalesPaymentEditEvent.fromJson(
      Map<String, dynamic>.from(raw['event'] as Map),
    );
    return SalesPaymentCorrectionResult(
      payment: payment,
      event: event,
      replayed: raw['replayed'] == true,
      financialFieldsChanged: raw['financial_fields_changed'] == true ||
          event.financialFieldsChanged,
    );
  }

  bool _isOutcomeAmbiguous(Object error) {
    return error is! PostgrestException ||
        error.code == null ||
        error.code!.isEmpty;
  }

  String? _blankToNull(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  bool _isPaymentIdempotencyConflict(PostgrestException error) {
    final details = error.details?.toString() ?? '';
    return error.code == '23505' &&
        (error.message.contains('idempotency') ||
            details.contains('idempotency'));
  }

  Future<Payment?> _findPaymentByIdempotencyKey(Payment payment) async {
    final data = await Supabase.instance.client
        .from(_paymentsCollection)
        .select()
        .eq('tenant_id', payment.tenantId)
        .eq('idempotency_key', payment.idempotencyKey!)
        .maybeSingle();

    if (data == null) {
      return null;
    }

    return Payment.fromJson(Map<String, dynamic>.from(data));
  }

  Future<void> deletePayment(String paymentId) async {
    try {
      await _databaseService.delete(_paymentsCollection, paymentId);
      _payments.removeWhere((payment) => payment.id == paymentId);
      _recordFinancialChange(
        FinancialProjectionChangeKind.salesPayment,
        entityId: paymentId,
        tenantId: _tenantService.currentTenantId,
      );
      await _accountingService.initialize();
      await _accountingService.journalEntries.loadJournalEntries();
      invalidatePaymentsCache();
      invalidateInvoicesCache(); // Invoice balance changes when payment deleted
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
    return _payments
        .where((payment) =>
            payment.invoiceId == invoiceId && payment.deletedAt == null)
        .toList()
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
      _recordFinancialChange(
        FinancialProjectionChangeKind.salesInvoice,
        entityId: invoiceId,
        tenantId: updated.tenantId,
      );

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
        if (payment.deletedAt != null) {
          _payments.removeWhere((element) => element.id == payment.id);
          _debouncedNotify();
          return;
        }
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
    if (payment.deletedAt != null) {
      _payments.removeWhere((element) => element.id == payment.id);
      return;
    }

    final index = _payments.indexWhere((element) => element.id == payment.id);
    if (index >= 0) {
      _payments[index] = payment;
    } else {
      _payments.add(payment);
      _payments.sort((a, b) => b.date.compareTo(a.date));
    }
  }
}
