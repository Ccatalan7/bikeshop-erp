part of '../website_editor_panel.dart';

/// The presentation a catalog section edits, as saved: from the page on the
/// canvas when it is that owner's, else from the registry the editor saves
/// into.
WebsiteCatalogPresentation _savedCatalogPresentation(
  BuildContext context,
  WebsiteEditModeProvider provider,
  String ownerId,
) {
  final canvas = provider.catalogCanvas;
  if (canvas != null && canvas.ownerId == ownerId) return canvas.saved;
  final root = WebsiteCatalogRootX.fromPresentationId(ownerId);
  final registry = context.read<WebsiteService>().catalogPresentationRegistry;
  return registry.forCategory(ownerId) ??
      (root == null
          ? WebsiteCatalogPresentation(categoryId: ownerId, slug: ownerId)
          : WebsiteCatalogPresentation.catalogRoot(root));
}

/// Where the catalog page's content is changed: a category's, in its
/// categories; a catalog's items, in its own list.
({String route, String label}) _catalogSourceFor(
  WebsiteCatalogCanvasContext? canvas,
) {
  if (canvas != null && canvas.collection) {
    return (
      route: '/inventory/categories',
      label: 'Abrir categorías en Inventario'
    );
  }
  if (canvas != null && canvas.noun == 'productos') {
    return (
      route: '/inventory/products',
      label: 'Abrir productos en Inventario'
    );
  }
  return (route: '/inventory/services', label: 'Abrir servicios en Inventario');
}

/// Leaves the editor for Inventario, through the same guard as any other
/// exit (save or discard first).
Future<void> _openCatalogSource(
  BuildContext context,
  WebsiteEditModeProvider provider,
) async {
  final route = _catalogSourceFor(provider.catalogCanvas).route;
  final decision = await WebsiteEditorNavigationGuard.authorize(
    context,
    intent: WebsiteEditorNavigationIntent.leaveEditor,
  );
  if (!decision.isAllowed || !context.mounted) return;
  if (!decision.commit()) return;
  provider.closeEditor();
  context.go(route);
}

/// «Lo que viene del catálogo»: what a section reads and where it changes.
class _CatalogSourceNote extends StatelessWidget {
  const _CatalogSourceNote({required this.provider, required this.text});

  final WebsiteEditModeProvider provider;
  final String text;

