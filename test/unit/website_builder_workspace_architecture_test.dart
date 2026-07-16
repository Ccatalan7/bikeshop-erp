import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:vinabike_erp/modules/website/models/website_action.dart';
import 'package:vinabike_erp/modules/website/models/website_block_capabilities.dart';
import 'package:vinabike_erp/modules/website/models/website_destination.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_destination_audit_service.dart';
import 'package:vinabike_erp/modules/website/theme/website_theme_builder.dart';

void main() {
  test('repo instructions require the current website editor contract', () {
    final instructions =
        File('.github/copilot-instructions.md').readAsStringSync();
    final contract =
        File('docs/architecture/website-editor-contract.md').readAsStringSync();

    expect(instructions, contains('website-editor-contract.md'));
    expect(
        instructions,
        isNot(
            contains('CURRENT STATE: Only HOME page supports inline editing')));
    expect(contract,
        contains('Agent-created campaigns are real editor operations'));
    expect(contract, contains('Two connected control planes'));
    expect(
        contract, contains('Editor, Preview, and published-renderer parity'));
    expect(contract, contains('Selection and right-inspector contract'));
    expect(contract, contains('Inspector information architecture'));
    expect(contract, contains('Geometry, transforms, and clipping'));
    expect(contract, contains('Media-control contract'));
    expect(contract, contains('Page navigation inside the editor'));
    expect(contract, contains('CTA universality'));
    expect(contract, contains('Global theme universality'));
    expect(contract, contains('Interactive UI and UX verification'));
  });

  test('management workspaces preserve the active page draft', () {
    final provider = WebsiteEditModeProvider();
    provider.enterEditMode(
      [
        {
          'id': 'hero-1',
          'block_type': 'carousel',
          'block_data': {'title': 'Original'},
        },
      ],
      const {},
      pageId: 'page-1',
      pageSlug: 'inicio',
    );
    provider.updateBlockData('hero-1', 'title', 'Campaña');

    provider.openWorkspace(WebsiteWorkspaceMode.catalog);

    expect(provider.isEditMode, isTrue);
    expect(provider.isManagementWorkspace, isTrue);
    expect(provider.hasUnsavedChanges, isTrue);
    expect(provider.currentPageId, 'page-1');
    expect(
      (provider.blocks.single['block_data'] as Map)['title'],
      'Campaña',
    );

    provider.returnToPageEditor();
    expect(provider.isPageEditorWorkspace, isTrue);
    expect(provider.hasUnsavedChanges, isTrue);
  });

  test(
      'website top bar exposes task workspaces instead of duplicate publishers',
      () {
    final source = File('lib/public_store/widgets/public_store_layout.dart')
        .readAsStringSync();

    expect(source, contains("label: 'Editar página'"));
    expect(source, contains("label: 'Catálogo web'"));
    expect(source, contains("label: 'Estructura'"));
    expect(source, contains("label: 'Destinos y enlaces'"));
    expect(source, contains("label: 'Ajustes'"));
    expect(source, isNot(contains("label: 'Productos (publicar en web)'")));
    expect(source, isNot(contains("label: 'Visibilidad de productos'")));
    expect(source, contains('WebsiteCatalogSection.categories'));
  });

  test('persistent block inspector only belongs to page composition', () {
    final shell = File('lib/public_store/widgets/persistent_editor_shell.dart')
        .readAsStringSync();
    final layout = File('lib/public_store/widgets/public_store_layout.dart')
        .readAsStringSync();

    expect(shell, contains('editProvider.isPageEditorWorkspace'));
    expect(shell, contains('if (showEditorPanel)'));
    expect(layout, contains('!_isConfigHubOpen'));
    expect(layout, contains("'Borrador de página preservado'"));
  });

  test('editor catalog route performs its initial product load', () {
    final catalog = File('lib/public_store/pages/product_catalog_page.dart')
        .readAsStringSync();
    final branchStart = catalog.indexOf('if (editProvider.isEditMode) {');
    final branchEnd = catalog.indexOf('_searchDebounce?.cancel()', branchStart);
    final editorBranch = branchStart < 0 || branchEnd < 0
        ? null
        : catalog.substring(branchStart, branchEnd);

    expect(editorBranch, isNotNull);
    expect(editorBranch, contains('!_hasLoadedInitialProducts'));
    expect(editorBranch, contains('_loadProducts(resetPage: true)'));
    expect(editorBranch, contains('_applyLocalFilters()'));
    expect(
      catalog,
      contains(
        'final isServerPaged = '
        '!context.read<WebsiteEditModeProvider>().isEditMode;',
      ),
    );
    expect(
      catalog,
      contains('final canStartPageBeforeCategories = !editProvider.isEditMode'),
    );
  });

  test('category publication has one website-builder owner', () {
    final panel = File('lib/modules/website/widgets/website_editor_panel.dart')
        .readAsStringSync();
    final visibility =
        File('lib/modules/website/pages/product_website_visibility_page.dart')
            .readAsStringSync();
    final categoryForm =
        File('lib/modules/inventory/pages/category_form_page.dart')
            .readAsStringSync();

    expect(panel, isNot(contains('_WebsiteCategoriesEditor')));
    expect(panel, isNot(contains('Categorías visibles en la tienda')));
    expect(visibility, contains('WebsiteCatalogSection.categories'));
    expect(visibility, contains("'Categorías públicas'"));
    expect(
      categoryForm,
      contains('showOnWebsite: _existingCategory?.showOnWebsite ?? false'),
    );
  });

  test('category CTA picker surfaces catalog readiness', () {
    final linkEditor =
        File('lib/modules/website/widgets/website_link_value_editor.dart')
            .readAsStringSync();

    expect(linkEditor, contains('show_on_website'));
    expect(linkEditor, contains('markedWebProductCount'));
    expect(linkEditor, contains('Oculta del catálogo público'));
    expect(linkEditor, contains('Catálogo web > Categorías'));
    expect(linkEditor, isNot(contains("'Catálogo: Categoria #\$cat'")));
  });

  test('CTA destinations normalize to canonical entity routes', () {
    final category =
        WebsiteDestination.parse('/tienda/productos?categoria=cat-1');
    final page = WebsiteDestination.parse('/pagina/ofertas-invierno');
    final product = WebsiteDestination.parse('/productos/product-1');

    expect(category.kind, WebsiteDestinationKind.category);
    expect(category.reference, 'cat-1');
    expect(category.href, '/productos?category=cat-1');
    expect(page.kind, WebsiteDestinationKind.page);
    expect(page.reference, 'ofertas-invierno');
    expect(product.kind, WebsiteDestinationKind.product);
    expect(product.reference, 'product-1');
    expect(
      WebsiteDestination.routeForPage(
        slug: 'ofertas-invierno',
        isHome: false,
      ),
      '/pagina/ofertas-invierno',
    );
    expect(
      WebsiteDestination.routeForCatalog(
        categoryId: 'tires-id',
        searchQuery: 'Maxxis',
        productType: 'product',
      ),
      '/productos?category=tires-id&q=Maxxis&type=product',
    );
  });

  test('combined category and brand search round-trips in link editor', () {
    final destination = WebsiteDestination.parse(
      '/productos?category=tires-id&q=Maxxis&type=product',
    );
    final editor =
        File('lib/modules/website/widgets/website_link_value_editor.dart')
            .readAsStringSync();

    expect(destination.kind, WebsiteDestinationKind.category);
    expect(destination.reference, 'tires-id');
    expect(destination.href, contains('q=Maxxis'));
    expect(editor, contains('hasCompositeCatalogFilter'));
    expect(editor, contains('Catálogo filtrado: categoría +'));
  });

  test('destination audit finds nested links but ignores media URLs', () {
    final links = WebsiteDestinationAuditService.extractLinks({
      'imageUrl': 'https://cdn.example/hero.jpg',
      'slides': [
        {'ctaLink': '/pagina/ofertas'},
        {
          'actions': [
            {'label': 'Ver', 'to': '/productos?category=cat-1'},
          ],
        },
      ],
    });

    expect(links.map((link) => link.href), [
      '/pagina/ofertas',
      '/productos?category=cat-1',
    ]);
  });

  test('header and legacy content no longer compete with canonical owners', () {
    final panel = File('lib/modules/website/widgets/website_editor_panel.dart')
        .readAsStringSync();
    final layout = File('lib/public_store/widgets/public_store_layout.dart')
        .readAsStringSync();
    final router = File('lib/shared/routes/app_router.dart').readAsStringSync();

    expect(panel, isNot(contains('header_nav_links')));
    expect(panel, contains('Administrar navegación'));
    expect(layout, isNot(contains('ContentManagementPage')));
    expect(layout, contains('WebsiteDestinationManagementPage'));
    expect(router,
        contains("redirect: (context, state) => '/website/destinations'"));
  });

  test('link picker offers typed owners and configure-return handoffs', () {
    final linkEditor =
        File('lib/modules/website/widgets/website_link_value_editor.dart')
            .readAsStringSync();

    expect(linkEditor, contains('Categoría del catálogo'));
    expect(linkEditor, contains('Producto específico'));
    expect(linkEditor, contains('Página del sitio'));
    expect(linkEditor, contains('Configurar categoría'));
    expect(linkEditor, contains('Configurar producto'));
    expect(linkEditor, contains('WebsiteWorkspacePanel.pages'));
    expect(linkEditor, contains('WebsiteWorkspacePanel.destinations'));
  });

  test('catalog publication writes use canonical website service commands', () {
    final catalog =
        File('lib/modules/website/pages/product_website_visibility_page.dart')
            .readAsStringSync();
    final service = File('lib/modules/website/services/website_service.dart')
        .readAsStringSync();

    expect(catalog, contains('updateProductWebsiteVisibilityBatch'));
    expect(catalog, contains('replaceWebsiteCategoryVisibility'));
    expect(
        service, contains('Future<void> updateProductWebsiteVisibilityBatch'));
    expect(service, contains('Future<void> replaceWebsiteCategoryVisibility'));
  });

  test('visible CTA fields beat stale structured actions and clear cleanly',
      () {
    final visible = WebsiteActionValue.resolvePrimary(
      {
        'ctaText': 'Campaña nueva',
        'ctaLink': '/pagina/campana-nueva',
        'actions': [
          {
            'type': 'navigate',
            'label': 'Campaña vieja',
            'to': '/pagina/campana-vieja',
          },
        ],
      },
      labelKeys: const ['ctaText', 'buttonText'],
      hrefKeys: const ['ctaLink', 'buttonLink'],
    );
    final cleared = WebsiteActionValue.resolvePrimary(
      {
        'ctaText': 'Sin enlace',
        'ctaLink': '',
        'actions': [
          {'type': 'navigate', 'label': 'Vieja', 'to': '/vieja'},
        ],
      },
      labelKeys: const ['ctaText', 'buttonText'],
      hrefKeys: const ['ctaLink', 'buttonLink'],
    );
    final blankVisibleLabel = WebsiteActionValue.resolvePrimary(
      {
        'ctaText': '',
        'ctaLink': '/pagina/nueva',
        'actions': [
          {'type': 'navigate', 'label': 'Vieja', 'to': '/vieja'},
        ],
      },
      labelKeys: const ['ctaText', 'buttonText'],
      hrefKeys: const ['ctaLink', 'buttonLink'],
      defaultLabel: 'Ver más',
    );

    expect(visible?.label, 'Campaña nueva');
    expect(visible?.href, '/pagina/campana-nueva');
    expect(cleared, isNull);
    expect(blankVisibleLabel?.label, 'Ver más');
  });

  test('provider synchronizes CTA aliases and structured action atomically',
      () {
    final provider = WebsiteEditModeProvider();
    provider.enterEditMode(
      [
        {
          'id': 'hero-cta',
          'block_type': 'hero',
          'block_data': {
            'ctaText': 'Viejo',
            'ctaLink': '/viejo',
            'actions': [
              {'type': 'navigate', 'label': 'Oculto', 'to': '/oculto'},
            ],
          },
        },
      ],
      const {},
    );

    provider.updateBlockDataMultiple('hero-cta', {
      'ctaText': 'Oferta',
      'ctaLink': '/pagina/oferta',
    });
    final data = Map<String, dynamic>.from(
      provider.blocks.single['block_data'] as Map,
    );
    final action = Map<String, dynamic>.from((data['actions'] as List).first);

    expect(data['buttonText'], 'Oferta');
    expect(data['buttonLink'], '/pagina/oferta');
    expect(action['label'], 'Oferta');
    expect(action['to'], '/pagina/oferta');

    provider.updateBlockData('hero-cta', 'ctaLink', '');
    final cleared = provider.blocks.single['block_data'] as Map;
    expect(cleared['actions'], isEmpty);
  });

  test('every declared link-action block has the canonical action model', () {
    final actionProfiles = WebsiteBlockCapabilityRegistry.all.where(
      (profile) => profile.supports(WebsiteEditorCapability.linkAction),
    );

    for (final profile in actionProfiles) {
      expect(
        profile.hasGap(WebsiteEditorGap.missingActionModel),
        isFalse,
        reason: '${profile.type} still declares a per-block action gap',
      );
    }
  });

  test('global Theme button controls produce shared shape and size tokens', () {
    final theme = WebsiteThemeBuilder.build(
      base: ThemeData.light(),
      primaryColor: Colors.teal,
      accentColor: Colors.orange,
      backgroundColor: Colors.white,
      buttonStyle: 'pill',
      buttonSize: 'large',
    );
    final style = theme.elevatedButtonTheme.style!;
    final shape = style.shape!.resolve({}) as RoundedRectangleBorder;
    final minimumSize = style.minimumSize!.resolve({})!;

    expect(shape.borderRadius, BorderRadius.circular(999));
    expect(minimumSize.height, 52);
  });

  test('all storefront navigation CTAs use one renderer and one editor', () {
    final renderer =
        File('lib/modules/website/widgets/website_block_renderer.dart')
            .readAsStringSync();
    final canvas = File('lib/modules/website/widgets/canvas_block.dart')
        .readAsStringSync();
    final editor = File('lib/modules/website/widgets/website_editor_panel.dart')
        .readAsStringSync();
    final layout = File('lib/public_store/widgets/public_store_layout.dart')
        .readAsStringSync();

    expect(renderer, contains("import 'website_action_button.dart';"));
    expect(renderer, contains('WebsiteActionButton('));
    expect(canvas, contains('WebsiteActionButton('));
    expect(editor, contains('WebsiteActionEditor('));
    expect(editor, isNot(contains("'Próximamente'")));
    expect(layout, contains("getThemeSetting('button_style', 'rounded')"));
    expect(layout, contains("getThemeSetting('button_size', 'medium')"));
  });

  test('carousel campaigns reuse the universal Canvas layer system', () {
    final publicRenderer =
        File('lib/modules/website/widgets/website_block_renderer.dart')
            .readAsStringSync();
    final editableRenderer =
        File('lib/modules/website/widgets/editable_block_renderer.dart')
            .readAsStringSync();
    final panel = File('lib/modules/website/widgets/website_editor_panel.dart')
        .readAsStringSync();
    final canvas = File('lib/modules/website/widgets/canvas_block.dart')
        .readAsStringSync();

    expect(publicRenderer, contains('final usesComposition ='));
    expect(publicRenderer, contains('DeferredCanvasBlock('));
    expect(editableRenderer, contains('CanvasBlock('));
    expect(editableRenderer, contains("onSlideUpdated(index, 'elements'"));
    expect(editableRenderer, contains('InlineEditableImage('));
    expect(editableRenderer, contains("'Usar URL (avanzado)'"));
    expect(editableRenderer, contains("'Imagen del slide'"));
    expect(editableRenderer, contains('clipContentToBounds: true'));
    expect(publicRenderer, contains('clipContentToBounds: true'));
    expect(editableRenderer, contains('selectBlock(widget.blockId)'));
    expect(editableRenderer, contains('onBackgroundTap:'));
    expect(panel, contains("label: 'Diseño avanzado por capas'"));
    expect(panel, contains('elementsOnly: true'));
    expect(panel, contains("_addElement('shape')"));
    expect(canvas, contains("case 'shape':"));
    expect(canvas, contains('WebsiteActionButton('));
    expect(canvas, contains("'constrainElementsToSafeArea'"));
    expect(canvas, contains("'ÁREA SEGURA'"));
    expect(panel, contains("title: 'Posición y tamaño'"));
    expect(panel, contains("title: 'Reglas del lienzo'"));
    expect(panel, contains("label: 'Restringir capas al área segura'"));
    expect(panel, isNot(contains("'constrainToCanvas'")));
  });

  test('inspector uses task navigation and progressive control groups', () {
    final panel = File('lib/modules/website/widgets/website_editor_panel.dart')
        .readAsStringSync();

    expect(
        panel, contains('enum _InspectorSection { content, layout, style }'));
    expect(panel, contains("'Contenido'"));
    expect(panel, contains("'Diseño'"));
    expect(panel, contains("'Estilo'"));
    expect(panel, contains('_scrollController.jumpTo(0)'));
    expect(panel, contains("title: 'Comportamiento del carrusel'"));
    expect(panel, contains("title: 'Imagen y encuadre'"));
    expect(panel, contains("title: 'Contenido y origen'"));
    expect(panel, contains("title: 'Información visible'"));
    expect(panel, contains('class _SchemaRepeaterEditor'));
    expect(panel, contains('exactly one item at a time'));
    expect(panel, contains("title: 'Texto y datos'"));
    expect(panel, contains("title: 'Imagen y medios'"));
    expect(panel, contains("title: 'Acción y enlace'"));
    expect(panel, contains("title: 'Elementos relacionados'"));

    final editableRenderer =
        File('lib/modules/website/widgets/editable_block_renderer.dart')
            .readAsStringSync();
    expect(editableRenderer,
        contains('onPointerDown: (_) => editProvider.selectBlock'));
  });

  test('carousel slide selection is transient and shared with the canvas', () {
    final provider = WebsiteEditModeProvider();
    provider.enterEditMode(
      [
        {
          'id': 'carousel-1',
          'block_type': 'carousel',
          'block_data': {
            'slides': [
              {'title': 'Uno'},
              {'title': 'Dos'},
              {'title': 'Tres'},
            ],
          },
        },
      ],
      const {},
    );

    provider.selectCarouselSlide('carousel-1', 2, 3);
    expect(provider.carouselSlideSelection('carousel-1', 3), 2);
    expect(provider.hasUnsavedChanges, isFalse);

    provider.selectCarouselSlide('carousel-1', 99, 3);
    expect(provider.carouselSlideSelection('carousel-1', 3), 2);

    final editableRenderer =
        File('lib/modules/website/widgets/editable_block_renderer.dart')
            .readAsStringSync();
    expect(
        editableRenderer, contains('selectedSlideIndex: selectedSlideIndex'));
    expect(editableRenderer, contains('onSlideSelected: (index)'));
  });

  test('rotation is one persisted transform for every Canvas element type', () {
    final panel = File('lib/modules/website/widgets/website_editor_panel.dart')
        .readAsStringSync();
    final canvas = File('lib/modules/website/widgets/canvas_block.dart')
        .readAsStringSync();

    expect(RegExp("label: 'Rotación'").allMatches(panel).length, 1);
    expect(panel, contains("_updateElement(activeId!, {'rotation': v})"));
    expect(panel, contains('Restablecer rotación'));
    expect(canvas, contains("final rotationDegrees = (el['rotation']"));
    expect(canvas, contains('Transform.rotate('));
  });

  test('Canvas contextual editing is shared, typed, and renderer-backed', () {
    final canvas = File('lib/modules/website/widgets/canvas_block.dart')
        .readAsStringSync();
    final toolbar =
        File('lib/modules/website/widgets/canvas_block_toolbar.dart')
            .readAsStringSync();
    final factory =
        File('lib/modules/website/models/canvas_element_factory.dart')
            .readAsStringSync();
    final panel = File('lib/modules/website/widgets/website_editor_panel.dart')
        .readAsStringSync();
    final provider =
        File('lib/modules/website/providers/website_edit_mode_provider.dart')
            .readAsStringSync();

    expect(canvas, contains('for (final handle in _CanvasFrameHandle.values)'));
    expect(canvas, contains("ValueKey('rotation_handle_\$id')"));
    expect(canvas, contains("'RECORTE · ARRASTRA LA IMAGEN'"));
    expect(canvas, contains("'focalPointX'"));
    expect(canvas, contains('alignment: imageAlignment'));
    expect(canvas, contains('_handleCanvasKeyEvent'));
    expect(toolbar, contains('CanvasElementAlignment'));
    expect(toolbar, contains("tooltip: 'Girar 90°'"));
    expect(toolbar, contains("'Recortar y reencuadrar'"));
    expect(toolbar, contains('_CanvasToolbarView'));
    expect(toolbar, contains("ValueKey('toolbar_more')"));
    expect(toolbar, contains("ValueKey('toolbar_align_left')"));
    expect(toolbar, isNot(contains('PopupMenuButton')));
    expect(toolbar, isNot(contains('Tooltip(')));
    expect(panel, contains("label: 'Encuadre horizontal'"));
    expect(panel, contains("label: 'Bloquear ajustes directos'"));
    expect(factory, contains("'rotation': 0.0"));
    expect(factory, contains("'focalPointX': 0.5"));
    expect(panel, contains('createCanvasElement(id: id, type: type)'));
    expect(
        provider, contains('createCanvasElement(id: id, type: elementType)'));
  });
}
