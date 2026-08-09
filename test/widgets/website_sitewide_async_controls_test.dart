import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/modules/website/widgets/website_color_picker.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_panel.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

class _SitewideWebsiteService extends WebsiteService {
  _SitewideWebsiteService({
    List<WebsiteNavigation> footerNavigation = const <WebsiteNavigation>[],
  })  : footerItems = footerNavigation,
        super(
          supabase: SupabaseClient(
            'http://localhost:54321',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
          tenantService: TenantService.testing(
            currentUserId: () => null,
            profileLookup: (_) async => const <Map<String, dynamic>>[],
          ),
        );

  List<WebsiteNavigation> footerItems;

  @override
  List<WebsiteNavigation> get footerNavigation => footerItems;

  @override
  Future<void> loadSettings() async {}
}

WebsiteEditModeProvider _provider({
  Map<String, String> header = const <String, String>{},
  Map<String, String> footer = const <String, String>{},
  Map<String, String> theme = const <String, String>{},
  String? selection,
}) {
  final provider = WebsiteEditModeProvider()
    ..enterEditMode(
      const <Map<String, dynamic>>[],
      const <String, dynamic>{},
    );
  if (header.isNotEmpty) provider.updateHeaderSettings(header);
  if (footer.isNotEmpty) provider.updateFooterSettings(footer);
  if (theme.isNotEmpty) provider.updateThemeSettings(theme);
  if (selection != null) provider.selectBlock(selection);
  return provider;
}

Widget _host({
  required ValueNotifier<WebsiteEditModeProvider> activeProvider,
  required WebsiteService websiteService,
}) {
  return MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 430,
          height: 850,
          child: ValueListenableBuilder<WebsiteEditModeProvider>(
            valueListenable: activeProvider,
            builder: (context, provider, _) => MultiProvider(
              providers: [
                ChangeNotifierProvider<WebsiteEditModeProvider>.value(
                  value: provider,
                ),
                ChangeNotifierProvider<WebsiteService>.value(
                  value: websiteService,
                ),
              ],
              child: const WebsiteEditorPanel(),
            ),
          ),
        ),
      ),
    ),
  );
}

bool _hasControllerText(WidgetTester tester, String value) {
  return tester
      .widgetList<TextFormField>(find.byType(TextFormField))
      .any((field) => field.controller?.text == value);
}

WebsiteColorPickerField _colorField(WidgetTester tester, String label) {
  return tester
      .widgetList<WebsiteColorPickerField>(
        find.byType(WebsiteColorPickerField),
      )
      .singleWhere((field) => field.label == label);
}