  @override
  Widget build(BuildContext context) {
    final accent = websiteEditorAccent(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.inventory_2_outlined, size: 16, color: accent),
              const SizedBox(width: 8),
              const Text(
                'Lo que viene del catálogo',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
              height: 1.4,
            ),
          ),
          TextButton.icon(
            key: const ValueKey('catalog-open-inventory'),
            onPressed: () => _openCatalogSource(context, provider),
            style: TextButton.styleFrom(
              foregroundColor: accent,
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
              minimumSize: const Size(0, 40),
            ),
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: Text(
              _catalogSourceFor(provider.catalogCanvas).label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The inspector of one catalog section: only what that section shows, in
/// groups that open, in the words of the page. Every control stages into the
/// editor's draft, saved by «Guardar» with the rest of the site.
class _CatalogSectionControls extends StatelessWidget {
  const _CatalogSectionControls({
    super.key,
    required this.provider,
    required this.target,
    this.showHeader = true,
  });

  final WebsiteEditModeProvider provider;
  final WebsiteCatalogSectionTarget target;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final saved = _savedCatalogPresentation(context, provider, target.ownerId);
    final value = provider.effectiveCatalogPresentation(saved);
    final canvas = provider.catalogCanvas?.ownerId == target.ownerId
        ? provider.catalogCanvas
        : null;
    final noun = canvas?.noun ?? 'servicios';
    void stage(WebsiteCatalogPresentation next) =>
        provider.stageCatalogPresentation(next, saved: saved);

    // A category's look (portada height, alignment and darkening, cards,
    // filters, trail, subcategories) is the category template's, shared by
    // every category page, unless this category has its own.
    final templateSaved = canvas != null && canvas.collection
        ? canvas.template ?? WebsiteCatalogPresentation.categoryTemplate()
        : null;
    final followsTemplate = templateSaved != null && !value.ownLook;
    final look = followsTemplate
        ? provider.effectiveCatalogPresentation(templateSaved)
        : value;
    void stageLook(WebsiteCatalogPresentation next) => followsTemplate
        ? provider.stageCatalogPresentation(next, saved: templateSaved)
        : stage(next);
    final lookScope = templateSaved == null
        ? null
        : _CategoryLookScope(
            categoryName: canvas!.rootLabel,
            ownLook: value.ownLook,
            categoryPageCount: canvas.categoryPageCount,
            ownLookCount: _ownLookCount(context, saved, value),
            onOwnLookChanged: (own) => stage(
              own
                  ? value.copyLookFrom(look).copyWith(ownLook: true)
                  : value.copyWith(ownLook: false),
            ),
          );

    final offersPriceList = canvas?.offersPriceList ?? true;
    final priceList = offersPriceList && value.isPriceList;
    final children = switch (target.section) {
      WebsiteCatalogSection.hero => canvas?.collection == true
          ? _collectionHero(
              context,
              value,
              canvas!,
              stage,
              look: look,
              stageLook: stageLook,
              lookScope: lookScope!,
            )
          : _hero(context, value, canvas, stage),
      WebsiteCatalogSection.plans => _plans(context, value, canvas, stage),
      WebsiteCatalogSection.list => priceList
          ? _list(context, canvas)
          : _gridList(
              context,
              look,
              canvas,
              stageLook,
              lookScope: lookScope,
            ),
      WebsiteCatalogSection.closing => _closing(context, value, stage),
      WebsiteCatalogSection.page => _page(
          context,
          value,
          stage,
          offersPriceList: offersPriceList,
          canvas: canvas,
        ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 16, 10),
            child: Row(
              children: [
                Tooltip(
                  message: 'Volver a las secciones',
                  child: InkWell(
                    key: const ValueKey('catalog-section-back'),
                    onTap: () => provider.selectBlock(null),
                    borderRadius: BorderRadius.circular(6),
                    child: ConstrainedBox(
                      constraints:
                          const BoxConstraints(minHeight: 40, minWidth: 40),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.arrow_back_rounded,
                              size: 16,
                              color: Colors.white60,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              canvas?.rootLabel ?? 'Servicios',
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: Colors.white38,
                  ),
                ),
                Expanded(
                  child: Text(
                    target.labelFor(noun: noun),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),
        ],
        Expanded(
          child: ListView(
            key: PageStorageKey<String>(
              'website_catalog_inspector_${target.selectionId}',
            ),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: children,
          ),
        ),
      ],
    );
  }

  List<Widget> _hero(
    BuildContext context,
    WebsiteCatalogPresentation value,
    WebsiteCatalogCanvasContext? canvas,
    ValueChanged<WebsiteCatalogPresentation> stage,
  ) {
    return [
      _CollapsibleSection(
        title: 'Textos',
        icon: Icons.short_text_rounded,
        children: [
          const _CatalogHelp(
            'También se escriben directo en la página: toca el texto.',
          ),
          _EditorTextField(
            key: const ValueKey('catalog-hero-eyebrow'),
            label: 'Etiqueta sobre el título',
            value: value.heroEyebrow,
            hint: 'Opcional, en mayúsculas',
            onChanged: (text) => stage(value.copyWith(heroEyebrow: text)),
          ),
          const SizedBox(height: 12),
          _EditorTextField(
            key: const ValueKey('catalog-hero-title'),
            label: 'Título',
            value: value.heroTitle,
            hint: canvas?.rootLabel ?? 'Servicios',
            onChanged: (text) => stage(value.copyWith(heroTitle: text)),
          ),
          const SizedBox(height: 12),
          _EditorTextField(
            key: const ValueKey('catalog-hero-intro'),
            label: 'Texto bajo el título',
            value: value.heroDescription,
            maxLines: 4,
            onChanged: (text) => stage(value.copyWith(heroDescription: text)),
          ),
        ],
      ),
      _CollapsibleSection(
        title: 'Botón',
        icon: Icons.smart_button_outlined,
        children: [
          _CatalogActionField(
            keyPrefix: 'catalog-hero-action',
            value: value.heroAction,
            help: 'El mismo botón sale en cada plan.',
            onChanged: (action) => stage(
              action == null
                  ? value.copyWith(clearHeroAction: true)
                  : value.copyWith(heroAction: action),
            ),
          ),
        ],
      ),
      _CollapsibleSection(
        title: 'Calificación de Google',
        icon: Icons.star_outline_rounded,
        initiallyExpanded: false,
        children: [
          _EditorToggle(
            label: 'Mostrarla en la portada',
            value: value.heroShowRating,
            onChanged: (show) => stage(value.copyWith(heroShowRating: show)),
          ),
          _CatalogHelp(
            canvas?.ratingSummary == null
                ? 'La tienda todavía no tiene calificación en Google; no se '
                    'muestra hasta que la tenga.'
                : '${canvas!.ratingSummary}. Se lee de Google, no se escribe.',
          ),
        ],
      ),
      _CollapsibleSection(
        title: 'Foto y color',
        icon: Icons.image_outlined,
        initiallyExpanded: false,
        children: [
          _ImagePicker(
            currentUrl: value.heroImageUrl.isEmpty ? null : value.heroImageUrl,
            onChanged: (url) => stage(value.copyWith(heroImageUrl: url.trim())),
          ),
          if (value.heroImageUrl.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => stage(value.copyWith(heroImageUrl: '')),
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('Quitar la foto'),
              ),
            ),
            const SizedBox(height: 6),
            _CatalogOverlaySlider(
              value: value.heroOverlay,
              onChanged: (overlay) =>
                  stage(value.copyWith(heroOverlay: overlay)),
            ),
          ] else
            const _CatalogHelp(
              'Sin foto, la portada usa el color principal de la marca.',
            ),
        ],
      ),
      _CollapsibleSection(
        title: 'Alineación',
        icon: Icons.format_align_left_rounded,
        initiallyExpanded: false,
        children: [
          VbSegmented<WebsiteCatalogHeroAlignment>(
            groupLabel: 'Alineación de la portada',
            value: value.heroAlignment,
            options: const [
              VbSegmentedOption(
                value: WebsiteCatalogHeroAlignment.left,
                label: 'Izquierda',
              ),
              VbSegmentedOption(
                value: WebsiteCatalogHeroAlignment.center,
                label: 'Centro',
              ),
            ],
            onChanged: (alignment) =>
                stage(value.copyWith(heroAlignment: alignment)),
          ),
        ],
      ),
    ];
  }

  /// A category's portada: its own texts and photo over the category's name,
  /// description and photo, which stay the category's; its look is the
  /// template's ([look], staged by [stageLook]) unless it has its own.
  List<Widget> _collectionHero(
    BuildContext context,
    WebsiteCatalogPresentation value,
    WebsiteCatalogCanvasContext canvas,
    ValueChanged<WebsiteCatalogPresentation> stage, {
    required WebsiteCatalogPresentation look,
    required ValueChanged<WebsiteCatalogPresentation> stageLook,
    required Widget lookScope,
  }) {
    return [
      _CollapsibleSection(
        title: 'Textos',
        icon: Icons.short_text_rounded,
        children: [
          const _CatalogHelp(
            'También se escriben directo en la página: toca el texto. Vacíos, '
            'la portada muestra el nombre y la descripción de la categoría.',
          ),
          _EditorTextField(
            key: const ValueKey('catalog-hero-eyebrow'),
            label: 'Etiqueta sobre el título',
            value: value.heroEyebrow,
            hint: 'Opcional, en mayúsculas',
            onChanged: (text) => stage(value.copyWith(heroEyebrow: text)),
          ),
          const SizedBox(height: 12),
          _EditorTextField(
            key: const ValueKey('catalog-hero-title'),
            label: 'Título',
            value: value.heroTitle,
            hint: canvas.rootLabel,
            onChanged: (text) => stage(value.copyWith(heroTitle: text)),
          ),
          const SizedBox(height: 12),
          _EditorTextField(
            key: const ValueKey('catalog-hero-intro'),
            label: 'Texto bajo el título',
            value: value.heroDescription,
            hint: 'Vacío usa la descripción de la categoría',
            maxLines: 4,
            onChanged: (text) => stage(value.copyWith(heroDescription: text)),
          ),
        ],
      ),
      _CollapsibleSection(
        title: 'Foto',
        icon: Icons.image_outlined,
        children: [
          _ImagePicker(
            currentUrl: value.heroImageUrl.isEmpty ? null : value.heroImageUrl,
            onChanged: (url) => stage(value.copyWith(heroImageUrl: url.trim())),
          ),
          if (value.heroImageUrl.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => stage(value.copyWith(heroImageUrl: '')),
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('Quitar la foto'),
              ),
            )
          else
            const _CatalogHelp(
              'Sin foto propia, usa la de la categoría; sin ninguna, el color '
              'de la marca.',
            ),
        ],
      ),
      _CollapsibleSection(
        title: 'Diseño',
        icon: Icons.dashboard_customize_outlined,
        children: [
          lookScope,
          const SizedBox(height: 14),
          _CatalogOverlaySlider(
            value: look.heroOverlay,
            onChanged: (overlay) =>
                stageLook(look.copyWith(heroOverlay: overlay)),
          ),
          const SizedBox(height: 12),
          VbSegmented<WebsiteCatalogHeroSize>(
            groupLabel: 'Alto de la portada',
            value: look.heroSize,
            options: [
              for (final size in WebsiteCatalogHeroSize.values)
                VbSegmentedOption(value: size, label: size.label),
            ],
            onChanged: (size) => stageLook(look.copyWith(heroSize: size)),
          ),
          const SizedBox(height: 12),
          VbSegmented<WebsiteCatalogHeroAlignment>(
            groupLabel: 'Alineación de la portada',
            value: look.heroAlignment,
            options: [
              for (final alignment in WebsiteCatalogHeroAlignment.values)
                VbSegmentedOption(value: alignment, label: alignment.label),
            ],
            onChanged: (alignment) =>
                stageLook(look.copyWith(heroAlignment: alignment)),
          ),
          const SizedBox(height: 12),
          _EditorToggle(
            key: const ValueKey('catalog-show-subcategories'),
            label: 'Subcategorías bajo la portada',
            value: look.showSubcategories,
            onChanged: (show) =>
                stageLook(look.copyWith(showSubcategories: show)),
          ),
          _CatalogHelp(
            canvas.groupCount == 0
                ? '${canvas.rootLabel} no tiene subcategorías con productos '
                    'publicados: no se muestra ninguna.'
                : '${canvas.groupCount} con productos publicados. Su nombre y '
                    'su orden son los de sus categorías.',
          ),
        ],
      ),
    ];
  }

  /// The product grid of a catalog page: how dense its cards are, which
  /// filters it offers, and (for a category) the trail above it. On a
  /// category, [value] is its look: the template's unless it has its own,
  /// as [lookScope] says.
  List<Widget> _gridList(
    BuildContext context,
    WebsiteCatalogPresentation value,
    WebsiteCatalogCanvasContext? canvas,
    ValueChanged<WebsiteCatalogPresentation> stage, {
    Widget? lookScope,
  }) {
    final noun = canvas?.noun ?? 'productos';
    void toggleFacet(WebsiteCatalogFacet facet, bool on) {
      final next = [
        for (final current in value.facets)
          if (current != facet) current,
        if (on) facet,
      ];
      stage(value.copyWith(facets: next));
    }

    return [
      if (lookScope != null) ...[lookScope, const SizedBox(height: 12)],
      _CollapsibleSection(
        title: 'Tarjetas',
        icon: Icons.grid_view_rounded,
        children: [
          VbSegmented<WebsiteCatalogGridDensity>(
            groupLabel: 'Tamaño de las tarjetas',
            value: value.gridDensity,
            options: [
              for (final density in WebsiteCatalogGridDensity.values)
                VbSegmentedOption(value: density, label: density.label),
            ],
            onChanged: (density) => stage(value.copyWith(gridDensity: density)),
          ),
          const SizedBox(height: 8),
          _CatalogHelp(value.gridDensity.description),
        ],
      ),
      _CollapsibleSection(
        title: 'Filtros',
        icon: Icons.filter_list_rounded,
        children: [
          // The ones shown, in their order (with arrows to change it), then
          // the ones that are off.
          for (var index = 0; index < value.facets.length; index++)
            Row(
              children: [
                Expanded(
                  child: _EditorToggle(
                    key: ValueKey('catalog-facet-${value.facets[index].name}'),
                    label: '${index + 1}. ${value.facets[index].label}',
                    value: true,
                    onChanged: (on) => toggleFacet(value.facets[index], on),
                  ),
                ),
                IconButton(
                  key: ValueKey('catalog-facet-up-${value.facets[index].name}'),
                  tooltip: 'Subir ${value.facets[index].label}',
                  onPressed: index == 0
                      ? null
                      : () => stage(
                            value.copyWith(
                              facets: [
                                ...value.facets.sublist(0, index - 1),
                                value.facets[index],
                                value.facets[index - 1],
                                ...value.facets.sublist(index + 1),
                              ],
                            ),
                          ),
                  icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                ),
              ],
            ),
          for (final facet in WebsiteCatalogFacet.values)
            if (!value.facets.contains(facet))
              _EditorToggle(
                key: ValueKey('catalog-facet-${facet.name}'),
                label: facet.label,
                value: false,
                onChanged: (on) => toggleFacet(facet, on),
              ),
          const _CatalogHelp(
            'Salen en la columna de la izquierda, en este orden. El buscador '
            'y los filtros de la ficha técnica salen siempre.',
          ),
        ],
      ),
      if (canvas?.collection == true)
        _CollapsibleSection(
          title: 'Ruta',
          icon: Icons.linear_scale_rounded,
          initiallyExpanded: false,
          children: [
            _EditorToggle(
              label: 'Mostrar la ruta de categorías sobre los $noun',
              value: value.showBreadcrumbs,
              onChanged: (show) => stage(value.copyWith(showBreadcrumbs: show)),
            ),
          ],
        ),
      _CatalogSourceNote(
        provider: provider,
        text: canvas == null
            ? 'Los $noun y sus fotos se cambian en Inventario.'
            : '${canvas.itemCount} $noun publicados. Sus nombres, precios y '
                'fotos se cambian en Inventario, no aquí.',
      ),
    ];
  }

  List<Widget> _plans(
    BuildContext context,
    WebsiteCatalogPresentation value,
    WebsiteCatalogCanvasContext? canvas,
    ValueChanged<WebsiteCatalogPresentation> stage,
  ) {
    final categories = canvas?.categories ?? const [];
    final selected = value.plansCategoryId;
    final known = categories.any((category) => category.id == selected);
    return [
      _CollapsibleSection(
        title: 'De dónde salen',
        icon: Icons.category_outlined,
        children: [
          _EditorDropdown(
            label: 'Categoría de los planes',
            value: selected,
            options: [
              ('', 'Sin planes'),
              for (final category in categories)
                (
                  category.id,
                  '${category.name} · ${category.itemCount} '
                      '${category.itemCount == 1 ? 'servicio' : 'servicios'}',
                ),
              if (selected.isNotEmpty && !known)
                (selected, 'Categoría sin servicios publicados'),
            ],
            onChanged: (id) => stage(value.copyWith(plansCategoryId: id)),
          ),
          const SizedBox(height: 8),
          const _CatalogHelp(
            'Cada servicio de esa categoría sale como una tarjeta con su '
            'precio y lo que incluye; el más completo va destacado. No se '
            'repiten en la lista de abajo.',
          ),
        ],
      ),
      _CatalogSourceNote(
        provider: provider,
        text: canvas == null || canvas.planCount == 0
            ? 'Sin planes publicados. El nombre, el precio y lo que incluye '
                'cada plan se escriben en el servicio.'
            : '${canvas.planCount} planes. Su nombre, precio y lo que '
                'incluyen se cambian en el servicio, no aquí.',
      ),
    ];
  }

  List<Widget> _list(
    BuildContext context,
    WebsiteCatalogCanvasContext? canvas,
  ) {
    final listed = canvas == null ? null : canvas.itemCount - canvas.planCount;
    return [
      const _CatalogHelp(
        'La lista muestra cada servicio publicado con su precio, agrupado '
        'por su categoría, con un buscador. El orden de los grupos es el de '
        'las categorías.',
      ),
      const SizedBox(height: 12),
      _CatalogSourceNote(
        provider: provider,
        text: listed == null
            ? 'Los servicios, sus precios y sus grupos se cambian en '
                'Inventario.'
            : '$listed servicios en ${canvas!.groupCount} grupos. Precios '
                'y nombres se cambian en el servicio; los grupos, en sus '
                'categorías.',
      ),
    ];
  }

  List<Widget> _closing(
    BuildContext context,
    WebsiteCatalogPresentation value,
    ValueChanged<WebsiteCatalogPresentation> stage,
  ) {
    return [
      _CollapsibleSection(
        title: 'Textos',
        icon: Icons.short_text_rounded,
        children: [
          if (!value.hasClosing)
            const _CatalogHelp(
              'Vacío, la página termina en la lista. Escribe un título para '
              'cerrar con una invitación.',
            ),
          _EditorTextField(
            key: const ValueKey('catalog-closing-title'),
            label: 'Título',
            value: value.closingTitle,
            onChanged: (text) => stage(value.copyWith(closingTitle: text)),
          ),
          const SizedBox(height: 12),
          _EditorTextField(
            key: const ValueKey('catalog-closing-text'),
            label: 'Texto',
            value: value.closingText,
            maxLines: 3,
            onChanged: (text) => stage(value.copyWith(closingText: text)),
          ),
        ],
      ),
      _CollapsibleSection(
        title: 'Botón',
        icon: Icons.smart_button_outlined,
        children: [
          _CatalogActionField(
            keyPrefix: 'catalog-closing-action',
            value: value.closingAction,
            onChanged: (action) => stage(
              action == null
                  ? value.copyWith(clearClosingAction: true)
                  : value.copyWith(closingAction: action),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _page(
    BuildContext context,
    WebsiteCatalogPresentation value,
    ValueChanged<WebsiteCatalogPresentation> stage, {
    required bool offersPriceList,
    WebsiteCatalogCanvasContext? canvas,
  }) {
    final collection = canvas?.collection == true;
    final saved = _savedCatalogPresentation(context, provider, target.ownerId);
    final losesSections = saved.isPriceList && !value.isPriceList;
    return [
      if (offersPriceList)
        _CollapsibleSection(
          title: 'Diseño',
          icon: Icons.dashboard_customize_outlined,
          children: [
            VbSegmented<WebsiteCatalogLayout>(
              groupLabel: 'Diseño de la página',
              value: value.layout,
              options: const [
                VbSegmentedOption(
                  value: WebsiteCatalogLayout.priceList,
                  label: 'Lista de precios',
                ),
                VbSegmentedOption(
                  value: WebsiteCatalogLayout.grid,
                  label: 'Cuadrícula',
                ),
              ],
              onChanged: (layout) => stage(value.copyWith(layout: layout)),
            ),
            const SizedBox(height: 8),
            _CatalogHelp(
              value.isPriceList
                  ? 'Portada, planes, todos los servicios con su precio y un '
                      'cierre. Para un taller con precios fijos.'
                  : 'Tarjetas con foto y filtros, como la tienda.',
            ),
            if (losesSections)
              const _CatalogHelp(
                'Como cuadrícula no hay portada, planes ni cierre: sus textos se '
                'borran al guardar.',
                warning: true,
              ),
          ],
        ),
      _CollapsibleSection(
        title: 'En Google',
        icon: Icons.travel_explore_rounded,
        children: [
          _EditorTextField(
            key: const ValueKey('catalog-seo-title'),
            label: 'Título en Google',
            value: value.seoTitle,
            hint: 'Vacío usa el título de la portada',
            onChanged: (text) => stage(value.copyWith(seoTitle: text)),
          ),
          const SizedBox(height: 12),
          _EditorTextField(
            key: const ValueKey('catalog-seo-description'),
            label: 'Descripción en Google',
            value: value.seoDescription,
            hint: 'Vacía usa el texto bajo el título',
            maxLines: 3,
            onChanged: (text) => stage(value.copyWith(seoDescription: text)),
          ),
          const SizedBox(height: 12),
          _EditorToggle(
            label: 'Que Google la muestre',
            value: value.allowIndexing,
            onChanged: (allow) => stage(value.copyWith(allowIndexing: allow)),
          ),
          const SizedBox(height: 12),
          Text(
            'Imagen al compartir',
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 6),
          _ImagePicker(
            currentUrl:
                value.socialImageUrl.isEmpty ? null : value.socialImageUrl,
            onChanged: (url) =>
                stage(value.copyWith(socialImageUrl: url.trim())),
          ),
          if (value.socialImageUrl.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => stage(value.copyWith(socialImageUrl: '')),
                icon: const Icon(Icons.close_rounded, size: 16),
                label: const Text('Quitar la imagen'),
              ),
            )
          else
            const _CatalogHelp(
              'Sin imagen propia, al compartir el enlace se usa la de la '
              'portada o la del sitio.',
            ),
        ],
      ),
      if (collection) ...[
        _CollapsibleSection(
          title: 'Dirección',
          icon: Icons.link_rounded,
          initiallyExpanded: false,
          children: [
            _CatalogAddressField(
              value: value,
              rootPath:
                  canvas!.noun == 'servicios' ? '/servicios' : '/productos',
              onChanged: stage,
            ),
          ],
        ),
        _CollapsibleSection(
          title: 'En el menú',
          icon: Icons.menu_open_rounded,
          initiallyExpanded: false,
          children: [
            const _CatalogHelp(
              'La foto del menú desplegable del encabezado, cuando la '
              'categoría tiene subcategorías.',
            ),
            _ImagePicker(
              currentUrl: value.megaMenuImageUrl.isEmpty
                  ? null
                  : value.megaMenuImageUrl,
              onChanged: (url) =>
                  stage(value.copyWith(megaMenuImageUrl: url.trim())),
            ),
            if (value.megaMenuImageUrl.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => stage(value.copyWith(megaMenuImageUrl: '')),
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Quitar la foto'),
                ),
              ),
              _CatalogSlider(
                label: 'Oscurecer la foto',
                value: value.megaMenuOverlay,
                max: 0.85,
                divisions: 17,
                percent: true,
                onChanged: (overlay) =>
                    stage(value.copyWith(megaMenuOverlay: overlay)),
              ),
              _CatalogSlider(
                label: 'Oscurecer la tarjeta',
                value: value.megaMenuCardOverlay,
                max: 0.65,
                divisions: 13,
                percent: true,
                onChanged: (overlay) =>
                    stage(value.copyWith(megaMenuCardOverlay: overlay)),
              ),
              _CatalogSlider(
                label: 'Ancho de la foto',
                value: value.megaMenuOverviewWidth,
                min: 300,
                max: 440,
                divisions: 14,
                onChanged: (width) =>
                    stage(value.copyWith(megaMenuOverviewWidth: width)),
              ),
              VbSegmented<WebsiteMegaMenuContentAlignment>(
                groupLabel: 'Dónde va el texto',
                value: value.megaMenuContentAlignment,
                options: [
                  for (final alignment
                      in WebsiteMegaMenuContentAlignment.values)
                    VbSegmentedOption(value: alignment, label: alignment.label),
                ],
                onChanged: (alignment) => stage(
                  value.copyWith(megaMenuContentAlignment: alignment),
                ),
              ),
            ],
          ],
        ),
        _CollapsibleSection(
          title: 'Restablecer',
          icon: Icons.restart_alt_rounded,
          initiallyExpanded: false,
          children: [
            const _CatalogHelp(
              'Quita los textos, las fotos y los ajustes propios de esta '
              'página; la dirección se mantiene. Se puede descartar antes de '
              'guardar.',
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('catalog-reset-presentation'),
                onPressed: () => stage(
                  WebsiteCatalogPresentation.fallback(
                    categoryId: value.ownerId,
                    categoryName: canvas.rootLabel,
                  ).copyWith(
                    slug: value.slug,
                    slugAliases: value.slugAliases,
                  ),
                ),
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('Volver a lo de por defecto'),
              ),
            ),
          ],
        ),
      ],
    ];
  }
}

/// The category's address: its current slug and the old ones that still lead
/// here. A slug another category claims is said before «Guardar» refuses it.
/// How many category pages have a look of their own, counting this
/// category's draft instead of what it saved.
int _ownLookCount(
  BuildContext context,
  WebsiteCatalogPresentation saved,
  WebsiteCatalogPresentation value,
) {
  final WebsiteCatalogPresentationRegistry registry;
  try {
    registry = context.read<WebsiteService>().catalogPresentationRegistry;
  } catch (_) {
    // A host without the site's service (a test, a preview): only this one.
    return value.ownLook ? 1 : 0;
  }
  final savedOwn = registry.forCategory(saved.ownerId)?.ownLook ?? false;
  return registry.categoriesWithOwnLook -
      (savedOwn ? 1 : 0) +
      (value.ownLook ? 1 : 0);
}

/// Above a category's look controls: whose look they change. Following the
/// template, every category page that follows it; with its own look, only
/// this one. The switch moves between the two without changing what shows.
class _CategoryLookScope extends StatelessWidget {
  const _CategoryLookScope({
    required this.categoryName,
    required this.ownLook,
    required this.categoryPageCount,
    required this.ownLookCount,
    required this.onOwnLookChanged,
  });

  final String categoryName;
  final bool ownLook;
  final int categoryPageCount;
  final int ownLookCount;
  final ValueChanged<bool> onOwnLookChanged;

  String get _title {
    if (ownLook) return 'Diseño propio de $categoryName';
    final following = (categoryPageCount - ownLookCount).clamp(1, 1 << 20);
    if (categoryPageCount <= 1) return 'Plantilla de las categorías';
    if (following >= categoryPageCount) {
      return 'Plantilla · cambia las $categoryPageCount categorías';
    }
    return 'Plantilla · cambia $following de las $categoryPageCount '
        'categorías';
  }

  @override
  Widget build(BuildContext context) {
    final accent = websiteEditorAccent(context);
    return Container(
      key: const ValueKey('catalog-look-scope'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: BoxDecoration(
        color: ownLook
            ? Colors.white.withValues(alpha: 0.05)
            : accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: ownLook
              ? Colors.white.withValues(alpha: 0.14)
              : accent.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ownLook ? Icons.brush_outlined : Icons.copy_all_rounded,
                size: 16,
                color: ownLook ? Colors.white70 : accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            ownLook
                ? 'Sólo esta categoría se ve así. Las demás siguen la '
                    'plantilla.'
                : 'La portada, las tarjetas y los filtros se ven igual en '
                    'todas las categorías: lo que cambies aquí cambia en '
                    'todas.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 4),
          _EditorToggle(
            key: const ValueKey('catalog-own-look'),
            label: 'Diseño propio para $categoryName',
            value: ownLook,
            onChanged: onOwnLookChanged,
          ),
        ],
      ),
    );
  }
}

class _CatalogAddressField extends StatefulWidget {
  const _CatalogAddressField({
    required this.value,
    required this.rootPath,
    required this.onChanged,
  });

  final WebsiteCatalogPresentation value;
  final String rootPath;
  final ValueChanged<WebsiteCatalogPresentation> onChanged;

  @override
  State<_CatalogAddressField> createState() => _CatalogAddressFieldState();
}

class _CatalogAddressFieldState extends State<_CatalogAddressField> {
  final TextEditingController _alias = TextEditingController();

  @override
  void dispose() {
    _alias.dispose();
    super.dispose();
  }

  /// The first of this page's addresses another category already answers
  /// to, if any.
  String? _claimedElsewhere(BuildContext context) {
    final value = widget.value;
    final claims = <String>{
      for (final raw in [value.slug, ...value.slugAliases])
        if (websiteCategorySlug(raw).isNotEmpty) websiteCategorySlug(raw),
    };
    if (claims.isEmpty) return null;
    try {
      final registry =
          context.read<WebsiteService>().catalogPresentationRegistry;
      for (final other in registry.byCategoryId.values) {
        if (!other.isCategoryPresentation || other.ownerId == value.ownerId) {
          continue;
        }
        final taken = claims.intersection({other.slug, ...other.slugAliases});
        if (taken.isNotEmpty) return taken.first;
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final theme = Theme.of(context);
    final taken = _claimedElsewhere(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EditorTextField(
          key: const ValueKey('catalog-slug'),
          label: 'Dirección',
          value: value.slug,
          hint: 'frenos',
          onChanged: (text) => widget.onChanged(value.copyWith(slug: text)),
        ),
        const SizedBox(height: 6),
        SelectableText(
          '${widget.rootPath}/categoria/${websiteCategorySlug(value.slug)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (taken != null)
          _CatalogHelp(
            '«$taken» ya es la dirección de otra categoría: así no se puede '
            'guardar.',
            warning: true,
          )
        else
          const _CatalogHelp(
            'Al guardar una dirección nueva, la anterior sigue llevando a esta '
            'página.',
          ),
        if (value.slugAliases.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Direcciones anteriores',
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final alias in value.slugAliases)
                InputChip(
                  label: Text(alias),
                  onDeleted: () => widget.onChanged(
                    value.copyWith(
                      slugAliases: [
                        for (final other in value.slugAliases)
                          if (other != alias) other,
                      ],
                    ),
                  ),
                  deleteButtonTooltipMessage: 'Dejar de usar $alias',
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('catalog-alias-new'),
                controller: _alias,
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Otra dirección que lleve aquí',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _addAlias(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Agregar la dirección',
              onPressed: _addAlias,
              icon: const Icon(Icons.add_rounded, size: 18),
            ),
          ],
        ),
      ],
    );
  }

  void _addAlias() {
    final raw = _alias.text.trim();
    if (raw.isEmpty) return;
    final value = widget.value;
    widget.onChanged(
      value.copyWith(slugAliases: [...value.slugAliases, raw]),
    );
    _alias.clear();
  }
}

/// One of the section's buttons: its text and where it goes, or none.
class _CatalogActionField extends StatelessWidget {
  const _CatalogActionField({
    required this.keyPrefix,
    required this.value,
    required this.onChanged,
    this.help,
  });

  final String keyPrefix;
  final WebsiteActionValue? value;
  final ValueChanged<WebsiteActionValue?> onChanged;
  final String? help;

  @override
  Widget build(BuildContext context) {
    final action = value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (help != null) _CatalogHelp(help!),
        WebsiteActionEditor(
          title: 'Texto y destino',
          value: action ?? const WebsiteActionValue(label: '', href: ''),
          keyPrefix: keyPrefix,
          showVariant: true,
          onChanged: onChanged,
        ),
        if (action != null && !action.isConfigured)
          const _CatalogHelp(
            'Sin destino el botón no se muestra.',
            warning: true,
          ),
        if (action != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: ValueKey('$keyPrefix-remove'),
              onPressed: () => onChanged(null),
              icon: const Icon(Icons.close_rounded, size: 16),
              label: const Text('Quitar el botón'),
            ),
          ),
      ],
    );
  }
}

