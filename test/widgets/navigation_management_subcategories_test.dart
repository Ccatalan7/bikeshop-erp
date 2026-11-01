import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/inventory/models/category_models.dart'
    as cat_models;
import 'package:vinabike_erp/modules/inventory/services/category_service.dart';
import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/modules/website/pages/navigation_management_page.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

const _tenantId = '7e300917-0000-4000-8000-0000000000f2';
const _toolsId = '7e300917-0000-4000-8000-0000000000c0';
const _chainToolId = '7e300917-0000-4000-8000-0000000000c1';
const _bottlesId = '7e300917-0000-4000-8000-0000000000c2';

SupabaseClient _offlineClient() => SupabaseClient(
      'https://example.supabase.co',
      'test-anon-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient(
        (request) async => http.Response(jsonEncode([]), 200,
            headers: {'content-type': 'application/json'}),
      ),
    );

TenantService _tenantService() => TenantService.testing(
      currentUserId: () => 'user-a',
      profileLookup: (_) async => const [
        {'tenant_id': _tenantId, 'role': 'admin', 'permissions': null},
      ],
    );

cat_models.Category _category(String id, String name, String path,
        {String? parentId}) =>
    cat_models.Category(
      id: id,
      tenantId: _tenantId,
      name: name,
      fullPath: path,
      parentId: parentId,
      level: parentId == null ? 0 : 1,
      showOnWebsite: true,
    );

/// Herramientas with two subcategories, as in production on 2026-11-01.
class _Categories extends CategoryService {
  _Categories(TenantService tenantService)
      : super(
          DatabaseService(
            client: _offlineClient(),
            tenantService: tenantService,
          ),
          tenantService,
        );

  final _tools = _category(_toolsId, 'Herramientas', 'Herramientas');
  late final _subs = [
    _category(_chainToolId, 'Corta Cadena', 'Herramientas / Corta Cadena',
        parentId: _toolsId),
    _category(_bottlesId, 'Botellas aplicadoras',
        'Herramientas / Botellas aplicadoras',
        parentId: _toolsId),
  ];

  @override
  Future<List<cat_models.Category>> getCategories({
    String? searchTerm,
    bool? activeOnly,
    bool forceRefresh = false,
  }) async =>
      [_tools, ..._subs];

  @override
  Future<cat_models.Category?> getCategoryById(String id) async =>
      [_tools, ..._subs].where((c) => c.id == id).firstOrNull;

  @override
  Future<List<cat_models.Category>> getSubcategories(String parentId) async =>
      parentId == _toolsId ? _subs : const [];
}

class _NavWebsiteService extends WebsiteService {
  _NavWebsiteService(TenantService tenantService)
      : super(
          supabase: _offlineClient(),
          tenantService: tenantService,
          httpClient: MockClient(
            (request) async => throw StateError('no edge calls'),
          ),
        );

  final created = <WebsiteNavigation>[];

  @override
  Future<void> loadNavigation() async {}

  @override
  List<WebsiteNavigation> get headerNavigation => const [];

  @override
  List<WebsiteNavigation> get footerNavigation => const [];

  @override
  Future<WebsiteNavigation> createNavigation(WebsiteNavigation nav) async {
    final saved = nav.copyWith(id: 'nav-${created.length + 1}');
    created.add(saved);
    return saved;
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      publishableKey: 'test-anon-key',
    );
  });

  /// Opens «Agregar enlace» and points it at Herramientas, whose two
  /// subcategories the dialog checks on its own.
  Future<_NavWebsiteService> openToolsLink(
    WidgetTester tester, {
    required String name,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final tenantService = _tenantService();
    await tenantService.getTenantId();
    final service = _NavWebsiteService(tenantService);
    addTearDown(service.dispose);
    final categories = _Categories(tenantService);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<WebsiteService>.value(value: service),
          ChangeNotifierProvider<TenantService>.value(value: tenantService),
          ChangeNotifierProvider<CategoryService>.value(value: categories),
        ],
        child: const MaterialApp(
          home: Scaffold(body: NavigationManagementPage(embedded: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Agregar enlace').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Categoría'));
    await tester.pumpAndSettle();
    if (name.isNotEmpty) {
      await tester.enterText(
        find.byKey(const ValueKey<String>('navigation-label-field')),
        name,
      );
    }
    await tester.tap(find.text('Categoría *'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Herramientas').last);
    await tester.pumpAndSettle();
    expect(find.text('Incluir Subcategorías:'), findsOneWidget);
    return service;
  }

  testWidgets(
    'a named category link is created, with its subcategories under it',
    (tester) async {
      final service = await openToolsLink(tester, name: 'Herramientas');
      expect(find.text('Las marcadas van debajo de «Herramientas».'),
          findsOneWidget);

      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();

      expect(
        service.created.map((n) => (n.label, n.parentId)).toList(),
        [
          ('Herramientas', null),
          ('Corta Cadena', 'nav-1'),
          ('Botellas aplicadoras', 'nav-1'),
        ],
        reason: 'The link the person named can never be dropped.',
      );
      expect(service.created.first.linkValue, contains(_toolsId));
    },
  );

  testWidgets(
    'without a name only the checked subcategories are added, side by side',
    (tester) async {
      final service = await openToolsLink(tester, name: '');
      expect(
        find.text('Sin texto del enlace, se agregan sólo las marcadas, '
            'cada una como enlace propio.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();

      expect(
        service.created.map((n) => (n.label, n.parentId)).toList(),
        [('Corta Cadena', null), ('Botellas aplicadoras', null)],
      );
    },
  );
}
