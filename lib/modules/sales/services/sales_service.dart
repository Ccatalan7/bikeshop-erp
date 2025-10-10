import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../../shared/services/database_service.dart';
import '../../accounting/models/journal_entry.dart';
import '../../accounting/services/accounting_service.dart';
import '../../accounting/services/journal_entry_service.dart';
import '../models/sales_models.dart';

class SalesService extends ChangeNotifier {
  static const _invoicesCollection = 'sales_invoices';
  static const _paymentsCollection = 'sales_payments';

  SalesService(this._databaseService, this._accountingService);

  DatabaseService _databaseService;
  AccountingService _accountingService;

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

  void updateDependencies(DatabaseService databaseService, AccountingService accountingService) {
    _databaseService = databaseService;
    _accountingService = accountingService;
  }

  Future<void> loadInvoices({bool forceRefresh = false}) async {
    if (_isLoadingInvoices) return;
  if (!forceRefresh && _invoices.isNotEmpty) return;

    _isLoadingInvoices = true;
    _invoiceError = null;
    notifyListeners();

    try {
      final data = await _databaseService.select(_invoicesCollection);
      final invoices = data
          .map((raw) => Invoice.fromJson(raw))
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));

      _invoices
        ..clear()
        ..addAll(invoices);
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

  Future<Invoice> saveInvoice(Invoice invoice, {bool postToAccounting = true}) async {
    try {
      final payload = invoice.toFirestoreMap();
      final isNew = invoice.id == null;

      Map<String, dynamic> result;
      if (isNew) {
        result = await _databaseService.insert(_invoicesCollection, payload);
      } else {
        result = await _databaseService.update(_invoicesCollection, invoice.id!, payload);
      }

      final savedInvoice = Invoice.fromJson(result);
      _upsertInvoice(savedInvoice);

      if (postToAccounting && isNew) {
        await _postInvoiceToAccounting(savedInvoice);
      }

      if (isNew) {
        await _recordInventoryMovements(savedInvoice);
      }

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

  Future<void> loadPayments({String? invoiceId, bool forceRefresh = false}) async {
    if (_isLoadingPayments) return;
    if (!forceRefresh && _payments.isNotEmpty && invoiceId == null) return;

    _isLoadingPayments = true;
    _paymentError = null;
    notifyListeners();

    try {
      final data = await _databaseService.select(_paymentsCollection);

      final filtered = invoiceId == null
          ? data
          : data.where((row) => row['invoice_id']?.toString() == invoiceId).toList();

      final payments = filtered.map(Payment.fromJson).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

      _payments
        ..clear()
        ..addAll(payments);
    } catch (e) {
      debugPrint('SalesService.loadPayments error: $e');
      _paymentError = 'No se pudieron cargar los pagos.';
    } finally {
      _isLoadingPayments = false;
      notifyListeners();
    }
  }

  Future<Payment> registerPayment(Payment payment, {bool postToAccounting = true}) async {
    try {
      final payload = payment.toFirestoreMap();
      final isNew = payment.id == null;
      Map<String, dynamic> result;

      if (isNew) {
        result = await _databaseService.insert(_paymentsCollection, payload);
      } else {
        result = await _databaseService.update(_paymentsCollection, payment.id!, payload);
      }

      final savedPayment = Payment.fromJson(result);
      _upsertPayment(savedPayment);

      if (postToAccounting && isNew) {
        await _postPaymentToAccounting(savedPayment);
      }

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

  void clearCache() {
    _invoices.clear();
    _payments.clear();
    notifyListeners();
  }

  Future<void> _postInvoiceToAccounting(Invoice invoice) async {
    final salesLines = invoice.items
        .map(
          (item) => SalesLineEntry(
            productId: item.productId,
            productName: item.productName ?? (item.productSku ?? 'Producto'),
            quantity: item.quantity.round(),
            unitPrice: item.unitPrice,
            cost: item.cost,
          ),
        )
        .toList();

    await _accountingService.postSalesEntry(
      date: invoice.date,
      customerName: invoice.customerName ?? 'Cliente',
      invoiceNumber: invoice.invoiceNumber.isNotEmpty
          ? invoice.invoiceNumber
          : (invoice.id ?? ''),
      subtotal: invoice.subtotal,
      ivaAmount: invoice.ivaAmount,
      total: invoice.total,
      salesLines: salesLines,
    );
  }

  Future<void> _postPaymentToAccounting(Payment payment) async {
    final description = 'Pago recibido ${payment.method.displayName}';
    await _accountingService.initialize();

    final debitAccountCode = _resolveDebitAccountForPayment(payment.method);
    final debitAccount = await _accountingService.getAccountByCode(debitAccountCode);
    final receivableAccount = await _accountingService.getAccountByCode('1201');

    if (debitAccount == null || debitAccount.id == null) {
      throw Exception('No se encontró la cuenta contable para el medio de pago ${payment.method.displayName} ($debitAccountCode).');
    }

    if (receivableAccount == null || receivableAccount.id == null) {
      throw Exception('No se encontró la cuenta contable "1201 - Cuentas por Cobrar Clientes".');
    }

    await _accountingService.createJournalEntry(
      date: payment.date,
      description: description,
      type: JournalEntryType.payment,
      lines: [
        JournalLine(
          accountId: debitAccount.id!,
          accountCode: debitAccount.code,
          accountName: debitAccount.name,
          description: description,
          debitAmount: payment.amount,
          creditAmount: 0,
        ),
        JournalLine(
          accountId: receivableAccount.id!,
          accountCode: receivableAccount.code,
          accountName: receivableAccount.name,
          description: 'Pago factura ${payment.invoiceReference ?? payment.invoiceId}',
          debitAmount: 0,
          creditAmount: payment.amount,
        ),
      ],
      sourceModule: 'sales',
      sourceReference: payment.invoiceId,
    );
  }

  String _resolveDebitAccountForPayment(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash:
        return '1101';
      case PaymentMethod.card:
        return '1110';
      case PaymentMethod.transfer:
        return '1110';
      case PaymentMethod.check:
        return '1110';
      case PaymentMethod.other:
        return '1190';
    }
  }

  Future<void> _recordInventoryMovements(Invoice invoice) async {
    for (final item in invoice.items) {
      if (item.productId.isEmpty) continue;
      final qty = item.quantity.round();
      if (qty <= 0) continue;
      await _databaseService.adjustStock(
        item.productId,
        qty,
        'OUT',
        invoice.invoiceNumber.isNotEmpty ? invoice.invoiceNumber : (invoice.id ?? ''),
      );
    }
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