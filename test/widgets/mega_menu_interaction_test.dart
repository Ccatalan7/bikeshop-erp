import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/public_store/services/public_category_publication.dart';
import 'package:vinabike_erp/public_store/widgets/mega_menu.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';
import 'package:vinabike_public_core/public_store/models/header_menu_help.dart';
import 'package:vinabike_public_core/public_store/theme/header_menu_palette.dart';

/// The wide panel on the editor's Flutter canvas (2026-10-25): the first
/// level as a column of sections, the open section's subcategories with
/// theirs under them, its photo and the help card, as the HTML store draws
/// it (`services/storefront_html/lib/src/mega_menu_view.dart`).
HeaderMenuPalette palette([Map<String, String> settings = const {}]) =>
    HeaderMenuPalette.fromTheme(
      primary: WebsiteRgba.fromArgb(0xFF123F68),
      background: WebsiteRgba.fromArgb(0xFFFFFFFF),
      onSurface: WebsiteRgba.fromArgb(0xFF1E293B),
      read: (key) => settings[key] ?? '',
    );

HeaderMenuHelp help({
  Map<String, String> settings = const {},
  String whatsapp = '',
}) =>
    HeaderMenuHelp.resolve(
      (key) => settings[key] ?? '',
      whatsappDigits: whatsapp,
      storeName: 'Viñabike',
    );

