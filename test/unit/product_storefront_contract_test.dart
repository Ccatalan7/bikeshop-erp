import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/models/product.dart';

void main() {
  group('Product storefront contract', () {
    test('uses the website price as the customer-facing price', () {
      final product = Product.fromJson(_productJson(
        price: 15990,
        websitePrice: 12990,
      ));

      expect(product.price, 12990);
      expect(product.websitePrice, 12990);
    });

    test('never fails open when legacy and canonical stock disagree', () {
      final product = Product.fromJson(_productJson(
        inventoryQty: 8,
        stockQuantity: 0,
      ));

      expect(product.stockQuantity, 0);
      expect(product.isOutOfStock, isTrue);
    });

    test('falls back to legacy stock only when canonical stock is absent', () {
      final json = _productJson(inventoryQty: 3);
      json.remove('stock_quantity');

      expect(Product.fromJson(json).stockQuantity, 3);
    });
  });
}

Map<String, dynamic> _productJson({
  num price = 10000,
  num? websitePrice,
  int inventoryQty = 0,
  int stockQuantity = 0,
}) {
  return <String, dynamic>{
    'id': '00000000-0000-4000-8000-000000000001',
    'name': 'Producto de prueba',
    'sku': 'PRODUCT-STORE-CONTRACT',
    'price': price,
    'website_price': websitePrice,
    'inventory_qty': inventoryQty,
    'stock_quantity': stockQuantity,
    'category': 'other',
    'product_type': 'product',
    'track_stock': true,
    'is_active': true,
    'is_published': true,
  };
}
