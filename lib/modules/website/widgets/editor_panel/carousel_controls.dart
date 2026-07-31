part of '../website_editor_panel.dart';

/// Carousel block controls with slides management
class _CarouselBlockControls extends StatefulWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;

  const _CarouselBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
  });

  @override
  State<_CarouselBlockControls> createState() => _CarouselBlockControlsState();
}

class _CarouselBlockControlsState extends State<_CarouselBlockControls> {
  int _selectedSlideIndex = 0;
  WebsiteEditModeProvider get editProvider => widget.provider;

  void _selectSlide(int index, {bool rebuild = true}) {
    final count = _slides.length;
    if (count <= 0) return;
    final normalized = index.clamp(0, count - 1).toInt();
    if (rebuild && mounted) {
      setState(() => _selectedSlideIndex = normalized);
    } else {
      _selectedSlideIndex = normalized;
    }
    widget.provider.selectCarouselSlide(widget.blockId, normalized, count);
  }

  List<Map<String, dynamic>> get _slides {
    final rawSlides = widget.data['slides'];
    if (rawSlides is List) {
      return rawSlides.map((s) => Map<String, dynamic>.from(s as Map)).toList();
    }
    return [];
  }

  void _updateSlides(List<Map<String, dynamic>> newSlides) {
    debugPrint(
        '🎠 [CarouselControls] _updateSlides: saving ${newSlides.length} slides to provider');
    debugPrint(
        '🎠 [CarouselControls] First slide data: ${newSlides.isNotEmpty ? newSlides[0] : "empty"}');
    widget.provider.updateBlockData(widget.blockId, 'slides', newSlides);
  }

  void _updateSlide(int index, String key, dynamic value) {
    debugPrint(
        '🎠🎠 [CarouselControls] _updateSlide CALLED: index=$index, key=$key, value=$value');
    final slides = List<Map<String, dynamic>>.from(_slides);
    if (index >= 0 && index < slides.length) {
      slides[index] = {...slides[index], key: value};
      debugPrint(
          '🎠 [CarouselControls] _updateSlide: index=$index, key=$key, value=$value');
      _updateSlides(slides);
    } else {
      debugPrint(
          '🎠⚠️ [CarouselControls] _updateSlide: INVALID INDEX index=$index, slides.length=${slides.length}');
    }
  }

  /// Update multiple slide properties atomically
  void _updateSlideMultiple(int index, Map<String, dynamic> updates) {
    final slides = List<Map<String, dynamic>>.from(_slides);
    if (index >= 0 && index < slides.length) {
      slides[index] = {...slides[index], ...updates};
      debugPrint(
          '🎠 [CarouselControls] _updateSlideMultiple: index=$index, keys=${updates.keys.join(", ")}');
      _updateSlides(slides);
    }
  }

