import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/website/models/website_editor_capability.dart';
import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/modules/website/pages/navigation_management_page.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

const _tenantId = '7e300917-0000-4000-8000-0000000000f1';

class _UserBox {
  String? id = 'user-a';
}

class _AuthTenantService extends TenantService {
  _AuthTenantService(this._box)
      : super.testing(
          currentUserId: () => _box.id,
          profileLookup: (_) async => const [
            {'tenant_id': _tenantId, 'role': 'admin', 'permissions': null},
          ],
        );

  final _UserBox _box;

  void emitAuthChange() {
    clearCache();
    notifyListeners();
  }
}

WebsiteNavigation _link() => WebsiteNavigation(
      id: '7e300917-0000-4000-8000-0000000000aa',
      tenantId: _tenantId,
      menuLocation: MenuLocation.header,
      label: 'Mi enlace',
      linkType: NavLinkType.external,
      linkValue: '/x',
      createdAt: DateTime.utc(2026, 7, 30),
      updatedAt: DateTime.utc(2026, 7, 30),
    );

class _NavWebsiteService extends WebsiteService {
  _NavWebsiteService(TenantService tenantService)
      : super(
          supabase: SupabaseClient(
            'https://example.supabase.co',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
            httpClient: MockClient(
              (request) async => http.Response(jsonEncode([]), 200,
                  headers: {'content-type': 'application/json'}),
            ),
          ),
          tenantService: tenantService,
          httpClient: MockClient(
            (request) async => throw StateError('no edge calls'),
          ),
        );

  int deleteCalls = 0;

  /// null => success; otherwise thrown by the delete.
  Object? deleteError;

  /// When set, runs BETWEEN the pre- and post-request guard invocations
  /// (models an identity switch landing while the RPC is in flight).
  void Function()? midFlightSwitch;

  @override
  Future<void> loadNavigation() async {}

  @override
  List<WebsiteNavigation> get headerNavigation => [_link()];

  @override
  List<WebsiteNavigation> get footerNavigation => const [];

  @override
  Future<void> deleteNavigationForTenant(
    String navId,
    String tenantId, {
    WebsiteEditorWriteGuard? writeGuard,
  }) async {
    writeGuard?.call();
    deleteCalls++;
    final error = deleteError;
    if (error != null) throw error;
    midFlightSwitch?.call();
    // Post-response guard, exactly like the real implementation.
    writeGuard?.call();
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  Future<
      ({
        _NavWebsiteService service,
        _AuthTenantService tenantService,
        _UserBox box,
      })> pumpPage(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final box = _UserBox();
    final tenantService = _AuthTenantService(box);
    await tenantService.getTenantId(); // Warm identity caches.
    final service = _NavWebsiteService(tenantService);
    addTearDown(service.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<WebsiteService>.value(value: service),
          ChangeNotifierProvider<TenantService>.value(value: tenantService),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: NavigationManagementPage(embedded: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mi enlace'), findsOneWidget);
    return (service: service, tenantService: tenantService, box: box);
  }

  Future<void> openDeleteDialog(WidgetTester tester) async {
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar').last);
    await tester.pumpAndSettle();
    expect(find.text('Eliminar Enlace'), findsOneWidget);
  }

  testWidgets(
    'a 42501 rejection keeps the link on screen and NEVER shows success',
    (tester) async {
      final harness = await pumpPage(tester);
      harness.service.deleteError = const PostgrestException(
        message: 'website_navigation_delete_forbidden',
        code: '42501',
      );

      await openDeleteDialog(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();

      expect(harness.service.deleteCalls, 1);
      expect(find.textContaining('Error al eliminar'), findsOneWidget);
      expect(find.text('Enlace eliminado'), findsNothing,
          reason: 'A server rejection can NEVER read as success.');
      expect(find.text('Mi enlace'), findsOneWidget,
          reason: 'The link stays on screen: it is still published.');
    },
  );

  testWidgets(
    'an identity switch DURING the confirmation dialog supersedes the '
    'delete before any RPC',
    (tester) async {
      final harness = await pumpPage(tester);
      await openDeleteDialog(tester);

      // A -> B while the dialog is open.
      harness.box.id = 'user-b';
      harness.tenantService.emitAuthChange();
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();

      expect(harness.service.deleteCalls, 0,
          reason: 'The pre-request guard stops the stale command.');
      expect(
        find.text('La sesión cambió; el enlace no se modificó.'),
        findsOneWidget,
      );
      expect(find.text('Enlace eliminado'), findsNothing);
      expect(find.text('Mi enlace'), findsOneWidget);
    },
  );

  testWidgets(
    'an identity switch DURING the RPC supersedes the outcome: no success, '
    'link intact',
    (tester) async {
      final harness = await pumpPage(tester);
      harness.service.midFlightSwitch = () {
        harness.box.id = 'user-b';
        harness.tenantService.emitAuthChange();
      };

      await openDeleteDialog(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();

      expect(harness.service.deleteCalls, 1);
      expect(
        find.text('La sesión cambió; el enlace no se modificó.'),
        findsOneWidget,
      );
      expect(find.text('Enlace eliminado'), findsNothing);
      expect(find.text('Mi enlace'), findsOneWidget);
    },
  );
}
