part of '../website_editor_panel.dart';

/// The «Secciones» rail at the left of the canvas (approved proposal,
/// 2026-10-06): the page in view, top to bottom, with the site's header and
/// footer around it. Mounted by the shell only where it fits
/// ([WebsiteEditorChromeGeometry.sectionsRailWidthFor]); below that the same
/// list is the inspector's «nothing selected» state.
class WebsiteEditorSectionsRail extends StatelessWidget {
  const WebsiteEditorSectionsRail({super.key});

  static const Key railKey = ValueKey('website-editor-sections-rail');

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<WebsiteEditModeProvider>();
    final theme = Theme.of(context);
    return DecoratedBox(
      key: railKey,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(right: BorderSide(color: theme.dividerColor)),
      ),
      child: WebsiteEditorControlDensityScope.resolved(
        context: context,
        child: _SectionsOutline(provider: provider),
      ),
    );
  }
}

/// One owner for the list of what the page in view is made of.
///
/// It lists only the page on the canvas: a block page while it owns the open
/// document ([WebsiteEditModeProvider.hasBlockCanvas]), a catalog page by its
/// own sections, and otherwise only the header and the footer — never the
/// blocks of a document the previous page left open.
class _SectionsOutline extends StatelessWidget {
  const _SectionsOutline({required this.provider});

  final WebsiteEditModeProvider provider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roles = VinabikeThemeRoles.maybeOf(context);
    final catalog = provider.catalogCanvas;
    final product = catalog == null ? provider.productCanvas : null;
    final blocks = catalog == null && product == null && provider.hasBlockCanvas
        ? provider.blocks
        : null;
    final onAddSection =
        WebsiteEditorCommandScope.maybeOf(context)?.onAddSection;
    final selected = provider.selectedBlockId;
    final pageName = _outlinePageName(context, provider);

    Widget chromeRow(WebsiteEditorChromeTarget target) => _SectionRow(
          key: ValueKey('website-sections-row-${target.selectionId}'),
          icon: target == WebsiteEditorChromeTarget.header
              ? Icons.web_asset_rounded
              : Icons.call_to_action_outlined,
          label: target.label,
          note: 'todo el sitio',
          selected: selected == target.selectionId,
          onTap: () => provider.selectBlock(target.selectionId),
        );