  void _setCompositionEnabled(Map<String, dynamic> slide, bool enabled) {
    if (!enabled) {
      _updateSlide(_selectedSlideIndex, 'useComposition', false);
      return;
    }

    final existing = slide['elements'];
    if (existing is List && existing.isNotEmpty) {
      _updateSlide(_selectedSlideIndex, 'useComposition', true);
      return;
    }

    final title = (slide['title'] ?? 'Título del banner').toString();
    final subtitle = (slide['subtitle'] ?? '').toString();
    final action = WebsiteActionValue.resolvePrimary(
          slide,
          labelKeys: const ['ctaText', 'buttonText'],
          hrefKeys: const ['ctaLink', 'buttonLink'],
          defaultLabel: 'Ver más',
          defaultHref: '/productos',
          defaultVariant: WebsiteActionVariant.outline,
        ) ??
        const WebsiteActionValue(
          label: 'Ver más',
          href: '/productos',
          variant: WebsiteActionVariant.outline,
        );
    Map<String, dynamic> textElement({
      required String id,
      required String text,
      required double x,
      required double y,
      required double w,
      required double h,
      required double size,
      required bool mobile,
      String role = 'heading',
      String weight = 'w700',
    }) =>
        {
          'id': id,
          'type': 'text',
          'text': text,
          'x': x,
          'y': y,
          'w': w,
          'h': h,
          'fontSize': size,
          'fontWeight': weight,
          'fontRole': role,
          'color': '#FFFFFF',
          'align': 'left',
          'lineHeight': 1.05,
          'letterSpacing': role == 'heading' ? 1.0 : 0.0,
          'hideOnMobile': !mobile,
          'showOnMobile': mobile,
        };
    Map<String, dynamic> buttonElement({
      required String id,
      required double x,
      required double y,
      required bool mobile,
    }) =>
        {
          'id': id,
          'type': 'button',
          'x': x,
          'y': y,
          'w': 220.0,
          'h': 56.0,
          'label': action.label,
          'link': action.href,
          'style': action.variant.storageValue,
          'inheritTheme': true,
          'actions': WebsiteActionValue.mergePrimary(null, action),
          'hideOnMobile': !mobile,
          'showOnMobile': mobile,
        };

    final elements = <Map<String, dynamic>>[
      textElement(
        id: 'title_desktop',
        text: title,
        x: 120,
        y: 190,
        w: 620,
        h: 130,
        size: 58,
        mobile: false,
      ),
      if (subtitle.isNotEmpty)
        textElement(
          id: 'subtitle_desktop',
          text: subtitle,
          x: 120,
          y: 330,
          w: 560,
          h: 80,
          size: 22,
          mobile: false,
          role: 'body',
          weight: 'w400',
        ),
      buttonElement(id: 'button_desktop', x: 120, y: 430, mobile: false),
      textElement(
        id: 'title_mobile',
        text: title,
        x: 28,
        y: 160,
        w: 334,
        h: 150,
        size: 42,
        mobile: true,
      ),
      if (subtitle.isNotEmpty)
        textElement(
          id: 'subtitle_mobile',
          text: subtitle,
          x: 28,
          y: 320,
          w: 334,
          h: 90,
          size: 18,
          mobile: true,
          role: 'body',
          weight: 'w400',
        ),
      buttonElement(id: 'button_mobile', x: 28, y: 440, mobile: true),
    ];

    _updateSlideMultiple(_selectedSlideIndex, {
      'useComposition': true,
      'designWidth': 1200.0,
      'mobileDesignWidth': 390.0,
      'constrainElementsToSafeArea': true,
      'elements': elements,
    });
  }

  void _addSlide() {
    final slides = List<Map<String, dynamic>>.from(_slides);
    slides.add({
      'title': 'Nuevo Slide',
      'subtitle': 'Descripción del slide',
      'imageUrl': '',
      'ctaText': 'Ver más',
      'ctaLink': '/productos',
      'showOverlay': true,
      'overlayOpacity': 0.55,
    });
    _updateSlides(slides);
    setState(() => _selectedSlideIndex = slides.length - 1);
    widget.provider.selectCarouselSlide(
      widget.blockId,
      _selectedSlideIndex,
      slides.length,
    );
  }

  void _removeSlide(int index) {
    final slides = List<Map<String, dynamic>>.from(_slides);
    if (slides.length > 1 && index >= 0 && index < slides.length) {
      slides.removeAt(index);
      _updateSlides(slides);
      final nextIndex = _selectedSlideIndex >= slides.length
          ? slides.length - 1
          : _selectedSlideIndex;
      setState(() => _selectedSlideIndex = nextIndex);
      widget.provider.selectCarouselSlide(
        widget.blockId,
        nextIndex,
        slides.length,
      );
    }
  }

