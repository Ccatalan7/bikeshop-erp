import '../../../shared/models/product.dart';

class POSCartItem {
  final String id;
  final String tenantId;
  final Product? product; // Nullable for ad-hoc items
  final String? adHocDescription; // For ad-hoc items
  final int quantity;
  final double unitPrice;
  final double discount;
  final String? notes;

  const POSCartItem({
    required this.id,
    required this.tenantId,
    this.product,
    this.adHocDescription,
    required this.quantity,
    required this.unitPrice,
    this.discount = 0.0,
    this.notes,
  }) : assert(product != null || adHocDescription != null,
            'Either product or adHocDescription must be provided');

  // Check if this is an ad-hoc item
  bool get isAdHoc => product == null;
  
  // Get display name
  String get displayName => adHocDescription ?? product!.name;

  // JSON serialization
  factory POSCartItem.fromJson(Map<String, dynamic> json) {
    return POSCartItem(
      id: json['id'] ?? '',
      tenantId: json['tenant_id']?.toString() ?? '',
      product:
          json['product'] != null ? Product.fromJson(json['product']) : null,
      adHocDescription: json['ad_hoc_description'],
      quantity: json['quantity'] ?? 1,
      unitPrice: (json['unit_price'] ?? 0).toDouble(),
      discount: (json['discount'] ?? 0).toDouble(),
      notes: json['notes'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'tenant_id': tenantId,
      'product': product?.toJson(),
      'ad_hoc_description': adHocDescription,
      'quantity': quantity,
      'unit_price': unitPrice,
      'discount': discount,
      'notes': notes,
    };
  }

  // Helper methods
  POSCartItem copyWith({
    String? id,
    String? tenantId,
    Product? product,
    String? adHocDescription,
    int? quantity,
    double? unitPrice,
    double? discount,
    String? notes,
  }) {
    return POSCartItem(
      id: id ?? this.id,
      tenantId: tenantId ?? this.tenantId,
      product: product ?? this.product,
      adHocDescription: adHocDescription ?? this.adHocDescription,
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
  double get totalCost => (product?.cost ?? 0) * quantity;
  double get totalMargin => total - totalCost;

  @override
  String toString() =>
      'POSCartItem(name: $displayName, qty: $quantity, total: \$${total.toStringAsFixed(0)})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is POSCartItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
