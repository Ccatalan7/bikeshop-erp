import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/inventory/models/category_models.dart';
import 'package:vinabike_erp/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/modules/website/models/website_page_composition.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/modules/website/widgets/deferred_editable_block_renderer.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_renderer.dart';
import 'package:vinabike_erp/public_store/models/public_checkout_capabilities.dart';
import 'package:vinabike_erp/public_store/providers/cart_provider.dart';
import 'package:vinabike_erp/public_store/providers/public_store_tenant_provider.dart';
import 'package:vinabike_erp/public_store/services/public_category_publication.dart';
import 'package:vinabike_erp/public_store/services/customer_account_service.dart';
import 'package:vinabike_erp/public_store/services/public_inventory_service.dart';
import 'package:vinabike_erp/public_store/services/public_store_scroll_state.dart';
import 'package:vinabike_erp/public_store/widgets/page_composition.dart';
import 'package:vinabike_erp/public_store/widgets/public_store_layout.dart';
import 'package:vinabike_erp/shared/models/tenant.dart';
import 'package:vinabike_erp/shared/services/tenant_detection_service.dart';

const _tenantId = '5443b130-cc28-45af-a420-cd500b288890';
const _accessoriesId = '164e46a9-3bfc-47d9-85ff-e911d96adacd';
const _componentsId = '5b73715d-cbf1-4c23-9bd6-8eb903028b84';
const _drivetrainId = 'd5d3b289-5c93-4871-a260-df6b572444ed';

const _transparentPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    'YAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

