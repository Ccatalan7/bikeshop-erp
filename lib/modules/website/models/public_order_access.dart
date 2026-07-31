import 'website_models.dart';

/// Result returned once by the atomic public checkout RPC.
class PublicOrderCheckoutAccess {
  const PublicOrderCheckoutAccess({
    required this.orderId,
    required this.accessToken,
    required this.expiresAt,
    required this.isReplay,
  });

  final String orderId;
  final String accessToken;
  final DateTime expiresAt;
  final bool isReplay;

  factory PublicOrderCheckoutAccess.fromRpc(Object? value) {
    if (value is! Map) {
      throw const FormatException('Checkout seguro sin respuesta válida');
    }

    final json = Map<String, dynamic>.from(value);
    final orderId = json['order_id']?.toString().trim() ?? '';
    final accessToken = json['access_token']?.toString().trim() ?? '';
    final expiresAt = DateTime.tryParse(
      json['expires_at']?.toString() ?? '',
    );

    if (orderId.isEmpty ||
        accessToken.length < 40 ||
        accessToken.length > 128 ||
        expiresAt == null) {
      throw const FormatException('Checkout seguro incompleto');
    }

    return PublicOrderCheckoutAccess(
      orderId: orderId,
      accessToken: accessToken,
      expiresAt: expiresAt,
      isReplay: json['replay'] == true,
    );
  }
}

/// Maps the deliberately redacted token reader response into the existing
/// presentation model. Missing customer identity/address fields stay empty;
/// they are never inferred or fetched through a second public query.
OnlineOrder onlineOrderFromPublicAccessResponse(
  Object? value, {
  required String expectedOrderId,
}) {
  if (value is! Map) {
    throw const FormatException('Pedido no encontrado o acceso vencido');
  }

  final envelope = Map<String, dynamic>.from(value);
  final rawOrder = envelope['order'];
  if (rawOrder is! Map) {
    throw const FormatException('Respuesta pública de pedido inválida');
  }

  final order = Map<String, dynamic>.from(rawOrder);
  final orderId = order['id']?.toString() ?? '';
  if (orderId.isEmpty || orderId != expectedOrderId) {
    throw const FormatException('El acceso no corresponde a este pedido');
  }

  final createdAt = order['createdAt']?.toString();
  final updatedAt = order['updatedAt']?.toString() ?? createdAt;
  if (createdAt == null ||
      DateTime.tryParse(createdAt) == null ||
      updatedAt == null ||
      DateTime.tryParse(updatedAt) == null) {
    throw const FormatException('Fechas públicas de pedido inválidas');
  }

  final rawItems = envelope['items'];
  final items = rawItems is List
      ? rawItems.map((rawItem) {
          if (rawItem is! Map) {
            throw const FormatException('Ítem público de pedido inválido');
          }
          final item = Map<String, dynamic>.from(rawItem);
          return <String, dynamic>{
            'id': '',
            'order_id': orderId,
            'product_name': item['name']?.toString() ?? 'Producto',
            'product_sku': item['sku']?.toString(),
            'quantity': item['quantity'],
            'unit_price': item['unitPrice'],
            'subtotal': item['subtotal'],
            'tax_rate': item['taxRate'],
            'created_at': createdAt,
          };
        }).toList()
      : const <Map<String, dynamic>>[];

  return OnlineOrder.fromJson({
    'id': orderId,
    'tenant_id': '',
    'order_number': order['number']?.toString() ?? 'N/A',
    'customer_email': '',
    'customer_name': '',
    'delivery_type': order['deliveryType']?.toString() ?? 'shipping',
    'shipping_carrier': order['trackingCarrier']?.toString(),
    'tracking_number': order['trackingNumber']?.toString(),
    'tracking_url': order['trackingUrl']?.toString(),
    'subtotal': order['subtotal'],
    'tax_amount': order['taxAmount'],
    'shipping_cost': order['shippingCost'],
    'discount_amount': order['discountAmount'],
    'total': order['total'],
    'status': order['status']?.toString() ?? 'pending',
    'payment_status': order['paymentStatus']?.toString() ?? 'pending',
    'payment_method': order['paymentMethod']?.toString(),
    'ready_for_pickup_at': order['readyForPickupAt']?.toString(),
    'shipped_at': order['shippedAt']?.toString(),
    'delivered_at': order['deliveredAt']?.toString(),
    'cancelled_at': order['cancelledAt']?.toString(),
    'created_at': createdAt,
    'updated_at': updatedAt,
    'online_order_items': items,
    'storefront_identity': envelope['storefront'],
  });
}
