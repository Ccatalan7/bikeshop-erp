import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/messaging/providers/chat_provider.dart';
import 'package:vinabike_erp/modules/purchases/models/purchase_invoice.dart';
import 'package:vinabike_erp/modules/purchases/services/purchase_service.dart';
import 'package:vinabike_erp/shared/models/supplier.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';
import 'package:vinabike_erp/shared/services/right_toolbar_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
import 'package:vinabike_erp/shared/widgets/quick_supplier_messages_panel.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets(
    'minimum right-toolbar panel width fuses supplier filters without overflow',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(600, 760));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => ChatProvider()),
            ChangeNotifierProvider<PurchaseService>(
              create: (_) => _EmptyPurchaseService(),
            ),
            ChangeNotifierProvider(create: (_) => RightToolbarService()),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  // RightToolbar's 320 px minimum includes its 48 px icon rail.
                  width: 272,
                  height: 720,
                  child: QuickSupplierMessagesPanel(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('supplier_toolbar_compact')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('supplier_toolbar_regular')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.byKey(const ValueKey('supplier_toolbar_compact_menu')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Todos'), findsOneWidget);
      expect(find.text('Sin leer'), findsOneWidget);
      expect(find.text('Activos'), findsOneWidget);
      expect(find.text('Historial'), findsOneWidget);

      await tester.tap(find.text('Sin leer'));
      await tester.pumpAndSettle();

      expect(find.text('Sin leer · Activos'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _EmptyPurchaseService extends PurchaseService {
  _EmptyPurchaseService() : super(DatabaseService(), TenantService());

  @override
  Future<List<Supplier>> getSuppliers({
    bool forceRefresh = false,
    bool activeOnly = false,
  }) async {
    return const [];
  }

  @override
  Future<List<PurchaseInvoice>> getPurchaseInvoicesForList({
    bool forceRefresh = false,
  }) async {
    return const [];
  }
}
