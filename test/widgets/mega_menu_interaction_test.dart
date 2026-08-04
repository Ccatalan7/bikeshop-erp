import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_erp/modules/website/models/website_catalog_query.dart';
import 'package:vinabike_erp/modules/website/models/website_destination.dart';
import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/public_store/services/public_category_publication.dart';
import 'package:vinabike_erp/public_store/theme/public_store_theme.dart';
import 'package:vinabike_erp/public_store/widgets/mega_menu.dart';

void main() {
  WebsiteNavigation navigation({
    required String id,
    required String label,
    String? linkValue,
    NavLinkType linkType = NavLinkType.page,
    List<WebsiteNavigation> children = const [],
  }) {
    final now = DateTime(2026, 7, 22);
    return WebsiteNavigation(
      id: id,
      tenantId: 'tenant-1',
      label: label,
      linkType: linkType,
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
    bool Function(WebsiteNavigation navigation)? canNavigate,
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
                canNavigate: canNavigate,
                onNavigate: (href, _) => onNavigate(href),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Reads the rendered weight of a rail tab's label: the section tab's own
  /// contract renders w800 when active and w600 when inactive, so this is a
  /// direct semantic read of the active state — no new visual literal.
  FontWeight? railTabWeight(WidgetTester tester, String label) {
    final text = tester.widget<Text>(
      find.descendant(
        of: find.widgetWithText(TextButton, label),
        matching: find.text(label),
      ),
    );
    return text.style?.fontWeight;
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
    // The structured root opens with its default active branch already
    // expanded, so the panel is full-height and click targets are stable
    // from the first frame.
    expect(find.text('Cadenas'), findsOneWidget,
        reason: 'the first root branch is deterministically active on open');
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

  testWidgets(
      'publication projection hides invalid leaves and disables structural CTAs',
      (tester) async {
    const chainsId = '11111111-1111-4111-8111-111111111111';
    const sprocketsId = '22222222-2222-4222-8222-222222222222';
    const drivetrainId = '33333333-3333-4333-8333-333333333333';
    final chains = navigation(
      id: 'chains',
      label: 'Cadenas',
      linkType: NavLinkType.category,
      linkValue: chainsId,
    );
    final sprockets = navigation(
      id: 'sprockets',
      label: 'Piñones',
      linkType: NavLinkType.category,
      linkValue: sprocketsId,
    );
    final drivetrain = navigation(
      id: 'drivetrain',
      label: 'Transmisión',
      linkType: NavLinkType.category,
      linkValue: drivetrainId,
      children: [chains, sprockets],
    );
    final authoredParent = navigation(
      id: 'components',
      label: 'Componentes',
      linkValue: '/productos',
      children: [drivetrain],
    );
    final publication = PublicCategoryPublication.resolve(
      categories: const [
        PublicCategoryDescriptor(
          id: chainsId,
          name: 'Cadenas',
          fullPath: 'Componentes / Transmisión / Cadenas',
          showOnWebsite: true,
        ),
        PublicCategoryDescriptor(
          id: sprocketsId,
          name: 'Piñones',
          fullPath: 'Componentes / Transmisión / Piñones',
          showOnWebsite: false,
        ),
        PublicCategoryDescriptor(
          id: drivetrainId,
          name: 'Transmisión',
          fullPath: 'Componentes / Transmisión',
          showOnWebsite: false,
        ),
      ],
      navigation: [authoredParent],
    );
    final projection = PublicCategoryNavigationProjection(publication);
    parent = projection.forDesktop([authoredParent]).single;
    children = parent.children;
    final navigations = <String>[];

    await pumpMenu(
      tester,
      onNavigate: navigations.add,
      canNavigate: projection.canNavigate,
    );

    await tester.tap(find.text('Componentes'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'TRANSMISIÓN'));
    await tester.pumpAndSettle();
    await revealBranch(tester);

    expect(navigations, isEmpty);
    expect(find.text('Cadenas'), findsOneWidget);
    expect(find.text('Piñones'), findsNothing);
    expect(find.text('Explorar Transmisión'), findsNothing);
    expect(find.text('VER TODO'), findsOneWidget);
  });

  testWidgets(
      'an open overlay reprojects after build without marking itself dirty during build',
      (tester) async {
    await pumpMenu(tester, onNavigate: (_) {});
    await tester.tap(find.text('Componentes'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('mega-menu-panel')),
      findsOneWidget,
    );

    final brakes = navigation(
      id: 'brakes',
      label: 'Frenos',
      linkValue: '/productos/categoria/frenos',
    );
    final replacementBranch = navigation(
      id: 'braking',
      label: 'Frenado',
      linkValue: '/productos/categoria/frenado',
      children: [brakes],
    );
    parent = navigation(
      id: 'components',
      label: 'Componentes',
      linkValue: '/productos',
      children: [replacementBranch],
    );
    children = parent.children;

    await pumpMenu(tester, onNavigate: (_) {});
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('FRENADO'), findsOneWidget);
    expect(find.text('TRANSMISIÓN'), findsNothing);
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

  testWidgets(
      'panel starts below the rendered header under a 0.8 topLeft window '
      'zoom (ERP Preview owner)', (tester) async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);
    await tester.binding.setSurfaceSize(const Size(1200, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const hostOffset = 86.0;
    const headerInset = 18.0;
    const headerHeight = 72.0;
    const zoomScale = 0.8;
    const headerKey = ValueKey<String>('zoomed-host-header');

    // Reproduces the real owner: the ERP Preview WindowZoomScope wraps the
    // WHOLE storefront — its Navigator/Overlay included — in a topLeft
    // Transform.scale(0.8). The panel must convert every global point
    // through the Overlay's own RenderBox so the transform is inverted
    // exactly once; the old manual origin subtraction double-scaled and
    // overlapped the header.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Transform.scale(
            scale: zoomScale,
            alignment: Alignment.topLeft,
            child: Padding(
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
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('Componentes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    final panelFinder = find.byKey(const ValueKey<String>('mega-menu-panel'));
    expect(panelFinder, findsOneWidget);

    // GLOBAL coordinates: under the zoom the rendered header ends at
    // 0.8 * (host + inset + height); the panel's first painted row must
    // start exactly there — never 0.8 * that again.
    final renderedHeaderBottom = tester.getBottomLeft(find.byKey(headerKey)).dy;
    final panelTop = tester.getTopLeft(panelFinder).dy;
    expect(
      renderedHeaderBottom,
      closeTo(zoomScale * (hostOffset + headerInset + headerHeight), 0.5),
    );
    expect(panelTop, closeTo(renderedHeaderBottom, 0.5),
        reason: 'the panel opens flush under the zoomed header, with no '
            'overlap and no double-scaled gap');
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
    // Deterministic default branch on open: the FIRST root (Transmisión)
    // shows its detail; the other branch stays hidden until hovered.
    expect(find.text('Cadenas'), findsOneWidget,
        reason: 'the first root branch is deterministically active on open');
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

    // Hovering the blank rail NO LONGER collapses the body: the panel keeps
    // its stable full-height topology and the content returns to the
    // deterministic default (first structured) branch.
    expect(find.text('Aros'), findsNothing);
    expect(find.text('Cadenas'), findsOneWidget,
        reason: 'blank rail returns to the default branch, never a collapse '
            'that moves hit targets mid-gesture');
    // Rail highlight follows the SAME effective branch on the blank-rail
    // return: default tab active again, the previously hovered one not.
    expect(railTabWeight(tester, 'TRANSMISIÓN'), FontWeight.w800,
        reason: 'the rail marks the default branch after the blank-rail '
            'return');
    expect(railTabWeight(tester, 'RUEDAS'), FontWeight.w600);
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
    // The caption now carries the branch depth, so a visitor can see how far
    // a branch goes before entering it.
    expect(find.text('2 SUBCATEGORÍAS'), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(inclusiveParentDestination));
    await tester.pump();
    expect(find.text('Guías de cadenas'), findsNothing);
    expect(
      tester.widget<Text>(find.text('2 SUBCATEGORÍAS')).style?.color,
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

  testWidgets(
      'a structured root opens full-height with its active branch visible '
      'and the FIRST rail click navigates', (tester) async {
    // Hit-test misses are fatal: a moving hit target (the old mid-gesture
    // body insertion) must fail loudly, never degrade to a warning.
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);

    final navigations = <String>[];
    await pumpMenu(tester, onNavigate: navigations.add);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('Componentes')));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pumpAndSettle();

    // The branch detail exists deterministically from opening — no branch
    // hover happened yet.
    expect(find.text('Cadenas'), findsOneWidget,
        reason: 'the default active branch exposes its detail from the '
            'first frame');
    expect(find.text('VER TODO'), findsOneWidget);
    // Body and rail consume the SAME effective active branch: the default
    // branch's tab is highlighted from the first frame.
    expect(railTabWeight(tester, 'TRANSMISIÓN'), FontWeight.w800,
        reason: 'the rail marks the default active branch from opening');

    // ONE click on the rail tab navigates: the topology did not shift under
    // the pointer.
    await tester.tap(find.widgetWithText(TextButton, 'TRANSMISIÓN'));
    await tester.pumpAndSettle();
    expect(navigations, ['/productos/categoria/transmision']);
  });

  testWidgets(
      'a mixed rail defaults to the first STRUCTURED branch and the flat '
      'link keeps its navigation', (tester) async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);

    // Flat link FIRST, structured branch AFTER: the deterministic default
    // must be the first root that actually has visible children, never
    // blindly roots.first.
    final offers = navigation(
      id: 'offers',
      label: 'Ofertas',
      linkValue: '/ofertas',
    );
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
      children: [offers, drivetrain],
    );
    children = parent.children;

    final navigations = <String>[];
    await pumpMenu(tester, onNavigate: navigations.add);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('Componentes')));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pumpAndSettle();

    // The structured branch owns the default detail and its tab is active;
    // the flat link is not marked active.
    expect(find.text('Cadenas'), findsOneWidget,
        reason: 'the first STRUCTURED root owns the default detail');
    expect(railTabWeight(tester, 'TRANSMISIÓN'), FontWeight.w800);
    expect(railTabWeight(tester, 'OFERTAS'), FontWeight.w600);

    // The flat link still navigates on its own click.
    await tester.tap(find.widgetWithText(TextButton, 'OFERTAS'));
    await tester.pumpAndSettle();
    expect(navigations, ['/ofertas'],
        reason: 'a flat rail link keeps visitor navigation');
  });

  testWidgets('a nested visual card navigates on its FIRST click after opening',
      (tester) async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = false);

    final navigations = <String>[];
    await pumpMenu(tester, onNavigate: navigations.add);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(find.text('Componentes')));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 220));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('mega-menu-card-navigate-chains')),
    );
    await tester.pump(const Duration(milliseconds: 320));

    expect(navigations, ['/productos/categoria/cadenas']);
    expect(find.text('VER TODO'), findsNothing,
        reason: 'navigation closes the overlay');
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
    // A structured root opens with its default active branch ALREADY
    // expanded: keyboard users see the same deterministic full-height panel
    // as pointer users, from the first frame.
    expect(find.text('Cadenas'), findsOneWidget,
        reason: 'the branch detail is present from opening, never gated on '
            'a second hover/Tab');

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

    final trigger = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Componentes'),
    );
    expect(
      trigger.style?.backgroundColor?.resolve({WidgetState.hovered}),
      const Color(0xFF17231C).withValues(alpha: 0.08),
    );
    expect(
      trigger.style?.backgroundColor?.resolve(<WidgetState>{}),
      Colors.transparent,
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
