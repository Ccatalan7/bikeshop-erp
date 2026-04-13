import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/models/product.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/models/payment_method.dart' as pm;
import '../../../shared/models/tax_treatment.dart';
import '../../../shared/services/inventory_service.dart';
import '../../../shared/services/number_generation_service.dart';
import '../../../shared/services/payment_method_service.dart';
import '../../../shared/services/tenant_service.dart';
import '../../sales/models/sales_models.dart' as sales_models;
import '../../sales/services/sales_service.dart';
import '../models/payment_method.dart';
import '../models/pos_cart_item.dart';
import '../models/pos_transaction.dart';

class POSService extends ChangeNotifier {
  InventoryService _inventoryService;
  SalesService _salesService;
  PaymentMethodService _paymentMethodService;
  TenantService _tenantService;
  final Uuid _uuid = const Uuid();

  // Current sale state
  final List<POSCartItem> _cartItems = [];
  Customer? _selectedCustomer;
  bool _isProcessingSale = false;
  TaxTreatment _taxTreatment = TaxTreatment.noTax; // Default: no tax for POS
  pm.PaymentMethod?
      _selectedPaymentMethod; // Primary payment method for tax detection

  // Invoice payment mode state (NEW)
  sales_models.Invoice? _linkedInvoice;

  POSService({
    required InventoryService inventoryService,
    required SalesService salesService,
    required PaymentMethodService paymentMethodService,
    required TenantService tenantService,
  })  : _inventoryService = inventoryService,
        _salesService = salesService,
        _paymentMethodService = paymentMethodService,
        _tenantService = tenantService;

  @override
  void notifyListeners() {
    debugPrint(
        '🔔 [POSService] notifyListeners() — stack: ${StackTrace.current.toString().split('\n').take(4).join(' | ')}');
    super.notifyListeners();
  }

  void updateDependencies({
    InventoryService? inventoryService,
    SalesService? salesService,
    PaymentMethodService? paymentMethodService,
    TenantService? tenantService,
  }) {
    if (inventoryService != null) {
      _inventoryService = inventoryService;
    }
    if (salesService != null) {
      _salesService = salesService;
    }
    if (paymentMethodService != null) {
      _paymentMethodService = paymentMethodService;
    }
    if (tenantService != null) {
      _tenantService = tenantService;
    }
  }

  // Getters
  List<POSCartItem> get cartItems => List.unmodifiable(_cartItems);
  Customer? get selectedCustomer => _selectedCustomer;
  bool get isProcessingSale => _isProcessingSale;
  bool get hasItemsInCart => _cartItems.isNotEmpty;
  TaxTreatment get taxTreatment => _taxTreatment;
  pm.PaymentMethod? get selectedPaymentMethod => _selectedPaymentMethod;

  // Invoice payment mode getters (NEW)
  bool get isInvoicePaymentMode => _linkedInvoice != null;
  sales_models.Invoice? get linkedInvoice => _linkedInvoice;

  // Cart calculations (POS uses INCLUDED tax like sales invoices)
  double get cartSubtotal =>
      _cartItems.fold(0.0, (sum, item) => sum + item.subtotal);
  double get cartDiscountAmount =>
      _cartItems.fold(0.0, (sum, item) => sum + item.discountAmount);

  // Net amount after discounts
  double get cartNetAmount => cartSubtotal - cartDiscountAmount;

  // Tax calculation: When tax_included, extract tax by dividing
  double get cartTaxAmount {
    if (_taxTreatment == TaxTreatment.taxIncluded) {
      // Tax is included in price - extract it
      final totalWithTax = cartNetAmount;
      final netBeforeTax = totalWithTax / 1.19;
      return totalWithTax - netBeforeTax;
    } else {
      return 0; // No tax
    }
  }

  // Total is always the net amount (price customer sees)
  double get cartTotal => cartNetAmount;

  double get cartTotalCost =>
      _cartItems.fold(0.0, (sum, item) => sum + item.totalCost);
  int get cartTotalItems =>
      _cartItems.fold(0, (sum, item) => sum + item.quantity);

