import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/website/catalog/catalog_web_controller.dart';
import 'package:vinabike_erp/modules/website/catalog/catalog_web_models.dart';
import 'package:vinabike_erp/modules/website/catalog/catalog_web_service.dart';
import 'package:vinabike_erp/modules/website/catalog/website_catalog_workspace.dart';
import 'package:vinabike_erp/public_store/widgets/catalog_price_list_view.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

/// The store catalog (2026-10-10) on the sizes and themes it is used in,
/// with rows shaped like `catalog_web_items_v1`'s: every tab draws without a
/// layout error, the detail shows the real store card, and a switch is a
/// catalog command.
void main() {
  Map<String, dynamic> row(
    String id,
    String name, {
    String kind = 'product',
    String state = 'venta',
    String? block,
    List<String> issues = const [],
    num price = 14000,
    num cost = 5000,
    int stock = 3,
    bool webOn = true,
    String priceMode = 'exact',
    String category = 'c-acc',
  }) =>
      {
        'id': id,
        'name': name.toUpperCase(),
        'website_name': name,
        'sku': 'SKU-$id',
        'kind': kind,
        'category_id': category,
        'category_name': category == 'c-srv' ? 'Frenos' : 'Accesorios',
        'brand_id': 'b1',
        'brand': 'INBIKE',
        'price': price,
        'web_price': price,
        'cost': cost,
        'tax_rate': 19,
        'min_web_price': (cost * 1.19).ceil(),
        'image_url': null,
        'has_description': true,
        'web_on': webOn,
        'is_active': true,
        'price_mode': priceMode,
        'stock': stock,
        'available': kind == 'service' ? null : stock,
        'block': block,
        'state': state,
        'sold_counter_12m': 4,
        'used_jobs_12m': 0,
        'sold_total_12m': 4,
        'issues': issues,
      };

  final rows = [
    row('p1', 'Bolso triangular para cuadro'),
    row('p2', 'Cámara aro 29 válvula auto', stock: 0, state: 'agotado'),
    row('p3', 'Maza trasera 36 rayos',
        state: 'falta', block: 'missing_image', issues: ['missing_image']),
    row('p4', 'Capuchón piola',
        kind: 'consumable', state: 'taller', webOn: false),
    row('p5', 'Extractor de cono',
        price: 29990,
        cost: 26990,
        state: 'falta',
        block: 'below_cost',
        issues: ['below_cost']),
    row('s1', 'Purgado de frenos hidráulicos',
        kind: 'service', price: 18000, cost: 0, category: 'c-srv'),
    row('s2', 'Restauración',
        kind: 'service',
        price: 0,
        cost: 0,
        priceMode: 'quote',
        category: 'c-srv'),
  ];

  ThemeData theme(Brightness brightness) => AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: brightness,
      );

  late _FakeCatalogService service;
  late CatalogWebController controller;

  setUp(() {
    service = _FakeCatalogService(rows);
    controller = CatalogWebController(
      service: service,
      tenantService: TenantService.testing(
        currentUserId: () => 'user-1',
        profileLookup: (_) async => [
          {'tenant_id': 'tenant-1', 'role': 'admin', 'permissions': {}},
        ],
      ),
      saveSettings: (_) async {},
    );
  });

  Future<void> pump(
    WidgetTester tester, {
    required Size size,
    Brightness brightness = Brightness.light,
    CatalogWorkspaceTab tab = CatalogWorkspaceTab.products,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: theme(brightness),
      home: Scaffold(
        body: WebsiteCatalogWorkspace(
          initialTab: tab,
          controller: controller,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  for (final (label, size) in [
    ('desktop', const Size(1600, 1000)),
    ('phone', const Size(390, 844)),
  ]) {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';
      testWidgets('every tab draws on $label, $mode', (tester) async {
        await pump(
          tester,
          size: size,
          brightness: dark ? Brightness.dark : Brightness.light,
        );
        expect(find.text('Bolso triangular para cuadro'), findsWidgets);
        for (final tab in [
          'Por resolver',
          'Servicios',
          'Categorías',
          'Destacados'
        ]) {
          final target = find.bySemanticsLabel(RegExp('^$tab'));
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          await tester.tap(target);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: '$tab on $label $mode');
        }
      });
    }
  }

  testWidgets('a product detail shows the ladder and the store card',
      (tester) async {
    await pump(tester, size: const Size(1600, 1000));
    await tester.tap(find.text('Bolso triangular para cuadro').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Vender en la web'), findsOneWidget);
    expect(find.text('Así se ve en vinabike.cl'), findsOneWidget);
  });

  testWidgets('on the phone the detail opens as a sheet', (tester) async {
    await pump(tester, size: const Size(390, 844));
    await tester.tap(find.text('Bolso triangular para cuadro').first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Vender en la web'), findsOneWidget);
  });

  testWidgets('on the phone /servicios opens as the real page', (tester) async {
    await pump(
      tester,
      size: const Size(390, 844),
      tab: CatalogWorkspaceTab.services,
    );
    await tester.tap(find.text('Ver /servicios'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(CatalogPriceListView), findsOneWidget);
    // A quoted service reads «A cotizar» on the page, as in the store.
    expect(find.text('A cotizar'), findsWidgets);
  });

  testWidgets('a service switch is a catalog command', (tester) async {
    await pump(
      tester,
      size: const Size(1600, 1000),
      tab: CatalogWorkspaceTab.services,
    );
    expect(find.text('Así se ve /servicios'), findsOneWidget);

    await tester.tap(
      find.bySemanticsLabel('Vender Purgado de frenos hidráulicos en la web'),
    );
    await tester.pumpAndSettle();

    expect(service.webSaleCalls, hasLength(1));
    expect(service.webSaleCalls.single.ids, ['s1']);
    expect(service.webSaleCalls.single.on, isFalse);
  });
}

class _FakeCatalogService extends CatalogWebService {
  _FakeCatalogService(this.rows)
      : super(SupabaseClient('http://localhost:54321', 'test-anon-key'));

  final List<Map<String, dynamic>> rows;
  final webSaleCalls = <({List<String> ids, bool on})>[];

  @override
  Future<List<CatalogWebItem>> loadItems(String tenantId) async =>
      [for (final row in rows) CatalogWebItem.fromRow(row)];

  @override
  Future<({Map<String, String> services, Map<String, String> categories})>
      loadServiceTexts(String tenantId) async => (
            services: {'s1': 'Cambio de aceite y ajuste de manillas.'},
            categories: const <String, String>{},
          );

  @override
  Future<CatalogRules> loadRules(String tenantId) async => const CatalogRules();

  @override
  Future<List<CatalogCategoryCount>> loadCategoryCounts(
          String tenantId) async =>
      [
        CatalogCategoryCount.fromRow(const {
          'category_id': 'c-acc',
          'name': 'Accesorios',
          'parent_id': null,
          'full_path': 'Accesorios',
          'level': 0,
          'sort_order': 1,
          'show_on_website': true,
          'subcategories': 0,
          'selling': 1,
          'out_of_stock': 1,
          'needs_attention': 2,
          'selling_direct': 1,
        }),
        CatalogCategoryCount.fromRow(const {
          'category_id': 'c-srv',
          'name': 'Frenos',
          'parent_id': null,
          'full_path': 'Frenos',
          'level': 0,
          'sort_order': 2,
          'show_on_website': false,
          'subcategories': 0,
          'selling': 0,
          'out_of_stock': 0,
          'needs_attention': 0,
          'selling_direct': 0,
        }),
      ];

  @override
  Future<List<String>> loadFeaturedIds(String tenantId) async => const ['p1'];

  @override
  Future<List<int>> loadFeaturedBlockLimits(String tenantId) async => const [6];

  @override
  Future<List<CatalogFeaturedSuggestion>> loadFeaturedSuggestions(
    String tenantId, {
    int limit = 16,
    int minStock = 2,
  }) async =>
      [
        CatalogFeaturedSuggestion.fromRow(const {
          'product_id': 'p1',
          'name': 'Bolso triangular para cuadro',
          'web_price': 14000,
          'available': 3,
          'sold_total_12m': 4,
          'margin_pct': 40,
        }),
      ];

  @override
  Future<CatalogWebSaleResult> setWebSale({
    required String tenantId,
    required Iterable<String> productIds,
    required bool on,
  }) async {
    webSaleCalls.add((ids: productIds.toList(), on: on));
    return CatalogWebSaleResult(
      changed: productIds.length,
      skippedConsumables: 0,
      skippedInactive: 0,
      skippedUntaxed: 0,
    );
  }
}
