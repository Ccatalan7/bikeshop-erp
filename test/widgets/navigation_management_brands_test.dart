import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/inventory/models/brand_directory.dart';
import 'package:vinabike_erp/modules/inventory/services/brand_directory_service.dart';
import 'package:vinabike_erp/modules/inventory/services/category_service.dart';
import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/modules/website/pages/navigation_management_page.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/modules/website/widgets/navigation_brand_picker.dart';
import 'package:vinabike_erp/shared/services/database_service.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

const _tenantId = '7e300917-0000-4000-8000-0000000000f2';
const _shimano = '7e300917-0000-4000-8000-0000000000b1';
const _maxxis = '7e300917-0000-4000-8000-0000000000b2';
const _kenda = '7e300917-0000-4000-8000-0000000000b3';
const _retired = '7e300917-0000-4000-8000-0000000000b4';

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

/// The shop's brands: two on sale, one without products in the store, and
/// one turned off in «Inventario › Marcas».
class _Brands implements BrandDirectorySource {
  @override
  Future<List<BrandDirectoryEntry>> directory() async => const [
        BrandDirectoryEntry(id: _kenda, name: 'Kenda', shared: true),
        BrandDirectoryEntry(
          id: _shimano,
          name: 'Shimano',
          shared: true,
          onWeb: 120,
          logoUrl: 'https://img.example/shimano.webp',
        ),
        BrandDirectoryEntry(
            id: _maxxis, name: 'Maxxis', shared: true, onWeb: 20),
        BrandDirectoryEntry(
          id: _retired,
          name: 'Retirada',
          shared: false,
          isActive: false,
        ),
      ];

  @override
  Future<BrandPageData?> page(String brandId) async => null;
}

/// The header holds «Marcas», a group without its own page.
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
  final updated = <WebsiteNavigation>[];

  late final brandsGroup = WebsiteNavigation(
    id: 'marcas',
    tenantId: _tenantId,
    label: 'Marcas',
    linkType: NavLinkType.page,
    linkValue: '',
    orderIndex: 5,
    cssClass: 'megamenu',
    createdAt: DateTime(2026, 11, 21),
    updatedAt: DateTime(2026, 11, 21),
    children: [
      WebsiteNavigation(
        id: 'marca-kenda',
        tenantId: _tenantId,
        label: 'Kenda',
        linkType: NavLinkType.brand,
        linkValue: _kenda,
        orderIndex: 0,
        parentId: 'marcas',
        createdAt: DateTime(2026, 11, 21),
        updatedAt: DateTime(2026, 11, 21),
      ),
    ],
  );

  @override
  Future<void> loadNavigation() async {}

  @override
  List<WebsiteNavigation> get headerNavigation => [brandsGroup];

  @override
  List<WebsiteNavigation> get footerNavigation => const [];

  @override
  Future<WebsiteNavigation> createNavigation(WebsiteNavigation nav) async {
    final saved = nav.copyWith(id: 'nav-${created.length + 1}');
    created.add(saved);
    return saved;
  }

  @override
  Future<WebsiteNavigation> updateNavigation(WebsiteNavigation nav) async {
    updated.add(nav);
    return nav;
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

  Future<_NavWebsiteService> openPage(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final tenantService = _tenantService();
    await tenantService.getTenantId();
    final service = _NavWebsiteService(tenantService);
    addTearDown(service.dispose);
    final categories = CategoryService(
      DatabaseService(client: _offlineClient(), tenantService: tenantService),
      tenantService,
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<WebsiteService>.value(value: service),
          ChangeNotifierProvider<TenantService>.value(value: tenantService),
          ChangeNotifierProvider<CategoryService>.value(value: categories),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: NavigationManagementPage(
              embedded: true,
              brandSource: _Brands(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return service;
  }

  testWidgets(
    'a new «Marca» link adds one link per brand chosen, in the order chosen, '
    'named after each brand and after the ones already there',
    (tester) async {
      final service = await openPage(tester);
      // Under «Marcas», which already holds Kenda.
      await tester.tap(find.byTooltip('Más acciones de Marcas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar subenlace'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Marca'));
      await tester.pumpAndSettle();

      // Active brands only, the ones on sale first.
      final rows = [
        for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
          if (tile.key case ValueKey<String>(:final value)
              when value.startsWith('navigation-brand-'))
            value,
      ];
      expect(rows, [
        NavigationBrandPicker.rowKey(_shimano).value,
        NavigationBrandPicker.rowKey(_maxxis).value,
        NavigationBrandPicker.rowKey(_kenda).value,
      ]);
      expect(find.text('120 en la tienda'), findsOneWidget);
      expect(find.text('Sin productos en la tienda'), findsOneWidget);

      await tester.tap(find.byKey(NavigationBrandPicker.rowKey(_maxxis)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(NavigationBrandPicker.rowKey(_shimano)));
      await tester.pumpAndSettle();
      expect(
        find.text('Se agregan 2 enlaces, uno por marca, con su nombre.'),
        findsOneWidget,
      );

      // The search narrows the list.
      await tester.enterText(
        find.byKey(NavigationBrandPicker.searchKey),
        'shi',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(NavigationBrandPicker.rowKey(_maxxis)), findsNothing);
      expect(
        find.byKey(NavigationBrandPicker.rowKey(_shimano)),
        findsOneWidget,
      );

      await tester.tap(find.text('Crear'));
      await tester.pumpAndSettle();

      expect(
        service.created
            .map((n) =>
                (n.label, n.linkType, n.linkValue, n.parentId, n.orderIndex))
            .toList(),
        [
          ('Maxxis', NavLinkType.brand, _maxxis, 'marcas', 1),
          ('Shimano', NavLinkType.brand, _shimano, 'marcas', 2),
        ],
      );
      expect(service.created.first.href, '/productos?brand=$_maxxis');
    },
  );

  testWidgets(
    'a saved brand link reopens on its brand, and choosing another renames '
    'it unless the person wrote a name of their own',
    (tester) async {
      final service = await openPage(tester);
      await tester.tap(find.byTooltip('Expandir Marcas'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Más acciones de Kenda'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();

      final kenda = tester.widget<ListTile>(
        find.byKey(NavigationBrandPicker.rowKey(_kenda)),
      );
      expect(kenda.selected, isTrue);

      await tester.tap(find.byKey(NavigationBrandPicker.rowKey(_maxxis)));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey<String>('navigation-label-field')),
            )
            .controller
            ?.text,
        'Maxxis',
      );
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(
        service.updated.map((n) => (n.id, n.label, n.linkValue)).toList(),
        [('marca-kenda', 'Maxxis', _maxxis)],
      );
    },
  );
}
