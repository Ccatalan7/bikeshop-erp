import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_models.dart';
import 'package:vinabike_erp/public_store/pages/order_confirmation_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('order summary renders with bundled Unicode fonts and redacted identity',
      () async {
    final createdAt = DateTime.utc(2026, 7, 18, 18, 30);
    final order = OnlineOrder(
      id: 'order-1',
      tenantId: '',
      orderNumber: 'WEB-26-00158',
      customerEmail: '',
      customerName: '',
      deliveryType: 'shipping',
      subtotal: 42008,
      taxAmount: 7982,
      shippingCost: 0,
      discountAmount: 0,
      total: 49990,
      status: 'confirmed',
      paymentStatus: 'paid',
      paymentMethod: 'mercadopago',
      createdAt: createdAt,
      updatedAt: createdAt,
      items: [
        OnlineOrderItem(
          id: 'item-1',
          orderId: 'order-1',
          productName: 'Casco urbano Viña Bike',
          quantity: 1,
          unitPrice: 49990,
          subtotal: 49990,
          taxRate: 19,
          createdAt: createdAt,
        ),
      ],
    );

    final bytes = await buildOrderPdfBytes(order);

    expect(bytes, isNotEmpty);
    expect(bytes.length, greaterThan(5000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });
}
