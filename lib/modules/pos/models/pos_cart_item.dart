import '../../../shared/models/product.dart';

class POSCartItem {
  final String id;
  final Product product;
  final int quantity;
  final double unitPrice;
  final double discount;
  final String? notes;

  const POSCartItem({
    required this.id,
    required this.product,
    required this.quantity,
    required this.unitPrice,
    this.discount = 0.0,
    this.notes,
  });

  // JSON serialization
  factory POSCartItem.fromJson(Map<String, dynamic> json) {
    return POSCartItem(
      id: json['id'] ?? '',
      product: Product.fromJson(json['product']),
      quantity: json['quantity'] ?? 1,
      unitPrice: (json['unit_price'] ?? 0).toDouble(),
      discount: (json['discount'] ?? 0).toDouble(),
      notes: json['notes'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product': product.toJson(),
      'quantity': quantity,
      'unit_price': unitPrice,
      'discount': discount,
      'notes': notes,
    };
  }

  // Helper methods
  POSCartItem copyWith({
    String? id,
    Product? product,
    int? quantity,
    double? unitPrice,
    double? discount,
    String? notes,
  }) {
    return POSCartItem(
      id: id ?? this.id,
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      discount: discount ?? this.discount,
      notes: notes ?? this.notes,
    );
  }

  // Calculated properties
  double get subtotal => unitPrice * quantity;
  double get discountAmount => subtotal * (discount / 100);
  double get total => subtotal - discountAmount;
  double get totalCost => product.cost * quantity;
  double get totalMargin => total - totalCost;

  @override
  String toString() => 'POSCartItem(product: ${product.name}, qty: $quantity, total: \$${total.toStringAsFixed(0)})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is POSCartItem && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}