void main() {
  WebsiteNavigation navigation({
    required String id,
    required String label,
    String? linkValue,
    NavLinkType linkType = NavLinkType.page,
    String? icon,
    List<WebsiteNavigation> children = const [],
  }) {
    final now = DateTime(2026, 7, 22);
    return WebsiteNavigation(
      id: id,
      tenantId: 'tenant-1',
      label: label,
      icon: icon,
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
    final chain = navigation(
      id: 'chain',
      label: 'Cadena 11v',
      linkValue: '/productos/categoria/cadena-11v',
    );
    final chains = navigation(
      id: 'chains',
      label: 'Cadenas',
      linkValue: '/productos/categoria/cadenas',
      children: [chain],
    );
    final drivetrain = navigation(
      id: 'drivetrain',
      label: 'Transmisión',
      icon: 'transmision',
      linkValue: '/productos/categoria/transmision',
      children: [chains],
    );
    final rims = navigation(
      id: 'rims',
      label: 'Aros',
      linkValue: '/productos/categoria/aros',
    );
    final wheels = navigation(
      id: 'wheels',
      label: 'Ruedas',
      icon: 'rueda',
      linkValue: '/productos/categoria/ruedas',
      children: [rims],
    );
    parent = navigation(
      id: 'components',
      label: 'Componentes',
      linkValue: '/productos',
      children: [drivetrain, wheels],
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
    Size surfaceSize = const Size(1400, 800),
    Map<String, MegaMenuBranchPresentation> branchPresentations =
        const <String, MegaMenuBranchPresentation>{},
    bool Function(WebsiteNavigation navigation)? canNavigate,
    HeaderMenuPalette? menuPalette,
    HeaderMenuHelp? menuHelp,
  }) async {
    await tester.binding.setSurfaceSize(surfaceSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF123F68),
            surface: Colors.white,
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
                palette: menuPalette ?? palette(),
                help: menuHelp ?? help(),
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

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('Componentes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
  }

  bool shown(String text) =>
      find.text(text).hitTestable().evaluate().isNotEmpty;

  testWidgets(
      'hover intent opens the column of sections on the first one, '
      'and leaving both closes it', (tester) async {
    final navigations = <String>[];
    await pumpMenu(tester, onNavigate: navigations.add);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    await mouse.moveTo(tester.getCenter(find.text('Componentes')));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 320));

    final panelFinder = find.byKey(const ValueKey<String>('mega-menu-panel'));
    expect(panelFinder, findsOneWidget);
    expect(
      tester.getSize(panelFinder).width,
      tester.getSize(find.byType(Scaffold)).width,
    );
    // Blank menu colors: the panel is the theme's background.
    expect(tester.widget<Material>(panelFinder).color, Colors.white);
    expect(
      find.byKey(const ValueKey<String>('mega-menu-rail')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('mega-menu-section-drivetrain')),
      findsOneWidget,
    );
    expect(shown('Ver todo Componentes'), isTrue);
    // The first section is open: its name, page, subcategories and theirs.
    expect(shown('Ver todo Transmisión'), isTrue);
    expect(shown('Cadenas'), isTrue);
    expect(shown('Cadena 11v'), isTrue);
    expect(shown('Aros'), isFalse);

    await mouse.moveTo(const Offset(1390, 790));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 340));

    expect(panelFinder, findsNothing);
    expect(navigations, isEmpty);
  });

  testWidgets(
      'hovering a row opens its section, and the panel keeps the '
      'height of the tallest', (tester) async {
    await pumpMenu(tester, onNavigate: (_) {});
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await open(tester);

    final panelFinder = find.byKey(const ValueKey<String>('mega-menu-panel'));
    final before = tester.getSize(panelFinder).height;
    await mouse.moveTo(
      tester.getCenter(
        find.byKey(const ValueKey<String>('mega-menu-section-wheels')),
      ),
    );
    await tester.pumpAndSettle();

    expect(shown('Aros'), isTrue);
    expect(shown('Cadenas'), isFalse);
    expect(shown('Ver todo Ruedas'), isTrue);
    expect(tester.getSize(panelFinder).height, before);
  });

  testWidgets(
      'a subcategory, its own and «Ver todo» navigate and close the '
      'panel', (tester) async {
    final navigations = <String>[];
    await pumpMenu(tester, onNavigate: navigations.add);
    await open(tester);

    await tester.tap(find.text('Cadena 11v'));
    await tester.pump(const Duration(milliseconds: 320));
    expect(navigations, ['/productos/categoria/cadena-11v']);
    expect(find.byKey(const ValueKey<String>('mega-menu-panel')), findsNothing);

    await open(tester);
    await tester.tap(find.text('Ver todo Transmisión'));
    await tester.pump(const Duration(milliseconds: 320));
    expect(navigations.last, '/productos/categoria/transmision');
  });

  testWidgets(
      'publication projection hides unpublished subcategories and their links',
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
    await open(tester);

    expect(shown('Cadenas'), isTrue);
    expect(find.text('Piñones'), findsNothing);
    expect(find.text('Ver todo Transmisión'), findsNothing);
    expect(shown('Ver todo Componentes'), isTrue);
    expect(navigations, isEmpty);
  });

  testWidgets(
      'an open overlay reprojects after build without marking itself dirty during build',
      (tester) async {
    await pumpMenu(tester, onNavigate: (_) {});
    await open(tester);
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
    expect(find.text('Frenado'), findsWidgets);
    expect(find.text('Transmisión'), findsNothing);
  });

  testWidgets(
      'the open section shows its photo, keyed by navigation id, '
      'over the help card', (tester) async {
    const imageUrl = 'https://cdn.example.test/drivetrain-menu.webp';
    final navigations = <String>[];
    await pumpMenu(
      tester,
      onNavigate: navigations.add,
      branchPresentations: const {
        'drivetrain': MegaMenuBranchPresentation(imageUrl: imageUrl),
      },
      menuHelp: help(whatsapp: '56912345678'),
    );
    await open(tester);

    final image = find.byKey(
      const ValueKey<String>('mega-menu-branch-image-drivetrain'),
    );
    expect(image, findsOneWidget);
    expect(
      (tester
              .widget<Image>(
                  find.descendant(of: image, matching: find.byType(Image)))
              .image as NetworkImage)
          .url,
      imageUrl,
    );
    expect(shown(HeaderMenuHelp.defaultTitle), isTrue);
    await tester.tap(find.text(HeaderMenuHelp.defaultWhatsAppAction));
    await tester.pump(const Duration(milliseconds: 320));
    expect(navigations.single, startsWith('https://wa.me/56912345678?text='));
  });

  testWidgets('the editor\'s colors paint the panel, and its help can be off',
      (tester) async {
    await pumpMenu(
      tester,
      onNavigate: (_) {},
      menuPalette: palette({HeaderMenuPalette.surfaceKey: '#000000'}),
      menuHelp: help(settings: {HeaderMenuHelp.showKey: 'false'}),
    );
    await open(tester);

    expect(
      tester
          .widget<Material>(
            find.byKey(const ValueKey<String>('mega-menu-panel')),
          )
          .color,
      const Color(0xFF000000),
    );
    expect(find.byKey(const ValueKey<String>('mega-menu-help')), findsNothing);
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
                            palette: palette(),
                            help: help(),
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
                              palette: palette(),
                              help: help(),
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

  testWidgets('keyboard opens on the first section and Escape dismisses',
      (tester) async {
    final navigations = <String>[];
    await pumpMenu(tester, onNavigate: navigations.add);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 320));

    expect(shown('Cadenas'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.byKey(const ValueKey<String>('mega-menu-panel')), findsNothing);
    expect(navigations, isEmpty);
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
