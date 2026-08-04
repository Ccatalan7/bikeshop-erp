import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/inventory/models/category_models.dart';
import 'package:vinabike_erp/modules/website/models/website_action.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/modules/website/widgets/premium_product_card.dart';
import 'package:vinabike_erp/modules/website/widgets/website_action_button.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_content_presenters.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_renderer.dart';
import 'package:vinabike_erp/public_store/providers/public_store_tenant_provider.dart';
import 'package:vinabike_erp/public_store/services/public_inventory_service.dart';
import 'package:vinabike_erp/public_store/utils/product_url.dart';
import 'package:vinabike_erp/shared/models/product.dart';
import 'package:vinabike_erp/shared/models/tenant.dart';
import 'package:vinabike_erp/shared/services/tenant_detection_service.dart';

/// Inventory stub: the category grid resolves publication over an empty
/// catalog, so manual cards with generic destinations stay eligible without
/// any network access.
class _StubInventoryService extends PublicInventoryService {
  @override
  Future<List<Category>> getCategoriesForTenant({
    required String tenantId,
    bool forceRefresh = false,
  }) async =>
      const <Category>[];
}

Widget _rendererHost({
  required String blockType,
  required Map<String, dynamic> data,
  required bool Function(String href) isNavigationEligible,
  void Function(String route)? onNavigate,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => WebsiteBlockRenderer.build(
          context: context,
          blockType: blockType,
          data: data,
          primaryColor: Colors.blue,
          accentColor: Colors.green,
          onNavigate: onNavigate ?? (_) {},
          isNavigationEligible: isNavigationEligible,
        ),
      ),
    ),
  );
}