  /// Build slide fields inline (same pattern as VideoBanner)
  Widget _buildSlideFields(Map<String, dynamic> slide) {
    final showOverlay = slide['showOverlay'] ?? true;
    final overlayOpacity =
        (slide['overlayOpacity'] as num?)?.toDouble() ?? 0.55;
    final hasVideoFile = (slide['videoFileUrl']?.toString() ?? '').isNotEmpty;
    final titleFormatting = TextFormatting.fromJson(
      slide['titleFormatting'] is Map
          ? Map<String, dynamic>.from(slide['titleFormatting'] as Map)
          : null,
    );
    final subtitleFormatting = TextFormatting.fromJson(
      slide['subtitleFormatting'] is Map
          ? Map<String, dynamic>.from(slide['subtitleFormatting'] as Map)
          : null,
    );
    final compositionElements = slide['elements'] is List
        ? (slide['elements'] as List)
            .whereType<Map>()
            .map((element) => Map<String, dynamic>.from(element))
            .toList()
        : <Map<String, dynamic>>[];
    final usesComposition =
        slide['useComposition'] == true || compositionElements.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CollapsibleSection(
          title: 'Contenido del slide',
          icon: Icons.edit_note_rounded,
          initiallyExpanded: true,
          children: [
            _EditorToggle(
              label: 'Diseño avanzado por capas',
              value: usesComposition,
              onChanged: (value) => _setCompositionEnabled(slide, value),
            ),
            const SizedBox(height: 8),
            Text(
              usesComposition
                  ? 'Cada texto, imagen, forma y botón es una capa editable. Arrástrala directamente sobre el slide.'
                  : 'Actívalo para crear campañas con composición libre sin perder los controles del editor.',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            const SizedBox(height: 16),
            if (usesComposition) ...[
              _CanvasBlockControls(
                data: <String, dynamic>{
                  ...slide,
                  'elements': compositionElements,
                  'blockHeight':
                      (slide['designHeight'] as num?)?.toDouble() ?? 750.0,
                },
                blockId: widget.blockId,
                provider: widget.provider,
                slideIndex: _selectedSlideIndex,
                elementsOnly: true,
                onElementsChanged: (elements) =>
                    _updateSlide(_selectedSlideIndex, 'elements', elements),
                onCanvasSettingChanged: (key, value) =>
                    _updateSlide(_selectedSlideIndex, key, value),
                onActiveElementChanged: (elementId) =>
                    widget.provider.selectCanvasElement(
                  widget.blockId,
                  elementId,
                  slideIndex: _selectedSlideIndex,
                  slideCount: _slides.length,
                ),
              ),
              _buildNestedLayers(widget.provider.blocks),
              const SizedBox(height: 20),
            ] else ...[
              _EditorTextField(
                label: 'Título',
                value: slide['title']?.toString() ?? '',
                onChanged: (v) => _updateSlide(_selectedSlideIndex, 'title', v),
              ),
              const SizedBox(height: 8),
              TextFormattingToolbar(
                currentFormatting: titleFormatting,
                preset: TextToolbarPreset.basic,
                showAdvancedOptions: false,
                onFormattingChanged: (value) => _updateSlide(
                  _selectedSlideIndex,
                  'titleFormatting',
                  value.toJson(),
                ),
              ),
              const SizedBox(height: 12),
              _EditorTextField(
                label: 'Subtítulo',
                value: slide['subtitle']?.toString() ?? '',
                onChanged: (v) =>
                    _updateSlide(_selectedSlideIndex, 'subtitle', v),
                maxLines: 2,
              ),
              const SizedBox(height: 8),
              TextFormattingToolbar(
                currentFormatting: subtitleFormatting,
                preset: TextToolbarPreset.basic,
                showAdvancedOptions: false,
                onFormattingChanged: (value) => _updateSlide(
                  _selectedSlideIndex,
                  'subtitleFormatting',
                  value.toJson(),
                ),
              ),
              const SizedBox(height: 12),
              WebsiteActionEditor(
                showVariant: true,
                value: WebsiteActionValue.resolvePrimary(
                      slide,
                      labelKeys: const ['ctaText', 'buttonText'],
                      hrefKeys: const ['ctaLink', 'buttonLink'],
                      defaultLabel: 'Ver más',
                      defaultHref: '/productos',
                      defaultVariant: WebsiteActionVariant.outline,
                    ) ??
                    const WebsiteActionValue(
                      label: 'Ver más',
                      href: '/productos',
                      variant: WebsiteActionVariant.outline,
                    ),
                onChanged: (action) => _updateSlideMultiple(
                  _selectedSlideIndex,
                  {
                    'ctaText': action.label,
                    'buttonText': action.label,
                    'ctaLink': action.href,
                    'buttonLink': action.href,
                    'actionVariant': action.variant.storageValue,
                    'actions': WebsiteActionValue.mergePrimary(
                      slide['actions'],
                      action,
                    ),
                  },
                ),
              ),
              const SizedBox(height: 4),
            ],
          ],
        ),
        _CollapsibleSection(
          title: 'Imagen y encuadre',
          icon: Icons.image_outlined,
          initiallyExpanded: !usesComposition,
          children: [
            _ImagePicker(
              currentUrl: slide['imageUrl']?.toString(),
              onChanged: (url) =>
                  _updateSlide(_selectedSlideIndex, 'imageUrl', url),
            ),
            const SizedBox(height: 12),
            const _SectionHeader('Foco de imagen'),
            const SizedBox(height: 8),
            FocalPointPicker(
              imageUrl: slide['imageUrl']?.toString(),
              focalX: (slide['focalPointX'] as num?)?.toDouble() ?? 0.5,
              focalY: (slide['focalPointY'] as num?)?.toDouble() ?? 0.5,
              onChanged: (x, y) {
                _updateSlideMultiple(_selectedSlideIndex, {
                  'focalPointX': x,
                  'focalPointY': y,
                });
              },
            ),
            const SizedBox(height: 12),
            const _SectionHeader('Foco móvil'),
            const SizedBox(height: 8),
            FocalPointPicker(
              imageUrl: slide['imageUrl']?.toString(),
              focalX: (slide['mobileFocalPointX'] as num?)?.toDouble() ?? 0.5,
              focalY: (slide['mobileFocalPointY'] as num?)?.toDouble() ?? 0.5,
              onChanged: (x, y) {
                // Update both values atomically
                _updateSlideMultiple(_selectedSlideIndex, {
                  'mobileFocalPointX': x,
                  'mobileFocalPointY': y,
                });
              },
            ),
            const SizedBox(height: 12),
            _EditorTextField(
              label: 'Texto alternativo',
              value: slide['altText']?.toString() ?? '',
              onChanged: (value) =>
                  _updateSlide(_selectedSlideIndex, 'altText', value),
            ),
          ],
        ),
        _CollapsibleSection(
          title: 'Video de fondo',
          icon: Icons.play_circle_outline_rounded,
          initiallyExpanded:
              hasVideoFile || (slide['videoUrl']?.toString() ?? '').isNotEmpty,
          children: [
            const Text(
              'Si se configura un video, se usará en vez de la imagen',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            const SizedBox(height: 12),

            // Upload/file selection is the primary workflow.
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _uploadSlideVideoFile,
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Subir archivo de video'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00A09D),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),

            // Show current video file if exists
            if (hasVideoFile) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                  border:
                      Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle,
                        color: Colors.green, size: 16),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Archivo de video cargado',
                        style: TextStyle(color: Colors.green, fontSize: 12),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close,
                          size: 16, color: Colors.green),
                      onPressed: () =>
                          _updateSlide(_selectedSlideIndex, 'videoFileUrl', ''),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            _CollapsibleSection(
              title: 'YouTube / enlace avanzado',
              icon: Icons.link_rounded,
              initiallyExpanded:
                  (slide['videoUrl']?.toString() ?? '').isNotEmpty,
              children: [
                _EditorTextField(
                  label: 'URL de YouTube',
                  value: slide['videoUrl']?.toString() ?? '',
                  onChanged: (v) {
                    _updateSlide(_selectedSlideIndex, 'videoUrl', v);
                    if (v.isNotEmpty) {
                      _updateSlide(_selectedSlideIndex, 'videoFileUrl', '');
                    }
                  },
                  hint: 'https://youtube.com/watch?v=...',
                ),
              ],
            ),
          ],
        ),
        _CollapsibleSection(
          title: 'Overlay',
          icon: Icons.gradient_outlined,
          initiallyExpanded: false,
          children: [
            _EditorToggle(
              label: 'Mostrar overlay oscuro',
              value: showOverlay,
              onChanged: (v) =>
                  _updateSlide(_selectedSlideIndex, 'showOverlay', v),
            ),
            if (showOverlay) ...[
              const SizedBox(height: 12),
              _EditorSlider(
                label: 'Opacidad del overlay',
                value: overlayOpacity,
                min: 0.0,
                max: 1.0,
                divisions: 20,
                onChanged: (v) =>
                    _updateSlide(_selectedSlideIndex, 'overlayOpacity', v),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildNestedLayers(List<Map<String, dynamic>> blocks) {
    final selectedId = editProvider.selectedBlockId;
    if (selectedId == null) return const SizedBox.shrink();
    final block = blocks.cast<Map<String, dynamic>?>().firstWhere(
          (candidate) => candidate?['id']?.toString() == selectedId,
          orElse: () => null,
        );
    if (block == null) return const SizedBox.shrink();
    final type = (block['block_type'] ?? block['type'] ?? '').toString();
    final data = Map<String, dynamic>.from(
      block['block_data'] as Map? ?? const <String, dynamic>{},
    );
    var slideIndex = 0;
    List<dynamic> rawElements;
    if (type == WebsiteBlockType.carousel.name) {
      final slides = List<dynamic>.from(data['slides'] as List? ?? const []);
      if (slides.isEmpty) return const SizedBox.shrink();
      slideIndex = editProvider.carouselSlideSelection(
        selectedId,
        slides.length,
      );
      final slide = Map<String, dynamic>.from(slides[slideIndex] as Map? ?? {});
      if (slide['useComposition'] != true) return const SizedBox.shrink();
      rawElements = List<dynamic>.from(slide['elements'] as List? ?? const []);
    } else if (type == WebsiteBlockType.canvas.name) {
      rawElements = List<dynamic>.from(data['elements'] as List? ?? const []);
    } else {
      return const SizedBox.shrink();
    }

    final elements = rawElements
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    if (elements.isEmpty) return const SizedBox.shrink();
    final selectedElementId = editProvider.canvasElementSelection(
      selectedId,
      slideIndex: type == WebsiteBlockType.carousel.name ? slideIndex : null,
    );

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: .08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
            child: Text(
              type == WebsiteBlockType.carousel.name
                  ? 'CAPAS · SLIDE ${slideIndex + 1}'
                  : 'CAPAS DEL CANVAS',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: .8,
              ),
            ),
          ),
          for (var index = elements.length - 1; index >= 0; index--)
            _buildNestedLayerRow(
              blockId: selectedId,
              type: type,
              slideIndex: slideIndex,
              elements: elements,
              index: index,
              selected: elements[index]['id']?.toString() == selectedElementId,
            ),
        ],
      ),
    );
  }