  // Cart operations
  Future<bool> addToCart(Product product,
      {int quantity = 1, double? customPrice}) async {
    if (quantity <= 0) return false;

    // Check stock availability
    if (product.trackStock && product.stockQuantity < quantity) {
      return false;
    }

    // Check if product already in cart
    final existingIndex =
        _cartItems.indexWhere((item) => item.product?.id == product.id);

    if (existingIndex != -1) {
      // Update quantity if product exists
      final existingItem = _cartItems[existingIndex];
      final newQuantity = existingItem.quantity + quantity;

      if (product.trackStock && product.stockQuantity < newQuantity) {
        return false;
      }

      _cartItems[existingIndex] = existingItem.copyWith(quantity: newQuantity);
    } else {
      // Add new item
      final tenantId = await _tenantService.getTenantId();
      if (tenantId == null) return false;

      final cartItem = POSCartItem(
        id: _uuid.v4(),
        tenantId: tenantId,
        product: product,
        quantity: quantity,
        unitPrice: customPrice ?? product.price,
      );
      _cartItems.add(cartItem);
    }

    notifyListeners();
    return true;
  }

  /// Add ad-hoc item (custom description) to cart
  Future<bool> addAdHocItem({
    required String description,
    required double price,
    int quantity = 1,
  }) async {
    if (quantity <= 0 || price < 0) return false;
    if (description.trim().isEmpty) return false;

    final tenantId = await _tenantService.getTenantId();
    if (tenantId == null) return false;

    final cartItem = POSCartItem(
      id: _uuid.v4(),
      tenantId: tenantId,
      product: null,
      adHocDescription: description.trim(),
      quantity: quantity,
      unitPrice: price,
    );

    _cartItems.add(cartItem);
    notifyListeners();
    return true;
  }

  bool removeFromCart(String itemId) {
    final initialLength = _cartItems.length;
    _cartItems.removeWhere((item) => item.id == itemId);
    if (_cartItems.length < initialLength) {
      notifyListeners();
      return true;
    }
    return false;
  }

  bool updateCartItemQuantity(String itemId, int newQuantity) {
    if (newQuantity <= 0) {
      return removeFromCart(itemId);
    }

    final itemIndex = _cartItems.indexWhere((item) => item.id == itemId);
    if (itemIndex != -1) {
      final item = _cartItems[itemIndex];

      // Check stock availability (only for real products, not ad-hoc)
      if (item.product != null) {
        final requiresStock =
            item.product!.productType == ProductType.product &&
                item.product!.trackStock;
        if (requiresStock && item.product!.stockQuantity < newQuantity) {
          if (kDebugMode) {
            print('POSService: Insufficient stock for quantity $newQuantity');
          }
          return false;
        }
      }

      _cartItems[itemIndex] = item.copyWith(quantity: newQuantity);
      notifyListeners();
      return true;
    }
    return false;
  }

  bool updateCartItemDiscount(String itemId, double discountPercentage) {
    if (discountPercentage < 0 || discountPercentage > 100) return false;

    final itemIndex = _cartItems.indexWhere((item) => item.id == itemId);
    if (itemIndex != -1) {
      _cartItems[itemIndex] =
          _cartItems[itemIndex].copyWith(discount: discountPercentage);
      notifyListeners();
      return true;
    }
    return false;
  }

  void clearCart() {
    _cartItems.clear();
    _selectedCustomer = null;
    _taxTreatment = TaxTreatment.noTax; // Reset to default
    notifyListeners();
  }

  void setCustomer(Customer? customer) {
    _selectedCustomer = customer;
    notifyListeners();
  }

  void setTaxTreatment(TaxTreatment treatment) {
    _taxTreatment = treatment;
    notifyListeners();
  }

  /// Set primary payment method and auto-detect tax treatment
  void setPaymentMethod(pm.PaymentMethod? method) {
    _selectedPaymentMethod = method;

    // Auto-detect tax treatment based on payment method's default
    if (method != null) {
      _taxTreatment = method.defaultTaxTreatment;
    }

    notifyListeners();
  }

  // Invoice payment mode methods (NEW)

  /// Enter invoice payment mode - clears cart and links invoice
  void enterInvoicePaymentMode(sales_models.Invoice invoice) {
    _linkedInvoice = invoice;
    _cartItems.clear(); // Clear cart when entering invoice mode
    notifyListeners();
  }

  /// Exit invoice payment mode - returns to normal POS mode
  void exitInvoicePaymentMode() {
    _linkedInvoice = null;
    notifyListeners();
  }

  /// Get the display total (invoice balance or cart total)
  double get displayTotal {
    if (_linkedInvoice != null) {
      return _linkedInvoice!.balance;
    }
    return cartTotal;
  }

