import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_erp/modules/website/models/website_catalog_query.dart';
import 'package:vinabike_erp/modules/website/models/website_destination.dart';
import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/public_store/theme/public_store_theme.dart';
import 'package:vinabike_erp/public_store/widgets/mega_menu.dart';

void main() {
  WebsiteNavigation navigation({
    required String id,
    required String label,
    String? linkValue,
    List<WebsiteNavigation> children = const [],
  }) {
    final now = DateTime(2026, 7, 22);
    return WebsiteNavigation(
      id: id,
      tenantId: 'tenant-1',
      label: label,
      linkType: NavLinkType.page,
      linkValue: linkValue ?? '/$id',
      createdAt: now,
      updatedAt: now,
      children: children,
    );
  }

  late WebsiteNavigation parent;
  late List<WebsiteNavigation> children;

  setUp(() {
    final chains = navigation(
      id: 'chains',
      label: 'Cadenas',
      linkValue: '/productos/categoria/cadenas',
    );
    final drivetrain = navigation(
      id: 'drivetrain',
      label: 'Transmisión',
      linkValue: '/productos/categoria/transmision',
      children: [chains],
    );
    parent = navigation(
      id: 'components',
      label: 'Componentes',
      linkValue: '/productos',
      children: [drivetrain],
    );
    children = parent.children;
    MegaMenuController.instance.closeMenu();
  });

  tearDown(() {
    MegaMenuController.instance.closeMenu();
  });

  Future<void> pumpMenu(
    WidgetTester tester, {
    required ValueChanged<String> onNavigate,
    Size surfaceSize = const Size(1200, 760),
    Map<String, MegaMenuBranchPresentation> branchPresentations =
        const <String, MegaMenuBranchPresentation>{},
  }) async {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const surface = Color(0xFFF7F5F1);
    const menuSurface = Color(0xFF000000);
    const menuRail = Color(0xFF64748B);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF235D3A),
            surface: surface,
          ),
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 24),
              child: MegaMenuButton(
                parent: parent,
                children: children,
                isEditMode: false,
                textColor: const Color(0xFF17231C),
                panelBackgroundColor: menuSurface,
                panelForegroundColor: Colors.white,
                panelRailBackgroundColor: menuRail,
                panelRailForegroundColor: Colors.white,
                branchPresentations: branchPresentations,
                onNavigate: (href, _) => onNavigate(href),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> revealBranch(
    WidgetTester tester, {
    String label = 'TRANSMISIÓN',
  }) async {
    final tab = find.widgetWithText(TextButton, label);
    expect(tab, findsOneWidget);
    tester.widget<TextButton>(tab).onHover?.call(true);
    await tester.pumpAndSettle();
  }

  testWidgets('desktop hover intent opens and dismisses the configured tree',
      (tester) async {
    final navigations = <String>[];
    await pumpMenu(tester, onNavigate: navigations.add);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    await mouse.moveTo(tester.getCenter(find.text('Componentes')));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('VER TODO'), findsOneWidget);
    expect(find.text('TRANSMISIÓN'), findsOneWidget);
    expect(find.text('Cadenas'), findsNothing);
    final panelFinder = find.byKey(const ValueKey<String>('mega-menu-panel'));
    expect(panelFinder, findsOneWidget);
    expect(
      tester.getSize(panelFinder).width,
      tester.getSize(find.byType(Scaffold)).width,
    );
    expect(
      tester.widget<Material>(panelFinder).color,
      const Color(0xFF000000),
    );
    final railFinder = find.byKey(const ValueKey<String>('mega-menu-rail'));
    expect(railFinder, findsOneWidget);
    expect(
      tester.widget<ColoredBox>(railFinder).color,
      const Color(0xFF64748B),
    );

    await mouse.moveTo(tester.getCenter(find.text('TRANSMISIÓN')));
    await tester.pumpAndSettle();
    expect(find.text('Cadenas'), findsOneWidget);

    final transmissionTab = find.widgetWithText(TextButton, 'TRANSMISIÓN');
    final transmissionTabRect = tester.getRect(transmissionTab);
    await mouse.moveTo(
      Offset(
        transmissionTabRect.center.dx,
        transmissionTabRect.bottom - 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cadenas'), findsOneWidget);

    await mouse.moveTo(
      tester.getCenter(
        find.byKey(
          const ValueKey<String>('mega-menu-branch-overview-drivetrain'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cadenas'), findsOneWidget);

    await mouse.moveTo(const Offset(1180, 740));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 340));

    expect(find.text('VER TODO'), findsNothing);
    expect(navigations, isEmpty);
  });

  testWidgets('active branch consumes media keyed by navigation id',
      (tester) async {
    const imageUrl = 'https://cdn.example.test/drivetrain-menu.webp';
    await pumpMenu(
      tester,
      onNavigate: (_) {},
      branchPresentations: const {
        'drivetrain': MegaMenuBranchPresentation(
          imageUrl: imageUrl,
          overlay: 0.64,
          overviewWidth: 330,
          contentAlignment: WebsiteMegaMenuContentAlignment.center,
        ),
        'chains': MegaMenuBranchPresentation(
          imageUrl: 'https://cdn.example.test/chains-card.webp',
          overlay: 0.58,
          cardOverlay: 0.30,
        ),
        // A category label is deliberately not a supported projection key.
        'Transmisión': MegaMenuBranchPresentation(
          imageUrl: 'https://cdn.example.test/wrong-owner.webp',
          overlay: 0.2,
        ),
      },
    );

    await tester.tap(find.text('Componentes'));
    await tester.pump();
    await revealBranch(tester);

    final imageFinder = find.byKey(
      const ValueKey<String>('mega-menu-branch-image-drivetrain'),
    );
    expect(imageFinder, findsOneWidget);
    final image = tester.widget<Image>(imageFinder);
    expect(image.image, isA<NetworkImage>());
    expect((image.image as NetworkImage).url, imageUrl);
    expect(
      tester.getSize(
        find.byKey(
          const ValueKey<String>('mega-menu-branch-overview-drivetrain'),
        ),
      ),
      const Size(330, 440),
    );
    final content = tester.widget<Column>(
      find.byKey(
        const ValueKey<String>('mega-menu-branch-content-drivetrain'),
      ),
    );
    expect(content.mainAxisAlignment, MainAxisAlignment.center);
    final cardImage = tester.widget<Image>(
      find.byKey(
        const ValueKey<String>('mega-menu-card-image-chains'),
      ),
    );
    expect(
      (cardImage.image as NetworkImage).url,
      'https://cdn.example.test/chains-card.webp',
    );
    final cardOverlay = tester.widget<ColoredBox>(
      find.byKey(
        const ValueKey<String>('mega-menu-card-overlay-chains'),
      ),
    );
    expect(cardOverlay.color.a, closeTo(0.30, 0.001));

    final gradientFinder = find.byKey(
      const ValueKey<String>('mega-menu-branch-gradient-drivetrain'),
    );
    expect(gradientFinder, findsOneWidget);
    final gradientDecoration =
        tester.widget<DecoratedBox>(gradientFinder).decoration as BoxDecoration;
    final gradient = gradientDecoration.gradient! as LinearGradient;
    expect(gradient.colors[0].a, closeTo(0.64, 0.001));
    expect(gradient.colors[1].a, closeTo(0.2176, 0.001));
    expect(gradient.colors[2].a, closeTo(0, 0.001));
  });

  testWidgets('visual cards cap their width and expose six options in two rows',
      (tester) async {
    final options = List<WebsiteNavigation>.generate(
      6,
      (index) => navigation(
        id: 'option-$index',
        label: 'Opción ${index + 1}',
      ),
    );
    final drivetrain = navigation(
      id: 'drivetrain',
      label: 'Transmisión',
      children: options,
    );
    parent = WebsiteNavigation(
      id: parent.id,
      tenantId: parent.tenantId,
      label: parent.label,
      linkValue: parent.linkValue,
      linkType: parent.linkType,
      createdAt: parent.createdAt,
      updatedAt: parent.updatedAt,
      children: [drivetrain],
    );
    children = parent.children;

    await pumpMenu(
      tester,
      onNavigate: (_) {},
      surfaceSize: const Size(1280, 760),
    );
    await tester.tap(find.text('Componentes'));
    await tester.pumpAndSettle();
    await revealBranch(tester);

    final cards = List<Finder>.generate(
      6,
      (index) => find.byKey(
        ValueKey<String>('mega-menu-card-option-$index'),
      ),
    );
    for (final card in cards) {
      expect(card, findsOneWidget);
      expect(tester.getSize(card).width, lessThanOrEqualTo(286));
      expect(tester.getSize(card).height, 184);
    }

    final firstRowTop = tester.getTopLeft(cards[0]).dy;
    expect(tester.getTopLeft(cards[1]).dy, closeTo(firstRowTop, 0.1));
    expect(tester.getTopLeft(cards[2]).dy, closeTo(firstRowTop, 0.1));

    final secondRowTop = tester.getTopLeft(cards[3]).dy;
    expect(secondRowTop, greaterThan(firstRowTop));
    expect(tester.getTopLeft(cards[4]).dy, closeTo(secondRowTop, 0.1));
    expect(tester.getTopLeft(cards[5]).dy, closeTo(secondRowTop, 0.1));

    final panelBottom = tester
        .getBottomLeft(
          find.byKey(const ValueKey<String>('mega-menu-panel')),
        )
        .dy;
    expect(tester.getBottomLeft(cards[5]).dy, lessThanOrEqualTo(panelBottom));

    final scrollable = find.descendant(
      of: find.byKey(const ValueKey<String>('mega-menu-card-grid')),
      matching: find.byType(Scrollable),
    );
    expect(
        tester.state<ScrollableState>(scrollable).position.maxScrollExtent, 0);
  });

  testWidgets(
      'panel starts below the rendered header inside a nonzero host offset',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const hostOffset = 86.0;
    const headerInset = 18.0;
    const headerHeight = 72.0;
    const headerKey = ValueKey<String>('offset-host-header');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.only(top: hostOffset),
            child: Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.only(top: headerInset),
                    child: MegaMenuHeaderWrapper(
                      key: headerKey,
                      openBackgroundColor: const Color(0xFF000000),
                      child: SizedBox(
                        height: headerHeight,
                        child: Align(
                          alignment: Alignment.center,
                          child: MegaMenuButton(
                            parent: parent,
                            children: children,
                            isEditMode: false,
                            textColor: const Color(0xFF17231C),
                            panelBackgroundColor: const Color(0xFF000000),
                            panelForegroundColor: Colors.white,
                            panelRailBackgroundColor: const Color(0xFF64748B),
                            panelRailForegroundColor: Colors.white,
                            onNavigate: (_, __) {},
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    final headerBackgroundFinder = find
        .descendant(
          of: find.byKey(headerKey),
          matching: find.byType(AnimatedContainer),
        )
        .first;
    expect(headerBackgroundFinder, findsOneWidget);
    final closedHeaderBackground = tester
        .widget<AnimatedContainer>(headerBackgroundFinder)
        .decoration! as BoxDecoration;
    expect(
      closedHeaderBackground.color,
      Colors.transparent,
    );

    await tester.tap(find.text('Componentes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    final openHeaderBackground = tester
        .widget<AnimatedContainer>(headerBackgroundFinder)
        .decoration! as BoxDecoration;
    expect(
      openHeaderBackground.color,
      const Color(0xFF000000),
    );
    final panelFinder = find.byKey(const ValueKey<String>('mega-menu-panel'));
    expect(panelFinder, findsOneWidget);
    final renderedHeaderBottom = tester.getBottomLeft(find.byKey(headerKey)).dy;
    final panelTop = tester.getTopLeft(panelFinder).dy;

    expect(renderedHeaderBottom, hostOffset + headerInset + headerHeight);
    expect(panelTop, closeTo(renderedHeaderBottom, 0.5));
  });

  testWidgets('hovering the editorial rail swaps the visible branch',
      (tester) async {
    final wheels = navigation(
      id: 'wheels',
      label: 'Ruedas',
      linkValue: '/productos/categoria/ruedas',
      children: [
        navigation(
          id: 'rims',
          label: 'Aros',
          linkValue: '/productos/categoria/aros',
        ),
      ],
    );
    children = [...children, wheels];
    parent = WebsiteNavigation(
      id: parent.id,
      tenantId: parent.tenantId,
      label: parent.label,
      linkValue: parent.linkValue,
      linkType: parent.linkType,
      createdAt: parent.createdAt,
      updatedAt: parent.updatedAt,
      children: children,
    );

    await pumpMenu(tester, onNavigate: (_) {});
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    await mouse.moveTo(tester.getCenter(find.text('Componentes')));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('Cadenas'), findsNothing);
    expect(find.text('Aros'), findsNothing);

    await mouse.moveTo(tester.getCenter(find.text('TRANSMISIÓN')));
    await tester.pumpAndSettle();
    expect(find.text('Cadenas'), findsOneWidget);
    expect(find.text('Aros'), findsNothing);

    await mouse.moveTo(tester.getCenter(find.text('RUEDAS')));
    await tester.pump();
    final wheelsTitleReveal = find.byKey(
      const ValueKey<String>('mega-menu-branch-reveal-wheels-title'),
    );
    expect(wheelsTitleReveal, findsOneWidget);
    expect(
      tester.widget<FadeTransition>(wheelsTitleReveal).opacity.value,
      lessThan(1),
    );
    await tester.pump(const Duration(milliseconds: 1300));
    expect(
      tester.widget<FadeTransition>(wheelsTitleReveal).opacity.value,
      closeTo(1, 0.001),
    );
    final wheelsTitle = tester.widget<Text>(
      find.descendant(
        of: wheelsTitleReveal,
        matching: find.text('Ruedas'),
      ),
    );
    expect(wheelsTitle.style?.fontSize, 30);
    await tester.pumpAndSettle();

    expect(find.text('Aros'), findsOneWidget);
    expect(find.text('Cadenas'), findsNothing);

    final railRect = tester.getRect(
      find.byKey(const ValueKey<String>('mega-menu-rail')),
    );
    await mouse.moveTo(railRect.center);
    await tester.pump(const Duration(milliseconds: 240));
    await tester.pumpAndSettle();

    expect(find.text('Aros'), findsNothing);
    expect(find.text('Cadenas'), findsNothing);
  });

  testWidgets('visual cards preview children, drill down and return',
      (tester) async {
    final cassettes = navigation(
      id: 'cassettes',
      label: 'Cassettes',
      children: [
        navigation(
          id: 'cassette-10',
          label: 'Cassette 10 velocidades',
        ),
      ],
    );
    final chains = navigation(
      id: 'chain-groups',
      label: 'Cadenas',
      children: [
        navigation(
          id: 'chain-11',
          label: 'Cadena 11 velocidades',
        ),
      ],
    );
    final drivetrain = navigation(
      id: 'drivetrain',
      label: 'Transmisión',
      children: [cassettes, chains],
    );
    parent = WebsiteNavigation(
      id: parent.id,
      tenantId: parent.tenantId,
      label: parent.label,
      linkValue: parent.linkValue,
      linkType: parent.linkType,
      createdAt: parent.createdAt,
      updatedAt: parent.updatedAt,
      children: [drivetrain],
    );
    children = parent.children;

    await pumpMenu(tester, onNavigate: (_) {});
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    await mouse.moveTo(tester.getCenter(find.text('Componentes')));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 220));
    await mouse.moveTo(tester.getCenter(find.text('TRANSMISIÓN')));
    await tester.pumpAndSettle();

    final cassettesCard = find.byKey(
      const ValueKey<String>('mega-menu-card-cassettes'),
    );
    final chainsCard = find.byKey(
      const ValueKey<String>('mega-menu-card-chain-groups'),
    );
    expect(cassettesCard, findsOneWidget);
    expect(chainsCard, findsOneWidget);
    expect(find.text('Cassette 10 velocidades'), findsNothing);
    expect(
      find.byKey(
        const ValueKey<String>('mega-menu-card-title-cassettes'),
      ),
      findsOneWidget,
    );

    await mouse.moveTo(tester.getCenter(cassettesCard));
    await tester.pump(const Duration(milliseconds: 180));
    expect(find.text('Cassette 10 velocidades'), findsNothing);

    final cassettesExplorer = find.byKey(
      const ValueKey<String>('mega-menu-card-explore-cassettes'),
    );
    final cardRect = tester.getRect(cassettesCard);
    final explorerRect = tester.getRect(cassettesExplorer);
    await mouse.moveTo(Offset(cardRect.left + 8, explorerRect.center.dy));
    await tester.pump(const Duration(milliseconds: 220));
    expect(find.text('Cassette 10 velocidades'), findsNothing);

    await mouse.moveTo(tester.getCenter(cassettesExplorer));
    await tester.pumpAndSettle();
    expect(find.text('Cassette 10 velocidades'), findsOneWidget);

    await tester.tap(cassettesExplorer);
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>('mega-menu-card-cassette-10'),
      ),
      findsOneWidget,
    );
    expect(chainsCard, findsNothing);
    expect(find.text('Volver a Transmisión'), findsOneWidget);
    expect(find.text('VER SECCIÓN'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey<String>('mega-menu-drill-back')),
    );
    await tester.pumpAndSettle();

    expect(cassettesCard, findsOneWidget);
    expect(chainsCard, findsOneWidget);
  });

  testWidgets(
      'homonymous direct option remains distinct from inclusive category CTAs',
      (tester) async {
    final inclusiveChainsHref = WebsiteDestination.routeForCatalog(
      categoryId: 'category-chains',
    );
    final directChainsHref = WebsiteDestination.routeForCatalog(
      categoryId: 'category-chains',
      catalogQuery: WebsiteCatalogQuery(
        categoryScope: WebsiteCatalogCategoryScope.direct,
      ),
    );
    final directChains = navigation(
      id: 'chains-direct',
      label: 'Cadenas',
      linkValue: directChainsHref,
    );
    final chainGuides = navigation(
      id: 'chain-guides',
      label: 'Guías de cadenas',
      linkValue: '/productos/categoria/guias-de-cadenas',
    );
    final chains = navigation(
      id: 'chains',
      label: 'Cadenas',
      linkValue: inclusiveChainsHref,
      children: [directChains, chainGuides],
    );
    final drivetrain = navigation(
      id: 'drivetrain',
      label: 'Transmisión',
      children: [chains],
    );
    parent = WebsiteNavigation(
      id: parent.id,
      tenantId: parent.tenantId,
      label: parent.label,
      linkValue: parent.linkValue,
      linkType: parent.linkType,
      createdAt: parent.createdAt,
      updatedAt: parent.updatedAt,
      children: [drivetrain],
    );
    children = parent.children;
    final navigations = <String>[];

    await pumpMenu(tester, onNavigate: navigations.add);
    await tester.tap(find.text('Componentes'));
    await tester.pumpAndSettle();
    await revealBranch(tester);

    final inclusiveParentDestination = find.byKey(
      const ValueKey<String>('mega-menu-card-navigate-chains'),
    );
    final optionsExplorer = find.byKey(
      const ValueKey<String>('mega-menu-card-explore-chains'),
    );
    expect(inclusiveParentDestination, findsOneWidget);
    expect(optionsExplorer, findsOneWidget);
    expect(find.text('VER SUBCATEGORÍAS'), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(inclusiveParentDestination));
    await tester.pump();
    expect(find.text('Guías de cadenas'), findsNothing);
    expect(
      tester.widget<Text>(find.text('VER SUBCATEGORÍAS')).style?.color,
      PublicStoreTheme.info,
    );

    // Only the explicit subcategory action previews and opens the options.
    await mouse.moveTo(tester.getCenter(optionsExplorer));
    await tester.pumpAndSettle();
    expect(find.text('Guías de cadenas'), findsOneWidget);

    await tester.tap(optionsExplorer);
    await tester.pumpAndSettle();

    expect(navigations, isEmpty);
    expect(
      find.byKey(
        const ValueKey<String>('mega-menu-card-chain-guides'),
      ),
      findsOneWidget,
    );
    expect(
      find.byKey(
        const ValueKey<String>('mega-menu-card-chains-direct'),
      ),
      findsOneWidget,
    );
    expect(find.text('SOLO ESTA CATEGORÍA'), findsWidgets);
    expect(find.text('VER TODO EN CADENAS'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey<String>('mega-menu-card-navigate-chains-direct'),
      ),
    );
    await tester.pumpAndSettle();

    expect(navigations, [directChainsHref]);
    expect(
      WebsiteCatalogQuery.fromUri(
        Uri.parse(navigations.single),
      ).categoryScope,
      WebsiteCatalogCategoryScope.direct,
    );

    // The interior "Ver todo" keeps the outer category's inclusive scope.
    await tester.tap(find.text('Componentes'));
    await tester.pumpAndSettle();
    await revealBranch(tester);
    await tester.tap(optionsExplorer);
    await tester.pumpAndSettle();
    await tester.tap(find.text('VER TODO EN CADENAS'));
    await tester.pumpAndSettle();

    expect(navigations, [directChainsHref, inclusiveChainsHref]);
    expect(
      Uri.parse(navigations.last).queryParameters,
      {'category': 'category-chains'},
    );

    // The exterior category CTA is also inclusive; only the homonymous child
    // carries category_scope=direct.
    await tester.tap(find.text('Componentes'));
    await tester.pumpAndSettle();
    await revealBranch(tester);
    await tester.tap(inclusiveParentDestination);
    await tester.pumpAndSettle();

    expect(
      navigations,
      [directChainsHref, inclusiveChainsHref, inclusiveChainsHref],
    );

    // The rail-level "Ver todo" remains the inclusive catalog destination.
    await tester.tap(find.text('Componentes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('VER TODO'));
    await tester.pumpAndSettle();

    expect(navigations.last, '/productos');
  });

  testWidgets('keyboard opens, exposes links and Escape dismisses the menu',
      (tester) async {
    final navigations = <String>[];
    await pumpMenu(tester, onNavigate: navigations.add);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('VER TODO'), findsOneWidget);
    expect(find.text('Cadenas'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(find.text('Cadenas'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('VER TODO'), findsNothing);
    expect(navigations, isEmpty);
  });

  testWidgets('configured destination navigates and closes the overlay',
      (tester) async {
    final navigations = <String>[];
    await pumpMenu(tester, onNavigate: navigations.add);

    await tester.tap(find.text('Componentes'));
    await tester.pump(const Duration(milliseconds: 320));
    await revealBranch(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('mega-menu-card-navigate-chains')),
    );
    await tester.pump(const Duration(milliseconds: 320));

    expect(navigations, ['/productos/categoria/cadenas']);
    expect(find.text('VER TODO'), findsNothing);
  });

  testWidgets('compact dropdown consumes the same configured destinations',
      (tester) async {
    final navigations = <String>[];
    final directChild = navigation(
      id: 'brakes',
      label: 'Frenos',
      linkValue: '/productos/categoria/frenos',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF235D3A),
          ),
        ),
        home: Scaffold(
          body: NavigationDropdownButton(
            parent: parent,
            children: [directChild],
            isEditMode: false,
            textColor: const Color(0xFF17231C),
            panelBackgroundColor: const Color(0xFF111714),
            panelForegroundColor: Colors.white,
            onNavigate: (href, _) => navigations.add(href),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Componentes'));
    await tester.pumpAndSettle();

    expect(find.text('VER TODO COMPONENTES'), findsOneWidget);
    expect(find.text('Frenos'), findsOneWidget);
    expect(find.byType(SubmenuButton), findsNothing);

    await tester.tap(find.text('Frenos'));
    await tester.pumpAndSettle();

    expect(navigations, ['/productos/categoria/frenos']);
  });
}
