import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/shared/services/workspace_manager.dart';

void main() {
  test('supplier profile is a registered routed read surface', () {
    final router = File(
      'lib/shared/routes/app_router.dart',
    ).readAsStringSync();
    final barrel = File(
      'lib/shared/routes/erp_routes_barrel.dart',
    ).readAsStringSync();

    expect(router, contains("path: '/purchases/suppliers/:id'"));
    expect(
      router,
      contains('erp.SupplierDetailPage(supplierId: id)'),
    );
    expect(
      barrel,
      contains("pages/supplier_detail_page.dart"),
    );
    expect(
      getRouteTitle(
        '/purchases/suppliers/20000000-0000-0000-0000-000000000002',
      ),
      'Proveedor',
    );
    expect(
      getRouteTitle(
        '/purchases/suppliers/20000000-0000-0000-0000-000000000002/edit',
      ),
      'Editar Proveedor',
    );
  });

  test('directory and messaging open profile, never edit directly', () {
    final sources = [
      File('lib/modules/purchases/pages/supplier_list_page.dart')
          .readAsStringSync(),
      File('lib/modules/messaging/widgets/chat_context_panel.dart')
          .readAsStringSync(),
      File('lib/modules/messaging/widgets/chat_window.dart').readAsStringSync(),
    ].join('\n');

    expect(sources, contains('/purchases/suppliers/'));
    expect(
      sources,
      isNot(contains("/purchases/suppliers/\${supplier.id}/edit")),
    );
    expect(
      sources,
      isNot(contains("/purchases/suppliers/\${profile.relationship.id}/edit")),
    );
  });

  test('detail owns the sole edit action and closes through return navigation',
      () {
    final detail = File(
      'lib/modules/purchases/pages/supplier_detail_page.dart',
    ).readAsStringSync();

    expect(
        detail, contains("'/purchases/suppliers/\${widget.supplierId}/edit'"));
    expect(detail, contains('ReturnNavigation.close('));
    expect(detail, isNot(contains("context.go('/purchases/suppliers")));
  });
}
