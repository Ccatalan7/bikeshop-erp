import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/models/product.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/models/payment_method.dart' as pm;
import '../../../shared/services/inventory_service.dart';
import '../../../shared/services/payment_method_service.dart';
import '../../sales/models/sales_models.dart' as sales_models;
import '../../sales/services/sales_service.dart';
import '../models/payment_method.dart';
import '../models/pos_cart_item.dart';
import '../models/pos_transaction.dart';

class POSService extends ChangeNotifier {
  InventoryService _inventoryService;
  SalesService _salesService;
  PaymentMethodService _paymentMethodService;
  final Uuid _uuid = const Uuid();

  // Current sale state
  final List<POSCartItem> _cartItems = [];
  Customer? _selectedCustomer;
  bool _isProcessingSale = false;
  
  POSService({
    required InventoryService inventoryService,
    required SalesService salesService,
    required PaymentMethodService paymentMethodService,
  })  : _inventoryService = inventoryService,
        _salesService = salesService,
        _paymentMethodService = paymentMethodService;

  void updateDependencies({
    InventoryService? inventoryService,
    SalesService? salesService,
    PaymentMethodService? paymentMethodService,
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
  }

  // Getters
  List<POSCartItem> get cartItems => List.unmodifiable(_cartItems);
  Customer? get selectedCustomer => _selectedCustomer;
  bool get isProcessingSale => _isProcessingSale;
  bool get hasItemsInCart => _cartItems.isNotEmpty;

  // Cart calculations
  double get cartSubtotal => _cartItems.fold(0.0, (sum, item) => sum + item.subtotal);
  double get cartDiscountAmount => _cartItems.fold(0.0, (sum, item) => sum + item.discountAmount);
  double get cartNetAmount => cartSubtotal - cartDiscountAmount;
  double get cartTaxAmount => cartNetAmount * 0.19; // 19% IVA
  double get cartTotal => cartNetAmount + cartTaxAmount;
  double get cartTotalCost => _cartItems.fold(0.0, (sum, item) => sum + item.totalCost);
  int get cartTotalItems => _cartItems.fold(0, (sum, item) => sum + item.quantity);

  // Cart operations
  Future<bool> addToCart(Product product, {int quantity = 1, double? customPrice}) async {
    if (quantity <= 0) return false;
    
    // Check stock availability
    if (product.stockQuantity < quantity) {
      if (kDebugMode) print('POSService: Insufficient stock for ${product.name}');
      return false;
    }

    final existingItemIndex = _cartItems.indexWhere((item) => item.product.id == product.id);
    
    if (existingItemIndex != -1) {
      // Update existing item
      final existingItem = _cartItems[existingItemIndex];
      final newQuantity = existingItem.quantity + quantity;
      
      if (product.stockQuantity < newQuantity) {
        if (kDebugMode) print('POSService: Insufficient stock for total quantity');
        return false;
      }
      
      _cartItems[existingItemIndex] = existingItem.copyWith(quantity: newQuantity);
    } else {
      // Add new item
      final cartItem = POSCartItem(
        id: _uuid.v4(),
        product: product,
        quantity: quantity,
        unitPrice: customPrice ?? product.price,
      );
      _cartItems.add(cartItem);
    }
    
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
      
      // Check stock availability
      if (item.product.stockQuantity < newQuantity) {
        if (kDebugMode) print('POSService: Insufficient stock for quantity $newQuantity');
        return false;
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
      _cartItems[itemIndex] = _cartItems[itemIndex].copyWith(discount: discountPercentage);
      notifyListeners();
      return true;
    }
    return false;
  }

  void clearCart() {
    _cartItems.clear();
    _selectedCustomer = null;
    notifyListeners();
  }

  void setCustomer(Customer? customer) {
    _selectedCustomer = customer;
    notifyListeners();
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
  Future<POSTransaction?> checkout(List<POSPayment> payments, {String? notes}) async {
    if (_cartItems.isEmpty) return null;
    if (_isProcessingSale) return null;
    if (payments.isEmpty) {
      throw Exception('Debe registrar al menos un pago.');
    }

    _isProcessingSale = true;
    notifyListeners();

    final timestamp = DateTime.now();

    try {
      final totalPaid = payments.fold<double>(0, (sum, payment) => sum + payment.amount);
      if (totalPaid < cartTotal) {
        throw Exception('Monto insuficiente para completar la venta.');
      }

      final invoiceNumber = _buildInvoiceNumber(timestamp);
      final invoiceItems = _cartItems.map((item) {
        final discountAmount = item.discountAmount;
        return sales_models.InvoiceItem(
          productId: item.product.id,
          productName: item.product.name,
          productSku: item.product.sku,
          quantity: item.quantity.toDouble(),
          unitPrice: item.unitPrice,
          discount: discountAmount,
          lineTotal: item.total,
          cost: item.totalCost,
        );
      }).toList();

      final invoice = sales_models.Invoice(
        customerId: _selectedCustomer?.id,
        invoiceNumber: invoiceNumber,
        customerName: _selectedCustomer?.name ?? 'Cliente Mostrador',
        customerRut: _selectedCustomer?.rut?.isNotEmpty == true ? _selectedCustomer!.rut : null,
        date: timestamp,
        dueDate: timestamp,
        reference: notes,
        // POS sales are immediately confirmed (not just sent) to trigger accounting
        status: payments.isNotEmpty ? sales_models.InvoiceStatus.confirmed : sales_models.InvoiceStatus.draft,
        subtotal: cartNetAmount,
        ivaAmount: cartTaxAmount,
        total: cartTotal,
        items: invoiceItems,
      );

      final savedInvoice = await _salesService.saveInvoice(invoice);
      if (savedInvoice.id == null) {
        throw Exception('No se pudo obtener el identificador de la factura generada.');
      }
      final invoiceId = savedInvoice.id!;

      double remaining = cartTotal;
      for (final payment in payments) {
        if (remaining <= 0) {
          break;
        }

        final appliedAmount = remaining < payment.amount ? remaining : payment.amount;
        if (appliedAmount <= 0) {
          continue;
        }

        // Map POS payment method to payment_method_id
        String? paymentMethodId;
        switch (payment.method.type) {
          case PaymentType.cash:
            paymentMethodId = _paymentMethodService.getPaymentMethodByCode('cash')?.id;
            break;
          case PaymentType.card:
            paymentMethodId = _paymentMethodService.getPaymentMethodByCode('card')?.id;
            break;
          case PaymentType.transfer:
            paymentMethodId = _paymentMethodService.getPaymentMethodByCode('transfer')?.id;
            break;
          case PaymentType.voucher:
            paymentMethodId = _paymentMethodService.getPaymentMethodByCode('cash')?.id; // fallback
            break;
        }

        if (paymentMethodId == null) {
          throw Exception('Payment method not found in database');
        }

        final salesPayment = sales_models.Payment(
          invoiceId: invoiceId,
          invoiceReference: savedInvoice.invoiceNumber.isNotEmpty
              ? savedInvoice.invoiceNumber
              : invoiceId,
          paymentMethodId: paymentMethodId,
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
    if (kDebugMode) print('POSService: Printing receipt for transaction ${transaction.id}');
    
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
    return PaymentMethod.defaultMethods.where((method) => method.isActive).toList();
  }

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