    const gutter = EdgeInsets.symmetric(horizontal: 12);
    return CustomScrollView(
      key: const PageStorageKey<String>('website_sections_outline'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Secciones',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (pageName != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    pageName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: gutter,
          sliver: SliverToBoxAdapter(
            child: chromeRow(WebsiteEditorChromeTarget.header),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          sliver: SliverToBoxAdapter(
            child: Text(
              'EN ESTA PÁGINA',
              style: theme.textTheme.labelSmall?.copyWith(
                color: roles?.faintForeground ??
                    theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        if (catalog != null)
          SliverPadding(
            padding: gutter,
            sliver: SliverList.list(
              children: _catalogOutlineRows(provider, catalog, selected),
            ),
          )
        else if (product != null)
          SliverPadding(
            padding: gutter,
            sliver: SliverList.list(
              children: _productOutlineRows(provider, product, selected),
            ),
          )
        else if (blocks != null && blocks.isNotEmpty)
          SliverPadding(
            padding: gutter,
            sliver: _BlockSectionsList(provider: provider, blocks: blocks),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Text(
                blocks != null
                    ? 'La página está vacía. Agrega su primera sección.'
                    : 'Esta página la arma la tienda con sus datos: no tiene '
                        'secciones propias. Aquí se editan el encabezado y el '
                        'pie de página.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ),
          ),
        if (blocks != null && onAddSection != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
            sliver: SliverToBoxAdapter(
              child: Builder(
                builder: (buttonContext) => OutlinedButton.icon(
                  key: const ValueKey('website-sections-add'),
                  onPressed: () => onAddSection(buttonContext),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(40),
                    foregroundColor: theme.colorScheme.primary,
                    side: BorderSide(
                      color: roles?.accentBorder ?? theme.colorScheme.primary,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Agregar sección'),
                ),
              ),
            ),
          ),
        if (blocks != null && provider.hasSectionClipboard)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
            sliver: SliverToBoxAdapter(
              child: TextButton.icon(
                key: const ValueKey('website-sections-paste'),
                onPressed: () => provider.pasteSectionFromClipboard(),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(36),
                  alignment: Alignment.centerLeft,
                ),
                icon: const Icon(Icons.content_paste_rounded, size: 18),
                label: Text(
                  'Pegar «${provider.sectionClipboardLabel ?? 'sección'}»',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
          sliver: SliverToBoxAdapter(
            child: chromeRow(WebsiteEditorChromeTarget.footer),
          ),
        ),
        if (catalog != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
            sliver: SliverList.list(
              children: _catalogOutlineTail(provider, catalog, selected),
            ),
          ),
        if (product != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
            sliver: SliverToBoxAdapter(
              child: _ProductSourceNote(provider: provider, canvas: product),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }
}

/// The page's name under «Secciones»: the catalog root, Inicio, or the CMS
/// page's own title. Null on a page with no sections of its own.
String? _outlinePageName(
  BuildContext context,
  WebsiteEditModeProvider provider,
) {
  if (provider.catalogCanvas case final canvas?) return canvas.rootLabel;
  if (provider.productCanvas != null) return 'Ficha de producto';
  if (!provider.hasBlockCanvas) return null;
  if (provider.isEditingHomePage) return 'Inicio';
  final pageId = provider.currentPageId;
  try {
    for (final page in context.read<WebsiteService>().pages) {
      if (page.id == pageId && page.title.trim().isNotEmpty) {
        return page.title.trim();
      }
    }
  } catch (_) {}
  return null;
}

/// The page's blocks, in page order, dragged by their handle.
class _BlockSectionsList extends StatelessWidget {
  const _BlockSectionsList({required this.provider, required this.blocks});

  final WebsiteEditModeProvider provider;
  final List<Map<String, dynamic>> blocks;

  @override
  Widget build(BuildContext context) {
    // The order this list was drawn from. A drop is applied only if the page
    // still has exactly this order: an undo or another edit that landed while
    // the row was in the air leaves the page as it is.
    final drawnIds = [
      for (final block in blocks) block['id']?.toString() ?? '',
    ];
    final selected = provider.selectedBlockId;
    return SliverReorderableList(
      itemCount: blocks.length,
      onReorder: (oldIndex, newIndex) {
        final liveIds = [
          for (final block in provider.blocks) block['id']?.toString() ?? '',
        ];
        if (!listEquals(liveIds, drawnIds)) return;
        provider.reorderBlocks(oldIndex, newIndex);
      },
      proxyDecorator: (child, index, animation) => Material(
        color: Colors.transparent,
        elevation: 6,
        shadowColor: VinabikeThemeRoles.maybeOf(context)?.shadow,
        borderRadius: BorderRadius.circular(8),
        child: child,
      ),
      itemBuilder: (context, index) {
        final block = blocks[index];
        final id = drawnIds[index];
        final type = (block['block_type'] ?? block['type'] ?? '').toString();
        final hidden = block['is_visible'] == false;
        final label = _outlineBlockLabel(type);
        final subtitle = _outlineBlockSubtitle(block, label: label);
        return _SectionRow(
          key: ValueKey('website-sections-row-$id'),
          icon: _outlineBlockIcon(type),
          label: label,
          subtitle: subtitle,
          note: hidden ? 'oculta' : null,
          noteTone: hidden ? _SectionNoteTone.warning : _SectionNoteTone.plain,
          hidden: hidden,
          selected: selected == id,
          semanticsLabel: [
            'Sección $label',
            if (subtitle != null) subtitle,
            if (hidden) 'oculta en la página',
          ].join(', '),
          onTap: () => provider.selectBlockFromOutline(id),
          leading: ReorderableDragStartListener(
            index: index,
            child: Tooltip(
              message: 'Arrastra para mover',
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                child: SizedBox(
                  key: ValueKey('website-sections-drag-$id'),
                  width: _sectionTarget(context, 20),
                  height: _sectionTarget(context, 36),
                  child: const Icon(Icons.drag_indicator_rounded, size: 18),
                ),
              ),
            ),
          ),
          visibilityAction: _SectionVisibilityAction(
            hidden: hidden,
            onToggle: () => provider.toggleBlockVisibility(id),
            buttonKey: ValueKey('website-sections-visibility-$id'),
          ),
          menu: _SectionBlockMenu(
            provider: provider,
            blockId: id,
            label: label,
            hidden: hidden,
            canMoveUp: index > 0,
            canMoveDown: index < blocks.length - 1,
          ),
        );
      },
    );
  }
}

/// The catalog page's own sections, in page order.
List<Widget> _catalogOutlineRows(
  WebsiteEditModeProvider provider,
  WebsiteCatalogCanvasContext canvas,
  String? selected,
) {
  final shown = provider.effectiveCatalogPresentation(canvas.saved);
  WebsiteCatalogSectionTarget target(WebsiteCatalogSection section) =>
      WebsiteCatalogSectionTarget(canvas.ownerId, section);
  Widget row(
    WebsiteCatalogSection section, {
    required IconData icon,
    required String label,
    String? note,
    bool fromCatalog = false,
  }) {
    final id = target(section).selectionId;
    return _SectionRow(
      key: ValueKey('website-sections-row-$id'),
      icon: icon,
      label: label,
      note: note,
      noteTone: fromCatalog ? _SectionNoteTone.catalog : _SectionNoteTone.plain,
      selected: selected == id,
      onTap: () => provider.selectBlock(id),
    );
  }

  if (!(canvas.offersPriceList && shown.isPriceList)) {
    return [
      if (canvas.collection)
        row(
          WebsiteCatalogSection.hero,
          icon: Icons.title_rounded,
          label: 'Portada',
          note: shown.heroTitle.trim().isEmpty ? 'con su nombre' : null,
        ),
      row(
        WebsiteCatalogSection.list,
        icon: Icons.grid_view_rounded,
        label: 'Todos los ${canvas.noun}',
        note: 'del catálogo · ${canvas.itemCount}',
        fromCatalog: true,
      ),
    ];
  }
  return [
    row(
      WebsiteCatalogSection.hero,
      icon: Icons.title_rounded,
      label: 'Portada',
    ),
    row(
      WebsiteCatalogSection.plans,
      icon: Icons.view_week_outlined,
      label: 'Planes',
      note: canvas.planCount == 0
          ? 'sin planes'
          : 'del catálogo · ${canvas.planCount}',
      fromCatalog: canvas.planCount > 0,
    ),
    row(
      WebsiteCatalogSection.list,
      icon: Icons.format_list_bulleted_rounded,
      label: 'Todos los ${canvas.noun}',
      note: 'del catálogo · ${canvas.itemCount - canvas.planCount}',
      fromCatalog: true,
    ),
    row(
      WebsiteCatalogSection.closing,
      icon: Icons.call_to_action_outlined,
      label: 'Cierre',
      note: shown.hasClosing ? null : 'vacío',
    ),
  ];
}

/// The product page's sections, in page order: the template every product
/// page draws.
List<Widget> _productOutlineRows(
  WebsiteEditModeProvider provider,
  WebsiteProductCanvasContext canvas,
  String? selected,
) {
  final template = provider.effectiveProductPageTemplate;
  Widget row(
    WebsiteProductPageSection section, {
    required IconData icon,
    String? note,
    bool hidden = false,
  }) {
    final id = WebsiteProductSectionTarget(section).selectionId;
    return _SectionRow(
      key: ValueKey('website-sections-row-$id'),
      icon: icon,
      label: section.label,
      note: note,
      noteTone: hidden ? _SectionNoteTone.warning : _SectionNoteTone.plain,
      hidden: hidden,
      selected: selected == id,
      onTap: () => provider.selectBlock(id),
    );
  }

  return [
    row(
      WebsiteProductPageSection.buy,
      icon: Icons.shopping_bag_outlined,
      note: 'plantilla de todas',
    ),
    row(
      WebsiteProductPageSection.sheet,
      icon: Icons.list_alt_rounded,
      note: canvas.technical ? 'con datos' : 'sin datos técnicos',
    ),
    row(
      WebsiteProductPageSection.related,
      icon: Icons.grid_view_rounded,
      note: template.showRelated ? null : 'oculta',
      hidden: !template.showRelated,
    ),
  ];
}

/// The catalog page's design and Google texts, and where its content changes.
List<Widget> _catalogOutlineTail(
  WebsiteEditModeProvider provider,
  WebsiteCatalogCanvasContext canvas,
  String? selected,
) {
  final shown = provider.effectiveCatalogPresentation(canvas.saved);
  final priceList = canvas.offersPriceList && shown.isPriceList;
  final pageId =
      WebsiteCatalogSectionTarget(canvas.ownerId, WebsiteCatalogSection.page)
          .selectionId;
  final singular = canvas.noun == 'servicios' ? 'servicio' : 'producto';
  final source = priceList
      ? '${canvas.itemCount} ${canvas.noun} en ${canvas.groupCount} grupos. '
          'Precios, nombres y lo que incluye cada plan se cambian en el '
          'servicio, no aquí.'
      : canvas.collection
          ? '${canvas.itemCount} ${canvas.noun} en ${canvas.rootLabel}'
              '${canvas.groupCount > 0 ? ' y sus ${canvas.groupCount} subcategorías' : ''}. '
              'El nombre, la descripción y la foto de la categoría, y sus '
              '${canvas.noun}, se cambian en Inventario; aquí, cómo se ven.'
          : '${canvas.itemCount} ${canvas.noun}. Precios, nombres y fotos se '
              'cambian en el $singular, no aquí.';
  return [
    _SectionRow(
      key: const ValueKey('website-sections-row-catalog-design'),
      icon: canvas.offersPriceList
          ? Icons.tune_rounded
          : Icons.travel_explore_rounded,
      label: canvas.offersPriceList ? 'Diseño y Google' : 'En Google',
      note: canvas.offersPriceList
          ? (priceList ? 'lista de precios' : 'cuadrícula')
          : (shown.allowIndexing ? 'se muestra' : 'oculta'),
      selected: selected == pageId,
      onTap: () => provider.selectBlock(pageId),
    ),
    const SizedBox(height: 12),
    _CatalogSourceNote(provider: provider, text: source),
  ];
}

enum _SectionNoteTone { plain, catalog, warning }

/// One row of the list: a section of the page, or the site's header/footer.
class _SectionRow extends StatefulWidget {
  const _SectionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.note,
    this.noteTone = _SectionNoteTone.plain,
    this.selected = false,
    this.hidden = false,
    this.semanticsLabel,
    this.leading,
    this.visibilityAction,
    this.menu,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final String? note;
  final _SectionNoteTone noteTone;
  final bool selected;
  final bool hidden;
  final String? semanticsLabel;
  final VoidCallback onTap;
  final Widget? leading;
  final _SectionVisibilityAction? visibilityAction;
  final Widget? menu;

  @override
  State<_SectionRow> createState() => _SectionRowState();
}

class _SectionRowState extends State<_SectionRow> {
  bool _hovering = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.maybeOf(context);
    final ink = widget.hidden
        ? (roles?.faintForeground ?? scheme.onSurfaceVariant)
        : scheme.onSurface;
    final noteColor = switch (widget.noteTone) {
      _SectionNoteTone.catalog => scheme.primary,
      _SectionNoteTone.warning => roles?.warning.accent ?? scheme.tertiary,
      _SectionNoteTone.plain => scheme.onSurfaceVariant,
    };
    // The quick «Ocultar» shows where it is wanted — on the row under the
    // pointer, the chosen one, or a hidden one waiting to be shown again —
    // and leaves the name its room everywhere else. The menu carries it too.
    final showsVisibility = widget.visibilityAction != null &&
        (widget.hidden || widget.selected || _hovering || _focused);
    final background = widget.selected
        ? (roles?.selectionContainer ?? scheme.primaryContainer)
        : _hovering
            ? scheme.onSurface.withValues(alpha: 0.05)
            : Colors.transparent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        selected: widget.selected,
        button: true,
        label: widget.semanticsLabel ?? widget.label,
        excludeSemantics: false,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: Material(
            color: background,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: widget.selected
                    ? (roles?.accentBorder ?? scheme.primary)
                    : Colors.transparent,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              onFocusChange: (value) => setState(() => _focused = value),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: _sectionTarget(context, 44),
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    widget.leading == null ? 10 : 2,
                    4,
                    4,
                    4,
                  ),
                  child: Row(
                    children: [
                      if (widget.leading case final leading?)
                        IconTheme.merge(
                          data: IconThemeData(
                            color: roles?.faintForeground ??
                                scheme.onSurfaceVariant,
                          ),
                          child: ExcludeSemantics(child: leading),
                        ),
                      if (widget.leading != null) const SizedBox(width: 2),
                      Icon(
                        widget.icon,
                        size: 18,
                        color: widget.selected ? scheme.primary : ink,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ExcludeSemantics(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: ink,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              // The second line: what the row is about
                              // («todo el sitio», «del catálogo · 59», «oculta»)
                              // and the block's own words. Under the name, so
                              // the name keeps the whole width at 264 px.
                              if (widget.note != null ||
                                  widget.subtitle != null)
                                Text.rich(
                                  TextSpan(
                                    children: [
                                      if (widget.note case final note?)
                                        TextSpan(
                                          text: note,
                                          style: TextStyle(
                                            color: noteColor,
                                            fontWeight: widget.noteTone ==
                                                    _SectionNoteTone.plain
                                                ? FontWeight.w400
                                                : FontWeight.w600,
                                          ),
                                        ),
                                      if (widget.note != null &&
                                          widget.subtitle != null)
                                        const TextSpan(text: ' · '),
                                      if (widget.subtitle case final subtitle?)
                                        TextSpan(text: subtitle),
                                    ],
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 11.5,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (showsVisibility) widget.visibilityAction!,
                      if (widget.menu case final menu?) menu,
                      if (widget.menu == null && widget.leading == null)
                        Padding(
                          padding: const EdgeInsets.only(left: 2, right: 4),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: roles?.faintForeground ??
                                scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionVisibilityAction extends StatelessWidget {
  const _SectionVisibilityAction({
    required this.hidden,
    required this.onToggle,
    required this.buttonKey,
  });

  final bool hidden;
  final VoidCallback onToggle;
  final Key buttonKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.maybeOf(context);
    return IconButton(
      key: buttonKey,
      onPressed: onToggle,
      tooltip: hidden ? 'Mostrar en la página' : 'Ocultar en la página',
      constraints: BoxConstraints.tightFor(
        width: _sectionTarget(context, 36),
        height: _sectionTarget(context, 36),
      ),
      padding: EdgeInsets.zero,
      iconSize: 18,
      color: hidden
          ? (roles?.warning.accent ?? scheme.tertiary)
          : scheme.onSurfaceVariant,
      icon: Icon(
        hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      ),
    );
  }
}

/// `O-01 VbMenu` · what a section can do besides being chosen: move it,
/// duplicate it, hide it, and — confirmed — delete it.
class _SectionBlockMenu extends StatelessWidget {
  const _SectionBlockMenu({
    required this.provider,
    required this.blockId,
    required this.label,
    required this.hidden,
    required this.canMoveUp,
    required this.canMoveDown,
  });

  final WebsiteEditModeProvider provider;
  final String blockId;
  final String label;
  final bool hidden;
  final bool canMoveUp;
  final bool canMoveDown;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final roles = VinabikeThemeRoles.maybeOf(context);
    final danger = roles?.danger.accent ?? scheme.error;
    PopupMenuItem<String> item(
      String value,
      IconData icon,
      String text, {
      bool enabled = true,
      bool destructive = false,
    }) =>
        PopupMenuItem<String>(
          value: value,
          enabled: enabled,
          child: Row(
            children: [
              Icon(icon, size: 18, color: destructive ? danger : null),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: destructive ? TextStyle(color: danger) : null,
                ),
              ),
            ],
          ),
        );
    final extent = _sectionTarget(context, 32);
    return PopupMenuButton<String>(
      key: ValueKey('website-sections-more-$blockId'),
      tooltip: 'Más acciones de $label',
      padding: EdgeInsets.zero,
      iconSize: 18,
      style: IconButton.styleFrom(
        minimumSize: Size(extent, extent),
        fixedSize: Size(extent, extent),
      ),
      constraints: const BoxConstraints(minWidth: 220),
      icon: Icon(Icons.more_horiz_rounded, color: scheme.onSurfaceVariant),
      onSelected: (action) async {
        switch (action) {
          case 'up':
            provider.moveBlockUp(blockId);
          case 'down':
            provider.moveBlockDown(blockId);
          case 'duplicate':
            provider.duplicateBlock(blockId);
          case 'copy':
            provider.copyBlockToClipboard(blockId, label: label);
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(
                content: Text(
                  '«$label» copiada: pégala aquí o en otra página.',
                ),
              ),
            );
          case 'paste':
            provider.pasteSectionFromClipboard(afterBlockId: blockId);
          case 'visibility':
            provider.toggleBlockVisibility(blockId);
          case 'delete':
            await confirmWebsiteBlockDeletion(
              context,
              provider: provider,
              blockId: blockId,
              requiresSelection: false,
            );
        }
      },
      itemBuilder: (context) => [
        item('up', Icons.arrow_upward_rounded, 'Subir', enabled: canMoveUp),
        item(
          'down',
          Icons.arrow_downward_rounded,
          'Bajar',
          enabled: canMoveDown,
        ),
        item('duplicate', Icons.copy_all_outlined, 'Duplicar'),
        item('copy', Icons.content_copy_rounded, 'Copiar para otra página'),
        if (provider.hasSectionClipboard)
          item(
            'paste',
            Icons.content_paste_rounded,
            'Pegar «${provider.sectionClipboardLabel ?? 'sección'}» debajo',
          ),
        item(
          'visibility',
          hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          hidden ? 'Mostrar en la página' : 'Ocultar en la página',
        ),
        const PopupMenuDivider(),
        item(
          'delete',
          Icons.delete_outline_rounded,
          'Eliminar bloque',
          destructive: true,
        ),
      ],
    );
  }
}

/// A control's hit extent: its pointer size, or the touch minimum where the
/// editor host is a touch host (`F-06`).
double _sectionTarget(BuildContext context, double pointerExtent) =>
    WebsiteEditorControlDensityScope.maybeOf(context)
        ?.targetExtentFor(pointerExtent) ??
    pointerExtent;

WebsiteBlockType? _outlineBlockType(String raw) {
  final normalised = raw.trim().toLowerCase();
  if (normalised.isEmpty) return null;
  for (final type in WebsiteBlockType.values) {
    if (type.name.toLowerCase() == normalised) return type;
  }
  return null;
}

IconData _outlineBlockIcon(String type) =>
    _outlineBlockType(type)?.icon ?? Icons.widgets_rounded;

String _outlineBlockLabel(String type) {
  final blockType = _outlineBlockType(type);
  if (blockType == null) return type.isEmpty ? 'Bloque' : type;
  return WebsiteBlockRegistry.definitionFor(blockType).title;
}

/// The block's own words, so two banners in a row are told apart. Words
/// that only repeat the kind («Productos destacados» under «Productos
/// destacados») say nothing and are left out.
String? _outlineBlockSubtitle(
  Map<String, dynamic> block, {
  required String label,
}) {
  final data = block['block_data'];
  if (data is! Map) return null;
  String? clean(Object? raw) {
    if (raw is! String) return null;
    final text = raw
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty || text.toLowerCase() == label.toLowerCase()) {
      return null;
    }
    return text;
  }

  for (final key in const ['title', 'heading', 'headline']) {
    if (clean(data[key]) case final text?) return text;
  }
  final slides = data['slides'];
  if (slides is List) {
    for (final slide in slides) {
      if (slide is Map) {
        if (clean(slide['title']) case final text?) return text;
      }
    }
  }
  return null;
}