void main() {
  group('WebsiteBlockRenderer navigation eligibility', () {
    test('shared action filter preserves eligible and empty destinations', () {
      const eligible = WebsiteActionValue(
        label: 'Comprar',
        href: '/productos',
      );
      const empty = WebsiteActionValue(
        label: 'Configurar',
        href: '',
      );

      expect(
        WebsiteBlockRenderer.visibleNavigationAction(
          eligible,
          isNavigationEligible: (_) => true,
        ),
        same(eligible),
      );
      expect(
        WebsiteBlockRenderer.visibleNavigationAction(
          eligible,
          isNavigationEligible: (_) => false,
        ),
        isNull,
      );
      expect(
        WebsiteBlockRenderer.visibleNavigationAction(
          empty,
          isNavigationEligible: (_) => false,
        ),
        same(empty),
      );
      expect(
        WebsiteBlockRenderer.visibleNavigationAction(
          eligible,
          isNavigationEligible: null,
        ),
        same(eligible),
      );
    });

    testWidgets('public render removes ineligible CTA affordances',
        (tester) async {
      const hiddenLabel = 'CTA OCULTA';
      final cases = <({String type, Map<String, dynamic> data})>[
        (
          type: 'button',
          data: const <String, dynamic>{
            'label': hiddenLabel,
            'link': '/productos/categoria/pinones',
          },
        ),
        (
          type: 'hero',
          data: const <String, dynamic>{
            'title': 'Hero visible',
            'ctaText': hiddenLabel,
            'ctaLink': '/productos/categoria/pinones',
          },
        ),
        (
          type: 'cta',
          data: const <String, dynamic>{
            'title': 'Campaña visible',
            'buttonText': hiddenLabel,
            'buttonLink': '/productos/categoria/pinones',
          },
        ),
        (
          type: 'carousel',
          data: const <String, dynamic>{
            'autoPlay': false,
            'slides': [
              {
                'title': 'Slide visible',
                'ctaText': hiddenLabel,
                'ctaLink': '/productos/categoria/pinones',
              },
            ],
          },
        ),
        (
          type: 'pricing',
          data: const <String, dynamic>{
            'title': 'Planes visibles',
            'plans': [
              {
                'name': 'Plan visible',
                'price': '10.000',
                'ctaText': hiddenLabel,
                'ctaLink': '/productos/categoria/pinones',
              },
            ],
          },
        ),
        (
          type: 'videoBanner',
          data: const <String, dynamic>{
            'title': 'Video visible',
            'showCta': true,
            'ctaText': hiddenLabel,
            'ctaLink': '/productos/categoria/pinones',
          },
        ),
      ];

      for (final testCase in cases) {
        await tester.pumpWidget(
          _rendererHost(
            blockType: testCase.type,
            data: testCase.data,
            isNavigationEligible: (_) => false,
          ),
        );
        await tester.pump();

        expect(
          find.text(hiddenLabel),
          findsNothing,
          reason: '${testCase.type} exposed an ineligible CTA.',
        );
      }
    });

    testWidgets('Canvas buttons use the same public eligibility boundary',
        (tester) async {
      const hiddenLabel = 'CANVAS OCULTO';
      const canvasData = <String, dynamic>{
        'blockHeight': 240.0,
        'designWidth': 800.0,
        'elements': [
          {
            'id': 'button-1',
            'type': 'button',
            'label': hiddenLabel,
            'link': '/productos/categoria/pinones',
            'x': 20.0,
            'y': 20.0,
            'w': 220.0,
            'h': 56.0,
          },
        ],
      };

      await tester.pumpWidget(
        _rendererHost(
          blockType: 'canvas',
          data: canvasData,
          isNavigationEligible: (_) => false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(hiddenLabel), findsNothing);

      await tester.pumpWidget(
        _rendererHost(
          blockType: 'canvas',
          data: canvasData,
          isNavigationEligible: (_) => true,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(hiddenLabel), findsOneWidget);
    });

    testWidgets('composed carousel Canvas cannot restore a hidden CTA',
        (tester) async {
      await tester.pumpWidget(
        _rendererHost(
          blockType: 'carousel',
          data: const <String, dynamic>{
            'autoPlay': false,
            'slides': [
              {
                'title': 'Slide compuesto',
                'useComposition': true,
                'elements': [
                  {
                    'id': 'button-1',
                    'type': 'button',
                    'label': 'CTA COMPUESTO OCULTO',
                    'link': '/productos/categoria/pinones',
                    'x': 20.0,
                    'y': 20.0,
                    'w': 260.0,
                    'h': 56.0,
                  },
                ],
              },
            ],
          },
          isNavigationEligible: (_) => false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('CTA COMPUESTO OCULTO'), findsNothing);
    });

    testWidgets('brand artwork stays visible without a dead category link',
        (tester) async {
      var navigations = 0;
      const brandData = <String, dynamic>{
        'title': 'Marcas',
        'brands': [
          {
            'name': 'Marca enlazada',
            'imageUrl': '',
            'link': '/productos/categoria/pinones',
          },
        ],
      };

      await tester.pumpWidget(
        _rendererHost(
          blockType: 'brandLogos',
          data: brandData,
          isNavigationEligible: (_) => false,
          onNavigate: (_) => navigations += 1,
        ),
      );
      await tester.pump();
      expect(find.text('Marca enlazada'), findsOneWidget);
      await tester.tap(find.text('Marca enlazada'));
      expect(navigations, 0);

      await tester.pumpWidget(
        _rendererHost(
          blockType: 'brandLogos',
          data: brandData,
          isNavigationEligible: (_) => true,
          onNavigate: (_) => navigations += 1,
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Marca enlazada'));
      expect(navigations, 1);
    });

    testWidgets('contact and team omit ineligible secondary links',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        _rendererHost(
          blockType: 'contact',
          data: const <String, dynamic>{
            'showMap': true,
            'mapUrl': '/productos/categoria/pinones',
          },
          isNavigationEligible: (_) => false,
        ),
      );
      await tester.pump();
      expect(find.text('Abrir mapa'), findsNothing);

      await tester.pumpWidget(
        _rendererHost(
          blockType: 'team',
          data: const <String, dynamic>{
            'members': [
              {
                'name': 'Persona',
                'instagram': '/productos/categoria/pinones',
                'linkedin': '/productos/categoria/pinones',
              },
            ],
          },
          isNavigationEligible: (_) => false,
        ),
      );
      await tester.pump();
      expect(find.byTooltip('Instagram'), findsNothing);
      expect(find.byTooltip('LinkedIn'), findsNothing);
    });
  });

  group('visitor interaction boundary parity', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues(const {});
      WebsiteService.setSharedPreferences(
        await SharedPreferences.getInstance(),
      );
      await Supabase.initialize(
        url: 'http://127.0.0.1:54321',
        anonKey: 'test-anon-key',
      );
    });

    setUp(() => WidgetController.hitTestWarningShouldBeFatal = true);
    tearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);

    Widget parityHost({
      required String blockType,
      required Map<String, dynamic> data,
      bool previewMode = false,
      bool edit = false,
      List<Product>? featuredProducts,
      void Function(String route)? onNavigate,
      Size size = const Size(1280, 900),
    }) {
      final tenant = PublicStoreTenantProvider(TenantDetectionService())
        ..setTenant(
          Tenant(
            id: 'tenant-parity',
            shopName: 'Tienda',
            subdomain: 'tienda',
            createdAt: DateTime.utc(2026, 8, 1),
            updatedAt: DateTime.utc(2026, 8, 1),
          ),
        );
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<PublicStoreTenantProvider>.value(
            value: tenant,
          ),
          ChangeNotifierProvider<PublicInventoryService>(
            create: (_) => _StubInventoryService(),
          ),
          ChangeNotifierProvider<WebsiteService>(
            create: (_) => WebsiteService(),
          ),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: size, disableAnimations: true),
            child: Scaffold(
              body: SingleChildScrollView(
                child: Builder(
                  builder: (context) => WebsiteBlockRenderer.build(
                    context: context,
                    blockType: blockType,
                    data: data,
                    primaryColor: Colors.blue,
                    accentColor: Colors.green,
                    previewMode: previewMode,
                    featuredProducts: featuredProducts,
                    onNavigate: onNavigate ?? (_) {},
                    isNavigationEligible: (_) => true,
                    tenantId: 'tenant-parity',
                    // Edit is identified by injected presenters — the ONE
                    // visitor-interaction boundary.
                    contentPresenters:
                        edit ? const WebsiteBlockContentPresenters() : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    Future<void> settleWithNetworkImages(WidgetTester tester) async {
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        tester.takeException();
      }
    }

    testWidgets('brand logo links navigate in Preview and Public; Edit inert',
        (tester) async {
      final routes = <String>[];
      const data = <String, dynamic>{
        'brands': <Map<String, dynamic>>[
          <String, dynamic>{
            'name': 'MAXXIS',
            'imageUrl': '',
            'link': '/productos/categoria/camaras',
          },
        ],
      };

      await tester.pumpWidget(
        parityHost(blockType: 'brandLogos', data: data, onNavigate: routes.add),
      );
      await tester.tap(find.text('MAXXIS'));
      expect(routes, ['/productos/categoria/camaras']);

      await tester.pumpWidget(
        parityHost(
          blockType: 'brandLogos',
          data: data,
          previewMode: true,
          onNavigate: routes.add,
        ),
      );
      await tester.tap(find.text('MAXXIS'));
      expect(
        routes,
        ['/productos/categoria/camaras', '/productos/categoria/camaras'],
        reason: 'Preview navigates exactly like Public',
      );

      await tester.pumpWidget(
        parityHost(
          blockType: 'brandLogos',
          data: data,
          edit: true,
          onNavigate: routes.add,
        ),
      );
      await tester.tap(find.text('MAXXIS'));
      expect(routes.length, 2, reason: 'Edit (presenters) never navigates');
    });

    testWidgets(
        'manual category cards navigate in Preview and Public; Edit inert',
        (tester) async {
      final routes = <String>[];
      const data = <String, dynamic>{
        'categories': <Map<String, dynamic>>[
          <String, dynamic>{
            'title': 'Cámaras',
            'imageUrl': 'https://invalid.local/c.png',
            'ctaText': 'Ver',
            'ctaLink': '/productos',
          },
        ],
      };

      Future<void> pumpGrid(
          {bool previewMode = false, bool edit = false}) async {
        await tester.pumpWidget(
          parityHost(
            blockType: 'categoryGrid',
            data: data,
            previewMode: previewMode,
            edit: edit,
            onNavigate: routes.add,
          ),
        );
        await settleWithNetworkImages(tester);
      }

      await pumpGrid();
      expect(find.byType(InkWell), findsOneWidget);
      await tester.tap(find.byType(InkWell));
      expect(routes, ['/productos']);

      await pumpGrid(previewMode: true);
      await tester.tap(find.byType(InkWell));
      expect(routes, ['/productos', '/productos'],
          reason: 'Preview navigates exactly like Public');

      await pumpGrid(edit: true);
      await tester.tap(find.byType(InkWell));
      expect(routes.length, 2, reason: 'Edit (presenters) never navigates');
    });

    testWidgets(
        'product cards and view-all navigate in Preview and Public; Edit '
        'inert', (tester) async {
      final routes = <String>[];
      final product = Product(
        id: 'prod-parity-1',
        name: 'Cámara 26',
        sku: 'CAM26',
        price: 9990,
        cost: 0,
        stockQuantity: 3,
        category: ProductCategory.other,
        createdAt: DateTime.utc(2026, 8, 1),
        updatedAt: DateTime.utc(2026, 8, 1),
      );
      const data = <String, dynamic>{
        'title': 'Destacados',
        'productSource': 'featured',
        'itemsPerRow': 2,
        'showViewAll': true,
        'viewAllText': 'Ver todos',
        'viewAllLink': '/productos',
      };

      await tester.pumpWidget(
        parityHost(
          blockType: 'products',
          data: data,
          featuredProducts: [product],
          onNavigate: routes.add,
        ),
      );
      await settleWithNetworkImages(tester);
      expect(find.byType(PremiumProductCard), findsWidgets);
      await tester.tap(find.byType(PremiumProductCard).first);
      expect(routes, [publicProductPath(product)],
          reason: 'the public product card navigates to its canonical URL');
      await tester.ensureVisible(find.text('VER TODOS'));
      await tester.tap(find.text('VER TODOS'));
      expect(routes, [publicProductPath(product), '/productos']);

      // Preview: visitor interactions stay enabled on the REAL card widget
      // (preview shows sample data, which is preview-data semantics), and
      // the configured view-all navigates exactly like Public.
      await tester.pumpWidget(
        parityHost(
          blockType: 'products',
          data: data,
          previewMode: true,
          featuredProducts: [product],
          onNavigate: routes.add,
        ),
      );
      await settleWithNetworkImages(tester);
      final previewCard = tester.widget<PremiumProductCard>(
        find.byType(PremiumProductCard).first,
      );
      expect(previewCard.interactionsEnabled, isTrue,
          reason: 'Preview keeps visitor interactions on product cards');
      await tester.ensureVisible(find.text('VER TODOS'));
      await tester.tap(find.text('VER TODOS'));
      expect(routes.last, '/productos',
          reason: 'Preview view-all navigates exactly like Public');
      final routesAfterPreview = routes.length;

      await tester.pumpWidget(
        parityHost(
          blockType: 'products',
          data: data,
          edit: true,
          featuredProducts: [product],
          onNavigate: routes.add,
        ),
      );
      await settleWithNetworkImages(tester);
      final editCard = tester.widget<PremiumProductCard>(
        find.byType(PremiumProductCard).first,
      );
      expect(editCard.interactionsEnabled, isFalse,
          reason: 'Edit (presenters) disables card interactions');
      await tester.ensureVisible(find.text('VER TODOS'));
      await tester.tap(find.text('VER TODOS'));
      expect(routes.length, routesAfterPreview,
          reason: 'Edit view-all keeps its inert affordance');
    });

    testWidgets('the mobile product carousel card follows the same boundary',
        (tester) async {
      final routes = <String>[];
      final product = Product(
        id: 'prod-parity-2',
        name: 'Cadena 11v',
        sku: 'CAD11',
        price: 19990,
        cost: 0,
        stockQuantity: 2,
        category: ProductCategory.other,
        createdAt: DateTime.utc(2026, 8, 1),
        updatedAt: DateTime.utc(2026, 8, 1),
      );
      const data = <String, dynamic>{
        'title': 'Destacados',
        'productSource': 'featured',
        'showViewAll': false,
      };

      await tester.pumpWidget(
        parityHost(
          blockType: 'products',
          data: data,
          featuredProducts: [product],
          onNavigate: routes.add,
          size: const Size(600, 900),
        ),
      );
      await settleWithNetworkImages(tester);
      expect(find.byType(PremiumProductCard), findsOneWidget);
      await tester.tap(find.byType(PremiumProductCard));
      expect(routes, [publicProductPath(product)],
          reason: 'the mobile card navigates publicly');

      await tester.pumpWidget(
        parityHost(
          blockType: 'products',
          data: data,
          previewMode: true,
          featuredProducts: [product],
          onNavigate: routes.add,
          size: const Size(600, 900),
        ),
      );
      await settleWithNetworkImages(tester);
      final previewCard = tester.widget<PremiumProductCard>(
        find.byType(PremiumProductCard).first,
      );
      expect(previewCard.interactionsEnabled, isTrue,
          reason: 'Preview keeps visitor interactions on the mobile card');

      await tester.pumpWidget(
        parityHost(
          blockType: 'products',
          data: data,
          edit: true,
          featuredProducts: [product],
          onNavigate: routes.add,
          size: const Size(600, 900),
        ),
      );
      await settleWithNetworkImages(tester);
      final editCard = tester.widget<PremiumProductCard>(
        find.byType(PremiumProductCard).first,
      );
      expect(editCard.interactionsEnabled, isFalse,
          reason: 'Edit (presenters) disables the mobile card');
    });

    testWidgets(
        'the Video Banner CTA navigates in Preview and Public; Edit inert',
        (tester) async {
      final routes = <String>[];
      const data = <String, dynamic>{
        'title': 'Video',
        'ctaText': 'Ver más',
        'ctaLink': '/servicios',
      };

      await tester.pumpWidget(
        parityHost(
            blockType: 'videoBanner', data: data, onNavigate: routes.add),
      );
      await tester.tap(find.byType(WebsiteActionButton));
      expect(routes, ['/servicios']);

      await tester.pumpWidget(
        parityHost(
          blockType: 'videoBanner',
          data: data,
          previewMode: true,
          onNavigate: routes.add,
        ),
      );
      await tester.tap(find.byType(WebsiteActionButton));
      expect(routes, ['/servicios', '/servicios'],
          reason: 'Preview navigates exactly like Public');

      await tester.pumpWidget(
        parityHost(
          blockType: 'videoBanner',
          data: data,
          edit: true,
          onNavigate: routes.add,
        ),
      );
      final editButton = tester.widget<WebsiteActionButton>(
        find.byType(WebsiteActionButton),
      );
      expect(editButton.onPressed, isNull,
          reason: 'Edit (presenters) keeps the CTA inert');
      expect(routes.length, 2);
    });
  });
}
