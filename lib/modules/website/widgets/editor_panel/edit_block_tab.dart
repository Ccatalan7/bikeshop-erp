part of '../website_editor_panel.dart';

enum _InspectorSection { content, layout, style }

class _CanvasSelectionContext {
  const _CanvasSelectionContext({
    required this.element,
    this.slideIndex,
  });

  /// The selected layer as the previewed viewport resolves it, so the header
  /// names what is on screen rather than the shared base.
  final Map<String, dynamic> element;
  final int? slideIndex;

  String get id => element['id']?.toString() ?? '';
  String get type => (element['type'] ?? 'text').toString();
  String get label => switch (type) {
        'button' => (element['label'] ?? 'Botón').toString(),
        'image' => (element['altText'] ?? 'Imagen').toString().trim().isEmpty
            ? 'Imagen'
            : element['altText'].toString(),
        'shape' => 'Forma',
        'product' => 'Producto',
        'productsGallery' => 'Galería de productos',
        _ => (element['text'] ?? 'Texto').toString(),
      };
  IconData get icon => switch (type) {
        'button' => Icons.smart_button_rounded,
        'image' => Icons.image_outlined,
        'shape' => Icons.rectangle_outlined,
        'product' => Icons.inventory_2_outlined,
        'productsGallery' => Icons.grid_view_rounded,
        _ => Icons.text_fields_rounded,
      };
}

/// Inspector for the selected block.
///
/// Professional editors keep block identity and primary actions stable while
/// separating content, layout and appearance. This also gives every selection
/// a predictable starting point instead of preserving an unrelated scroll
/// position from the previously selected block.
class _EditBlockTab extends StatefulWidget {
  final WebsiteEditModeProvider editProvider;

  /// The pane keeps its own identity row. The contextual sheet already names
  /// the block in its header and in the dock, so it opts out instead of
  /// stacking a third identity.
  final bool showBlockHeader;

  /// The pane owns the capsule it has always shown. A host that supplies its
  /// own `T-04` navigation passes false and drives [section] from outside.
  final bool showSectionNavigation;

  /// External section, for a host that renders the sub-tabs itself. Null keeps
  /// the internal state the pane has always used.
  final _InspectorSection? section;

  const _EditBlockTab({
    required this.editProvider,
    this.showBlockHeader = true,
    this.showSectionNavigation = true,
    this.section,
  });

  @override
  State<_EditBlockTab> createState() => _EditBlockTabState();
}

class _EditBlockTabState extends State<_EditBlockTab> {
  final ScrollController _scrollController = ScrollController();
  _InspectorSection _internalSection = _InspectorSection.content;
  String? _lastSelectedId;

  WebsiteEditModeProvider get editProvider => widget.editProvider;

  /// One reader for both hosts: the pane's own state, or the section the
  /// contextual host is showing.
  _InspectorSection get _section => widget.section ?? _internalSection;

  set _section(_InspectorSection value) => _internalSection = value;

