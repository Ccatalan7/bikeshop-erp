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

/// Leaves the editor for Inventario's services, through the same guard as
/// any other exit (save or discard first).
Future<void> _openCatalogSource(
  BuildContext context,
  WebsiteEditModeProvider provider,
) async {
  final decision = await WebsiteEditorNavigationGuard.authorize(
    context,
    intent: WebsiteEditorNavigationIntent.leaveEditor,
  );
  if (!decision.isAllowed || !context.mounted) return;
  if (!decision.commit()) return;
  provider.closeEditor();
  context.go('/inventory/services');
}

/// The sections of the catalog page on the canvas, with nothing selected:
/// what the page is made of, what comes from the catalog, and each section a
/// tap away (the canvas selects the same ones).
class _CatalogSectionOutline extends StatelessWidget {
  const _CatalogSectionOutline({
    required this.provider,
    required this.canvas,
  });

  final WebsiteEditModeProvider provider;
  final WebsiteCatalogCanvasContext canvas;

  @override
  Widget build(BuildContext context) {
    final shown = provider.effectiveCatalogPresentation(canvas.saved);
    WebsiteCatalogSectionTarget target(WebsiteCatalogSection section) =>
        WebsiteCatalogSectionTarget(canvas.ownerId, section);
    final priceList = shown.isPriceList;
    return ListView(
      key: const PageStorageKey<String>('website_catalog_outline'),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
      children: [
        Text(
          'Secciones de ${canvas.rootLabel}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Toca una sección aquí o en la página. Los textos también se '
          'escriben directo sobre ella.',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.55),
            fontSize: 12,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),
        _CatalogOutlineRow(
          icon: Icons.web_asset_rounded,
          label: 'Encabezado',
          note: 'todo el sitio',
          onTap: () => provider
              .selectBlock(WebsiteEditorChromeTarget.header.selectionId),
        ),
        if (priceList) ...[
          _CatalogOutlineRow(
            icon: Icons.title_rounded,
            label: 'Portada',
            onTap: () => provider
                .selectBlock(target(WebsiteCatalogSection.hero).selectionId),
          ),
          _CatalogOutlineRow(
            icon: Icons.view_week_outlined,
            label: 'Planes',
            note: canvas.planCount == 0
                ? 'sin planes'
                : 'del catálogo · ${canvas.planCount}',
            fromCatalog: canvas.planCount > 0,
            onTap: () => provider
                .selectBlock(target(WebsiteCatalogSection.plans).selectionId),
          ),
          _CatalogOutlineRow(
            icon: Icons.format_list_bulleted_rounded,
            label: 'Todos los ${canvas.noun}',
            note: 'del catálogo · ${canvas.itemCount - canvas.planCount}',
            fromCatalog: true,
            onTap: () => provider
                .selectBlock(target(WebsiteCatalogSection.list).selectionId),
          ),
          _CatalogOutlineRow(
            icon: Icons.call_to_action_outlined,
            label: 'Cierre',
            note: shown.hasClosing ? null : 'vacío',
            onTap: () => provider.selectBlock(
              target(WebsiteCatalogSection.closing).selectionId,
            ),
          ),
        ] else
          _CatalogOutlineRow(
            icon: Icons.grid_view_rounded,
            label: 'Todos los ${canvas.noun}',
            note: 'del catálogo · ${canvas.itemCount}',
            fromCatalog: true,
            onTap: () => provider
                .selectBlock(target(WebsiteCatalogSection.page).selectionId),
          ),
        _CatalogOutlineRow(
          icon: Icons.web_asset_rounded,
          label: 'Pie de página',
          note: 'todo el sitio',
          onTap: () => provider
              .selectBlock(WebsiteEditorChromeTarget.footer.selectionId),
        ),
        const SizedBox(height: 8),
        _CatalogOutlineRow(
          icon: Icons.tune_rounded,
          label: 'Diseño y Google',
          note: priceList ? 'lista de precios' : 'cuadrícula',
          onTap: () => provider
              .selectBlock(target(WebsiteCatalogSection.page).selectionId),
        ),
        const SizedBox(height: 16),
        _CatalogSourceNote(
          provider: provider,
          text: priceList
              ? '${canvas.itemCount} ${canvas.noun} en ${canvas.groupCount} '
                  'grupos. Precios, nombres y lo que incluye cada plan se '
                  'cambian en el servicio, no aquí.'
              : '${canvas.itemCount} ${canvas.noun}. Precios, nombres y '
                  'fotos se cambian en el servicio, no aquí.',
        ),
      ],
    );
  }
}

class _CatalogOutlineRow extends StatelessWidget {
  const _CatalogOutlineRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.note,
    this.fromCatalog = false,
  });

  final IconData icon;
  final String label;
  final String? note;

  /// Its content is read from the catalog: the note says so in the accent.
  final bool fromCatalog;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = websiteEditorAccent(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.white.withValues(alpha: 0.03),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: Colors.white60),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 3,
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (note != null) ...[
                    const SizedBox(width: 8),
                    // Its own share of the row, ending at the chevron: the
                    // notes of every row line up on the right.
                    Expanded(
                      flex: 2,
                      child: Text(
                        note!,
                        textAlign: TextAlign.end,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: fromCatalog
                              ? accent
                              : Colors.white.withValues(alpha: 0.5),
                          fontSize: 11.5,
                          fontWeight:
                              fromCatalog ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: Colors.white38,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
            label: const Text(
              'Abrir servicios en Inventario',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
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

    final children = switch (target.section) {
      WebsiteCatalogSection.hero => _hero(context, value, canvas, stage),
      WebsiteCatalogSection.plans => _plans(context, value, canvas, stage),
      WebsiteCatalogSection.list => _list(context, canvas),
      WebsiteCatalogSection.closing => _closing(context, value, stage),
      WebsiteCatalogSection.page => _page(context, value, stage),
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
    ValueChanged<WebsiteCatalogPresentation> stage,
  ) {
    final saved = _savedCatalogPresentation(context, provider, target.ownerId);
    final losesSections = saved.isPriceList && !value.isPriceList;
    return [
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
        ],
      ),
    ];
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