  // Barcode/SKU scanning
  Future<bool> scanProduct(String code) async {
    try {
      // Try barcode first
      Product? product = await _inventoryService.getProductByBarcode(code);

      // If not found by barcode, try SKU
      product ??= await _inventoryService.getProductBySku(code);

      if (product != null) {
        return await addToCart(product);
      }

      if (kDebugMode) print('POSService: Product not found for code: $code');
      return false;
    } catch (e) {
      if (kDebugMode) print('POSService: Error scanning product: $e');
      return false;
    }
  }

  // Checkout process
  Future<POSTransaction?> checkout(List<POSPayment> payments,
      {String? notes}) async {
    if (_cartItems.isEmpty) return null;
    if (_isProcessingSale) return null;
    if (payments.isEmpty) {
      throw Exception('Debe registrar al menos un pago.');
    }

    _isProcessingSale = true;
    notifyListeners();

    final timestamp = DateTime.now();

    final tenantId = await TenantService().getTenantId();
    if (tenantId == null) {
      throw Exception('User does not have a tenant_id. Cannot proceed.');
    }

    try {
      // CRITICAL: Ensure payment methods are loaded from database
      if (_paymentMethodService.paymentMethods.isEmpty) {
        if (kDebugMode) {
          print('POSService: Loading payment methods before checkout...');
        }
        await _paymentMethodService.loadPaymentMethods(forceRefresh: true);
      }

      final totalPaid =
          payments.fold<double>(0, (sum, payment) => sum + payment.amount);
      if (totalPaid < cartTotal) {
        throw Exception('Monto insuficiente para completar la venta.');
      }

      // Generate invoice number using new sequential system
      final numberService = NumberGenerationService();
      final invoiceNumber = await numberService.nextSalesInvoiceNumber();

      final invoiceItems = _cartItems.map((item) {
        final discountAmount = item.discountAmount;
        return sales_models.InvoiceItem(
          productId: item.product?.id,
          productName: item.displayName,
          productSku: item.product?.sku,
          quantity: item.quantity.toDouble(),
          unitPrice: item.unitPrice,
          discount: discountAmount,
          lineTotal: item.total,
          cost: item.product?.cost ?? 0,
          purchaseTreatment:
              item.product?.purchaseTreatment ?? PurchaseTreatment.inventory,
          isService: item.product?.isService ?? false,
        );
      }).toList();

      final invoice = sales_models.Invoice(
        tenantId: tenantId,
        customerId: _selectedCustomer?.id,
        invoiceNumber: invoiceNumber,
        customerName: _selectedCustomer?.name ?? 'Cliente Mostrador',
        customerRut: _selectedCustomer?.rut?.isNotEmpty == true
            ? _selectedCustomer!.rut
            : null,
        date: timestamp,
        dueDate: timestamp,
        reference: notes,
        // POS sales are immediately confirmed (not just sent) to trigger accounting
        status: payments.isNotEmpty
            ? sales_models.InvoiceStatus.confirmed
            : sales_models.InvoiceStatus.draft,
        subtotal: cartNetAmount, // Total before tax (for line items display)
        netAmount: cartNetAmount -
            cartTaxAmount, // ✅ CRITICAL: Net revenue (total - IVA)
        ivaAmount: cartTaxAmount,
        total: cartTotal,
        taxTreatment: _taxTreatment, // ✅ Include tax treatment
        items: invoiceItems,
        source: 'pos',
      );

      final savedInvoice = await _salesService.saveInvoice(invoice);
      if (savedInvoice.id == null) {
        throw Exception(
            'No se pudo obtener el identificador de la factura generada.');
      }
      final invoiceId = savedInvoice.id!;

      // Safety net: ensure invoice journal entry is created even if trigger missed it
      try {
        await Supabase.instance.client.rpc(
          'ensure_sales_invoice_journal_entry',
          params: {'p_invoice_id': invoiceId},
        );
      } catch (e) {
        if (kDebugMode) print('⚠️ POS: ensure_sales_invoice_journal_entry: $e');
      }

      double remaining = cartTotal;
      for (final payment in payments) {
        if (remaining <= 0) {
          break;
        }

        final appliedAmount =
            remaining < payment.amount ? remaining : payment.amount;
        if (appliedAmount <= 0) {
          continue;
        }

        // Map POS payment method to payment_method_id
        pm.PaymentMethod? dbPaymentMethod;
        switch (payment.method.type) {
          case PaymentType.cash:
            dbPaymentMethod =
                _paymentMethodService.getPaymentMethodByCode('cash');
            if (kDebugMode) {
              print('POSService: Cash payment method: $dbPaymentMethod');
            }
            break;
          case PaymentType.card:
            dbPaymentMethod =
                _paymentMethodService.getPaymentMethodByCode('card');
            if (kDebugMode) {
              print('POSService: Card payment method: $dbPaymentMethod');
            }
            break;
          case PaymentType.transfer:
            dbPaymentMethod =
                _paymentMethodService.getPaymentMethodByCode('transfer');
            if (kDebugMode) {
              print('POSService: Transfer payment method: $dbPaymentMethod');
            }
            break;
          case PaymentType.voucher:
            dbPaymentMethod = _paymentMethodService
                .getPaymentMethodByCode('cash'); // fallback
            if (kDebugMode) {
              print(
                  'POSService: Voucher (cash fallback) payment method: $dbPaymentMethod');
            }
            break;
        }

        if (dbPaymentMethod == null) {
          if (kDebugMode) {
            print(
                'POSService: Payment method not found for ${payment.method.type}');
            print(
                'POSService: Available payment methods: ${_paymentMethodService.paymentMethods.map((pm) => '${pm.code} (${pm.name})').join(', ')}');
          }
          throw Exception(
              'Método de pago "${payment.method.name}" no encontrado en la base de datos. Por favor, configure los métodos de pago en Configuración.');
        }

        final salesPayment = sales_models.Payment(
          tenantId: savedInvoice.tenantId, // Get from parent invoice
          invoiceId: invoiceId,
          invoiceReference: savedInvoice.invoiceNumber.isNotEmpty
              ? savedInvoice.invoiceNumber
              : invoiceId,
          paymentMethodId: dbPaymentMethod.id,
          amount: appliedAmount,
          date: timestamp,
          reference: payment.reference,
        );

        await _salesService.registerPayment(salesPayment);
        remaining -= appliedAmount;
      }

      await _inventoryService.getProducts(forceRefresh: true);

      final transaction = POSTransaction(
        id: invoiceId,
        tenantId: tenantId,
        cashierId: 'current_user', // TODO: enlazar con el usuario autenticado
        customerId: _selectedCustomer?.id,
        customer: _selectedCustomer,
        items: List.from(_cartItems),
        payments: payments,
        subtotal: cartNetAmount,
        taxAmount: cartTaxAmount,
        discountAmount: cartDiscountAmount,
        total: cartTotal,
        status: POSTransactionStatus.completed,
        notes: notes,
        createdAt: timestamp,
        completedAt: timestamp,
        receiptNumber: savedInvoice.invoiceNumber.isNotEmpty
            ? savedInvoice.invoiceNumber
            : invoiceId,
      );

      clearCart();

      _isProcessingSale = false;
      notifyListeners();

      return transaction;
    } catch (e) {
      _isProcessingSale = false;
      notifyListeners();
      if (kDebugMode) {
        print('POSService: Checkout error: $e');
      }
      rethrow;
    }
  }

