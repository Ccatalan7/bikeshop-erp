import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/models/product.dart';
import '../../../shared/models/customer.dart';
import '../../../shared/services/inventory_service.dart';
import '../../accounting/services/accounting_service.dart';
import '../../accounting/services/journal_entry_service.dart';
import '../models/pos_cart_item.dart';
import '../models/pos_transaction.dart';
import '../models/payment_method.dart';

class POSService extends ChangeNotifier {
  final InventoryService _inventoryService;
  final AccountingService _accountingService;
  final Uuid _uuid = const Uuid();

  // Current sale state
  final List<POSCartItem> _cartItems = [];
  Customer? _selectedCustomer;
  bool _isProcessingSale = false;
  
  POSService({
    required InventoryService inventoryService,
    required AccountingService accountingService,
  }) : _inventoryService = inventoryService,
       _accountingService = accountingService;

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

    _isProcessingSale = true;
    notifyListeners();

    try {
      // Validate payment amount
      final totalPaid = payments.fold(0.0, (sum, payment) => sum + payment.amount);
      if (totalPaid < cartTotal) {
        throw Exception('Insufficient payment amount');
      }

      // Create transaction
      final transactionId = 'TXN-${DateTime.now().millisecondsSinceEpoch}';
      final receiptNumber = 'RCP-${DateTime.now().millisecondsSinceEpoch}';
      
      final transaction = POSTransaction(
        id: transactionId,
        cashierId: 'current_user', // TODO: Get from auth service
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
        createdAt: DateTime.now(),
        completedAt: DateTime.now(),
        receiptNumber: receiptNumber,
      );

      // Update inventory
      for (final item in _cartItems) {
        final success = await _inventoryService.deductStock(
          item.product.id,
          item.quantity,
        );
        if (!success) {
          throw Exception('Failed to update inventory for ${item.product.name}');
        }
      }

      // Create accounting entry
      await _accountingService.postSalesEntry(
        date: DateTime.now(),
        customerName: _selectedCustomer?.name ?? 'Cliente General',
        invoiceNumber: transactionId,
        subtotal: cartNetAmount,
        ivaAmount: cartTaxAmount,
        total: cartTotal,
        salesLines: _cartItems.map((item) => SalesLineEntry(
          productId: item.product.id,
          productName: item.product.name,
          quantity: item.quantity,
          unitPrice: item.product.price,
          cost: item.product.cost * item.quantity,
        )).toList(),
      );

      final completedTransaction = transaction.copyWith(journalEntryId: transactionId);

      // Clear cart
      clearCart();

      _isProcessingSale = false;
      notifyListeners();

      return completedTransaction;
    } catch (e) {
      _isProcessingSale = false;
      notifyListeners();
      if (kDebugMode) print('POSService: Checkout error: $e');
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
}