/// A value dragged on a slider and staged once, when the drag ends.
class _CatalogSlider extends StatefulWidget {
  const _CatalogSlider({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    required this.max,
    required this.divisions,
    this.percent = false,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;

  /// Shown as a percentage of 1 (an overlay), else as pixels.
  final bool percent;
  final ValueChanged<double> onChanged;

  @override
  State<_CatalogSlider> createState() => _CatalogSliderState();
}

class _CatalogSliderState extends State<_CatalogSlider> {
  double? _dragging;

  String _format(double value) =>
      widget.percent ? '${(value * 100).round()} %' : '${value.round()} px';

  @override
  Widget build(BuildContext context) {
    final shown = (_dragging ?? widget.value).clamp(widget.min, widget.max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${widget.label} · ${_format(shown)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Slider(
          value: shown,
          min: widget.min,
          max: widget.max,
          divisions: widget.divisions,
          label: _format(shown),
          onChanged: (next) => setState(() => _dragging = next),
          onChangeEnd: (next) {
            setState(() => _dragging = null);
            widget.onChanged(next);
          },
        ),
      ],
    );
  }
}

class _CatalogOverlaySlider extends StatefulWidget {
  const _CatalogOverlaySlider({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<_CatalogOverlaySlider> createState() => _CatalogOverlaySliderState();
}

class _CatalogOverlaySliderState extends State<_CatalogOverlaySlider> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final shown = _dragging ?? widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Oscurecer la foto · ${(shown * 100).round()} %',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Slider(
          value: shown.clamp(0.0, 0.85),
          max: 0.85,
          divisions: 17,
          activeColor: websiteEditorAccent(context),
          label: '${(shown * 100).round()} %',
          onChanged: (next) => setState(() => _dragging = next),
          onChangeEnd: (next) {
            setState(() => _dragging = null);
            widget.onChanged(next);
          },
        ),
      ],
    );
  }
}

class _CatalogHelp extends StatelessWidget {
  const _CatalogHelp(this.text, {this.warning = false});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final warningTone =
        VinabikeThemeRoles.maybeOf(context)?.warning.accent ?? Colors.amber;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (warning) ...[
            Icon(Icons.warning_amber_rounded, size: 15, color: warningTone),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: warning
                    ? Color.lerp(warningTone, Colors.white, 0.45)
                    : Colors.white.withValues(alpha: 0.55),
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
