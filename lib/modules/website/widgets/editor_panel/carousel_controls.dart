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

  /// "Diseño avanzado por capas".
  ///
  /// Turning it on for the first time is a document INITIALISATION, and it
  /// belongs to the provider: one atomic command, one history entry, one
  /// identity per semantic element with its phone geometry recorded as a typed
  /// `responsive.mobile` override. This surface no longer injects an `elements`
  /// list of its own, and it can no longer generate the `_desktop`/`_mobile`
  /// twins — with their contradictory `hideOnMobile`/`showOnMobile` flags —
  /// that the canonical model replaced.
  ///
  /// On an already composed slide the toggle is just a property of the Canvas
  /// document, so it goes through the same Canvas command as every other one.
  void _setCompositionEnabled(Map<String, dynamic> slide, bool enabled) {
    final existing = slide['elements'];
    final composed = slide['useComposition'] == true ||
        (existing is List && existing.isNotEmpty);

    if (composed) {
      widget.provider.setCanvasRootProperties(
        widget.blockId,
        <String, Object?>{'useComposition': enabled},
        slideIndex: _selectedSlideIndex,
        scope: WebsiteWriteScope.shared,
        viewport: widget.provider.previewViewport,
      );
      return;
    }
    if (!enabled) return;

    widget.provider.initializeCanvasComposition(
      widget.blockId,
      slideIndex: _selectedSlideIndex,
    );
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
    // Both overlay properties resolve through the canonical binding, so the
    // inspector shows — and gates on — the value the renderer will use for the
    // previewed viewport, not the shared one.
    final overlayToggle = _slideScalarBinding<bool>(
      slide: slide,
      fieldPath: 'slides.showOverlay',
      decode: WebsiteResponsiveScalarBinding.decodeBoolean,
    );
    final overlayOpacityBinding = _slideScalarBinding<num>(
      slide: slide,
      fieldPath: 'slides.overlayOpacity',
      decode: WebsiteResponsiveScalarBinding.decodeNumber,
    );
    final showOverlay = overlayToggle?.value ?? true;
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
    // Whether this slide is a Canvas at all — the same condition the Canvas
    // commands validate. The layers themselves are read by the inspector from
    // the document, never copied out into this widget.
    final slideLayers = slide['elements'];
    final usesComposition = slide['useComposition'] == true ||
        (slideLayers is List && slideLayers.isNotEmpty);

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
              // The Canvas inspector owns its own document: it addresses this
              // exact slide and writes through the Canvas commands, so nothing
              // here rebuilds `elements` or `slides` on its behalf.
              _CanvasBlockControls(
                blockId: widget.blockId,
                provider: widget.provider,
                slideIndex: _selectedSlideIndex,
                elementsOnly: true,
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
            // Same owner as the generic schema path: one media row, one focal
            // editor on demand, for the viewport being previewed. The separate
            // "Foco móvil" editor is gone, and with it the divergent rule that
            // made the inspector disagree with the renderer.
            _buildSlideMedia(slide),
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
            // Same protocol as the generic inspector: the slide's overlay is a
            // presentation property of THIS item, so it resolves and writes
            // through the canonical repeater binding instead of `_updateSlide`,
            // which always wrote the shared value.
            _mountSlideField<bool>(
              overlayToggle,
              (binding) => _EditorToggle(
                label: '',
                value: binding.value ?? true,
                onChanged: binding.write,
              ),
            ),
            if (showOverlay) ...[
              const SizedBox(height: 12),
              _mountSlideField<num>(
                overlayOpacityBinding,
                (binding) {
                  final value =
                      (binding.value?.toDouble() ?? 0.55).clamp(0.0, 1.0);
                  return _EditorSlider(
                    label: '',
                    value: value,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    valueLabel: value.toStringAsFixed(2),
                    onChanged: binding.write,
                  );
                },
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
    int? slideIndex;
    if (type == WebsiteBlockType.carousel.name) {
      final slides = List<dynamic>.from(data['slides'] as List? ?? const []);
      if (slides.isEmpty) return const SizedBox.shrink();
      slideIndex = editProvider.carouselSlideSelection(
        selectedId,
        slides.length,
      );
      final slide = Map<String, dynamic>.from(slides[slideIndex] as Map? ?? {});
      if (slide['useComposition'] != true) return const SizedBox.shrink();
    } else if (type != WebsiteBlockType.canvas.name) {
      return const SizedBox.shrink();
    }

    // The list is the PROJECTED one: the rows show what the previewed viewport
    // resolves, in the z-order that viewport really draws.
    final document = editProvider.canvasDocument(
      selectedId,
      slideIndex: slideIndex,
    );
    if (document == null) return const SizedBox.shrink();
    final legacy = WebsiteCanvasLegacyInventory.of(document);
    final layers = WebsiteCanvasResponsiveDocument.projectLayers(
      data: document,
      viewport: editProvider.previewViewport,
    );
    if (layers.isEmpty) return const SizedBox.shrink();
    final selectedElementId = editProvider.canvasElementSelection(
      selectedId,
      slideIndex: slideIndex,
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
              slideIndex == null
                  ? 'CAPAS DEL CANVAS'
                  : 'CAPAS · SLIDE ${slideIndex + 1}',
              style: const TextStyle(
                color: Colors.white38,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: .8,
              ),
            ),
          ),
          for (var index = layers.length - 1; index >= 0; index--)
            _buildNestedLayerRow(
              blockId: selectedId,
              slideIndex: slideIndex,
              legacy: legacy,
              layer: layers[index],
              selected: layers[index].id == selectedElementId,
            ),
        ],
      ),
    );
  }

  Widget _buildNestedLayerRow({
    required String blockId,
    required int? slideIndex,
    required WebsiteCanvasLegacyInventory legacy,
    required WebsiteCanvasLayerProjection layer,
    required bool selected,
  }) {
    final id = layer.id;
    final element = layer.data;
    final elementType = element['type']?.toString() ?? 'element';
    final locked = element['locked'] == true;
    // Visibility is the typed property, resolved for the previewed viewport.
    // The old `hidden` flag was written by this row and read by nothing.
    final hidden = !layer.visible;
    final label = (element['name'] ??
            element['text'] ??
            element['label'] ??
            element['title'] ??
            _canvasElementLabel(elementType))
        .toString();

    WebsiteCanvasFieldBinding<bool>? toggle(String propertyKey, String label) {
      return WebsiteCanvasFieldBinding.resolve<bool>(
        provider: editProvider,
        blockId: blockId,
        slideIndex: slideIndex,
        layerId: id,
        propertyKey: propertyKey,
        label: label,
        decode: WebsiteResponsiveScalarBinding.decodeBoolean,
        type: WebsiteBlockFieldType.toggle,
        legacyInventory: legacy,
      );
    }

    final visibility = toggle(
      WebsiteCanvasResponsivePolicy.visibleKey,
      'Mostrar esta capa',
    );
    final lock = toggle('locked', 'Bloquear ajustes directos');
    // A value that still reaches this layer through a legacy twin or alias is
    // readable, not writable: which branch the write belongs in is exactly the
    // ambiguity the deliberate migration resolves.
    final visibilityBlocked = visibility == null ||
        visibility.state.status == WebsiteResponsiveFieldStatus.unavailable;
    final lockBlocked = lock == null ||
        lock.state.status == WebsiteResponsiveFieldStatus.unavailable;

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
          slideIndex: slideIndex,
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
                tooltip: visibilityBlocked
                    ? 'Esta capa viene de una configuración anterior. '
                        'Revísala en la migración antes de cambiarla.'
                    : hidden
                        ? 'Mostrar capa'
                        : 'Ocultar capa',
                onPressed:
                    visibilityBlocked ? null : () => visibility.write(hidden),
                icon: Icon(hidden ? Icons.visibility_off : Icons.visibility,
                    size: 15,
                    color: visibilityBlocked ? Colors.white24 : Colors.white38),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: lockBlocked
                    ? 'Esta capa viene de una configuración anterior. '
                        'Revísala en la migración antes de cambiarla.'
                    : locked
                        ? 'Desbloquear capa'
                        : 'Bloquear capa',
                onPressed: lockBlocked ? null : () => lock.write(!locked),
                icon: Icon(locked ? Icons.lock : Icons.lock_open,
                    size: 15,
                    color: lockBlocked ? Colors.white24 : Colors.white38),
              ),
            ],
          ),
        ),
      ),
    );
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

  /// The active slide's image and framing, through the shared binding.
  ///
  /// The slide is addressed by its stable `id` when it has one, with the index
  /// as the positional fallback, so a reorder cannot land a write on the wrong
  /// slide. Everything else about the slide — Canvas, video, CTA, add/remove
  /// and reorder — is untouched.
  /// The selected slide as a responsive owner.
  ///
  /// Identity is used when the slide already has one; otherwise the explicit
  /// index addresses it. Nothing is invented and no document is migrated.
  WebsiteResponsiveRepeaterField _slideOwner(Map<String, dynamic> slide) {
    return WebsiteResponsiveRepeaterField.forItem(
      collectionKeys: const <String>['slides'],
      itemIndex: _selectedSlideIndex,
      item: slide,
    );
  }

  WebsiteAuthoringHostClass get _hostClass =>
      WebsiteEditorChromeScope.maybeOf(context)?.hostClass ??
      WebsiteAuthoringHostClass.desktop;

  /// Binds one non-media slide property through the canonical scalar owner.
  ///
  /// Null only when the registry has no such field, which would be a schema
  /// bug rather than a state to render.
  WebsiteResponsiveScalarBinding<T>? _slideScalarBinding<T>({
    required Map<String, dynamic> slide,
    required String fieldPath,
    required WebsiteResponsiveDecoder<T> decode,
  }) {
    final field = WebsiteBlockRegistry.fieldForPath(
      WebsiteBlockType.carousel,
      fieldPath,
    );
    if (field == null) return null;

    return WebsiteResponsiveScalarBinding<T>.forField(
      provider: widget.provider,
      blockId: widget.blockId,
      field: field,
      owner: _slideOwner(slide),
      decode: decode,
      hostClass: _hostClass,
    );
  }

  /// Mounts a slide control under the canonical inheritance shell.
  ///
  /// The control carries an EMPTY label: `ResponsiveFieldShell` owns label,
  /// help, status, scope sentence and the customize/reset action, and a second
  /// label for the same field is exactly the duplication the protocol removes.
  Widget _mountSlideField<T>(
    WebsiteResponsiveScalarBinding<T>? binding,
    Widget Function(WebsiteResponsiveScalarBinding<T> binding) build,
  ) {
    if (binding == null) return const SizedBox.shrink();
    return ResponsiveFieldShell<T>(
      state: binding.state,
      onCustomize: binding.customize,
      onReset: binding.reset,
      child: build(binding),
    );
  }

  Widget _buildSlideMedia(Map<String, dynamic> slide) {
    final field = WebsiteBlockRegistry.fieldForPath(
      WebsiteBlockType.carousel,
      'slides.imageUrl',
    );
    if (field == null) return const SizedBox.shrink();

    final owner = _slideOwner(slide);

    final binding = WebsiteResponsiveMediaBinding.repeaterItem(
      provider: widget.provider,
      blockId: widget.blockId,
      field: field,
      collectionKeys: owner.collectionKeys,
      itemIndex: owner.itemIndex,
      identityKey: owner.identityKey,
      identityValue: owner.identityValue,
      hostClass: _hostClass,
    );

    return ResponsiveMediaField(
      state: binding.urlState,
      focalState: binding.focalState,
      onChanged: binding.writeUrl,
      onFocalChanged: binding.writeFocal,
      onCustomize: binding.customizeUrl,
      onReset: binding.resetUrl,
      onFocalCustomize: binding.customizeFocal,
      onFocalReset: binding.resetFocal,
    );
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
