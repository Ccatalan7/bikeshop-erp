import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('navigation width control selects the saved desktop renderer', () {
    final editor = File(
      'lib/modules/website/pages/navigation_management_page.dart',
    ).readAsStringSync();
    final layout = File(
      'lib/public_store/widgets/public_store_layout.dart',
    ).readAsStringSync();
    final inspector = File(
      'lib/modules/website/widgets/website_editor_panel.dart',
    ).readAsStringSync();

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
    expect(layout, isNot(contains('menuSurfaceColor: headerBgColor')));
    expect(layout, contains('final resolvedMenuSurface ='));
    expect(layout, contains('configuredMenuSurface.withValues(alpha: 1)'));
    expect(layout, contains('final menuPanelForegroundColor ='));
    expect(
      layout,
      matches(
        RegExp(
          r'panelForegroundColor:\s+menuPanelForegroundColor',
          multiLine: true,
        ),
      ),
    );
    expect(
      layout,
      isNot(
        matches(
          RegExp(
            r'panelForegroundColor:\s+textColor',
            multiLine: true,
          ),
        ),
      ),
    );
    expect(
      layout,
      matches(
        RegExp(
          r'panelRailBackgroundColor:\s+resolvedMenuRail',
          multiLine: true,
        ),
      ),
    );
    expect(
      layout,
      matches(
        RegExp(
          r'panelRailForegroundColor:\s+menuRailForegroundColor',
          multiLine: true,
        ),
      ),
    );
    expect(layout, contains('final isDesktopHeader = screenWidth >= 1080'));
    expect(
      inspector,
      matches(
        RegExp(
          r"getSetting\(\s*'header_menu_surface_color',\s*'#000000'\s*\)",
          multiLine: true,
        ),
      ),
    );
    expect(
      inspector,
      matches(
        RegExp(
          r"getSetting\(\s*'header_menu_rail_color',\s*'#64748B'\s*\)",
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
  });

  test('desktop navigation preserves recursive visual-card hierarchy', () {
    final source = File(
      'lib/public_store/widgets/mega_menu.dart',
    ).readAsStringSync();

    expect(source, contains('_visibleDesktopNodes(widget.children)'));
    expect(source, contains('_buildNavigationRail('));
    expect(source, contains('_buildVisualCategoryBrowser('));
    expect(source, contains('_buildVisualCardGrid('));
    expect(source, contains('_MegaMenuMediaCard('));
    expect(source, contains('_drilldownPath'));
    expect(source, contains('_openVisualCategory('));
    expect(source, contains('_closeVisualCategory('));
    expect(source, contains("ValueKey<String>('mega-menu-drill-back')"));
    expect(source, contains("ValueKey<String>('mega-menu-card-grid')"));
    expect(source, contains('SliverGridDelegateWithMaxCrossAxisExtent('));
    expect(source, contains('maxCrossAxisExtent: 286'));
    expect(source, contains('mainAxisExtent: 184'));
    expect(source, contains("'mega-menu-card-\${node.id}'"));
    expect(
      source,
      contains("'mega-menu-card-image-\${widget.navigationId}'"),
    );
    expect(
      source,
      contains("'mega-menu-card-hover-\${widget.navigationId}'"),
    );
    expect(
      source,
      contains("'mega-menu-card-explore-\${widget.navigationId}'"),
    );
    expect(
      source,
      contains("'mega-menu-card-navigate-\${widget.navigationId}'"),
    );
    expect(source, contains('Explorar subcategorías de'));
    expect(source, contains('Ver categoría \${widget.label}'));
    expect(source, contains('VER TODO EN \${levelOwner.label.toUpperCase()}'));
    expect(source, contains('onHover: (value)'));
    expect(source, contains('onFocusChange: updateFocus'));
    expect(source, contains('subcategorías'));
    expect(source, isNot(contains('_buildBranchDiscovery(')));
    expect(source, isNot(contains('_buildActiveGroup(')));
    expect(source, isNot(contains('VER SECCIÓN')));
    expect(source, contains('panelBackgroundColor'));
    expect(source, contains('panelRailBackgroundColor'));
    expect(source, contains('panelRailForegroundColor'));
    expect(source, contains("ValueKey<String>('mega-menu-rail')"));
    expect(source, isNot(contains('maxWidth: 1240')));
    expect(source, isNot(contains('SubmenuButton(')));
    expect(source, isNot(contains('colors.scrim')));
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
    expect(menu, contains("'SOLO ESTA CATEGORÍA'"));
    expect(
      menu,
      contains("'mega-menu-card-explore-\${widget.navigationId}'"),
    );
    expect(
      menu,
      contains("'mega-menu-card-navigate-\${widget.navigationId}'"),
    );
    expect(
      menu,
      contains('levelOwner.href!'),
    );
  });

  test('mega-menu category artwork resolves from typed destinations', () {
    final layout = File(
      'lib/public_store/widgets/public_store_layout.dart',
    ).readAsStringSync();
    final menu = File(
      'lib/public_store/widgets/mega_menu.dart',
    ).readAsStringSync();

    expect(layout, contains('_projectMegaMenuBranchPresentations('));
    expect(
      layout,
      contains("WebsiteDestination.parse(branch.href ?? '')"),
    );
    expect(
      layout,
      contains('destination.kind == WebsiteDestinationKind.category'),
    );
    expect(layout, contains('registry.forCategory(reference)'));
    expect(
      layout,
      contains('registry.resolveSlug(reference)?.presentation'),
    );
    expect(layout, contains('projections[branch.id] ='));
    expect(layout, contains('for (final child in branch.children)'));
    expect(layout, contains('visit(child);'));
    expect(layout, contains('visit(branch);'));
    expect(layout, contains('presentation.megaMenuImageUrl'));
    expect(layout, contains('presentation.megaMenuOverlay'));
    expect(
      layout,
      contains('branchPresentations:'),
    );

    expect(
      menu,
      contains('final Map<String, MegaMenuBranchPresentation> '
          'branchPresentations;'),
    );
    expect(menu, contains('widget.branchPresentations[branch.id]'));
    expect(menu, contains('widget.branchPresentations[node.id]'));
    expect(menu, contains('Image.network('));
    expect(menu, contains('LinearGradient('));
    expect(
      '$layout\n$menu',
      isNot(contains('website_megamenu_transmission_premium.png')),
    );
  });

  test('empty navigation exposes its canonical editor instead of fake links',
      () {
    final layout = File(
      'lib/public_store/widgets/public_store_layout.dart',
    ).readAsStringSync();

    expect(layout, contains('Configurar navegación'));
    expect(
      layout,
      contains('WebsiteWorkspacePanel.navigation'),
    );
    expect(layout, isNot(contains('Widget _buildNavLink(')));
  });
}
