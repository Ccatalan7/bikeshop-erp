import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/public_store/pages/customer_addresses_page.dart';
import 'package:vinabike_erp/public_store/providers/public_store_tenant_provider.dart';
import 'package:vinabike_erp/public_store/services/address_autocomplete_service.dart';
import 'package:vinabike_erp/public_store/services/customer_account_service.dart';
import 'package:vinabike_erp/shared/services/tenant_detection_service.dart';

class _FakeAddressAutocompleteService extends AddressAutocompleteService {
  @override
  Future<void> initialize({String? tenantId}) async {}
}

class _FakeCustomerAccountService extends CustomerAccountService {
  @override
  bool get isAuthenticated => true;

  @override
  Map<String, dynamic>? get customerProfile => const {
        'name': 'Cliente Prueba',
        'email': 'cliente@example.com',
      };
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets(
    'address dialog retains its route-scoped autocomplete provider',
    (tester) async {
      final accountService = _FakeCustomerAccountService();
      final tenantProvider =
          PublicStoreTenantProvider(TenantDetectionService());
      final autocompleteService = _FakeAddressAutocompleteService();
      final router = GoRouter(
        initialLocation: '/cuenta/direcciones',
        overridePlatformDefaultLocation: true,
        routes: [
          GoRoute(
            path: '/cuenta/direcciones',
            builder: (_, __) => const Scaffold(
              body: CustomerAddressesPage(),
            ),
          ),
          GoRoute(
            path: '/cuenta/login',
            builder: (_, __) => const SizedBox.shrink(),
          ),
        ],
      );

      addTearDown(accountService.dispose);
      addTearDown(tenantProvider.dispose);
      addTearDown(autocompleteService.dispose);
      addTearDown(router.dispose);
      await tester.binding.setSurfaceSize(const Size(800, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<CustomerAccountService>.value(
              value: accountService,
            ),
            ChangeNotifierProvider<PublicStoreTenantProvider>.value(
              value: tenantProvider,
            ),
            ChangeNotifierProvider<AddressAutocompleteService>.value(
              value: autocompleteService,
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final addAddress = find.text('Agregar la primera dirección');
      await tester.ensureVisible(addAddress);
      await tester.pumpAndSettle();
      await tester.tap(addAddress);
      await tester.pump();
      await tester.pump();

      expect(find.text('Nueva Dirección'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
