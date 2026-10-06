/// The customer's words for an online order's raw states: one owner for the
/// ERP's `OnlineOrder` getters, the order summary PDF and the HTML store.
library;

/// `OnlineOrder.statusDisplayName`.
String onlineOrderStatusLabel(String status) => switch (status) {
  'pending' => 'Pendiente',
  'confirmed' => 'Confirmado',
  'processing' => 'En Proceso',
  'ready_for_pickup' => 'Listo para retiro',
  'shipped' => 'Enviado',
  'delivered' => 'Entregado',
  'cancelled' => 'Cancelado',
  _ => status,
};

/// `OnlineOrder.paymentStatusDisplayName`.
String onlineOrderPaymentStatusLabel(String paymentStatus) =>
    switch (paymentStatus) {
      'pending' => 'Pendiente',
      'paid' => 'Pagado',
      'failed' => 'Fallido',
      'refunded' => 'Reembolsado',
      _ => paymentStatus,
    };

/// Canonical operator-facing name for an online-order delivery mode.
String onlineOrderDeliveryLabel(String deliveryType) => switch (deliveryType) {
  'pickup' => 'Retiro en tienda',
  'shipping' => 'Despacho',
  _ => deliveryType,
};
