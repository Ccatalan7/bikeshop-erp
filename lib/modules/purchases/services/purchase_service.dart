import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/models/supplier.dart' as shared_supplier;
import '../../../shared/models/supplier_ocr_template.dart';
import '../../../shared/models/tax_treatment.dart';
import '../../../shared/services/authority_scoped_cache.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../accounting/services/accounting_service.dart';
import '../../accounting/services/financial_projection_refresh_coordinator.dart';
import '../models/legacy_supplier_adapter.dart';
import '../models/purchase_invoice.dart';
import '../models/purchase_payment.dart';
import '../models/supplier_foundation.dart';
import 'supplier_relationship_service.dart';

@visibleForTesting
class SupplierCommandRetryLedger {
  SupplierCommandRetryLedger({String Function()? newOperationId})
      : _newOperationId = newOperationId ?? (() => const Uuid().v4());

  final String Function() _newOperationId;
  final Map<String, String> _operationIds = {};

  String retain(String requestFingerprint) =>
      _operationIds.putIfAbsent(requestFingerprint, _newOperationId);

  void complete(String requestFingerprint, String operationId) {
    if (_operationIds[requestFingerprint] == operationId) {
      _operationIds.remove(requestFingerprint);
    }
  }

  void clear() => _operationIds.clear();
}

class PurchaseService extends ChangeNotifier {
  PurchaseService(
    this._db,
    this._tenantService, {
    FinancialProjectionRefreshCoordinator? financialProjectionRefresh,
    SupplierRelationshipService? supplierRelationshipService,
  })  : _financialProjectionRefresh = financialProjectionRefresh ??
            FinancialProjectionRefreshCoordinator.fallback,
        _supplierRelationshipService = supplierRelationshipService ??
            SupplierRelationshipService(tenantService: _tenantService);

  final DatabaseService _db;
  final TenantService _tenantService;
  final FinancialProjectionRefreshCoordinator _financialProjectionRefresh;
  final SupplierRelationshipService _supplierRelationshipService;
  static AccountingService? _accountingService;

  // Helper to get Supabase client
  SupabaseClient get _supabase => Supabase.instance.client;

  List<shared_supplier.Supplier> _supplierCache = const [];
  List<PurchaseInvoice> _invoiceCache = const [];
  List<PurchaseInvoice> _listInvoiceCache = const [];
  List<PurchasePayment> _paymentCache = const [];
  bool _suppliersLoaded = false;
  bool _invoicesLoaded = false;
  bool _paymentsLoaded = false;
  bool _isLoadingListInvoices = false;
  final AuthorityCacheScope _supplierCacheScope = AuthorityCacheScope();
  final SupplierCommandRetryLedger _supplierCreateRetries =
      SupplierCommandRetryLedger();
  final SupplierCommandRetryLedger _supplierOcrRetries =
      SupplierCommandRetryLedger();
  late final AuthorityScopedLoad<List<shared_supplier.Supplier>>
      _suppliersLoad =
      AuthorityScopedLoad<List<shared_supplier.Supplier>>(_supplierCacheScope);

  // ============================================================
  // CACHING - TTL-based cache for performance optimization
  // ============================================================
  DateTime? _suppliersCacheTime;
  DateTime? _invoicesCacheTime;
  DateTime? _listInvoicesCacheTime;
  DateTime? _paymentsCacheTime;
  static const Duration _cacheMaxAge = Duration(minutes: 5);

  // Public getters for cached data (instant UI access)
  List<shared_supplier.Supplier> get cachedSuppliers =>
      List.unmodifiable(_supplierCache);
  List<PurchaseInvoice> get cachedInvoices => List.unmodifiable(_invoiceCache);
  List<PurchaseInvoice> get cachedListInvoices =>
      List.unmodifiable(_listInvoiceCache);
  List<PurchasePayment> get cachedPayments => List.unmodifiable(_paymentCache);
  bool get hasSuppliersCache =>
      _supplierCache.isNotEmpty && _suppliersCacheTime != null;
  bool get hasInvoicesCache =>
      _invoiceCache.isNotEmpty && _invoicesCacheTime != null;
  bool get hasListInvoicesCache =>
      _listInvoiceCache.isNotEmpty && _listInvoicesCacheTime != null;
  bool get hasPaymentsCache =>
      _paymentCache.isNotEmpty && _paymentsCacheTime != null;
  ErpAuthorityScopeKey? get supplierAuthorityScope => _supplierCacheScope.key;

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

  /// Check if cache is still valid
  bool _isCacheValid(DateTime? cacheTime) {
    if (cacheTime == null) return false;
    return DateTime.now().difference(cacheTime) < _cacheMaxAge;
  }