  @override
  void didUpdateWidget(covariant _EditBlockTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A host-driven section change restarts the reading position for the same
    // reason a selection change does: the previous offset belongs to content
    // that is no longer on screen.
    if (widget.section != null && widget.section != oldWidget.section) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _syncSelection(String? selectedId) {
    if (_lastSelectedId == selectedId) return;
    _lastSelectedId = selectedId;
    _section = _InspectorSection.content;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    });
  }

  void _selectSection(_InspectorSection value) {
    if (_section == value) return;
    setState(() => _section = value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = editProvider.selectedBlockId;

    if (selectedId == null) {
      _syncSelection(null);
      return _buildNoSelection();
    }

    // Handle special elements (header/footer) - these are not blocks
    // Use ValueKey to preserve state across rebuilds
    if (selectedId == 'header') {
      _syncSelection(selectedId);
      return _HeaderBlockControls(
          key: const ValueKey('header_controls'), provider: editProvider);
    }
    if (selectedId == 'footer') {
      _syncSelection(selectedId);
      return _FooterBlockControls(
          key: const ValueKey('footer_controls'), provider: editProvider);
    }

    final block = editProvider.getBlock(selectedId);
    if (block == null) {
      return _buildNoSelection();
    }

    final blockType = block['block_type']?.toString() ?? '';
    final blockData = Map<String, dynamic>.from(block['block_data'] ?? {});
    final isVisible = block['is_visible'] ?? true;
    final canvasSelection = _resolveCanvasSelection(
      blockType: blockType,
      blockData: blockData,
      blockId: selectedId,
    );
    _syncSelection(
      canvasSelection == null
          ? selectedId
          : '$selectedId/${canvasSelection.slideIndex ?? 'root'}/${canvasSelection.id}',
    );

    return Column(
      children: [
        if (widget.showBlockHeader)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: _buildBlockHeader(
              blockType,
              isVisible,
              selectedId,
              canvasSelection: canvasSelection,
            ),
          ),
        if (widget.showSectionNavigation) ...[
          _buildSectionNavigation(),
          const Divider(height: 1, color: Colors.white12),
        ],
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollController,
            key: PageStorageKey<String>(
              'website_inspector_${selectedId}_${_section.name}',
            ),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            child: _buildSectionContent(
              blockType: blockType,
              blockData: blockData,
              block: block,
              blockId: selectedId,
              canvasSelection: canvasSelection,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionNavigation() {
    const items = <(_InspectorSection, IconData, String)>[
      (_InspectorSection.content, Icons.edit_note_rounded, 'Contenido'),
      (_InspectorSection.layout, Icons.dashboard_customize_outlined, 'Diseño'),
      (_InspectorSection.style, Icons.palette_outlined, 'Estilo'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Row(
          children: items.map((item) {
            final selected = item.$1 == _section;
            return Expanded(
              child: Semantics(
                button: true,
                selected: selected,
                label: 'Inspector: ${item.$3}',
                child: InkWell(
                  onTap: () => _selectSection(item.$1),
                  borderRadius: BorderRadius.circular(7),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF00A09D).withValues(alpha: 0.18)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF00A09D).withValues(alpha: 0.55)
                            : Colors.transparent,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          item.$2,
                          size: 15,
                          color: selected
                              ? const Color(0xFF20C5C1)
                              : Colors.white54,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            item.$3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected ? Colors.white : Colors.white54,
                              fontSize: 11.5,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSectionContent({
    required String blockType,
    required Map<String, dynamic> blockData,
    required Map<String, dynamic> block,
    required String blockId,
    _CanvasSelectionContext? canvasSelection,
  }) {
    final registeredType = _tryParseWebsiteBlockType(blockType);
    final heightBehavior = registeredType == null
        ? WebsitePageBlockHeightBehavior.intrinsic
        : WebsiteBlockCapabilityRegistry.profileFor(registeredType)
            .heightBehavior;

    if (canvasSelection != null) {
      // The Canvas inspector addresses its document by identity — block plus
      // the exact slide — and writes through the Canvas commands. There is no
      // host callback that rebuilds `elements` or `slides` any more: replacing
      // a whole list overwrites the responsive overrides inside the layers it
      // replaces.
      return _CanvasBlockControls(
        blockId: blockId,
        provider: editProvider,
        slideIndex: canvasSelection.slideIndex,
        elementsOnly: true,
        selectedElementOnly: true,
        inspectorSection: _section,
      );
    }

    switch (_section) {
      case _InspectorSection.content:
        return _buildBlockControls(blockType, blockData, blockId);
      case _InspectorSection.layout:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _InspectorIntro(
              title: 'Disposición del bloque',
              description:
                  'Controla el tamaño y el espacio que ocupa este bloque en la página.',
              icon: Icons.dashboard_customize_outlined,
            ),
            const SizedBox(height: 18),
            if (heightBehavior != WebsitePageBlockHeightBehavior.intrinsic) ...[
              _BlockHeightControl(
                data: blockData,
                blockId: blockId,
                blockType: blockType,
                heightBehavior: heightBehavior,
                provider: editProvider,
              ),
              const SizedBox(height: 18),
            ],
            _BlockSpacingControl(
              data: blockData,
              blockId: blockId,
              provider: editProvider,
            ),
            const SizedBox(height: 18),
            _BlockResponsiveVisibilityControl(
              data: blockData,
              blockId: blockId,
              provider: editProvider,
            ),
          ],
        );
      case _InspectorSection.style:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _InspectorIntro(
              title: 'Apariencia del bloque',
              description:
                  'Personaliza fondo, relleno, bordes y sombra sin alterar el contenido.',
              icon: Icons.palette_outlined,
            ),
            const SizedBox(height: 18),
            _BlockStyleControls(
              blockId: blockId,
              provider: editProvider,
              blockData: block,
              collapsible: false,
            ),
          ],
        );
    }
  }

  _CanvasSelectionContext? _resolveCanvasSelection({
    required String blockType,
    required Map<String, dynamic> blockData,
    required String blockId,
  }) {
    int? slideIndex;
    if (blockType == WebsiteBlockType.carousel.name) {
      final rawSlides = blockData['slides'];
      if (rawSlides is! List || rawSlides.isEmpty) return null;
      slideIndex = editProvider.carouselSlideSelection(
        blockId,
        rawSlides.length,
      );
    } else if (blockType != WebsiteBlockType.canvas.name) {
      return null;
    }

    final elementId = editProvider.canvasElementSelection(
      blockId,
      slideIndex: slideIndex,
    );
    if (elementId == null) return null;

    // The document is resolved by the same owner every Canvas command uses, so
    // a selection can only ever address the exact slide it belongs to.
    final document = editProvider.canvasDocument(
      blockId,
      slideIndex: slideIndex,
    );
    if (document == null) return null;
    for (final layer in WebsiteCanvasResponsiveDocument.projectLayers(
      data: document,
      viewport: editProvider.previewViewport,
    )) {
      if (layer.id == elementId) {
        return _CanvasSelectionContext(
          element: layer.data,
          slideIndex: slideIndex,
        );
      }
    }
    return null;
  }

  Widget _buildNoSelection() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.touch_app_outlined,
              size: 48,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'Selecciona un bloque',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Haz clic en cualquier bloque de la página para editar sus propiedades',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockHeader(
    String blockType,
    bool isVisible,
    String blockId, {
    _CanvasSelectionContext? canvasSelection,
  }) {
    final parsedType = _tryParseWebsiteBlockType(blockType);
    final title = parsedType != null
        ? WebsiteBlockRegistry.definitionFor(parsedType).title
        : blockType;
    final icon = parsedType?.icon ?? Icons.widgets_rounded;

    final effectiveTitle = canvasSelection?.label ?? title;
    final effectiveIcon = canvasSelection?.icon ?? icon;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canvasSelection != null) ...[
          Row(
            children: [
              InkWell(
                onTap: () => editProvider.selectCanvasElement(
                  blockId,
                  null,
                  slideIndex: canvasSelection.slideIndex,
                ),
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_rounded,
                          size: 15, color: Colors.white54),
                      SizedBox(width: 5),
                      Text('Volver al bloque',
                          style:
                              TextStyle(color: Colors.white54, fontSize: 11)),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  canvasSelection.slideIndex == null
                      ? title
                      : '$title > Slide ${canvasSelection.slideIndex! + 1}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white38, fontSize: 10.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF00A09D).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                effectiveIcon,
                color: const Color(0xFF00A09D),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    effectiveTitle,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    isVisible ? 'Visible' : 'Oculto',
                    style: TextStyle(
                      color:
                          isVisible ? const Color(0xFF00A09D) : Colors.orange,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (canvasSelection == null) ...[
              _QuickActionButton(
                targetKey: const ValueKey<String>(
                  'website-block-quick-visibility',
                ),
                icon: isVisible ? Icons.visibility : Icons.visibility_off,
                tooltip: isVisible ? 'Ocultar' : 'Mostrar',
                onPressed: () => editProvider.toggleBlockVisibility(blockId),
              ),
              _QuickActionButton(
                targetKey: const ValueKey<String>(
                  'website-block-quick-duplicate',
                ),
                icon: Icons.content_copy,
                tooltip: 'Duplicar',
                onPressed: () => editProvider.duplicateBlock(blockId),
              ),
              _QuickActionButton(
                targetKey: const ValueKey<String>(
                  'website-block-quick-delete',
                ),
                icon: Icons.delete_outline,
                tooltip: 'Eliminar',
                onPressed: () => editProvider.deleteBlock(blockId),
                isDestructive: true,
              ),
            ],
          ],
        ),
      ],
    );
  }

  WebsiteBlockType? _tryParseWebsiteBlockType(String raw) {
    final normalised = raw.trim();
    if (normalised.isEmpty) return null;

    // Parse using the shared helper, but only accept it if it actually matched.
    final parsed = parseWebsiteBlockType(
      normalised,
      fallback: WebsiteBlockType.hero,
    );

    if (parsed.name.toLowerCase() == normalised.toLowerCase()) {
      return parsed;
    }

    // If we fell back to hero for a non-hero raw value, treat as unknown.
    if (parsed == WebsiteBlockType.hero && normalised.toLowerCase() != 'hero') {
      return null;
    }
    return parsed;
  }

  Widget _buildBlockControls(
      String blockType, Map<String, dynamic> data, String blockId) {
    // Build controls based on block type
    switch (blockType) {
      case 'carousel':
        return _CarouselBlockControls(
            data: data, blockId: blockId, provider: editProvider);
      case 'canvas':
        return _CanvasBlockControls(blockId: blockId, provider: editProvider);
      case 'products':
        return _ProductsBlockControls(
            data: data, blockId: blockId, provider: editProvider);
      case 'about':
      case 'categoryGrid':
      case 'partnersBanner':
      case 'brandLogos':
      case 'videoBanner':
        final parsedType = _tryParseWebsiteBlockType(blockType);
        return _GenericBlockControls(
          data: data,
          blockId: blockId,
          provider: editProvider,
          blockType: parsedType,
          rawBlockType: blockType,
        );
      default:
        final parsedType = _tryParseWebsiteBlockType(blockType);
        return _GenericBlockControls(
          data: data,
          blockId: blockId,
          provider: editProvider,
          blockType: parsedType,
          rawBlockType: blockType,
        );
    }
  }
}

class _BlockResponsiveVisibilityControl extends StatelessWidget {
  const _BlockResponsiveVisibilityControl({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  @visibleForTesting
  static const Key migrationDialogKey =
      Key('website-visibility-migration-dialog');

  Future<void> _toggle(
    BuildContext context, {
    required String breakpoint,
    required bool nextValue,
  }) async {
    final viewport = provider.renderedBlockViewportFor(blockId);
    if (viewport == null) return;
    final target = WebsiteInlineManipulationTarget(
      blockId: blockId,
      owner: const WebsiteInlineBlockOwner(),
      viewport: viewport,
      properties: <WebsiteInlineManipulationProperty>[
        WebsiteInlineManipulationProperty(
          canonicalKey: 'visibility',
          policy: WebsiteResponsivePropertyPolicy.sharedOnly,
        ),
      ],
      requiresSelection: true,
    );
    final lease = provider.captureInlineMutationLease(target);
    if (lease == null) return;
    final sourceData = _blockDataOf(lease.sourceBlock);
    final rawVisibility = sourceData['visibility'];
    final generation = websiteVisibilityGeneration(rawVisibility);
    final needsConfirmation =
        generation == WebsiteVisibilityBreakpointGeneration.legacy &&
            !canMigrateWebsiteVisibilityWithoutBehaviorChange(rawVisibility);

    WebsiteInlineMutationResult commit(
      WebsiteEditModeProvider owner, {
      required bool confirmLegacyMigration,
    }) {
      return owner.commitInlineMutation(
        lease,
        <String, Object?>{
          'visibility': updatedWebsiteBlockVisibility(
            rawVisibility,
            breakpoint: breakpoint,
            isVisible: nextValue,
            useCanonicalBreakpoints:
                generation == WebsiteVisibilityBreakpointGeneration.canonical ||
                    !needsConfirmation ||
                    confirmLegacyMigration,
          ),
        },
      );
    }

    if (!needsConfirmation) {
      commit(provider, confirmLegacyMigration: false);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: migrationDialogKey,
        title: const Text('Actualizar puntos de quiebre'),
        content: const Text(
          'Este bloque usa los tamaños anteriores (640 y 1024 px). '
          'Al editar su visibilidad se actualizará al sistema actual '
          '(600 y 900 px), por lo que también puede cambiar lo que se ve '
          'entre 600–639 px y 900–1023 px.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Actualizar y continuar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    WebsiteEditModeProvider liveProvider;
    try {
      liveProvider = context.read<WebsiteEditModeProvider>();
    } catch (_) {
      return;
    }
    commit(liveProvider, confirmLegacyMigration: true);
  }

  Map<String, bool> get _visibility {
    final result = <String, bool>{
      'desktop': true,
      'tablet': true,
      'mobile': true,
    };
    final raw = data['visibility'];
    if (raw is Map) {
      for (final key in result.keys) {
        final value = raw[key];
        if (value is bool) result[key] = value;
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final visibility = _visibility;
    const options = <(String, String, IconData)>[
      ('desktop', 'Escritorio', Icons.desktop_windows_outlined),
      ('tablet', 'Tablet', Icons.tablet_mac_outlined),
      ('mobile', 'Móvil', Icons.phone_iphone_outlined),
    ];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .035),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.devices_outlined, color: Color(0xFF00A09D), size: 18),
              SizedBox(width: 8),
              Text(
                'Visibilidad responsive',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'El contenido se conserva; sólo decides en qué tamaños aparece.',
            style: TextStyle(color: Colors.white38, fontSize: 10),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final option in options)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: option.$1 == 'mobile' ? 0 : 6,
                    ),
                    child: Semantics(
                      button: true,
                      selected: visibility[option.$1]!,
                      label:
                          '${option.$2}: ${visibility[option.$1]! ? 'visible' : 'oculto'}',
                      child: InkWell(
                        onTap: () => _toggle(
                          context,
                          breakpoint: option.$1,
                          nextValue: !visibility[option.$1]!,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: visibility[option.$1]!
                                ? const Color(0xFF00A09D).withValues(alpha: .18)
                                : Colors.white.withValues(alpha: .035),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: visibility[option.$1]!
                                  ? const Color(0xFF00A09D)
                                  : Colors.white12,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                option.$3,
                                size: 18,
                                color: visibility[option.$1]!
                                    ? const Color(0xFF20C5C1)
                                    : Colors.white30,
                              ),
                              const SizedBox(height: 5),
                              Text(
                                option.$2,
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: visibility[option.$1]!
                                      ? Colors.white
                                      : Colors.white38,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Block height control with presets and custom input
class _BlockHeightControl extends StatefulWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final String blockType;
  final WebsitePageBlockHeightBehavior heightBehavior;
  final WebsiteEditModeProvider provider;

  const _BlockHeightControl({
    required this.data,
    required this.blockId,
    required this.blockType,
    required this.heightBehavior,
    required this.provider,
  });

  @override
  State<_BlockHeightControl> createState() => _BlockHeightControlState();
}

class _BlockHeightControlState extends State<_BlockHeightControl> {
  late TextEditingController _customHeightController;
  late final FocusNode _customHeightFocusNode = FocusNode(
    debugLabel: 'website-block-custom-height',
  );
  bool _showCustomInput = false;

  @override
  void initState() {
    super.initState();
    final currentHeight = (widget.data['blockHeight'] as num?)?.toDouble();
    _customHeightController = TextEditingController(
      text: currentHeight?.toStringAsFixed(0) ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant _BlockHeightControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentHeight = (widget.data['blockHeight'] as num?)?.toDouble();
    if (currentHeight?.toStringAsFixed(0) != _customHeightController.text) {
      _customHeightController.text = currentHeight?.toStringAsFixed(0) ?? '';
    }
  }

  @override
  void dispose() {
    _customHeightController.dispose();
    _customHeightFocusNode.dispose();
    super.dispose();
  }

  WebsiteResponsiveScalarBinding<num> _binding(BuildContext context) {
    return WebsiteResponsiveScalarBinding<num>.forField(
      provider: widget.provider,
      blockId: widget.blockId,
      field: WebsiteBlockMetaFields.blockHeight,
      owner: const WebsiteResponsiveRootField(),
      decode: WebsiteResponsiveScalarBinding.decodeNumber,
      hostClass: WebsiteEditorChromeScope.maybeOf(context)?.hostClass ??
          WebsiteAuthoringHostClass.desktop,
      viewport: WebsiteEditorAuthoringViewportScope.effectiveOf(
        context,
        fallback: widget.provider.previewViewport,
      ),
    );
  }

  void _setHeight(
    WebsiteResponsiveScalarBinding<num> binding,
    double? height,
  ) {
    binding.write(height);
    if (height != null) {
      _customHeightController.text = height.toStringAsFixed(0);
    } else {
      _customHeightController.text = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final binding = _binding(context);
    final currentHeight = binding.value?.toDouble();
    return ResponsiveFieldShell<num>(
      state: binding.state,
      onCustomize: binding.customize,
      onReset: binding.reset,
      helpText: widget.heightBehavior.inspectorLabel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (currentHeight != null)
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '${currentHeight.toStringAsFixed(0)}px',
                style: const TextStyle(
                    color: Color(0xFF00A09D),
                    fontSize: 11,
                    fontWeight: FontWeight.w500),
              ),
            ),
          const SizedBox(height: 8),
          BlockHeightPresetSelector(
            blockType: widget.blockType,
            currentHeight: currentHeight,
            onHeightChanged: (height) => _setHeight(binding, height),
          ),
          const SizedBox(height: 8),
          // Custom height input toggle
          Row(
            children: [
              WebsiteEditorControlTarget(
                targetKey: const ValueKey<String>(
                  'website-height-custom-toggle',
                ),
                semanticLabel: 'Altura personalizada',
                onTap: () =>
                    setState(() => _showCustomInput = !_showCustomInput),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _showCustomInput
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: Colors.white38,
                      size: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Altura personalizada',
                      style: TextStyle(
                        color:
                            _showCustomInput ? Colors.white70 : Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (currentHeight != null)
                WebsiteEditorControlTarget(
                  targetKey: const ValueKey<String>('website-height-reset'),
                  semanticLabel: 'Restablecer altura automática',
                  onTap: () => _setHeight(binding, null),
                  child: const Text(
                    'Restablecer',
                    style: TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        decoration: TextDecoration.underline),
                  ),
                ),
            ],
          ),
          if (_showCustomInput) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: WebsiteEditorControlTarget(
                    targetKey: const ValueKey<String>(
                      'website-height-custom-input',
                    ),
                    semanticLabel: 'Altura personalizada en píxeles',
                    semanticsButton: false,
                    onTap: _customHeightFocusNode.requestFocus,
                    child: SizedBox(
                      width: double.infinity,
                      child: Container(
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2D2D2D),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: TextField(
                          focusNode: _customHeightFocusNode,
                          controller: _customHeightController,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            hintText: 'ej: 450',
                            hintStyle:
                                TextStyle(color: Colors.white24, fontSize: 12),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                            isDense: true,
                          ),
                          onSubmitted: (value) {
                            final parsed = double.tryParse(value);
                            if (parsed != null && parsed >= 100) {
                              _setHeight(binding, parsed);
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                WebsiteEditorControlTarget(
                  targetKey: const ValueKey<String>('website-height-apply'),
                  semanticLabel: 'Aplicar altura personalizada',
                  minimumWidth: true,
                  onTap: () {
                    final parsed =
                        double.tryParse(_customHeightController.text);
                    if (parsed != null && parsed >= 100) {
                      _setHeight(binding, parsed);
                    }
                  },
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00A09D),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Center(
                      child: Text(
                        'Aplicar',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.heightBehavior.inspectorResizeHint!,
              style: const TextStyle(color: Colors.white24, fontSize: 9),
            ),
          ],
        ],
      ),
    );
  }
}

/// Control for spacing after a block (gap between blocks)
class _BlockSpacingControl extends StatefulWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _BlockSpacingControl({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  State<_BlockSpacingControl> createState() => _BlockSpacingControlState();
}

class _BlockSpacingControlState extends State<_BlockSpacingControl> {
  double get _sectionSpacing {
    final sectionSpacing = WebsitePageComposition.resolveSectionSpacing(
      widget.provider.getEffectiveThemeSetting(
        'theme_section_spacing',
        WebsitePageComposition.defaultSectionSpacing.toString(),
      ),
    );
    return sectionSpacing;
  }

  WebsiteResponsiveScalarBinding<num> _binding(BuildContext context) {
    return WebsiteResponsiveScalarBinding<num>.forField(
      provider: widget.provider,
      blockId: widget.blockId,
      field: WebsiteBlockMetaFields.spacingAfter,
      owner: const WebsiteResponsiveRootField(),
      decode: WebsiteResponsiveScalarBinding.decodeNumber,
      fallback: _sectionSpacing,
      hostClass: WebsiteEditorChromeScope.maybeOf(context)?.hostClass ??
          WebsiteAuthoringHostClass.desktop,
      viewport: WebsiteEditorAuthoringViewportScope.effectiveOf(
        context,
        fallback: widget.provider.previewViewport,
      ),
    );
  }

  void _setSpacing(
    WebsiteResponsiveScalarBinding<num> binding,
    double spacing,
  ) {
    binding.write(spacing);
  }

  @override
  Widget build(BuildContext context) {
    final binding = _binding(context);
    final asyncBinding = WebsiteAsyncFieldBinding.pageBlock(
      provider: widget.provider,
      target: WebsiteAsyncFieldTarget.block(
        blockId: widget.blockId,
        scopeKey: 'root.${WebsiteBlockMetaFields.spacingAfter.key}',
      ),
    );
    final currentSpacing = WebsitePageComposition.resolveSpacingAfter(
      binding.value,
      sectionSpacing: _sectionSpacing,
    );
    return ResponsiveFieldShell<num>(
      state: binding.state,
      onCustomize: binding.customize,
      onReset: binding.reset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.height, color: Colors.white38, size: 14),
              const Spacer(),
              Text(
                currentSpacing == 0 ? '0' : '${currentSpacing.toInt()}px',
                style: const TextStyle(
                    color: Color(0xFF00A09D),
                    fontSize: 11,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Preset buttons
          Row(
            children: [
              _SpacingPresetButton(
                label: '0',
                isSelected: currentSpacing == 0,
                onTap: () => _setSpacing(binding, 0),
              ),
              const SizedBox(width: 6),
              _SpacingPresetButton(
                label: 'S',
                isSelected: currentSpacing > 0 && currentSpacing <= 16,
                onTap: () => _setSpacing(binding, 16),
              ),
              const SizedBox(width: 6),
              _SpacingPresetButton(
                label: 'M',
                isSelected: currentSpacing > 16 && currentSpacing <= 32,
                onTap: () => _setSpacing(binding, 32),
              ),
              const SizedBox(width: 6),
              _SpacingPresetButton(
                label: 'L',
                isSelected: currentSpacing > 32 && currentSpacing <= 64,
                onTap: () => _setSpacing(binding, 64),
              ),
              const SizedBox(width: 6),
              _SpacingPresetButton(
                label: 'XL',
                isSelected: currentSpacing > 64,
                onTap: () => _setSpacing(binding, 96),
              ),
            ],
          ),
          const SizedBox(height: 6),
          WebsiteTransactionalSlider(
            key: const ValueKey<String>('website-block-spacing-slider'),
            value: currentSpacing.clamp(0, 200).toDouble(),
            min: 0,
            max: 200,
            divisions: 50,
            transactionIdentity: (
              asyncBinding.identity,
              binding.state.context.hostClass,
              binding.state.context.previewViewport,
              binding.state.effectiveWriteScope,
              binding.state.status,
            ),
            asyncBinding: asyncBinding,
            onCommit: (value) => _setSpacing(binding, value.roundToDouble()),
            builder: (context, _, slider) => SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: const Color(0xFF00A09D),
                inactiveTrackColor: Colors.white12,
                thumbColor: const Color(0xFF00A09D),
                overlayColor: const Color(0xFF00A09D).withValues(alpha: 0.2),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                trackHeight: 3,
              ),
              child: slider,
            ),
          ),
          const Text(
            'También puedes arrastrar la línea entre bloques',
            style: TextStyle(color: Colors.white24, fontSize: 9),
          ),
        ],
      ),
    );
  }
}

class _SpacingPresetButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SpacingPresetButton({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: WebsiteEditorControlTarget(
        targetKey: ValueKey<String>('website-spacing-preset-$label'),
        semanticLabel: 'Espaciado $label',
        onTap: onTap,
        child: SizedBox(
          width: double.infinity,
          child: Container(
            height: 28,
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF00A09D)
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: isSelected ? const Color(0xFF00A09D) : Colors.white12,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final Key targetKey;
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isDestructive;

  const _QuickActionButton({
    required this.targetKey,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: WebsiteEditorControlTarget(
        targetKey: targetKey,
        semanticLabel: tooltip,
        minimumWidth: true,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(
            icon,
            color: isDestructive ? Colors.red.shade300 : Colors.white54,
            size: 18,
          ),
        ),
      ),
    );
  }
}
