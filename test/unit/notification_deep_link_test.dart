import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/utils/notification_deep_link.dart';

void main() {
  group('notification deep links', () {
    test('opens the exact workshop job', () {
      expect(
        resolveErpNotificationRoute({
          'type': 'mechanic_job_created',
          'entity_type': 'mechanic_job',
          'entity_id': 'job/42',
          'route': '/taller/pegas',
        }),
        '/taller/pegas/job%2F42',
      );
    });

    test('archived workshop activity opens the surviving jobs module', () {
      expect(
        resolveErpNotificationRoute({
          'type': 'mechanic_job_archived',
          'entity_type': 'mechanic_job',
          'entity_id': 'archived-job-42',
          'route': '/taller/pegas',
        }),
        '/taller/pegas',
      );
    });

    test('opens the exact sales payment', () {
      expect(
        resolveErpNotificationRoute({
          'type': 'sales_payment_received',
          'entity_type': 'sales_payment',
          'entity_id': 'payment-42',
          'route': '/sales/payments',
        }),
        '/sales/payments?paymentId=payment-42',
      );
    });

    test('opens the surviving invoice for a voided sales payment', () {
      expect(
        resolveErpNotificationRoute({
          'type': 'sales_payment_voided',
          'entity_type': 'sales_payment',
          'entity_id': 'deleted-payment-42',
          'route': '/sales/invoices/invoice-42',
          'data': {'invoice_id': 'invoice/42'},
        }),
        '/sales/invoices/invoice%2F42',
      );
      expect(
        withNotificationOpenRequest(
          '/sales/invoices/invoice-42',
          requestId: 'request-voided',
        ),
        '/sales/invoices/invoice-42?openRequest=request-voided',
      );
    });

    test('opens the exact expense', () {
      expect(
        resolveErpNotificationRoute({
          'type': 'expense_recorded',
          'entity_type': 'expense',
          'entity_id': 'expense/42',
          'route': '/accounting/expenses',
        }),
        '/accounting/expenses/expense%2F42',
      );
    });

    test('expense lifecycle routes only target records that still exist', () {
      expect(
        resolveErpNotificationRoute({
          'type': 'expense_voided',
          'entity_type': 'expense',
          'entity_id': 'expense/voided',
        }),
        '/accounting/expenses/expense%2Fvoided',
      );
      expect(
        resolveErpNotificationRoute({
          'type': 'expense_deleted',
          'entity_type': 'expense',
          'entity_id': 'expense/deleted',
          'route': '/accounting/expenses',
        }),
        '/accounting/expenses',
      );
    });

    test('opens the exact online order and catalog product', () {
      expect(
        resolveErpNotificationRoute({
          'type': 'online_order_created',
          'data': {'order_id': 'order-42'},
        }),
        '/website/orders?order=order-42',
      );
      expect(
        resolveErpNotificationRoute({
          'type': 'online_order_cancelled',
          'data': {'order_id': 'cancelled-order-42'},
        }),
        '/website/orders?order=cancelled-order-42',
      );
      expect(
        resolveErpNotificationRoute({
          'type': 'whatsapp_catalog_approved',
          'data': {'product_id': 'product-42'},
        }),
        '/inventory/products/product-42/edit',
      );
    });

    test('preserves exact mail, chat, and stored-file identity', () {
      expect(
        resolveErpNotificationRoute({
          'type': 'mail',
          'data': {
            'provider_id': 'zoho ventas',
            'message_id': 'message/42',
          },
        }),
        '/mail?providerId=zoho+ventas&messageId=message%2F42',
      );
      expect(
        resolveErpNotificationRoute({
          'entity_type': 'conversation',
          'entity_id': 'conversation-42',
        }),
        '/chat?conversation=conversation-42',
      );
      expect(
        resolveErpNotificationRoute({
          'entity_type': 'app_file',
          'entity_id': 'file-42',
        }),
        '/storage?file=file-42',
      );
    });

    test('keeps trusted-provider and generic stored routes as fallbacks', () {
      expect(
        resolveErpNotificationRoute({
          'type': 'meta_instagram_comment',
          'route': 'https://www.instagram.com/p/example/',
        }),
        'https://www.instagram.com/p/example/',
      );
      expect(
        resolveErpNotificationRoute({
          'type': 'other',
          'route': '/dashboard',
        }),
        '/dashboard',
      );
    });

    test('makes repeated concrete destinations independently actionable', () {
      expect(
        withNotificationOpenRequest(
          '/mail?providerId=gmail&messageId=message-42',
          requestId: 'request-a',
        ),
        '/mail?providerId=gmail&messageId=message-42&openRequest=request-a',
      );
      expect(
        withNotificationOpenRequest(
          '/sales/payments?paymentId=payment-42',
          requestId: 'request-b',
        ),
        '/sales/payments?paymentId=payment-42&openRequest=request-b',
      );
      expect(
        withNotificationOpenRequest(
          '/taller/pegas/job-42',
          requestId: 'request-c',
        ),
        '/taller/pegas/job-42?openRequest=request-c',
      );
      expect(
        withNotificationOpenRequest(
          '/accounting/expenses/expense-42',
          requestId: 'request-d',
        ),
        '/accounting/expenses/expense-42?openRequest=request-d',
      );
      expect(
        withNotificationOpenRequest(
          '/sales/payments',
          requestId: 'ignored',
        ),
        '/sales/payments',
      );
    });
  });
}