late HttpServer _origin;
late StreamSubscription<HttpRequest> _originRequests;
late String _imageUrl;
HttpOverrides? _previousHttpOverrides;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    _previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = _LoopbackHttpOverrides();
    _origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _imageUrl = 'http://${_origin.address.address}:${_origin.port}/card.png';
    _originRequests = _origin.listen((request) async {
      await request.drain<void>();
      final bytes = base64Decode(_transparentPng);
      request.response.headers.contentType = ContentType('image', 'png');
      request.response.contentLength = bytes.length;
      request.response.add(bytes);
      await request.response.close();
    });
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(
        detectSessionInUri: false,
      ),
    );
  });

  tearDownAll(() async {
    await _originRequests.cancel();
    await _origin.close(force: true);
    HttpOverrides.global = _previousHttpOverrides;
  });

  testWidgets(
    'category grid retains authored generic-search cards when one category is public',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final website = _ProjectionWebsiteService(
        authoritativeTenantId: _tenantId,
      );
      final inventory = _ProjectionInventoryService({
        _tenantId: [
          _category(
            id: _drivetrainId,
            name: 'Transmisión',
            fullPath: 'Componentes / Transmisión',
          ),
        ],
      });
      final tenant = PublicStoreTenantProvider(TenantDetectionService())
        ..setTenant(_tenant());
      addTearDown(website.dispose);
      addTearDown(inventory.dispose);
      addTearDown(tenant.dispose);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<WebsiteService>.value(value: website),
            ChangeNotifierProvider<PublicInventoryService>.value(
              value: inventory,
            ),
            ChangeNotifierProvider<PublicStoreTenantProvider>.value(
              value: tenant,
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => SingleChildScrollView(
                  child: WebsiteBlockRenderer.build(
                    context: context,
                    blockType: 'categoryGrid',
                    effectiveViewport: WebsiteViewport.desktop,
                    data: {
                      'title': 'Explora',
                      'categories': [
                        {
                          'title': 'Busca cadenas',
                          'imageUrl': _imageUrl,
                          'ctaText': 'Buscar',
                          'ctaLink': '/productos?search=cadenas',
                          'size': 'large',
                        },
                        {
                          'title': 'Busca neumáticos',
                          'imageUrl': _imageUrl,
                          'ctaText': 'Buscar',
                          'ctaLink': '/productos?search=neumaticos',
                          'size': 'large',
                        },
                        {
                          'title': 'Transmisión',
                          'imageUrl': _imageUrl,
                          'ctaText': 'Ver categoría',
                          'ctaLink': '/productos?category=$_drivetrainId',
                          'size': 'medium',
                        },
                      ],
                    },
                    primaryColor: Colors.blue,
                    accentColor: Colors.green,
                    previewMode: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await _pumpUntilFound(tester, find.text('TRANSMISIÓN'));

      expect(find.text('BUSCA CADENAS'), findsOneWidget);
      expect(find.text('BUSCA NEUMÁTICOS'), findsOneWidget);
      expect(find.text('TRANSMISIÓN'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'category grid title formatting survives Edit save-reload Preview and Public',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final website = _ProjectionWebsiteService(
        authoritativeTenantId: _tenantId,
      );
      final inventory = _ProjectionInventoryService({
        _tenantId: [
          _category(
            id: _drivetrainId,
            name: 'Transmisión',
            fullPath: 'Componentes / Transmisión',
          ),
        ],
      });
      final tenant = PublicStoreTenantProvider(TenantDetectionService())
        ..setTenant(_tenant());
      final editProvider = WebsiteEditModeProvider()
        ..enterEditMode(
          <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'category-grid-formatting',
              'block_type': 'categoryGrid',
              'block_data': <String, dynamic>{
                'title': 'Explora con estilo',
                'categories': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'title': 'Busca cadenas',
                    'imageUrl': _imageUrl,
                    'ctaText': 'Buscar',
                    'ctaLink': '/productos?search=cadenas',
                    'size': 'large',
                  },
                ],
              },
              'is_visible': true,
              'sort_order': 0,
            },
          ],
          const <String, dynamic>{},
          pageId: 'category-grid-page',
          pageSlug: 'category-grid',
        );
      addTearDown(website.dispose);
      addTearDown(inventory.dispose);
      addTearDown(tenant.dispose);
      addTearDown(editProvider.dispose);

      const authoredColor = Color(0xFF4A237A);
      final authoredFormatting = <String, dynamic>{
        'italic': true,
        'underline': true,
        'fontSize': 31.0,
        'textAlign': 'right',
        'textColor': authoredColor.toARGB32(),
      };
      editProvider.updateBlockData(
        'category-grid-formatting',
        'titleFormatting',
        authoredFormatting,
      );

      await _pumpCategoryGridComposition(
        tester,
        rows: editProvider.blocks,
        mode: WebsitePageCompositionMode.edit,
        website: website,
        inventory: inventory,
        tenant: tenant,
        editProvider: editProvider,
        originKey: 'edit-draft',
      );
      _expectCategoryGridTitlePresentation(
        tester,
        color: authoredColor,
      );

      // Simulated persistence boundary: JSON destroys every list/map identity,
      // matching a save plus fresh origin read without performing any write.
      final persistedRows =
          (jsonDecode(jsonEncode(editProvider.blocks)) as List)
              .map((row) => Map<String, dynamic>.from(row as Map))
              .toList(growable: false);
      expect(identical(persistedRows, editProvider.blocks), isFalse);
      expect(
        identical(
          persistedRows.single['block_data'],
          editProvider.blocks.single['block_data'],
        ),
        isFalse,
      );

      final reloadedProvider = WebsiteEditModeProvider()
        ..enterEditMode(
          persistedRows,
          const <String, dynamic>{},
          pageId: 'category-grid-page',
          pageSlug: 'category-grid',
        );
      addTearDown(reloadedProvider.dispose);
      final reloadedData = Map<String, dynamic>.from(
        reloadedProvider.blocks.single['block_data'] as Map,
      );
      expect(reloadedData['titleFormatting'], authoredFormatting);

      await _pumpCategoryGridComposition(
        tester,
        rows: reloadedProvider.blocks,
        mode: WebsitePageCompositionMode.preview,
        website: website,
        inventory: inventory,
        tenant: tenant,
        originKey: 'preview-reload',
      );
      _expectCategoryGridTitlePresentation(
        tester,
        color: authoredColor,
      );

      final publicRows = (jsonDecode(jsonEncode(persistedRows)) as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(growable: false);
      expect(
        identical(
          publicRows.single['block_data'],
          persistedRows.single['block_data'],
        ),
        isFalse,
        reason: 'Public must consume a fresh origin projection.',
      );
      await _pumpCategoryGridComposition(
        tester,
        rows: publicRows,
        mode: WebsitePageCompositionMode.public,
        website: website,
        inventory: inventory,
        tenant: tenant,
        originKey: 'public-origin',
      );
      _expectCategoryGridTitlePresentation(
        tester,
        color: authoredColor,
      );

      expect(tester.takeException(), isNull);
    },
  );

  test(
    'published category rows survive the header navigation projection',
    () {
      final navigation = [
        _navigation(
          id: 'header-accessories',
          location: MenuLocation.header,
          label: 'Accesorios',
          type: NavLinkType.category,
          value: '/productos?category=$_accessoriesId',
          order: 1,
        ),
        _navigation(
          id: 'header-components',
          location: MenuLocation.header,
          label: 'Componentes',
          type: NavLinkType.category,
          value: '/productos?category=$_componentsId',
          order: 2,
          cssClass: 'megamenu',
        ),
      ];
      final publication = PublicCategoryPublication.resolve(
        categories: const [
          PublicCategoryDescriptor(
            id: _accessoriesId,
            name: 'Accesorios',
            fullPath: 'Accesorios',
            showOnWebsite: true,
          ),
          PublicCategoryDescriptor(
            id: _componentsId,
            name: 'Componentes',
            fullPath: 'Componentes',
            showOnWebsite: true,
          ),
        ],
        navigation: navigation,
      );
      final projected = PublicCategoryNavigationProjection(publication)
          .forDesktop(navigation);

      expect(projected.map((item) => item.label), [
        'Accesorios',
        'Componentes',
      ]);
    },
  );

  test(
    'ERP tenant scope is explicit, idempotent, and overrides manual scope',
    () {
      final provider = PublicStoreTenantProvider(TenantDetectionService());
      var notifications = 0;
      provider.addListener(() => notifications++);

      expect(
        provider.projectAuthenticatedTenantForStorefront(_tenantId),
        isTrue,
      );
      expect(provider.tenantId, _tenantId);
      expect(provider.hasTenant, isFalse);
      expect(provider.hasTenantScope, isTrue);
      expect(provider.hasHydratedTenant, isFalse);
      expect(provider.currentTenant, isNull);
      expect(provider.isErpProjected, isTrue);
      expect(
        provider.scopeSource,
        PublicStoreTenantScopeSource.authenticatedErp,
      );
      expect(notifications, 1);

      expect(
        provider.projectAuthenticatedTenantForStorefront(_tenantId),
        isFalse,
      );
      expect(notifications, 1);

      final detected = _tenant(
        id: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
      );
      provider.setTenant(detected);
      notifications = 0;

      expect(
        provider.projectAuthenticatedTenantForStorefront(_tenantId),
        isTrue,
      );
      expect(provider.currentTenant, isNull);
      expect(provider.tenantId, _tenantId);
      expect(
        provider.scopeSource,
        PublicStoreTenantScopeSource.authenticatedErp,
      );
      expect(notifications, 1);

      provider.dispose();
    },
  );

  test(
    'authenticated ERP scope replaces URL detection and blocks late results',
    () async {
      final firstDetected = _tenant(
        id: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
      );
      final initialDetection = _ControlledTenantDetectionService()
        ..complete(firstDetected);
      final provider = PublicStoreTenantProvider(initialDetection);
      addTearDown(provider.dispose);

      await provider.detectTenant();
      expect(provider.tenantId, firstDetected.id);
      expect(provider.hasTenant, isTrue);
      expect(provider.hasTenantScope, isTrue);
      expect(provider.hasHydratedTenant, isTrue);
      expect(provider.scopeSource, PublicStoreTenantScopeSource.detected);

      expect(
        provider.projectAuthenticatedTenantForStorefront(_tenantId),
        isTrue,
      );
      expect(provider.tenantId, _tenantId);
      expect(provider.currentTenant, isNull);
      expect(provider.isErpProjected, isTrue);

      final lateDetection = _ControlledTenantDetectionService();
      final lateProvider = PublicStoreTenantProvider(lateDetection);
      addTearDown(lateProvider.dispose);
      final pendingDetection = lateProvider.detectTenant();
      expect(lateProvider.isLoading, isTrue);

      expect(
        lateProvider.projectAuthenticatedTenantForStorefront(_tenantId),
        isTrue,
      );
      lateDetection.complete(
        _tenant(id: 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
      );
      await pendingDetection;

      expect(lateProvider.tenantId, _tenantId);
      expect(lateProvider.currentTenant, isNull);
      expect(lateProvider.isLoading, isFalse);
      expect(
        lateProvider.scopeSource,
        PublicStoreTenantScopeSource.authenticatedErp,
      );
    },
  );

  testWidgets(
    'ERP storefront renders loaded header categories when URL tenant detection is empty',
    (tester) async {
      await _pumpErpStorefrontProjection(tester);

      expect(find.text('Accesorios'), findsOneWidget);
      expect(find.text('Componentes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'ERP storefront renders loaded published footer pages when URL tenant detection is empty',
    (tester) async {
      await _pumpErpStorefrontProjection(tester);

      expect(find.text('Envíos'), findsOneWidget);
      expect(find.text('Privacidad'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _pumpCategoryGridComposition(
  WidgetTester tester, {
  required List<Map<String, dynamic>> rows,
  required WebsitePageCompositionMode mode,
  required WebsiteService website,
  required PublicInventoryService inventory,
  required PublicStoreTenantProvider tenant,
  required String originKey,
  WebsiteEditModeProvider? editProvider,
}) async {
  if (mode == WebsitePageCompositionMode.edit) {
    await tester.runAsync(DeferredEditableBlockRenderer.preload);
  }

  Widget mountedStore = MultiProvider(
    providers: [
      ChangeNotifierProvider<WebsiteService>.value(value: website),
      ChangeNotifierProvider<PublicInventoryService>.value(value: inventory),
      ChangeNotifierProvider<PublicStoreTenantProvider>.value(value: tenant),
    ],
    child: SingleChildScrollView(
      child: KeyedSubtree(
        key: ValueKey<String>('category-grid-origin-$originKey'),
        child: PageComposition(
          composition: WebsitePageComposition.project(
            blocks: rows,
            mode: mode,
            breakpoint: 'desktop',
          ),
          primaryColor: Colors.blue,
          accentColor: Colors.green,
          textColor: Colors.black,
          containerPadding: 24,
          onNavigate: (_) {},
          isNavigationEligible: (_) => true,
        ),
      ),
    ),
  );
  if (editProvider != null) {
    mountedStore = ChangeNotifierProvider<WebsiteEditModeProvider>.value(
      value: editProvider,
      child: mountedStore,
    );
  }

  await tester.pumpWidget(
    MaterialApp(home: Scaffold(body: mountedStore)),
  );
  await _pumpUntilFound(
    tester,
    find.descendant(
      of: find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_AutoCategoryGrid',
      ),
      matching: find.text('Explora con estilo'),
    ),
  );
}

void _expectCategoryGridTitlePresentation(
  WidgetTester tester, {
  required Color color,
}) {
  final autoCategoryGrid = find.byWidgetPredicate(
    (widget) => widget.runtimeType.toString() == '_AutoCategoryGrid',
  );
  expect(autoCategoryGrid, findsOneWidget);

  final titleFinder = find.descendant(
    of: autoCategoryGrid,
    matching: find.text('Explora con estilo'),
  );
  expect(titleFinder, findsOneWidget);
  final title = tester.widget<Text>(titleFinder);
  expect(title.style?.fontSize, 31);
  expect(title.style?.fontStyle, FontStyle.italic);
  expect(title.style?.decoration, TextDecoration.underline);
  expect(title.style?.color, color);
  expect(title.textAlign, TextAlign.right);

  final paragraph = tester.renderObject<RenderParagraph>(titleFinder);
  expect(
    paragraph.textAlign,
    TextAlign.right,
    reason: 'The mounted consumer, not only the persisted map, must align it.',
  );
}

Future<void> _pumpErpStorefrontProjection(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1600, 1800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  final pages = [
    _page('envios', 'Información de Envíos'),
    _page('privacidad', 'Política de Privacidad'),
  ];
  final footerSection = _navigation(
    id: 'footer-information',
    location: MenuLocation.footer,
    label: 'Información',
    type: NavLinkType.action,
    order: 0,
    children: [
      _navigation(
        id: 'footer-shipping',
        location: MenuLocation.footer,
        label: 'Envíos',
        type: NavLinkType.page,
        value: pages[0].id,
        parentId: 'footer-information',
        linkedPage: pages[0],
      ),
      _navigation(
        id: 'footer-privacy',
        location: MenuLocation.footer,
        label: 'Privacidad',
        type: NavLinkType.page,
        value: pages[1].id,
        parentId: 'footer-information',
        linkedPage: pages[1],
        order: 1,
      ),
    ],
  );
  final header = [
    _navigation(
      id: 'header-accessories',
      location: MenuLocation.header,
      label: 'Accesorios',
      type: NavLinkType.category,
      value: '/productos?category=$_accessoriesId',
      order: 1,
    ),
    _navigation(
      id: 'header-components',
      location: MenuLocation.header,
      label: 'Componentes',
      type: NavLinkType.category,
      value: '/productos?category=$_componentsId',
      order: 2,
      cssClass: 'megamenu',
    ),
  ];
  final website = _ProjectionWebsiteService(
    authoritativeTenantId: _tenantId,
    pages: pages,
    headerNavigation: header,
    footerNavigation: [footerSection],
    settings: const {
      'site_published': 'true',
      'store_name': 'Tienda de prueba',
      'header_style': 'solid',
      'header_show_top_banner': 'false',
      'header_navigation_uppercase': 'false',
    },
  );
  final inventory = _ProjectionInventoryService({
    _tenantId: [
      _category(
        id: _accessoriesId,
        name: 'Accesorios',
        fullPath: 'Accesorios',
      ),
      _category(
        id: _componentsId,
        name: 'Componentes',
        fullPath: 'Componentes',
      ),
    ],
  });
  final tenant = PublicStoreTenantProvider(TenantDetectionService());
  expect(
    tenant.projectAuthenticatedTenantForStorefront(_tenantId),
    isTrue,
  );
  expect(
    tenant.projectAuthenticatedTenantForStorefront(_tenantId),
    isFalse,
  );
  final editMode = WebsiteEditModeProvider();
  final cart = CartProvider();
  final scrollState = PublicStoreScrollState();
  addTearDown(website.dispose);
  addTearDown(inventory.dispose);
  addTearDown(tenant.dispose);
  addTearDown(editMode.dispose);
  addTearDown(cart.dispose);

  PublicStoreRuntimeConfig.isErpMounted = true;
  addTearDown(() => PublicStoreRuntimeConfig.isErpMounted = false);

  late final GoRouter router;
  router = GoRouter(
    initialLocation: '/tienda',
    routes: [
      GoRoute(
        path: '/tienda',
        builder: (context, state) => MultiProvider(
          providers: [
            ChangeNotifierProvider<WebsiteService>.value(value: website),
            ChangeNotifierProvider<WebsiteEditModeProvider>.value(
              value: editMode,
            ),
            ChangeNotifierProvider<PublicStoreTenantProvider>.value(
              value: tenant,
            ),
            ChangeNotifierProvider<CartProvider>.value(value: cart),
            ChangeNotifierProvider<PublicInventoryService>.value(
              value: inventory,
            ),
            ChangeNotifierProvider<CustomerAccountService>(
              create: (_) => CustomerAccountService(),
            ),
            Provider<PublicStoreScrollState>.value(value: scrollState),
          ],
          child: PublicStoreLayout(
            showEditorButton: false,
            enablePageViewScrolling: true,
            routePath: '/tienda',
            checkoutCapabilityLoader: (_) async =>
                const PublicCheckoutCapabilities(methods: []),
            child: const SizedBox(
              height: 120,
              child: Center(child: Text('Contenido')),
            ),
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await _pumpUntilFound(tester, find.text('Contenido'));
  await tester.pump();
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 20,
}) async {
  for (var pump = 0; pump < maxPumps; pump++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 2)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  fail('Did not find the requested widget after $maxPumps pumps.');
}

Category _category({
  required String id,
  required String name,
  required String fullPath,
}) {
  return Category(
    id: id,
    tenantId: _tenantId,
    name: name,
    fullPath: fullPath,
    showOnWebsite: true,
  );
}

WebsitePage _page(String slug, String title) {
  final timestamp = DateTime.utc(2026, 7, 29);
  return WebsitePage(
    id: 'page-$slug',
    tenantId: _tenantId,
    slug: slug,
    title: title,
    isPublished: true,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

WebsiteNavigation _navigation({
  required String id,
  required MenuLocation location,
  required String label,
  required NavLinkType type,
  String? value,
  String? parentId,
  int order = 0,
  String? cssClass,
  List<WebsiteNavigation> children = const [],
  WebsitePage? linkedPage,
}) {
  final timestamp = DateTime.utc(2026, 7, 29);
  return WebsiteNavigation(
    id: id,
    tenantId: _tenantId,
    menuLocation: location,
    label: label,
    linkType: type,
    linkValue: value,
    parentId: parentId,
    orderIndex: order,
    cssClass: cssClass,
    createdAt: timestamp,
    updatedAt: timestamp,
    children: children,
    linkedPage: linkedPage,
  );
}

Tenant _tenant({String id = _tenantId}) {
  final timestamp = DateTime.utc(2026, 7, 29);
  return Tenant(
    id: id,
    shopName: 'Tienda de prueba',
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

class _ProjectionWebsiteService extends WebsiteService {
  _ProjectionWebsiteService({
    required this.authoritativeTenantId,
    this.pages = const [],
    this.headerNavigation = const [],
    this.footerNavigation = const [],
    Map<String, String> settings = const {},
  }) : _fixtureSettings = settings;

  final String authoritativeTenantId;

  @override
  final List<WebsitePage> pages;

  @override
  final List<WebsiteNavigation> headerNavigation;

  @override
  final List<WebsiteNavigation> footerNavigation;

  final Map<String, String> _fixtureSettings;

  @override
  List<WebsiteNavigation> get navigation => [
        ...headerNavigation,
        ...footerNavigation,
      ];

  @override
  bool hasAuthoritativePagePublicationForTenant(String tenantId) =>
      tenantId == authoritativeTenantId;

  @override
  String getSetting(String key, [String defaultValue = '']) =>
      _fixtureSettings[key] ?? defaultValue;

  @override
  WebsiteCatalogPresentationRegistry get catalogPresentationRegistry =>
      const WebsiteCatalogPresentationRegistry({});
}

class _ProjectionInventoryService extends PublicInventoryService {
  _ProjectionInventoryService(this.categoriesByTenant);

  final Map<String, List<Category>> categoriesByTenant;

  @override
  Future<List<Category>> getCategoriesForTenant({
    required String tenantId,
    bool forceRefresh = false,
  }) async =>
      List<Category>.unmodifiable(
        categoriesByTenant[tenantId] ?? const <Category>[],
      );

  @override
  PublicCategoryCacheSnapshot? cachedCategoriesForTenant({
    required String tenantId,
  }) {
    final categories = categoriesByTenant[tenantId];
    if (categories == null) return null;
    return PublicCategoryCacheSnapshot(
      categories: List<Category>.unmodifiable(categories),
      isFresh: true,
    );
  }
}

class _LoopbackHttpOverrides extends HttpOverrides {}

class _ControlledTenantDetectionService extends TenantDetectionService {
  final Completer<Tenant?> _result = Completer<Tenant?>();

  void complete(Tenant? tenant) {
    if (!_result.isCompleted) _result.complete(tenant);
  }

  @override
  Future<Tenant?> detectTenant() => _result.future;
}
