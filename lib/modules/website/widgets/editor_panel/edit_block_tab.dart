part of '../website_editor_panel.dart';

enum _InspectorSection { content, layout, style }

class _CanvasSelectionContext {
  const _CanvasSelectionContext({
    required this.canvasData,
    required this.element,
    this.slideIndex,
  });

  final Map<String, dynamic> canvasData;
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

  const _EditBlockTab({required this.editProvider});

  @override
  State<_EditBlockTab> createState() => _EditBlockTabState();
}

class _EditBlockTabState extends State<_EditBlockTab> {
  final ScrollController _scrollController = ScrollController();
  _InspectorSection _section = _InspectorSection.content;
  String? _lastSelectedId;

  WebsiteEditModeProvider get editProvider => widget.editProvider;

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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: _buildBlockHeader(
            blockType,
            isVisible,
            selectedId,
            canvasSelection: canvasSelection,
          ),
        ),
        _buildSectionNavigation(),
        const Divider(height: 1, color: Colors.white12),
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
      void updateSlideValue(String key, dynamic value) {
        final rawSlides = blockData['slides'];
        if (canvasSelection.slideIndex == null || rawSlides is! List) {
          editProvider.updateBlockData(blockId, key, value);
          return;
        }
        final slides = rawSlides
            .whereType<Map>()
            .map((slide) => Map<String, dynamic>.from(slide))
            .toList();
        final index = canvasSelection.slideIndex!;
        if (index < 0 || index >= slides.length) return;
        slides[index] = {...slides[index], key: value};
        editProvider.updateBlockData(blockId, 'slides', slides);
      }

      return _CanvasBlockControls(
        data: canvasSelection.canvasData,
        blockId: blockId,
        provider: editProvider,
        slideIndex: canvasSelection.slideIndex,
        elementsOnly: true,
        selectedElementOnly: true,
        inspectorSection: _section,
        onElementsChanged: (elements) => updateSlideValue('elements', elements),
        onCanvasSettingChanged: updateSlideValue,
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
    Map<String, dynamic> canvasData = blockData;
    if (blockType == WebsiteBlockType.carousel.name) {
      final rawSlides = blockData['slides'];
      if (rawSlides is! List || rawSlides.isEmpty) return null;
      slideIndex = editProvider.carouselSlideSelection(
        blockId,
        rawSlides.length,
      );
      final slide = rawSlides[slideIndex];
      if (slide is! Map) return null;
      canvasData = Map<String, dynamic>.from(slide);
    } else if (blockType != WebsiteBlockType.canvas.name) {
      return null;
    }

    final elementId = editProvider.canvasElementSelection(
      blockId,
      slideIndex: slideIndex,
    );
    if (elementId == null) return null;
    final rawElements = canvasData['elements'];
    if (rawElements is! List) return null;
    for (final raw in rawElements) {
      if (raw is Map && raw['id']?.toString() == elementId) {
        return _CanvasSelectionContext(
          canvasData: canvasData,
          element: Map<String, dynamic>.from(raw),
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
                icon: isVisible ? Icons.visibility : Icons.visibility_off,
                tooltip: isVisible ? 'Ocultar' : 'Mostrar',
                onPressed: () => editProvider.toggleBlockVisibility(blockId),
              ),
              _QuickActionButton(
                icon: Icons.content_copy,
                tooltip: 'Duplicar',
                onPressed: () => editProvider.duplicateBlock(blockId),
              ),
              _QuickActionButton(
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
        return _CanvasBlockControls(
            data: data, blockId: blockId, provider: editProvider);
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
                        onTap: () {
                          final updated = Map<String, bool>.from(visibility);
                          updated[option.$1] = !updated[option.$1]!;
                          provider.updateBlockData(
                            blockId,
                            'visibility',
                            updated,
                          );
                        },
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
    super.dispose();
  }

  double? get _currentHeight =>
      (widget.data['blockHeight'] as num?)?.toDouble();

  void _setHeight(double? height) {
    widget.provider.updateBlockData(widget.blockId, 'blockHeight', height);
    if (height != null) {
      _customHeightController.text = height.toStringAsFixed(0);
    } else {
      _customHeightController.text = '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              widget.heightBehavior.inspectorLabel!,
              style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            if (_currentHeight != null)
              Text(
                '${_currentHeight!.toStringAsFixed(0)}px',
                style: const TextStyle(
                    color: Color(0xFF00A09D),
                    fontSize: 11,
                    fontWeight: FontWeight.w500),
              ),
          ],
        ),
        const SizedBox(height: 8),
        BlockHeightPresetSelector(
          blockType: widget.blockType,
          currentHeight: _currentHeight,
          onHeightChanged: _setHeight,
        ),
        const SizedBox(height: 8),
        // Custom height input toggle
        Row(
          children: [
            GestureDetector(
              onTap: () => setState(() => _showCustomInput = !_showCustomInput),
              child: Row(
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
                      color: _showCustomInput ? Colors.white70 : Colors.white38,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (_currentHeight != null)
              GestureDetector(
                onTap: () => _setHeight(null),
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
                child: Container(
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2D2D2D),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: TextField(
                    controller: _customHeightController,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: 'ej: 450',
                      hintStyle: TextStyle(color: Colors.white24, fontSize: 12),
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      isDense: true,
                    ),
                    onSubmitted: (value) {
                      final parsed = double.tryParse(value);
                      if (parsed != null && parsed >= 100) {
                        _setHeight(parsed);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  final parsed = double.tryParse(_customHeightController.text);
                  if (parsed != null && parsed >= 100) {
                    _setHeight(parsed);
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
  double get _currentSpacing {
    final sectionSpacing = WebsitePageComposition.resolveSectionSpacing(
      widget.provider.getEffectiveThemeSetting(
        'theme_section_spacing',
        WebsitePageComposition.defaultSectionSpacing.toString(),
      ),
    );
    return WebsitePageComposition.resolveSpacingAfter(
      widget.data['spacingAfter'],
      sectionSpacing: sectionSpacing,
    );
  }

  void _setSpacing(double spacing) {
    widget.provider.updateBlockData(widget.blockId, 'spacingAfter', spacing);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.height, color: Colors.white38, size: 14),
            const SizedBox(width: 6),
            const Text(
              'Espaciado inferior',
              style: TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text(
              _currentSpacing == 0 ? '0' : '${_currentSpacing.toInt()}px',
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
              isSelected: _currentSpacing == 0,
              onTap: () => _setSpacing(0),
            ),
            const SizedBox(width: 6),
            _SpacingPresetButton(
              label: 'S',
              isSelected: _currentSpacing > 0 && _currentSpacing <= 16,
              onTap: () => _setSpacing(16),
            ),
            const SizedBox(width: 6),
            _SpacingPresetButton(
              label: 'M',
              isSelected: _currentSpacing > 16 && _currentSpacing <= 32,
              onTap: () => _setSpacing(32),
            ),
            const SizedBox(width: 6),
            _SpacingPresetButton(
              label: 'L',
              isSelected: _currentSpacing > 32 && _currentSpacing <= 64,
              onTap: () => _setSpacing(64),
            ),
            const SizedBox(width: 6),
            _SpacingPresetButton(
              label: 'XL',
              isSelected: _currentSpacing > 64,
              onTap: () => _setSpacing(96),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Slider
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: const Color(0xFF00A09D),
            inactiveTrackColor: Colors.white12,
            thumbColor: const Color(0xFF00A09D),
            overlayColor: const Color(0xFF00A09D).withValues(alpha: 0.2),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            trackHeight: 3,
          ),
          child: Slider(
            value: _currentSpacing.clamp(0, 200),
            min: 0,
            max: 200,
            divisions: 50,
            onChanged: (value) => _setSpacing(value.roundToDouble()),
          ),
        ),
        const Text(
          'También puedes arrastrar la línea entre bloques',
          style: TextStyle(color: Colors.white24, fontSize: 9),
        ),
      ],
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
      child: GestureDetector(
        onTap: onTap,
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
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isDestructive;

  const _QuickActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
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
