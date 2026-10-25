import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../support/library_source.dart';

void main() {
  test('navigation width control selects the saved desktop renderer', () {
    final editor = File(
      'lib/modules/website/pages/navigation_management_page.dart',
    ).readAsStringSync();
    final layout =
        readLibrarySource('lib/public_store/widgets/public_store_layout.dart');
    final inspector = readLibrarySource(
        'lib/modules/website/widgets/website_editor_panel.dart');

    expect(editor, contains('cssClass: _resolvedCssClass()'));
    expect(editor, contains("token.toLowerCase() != 'megamenu'"));
    expect(editor, contains("tokens.add('megamenu')"));
    expect(editor, contains('widget.location == MenuLocation.header'));
    expect(editor, contains('_selectedParentId == null'));
    expect(layout, contains('nav.cssClass'));
    expect(layout, contains("'megamenu'"));
    expect(layout, contains('MegaMenuButton('));
    expect(layout, contains('NavigationDropdownButton('));
    expect(layout, contains("'header_menu_surface_color'"));
    expect(layout, contains("'header_menu_rail_color'"));
    expect(layout, contains("'header_navigation_uppercase'"));
    expect(layout, contains('uppercaseLabel:'));
    expect(layout, contains('nav.label.toUpperCase()'));
    expect(layout, isNot(contains('menuSurfaceColor: headerBgColor')));
    // One color rule for the open panel, shared with the HTML store
    // (`HeaderMenuPalette`, 2026-10-25), and the editor's help card.
    expect(
        layout, contains('final menuPalette = HeaderMenuPalette.fromTheme('));
    expect(layout, contains('palette: menuPalette,'));
    expect(layout, contains('help: _menuHelp,'));
    expect(layout, contains('_menuHelp = HeaderMenuHelp.resolve('));
    expect(
      layout,
      matches(
        RegExp(
          r'final headerGeometry\s*=\s*'
          r'PublicStoreHeaderGeometry\.resolve\(screenWidth\)',
          multiLine: true,
        ),
      ),
    );
    expect(
        layout, contains('final isDesktopHeader = headerGeometry.isDesktop'));
    // La autoridad de estos dos valores es `effective(...)`: al reabrir el
    // control, el borrador PENDIENTE gana sobre lo guardado, porque un staged
    // sin guardar no puede contradecir el lienzo que está previsualizando.
    // `getSetting` sigue existiendo dentro de ese resolvedor, como el
    // respaldo guardado, no como el lector directo del control.
    expect(
      inspector,
      matches(
        RegExp(
          r'String effective\(String key, String defaultValue\) =>\s*'
          r'widget\.provider\.getEffectiveHeaderSetting\(\s*key,\s*'
          r'service\.getSetting\(key, defaultValue\),',
          multiLine: true,
        ),
      ),
    );
    expect(
      inspector,
      matches(
        RegExp(
          r"effective\(\s*'header_menu_surface_color',\s*''\s*\)",
          multiLine: true,
        ),
      ),
    );
    expect(
      inspector,
      matches(
        RegExp(
          r"effective\(\s*'header_menu_rail_color',\s*''\s*\)",
          multiLine: true,
        ),
      ),
    );
    expect(
      inspector,
      contains("'header_menu_surface_color':"),
    );
    expect(
      inspector,
      contains("'header_menu_rail_color':"),
    );
    expect(
      inspector,
      contains(
          "'header_navigation_uppercase': _navigationUppercase.toString()"),
    );
    expect(
      inspector,
      contains("effective('header_navigation_uppercase', 'true')"),
    );
    expect(
      inspector,
      contains('Títulos del menú en mayúsculas'),
    );
    for (final key in const [
      'HeaderMenuHelp.showKey',
      'HeaderMenuHelp.titleKey',
      'HeaderMenuHelp.textKey',
      'HeaderMenuHelp.actionKey',
    ]) {
      expect(inspector, contains('$key:'));
      expect(inspector, contains('effective($key,'));
    }
    expect(
      File('lib/public_store/widgets/mega_menu.dart').readAsStringSync(),
      contains('widget.parent.label.toUpperCase()'),
    );
  });

  test('desktop navigation draws sections in a column with their icons', () {
    final source = File(
      'lib/public_store/widgets/mega_menu.dart',
    ).readAsStringSync();

    expect(source, contains('_visibleDesktopNodes(widget.children)'));
    expect(source, contains('_buildRail('));
    expect(source, contains('_buildSection('));
    expect(source, contains('_buildGroup('));
    expect(source, contains('_buildAside('));
    expect(source, contains('WebsiteMenuIconView('));
    expect(source, contains("ValueKey<String>('mega-menu-rail')"));
    expect(source, contains("ValueKey<String>('mega-menu-panel')"));
    expect(source, contains("'mega-menu-section-\${section.id}'"));
    expect(source, contains("'mega-menu-branch-image-\${active!.id}'"));
    expect(source, contains("'Ver todo \$title'"));
    expect(source, contains('maintainSize: true'));
    expect(source, contains('bool _aiming()'));
    expect(source, contains('final HeaderMenuPalette palette;'));
    expect(source, contains('final HeaderMenuHelp help;'));
    expect(source, isNot(contains('_MegaMenuMediaCard(')));
    expect(source, isNot(contains('_drilldownPath')));
    expect(source, isNot(contains('maxWidth: 1240')));
    expect(source, isNot(contains('SubmenuButton(')));
    expect(source, contains('LogicalKeyboardKey.arrowDown'));
    expect(source, contains('LogicalKeyboardKey.escape'));
    expect(source, contains('onEnter: (_)'));
    expect(source, contains('_scheduleOpen();'));
  });

  test('category scope survives editor save and renderer projection', () {
    final editor = File(
      'lib/modules/website/pages/navigation_management_page.dart',
    ).readAsStringSync();
    final menu = File(
      'lib/public_store/widgets/mega_menu.dart',
    ).readAsStringSync();

    expect(
      editor,
      contains('WebsiteCatalogQuery.tryParse(uri)'),
    );
    expect(
      editor,
      contains(
        'query?.categoryScope ?? WebsiteCatalogCategoryScope.subtree',
      ),
    );
    expect(
      editor,
      contains('categoryScope: _selectedCategoryScope'),
    );
    expect(
      editor,
      contains('_selectedCategoryScope = WebsiteCatalogCategoryScope.direct'),
    );
    expect(
      menu,
      contains(
        'WebsiteCatalogQuery.tryParse(uri)?.categoryScope ==\n'
        '      WebsiteCatalogCategoryScope.direct',
      ),
    );
    // The compact list still says when an item shows only its category.
    expect(menu, contains("'Solo esta categoría'"));
  });

  test('mega-menu category artwork resolves from typed destinations', () {
    final layout =
        readLibrarySource('lib/public_store/widgets/public_store_layout.dart');
    final menu = File(
      'lib/public_store/widgets/mega_menu.dart',
    ).readAsStringSync();

    // The typed resolution has one owner the HTML store's wide menu shares
    // (`megaMenuPresentationOf`, vinabike_public_core, 2026-10-06).
    final owner = File(
      'packages/vinabike_public_core/lib/public_store/services/'
      'mega_menu_presentation.dart',
    ).readAsStringSync();
    expect(layout, contains('_projectMegaMenuBranchPresentations('));
    expect(layout, contains('megaMenuPresentationOf(branch, registry)'));
    expect(owner, contains("WebsiteDestination.parse(item.href ?? '')"));
    expect(
      owner,
      contains('destination.kind != WebsiteDestinationKind.category'),
    );
    expect(owner, contains('registry.forCategory(reference)'));
    expect(
      owner,
      contains('registry.resolveSlug(reference)?.presentation'),
    );
    expect(layout, contains('projections[branch.id] ='));
    expect(layout, contains('for (final child in branch.children)'));
    expect(layout, contains('visit(child);'));
    expect(layout, contains('visit(branch);'));
    expect(layout, contains('presentation.megaMenuImageUrl'));
    // The panel draws the photo as it is (2026-10-25): the old card's
    // darkening, width and text placement have no control and no reader.
    expect(layout, isNot(contains('presentation.megaMenuOverlay')));
    expect(layout, isNot(contains('presentation.megaMenuContentAlignment')));
    expect(
      layout,
      contains('branchPresentations:'),
    );

    expect(
      menu,
      contains('final Map<String, MegaMenuBranchPresentation> '
          'branchPresentations;'),
    );
    expect(menu, contains('widget.branchPresentations[section.id]'));
    expect(menu, contains('Image.network('));
    expect(
      '$layout\n$menu',
      isNot(contains('website_megamenu_transmission_premium.png')),
    );
  });

  test('empty navigation exposes its canonical editor instead of fake links',
      () {
    final layout =
        readLibrarySource('lib/public_store/widgets/public_store_layout.dart');

    expect(layout, contains('Configurar navegación'));
    expect(
      layout,
      contains('WebsiteWorkspacePanel.navigation'),
    );
    expect(layout, isNot(contains('Widget _buildNavLink(')));
  });

  test('category publication gates menus, CMS cards, and stale CTA clicks', () {
    final layout =
        readLibrarySource('lib/public_store/widgets/public_store_layout.dart');
    final blocks = File(
      'lib/modules/website/widgets/website_block_renderer.dart',
    ).readAsStringSync();
    final catalog = File(
      'lib/public_store/pages/product_catalog_page.dart',
    ).readAsStringSync();

    expect(layout, contains('PublicCategoryNavigationProjection('));
    expect(layout, contains('categoryNavigationProjection.forDesktop('));
    expect(layout, contains('categoryNavigationProjection.forMobile('));
    expect(layout, contains('if (!_allowsPublicHref(normalized))'));
    expect(
      layout,
      contains('internalOrigins: _storefrontInternalOrigins'),
    );
    expect(blocks, contains('isNavigationEligible'));
    expect(blocks, isNot(contains('independent of DB')));
    expect(blocks, isNot(contains('_useManualCategories')));
    expect(
      catalog,
      contains('forceCategoryRefresh: categorySnapshot == null'),
      reason: 'A published cache event must not recursively force the origin.',
    );
  });

  test('no lib file issues a direct DELETE against website_navigation', () {
    final violations = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync().replaceAll(RegExp(r'\s+'), '');
      if (source.contains(".from('website_navigation').delete(")) {
        violations.add(entity.path);
      }
    }
    expect(
      violations,
      isEmpty,
      reason: 'delete_website_navigation (authority-bound, idempotent RPC) '
          'is the ONLY delete owner: a direct DELETE silently filters to '
          'zero rows under a stale grant.',
    );
  });
}