  Widget _buildNestedLayerRow({
    required String blockId,
    required String type,
    required int slideIndex,
    required List<Map<String, dynamic>> elements,
    required int index,
    required bool selected,
  }) {
    final element = elements[index];
    final id = element['id']?.toString() ?? '';
    final elementType = element['type']?.toString() ?? 'element';
    final hidden = element['hidden'] == true;
    final locked = element['locked'] == true;
    final label = (element['name'] ??
            element['text'] ??
            element['label'] ??
            element['title'] ??
            _canvasElementLabel(elementType))
        .toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: selected
            ? const Color(0xFF00A09D).withValues(alpha: .14)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
      ),
      child: InkWell(
        onTap: () => editProvider.selectCanvasElement(
          blockId,
          id,
          slideIndex:
              type == WebsiteBlockType.carousel.name ? slideIndex : null,
        ),
        borderRadius: BorderRadius.circular(7),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Row(
            children: [
              Icon(_canvasElementIcon(elementType),
                  size: 15,
                  color: selected ? const Color(0xFF00A09D) : Colors.white54),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: hidden ? Colors.white30 : Colors.white70,
                    fontSize: 11,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: hidden ? 'Mostrar capa' : 'Ocultar capa',
                onPressed: () => _patchNestedLayer(
                  blockId: blockId,
                  type: type,
                  slideIndex: slideIndex,
                  elements: elements,
                  index: index,
                  key: 'hidden',
                  value: !hidden,
                ),
                icon: Icon(hidden ? Icons.visibility_off : Icons.visibility,
                    size: 15, color: Colors.white38),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: locked ? 'Desbloquear capa' : 'Bloquear capa',
                onPressed: () => _patchNestedLayer(
                  blockId: blockId,
                  type: type,
                  slideIndex: slideIndex,
                  elements: elements,
                  index: index,
                  key: 'locked',
                  value: !locked,
                ),
                icon: Icon(locked ? Icons.lock : Icons.lock_open,
                    size: 15, color: Colors.white38),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _patchNestedLayer({
    required String blockId,
    required String type,
    required int slideIndex,
    required List<Map<String, dynamic>> elements,
    required int index,
    required String key,
    required dynamic value,
  }) {
    final updated =
        elements.map((element) => Map<String, dynamic>.from(element)).toList();
    updated[index][key] = value;
    if (type == WebsiteBlockType.canvas.name) {
      editProvider.updateBlockData(blockId, 'elements', updated);
      return;
    }
    final block = editProvider.blocks.firstWhere(
      (candidate) => candidate['id']?.toString() == blockId,
    );
    final data = Map<String, dynamic>.from(block['block_data'] as Map? ?? {});
    final slides = List<dynamic>.from(data['slides'] as List? ?? const []);
    final slide = Map<String, dynamic>.from(slides[slideIndex] as Map? ?? {});
    slides[slideIndex] = {...slide, 'elements': updated};
    editProvider.updateBlockData(blockId, 'slides', slides);
  }

  static IconData _canvasElementIcon(String type) => switch (type) {
        'text' => Icons.text_fields_rounded,
        'button' => Icons.smart_button_rounded,
        'image' => Icons.image_outlined,
        'shape' => Icons.rectangle_outlined,
        'product' => Icons.inventory_2_outlined,
        'productsGallery' => Icons.grid_view_rounded,
        _ => Icons.layers_outlined,
      };

  static String _canvasElementLabel(String type) => switch (type) {
        'text' => 'Texto',
        'button' => 'Botón',
        'image' => 'Imagen',
        'shape' => 'Forma',
        'product' => 'Producto',
        'productsGallery' => 'Galería de productos',
        _ => 'Elemento',
      };

  Future<void> _uploadSlideVideoFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error: No se pudo leer el archivo')),
          );
        }
        return;
      }

