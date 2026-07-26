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
    expect(editorBranch, contains('_loadProducts(resetPage: resetPage)'));
    expect(editorBranch, contains('_applyLocalFilters(resetPage: resetPage)'));
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
    expect(visibility, contains("'Categorías en navegación'"));
    expect(
      categoryForm,
      contains('showOnWebsite: _existingCategory?.showOnWebsite ?? false'),
    );
  });

  test('catalog workspace separates publication, filtering, and homepage order',
      () {
    final layout = File('lib/public_store/widgets/public_store_layout.dart')
        .readAsStringSync();
    final visibility =
        File('lib/modules/website/pages/product_website_visibility_page.dart')
            .readAsStringSync();
    final featured =
        File('lib/modules/website/pages/featured_products_page.dart')
            .readAsStringSync();
    final renderer =
        File('lib/modules/website/widgets/website_block_renderer.dart')
            .readAsStringSync();
    final productForm =
        File('lib/modules/inventory/pages/product_form_page.dart')
            .readAsStringSync();
    final availabilityLoader = File(
      'lib/modules/website/services/website_catalog_availability_loader.dart',
    ).readAsStringSync();
    final registry =
        File('docs/architecture/canonical-ui-surfaces.md').readAsStringSync();

    expect(layout, contains("label: Text('Portada')"));
    expect(layout, contains('fuente es “Destacados”'));
    expect(visibility, contains('bool _showAdvancedFilters = false'));
    expect(visibility, contains('bool _showPublicRules = false'));
    expect(visibility, contains("label: 'Reglas públicas'"));
    expect(visibility, contains("message: 'Publicar el resultado actual'"));
    expect(visibility, contains('_confirmAndRunResultAction'));
    expect(visibility, contains("title: 'Publicar resultado actual'"));
    expect(visibility, contains("title: 'Ocultar resultado actual'"));
    expect(
      visibility,
      contains("title: 'Dejar visible sólo este resultado'"),
    );
    expect(
      visibility,
      isNot(contains('value: _CatalogResultAction.publish')),
    );
    expect(visibility, isNot(contains("label: 'Acciones'")));
    expect(visibility, contains("'Marcado web'"));
    expect(visibility, contains("'Estado'"));
    expect(visibility, contains('_buildWebIntentSwitch'));
    expect(visibility, contains('_buildPublicStatusBadge'));
    expect(visibility, contains('isMarkedForWebsite'));
    expect(visibility, contains('OperationalStatusBadge('));
    expect(visibility, contains("label = 'Publicado'"));
    expect(visibility, contains("label = 'Bloqueado'"));
    expect(visibility, contains("label = 'Oculto'"));
    expect(visibility, contains("label = 'Inactivo'"));
    expect(
      visibility,
      isNot(contains(
        'Marcado web, pero una regla del catálogo público lo oculta.',
      )),
    );
    expect(visibility, isNot(contains('_buildWebVisibilityControl')));
    expect(visibility, contains('bool _showCatalogSummaryDetails = false'));
    expect(visibility, contains('_buildCatalogOverview'));
    expect(visibility, contains("label: 'Productos públicos'"));
    expect(visibility, contains("label: 'Categorías en navegación'"));
    expect(visibility, contains("label: 'Bloqueados por reglas'"));
    expect(visibility, contains("label: 'Limitar catálogo por categoría'"));
    expect(visibility, contains("'Configurar navegación'"));
    expect(visibility, contains("'\$visibleRows resultados'"));
    expect(visibility, contains("'Agregar resultados'"));
    expect(
      visibility,
      contains('esas categorías siguen apareciendo como filtros'),
    );
    expect(
      layout,
      contains('no limitan productos por sí solas'),
    );
    expect(visibility, contains('_visibleWebsiteCategorySummary'));
    expect(
      visibility,
      contains('WebsiteCatalogAvailabilityLoader(_supabase).load'),
    );
    expect(
      visibility,
      contains('WebsiteCatalogAvailabilityLoader.applyToRows'),
    );
    expect(
      visibility,
      isNot(contains('inventoryService.getProductsByIds')),
    );
    expect(
      availabilityLoader,
      contains("'get_product_available_quantities'"),
    );
    expect(
      availabilityLoader,
      contains('static const int maxBatchSize = 500'),
    );
    expect(visibility, contains('_openProductWebsiteEditor'));
    expect(
        visibility, contains("label: 'Editar página web de \${product.name}'"));
    expect(
      visibility,
      contains('initialSection: ProductFormSection.website'),
    );
    expect(
      visibility,
      isNot(contains("context.go('/inventory/products/")),
    );
    expect(productForm, contains('enum ProductFormSection'));
    expect(
      productForm,
      contains('widget.initialSection == ProductFormSection.website ? 1 : 0'),
    );
    expect(
      visibility,
      contains(
        'Solo filtra esta lista; no cambia las categorías públicas.',
      ),
    );
    expect(visibility, contains('showHeaderWhenEmbedded: false'));
    expect(featured, contains('showHeaderWhenEmbedded: false'));
    expect(featured, contains('bloques con fuente Destacados'));
    expect(renderer, contains("case 'featured':"));
    expect(renderer, contains('widget.featuredProducts'));
    expect(registry, contains('| Website catalog workspace |'));
    expect(registry, contains('`Categorías > Publicación` exclusively owns'));
    expect(
      registry,
      contains(
        'opens the canonical `ProductFormPage` in the host-appropriate '
        'context-preserving workspace',
      ),
    );
  });

  test('category CTA picker surfaces catalog readiness', () {
    final linkEditor =
        File('lib/modules/website/widgets/website_link_value_editor.dart')
            .readAsStringSync();

    expect(linkEditor, contains('show_on_website'));
    expect(linkEditor, contains('markedWebProductCount'));
    expect(linkEditor, contains('Oculta del catálogo público'));
    expect(
      linkEditor,
      contains('Catálogo web > Categorías > Publicación'),
    );
    expect(
      linkEditor,
      contains('WebsiteWorkspacePanel.catalogCategories'),
    );
    expect(linkEditor, contains("actionLabel: 'Configurar categoría'"));
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

  test('ERP Preview mounts canonical product detail routes', () {
    final appRouter =
        File('lib/shared/routes/app_router.dart').readAsStringSync();
    final storeLayout = File(
      'lib/public_store/widgets/public_store_layout.dart',
    ).readAsStringSync();
    final productDetail = File(
      'lib/public_store/pages/product_detail_page.dart',
    ).readAsStringSync();
    final cart = File(
      'lib/public_store/pages/cart_page.dart',
    ).readAsStringSync();
    final tenantResolver = File(
      'lib/public_store/utils/public_store_tenant_resolver.dart',
    ).readAsStringSync();

    expect(appRouter, contains("path: '/productos/:slug/:sku'"));
    expect(appRouter, contains("path: ':slug/:sku'"));
    expect(
      appRouter,
      contains("ProductDetailPage(productId: 'sku:\$sku')"),
    );
    expect(storeLayout, contains('normalizePublicCatalogRouteForRuntime'));
    expect(storeLayout, contains("const ValueKey('viewport_desktop')"));
    expect(storeLayout, isNot(contains('viewport_desktop_\$modeKey')));
    expect(storeLayout,
        isNot(contains('viewport_layout_app_\${mode.name}_\$modeKey')));
    expect(
      storeLayout,
      isNot(contains('viewport_layout_scroll_\${mode.name}_\$modeKey')),
    );
    expect(productDetail, contains('PublicStoreLayout.navigateToHref'));
    expect(cart, contains('PublicStoreLayout.navigateToHref'));
    expect(productDetail, contains('resolvePublicStoreTenantId(context)'));
    expect(
      tenantResolver,
      contains('isInEditorContext'),
    );
    expect(tenantResolver, contains("previewQuery = query['preview']"));
    expect(
      productDetail,
      contains("currentUri.path.startsWith('/tienda/')"),
    );
  });

  test('Edit and Preview keep routed Navigator ancestors stable', () {
    final storeLayout = File(
      'lib/public_store/widgets/public_store_layout.dart',
    ).readAsStringSync();

    expect(storeLayout, contains("const ValueKey('viewport_desktop')"));
    expect(storeLayout, contains("const ValueKey('scroll_solid')"));
    expect(
      storeLayout,
      contains("const ValueKey('scroll_transparent_notHome')"),
    );
    expect(storeLayout, contains("const ValueKey('sticky_scaffold')"));
    expect(storeLayout, contains('_isErpMountedStore()) {'));
    expect(storeLayout, isNot(contains('scrollViewMode')));
    expect(storeLayout, isNot(contains('viewport_desktop_\$modeKey')));
    expect(storeLayout, isNot(contains('sticky_scaffold_\$scrollViewMode')));
  });

  test('catalog route restoration preserves encoded pagination', () {
    final catalog = File(
      'lib/public_store/pages/product_catalog_page.dart',
    ).readAsStringSync();

    expect(
      catalog,
      contains('_handleFiltersChanged(resetPage: false);'),
    );
    expect(
      catalog,
      contains('unawaited(_loadProducts(resetPage: false));'),
    );
    expect(
      catalog,
      contains('void _applyLocalFilters({bool resetPage = true})'),
    );
  });

  test('public category membership and navigation use distinct owners', () {
    final catalog = File(
      'lib/public_store/pages/product_catalog_page.dart',
    ).readAsStringSync();

    expect(catalog, contains(".eq('is_active', true)"));
    expect(catalog, isNot(contains(".eq('show_on_website', true)")));
    expect(catalog, contains('final bool showOnWebsite;'));
    expect(catalog, contains('child.showOnWebsite &&'));
    expect(
      catalog,
      contains('_allCategoriesById[trimmed]?.showOnWebsite == true'),
    );
  });

  test('catalog transport failures never masquerade as zero results', () {
    final catalog = File(
      'lib/public_store/pages/product_catalog_page.dart',
    ).readAsStringSync();
    final inventory = File(
      'lib/public_store/services/public_inventory_service.dart',
    ).readAsStringSync();

    expect(catalog, contains('_buildCatalogLoadErrorState()'));
    expect(catalog, contains("label: const Text('Reintentar')"));
    expect(
      inventory,
      isNot(
        contains(
          'return const PublicProductPage(products: [], totalCount: 0);',
        ),
      ),
    );
    expect(inventory, contains('rethrow;'));
  });

  test('category counts consume the filtered facet projection', () {
    final catalog = File(
      'lib/public_store/pages/product_catalog_page.dart',
    ).readAsStringSync();
    final inventory = File(
      'lib/public_store/services/public_inventory_service.dart',
    ).readAsStringSync();
    final migration = File(
      'supabase/migrations/20260722200000_add_public_catalog_facets.sql',
    ).readAsStringSync();

    expect(inventory, contains("case 'category':"));
    expect(inventory, contains("case 'summary':"));
    expect(catalog, contains('facetSnapshot.directCategoryCounts'));
    expect(catalog, contains('facetSnapshot.filteredTotalCount'));
    expect(migration, contains("'category'::text as facet_key"));
    expect(migration, contains("'summary'::text as facet_key"));
    expect(migration, contains('p_category_ids := null'));
  });

  test('combined category and search round-trips in link editor', () {
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
    expect(editor, contains('_catalogSearchController.text = q;'));
    expect(editor, contains('_catalogType = switch (type.toLowerCase())'));
    expect(
      editor,
      contains('_catalogCategoryId = destination.kind'),
    );
    expect(editor, contains('return WebsiteDestination.routeForCatalog('));
  });

  test('category collection presentation is editor-owned and route-backed', () {
    final model = File(
      'lib/modules/website/models/website_catalog_presentation.dart',
    ).readAsStringSync();
    final workspace = File(
      'lib/modules/website/pages/product_website_visibility_page.dart',
    ).readAsStringSync();
    final service = File(
      'lib/modules/website/services/website_service.dart',
    ).readAsStringSync();
    final catalog = File(
      'lib/public_store/pages/product_catalog_page.dart',
    ).readAsStringSync();
    final publicInventory = File(
      'lib/public_store/services/public_inventory_service.dart',
    ).readAsStringSync();
    final sharedPresentation = File(
      'lib/public_store/widgets/catalog_collection_presentation.dart',
    ).readAsStringSync();
    final seoHelper =
        File('lib/shared/utils/seo_helper.dart').readAsStringSync();
    final seoHelperWeb =
        File('lib/shared/utils/seo_helper_web.dart').readAsStringSync();
    final storeLayout = File(
      'lib/public_store/widgets/public_store_layout.dart',
    ).readAsStringSync();
    final router = File('lib/shared/routes/app_router.dart').readAsStringSync();

    expect(model, contains('class WebsiteCatalogPresentation'));
    expect(model, contains('WebsiteCatalogGridDensity'));
    expect(model, contains('WebsiteCatalogFacet'));
    expect(model, contains('websiteProductsCatalogPresentationId'));
    expect(model, contains('websiteServicesCatalogPresentationId'));
    expect(model, contains('websiteCatalogGridMetrics('));
    expect(model, contains('final String seoTitle;'));
    expect(model, contains('final String seoDescription;'));
    expect(model, contains('final String socialImageUrl;'));
    expect(model, contains('final String megaMenuImageUrl;'));
    expect(model, contains('final double megaMenuOverlay;'));
    expect(model, contains('final double megaMenuCardOverlay;'));
    expect(model, contains('final double megaMenuOverviewWidth;'));
    expect(
      model,
      contains(
        'final WebsiteMegaMenuContentAlignment megaMenuContentAlignment;',
      ),
    );
    expect(model, contains("'mega_menu_image_url': megaMenuImageUrl"));
    expect(model, contains("'mega_menu_overlay': megaMenuOverlay"));
    expect(
      model,
      contains("'mega_menu_card_overlay': megaMenuCardOverlay"),
    );
    expect(
      model,
      contains("'mega_menu_overview_width': megaMenuOverviewWidth"),
    );
    expect(
      model,
      contains(
        "'mega_menu_content_alignment': megaMenuContentAlignment.storageValue",
      ),
    );
    expect(model, contains('megaMenuOverlay.clamp(0.0, 0.85)'));
    expect(model, contains('final bool allowIndexing;'));
    expect(model, contains('final List<String> slugAliases;'));
    expect(model, contains('WebsiteCatalogSlugResolution? resolveSlug('));
    expect(model, contains('WebsiteCatalogPresentation prepareForSave('));
    expect(model, contains('WebsiteCatalogSlugCollisionException'));
    expect(workspace, contains('WebsiteCatalogSection.categoryPresentation'));
    expect(workspace, contains("'Presentación del catálogo'"));
    expect(workspace, contains('WebsiteImagePickerField('));
    expect(workspace, contains('_hasUnsavedPresentationChanges'));
    expect(workspace, contains('_presentationRemovalPending'));
    expect(workspace, contains('_discardPresentationChanges'));
    expect(workspace, contains('_reloadPresentationFromPersistence'));
    expect(workspace, contains("'Cambios sin guardar'"));
    expect(workspace, contains("'Descartar'"));
    expect(workspace, contains("'Recargar'"));
    expect(workspace, contains('_buildPresentationSeoEditor'));
    expect(workspace, contains("'Título para buscadores'"));
    expect(workspace, contains("'Meta descripción'"));
    expect(workspace, contains("'Imagen al compartir'"));
    expect(workspace, contains("'Permitir indexación'"));
    expect(workspace, contains("'Megamenú'"));
    expect(workspace, contains('draft.megaMenuImageUrl'));
    expect(workspace, contains('draft.megaMenuOverlay'));
    expect(workspace, contains('draft.megaMenuCardOverlay'));
    expect(workspace, contains("'Oscurecimiento de la card"));
    expect(workspace, contains('draft.megaMenuOverviewWidth'));
    expect(workspace, contains('draft.megaMenuContentAlignment'));
    expect(workspace, contains("'Ancho de portada"));
    expect(workspace, contains("'Posición del contenido'"));
    expect(workspace, contains("'Quitar imagen del megamenú'"));
    expect(workspace, contains("'Rutas anteriores'"));
    expect(workspace, contains("'Agregar alias'"));
    expect(workspace, contains('_removePresentationAlias'));
    expect(workspace, contains('socialImageUrl: url.trim()'));
    expect(service, contains('saveCatalogPresentation('));
    expect(service, contains('removeCatalogPresentation('));
    expect(service, contains('await loadSettings();'));
    expect(service, contains('prepareForSave(normalized)'));
    expect(
      service,
      contains('_catalogPresentationRegistryWithFallbacks('),
    );
    expect(service, contains("select('id,name')"));
    expect(service, contains("eq('is_active', true)"));
    expect(catalog, contains('_buildCollectionIntroduction'));
    expect(catalog, contains('_presentationForCategory'));
    expect(catalog, contains('forCatalogRoot(root)'));
    expect(
      catalog,
      contains('CatalogCollectionPresentationHeader('),
    );
    expect(catalog, contains('websiteCatalogGridMetrics('));
    expect(catalog, contains('_scheduleCatalogSeo('));
    expect(catalog, contains('ownerAllowsIndexing:'));
    expect(catalog, contains('ownerIsPublished:'));
    expect(catalog, contains('hasEligibleContent:'));
    expect(catalog, contains('_replaceResolvedCategoryAlias('));
    expect(catalog, contains('categorySlugClaimCount(trimmed)'));
    expect(catalog, contains('return matches.length == 1 ? matches.single'));
    expect(
      workspace,
      contains('CatalogCollectionPresentationHeader('),
    );
    expect(workspace, contains('websiteCatalogGridMetrics('));
    expect(
      sharedPresentation,
      contains('class CatalogCollectionPresentationHeader'),
    );
    expect(seoHelper, contains('!ownerAllowsIndexing'));
    expect(seoHelper, contains('!ownerIsPublished'));
    expect(seoHelper, contains('!hasEligibleContent'));
    expect(
      seoHelperWeb,
      contains("_updateMetaProperty('og:image', imageUrl);"),
    );
    expect(
      seoHelperWeb,
      contains("_updateMeta('twitter:image', imageUrl);"),
    );
    expect(seoHelperWeb, contains('element?.remove();'));
    expect(storeLayout, contains('isCatalogSeoManagedPath(currentPath)'));
    expect(storeLayout, contains('isProductDetailSeoManagedPath(currentPath)'));
    expect(catalog, contains('_buildUnavailableCategoryState'));
    expect(catalog, contains('stock: _stockFilter'));
    expect(
      catalog,
      isNot(contains(
        'stock: _onlyInStock ? null : WebsiteCatalogStockFilter.all',
      )),
    );
    expect(catalog, contains('applyAvailabilityFacet:'));
    expect(publicInventory, contains('bool applyAvailabilityFacet = false'));
    expect(
      publicInventory,
      contains("'p_only_in_stock': applyAvailabilityFacet && onlyInStock"),
    );

    final categoryRoute =
        router.indexOf("path: '/productos/categoria/:category'");
    final productRoute = router.indexOf("path: '/productos/:slug/:sku'");
    expect(categoryRoute, greaterThanOrEqualTo(0));
    expect(productRoute, greaterThan(categoryRoute));
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

  test('global Theme button controls change the shared button tokens', () {
    final base = ThemeData.light();
    final pillLargeTheme = WebsiteThemeBuilder.build(
      base: base,
      primaryColor: base.colorScheme.primary,
      accentColor: base.colorScheme.secondary,
      backgroundColor: base.colorScheme.surface,
      buttonStyle: 'pill',
      buttonSize: 'large',
    );
    final sharpSmallTheme = WebsiteThemeBuilder.build(
      base: base,
      primaryColor: base.colorScheme.primary,
      accentColor: base.colorScheme.secondary,
      backgroundColor: base.colorScheme.surface,
      buttonStyle: 'sharp',
      buttonSize: 'small',
    );
    final pillLargeStyle = pillLargeTheme.elevatedButtonTheme.style!;
    final sharpSmallStyle = sharpSmallTheme.elevatedButtonTheme.style!;
    final pillLargeShape =
        pillLargeStyle.shape!.resolve({}) as RoundedRectangleBorder;
    final sharpSmallShape =
        sharpSmallStyle.shape!.resolve({}) as RoundedRectangleBorder;
    final pillLargeMinimumSize = pillLargeStyle.minimumSize!.resolve({})!;
    final sharpSmallMinimumSize = sharpSmallStyle.minimumSize!.resolve({})!;
    final pillLargeRadius =
        pillLargeShape.borderRadius.resolve(TextDirection.ltr);
    final sharpSmallRadius =
        sharpSmallShape.borderRadius.resolve(TextDirection.ltr);

    expect(
      pillLargeRadius.topLeft.x,
      greaterThan(sharpSmallRadius.topLeft.x),
    );
    expect(
      pillLargeMinimumSize.height,
      greaterThan(sharpSmallMinimumSize.height),
    );
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

  test('linked Canvas images can use a campaign-specific media cutout', () {
    final factory =
        File('lib/modules/website/models/canvas_element_factory.dart')
            .readAsStringSync();
    final canvas = File('lib/modules/website/widgets/canvas_block.dart')
        .readAsStringSync();
    final inspector =
        File('lib/modules/website/widgets/website_editor_panel.dart')
            .readAsStringSync();

    expect(factory, contains("'imageSource': 'manual'"));
    expect(canvas, contains("imageSource != 'manual'"));
    expect(inspector, contains('Imagen seleccionada / recorte'));
    expect(inspector, contains('conserva el vínculo comercial'));
  });

  test('background removal is shared by Canvas and schema image controls', () {
    final canvas = File('lib/modules/website/widgets/canvas_block.dart')
        .readAsStringSync();
    final toolbar =
        File('lib/modules/website/widgets/canvas_block_toolbar.dart')
            .readAsStringSync();
    final inspector =
        File('lib/modules/website/widgets/website_editor_panel.dart')
            .readAsStringSync();
    final dialog = File(
      'lib/modules/website/widgets/website_background_removal_dialog.dart',
    ).readAsStringSync();

    expect(toolbar, contains("ValueKey('toolbar_remove_background')"));
    expect(canvas, contains('showWebsiteBackgroundRemovalDialog('));
    expect(canvas, contains("'backgroundRemovalOriginalUrl'"));
    expect(inspector, contains('showWebsiteBackgroundRemovalDialog('));
    expect(dialog, contains("'Quitar fondo'"));
    expect(dialog, contains("'Aplicar versión'"));
    expect(dialog, contains("'Usar modo inteligente'"));

    final mediaService = File(
      'lib/modules/website/services/website_media_service.dart',
    ).readAsStringSync();
    expect(mediaService, contains("'website-optimize-image'"));
    expect(mediaService, contains('WebsiteImageUploadProcessor.prepare'));
    final backgroundService = File(
      'lib/modules/website/services/website_background_removal_service.dart',
    ).readAsStringSync();
    expect(
      backgroundService,
      contains("operation: 'background-removal-local'"),
    );

    final optimizer = File(
      'supabase/functions/website-optimize-image/index.ts',
    ).readAsStringSync();
    expect(optimizer, contains('MagickFormat.WebP'));
    expect(optimizer, contains('website/media/sources/'));
    expect(optimizer, contains('thumbnail_url'));

    expect(inspector, isNot(contains('ImagePicker()')));
    expect(inspector, isNot(contains("'brand-logos/'")));
    expect(inspector, isNot(contains("'website-images/'")));
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