  /// Invalidate supplier cache (call after create/update/delete)
  void invalidateSuppliersCache() {
    _supplierCacheScope.invalidate();
    _suppliersLoad.detach();
    _suppliersCacheTime = null;
    _suppliersLoaded = false;
    debugPrint('🗑️ [PurchaseService] Suppliers cache invalidated');
  }

  void bindSupplierAuthorityScope({
    required String? userId,
    required String? tenantId,
  }) {
    if (!_supplierCacheScope.bind(userId: userId, tenantId: tenantId)) return;
    _clearSupplierAuthorityOwnedState();
  }

  AuthorityScopeResolution _resolveSupplierAuthorityScope({
    required String? userId,
    required String? tenantId,
  }) {
    final resolution = _supplierCacheScope.resolve(
      userId: userId,
      tenantId: tenantId,
    );
    if (resolution.didChange) _clearSupplierAuthorityOwnedState();
    return resolution;
  }

  void _clearSupplierAuthorityOwnedState() {
    final hadCache = _supplierCache.isNotEmpty;
    _suppliersLoad.detach();
    _supplierCache = const [];
    _supplierCreateRetries.clear();
    _supplierOcrRetries.clear();
    _suppliersCacheTime = null;
    _suppliersLoaded = false;
    if (hadCache) notifyListeners();
  }