Future<void> _openThemeColors(WidgetTester tester) async {
  await tester.tap(find.text('Tema'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Colores'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('header controllers rebaseline without staging provider A into B',
      (tester) async {
    final providerA = _provider(
      header: const <String, String>{'store_name': 'Tienda A'},
      selection: 'header',
    );
    final providerB = _provider(
      header: const <String, String>{'store_name': 'Tienda B'},
      selection: 'header',
    );
    final activeProvider = ValueNotifier<WebsiteEditModeProvider>(providerA);
    final websiteService = _SitewideWebsiteService();
    addTearDown(providerA.dispose);
    addTearDown(providerB.dispose);
    addTearDown(activeProvider.dispose);
    addTearDown(websiteService.dispose);

    await tester.pumpWidget(
      _host(
        activeProvider: activeProvider,
        websiteService: websiteService,
      ),
    );
    await tester.pumpAndSettle();
    expect(_hasControllerText(tester, 'Tienda A'), isTrue);

    activeProvider.value = providerB;
    await tester.pumpAndSettle();

    expect(_hasControllerText(tester, 'Tienda B'), isTrue);
    expect(_hasControllerText(tester, 'Tienda A'), isFalse);
    expect(
      providerB.pendingHeaderSettings,
      const <String, String>{'store_name': 'Tienda B'},
      reason: 'rebaseline must not fire A controllers into provider B',
    );
  });

  testWidgets('footer controllers rebaseline without staging provider A into B',
      (tester) async {
    final providerA = _provider(
      footer: const <String, String>{'store_tagline': 'Footer A'},
      selection: 'footer',
    );
    final providerB = _provider(
      footer: const <String, String>{'store_tagline': 'Footer B'},
      selection: 'footer',
    );
    final activeProvider = ValueNotifier<WebsiteEditModeProvider>(providerA);
    final websiteService = _SitewideWebsiteService();
    addTearDown(providerA.dispose);
    addTearDown(providerB.dispose);
    addTearDown(activeProvider.dispose);
    addTearDown(websiteService.dispose);

    await tester.pumpWidget(
      _host(
        activeProvider: activeProvider,
        websiteService: websiteService,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marca'));
    await tester.pumpAndSettle();
    expect(_hasControllerText(tester, 'Footer A'), isTrue);

    activeProvider.value = providerB;
    await tester.pumpAndSettle();

    expect(_hasControllerText(tester, 'Footer B'), isTrue);
    expect(_hasControllerText(tester, 'Footer A'), isFalse);
    expect(
      providerB.pendingFooterSettings,
      const <String, String>{'store_tagline': 'Footer B'},
    );
  });

  testWidgets('theme controllers rebaseline on the explicit provider swap',
      (tester) async {
    final providerA = _provider(
      theme: const <String, String>{'theme_primary_color': '#112233'},
    );
    final providerB = _provider(
      theme: const <String, String>{'theme_primary_color': '#445566'},
    );
    final activeProvider = ValueNotifier<WebsiteEditModeProvider>(providerA);
    final websiteService = _SitewideWebsiteService();
    addTearDown(providerA.dispose);
    addTearDown(providerB.dispose);
    addTearDown(activeProvider.dispose);
    addTearDown(websiteService.dispose);

    await tester.pumpWidget(
      _host(
        activeProvider: activeProvider,
        websiteService: websiteService,
      ),
    );
    await tester.pumpAndSettle();
    await _openThemeColors(tester);
    expect(_colorField(tester, 'Color principal').value, '#112233');

    activeProvider.value = providerB;
    await tester.pumpAndSettle();

    expect(_colorField(tester, 'Color principal').value, '#445566');
    expect(
      providerB.pendingThemeSettings,
      const <String, String>{'theme_primary_color': '#445566'},
    );
  });

  testWidgets('valid theme color Apply is exactly one provider state write',
      (tester) async {
    final provider = _provider(
      theme: const <String, String>{'theme_primary_color': '#112233'},
    );
    final activeProvider = ValueNotifier<WebsiteEditModeProvider>(provider);
    final websiteService = _SitewideWebsiteService();
    addTearDown(provider.dispose);
    addTearDown(activeProvider.dispose);
    addTearDown(websiteService.dispose);

    await tester.pumpWidget(
      _host(
        activeProvider: activeProvider,
        websiteService: websiteService,
      ),
    );
    await tester.pumpAndSettle();
    await _openThemeColors(tester);

    var notifications = 0;
    provider.addListener(() => notifications++);
    await tester.tap(
      find.byKey(const ValueKey('website_color_picker_Color principal')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('website_color_swatch_#F0642F')).first,
    );
    await tester.tap(
      find.byKey(const ValueKey('website_color_picker_apply')),
    );
    await tester.pumpAndSettle();

    expect(provider.pendingThemeSettings['theme_primary_color'], '#F0642F');
    expect(notifications, 1);
  });

  testWidgets(
      'color arm from provider A cannot update A or same-key provider B',
      (tester) async {
    final providerA = _provider(
      theme: const <String, String>{'theme_primary_color': '#112233'},
    );
    final providerB = _provider(
      theme: const <String, String>{'theme_primary_color': '#112233'},
    );
    final activeProvider = ValueNotifier<WebsiteEditModeProvider>(providerA);
    final websiteService = _SitewideWebsiteService();
    addTearDown(providerA.dispose);
    addTearDown(providerB.dispose);
    addTearDown(activeProvider.dispose);
    addTearDown(websiteService.dispose);

    await tester.pumpWidget(
      _host(
        activeProvider: activeProvider,
        websiteService: websiteService,
      ),
    );
    await tester.pumpAndSettle();
    await _openThemeColors(tester);
    await tester.tap(
      find.byKey(const ValueKey('website_color_picker_Color principal')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('website_color_swatch_#F0642F')).first,
    );

    activeProvider.value = providerB;
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('website_color_picker_apply')),
    );
    await tester.pumpAndSettle();

    expect(providerA.pendingThemeSettings['theme_primary_color'], '#112233');
    expect(providerB.pendingThemeSettings['theme_primary_color'], '#112233');
    expect(_colorField(tester, 'Color principal').value, '#112233');
  });

  testWidgets('footer delete rejects a base navigation A to B refresh',
      (tester) async {
    WebsiteNavigation section(String childLabel) => WebsiteNavigation(
          id: 'section-1',
          tenantId: 'tenant-a',
          menuLocation: MenuLocation.footer,
          label: 'Ayuda',
          linkType: NavLinkType.action,
          orderIndex: 0,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          children: <WebsiteNavigation>[
            WebsiteNavigation(
              id: 'child-1',
              tenantId: 'tenant-a',
              menuLocation: MenuLocation.footer,
              label: childLabel,
              linkType: NavLinkType.page,
              linkValue: '/ayuda',
              parentId: 'section-1',
              orderIndex: 0,
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          ],
        );

    final provider = _provider(selection: 'footer');
    final activeProvider = ValueNotifier<WebsiteEditModeProvider>(provider);
    final websiteService = _SitewideWebsiteService(
      footerNavigation: <WebsiteNavigation>[section('Preguntas A')],
    );
    addTearDown(provider.dispose);
    addTearDown(activeProvider.dispose);
    addTearDown(websiteService.dispose);

    await tester.pumpWidget(
      _host(
        activeProvider: activeProvider,
        websiteService: websiteService,
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Enlaces del footer'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Opciones').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Eliminar').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('¿Eliminar "Ayuda"?'), findsOneWidget);

    // Same provider and no pending footer mutation: only the authoritative
    // WebsiteService base tree changes while the confirmation awaits.
    websiteService.footerItems = <WebsiteNavigation>[section('Preguntas B')];
    await tester.tap(find.text('Eliminar').last);
    await tester.pumpAndSettle();

    expect(provider.pendingFooterNavDeletes, isEmpty);
    expect(provider.hasFooterChanges, isFalse);
  });

  testWidgets('footer drag rejects a refreshed base tree before drop',
      (tester) async {
    WebsiteNavigation section(String secondLabel) => WebsiteNavigation(
          id: 'section-1',
          tenantId: 'tenant-a',
          menuLocation: MenuLocation.footer,
          label: 'Ayuda',
          linkType: NavLinkType.action,
          orderIndex: 0,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          children: <WebsiteNavigation>[
            WebsiteNavigation(
              id: 'child-1',
              tenantId: 'tenant-a',
              menuLocation: MenuLocation.footer,
              label: 'Primero',
              linkType: NavLinkType.page,
              linkValue: '/primero',
              parentId: 'section-1',
              orderIndex: 0,
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
            WebsiteNavigation(
              id: 'child-2',
              tenantId: 'tenant-a',
              menuLocation: MenuLocation.footer,
              label: secondLabel,
              linkType: NavLinkType.page,
              linkValue: '/segundo',
              parentId: 'section-1',
              orderIndex: 1,
              createdAt: DateTime(2026),
              updatedAt: DateTime(2026),
            ),
          ],
        );

    final provider = _provider(selection: 'footer');
    final activeProvider = ValueNotifier<WebsiteEditModeProvider>(provider);
    final websiteService = _SitewideWebsiteService(
      footerNavigation: <WebsiteNavigation>[section('Segundo A')],
    );
    addTearDown(provider.dispose);
    addTearDown(activeProvider.dispose);
    addTearDown(websiteService.dispose);

    await tester.pumpWidget(
      _host(
        activeProvider: activeProvider,
        websiteService: websiteService,
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Enlaces del footer'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    Draggable<String> dragged() => tester
        .widgetList<Draggable<String>>(
          find.byWidgetPredicate((widget) => widget is Draggable<String>),
        )
        .singleWhere((widget) => widget.data == 'child-1');
    DragTarget<String> target() => tester.widget<DragTarget<String>>(
          find.byKey(const ValueKey('footer_link_target_1')),
        );
    final details = DragTargetDetails<String>(
      data: 'child-1',
      offset: Offset.zero,
    );

    dragged().onDragStarted!();
    target().onMove!(details);
    websiteService.footerItems = <WebsiteNavigation>[section('Segundo B')];
    target().onAcceptWithDetails!(details);
    await tester.pump();
    expect(provider.pendingFooterLinkOrder, isEmpty);

    dragged().onDragStarted!();
    target().onMove!(details);
    target().onAcceptWithDetails!(details);
    await tester.pump();
    expect(
      provider.pendingFooterLinkOrder['section-1'],
      const <String>['child-2', 'child-1'],
    );
  });
}