  // Receipt operations
  Future<bool> printReceipt(POSTransaction transaction) async {
    if (kDebugMode) {
      print('POSService: Printing receipt for transaction ${transaction.id}');
    }

    // TODO: Implement actual receipt printing
    // This could integrate with thermal printers, PDF generation, etc.

    return true;
  }

  // Cash drawer operations
  Future<bool> openCashDrawer() async {
    if (kDebugMode) print('POSService: Opening cash drawer');

    // TODO: Implement cash drawer trigger
    // This could send a signal to hardware cash drawer

    return true;
  }

  // Product search for POS
  Future<List<Product>> searchProducts(String query) async {
    return await _inventoryService.searchProducts(query);
  }

  // Calculate change amount
  double calculateChange(double totalPaid) {
    return totalPaid - cartTotal;
  }

  // Validate if transaction can be completed
  bool canCompleteTransaction() {
    return _cartItems.isNotEmpty && !_isProcessingSale;
  }

  // Get available payment methods
  List<PaymentMethod> getAvailablePaymentMethods() {
    return PaymentMethod.defaultMethods
        .where((method) => method.isActive)
        .toList();
  }

  // Deprecated: Old invoice numbering (kept for reference)
  // Now uses NumberGenerationService.nextSalesInvoiceNumber()
  String _buildInvoiceNumber(DateTime timestamp) {
    final datePortion =
        '${timestamp.year}${timestamp.month.toString().padLeft(2, '0')}${timestamp.day.toString().padLeft(2, '0')}';
    final millisPortion = timestamp.millisecondsSinceEpoch
        .toString()
        .padLeft(13, '0')
        .substring(7);
    return 'POS-$datePortion-$millisPortion';
  }
}
