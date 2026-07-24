import 'package:flutter/material.dart';
import '../../shared/models/product.dart';
import '../models/public_commerce_product_projection.dart';
import '../models/storefront_tax_summary.dart';
import '../services/meta_pixel_service.dart';

class CartItem {
  final Product product;
  int quantity;

  CartItem({
    required this.product,
    required this.quantity,
  });

  PublicCommerceProductProjection get commerce =>
      PublicCommerceProductProjection.fromProduct(
        product,
        categoryPath: product.categoryName,
      );

  double get subtotal => commerce.price * quantity;

  StorefrontTaxLineInput get taxInput => StorefrontTaxLineInput(
        label: commerce.title,
        grossUnitPrice: commerce.price,
        quantity: quantity,
        taxRate: product.taxRate,
      );
}

class CartProvider with ChangeNotifier {
  final List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);

  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  /// Total amount (what customer pays) - prices already INCLUDE IVA
  double get total => _items.fold(0.0, (sum, item) => sum + item.subtotal);

  /// Product-derived, line-by-line fiscal breakdown. Payment method never
  /// participates in tax classification.
  StorefrontTaxSummary get taxSummary => StorefrontTaxSummary.calculate(
        _items.map((item) => item.taxInput),
      );

  bool get hasValidTaxClassification => taxSummary.isValid;

  String? get taxCheckoutBlockMessage => taxSummary.checkoutBlockMessage;

  /// Net amount extracted from affected gross lines and preserved as gross for
  /// exempt lines. Invalid carts return zero and are blocked before checkout.
  double get subtotal {
    final summary = taxSummary;
    return summary.isValid ? summary.netAmount.toDouble() : 0;
  }

  /// IVA extracted per affected line using whole-CLP rounding.
  double get ivaAmount {
    final summary = taxSummary;
    return summary.isValid ? summary.taxAmount.toDouble() : 0;
  }

  bool get isEmpty => _items.isEmpty;

  bool get isNotEmpty => _items.isNotEmpty;

  void addProduct(Product product, {int quantity = 1}) {
    // Check if product already in cart
    final existingIndex =
        _items.indexWhere((item) => item.product.id == product.id);

    if (existingIndex >= 0) {
      // Increase quantity
      _items[existingIndex].quantity += quantity;
    } else {
      // Add new item
      _items.add(CartItem(product: product, quantity: quantity));
    }

    final commerce = PublicCommerceProductProjection.fromProduct(
      product,
      categoryPath: product.categoryName,
    );
    MetaPixelService.instance.trackAddToCart(
      contentId: MetaPixelService.catalogContentId(
        sku: product.sku,
        productId: product.id,
      ),
      contentName: commerce.title,
      itemPrice: commerce.price,
      quantity: quantity,
    );
    notifyListeners();
  }

  void removeProduct(String productId) {
    _items.removeWhere((item) => item.product.id == productId);
    notifyListeners();
  }

  void updateQuantity(String productId, int quantity) {
    if (quantity <= 0) {
      removeProduct(productId);
      return;
    }

    final index = _items.indexWhere((item) => item.product.id == productId);
    if (index >= 0) {
      _items[index].quantity = quantity;
      notifyListeners();
    }
  }

  void incrementQuantity(String productId) {
    final index = _items.indexWhere((item) => item.product.id == productId);
    if (index >= 0) {
      _items[index].quantity++;
      notifyListeners();
    }
  }

  void decrementQuantity(String productId) {
    final index = _items.indexWhere((item) => item.product.id == productId);
    if (index >= 0) {
      if (_items[index].quantity > 1) {
        _items[index].quantity--;
      } else {
        _items.removeAt(index);
      }
      notifyListeners();
    }
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }

  int getProductQuantity(String productId) {
    try {
      final item = _items.firstWhere(
        (item) => item.product.id == productId,
      );
      return item.quantity;
    } catch (e) {
      return 0;
    }
  }

  bool hasProduct(String productId) {
    return _items.any((item) => item.product.id == productId);
  }
}