  Future<bool> _ensureSupplierAuthorityScope() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      _resolveSupplierAuthorityScope(userId: null, tenantId: null);
      return false;
    }

    final tenantId = await _tenantService.getTenantId();
    if (_supabase.auth.currentUser?.id != userId) return false;
    if (tenantId == null || tenantId.isEmpty) {
      _resolveSupplierAuthorityScope(userId: null, tenantId: null);
      return false;
    }
    final resolution = _resolveSupplierAuthorityScope(
      userId: userId,
      tenantId: tenantId,
    );
    if (resolution == AuthorityScopeResolution.rejectedTenantChange) {
      throw const AuthorityScopeChangedException();
    }
    return resolution.isAccepted;
  }

  Future<AuthorityCacheLease> _requireSupplierAuthorityLease() async {
    if (!await _ensureSupplierAuthorityScope()) {
      throw const AuthorityScopeChangedException();
    }
    final lease = _supplierCacheScope.capture();
    if (lease == null) throw const AuthorityScopeChangedException();
    return lease;
  }

  /// Invalidate invoice cache (call after create/update/delete)
  void invalidateInvoicesCache() {
    _invoicesCacheTime = null;
    _listInvoicesCacheTime = null;
    _invoicesLoaded = false;
    debugPrint('🗑️ [PurchaseService] Invoices cache invalidated');
  }

  PurchaseInvoice _toListPreviewInvoice(PurchaseInvoice invoice) {
    return PurchaseInvoice(
      id: invoice.id,
      tenantId: invoice.tenantId,
      invoiceNumber: invoice.invoiceNumber,
      supplierId: invoice.supplierId,
      supplierName: invoice.supplierName,
      supplierRut: invoice.supplierRut,
      date: invoice.date,
      dueDate: invoice.dueDate,
      reference: invoice.reference,
      status: invoice.status,
      subtotal: invoice.subtotal,
      ivaAmount: invoice.ivaAmount,
      total: invoice.total,
      taxTreatment: invoice.taxTreatment,
      netAmount: invoice.netAmount,
      discountType: invoice.discountType,
      discountValue: invoice.discountValue,
      discountAmount: invoice.discountAmount,
      isDiscountBeforeTax: invoice.isDiscountBeforeTax,
      items: invoice.items,
      createdAt: invoice.createdAt,
      updatedAt: invoice.updatedAt,
      prepaymentModel: invoice.prepaymentModel,
      sentDate: invoice.sentDate,
      confirmedDate: invoice.confirmedDate,
      receivedDate: invoice.receivedDate,
      paidDate: invoice.paidDate,
      supplierInvoiceNumber: invoice.supplierInvoiceNumber,
      supplierInvoiceDate: invoice.supplierInvoiceDate,
      paidAmount: invoice.paidAmount,
      creditedAmount: invoice.creditedAmount,
      supplierCreditBalance: invoice.supplierCreditBalance,
      receiptFulfillment: invoice.receiptFulfillment,
      balance: invoice.balance,
    );
  }

  void _upsertInvoice(PurchaseInvoice invoice) {
    final fullInvoices = List<PurchaseInvoice>.from(_invoiceCache);
    final fullIndex = fullInvoices.indexWhere((inv) => inv.id == invoice.id);
    if (fullIndex >= 0) {
      fullInvoices[fullIndex] = invoice;
    } else {
      fullInvoices.add(invoice);
    }
    fullInvoices.sort((a, b) => b.date.compareTo(a.date));
    _invoiceCache = fullInvoices;

    final listInvoices = List<PurchaseInvoice>.from(_listInvoiceCache);
    final listIndex = listInvoices.indexWhere((inv) => inv.id == invoice.id);
    final existingFulfillment =
        listIndex >= 0 ? listInvoices[listIndex].receiptFulfillment : null;
    final authoritativeFulfillment =
        invoice.receiptFulfillment ?? existingFulfillment;

    // The list cache is owned by purchase_invoice_list_read_model. A full
    // purchase_invoices fetch does not contain physical receiving state, so it
    // must never introduce a financial-only row that will be corrected a frame
    // later. It may refresh an existing authoritative row only while preserving
    // that row's fulfillment snapshot.
    if (authoritativeFulfillment != null) {
      final previewInvoice = _toListPreviewInvoice(
        invoice.copyWith(receiptFulfillment: authoritativeFulfillment),
      );
      if (listIndex >= 0) {
        listInvoices[listIndex] = previewInvoice;
      } else {
        listInvoices.add(previewInvoice);
      }
    } else if (listIndex >= 0) {
      listInvoices.removeAt(listIndex);
      _listInvoicesCacheTime = null;
    }
    listInvoices.sort((a, b) => b.date.compareTo(a.date));
    _listInvoiceCache = listInvoices;
  }

  void _upsertPayment(PurchasePayment payment) {
    final payments = List<PurchasePayment>.from(_paymentCache);
    final index = payments.indexWhere((item) => item.id == payment.id);
    if (index >= 0) {
      payments[index] = payment;
    } else {
      payments.add(payment);
    }
    payments.sort((a, b) => b.date.compareTo(a.date));
    _paymentCache = payments;
  }

  /// Invalidate payment cache (call after create/update/delete)
  void invalidatePaymentsCache() {
    _paymentsCacheTime = null;
    _paymentsLoaded = false;
    debugPrint('🗑️ [PurchaseService] Payments cache invalidated');
  }

  // Pending data from smart purchase list
  String? _pendingSupplierId;
  List<Map<String, dynamic>>? _pendingLineItems;

  // Realtime channels
  RealtimeChannel? _purchaseInvoicesChannel;
  RealtimeChannel? _purchasePaymentsChannel;
  RealtimeChannel? _purchaseReceivingChannel;

  // Public getters for reactive UI
  UnmodifiableListView<PurchaseInvoice> get purchaseInvoices =>
      UnmodifiableListView(_invoiceCache);
  UnmodifiableListView<PurchaseInvoice> get listInvoices =>
      UnmodifiableListView(_listInvoiceCache);
  bool get isLoadingListInvoices => _isLoadingListInvoices;

  static void setAccountingService(AccountingService accountingService) {
    _accountingService = accountingService;
  }

  // Store data from smart purchase list to be picked up by form page
  void setPendingSmartPurchaseData({
    String? supplierId,
    List<Map<String, dynamic>>? lineItems,
  }) {
    _pendingSupplierId = supplierId;
    _pendingLineItems = lineItems;
    debugPrint(
        '📦 PurchaseService: Stored pending data - supplier: $supplierId, items: ${lineItems?.length}');
  }

  // Retrieve and clear pending data (consume once)
  Map<String, dynamic>? consumePendingSmartPurchaseData() {
    if (_pendingSupplierId == null && _pendingLineItems == null) {
      return null;
    }

    final data = {
      'supplierId': _pendingSupplierId,
      'lineItems': _pendingLineItems,
    };

    // Clear after consuming
    _pendingSupplierId = null;
    _pendingLineItems = null;

    debugPrint('📦 PurchaseService: Consumed pending data');
    return data;
  }

  Future<List<shared_supplier.Supplier>> getSuppliers({
    bool forceRefresh = false,
    bool activeOnly = false,
  }) async {
    if (!await _ensureSupplierAuthorityScope()) {
      throw const AuthorityScopeChangedException();
    }
    // Return cached data if valid
    if (!forceRefresh &&
        _isCacheValid(_suppliersCacheTime) &&
        _supplierCache.isNotEmpty) {
      debugPrint(
          '📦 [PurchaseService] Using cached suppliers (${_supplierCache.length} items)');
      return activeOnly
          ? _supplierCache.where((s) => s.isActive).toList()
          : _supplierCache;
    }
    try {
      final suppliers = await _suppliersLoad.run(
        load: (lease) async {
          final data = await _db.select(
            'suppliers',
            selectColumns: shared_supplier.Supplier.secretFreeSelect,
            orderBy: 'id',
            fetchAll: true,
          );
          final loadedSuppliers = data
              .map((row) => shared_supplier.Supplier.fromJson(row))
              .toList();
          if (loadedSuppliers.any(
            (supplier) => supplier.tenantId != lease.scope.tenantId,
          )) {
            throw StateError(
              'Supplier query returned data outside the authority tenant',
            );
          }
          loadedSuppliers.sort((a, b) {
            final byName = a.name.compareTo(b.name);
            return byName != 0 ? byName : a.id.compareTo(b.id);
          });
          return loadedSuppliers;
        },
        publish: (loadedSuppliers, _) {
          _supplierCache = loadedSuppliers;
          _suppliersLoaded = true;
          _suppliersCacheTime = DateTime.now();
          debugPrint(
            '✅ [PurchaseService] Cached ${_supplierCache.length} suppliers',
          );
          notifyListeners();
        },
      );
      return activeOnly
          ? suppliers.where((supplier) => supplier.isActive).toList()
          : suppliers;
    } on AuthorityScopeChangedException {
      rethrow;
    } catch (e) {
      throw Exception('No se pudieron cargar los proveedores: $e');
    }
  }

  Future<shared_supplier.Supplier?> getSupplier(String id) async {
    if (id.isEmpty) return null;
    if (!await _ensureSupplierAuthorityScope()) {
      throw const AuthorityScopeChangedException();
    }
    if (!_suppliersLoaded) {
      await getSuppliers(forceRefresh: true);
    }
    try {
      return _supplierCache.firstWhere((supplier) => supplier.id == id);
    } catch (_) {}

    try {
      final data = await _db.selectById(
        'suppliers',
        id,
        selectColumns: shared_supplier.Supplier.secretFreeSelect,
      );
      if (data == null) return null;
      return shared_supplier.Supplier.fromJson(data);
    } catch (e) {
      debugPrint('PurchaseService: error obteniendo proveedor $id -> $e');
      return null;
    }
  }

  Future<shared_supplier.Supplier> createSupplier(String name) async {
    try {
      final lease = await _requireSupplierAuthorityLease();
      final tenantId = lease.scope.tenantId;
      final displayName = name.trim();
      if (displayName.isEmpty) {
        throw ArgumentError.value(name, 'name', 'Supplier name is required');
      }

      // Quick-create intentionally does not infer role, accounting behavior or
      // IVA from the screen that happened to create the counterparty. Those
      // dimensions stay open for the supplier profile to define explicitly.
      final provisionalPartyId = const Uuid().v4();
      final retryKey = displayName.toLowerCase();
      final operationId = _supplierCreateRetries.retain(retryKey);
      final result = await _supplierRelationshipService.saveProfile(
        SaveSupplierRelationshipProfileCommand(
          operationId: operationId,
          party: ExternalParty(
            id: provisionalPartyId,
            tenantId: tenantId,
            kind: ExternalPartyKind.other,
            name: displayName,
          ),
          relationship: SupplierRelationship(
            id: provisionalPartyId,
            tenantId: tenantId,
            externalPartyId: provisionalPartyId,
            name: displayName,
            status: SupplierRelationshipStatus.active,
          ),
          defaultTaxTreatment: TaxTreatment.noTax,
        ),
      );
      final supplier = LegacySupplierAdapter.toLegacy(result.profile);
      if (supplier.tenantId != tenantId) {
        throw StateError(
          'Supplier command returned data outside the authority tenant',
        );
      }
      _supplierCreateRetries.complete(retryKey, operationId);
      if (_supplierCacheScope.owns(lease)) {
        invalidateSuppliersCache();
        notifyListeners();
      }
      return supplier;
    } catch (e) {
      throw Exception('No se pudo crear el proveedor: $e');
    }
  }

  Future<shared_supplier.Supplier> updateSupplierOcrTemplate({
    required shared_supplier.Supplier supplier,
    required SupplierOcrTemplate template,
  }) async {
    try {
      final lease = await _requireSupplierAuthorityLease();
      final tenantId = lease.scope.tenantId;
      if (supplier.tenantId != tenantId || supplier.id.isEmpty) {
        throw const AuthorityScopeChangedException();
      }
      final retryKey = [
        supplier.id,
        supplier.updatedAt.toUtc().toIso8601String(),
        template.enabled,
        template.discountParser.name,
      ].join('|');
      final operationId = _supplierOcrRetries.retain(retryKey);
      final result = await _supplierRelationshipService.updateOcrTemplate(
        UpdateSupplierOcrTemplateCommand(
          operationId: operationId,
          supplierId: supplier.id,
          expectedUpdatedAt: supplier.updatedAt,
          template: template,
        ),
      );
      if (result.tenantId != tenantId || result.supplierId != supplier.id) {
        throw const AuthorityScopeChangedException();
      }
      _supplierOcrRetries.complete(retryKey, operationId);
      final updated = supplier.copyWith(
        tenantId: tenantId,
        ocrTemplate: result.template,
        updatedAt: result.updatedAt,
      );
      if (!_supplierCacheScope.owns(lease)) return updated;
      _supplierCache = _supplierCache
          .map((item) => item.id == updated.id ? updated : item)
          .toList(growable: false);
      _suppliersCacheTime = DateTime.now();
      notifyListeners();
      return updated;
    } catch (e) {
      throw Exception('No se pudo actualizar la plantilla OCR: $e');
    }
  }

  Future<List<PurchaseInvoice>> getPurchaseInvoices(
      {bool forceRefresh = false}) async {
    // Return cached data if valid
    if (!forceRefresh &&
        _isCacheValid(_invoicesCacheTime) &&
        _invoiceCache.isNotEmpty) {
      debugPrint(
          '📦 [PurchaseService] Using cached invoices (${_invoiceCache.length} items)');
      return _invoiceCache;
    }
    try {
      final data = await _db.select('purchase_invoices');
      _invoiceCache = data.map((row) => PurchaseInvoice.fromJson(row)).toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      _invoicesLoaded = true;
      _invoicesCacheTime = DateTime.now();
      debugPrint('✅ [PurchaseService] Cached ${_invoiceCache.length} invoices');
      _setupPurchaseRealtime(); // Setup realtime after first load
      notifyListeners(); // Notify UI to rebuild after loading invoices
      return _invoiceCache;
    } catch (e) {
      throw Exception('No se pudieron cargar las facturas de compra: $e');
    }
  }

  Future<List<PurchaseInvoice>> getPurchaseInvoicesForList(
      {bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _isCacheValid(_listInvoicesCacheTime) &&
        _listInvoiceCache.isNotEmpty) {
      debugPrint(
          '📦 [PurchaseService] Using cached purchase invoice list preview (${_listInvoiceCache.length} items)');
      return _listInvoiceCache;
    }

    if (_isLoadingListInvoices) {
      return _listInvoiceCache;
    }

    _isLoadingListInvoices = true;
    notifyListeners();

    try {
      final data = await _db.select(
        'purchase_invoice_list_read_model',
        selectColumns: PurchaseInvoice.listReadModelSelect,
        fetchAll: true,
      );
      _listInvoiceCache = data
          .map((row) => PurchaseInvoice.fromJson(row))
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      _listInvoicesCacheTime = DateTime.now();
      debugPrint(
          '✅ [PurchaseService] Cached ${_listInvoiceCache.length} purchase invoice list preview rows');
      _setupPurchaseRealtime();
      return _listInvoiceCache;
    } catch (e) {
      throw Exception('No se pudieron cargar las facturas de compra: $e');
    } finally {
      _isLoadingListInvoices = false;
      notifyListeners();
    }
  }

  Future<List<PurchaseInvoice>> getInvoicesBySupplier(String supplierId) async {
    try {
      final List<dynamic> data = await _supabase
          .from('purchase_invoices')
          .select()
          .eq('tenant_id', await _tenantService.getTenantId() ?? '')
          .eq('supplier_id', supplierId)
          .order('date', ascending: false);
      return data.map((row) => PurchaseInvoice.fromJson(row)).toList();
    } catch (e) {
      debugPrint('Error getting invoices for supplier: $e');
      return [];
    }
  }

  Future<PurchaseInvoice?> getPurchaseInvoice(String id,
      {bool refresh = false}) async {
    try {
      if (!refresh) {
        for (final invoice in _invoiceCache) {
          if (invoice.id == id) return invoice;
        }
      }

      final data = await _db.selectById('purchase_invoices', id);
      if (data == null) return null;
      final invoice = PurchaseInvoice.fromJson(data);
      _upsertInvoice(invoice);
      return invoice;
    } catch (e) {
      throw Exception('No se pudo obtener la factura: $e');
    }
  }

  Future<PurchaseInvoice?> fetchPurchaseInvoice(String id,
      {bool refresh = false}) {
    return getPurchaseInvoice(id, refresh: refresh);
  }

  /// Check if an invoice number already exists (for duplicate detection)
  /// Returns the existing invoice if found, null otherwise
  /// [excludeId] - Exclude this invoice ID from the check (for editing existing invoices)
  Future<PurchaseInvoice?> checkInvoiceNumberExists(
    String invoiceNumber, {
    String? excludeId,
  }) async {
    if (invoiceNumber.isEmpty) return null;

    try {
      // Ensure cache is loaded
      if (!_invoicesLoaded || _invoiceCache.isEmpty) {
        await getPurchaseInvoices(forceRefresh: true);
      }

      // Check cached invoices for duplicate
      final normalizedNumber = invoiceNumber.trim().toLowerCase();
      for (final invoice in _invoiceCache) {
        if (invoice.id == excludeId) continue; // Skip the invoice being edited
        if (invoice.invoiceNumber.trim().toLowerCase() == normalizedNumber) {
          debugPrint(
              '⚠️ Duplicate invoice number found: $invoiceNumber (ID: ${invoice.id})');
          return invoice;
        }
      }

      return null; // No duplicate found
    } catch (e) {
      debugPrint('Error checking invoice number: $e');
      return null;
    }
  }

  Future<PurchaseInvoice> savePurchaseInvoice(PurchaseInvoice invoice) async {
    try {
      PurchaseInvoice saved;
      if (invoice.id == null) {
        final payload = invoice.toJson()..remove('id');
        // Add tenant_id for new invoices
        final invoiceData = _tenantService.addTenantId(payload);
        final result = await _db.insert('purchase_invoices', invoiceData);
        saved = PurchaseInvoice.fromJson(result);
      } else {
        final payload = invoice.toJson();
        payload.remove('created_at');
        await _db.update('purchase_invoices', invoice.id!, payload);
        final refreshed = await getPurchaseInvoice(invoice.id!);
        saved = refreshed ?? invoice;
      }

      _recordFinancialChange(
        FinancialProjectionChangeKind.purchaseInvoice,
        entityId: saved.id,
        tenantId: saved.tenantId,
      );
      invalidateInvoicesCache();
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
    debugPrint('🗑️ DELETE PURCHASE INVOICE CALLED - ID: $id');

    try {
      final client = Supabase.instance.client;

      // The database permits deletion only for drafts. Posted accounting and
      // inventory evidence is reversed through document commands, never erased
      // by the client.
      debugPrint('🗑️ Deleting purchase invoice from database...');
      final response = await client
          .from('purchase_invoices')
          .delete()
          .eq('id', id)
          .select(); // Request response to verify deletion

      debugPrint('📊 Delete response: $response');
      debugPrint('✅ Purchase invoice deleted from database');

      // Clear cache and reload
      debugPrint('🔄 Clearing cache and refreshing invoice list...');
      invalidateInvoicesCache();
      _recordFinancialChange(
        FinancialProjectionChangeKind.purchaseInvoice,
        entityId: id,
        tenantId: _tenantService.currentTenantId,
      );
      _invoiceCache = const []; // Clear cache
      _invoicesLoaded = false;
      await getPurchaseInvoices(forceRefresh: true);
      debugPrint('🔔 Notifying listeners...');
      notifyListeners();
      debugPrint('✅ DELETE COMPLETE!');
    } catch (e) {
      debugPrint('❌ DELETE ERROR: $e');
      rethrow;
    }
  }

  /// Update the status of a purchase invoice
  /// This triggers database triggers for inventory and accounting
  Future<PurchaseInvoice?> updateInvoiceStatus(
    String invoiceId,
    PurchaseInvoiceStatus status,
  ) async {
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final payload = {
        'status': status.name,
        'updated_at': now,
      };

      // Set the appropriate workflow date field based on status
      switch (status) {
        case PurchaseInvoiceStatus.sent:
          payload['sent_date'] = now;
          break;
        case PurchaseInvoiceStatus.confirmed:
          payload['confirmed_date'] = now;
          break;
        case PurchaseInvoiceStatus.received:
          payload['received_date'] = now;
          break;
        case PurchaseInvoiceStatus.paid:
          payload['paid_date'] = now;
          break;
        default:
          // For draft and cancelled, don't set any workflow date
          break;
      }

      final result = await _db.update('purchase_invoices', invoiceId, payload);
      final updated = PurchaseInvoice.fromJson(result);

      _upsertInvoice(updated);
      _recordFinancialChange(
        FinancialProjectionChangeKind.purchaseInvoice,
        entityId: updated.id,
        tenantId: updated.tenantId,
      );

      // Refresh accounting if service available
      if (_accountingService != null) {
        await _accountingService!.initialize();
        await _accountingService!.journalEntries.loadJournalEntries();
      }

      // Fetch fresh data from database
      final refreshed = await getPurchaseInvoice(invoiceId, refresh: true);

      if (refreshed != null) {
        _upsertInvoice(refreshed);
      }

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

  // ignore: unused_element
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
      final data = await _db.select(
        'purchase_payments',
        fetchAll: true,
      );
      _paymentCache = data
          .map((row) => PurchasePayment.fromJson(row))
          .where((payment) => payment.deletedAt == null)
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date)); // Most recent first

      _paymentsLoaded = true;
      notifyListeners();
      return _paymentCache;
    } catch (e) {
      throw Exception('No se pudieron cargar los pagos de compras: $e');
    }
  }

  Future<PurchasePayment?> getPurchasePayment(String id,
      {bool refresh = false}) async {
    if (!refresh) {
      for (final payment in _paymentCache) {
        if (payment.id == id && payment.deletedAt == null) return payment;
      }
    }

    try {
      final data = await _db.selectById('purchase_payments', id);
      if (data == null) return null;
      final payment = PurchasePayment.fromJson(data);
      if (payment.deletedAt != null) return null;
      return payment;
    } catch (e) {
      throw Exception('No se pudo obtener el pago de compra: $e');
    }
  }

  Future<PurchasePayment?> fetchPurchasePayment(String id,
      {bool refresh = false}) {
    return getPurchasePayment(id, refresh: refresh);
  }

  Future<List<PurchasePayment>> getPaymentsForInvoice(String invoiceId) async {
    try {
      final data = await _db.select(
        'purchase_payments',
        where: 'invoice_id=$invoiceId',
      );

      return data
          .map((row) => PurchasePayment.fromJson(row))
          .where((payment) => payment.deletedAt == null)
          .toList()
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
      _recordFinancialChange(
        FinancialProjectionChangeKind.purchasePayment,
        entityId: created.id,
        tenantId: created.tenantId,
      );

      await _refreshAfterPayment(payment.invoiceId);
      return created;
    } on PostgrestException catch (e) {
      if (_isPaymentIdempotencyConflict(e) && payment.idempotencyKey != null) {
        final existing = await _findPaymentByIdempotencyKey(payment);
        if (existing != null) {
          _recordFinancialChange(
            FinancialProjectionChangeKind.purchasePayment,
            entityId: existing.id,
            tenantId: existing.tenantId,
          );
          await _refreshAfterPayment(existing.invoiceId);
          return existing;
        }
      }
      throw Exception('No se pudo registrar el pago: ${e.message}');
    } catch (e) {
      throw Exception('No se pudo registrar el pago: $e');
    }
  }

  /// Applies an explicit correction to an existing supplier payment through
  /// the database-owned accounting command. The command preserves payment and
  /// invoice identities, checks optimistic concurrency, records the reason,
  /// and rebuilds settlement evidence only when a financial field changed.
  Future<PurchasePaymentCorrectionResult> correctPurchasePayment({
    required PurchasePayment current,
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
      raw = await _db.rpc(
        'correct_purchase_payment',
        params: params,
      );
    } catch (error, stackTrace) {
      if (!_isOutcomeAmbiguous(error)) rethrow;
      try {
        raw = await _db.rpc(
          'get_purchase_payment_edit_operation',
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
      FinancialProjectionChangeKind.purchasePayment,
      entityId: result.payment.id,
      tenantId: result.payment.tenantId,
    );
    notifyListeners();

    // The correction is already durably committed and acknowledged. Refresh
    // failures must not turn that success into a false save failure or invite
    // an unsafe second correction.
    try {
      await getPurchaseInvoice(result.payment.invoiceId, refresh: true);
      await getPurchasePayments(forceRefresh: true);
      await getPurchaseInvoices(forceRefresh: true);
      if (_accountingService != null) {
        await _accountingService!.initialize();
        await _accountingService!.journalEntries.loadJournalEntries();
      }
    } catch (error) {
      debugPrint(
        'PurchaseService.correctPurchasePayment post-commit refresh failed: '
        '$error',
      );
    }
    return result;
  }

  Future<List<PurchasePaymentEditEvent>> loadPurchasePaymentEditEvents(
    String paymentId,
  ) async {
    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null || tenantId.isEmpty) return const [];

    final response = await _supabase
        .from('purchase_payment_edit_events')
        .select()
        .eq('tenant_id', tenantId)
        .eq('payment_id', paymentId)
        .order('created_at', ascending: false);
    return (response as List)
        .map(
          (row) => PurchasePaymentEditEvent.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
  }

  PurchasePaymentCorrectionResult _parsePaymentCorrectionResult(dynamic raw) {
    if (raw is! Map || raw['payment'] is! Map || raw['event'] is! Map) {
      throw StateError('La respuesta de corrección del pago es inválida.');
    }
    final payment = PurchasePayment.fromJson(
      Map<String, dynamic>.from(raw['payment'] as Map),
    );
    final event = PurchasePaymentEditEvent.fromJson(
      Map<String, dynamic>.from(raw['event'] as Map),
    );
    return PurchasePaymentCorrectionResult(
      payment: payment,
      event: event,
      replayed: raw['replayed'] == true,
      financialFieldsChanged: raw['financial_fields_changed'] == true ||
          event.financialFieldsChanged,
      legacyJournalRelinked:
          raw['legacy_journal_relinked'] == true || event.legacyJournalRelinked,
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

  Future<PurchasePayment?> _findPaymentByIdempotencyKey(
      PurchasePayment payment) async {
    final data = await _supabase
        .from('purchase_payments')
        .select()
        .eq('tenant_id', payment.tenantId)
        .eq('idempotency_key', payment.idempotencyKey!)
        .maybeSingle();

    if (data == null) {
      return null;
    }

    return PurchasePayment.fromJson(Map<String, dynamic>.from(data));
  }

  Future<void> _refreshAfterPayment(String invoiceId) async {
    await getPurchasePayments(forceRefresh: true);
    await getPurchaseInvoices(forceRefresh: true);

    final updatedInvoice = await getPurchaseInvoice(invoiceId);
    final balance = updatedInvoice == null
        ? 0.0
        : (updatedInvoice.balance.abs() < 1 ? 0.0 : updatedInvoice.balance);
    if (updatedInvoice != null &&
        balance <= 0 &&
        updatedInvoice.paidAmount > 0 &&
        updatedInvoice.status != PurchaseInvoiceStatus.received &&
        updatedInvoice.receivedDate == null &&
        updatedInvoice.status != PurchaseInvoiceStatus.paid) {
      debugPrint(
          '💰 Invoice ${updatedInvoice.invoiceNumber} fully paid (balance: $balance). Updating status to PAID.');
      await markAsPaid(updatedInvoice.id!);
    }

    notifyListeners();
  }

  Future<void> deletePayment(String paymentId) async {
    try {
      await _db.delete('purchase_payments', paymentId);
      _recordFinancialChange(
        FinancialProjectionChangeKind.purchasePayment,
        entityId: paymentId,
        tenantId: _tenantService.currentTenantId,
      );

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
        'supplier_invoice_date': supplierInvoiceDate.toUtc().toIso8601String(),
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
    String? idempotencyKey,
    String? reference,
    String? notes,
  }) async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        throw Exception('No se pudo obtener el tenant ID');
      }

      await createPayment(
        PurchasePayment(
          tenantId: tenantId,
          invoiceId: invoiceId,
          paymentMethodId: paymentMethod,
          idempotencyKey: idempotencyKey,
          amount: amount,
          date: paymentDate,
          reference: reference,
          notes: notes,
        ),
      );
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

  // Realtime subscriptions for purchase invoices and payments
  void _setupPurchaseRealtime() async {
    try {
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) {
        debugPrint('⚠️ [PurchaseService] Cannot setup realtime: no tenant_id');
        return;
      }

      await _purchaseInvoicesChannel?.unsubscribe();
      await _purchasePaymentsChannel?.unsubscribe();
      await _purchaseReceivingChannel?.unsubscribe();

      _purchaseInvoicesChannel = _supabase
          .channel('purchase_invoices_changes')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'purchase_invoices',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'tenant_id',
              value: tenantId,
            ),
            callback: (payload) {
              debugPrint(
                  '🔔 [PurchaseService] Purchase invoice changed: ${payload.eventType}');
              if (_invoicesCacheTime != null || _invoiceCache.isNotEmpty) {
                getPurchaseInvoices(forceRefresh: true);
              }
              if (_listInvoicesCacheTime != null ||
                  _listInvoiceCache.isNotEmpty) {
                getPurchaseInvoicesForList(forceRefresh: true);
              }
            },
          )
          .subscribe();

      _purchasePaymentsChannel = _supabase
          .channel('purchase_payments_changes')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'purchase_payments',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'tenant_id',
              value: tenantId,
            ),
            callback: (payload) {
              if (!kReleaseMode) {
                debugPrint('🔔 [PurchaseService] Purchase payment changed');
              }
              getPurchasePayments(forceRefresh: true);
            },
          )
          .subscribe();

      void refreshReceiptReadModel(PostgresChangePayload payload) {
        if (!kReleaseMode) {
          debugPrint(
            '🔔 [PurchaseService] Purchase receiving evidence changed: '
            '${payload.table} ${payload.eventType}',
          );
        }
        getPurchaseInvoicesForList(forceRefresh: true);
      }

      _purchaseReceivingChannel = _supabase
          .channel('purchase_receiving_changes')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'purchase_receipts',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'tenant_id',
              value: tenantId,
            ),
            callback: refreshReceiptReadModel,
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'purchase_receipt_resolution_allocations',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'tenant_id',
              value: tenantId,
            ),
            callback: refreshReceiptReadModel,
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'purchase_credit_notes',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'tenant_id',
              value: tenantId,
            ),
            callback: refreshReceiptReadModel,
          )
          .subscribe();

      if (!kReleaseMode) {
        debugPrint('✅ [PurchaseService] Realtime subscriptions active');
      }
    } catch (e) {
      if (!kReleaseMode) {
        debugPrint('❌ [PurchaseService] Failed to setup realtime: $e');
      }
    }
  }

  @override
  void dispose() {
    _purchaseInvoicesChannel?.unsubscribe();
    _purchasePaymentsChannel?.unsubscribe();
    _purchaseReceivingChannel?.unsubscribe();
    super.dispose();
  }
}
