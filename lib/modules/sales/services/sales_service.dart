import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/database_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../accounting/services/accounting_service.dart';
import '../models/sales_models.dart';

class SalesService extends ChangeNotifier {
  static const _invoicesCollection = 'sales_invoices';
  static const _paymentsCollection = 'sales_payments';

  SalesService(this._databaseService, this._accountingService, this._tenantService);

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
    if (_isLoadingInvoices) return;
    if (!forceRefresh && _invoices.isNotEmpty) return;

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
    if (!refresh) {
      for (final invoice in _invoices) {
        if (invoice.id == id) {
          return invoice;
        }
      }
    }

    try {
      final data = await _databaseService.selectById(_invoicesCollection, id);
      if (data == null) return null;
      final invoice = Invoice.fromJson(data);
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

      Map<String, dynamic> result;
      if (isNew) {
        // Add tenant_id for new invoices
        final invoiceData = _tenantService.addTenantId(payload);
        result = await _databaseService.insert(_invoicesCollection, invoiceData);
      } else {
        result = await _databaseService.update(
            _invoicesCollection, invoice.id!, payload);
      }

      final savedInvoice = Invoice.fromJson(result);
      _upsertInvoice(savedInvoice);

      await _accountingService.initialize();
      await _accountingService.journalEntries.loadJournalEntries();

      notifyListeners();
      return savedInvoice;
    } catch (e) {
      debugPrint('SalesService.saveInvoice error: $e');
      throw Exception('No se pudo guardar la factura.');
    }
  }

  Future<void> deleteInvoice(String invoiceId) async {
    try {
      await _databaseService.delete(_invoicesCollection, invoiceId);
      _invoices.removeWhere((invoice) => invoice.id == invoiceId);
      notifyListeners();
    } catch (e) {
      debugPrint('SalesService.deleteInvoice error: $e');
      throw Exception('No se pudo eliminar la factura.');
    }
  }

  Future<void> loadPayments(
      {String? invoiceId, bool forceRefresh = false}) async {
    if (_isLoadingPayments) return;
    if (!forceRefresh && _payments.isNotEmpty && invoiceId == null) return;

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
      if (invoiceId != null) {
        // Mantener caché completa; las vistas filtrarán por factura según sea necesario.
      }
      _ensureRealtimeSubscriptions();
    } catch (e) {
      debugPrint('SalesService.loadPayments error: $e');
      _paymentError = 'No se pudieron cargar los pagos.';
    } finally {
      _isLoadingPayments = false;
      notifyListeners();
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

      notifyListeners();
      return savedPayment;
    } catch (e) {
      debugPrint('SalesService.registerPayment error: $e');
      throw Exception('No se pudo registrar el pago.');
    }
  }

  Future<void> deletePayment(String paymentId) async {
    try {
      await _databaseService.delete(_paymentsCollection, paymentId);
      _payments.removeWhere((payment) => payment.id == paymentId);
      await _accountingService.initialize();
      await _accountingService.journalEntries.loadJournalEntries();
      notifyListeners();
    } catch (e) {
      debugPrint('SalesService.deletePayment error: $e');
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

      await _accountingService.initialize();
      await _accountingService.journalEntries.loadJournalEntries();

      final refreshed = await fetchInvoice(invoiceId, refresh: true);

      if (status == InvoiceStatus.paid) {
        await loadPayments(forceRefresh: true);
      }

      notifyListeners();
      return refreshed ?? updated;
    } catch (e) {
      debugPrint('SalesService.updateInvoiceStatus error: $e');
      rethrow;
    }
  }

  void _ensureRealtimeSubscriptions() {
    final client = Supabase.instance.client;

    _invoiceChannel ??=
        client.channel('sales_invoices_stream').onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: _invoicesCollection,
              callback: _handleInvoiceChange,
            )..subscribe();

    _paymentChannel ??=
        client.channel('sales_payments_stream').onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: _paymentsCollection,
              callback: _handlePaymentChange,
            )..subscribe();
  }

  void _handleInvoiceChange(PostgresChangePayload payload) {
    try {
      switch (payload.eventType) {
        case PostgresChangeEvent.insert:
        case PostgresChangeEvent.update:
          final dynamic rawNew = payload.newRecord;
          if (rawNew is Map) {
            final invoice = Invoice.fromJson(
                Map<String, dynamic>.from(rawNew.cast<String, dynamic>()));
            _upsertInvoice(invoice);
            notifyListeners();
          }
          break;
        case PostgresChangeEvent.delete:
          final dynamic rawOld = payload.oldRecord;
          final id = rawOld is Map ? rawOld['id']?.toString() : null;
          if (id != null) {
            _invoices.removeWhere((element) => element.id == id);
            notifyListeners();
          }
          break;
        default:
          break;
      }
    } catch (e) {
      debugPrint('SalesService._handleInvoiceChange error: $e');
    }
  }

  void _handlePaymentChange(PostgresChangePayload payload) {
    try {
      switch (payload.eventType) {
        case PostgresChangeEvent.insert:
        case PostgresChangeEvent.update:
          final dynamic rawNew = payload.newRecord;
          if (rawNew is Map) {
            final payment = Payment.fromJson(
                Map<String, dynamic>.from(rawNew.cast<String, dynamic>()));
            _upsertPayment(payment);
            notifyListeners();
          }
          break;
        case PostgresChangeEvent.delete:
          final dynamic rawOld = payload.oldRecord;
          final id = rawOld is Map ? rawOld['id']?.toString() : null;
          if (id != null) {
            _payments.removeWhere((element) => element.id == id);
            notifyListeners();
          }
          break;
        default:
          break;
      }
    } catch (e) {
      debugPrint('SalesService._handlePaymentChange error: $e');
    }
  }

  @override
  void dispose() {
    _invoiceChannel?.unsubscribe();
    _paymentChannel?.unsubscribe();
    super.dispose();
  }

  void clearCache() {
    _invoices.clear();
    _payments.clear();
    notifyListeners();
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
