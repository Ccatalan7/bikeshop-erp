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

  // The base takes 8000 characters for a consultation and 1000 for a note;
  // the HTML store's server refuses past them, so Flutter's fields stop
  // there too instead of failing on send (Codex 10, 2026-10-08).
  test('customer chat fields stop at the lengths the base takes', () {
    final view = File(
      'lib/public_store/widgets/customer_chat_view.dart',
    ).readAsStringSync();
    final hub = File(
      'lib/public_store/pages/customer_chat_hub_page.dart',
    ).readAsStringSync();

    // In code points, as the base counts (Codex 11).
    expect('CodePointLengthFormatter('.allMatches(view).length, 2);
    expect(view, isNot(contains('LengthLimitingTextInputFormatter')));
    expect(view, contains('customerChatMessageMaxLength'));
    expect(
        view, contains('CodePointLengthFormatter(customerChatNoteMaxLength)'));
    expect(
      hub,
      contains('CodePointLengthFormatter(customerChatMessageMaxLength)'),
    );
  });

  test('customer pay requests do not expose a nonexistent payment route', () {
    final source = File(
      'lib/public_store/widgets/customer_chat_view.dart',
    ).readAsStringSync();

    // The card's rules and words live in the core since 2026-10-08, shared
    // with the HTML store's chat.
    final card = File(
      'packages/vinabike_public_core/lib/public_store/models/customer_chat_words.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('/tienda/cuenta/facturas/')));
    expect(source, isNot(contains('action=pay')));
    expect(source, contains('CustomerChatActionCard.of(msg.metadata)'));
    expect(card, contains("actionType == 'pay_now'"));
    expect(card, contains('El chat no abre cobros'));
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
    // El marco del portal ya no lleva un segundo chat en una columna
    // derecha (2026-09-24): el chat vive en «Soporte» y en el botón flotante.
    expect(portal, isNot(contains('CustomerChatSurface')));
    expect(launcher, contains('CustomerChatSurface('));
  });

  test('customer detail hosts apply the same context capability gate', () {
    final hub = File(
      'lib/public_store/pages/customer_chat_hub_page.dart',
    ).readAsStringSync();

    expect(hub, contains('CustomerChatContextSupport.supports(contextType)'));
  });
}