      // Get tenant ID
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Usuario no autenticado');

      final profileResponse = await Supabase.instance.client
          .from('user_profiles')
          .select('tenant_id')
          .eq('user_id', user.id)
          .single();

      final tenantId = profileResponse['tenant_id'] as String;

      // Upload to Supabase Storage
      final fileName =
          'video_${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final storagePath = '$tenantId/videos/$fileName';

      await Supabase.instance.client.storage
          .from('website-assets')
          .uploadBinary(storagePath, file.bytes!,
              fileOptions: FileOptions(
                contentType: file.extension == 'mp4'
                    ? 'video/mp4'
                    : 'video/${file.extension ?? 'mp4'}',
              ));

      // Get public URL
      final publicUrl = Supabase.instance.client.storage
          .from('website-assets')
          .getPublicUrl(storagePath);

      _updateSlide(_selectedSlideIndex, 'videoFileUrl', publicUrl);
      // Clear the YouTube URL if uploading a file
      _updateSlide(_selectedSlideIndex, 'videoUrl', '');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Video subido correctamente'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('[CarouselSlide] Error uploading video: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al subir video: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final slides = _slides;
    final sharedSelection =
        widget.provider.carouselSlideSelection(widget.blockId, slides.length);
    if (sharedSelection != _selectedSlideIndex) {
      _selectedSlideIndex = sharedSelection;
    }
    final autoPlay = widget.data['autoPlay'] ?? true;
    final intervalSeconds =
        (widget.data['intervalSeconds'] as num?)?.toInt() ?? 5;
    final showIndicators = widget.data['showIndicators'] ?? true;
    final showArrows = widget.data['showArrows'] ?? true;
    final animation = widget.data['animation']?.toString() ?? 'slide';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CollapsibleSection(
          title: 'Comportamiento del carrusel',
          icon: Icons.motion_photos_auto_outlined,
          initiallyExpanded: false,
          children: [
            _EditorToggle(
              label: 'Reproducción automática',
              value: autoPlay,
              onChanged: (v) => widget.provider
                  .updateBlockData(widget.blockId, 'autoPlay', v),
            ),
            const SizedBox(height: 12),
            if (autoPlay) ...[
              _EditorSlider(
                label: 'Intervalo (segundos)',
                value: intervalSeconds.toDouble(),
                min: 2,
                max: 15,
                divisions: 13,
                onChanged: (v) => widget.provider.updateBlockData(
                    widget.blockId, 'intervalSeconds', v.toInt()),
              ),
              const SizedBox(height: 12),
            ],
            _EditorSlider(
              label: 'Duración animación (ms)',
              value: (widget.data['animationDurationMs'] as num?)?.toDouble() ??
                  600,
              min: 200,
              max: 2000,
              divisions: 18, // (2000-200)/100 = 18 steps of 100ms
              onChanged: (v) => widget.provider.updateBlockDataMultiple(
                widget.blockId,
                {
                  'animationDurationMs': v.toInt(),
                  // Keep legacy field in sync until all persisted data is normalized.
                  'transitionDuration': v.toInt(),
                },
              ),
            ),
            const SizedBox(height: 12),
            _EditorDropdown(
              label: 'Animación',
              value: animation,
              options: const [
                ('slide', 'Deslizar'),
                ('fade', 'Desvanecer'),
                ('zoom', 'Zoom'),
              ],
              onChanged: (v) => widget.provider
                  .updateBlockData(widget.blockId, 'animation', v),
            ),
            const SizedBox(height: 12),
            _EditorToggle(
              label: 'Mostrar indicadores',
              value: showIndicators,
              onChanged: (v) => widget.provider
                  .updateBlockData(widget.blockId, 'showIndicators', v),
            ),
            const SizedBox(height: 12),
            _EditorToggle(
              label: 'Mostrar flechas',
              value: showArrows,
              onChanged: (v) => widget.provider
                  .updateBlockData(widget.blockId, 'showArrows', v),
            ),
          ],
        ),
        _CollapsibleSection(
          title: 'Slides (${slides.length})',
          icon: Icons.view_carousel_outlined,
          initiallyExpanded: true,
          children: [
            Row(
              children: [
                const Expanded(child: _SectionHeader('Slides')),
                InkWell(
                  onTap: _addSlide,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00A09D).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 14, color: Color(0xFF00A09D)),
                        SizedBox(width: 4),
                        Text('Agregar',
                            style: TextStyle(
                                color: Color(0xFF00A09D), fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Slide tabs
            if (slides.isNotEmpty) ...[
              SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: slides.length,
                  itemBuilder: (context, index) {
                    final isSelected = index == _selectedSlideIndex;
                    return GestureDetector(
                      onTap: () => _selectSlide(index),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF00A09D)
                              : Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Slide ${index + 1}',
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white70
                                    : Colors.white70,
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                            if (slides.length > 1) ...[
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () => _removeSlide(index),
                                child: Icon(
                                  Icons.close,
                                  size: 14,
                                  color: isSelected
                                      ? Colors.white70
                                      : Colors.white38,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Selected slide editor - INLINE fields (not nested StatefulWidget)
              if (_selectedSlideIndex < slides.length)
                _buildSlideFields(slides[_selectedSlideIndex]),
            ] else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(Icons.image_outlined,
                          size: 40, color: Colors.white.withValues(alpha: 0.3)),
                      const SizedBox(height: 12),
                      Text(
                        'No hay slides',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5)),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _addSlide,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Agregar slide'),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Individual slide editor - now supports video backgrounds
class _SlideEditor extends StatefulWidget {
  final Map<String, dynamic> slide;
  final void Function(String key, dynamic value) onUpdate;

  const _SlideEditor({
    required this.slide,
    required this.onUpdate,
  });

  @override
  State<_SlideEditor> createState() => _SlideEditorState();
}

class _SlideEditorState extends State<_SlideEditor> {
  bool _isUploading = false;

  Future<void> _uploadVideoFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error: No se pudo leer el archivo')),
          );
        }
        return;
      }

      setState(() => _isUploading = true);

      // Get tenant ID
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Usuario no autenticado');

      final profileResponse = await Supabase.instance.client
          .from('user_profiles')
          .select('tenant_id')
          .eq('user_id', user.id)
          .single();

      final tenantId = profileResponse['tenant_id'] as String;

      // Upload to Supabase Storage
      final fileName =
          'carousel_video_${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final storagePath = '$tenantId/videos/$fileName';

      await Supabase.instance.client.storage
          .from('website-assets')
          .uploadBinary(storagePath, file.bytes!,
              fileOptions: FileOptions(
                contentType: file.extension == 'mp4'
                    ? 'video/mp4'
                    : 'video/${file.extension ?? 'mp4'}',
              ));

      // Get public URL
      final publicUrl = Supabase.instance.client.storage
          .from('website-assets')
          .getPublicUrl(storagePath);

      widget.onUpdate('videoFileUrl', publicUrl);
      // Clear the YouTube URL if uploading a file
      widget.onUpdate('videoUrl', '');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Video subido correctamente'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('[SlideEditor] Error uploading video: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al subir video: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final showOverlay = widget.slide['showOverlay'] ?? true;
    final overlayOpacity =
        (widget.slide['overlayOpacity'] as num?)?.toDouble() ?? 0.55;
    final hasVideoFile =
        (widget.slide['videoFileUrl']?.toString() ?? '').isNotEmpty;
    final hasYoutubeUrl =
        (widget.slide['videoUrl']?.toString() ?? '').isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _EditorTextField(
          label: 'Título',
          value: widget.slide['title']?.toString() ?? '',
          onChanged: (v) => widget.onUpdate('title', v),
        ),
        const SizedBox(height: 12),
        _EditorTextField(
          label: 'Subtítulo',
          value: widget.slide['subtitle']?.toString() ?? '',
          onChanged: (v) => widget.onUpdate('subtitle', v),
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        const _SectionHeader('Imagen de fondo'),
        const SizedBox(height: 8),
        _ImagePicker(
          currentUrl: widget.slide['imageUrl']?.toString(),
          onChanged: (url) => widget.onUpdate('imageUrl', url),
        ),

        const SizedBox(height: 20),
        // Video section
        const Text('VIDEO DE FONDO (OPCIONAL)',
            style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1)),
        const SizedBox(height: 8),
        const Text(
          'Si se configura un video, se usará en vez de la imagen',
          style: TextStyle(color: Colors.white38, fontSize: 11),
        ),
        const SizedBox(height: 12),

        // Upload/file selection is the primary workflow.
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isUploading ? null : _uploadVideoFile,
            icon: _isUploading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.upload_file, size: 18),
            label:
                Text(_isUploading ? 'Subiendo...' : 'Subir archivo de video'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00A09D),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),

        // Show current video file if exists
        if (hasVideoFile) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Archivo de video cargado',
                    style: TextStyle(color: Colors.green, fontSize: 12),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: Colors.red.shade300, size: 18),
                  onPressed: () => widget.onUpdate('videoFileUrl', ''),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Eliminar video',
                ),
              ],
            ),
          ),
        ],

        // Show YouTube status if exists
        if (hasYoutubeUrl && !hasVideoFile) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.play_circle_filled,
                    color: Colors.red, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Video de YouTube configurado',
                    style: TextStyle(color: Colors.red.shade200, fontSize: 12),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: Colors.red.shade300, size: 18),
                  onPressed: () => widget.onUpdate('videoUrl', ''),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Eliminar video',
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        _CollapsibleSection(
          title: 'YouTube / enlace avanzado',
          icon: Icons.link_rounded,
          initiallyExpanded: hasYoutubeUrl,
          children: [
            _EditorTextField(
              label: 'URL de YouTube',
              value: widget.slide['videoUrl']?.toString() ?? '',
              onChanged: (v) {
                widget.onUpdate('videoUrl', v);
                if (v.isNotEmpty) {
                  widget.onUpdate('videoFileUrl', '');
                }
              },
              hint: 'https://youtube.com/watch?v=...',
            ),
          ],
        ),

        const SizedBox(height: 20),
        _EditorToggle(
          label: 'Mostrar overlay oscuro',
          value: showOverlay,
          onChanged: (v) => widget.onUpdate('showOverlay', v),
        ),
        if (showOverlay) ...[
          const SizedBox(height: 12),
          _EditorSlider(
            label: 'Opacidad del overlay',
            value: overlayOpacity,
            min: 0.1,
            max: 0.9,
            divisions: 8,
            onChanged: (v) => widget.onUpdate('overlayOpacity', v),
          ),
        ],
        const SizedBox(height: 16),
        const _SectionHeader('Botón'),
        const SizedBox(height: 8),
        WebsiteActionEditor(
          showVariant: true,
          value: WebsiteActionValue.resolvePrimary(
                widget.slide,
                labelKeys: const ['ctaText', 'buttonText'],
                hrefKeys: const ['ctaLink', 'buttonLink'],
                defaultLabel: 'Ver más',
                defaultHref: '/productos',
                defaultVariant: WebsiteActionVariant.outline,
              ) ??
              const WebsiteActionValue(
                label: 'Ver más',
                href: '/productos',
                variant: WebsiteActionVariant.outline,
              ),
          onChanged: (action) {
            widget.onUpdate('ctaText', action.label);
            widget.onUpdate('buttonText', action.label);
            widget.onUpdate('ctaLink', action.href);
            widget.onUpdate('buttonLink', action.href);
            widget.onUpdate('actionVariant', action.variant.storageValue);
            widget.onUpdate(
              'actions',
              WebsiteActionValue.mergePrimary(
                widget.slide['actions'],
                action,
              ),
            );
          },
        ),
      ],
    );
  }
}
