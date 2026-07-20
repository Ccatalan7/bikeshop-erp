import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/public_store/widgets/customer_chat_context_support.dart';
import 'package:vinabike_erp/public_store/widgets/customer_chat_visibility.dart';

void main() {
  test('customer chat visibility requires active branch and current route', () {
    expect(
      isCustomerChatHostVisible(
        tickerEnabled: true,
        routeIsCurrent: true,
      ),
      isTrue,
    );
    expect(
      isCustomerChatHostVisible(
        tickerEnabled: false,
        routeIsCurrent: true,
      ),
      isFalse,
    );
    expect(
      isCustomerChatHostVisible(
        tickerEnabled: true,
        routeIsCurrent: false,
      ),
      isFalse,
    );
  });

  test('customer context policy exposes only implemented authorized readers',
      () {
    expect(CustomerChatContextSupport.supports('job'), isTrue);
    expect(CustomerChatContextSupport.supports('invoice'), isTrue);
    expect(CustomerChatContextSupport.supports('order'), isFalse);
    expect(CustomerChatContextSupport.supports('bike'), isFalse);
    expect(CustomerChatContextSupport.supports(null), isFalse);
  });

  test('parsed employee invoice references are read-only and open canonical',
      () {
    final source = File(
      'lib/modules/messaging/widgets/context_side_panel.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('SalesInvoiceEditor')));
    expect(source,
        contains("openRouteInWorkspace('/sales/invoices/\$invoiceId')"));
    expect(source, contains('Este panel no edita el documento'));
  });

  test('customer pay requests do not expose a nonexistent payment route', () {
    final source = File(
      'lib/public_store/widgets/customer_chat_view.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('/tienda/cuenta/facturas/')));
    expect(source, isNot(contains('action=pay')));
    expect(source, contains("actionType == 'pay_now'"));
    expect(source, contains('El chat no abre cobros'));
  });

  test('every compact customer chat host composes the canonical provider view',
      () {
    final surface = File(
      'lib/public_store/widgets/customer_chat_surface.dart',
    ).readAsStringSync();
    final portal = File(
      'lib/public_store/widgets/customer_portal_layout.dart',
    ).readAsStringSync();
    final launcher = File(
      'lib/public_store/widgets/customer_chat_widget.dart',
    ).readAsStringSync();

    expect(
      File('lib/public_store/widgets/customer_chat_panel.dart').existsSync(),
      isFalse,
    );
    expect(surface, contains('context.watch<ChatProvider>()'));
    expect(surface, contains('CustomerChatView('));
    expect(surface, isNot(contains('getMessagesStream(')));
    expect(portal, contains('CustomerChatSurface()'));
    expect(launcher, contains('CustomerChatSurface('));
  });

  test('customer detail hosts apply the same context capability gate', () {
    final hub = File(
      'lib/public_store/pages/customer_chat_hub_page.dart',
    ).readAsStringSync();
    final detail = File(
      'lib/public_store/pages/customer_chat_detail_page.dart',
    ).readAsStringSync();

    expect(hub, contains('CustomerChatContextSupport.supports(contextType)'));
    expect(
      detail,
      contains('CustomerChatContextSupport.supports(contextType)'),
    );
    expect(detail, isNot(contains("case 'order':")));
    expect(detail, isNot(contains("case 'bike':")));
  });
}
