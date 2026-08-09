part of '../website_editor_panel.dart';

/// One Canvas document, resolved once for the surface that is editing it.
///
/// Everything the inspector shows comes from here: the effective root values
/// and the layers already placed in the previewed viewport's own z-order,
/// never the raw persisted map. The legacy inventory is resolved once too —
/// a full migration analysis per field would otherwise run dozens of times per
/// rebuild for one answer that belongs to the document, not to the field.
class _CanvasSurface {
  _CanvasSurface({
    required this.provider,
    required this.blockId,
    required this.slideIndex,
    required this.document,
  })  : viewport = provider.previewViewport,
        legacy = WebsiteCanvasLegacyInventory.of(document),
        root = WebsiteCanvasResponsiveDocument.project(
          data: document,
          viewport: provider.previewViewport,
        ),
        layers = WebsiteCanvasResponsiveDocument.projectLayers(
          data: document,
          viewport: provider.previewViewport,
        );

  final WebsiteEditModeProvider provider;
  final String blockId;

  /// Null addresses a standalone Canvas block; any other value addresses the
  /// Canvas of that exact carousel slide.
  final int? slideIndex;

  final Map<String, dynamic> document;
  final WebsiteViewport viewport;
  final WebsiteCanvasLegacyInventory legacy;

  /// Root values already resolved for [viewport].
  final Map<String, dynamic> root;

  /// Layers in the EFFECTIVE order of [viewport], values already resolved.
  final List<WebsiteCanvasLayerProjection> layers;

  WebsiteCanvasLayerProjection? layer(String? layerId) {
    final id = layerId?.trim() ?? '';
    if (id.isEmpty) return null;
    for (final layer in layers) {
      if (layer.id == id) return layer;
    }
    return null;
  }

  /// The layer's slot in the effective order, or -1.
  int slotOf(String layerId) =>
      layers.indexWhere((layer) => layer.id == layerId.trim());

  /// The layer exactly as persisted — no override applied.
  ///
  /// Reserved for the companions that must stay COMMON while a viewport is
  /// previewed: rebuilding the `actions` mirror from the projected variant
  /// would record the phone's presentation as the shared one.
  Map<String, dynamic>? sharedLayer(String layerId) {
    final raw = document[WebsiteCanvasResponsivePolicy.elementsKey];
    if (raw is! List) return null;
    final id = layerId.trim();
    for (final item in raw) {
      if (item is Map && item['id']?.toString().trim() == id) {
        return Map<String, dynamic>.from(
          item.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    }
    return null;
  }

  double rootNumber(String key, double fallback) =>
      (root[key] as num?)?.toDouble() ?? fallback;

  /// The one authority for a Canvas property, root or layer.
  WebsiteCanvasFieldBinding<T>? field<T>(
    String propertyKey, {
    required String label,
    required WebsiteResponsiveDecoder<T> decode,
    String? layerId,
    WebsiteBlockFieldType type = WebsiteBlockFieldType.text,
  }) {
    return WebsiteCanvasFieldBinding.resolve<T>(
      provider: provider,
      blockId: blockId,
      slideIndex: slideIndex,
      layerId: layerId,
      propertyKey: propertyKey,
      label: label,
      decode: decode,
      type: type,
      legacyInventory: legacy,
    );
  }

  WebsiteCanvasFieldBinding<num>? number(
    String propertyKey, {
    required String label,
    String? layerId,
  }) =>
      field<num>(
        propertyKey,
        label: label,
        layerId: layerId,
        decode: WebsiteResponsiveScalarBinding.decodeNumber,
        type: WebsiteBlockFieldType.number,
      );

  WebsiteCanvasFieldBinding<bool>? boolean(
    String propertyKey, {
    required String label,
    String? layerId,
  }) =>
      field<bool>(
        propertyKey,
        label: label,
        layerId: layerId,
        decode: WebsiteResponsiveScalarBinding.decodeBoolean,
        type: WebsiteBlockFieldType.toggle,
      );

  WebsiteCanvasFieldBinding<String>? text(
    String propertyKey, {
    required String label,
    String? layerId,
    WebsiteBlockFieldType type = WebsiteBlockFieldType.text,
  }) =>
      field<String>(
        propertyKey,
        label: label,
        layerId: layerId,
        decode: WebsiteResponsiveScalarBinding.decodeText,
        type: type,
      );

  WebsiteCanvasFieldBinding<String>? color(
    String propertyKey, {
    required String label,
    String? layerId,
  }) =>
      field<String>(
        propertyKey,
        label: label,
        layerId: layerId,
        decode: WebsiteResponsiveScalarBinding.decodeColor,
        type: WebsiteBlockFieldType.color,
      );
}

/// Controls for the free-position Canvas block (Wix-like).
///
/// The inspector owns no document of its own: it addresses one Canvas by
/// `blockId` + `slideIndex`, reads every visible value from the 7A projection
/// for the previewed viewport, and writes exclusively through
/// [WebsiteCanvasFieldBinding] and the provider's atomic Canvas commands.
/// There is deliberately no callback that hands a rebuilt `elements` or
/// `slides` list back to a host: replacing a list overwrites the responsive
/// overrides that live inside the layers it replaces.
class _CanvasBlockControls extends StatelessWidget {
  final String blockId;
  final WebsiteEditModeProvider provider;
  final int? slideIndex;
  final bool elementsOnly;
  final bool selectedElementOnly;
  final _InspectorSection? inspectorSection;

  const _CanvasBlockControls({
    required this.blockId,
    required this.provider,
    this.slideIndex,
    this.elementsOnly = false,
    this.selectedElementOnly = false,
    this.inspectorSection,
  });

  String? _activeElementId() {
    final id = provider
        .canvasElementSelection(blockId, slideIndex: slideIndex)
        ?.toString();
    if (id == null || id.trim().isEmpty) return null;
    return id.trim();
  }

  int? _slideCount() {
    if (slideIndex == null) return null;
    final block = provider.getBlock(blockId);
    final slides = (block?['block_data'] as Map?)?['slides'];
    return slides is List ? slides.length : null;
  }

  void _setActive(String? id) {
    provider.selectCanvasElement(
      blockId,
      id,
      slideIndex: slideIndex,
      slideCount: _slideCount(),
    );
  }

  /// Mounts one control under the canonical inheritance shell.
  ///
  /// The control carries an EMPTY label: `ResponsiveFieldShell` owns label,
  /// status, scope sentence and the customize/reset action, and a second label
  /// for the same field is exactly the duplication the protocol removes.
  Widget _mount<T>(
    WebsiteCanvasFieldBinding<T>? binding,
    Widget Function(WebsiteCanvasFieldBinding<T> binding) build,
  ) {
    if (binding == null) return const SizedBox.shrink();
    return ResponsiveFieldShell<T>(
      state: binding.state,
      onCustomize: binding.customize,
      onReset: binding.reset,
      child: build(binding),
    );
  }

  WebsiteAsyncFieldBinding _asyncFieldBinding<T>(
    WebsiteCanvasFieldBinding<T> binding,
  ) {
    return WebsiteAsyncFieldBinding.pageBlock(
      provider: provider,
      target: WebsiteAsyncFieldTarget.block(
        blockId: blockId,
        // `scopeKey` is the Canvas owner's canonical semantic address:
        // block + slide + root/layer + property + viewport. Keeping it intact
        // means a retained picker or slider can never adopt a sibling layer.
        scopeKey: jsonEncode(<String, Object?>{
          'surface': 'canvas',
          'field': binding.scopeKey,
        }),
      ),
    );
  }

  /// The two framing axes presented as ONE value.
  ///
  /// The status is the strongest of the two, so a single overridden axis still
  /// reads as customised instead of looking inherited.
  WebsiteResponsiveFieldState<Offset> _framingState({
    required WebsiteCanvasFieldBinding<num> x,
    required WebsiteCanvasFieldBinding<num> y,
    required String label,
  }) {
    Offset? pair(num? a, num? b) {
      if (a == null && b == null) return null;
      return Offset(a?.toDouble() ?? 0.5, b?.toDouble() ?? 0.5);
    }

    return WebsiteResponsiveFieldState<Offset>.resolve(
      schema: WebsiteBlockFieldSchema(
        key: 'focalPoint',
        label: label,
        type: WebsiteBlockFieldType.number,
        responsivePolicy: WebsiteResponsivePropertyPolicy.perViewportGeometry,
      ),
      context: x.state.context,
      resolved: WebsiteResolvedResponsiveValue<Offset>(
        shared: pair(x.state.resolved.shared, y.state.resolved.shared),
        value: pair(x.state.resolved.value, y.state.resolved.value),
        viewport: x.state.resolved.viewport,
        isOverride: x.state.resolved.isOverride || y.state.resolved.isOverride,
        isLegacyOverride: x.state.resolved.isLegacyOverride ||
            y.state.resolved.isLegacyOverride,
      ),
      unavailableReason: x.state.unavailableReason ?? y.state.unavailableReason,
    );
  }

  /// The ONE focal control, always contextual to the previewed viewport.
  ///
  /// There is no second "Foco móvil" editor and no separate desktop/mobile
  /// pair: the phone's framing IS this control while the phone is previewed,
  /// and the shell's badge says whether the value is inherited or its own.
  /// `x` and `y` travel in a single [WebsiteCanvasFieldBinding.writeMany], so
  /// one reframe is one history entry and one undo.
  Widget _focalControl({
    required _CanvasSurface surface,
    required String imageUrl,
    required String label,
    String? layerId,
  }) {
    final x = surface.number('focalPointX', label: label, layerId: layerId);
    final y = surface.number('focalPointY', label: label, layerId: layerId);
    if (x == null || y == null) return const SizedBox.shrink();

    return _CanvasFocalField(
      state: _framingState(x: x, y: y, label: label),
      imageUrl: imageUrl,
      asyncBinding: _asyncFieldBinding(x),
      onChanged: (nextX, nextY) => x.writeMany(<String, Object?>{
        'focalPointX': nextX,
        'focalPointY': nextY,
      }),
      onCustomize: () {
        x.customize();
        y.customize();
      },
      onReset: () {
        x.reset();
        y.reset();
      },
    );
  }

  Widget _inspectorLayoutAction({
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    Key? key,
  }) {
    return Expanded(
      child: OutlinedButton.icon(
        key: key,
        onPressed: onPressed,
        icon: Icon(icon, size: 16),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10.5),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 7),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }

  /// Moves the active layer to [slot] of the EFFECTIVE order.
  ///
  /// Shared scope moves it in the persisted list; a promoted phone or tablet
  /// field records the typed `order` exception instead and leaves the base
  /// order — and every other viewport — exactly where it was.
  void _reorder(
    _CanvasSurface surface,
    WebsiteCanvasFieldBinding<num> order,
    String layerId,
    int slot,
  ) {
    provider.reorderCanvasLayer(
      blockId,
      layerId,
      slot,
      slideIndex: slideIndex,
      scope: order.state.effectiveWriteScope,
      viewport: surface.viewport,
    );
  }

  void _alignToCanvas(
    _CanvasSurface surface,
    WebsiteCanvasLayerProjection active,
    String alignment,
  ) {
    final geometry = surface.number('x', label: 'X', layerId: active.id);
    if (geometry == null) return;

    final width = (active.data['w'] as num?)?.toDouble() ?? 200;
    final height = (active.data['h'] as num?)?.toDouble() ?? 56;
    final designWidth = surface.rootNumber('designWidth', 1200);
    final designHeight = surface.rootNumber(
      'designHeight',
      surface.rootNumber('blockHeight', 750),
    );
    var x = (active.data['x'] as num?)?.toDouble() ?? 0;
    var y = (active.data['y'] as num?)?.toDouble() ?? 0;

    // Same canonical math as the canvas toolbar. Only the design surface is
    // this caller's own: the inspector is authoritative about the document's
    // declared roots, the canvas about what it rendered.
    final origin = WebsiteCanvasAlignmentMath.align(
      alignment: switch (alignment) {
        'left' => WebsiteCanvasAlignment.left,
        'hCenter' => WebsiteCanvasAlignment.horizontalCenter,
        'right' => WebsiteCanvasAlignment.right,
        'top' => WebsiteCanvasAlignment.top,
        'vCenter' => WebsiteCanvasAlignment.verticalCenter,
        _ => WebsiteCanvasAlignment.bottom,
      },
      x: x,
      y: y,
      width: width,
      height: height,
      designWidth: designWidth,
      designHeight: designHeight,
    );
    x = origin.x;
    y = origin.y;
    geometry.writeMany(<String, Object?>{'x': x, 'y': y});
  }

  Widget _buildElementArrangeControls(
    _CanvasSurface surface,
    WebsiteCanvasLayerProjection active,
  ) {
    final order = surface.number(
      WebsiteCanvasResponsivePolicy.orderKey,
      label: 'Orden de capas',
      layerId: active.id,
    );
    if (order == null) return const SizedBox.shrink();

    final slot = surface.slotOf(active.id);
    final locked = active.data['locked'] == true;
    final canMoveBackward = slot > 0;
    final canMoveForward = slot >= 0 && slot < surface.layers.length - 1;
    final blocked =
        order.state.status == WebsiteResponsiveFieldStatus.unavailable;

    return _CollapsibleSection(
      title: 'Alinear y ordenar',
      icon: Icons.layers_outlined,
      initiallyExpanded: true,
      children: [
        const Text(
          'Las acciones relativas también están siempre visibles en el toolbar del lienzo.',
          style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.3),
        ),
        const SizedBox(height: 14),
        ResponsiveFieldShell<num>(
          state: order.state,
          onCustomize: order.customize,
          onReset: order.reset,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _inspectorLayoutAction(
                    key: const ValueKey('inspector_layer_backward'),
                    label: 'Una atrás',
                    icon: Icons.flip_to_back_rounded,
                    onPressed: canMoveBackward && !blocked
                        ? () => _reorder(surface, order, active.id, slot - 1)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  _inspectorLayoutAction(
                    key: const ValueKey('inspector_layer_forward'),
                    label: 'Una adelante',
                    icon: Icons.flip_to_front_rounded,
                    onPressed: canMoveForward && !blocked
                        ? () => _reorder(surface, order, active.id, slot + 1)
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _inspectorLayoutAction(
                    label: 'Al fondo',
                    icon: Icons.vertical_align_bottom_rounded,
                    onPressed: canMoveBackward && !blocked
                        ? () => _reorder(surface, order, active.id, 0)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  _inspectorLayoutAction(
                    label: 'Al frente',
                    icon: Icons.vertical_align_top_rounded,
                    onPressed: canMoveForward && !blocked
                        ? () => _reorder(
                              surface,
                              order,
                              active.id,
                              surface.layers.length - 1,
                            )
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _SectionHeader('Alinear al lienzo'),
        if (locked) ...[
          const SizedBox(height: 6),
          const Text(
            'Desbloquea la capa para cambiar su posición.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            _inspectorLayoutAction(
              label: 'Izquierda',
              icon: Icons.align_horizontal_left_rounded,
              onPressed:
                  locked ? null : () => _alignToCanvas(surface, active, 'left'),
            ),
            const SizedBox(width: 6),
            _inspectorLayoutAction(
              label: 'Centro',
              icon: Icons.align_horizontal_center_rounded,
              onPressed: locked
                  ? null
                  : () => _alignToCanvas(surface, active, 'hCenter'),
            ),
            const SizedBox(width: 6),
            _inspectorLayoutAction(
              label: 'Derecha',
              icon: Icons.align_horizontal_right_rounded,
              onPressed: locked
                  ? null
                  : () => _alignToCanvas(surface, active, 'right'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _inspectorLayoutAction(
              label: 'Arriba',
              icon: Icons.align_vertical_top_rounded,
              onPressed:
                  locked ? null : () => _alignToCanvas(surface, active, 'top'),
            ),
            const SizedBox(width: 6),
            _inspectorLayoutAction(
              label: 'Medio',
              icon: Icons.align_vertical_center_rounded,
              onPressed: locked
                  ? null
                  : () => _alignToCanvas(surface, active, 'vCenter'),
            ),
            const SizedBox(width: 6),
            _inspectorLayoutAction(
              label: 'Abajo',
              icon: Icons.align_vertical_bottom_rounded,
              onPressed: locked
                  ? null
                  : () => _alignToCanvas(surface, active, 'bottom'),
            ),
          ],
        ),
      ],
    );
  }

  /// "Agregar capa". The command is the only writer, and a target that cannot
  /// take a layer says so instead of looking like it worked.
  void _addElement(BuildContext context, String type) {
    final added = provider.addCanvasElementToCanvasBlock(
      blockId,
      type,
      slideIndex: slideIndex,
    );
    if (added) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Esta diapositiva todavía no usa capas. Activa "Diseño avanzado '
          'por capas" para empezar la composición.',
        ),
        duration: Duration(seconds: 3),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _duplicateElement(_CanvasSurface surface, String layerId) {
    provider.duplicateCanvasLayer(
      blockId,
      layerId,
      WebsiteCanvasResponsiveDocument.nextLayerId(
        surface.document,
        seed: '${layerId}_copia',
      ),
      slideIndex: slideIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final document = provider.canvasDocument(blockId, slideIndex: slideIndex);
    if (document == null) {
      return const _CanvasNotComposedNotice();
    }

    final surface = _CanvasSurface(
      provider: provider,
      blockId: blockId,
      slideIndex: slideIndex,
      document: document,
    );
    final active = surface.layer(_activeElementId());
    final activeId = active?.id;
    final activeType = (active?.data['type'] ?? '').toString();
    final heightMode = (surface.root['heightMode'] ?? 'fixed').toString();
    final backgroundImageUrl =
        (surface.root['backgroundImageUrl'] ?? '').toString();
    final overlayEnabled = (surface.root['overlayEnabled'] as bool?) ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ========== LEGACY / MIGRATION STATE ==========
        // Anchored to the content and shown before anything else: an operator
        // editing a document that still speaks the old model has to know it
        // before spending a decision on a field.
        if (!selectedElementOnly)
          _CanvasMigrationNotice(
            status: WebsiteCanvasMigration.inspect(document),
            onMigrate: () => provider.migrateCanvasDocument(
              blockId,
              slideIndex: slideIndex,
            ),
            onMigrateKeepingLayers: () =>
                provider.migrateCanvasDocumentKeepingLayers(
              blockId,
              slideIndex: slideIndex,
            ),
            onRestore: () => provider.restoreCanvasLegacyDocument(
              blockId,
              slideIndex: slideIndex,
            ),
          ),
        if (!elementsOnly) ...[
          // ========== BLOCK SETTINGS ==========
          _CollapsibleSection(
            title: 'Block Settings',
            icon: Icons.settings_rounded,
            initiallyExpanded:
                active == null, // Only expanded when no element selected
            children: [
              _mount<bool>(
                surface.boolean('fullBleed', label: 'Full-bleed (sin padding)'),
                (binding) => _EditorToggle(
                  label: '',
                  value: binding.value ?? false,
                  onChanged: binding.write,
                ),
              ),
              const SizedBox(height: 12),
              _mount<String>(
                surface.text(
                  'heightMode',
                  label: 'Altura',
                  type: WebsiteBlockFieldType.select,
                ),
                (binding) => _EditorDropdown(
                  label: '',
                  value: binding.value ?? 'fixed',
                  options: const [
                    ('fixed', 'Fija'),
                    ('viewport', 'Viewport (pantalla)'),
                  ],
                  onChanged: binding.write,
                ),
              ),
              const SizedBox(height: 12),
              if (heightMode == 'viewport')
                _mount<num>(
                  surface.number('vhPct', label: 'Viewport height'),
                  (binding) {
                    final value =
                        (binding.value?.toDouble() ?? 0.7).clamp(0.2, 1.0);
                    return _EditorSlider(
                      label: '',
                      value: value,
                      min: 0.2,
                      max: 1.0,
                      divisions: 16,
                      valueLabel: '${(value * 100).toStringAsFixed(0)}%',
                      transactionIdentity: (provider, binding.scopeKey),
                      asyncBinding: _asyncFieldBinding(binding),
                      onCommit: binding.write,
                    );
                  },
                )
              else
                _mount<num>(
                  surface.number('blockHeight', label: 'Altura del canvas'),
                  (binding) {
                    final value =
                        (binding.value?.toDouble() ?? 420.0).clamp(220, 1600);
                    return _EditorSlider(
                      label: '',
                      value: value.toDouble(),
                      min: 220,
                      max: 1600,
                      divisions: 69,
                      valueLabel: '${value.toStringAsFixed(0)}px',
                      transactionIdentity: (provider, binding.scopeKey),
                      asyncBinding: _asyncFieldBinding(binding),
                      onCommit: binding.write,
                    );
                  },
                ),
              const SizedBox(height: 12),
              _mount<String>(
                surface.color('backgroundColor', label: 'Color de fondo'),
                (binding) => WebsiteColorPickerField(
                  label: '',
                  value: binding.value ?? '#FFFFFF',
                  allowAlpha: true,
                  asyncBinding: _asyncFieldBinding(binding),
                  onChanged: binding.write,
                ),
              ),
            ],
          ),

          // ========== BACKGROUND & OVERLAY ==========
          _CollapsibleSection(
            title: 'Background & Overlay',
            icon: Icons.image_rounded,
            initiallyExpanded: false, // Always collapsed unless manually opened
            children: [
              _mount<String>(
                surface.text(
                  'backgroundImageUrl',
                  label: 'Imagen de fondo',
                  type: WebsiteBlockFieldType.image,
                ),
                (binding) => _ImagePicker(
                  currentUrl: binding.value ?? '',
                  asyncBinding: _asyncFieldBinding(binding),
                  onChanged: binding.write,
                ),
              ),
              if (backgroundImageUrl.isNotEmpty) ...[
                const SizedBox(height: 12),
                _focalControl(
                  surface: surface,
                  imageUrl: backgroundImageUrl,
                  label: 'Foco de imagen',
                ),
                const SizedBox(height: 12),
                _mount<String>(
                  surface.text(
                    'backgroundImageAltText',
                    label: 'Texto alternativo',
                  ),
                  (binding) => _EditorTextField(
                    label: '',
                    value: binding.value ?? '',
                    asyncBinding: _asyncFieldBinding(binding),
                    onChanged: binding.write,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const _SectionHeader('Video de fondo'),
              const SizedBox(height: 8),
              _mount<String>(
                surface.text(
                  'backgroundVideoUrl',
                  label: 'Archivo de video',
                  type: WebsiteBlockFieldType.video,
                ),
                (binding) => _VideoPicker(
                  currentUrl: binding.value ?? '',
                  asyncBinding: _asyncFieldBinding(binding),
                  onChanged: (url) => binding.writeMany(<String, Object?>{
                    'backgroundVideoUrl': url,
                    if (url.isNotEmpty) 'backgroundYoutubeId': '',
                  }),
                ),
              ),
              const SizedBox(height: 12),
              _CollapsibleSection(
                title: 'Enlaces avanzados',
                icon: Icons.link_rounded,
                initiallyExpanded: false,
                children: [
                  const Text(
                    'Usa estas opciones sólo para recursos ya alojados o videos de YouTube.',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _mount<String>(
                    surface.text(
                      'backgroundVideoUrl',
                      label: 'URL directa de video (mp4/webm)',
                    ),
                    (binding) => _EditorTextField(
                      label: '',
                      value: binding.value ?? '',
                      asyncBinding: _asyncFieldBinding(binding),
                      onChanged: binding.write,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _mount<String>(
                    surface.text(
                      'backgroundYoutubeId',
                      label: 'YouTube URL / ID',
                    ),
                    (binding) => _EditorTextField(
                      label: '',
                      value: binding.value ?? '',
                      asyncBinding: _asyncFieldBinding(binding),
                      onChanged: (v) => binding.write(_youtubeIdOf(v)),
                      hint: 'Pega el enlace o ID',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _mount<String>(
                surface.text(
                  'backgroundFit',
                  label: 'Fit',
                  type: WebsiteBlockFieldType.select,
                ),
                (binding) => _EditorDropdown(
                  label: '',
                  value: binding.value ?? 'cover',
                  options: const [
                    ('cover', 'Cover'),
                    ('contain', 'Contain'),
                  ],
                  onChanged: binding.write,
                ),
              ),
              const SizedBox(height: 12),
              _mount<bool>(
                surface.boolean('overlayEnabled', label: 'Overlay'),
                (binding) => _EditorToggle(
                  label: '',
                  value: binding.value ?? false,
                  onChanged: binding.write,
                ),
              ),
              if (overlayEnabled) ...[
                const SizedBox(height: 12),
                _mount<String>(
                  surface.color('overlayColor', label: 'Color del overlay'),
                  (binding) => WebsiteColorPickerField(
                    label: '',
                    value: binding.value ?? '#000000',
                    allowAlpha: false,
                    asyncBinding: _asyncFieldBinding(binding),
                    onChanged: binding.write,
                  ),
                ),
                const SizedBox(height: 12),
                _mount<num>(
                  surface.number('overlayOpacity', label: 'Opacidad overlay'),
                  (binding) {
                    final value =
                        (binding.value?.toDouble() ?? 0.35).clamp(0.0, 0.9);
                    return _EditorSlider(
                      label: '',
                      value: value,
                      min: 0.0,
                      max: 0.9,
                      divisions: 18,
                      valueLabel: value.toStringAsFixed(2),
                      transactionIdentity: (provider, binding.scopeKey),
                      asyncBinding: _asyncFieldBinding(binding),
                      onCommit: binding.write,
                    );
                  },
                ),
              ],
            ],
          ),

          // ========== GRID & SNAPPING ==========
          _CollapsibleSection(
            title: 'Grid & Snapping',
            icon: Icons.grid_on_rounded,
            initiallyExpanded: false, // Always collapsed unless manually opened
            children: [
              _mount<bool>(
                surface.boolean('showGrid', label: 'Mostrar grid'),
                (binding) => _EditorToggle(
                  label: '',
                  value: binding.value ?? true,
                  onChanged: binding.write,
                ),
              ),
              const SizedBox(height: 12),
              _mount<bool>(
                surface.boolean('snap', label: 'Snapping'),
                (binding) => _EditorToggle(
                  label: '',
                  value: binding.value ?? true,
                  onChanged: binding.write,
                ),
              ),
              const SizedBox(height: 12),
              _mount<num>(
                surface.number('gridSize', label: 'Tamaño grid'),
                (binding) {
                  final value = (binding.value?.toDouble() ?? 8.0).clamp(4, 24);
                  return _EditorSlider(
                    label: '',
                    value: value.toDouble(),
                    min: 4,
                    max: 24,
                    divisions: 20,
                    valueLabel: '${value.toStringAsFixed(0)}px',
                    transactionIdentity: (provider, binding.scopeKey),
                    asyncBinding: _asyncFieldBinding(binding),
                    onCommit: binding.write,
                  );
                },
              ),
              const SizedBox(height: 12),
              _mount<num>(
                surface.number('snapDistance', label: 'Distancia snap'),
                (binding) {
                  final value = (binding.value?.toDouble() ?? 6.0).clamp(2, 16);
                  return _EditorSlider(
                    label: '',
                    value: value.toDouble(),
                    min: 2,
                    max: 16,
                    divisions: 14,
                    valueLabel: '${value.toStringAsFixed(0)}px',
                    transactionIdentity: (provider, binding.scopeKey),
                    asyncBinding: _asyncFieldBinding(binding),
                    onCommit: binding.write,
                  );
                },
              ),
            ],
          ),
        ],

        // ========== CANVAS-WIDE LAYOUT POLICY ==========
        if (!selectedElementOnly)
          _CollapsibleSection(
            title: 'Reglas del lienzo',
            icon: Icons.crop_free_rounded,
            initiallyExpanded: true,
            children: [
              _mount<bool>(
                surface.boolean(
                  'constrainElementsToSafeArea',
                  label: 'Restringir capas al área segura',
                ),
                (binding) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _EditorToggle(
                      label: '',
                      value: binding.value ?? true,
                      onChanged: binding.write,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      binding.value == false
                          ? 'Sangrado general activado: cualquier capa puede cruzar la guía. La parte fuera de la diapositiva se recorta en vista previa.'
                          : 'Regla general activa para capas actuales y nuevas. La guía visible conserva la composición entre editor y vista previa.',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

        // ========== CANVAS ELEMENTS ==========
        if (!selectedElementOnly)
          _CollapsibleSection(
            title: 'Canvas Elements (${surface.layers.length})',
            icon: Icons.layers_rounded,
            initiallyExpanded:
                active == null, // Only expanded when no element selected
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _addElement(context, 'text'),
                      icon: const Icon(Icons.text_fields_rounded, size: 18),
                      label: const Text('Texto'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _addElement(context, 'button'),
                      icon: const Icon(Icons.smart_button_rounded, size: 18),
                      label: const Text('Botón'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _addElement(context, 'image'),
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: const Text('Imagen'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _addElement(context, 'shape'),
                      icon: const Icon(Icons.rectangle_outlined, size: 18),
                      label: const Text('Forma'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (surface.layers.isEmpty)
                Text(
                  'Agrega elementos y arrástralos en el canvas.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                )
              else
                Column(
                  children: surface.layers.map((layer) {
                    final data = layer.data;
                    final type = (data['type'] ?? 'text').toString();
                    final title = switch (type) {
                      'button' => (data['label'] ?? 'Botón').toString(),
                      'image' =>
                        (data['altText'] ?? 'Imagen').toString().trim().isEmpty
                            ? 'Imagen'
                            : data['altText'].toString(),
                      'shape' => 'Forma',
                      'product' => 'Producto',
                      'productsGallery' => 'Galería de productos',
                      _ => (data['text'] ?? 'Texto').toString(),
                    };
                    final isActive = layer.id == activeId;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isActive
                              ? const Color(0xFF00A09D)
                              : Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: Icon(
                          switch (type) {
                            'button' => Icons.smart_button_rounded,
                            'image' => Icons.image_outlined,
                            'shape' => Icons.rectangle_outlined,
                            'product' => Icons.inventory_2_outlined,
                            'productsGallery' => Icons.grid_view_rounded,
                            _ => Icons.text_fields_rounded,
                          },
                          color:
                              layer.visible ? Colors.white70 : Colors.white30,
                          size: 18,
                        ),
                        title: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color:
                                layer.visible ? Colors.white70 : Colors.white30,
                            fontSize: 13,
                          ),
                        ),
                        onTap: () => _setActive(layer.id),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Duplicar',
                              icon: const Icon(Icons.copy_rounded, size: 17),
                              color: Colors.white54,
                              visualDensity: VisualDensity.compact,
                              onPressed: () =>
                                  _duplicateElement(surface, layer.id),
                            ),
                            IconButton(
                              tooltip: 'Eliminar',
                              icon: const Icon(Icons.delete_outline, size: 18),
                              color: Colors.red.shade300,
                              visualDensity: VisualDensity.compact,
                              onPressed: () => provider.removeCanvasLayer(
                                blockId,
                                layer.id,
                                slideIndex: slideIndex,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              if (active == null) ...[
                const SizedBox(height: 12),
                Text(
                  'Selecciona un elemento para editarlo.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                ),
              ],
            ],
          ),

        // ========== ELEMENT EDITOR (when element is selected) ==========
        if (active != null &&
            (inspectorSection == null ||
                inspectorSection == _InspectorSection.layout)) ...[
          _CollapsibleSection(
            title: 'Posición y tamaño',
            icon: Icons.open_with_rounded,
            initiallyExpanded: true,
            children: [
              // One geometry field per row. The two-column grid the Canvas used
              // to draw predates the inheritance shell: the shell's own header
              // is a label plus a status badge — "Personalizado para Móvil" is
              // the widest of them — and half of a 380 px inspector cannot hold
              // it, so the pair overflowed instead of ellipsizing.
              _mount<num>(
                surface.number('x', label: 'X', layerId: active.id),
                (binding) => _EditorTextField(
                  label: '',
                  value: (binding.value?.toDouble() ?? 0).toStringAsFixed(0),
                  asyncBinding: _asyncFieldBinding(binding),
                  onChanged: (v) {
                    final parsed = double.tryParse(v);
                    if (parsed != null) binding.write(parsed);
                  },
                ),
              ),
              const SizedBox(height: 10),
              _mount<num>(
                surface.number('y', label: 'Y', layerId: active.id),
                (binding) => _EditorTextField(
                  label: '',
                  value: (binding.value?.toDouble() ?? 0).toStringAsFixed(0),
                  asyncBinding: _asyncFieldBinding(binding),
                  onChanged: (v) {
                    final parsed = double.tryParse(v);
                    if (parsed != null) binding.write(parsed);
                  },
                ),
              ),
              const SizedBox(height: 10),
              _mount<num>(
                surface.number('w', label: 'Ancho', layerId: active.id),
                (binding) => _EditorTextField(
                  label: '',
                  value: (binding.value?.toDouble() ?? 200).toStringAsFixed(0),
                  asyncBinding: _asyncFieldBinding(binding),
                  onChanged: (v) {
                    final parsed = double.tryParse(v);
                    if (parsed != null) {
                      binding.write(parsed.clamp(40, 2000));
                    }
                  },
                ),
              ),
              const SizedBox(height: 10),
              _mount<num>(
                surface.number('h', label: 'Alto', layerId: active.id),
                (binding) => _EditorTextField(
                  label: '',
                  value: (binding.value?.toDouble() ?? 56).toStringAsFixed(0),
                  asyncBinding: _asyncFieldBinding(binding),
                  onChanged: (v) {
                    final parsed = double.tryParse(v);
                    if (parsed != null) {
                      binding.write(parsed.clamp(30, 2000));
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
              _mount<num>(
                surface.number('rotation',
                    label: 'Rotación', layerId: active.id),
                (binding) {
                  final value =
                      (binding.value?.toDouble() ?? 0).clamp(-180, 180);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _EditorSlider(
                        label: '',
                        value: value.toDouble(),
                        min: -180,
                        max: 180,
                        divisions: 360,
                        valueLabel: '${value.toStringAsFixed(0)}°',
                        transactionIdentity: (provider, binding.scopeKey),
                        asyncBinding: _asyncFieldBinding(binding),
                        onCommit: binding.write,
                      ),
                      if (value.abs() > 0.01)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () => binding.write(0),
                            icon:
                                const Icon(Icons.restart_alt_rounded, size: 16),
                            label: const Text('Restablecer rotación'),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF20C5C1),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              _mount<bool>(
                surface.boolean('locked',
                    label: 'Bloquear ajustes directos', layerId: active.id),
                (binding) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _EditorToggle(
                      label: '',
                      value: binding.value ?? false,
                      onChanged: binding.write,
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      'Evita mover, redimensionar, recortar o rotar accidentalmente desde el lienzo. Los valores precisos siguen disponibles aquí.',
                      style: TextStyle(
                          color: Colors.white38, fontSize: 11, height: 1.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // ONE typed visibility. The contradictory `hideOnMobile` /
              // `showOnMobile` pair is neither written nor offered: what a
              // viewport owns is this property's own override.
              _mount<bool>(
                surface.boolean(
                  WebsiteCanvasResponsivePolicy.visibleKey,
                  label: 'Mostrar esta capa',
                  layerId: active.id,
                ),
                (binding) => _EditorToggle(
                  label: '',
                  value: binding.value ?? true,
                  onChanged: binding.write,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildElementArrangeControls(surface, active),
        ],
        if (active != null &&
            (inspectorSection == null ||
                inspectorSection == _InspectorSection.content ||
                inspectorSection == _InspectorSection.style)) ...[
          _CollapsibleSection(
            title: inspectorSection == _InspectorSection.content
                ? 'Contenido'
                : inspectorSection == _InspectorSection.style
                    ? 'Apariencia'
                    : 'Contenido y apariencia',
            icon: switch (activeType) {
              'button' => Icons.smart_button_rounded,
              'image' => Icons.image_outlined,
              'shape' => Icons.rectangle_outlined,
              'product' => Icons.inventory_2_outlined,
              'productsGallery' => Icons.grid_view_rounded,
              _ => Icons.text_fields_rounded,
            },
            initiallyExpanded: selectedElementOnly,
            children: [
              if (activeType == 'text')
                ..._buildTextLayerControls(surface, active)
              else if (activeType == 'button')
                ..._buildButtonLayerControls(surface, active)
              else if (activeType == 'image')
                ..._buildImageLayerControls(surface, active)
              else if (activeType == 'shape')
                ..._buildShapeLayerControls(surface, active)
              else if (activeType == 'product')
                ..._buildProductLayerControls(surface, active)
              else if (activeType == 'productsGallery')
                ..._buildGalleryLayerControls(surface, active),
              if (inspectorSection == null) ...[
                const SizedBox(height: 12),
                const Divider(color: Colors.white12),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _setActive(null),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Deseleccionar elemento'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade300,
                    side: BorderSide(
                        color: Colors.red.shade300.withValues(alpha: 0.5)),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  List<Widget> _buildTextLayerControls(
    _CanvasSurface surface,
    WebsiteCanvasLayerProjection active,
  ) {
    final id = active.id;
    return <Widget>[
      if (inspectorSection != _InspectorSection.style)
        _mount<String>(
          surface.text('text', label: 'Texto', layerId: id),
          (binding) => _EditorTextField(
            label: '',
            value: binding.value ?? '',
            asyncBinding: _asyncFieldBinding(binding),
            onChanged: binding.write,
            maxLines: 3,
          ),
        ),
      if (inspectorSection != _InspectorSection.content) ...[
        _mount<num>(
          surface.number('fontSize', label: 'Tamaño fuente', layerId: id),
          (binding) {
            final value = (binding.value?.toDouble() ?? 24).clamp(10, 80);
            return _EditorSlider(
              label: '',
              value: value.toDouble(),
              min: 10,
              max: 80,
              divisions: 70,
              valueLabel: '${value.toStringAsFixed(0)}px',
              transactionIdentity: (provider, binding.scopeKey),
              asyncBinding: _asyncFieldBinding(binding),
              onCommit: binding.write,
            );
          },
        ),
        const SizedBox(height: 12),
        _mount<String>(
          surface.text(
            'fontRole',
            label: 'Tipografía del tema',
            layerId: id,
            type: WebsiteBlockFieldType.select,
          ),
          (binding) => _EditorDropdown(
            label: '',
            value: binding.value ?? 'heading',
            options: const [
              ('heading', 'Títulos'),
              ('body', 'Texto general'),
            ],
            onChanged: binding.write,
          ),
        ),
        const SizedBox(height: 12),
        _mount<String>(
          surface.text(
            'fontWeight',
            label: 'Peso',
            layerId: id,
            type: WebsiteBlockFieldType.select,
          ),
          (binding) => _EditorDropdown(
            label: '',
            value: binding.value ?? 'w600',
            options: const [
              ('w400', 'Normal'),
              ('w500', 'Medio'),
              ('w600', 'Semi-bold'),
              ('w700', 'Bold'),
            ],
            onChanged: binding.write,
          ),
        ),
        const SizedBox(height: 12),
        _mount<String>(
          surface.text(
            'align',
            label: 'Alineación',
            layerId: id,
            type: WebsiteBlockFieldType.select,
          ),
          (binding) => _EditorDropdown(
            label: '',
            value: binding.value ?? 'left',
            options: const [
              ('left', 'Izquierda'),
              ('center', 'Centro'),
              ('right', 'Derecha'),
            ],
            onChanged: binding.write,
          ),
        ),
        const SizedBox(height: 12),
        _mount<String>(
          surface.color('color', label: 'Color del texto', layerId: id),
          (binding) => WebsiteColorPickerField(
            label: '',
            value: binding.value ?? '#111111',
            allowAlpha: true,
            asyncBinding: _asyncFieldBinding(binding),
            onChanged: binding.write,
          ),
        ),
        const SizedBox(height: 12),
        _mount<num>(
          surface.number('letterSpacing',
              label: 'Espaciado de letras', layerId: id),
          (binding) {
            final value = (binding.value?.toDouble() ?? 0).clamp(-1, 8);
            return _EditorSlider(
              label: '',
              value: value.toDouble(),
              min: -1,
              max: 8,
              divisions: 18,
              valueLabel: value.toStringAsFixed(1),
              transactionIdentity: (provider, binding.scopeKey),
              asyncBinding: _asyncFieldBinding(binding),
              onCommit: binding.write,
            );
          },
        ),
        const SizedBox(height: 12),
        _mount<num>(
          surface.number('lineHeight', label: 'Interlineado', layerId: id),
          (binding) {
            final value = (binding.value?.toDouble() ?? 1.1).clamp(0.8, 2.0);
            return _EditorSlider(
              label: '',
              value: value,
              min: 0.8,
              max: 2.0,
              divisions: 12,
              valueLabel: value.toStringAsFixed(1),
              transactionIdentity: (provider, binding.scopeKey),
              asyncBinding: _asyncFieldBinding(binding),
              onCommit: binding.write,
            );
          },
        ),
        const SizedBox(height: 12),
        _mount<bool>(
          surface.boolean('uppercase', label: 'MAYÚSCULAS', layerId: id),
          (binding) => _EditorToggle(
            label: '',
            value: binding.value ?? false,
            onChanged: binding.write,
          ),
        ),
        const SizedBox(height: 12),
        _animationControl(surface, id),
      ],
    ];
  }

  List<Widget> _buildButtonLayerControls(
    _CanvasSurface surface,
    WebsiteCanvasLayerProjection active,
  ) {
    final id = active.id;
    final data = active.data;
    final inheritTheme = data['inheritTheme'] != false;
    // The action as PERSISTED, for the companion that must stay common.
    //
    // Resolved as a whole action rather than read off `style`: a layer written
    // before the direct keys existed carries its presentation only inside the
    // structured `actions`, and asking for `style` alone would answer "filled"
    // for it. Editing just the wording would then rewrite an `outline` button
    // as a solid one — a silent change to the SHARED presentation, which is
    // exactly what this split exists to prevent.
    final shared = surface.sharedLayer(id) ?? data;
    final sharedAction = WebsiteActionValue.resolvePrimary(
          shared,
          labelKeys: const ['label'],
          hrefKeys: const ['link'],
          variantKeys: const ['style'],
          defaultLabel: 'Botón',
          defaultHref: '/',
        ) ??
        const WebsiteActionValue(label: 'Botón', href: '/');
    final sharedVariant = sharedAction.variant;
    return <Widget>[
      // Content is the shared half of the action — the words and the
      // destination — and it is edited WITHOUT the variant selector.
      //
      // `label` and `link` are `sharedOnly`; `style` is `responsiveOptional`.
      // One editor writing all three would drag presentation into whatever
      // scope the shared half writes at, so a phone edit of the wording would
      // silently stamp the phone's variant onto the common base. The variant
      // therefore lives under Apariencia with its own binding, and the
      // `actions` mirror is rebuilt from the layer's SHARED variant so the
      // mirror never records a projected phone value as the common one.
      if (inspectorSection != _InspectorSection.style)
        _mount<String>(
          surface.text('label', label: 'Acción', layerId: id),
          (binding) => WebsiteActionEditor(
            showVariant: false,
            asyncBinding: _asyncFieldBinding(binding),
            // Label, destination and variant are all shared for this layer, so
            // the editor shows the shared action itself.
            value: sharedAction,
            onChanged: (action) => binding.writeMany(<String, Object?>{
              'label': action.label,
              'link': action.href,
              'actions': WebsiteActionValue.mergePrimary(
                shared['actions'],
                action.copyWith(variant: sharedVariant),
              ),
            }),
          ),
        ),
      if (inspectorSection != _InspectorSection.content) ...[
        _mount<String>(
          surface.text(
            'style',
            label: 'Estilo del botón',
            layerId: id,
            type: WebsiteBlockFieldType.select,
          ),
          (binding) => _EditorDropdown(
            label: '',
            value: WebsiteActionVariant.fromStorage(binding.value).storageValue,
            options: const [
              ('filled', 'Sólido'),
              ('outline', 'Contorno'),
              ('text', 'Solo texto'),
            ],
            onChanged: binding.write,
          ),
        ),
        const SizedBox(height: 12),
        _mount<bool>(
          surface.boolean('inheritTheme',
              label: 'Usar estilo global del tema', layerId: id),
          (binding) => _EditorToggle(
            label: '',
            value: binding.value ?? true,
            onChanged: binding.write,
          ),
        ),
        if (!inheritTheme) ...[
          const SizedBox(height: 12),
          _mount<String>(
            surface.color('bgColor', label: 'Color del botón', layerId: id),
            (binding) => WebsiteColorPickerField(
              label: '',
              value: binding.value ?? '#00A09D',
              allowAlpha: true,
              asyncBinding: _asyncFieldBinding(binding),
              onChanged: binding.write,
            ),
          ),
          const SizedBox(height: 12),
          _mount<String>(
            surface.color('fgColor', label: 'Color del texto', layerId: id),
            (binding) => WebsiteColorPickerField(
              label: '',
              value: binding.value ?? '#FFFFFF',
              allowAlpha: true,
              asyncBinding: _asyncFieldBinding(binding),
              onChanged: binding.write,
            ),
          ),
          const SizedBox(height: 12),
          _mount<num>(
            surface.number('radius', label: 'Radio', layerId: id),
            (binding) {
              final value = (binding.value?.toDouble() ?? 12).clamp(0, 32);
              return _EditorSlider(
                label: '',
                value: value.toDouble(),
                min: 0,
                max: 32,
                divisions: 32,
                valueLabel: '${value.toStringAsFixed(0)}px',
                transactionIdentity: (provider, binding.scopeKey),
                asyncBinding: _asyncFieldBinding(binding),
                onCommit: binding.write,
              );
            },
          ),
          const SizedBox(height: 12),
          _mount<bool>(
            surface.boolean('shadow', label: 'Sombra', layerId: id),
            (binding) => _EditorToggle(
              label: '',
              value: binding.value ?? false,
              onChanged: binding.write,
            ),
          ),
          const SizedBox(height: 12),
          _mount<bool>(
            surface.boolean('uppercase', label: 'MAYÚSCULAS', layerId: id),
            (binding) => _EditorToggle(
              label: '',
              value: binding.value ?? false,
              onChanged: binding.write,
            ),
          ),
          const SizedBox(height: 12),
          _mount<num>(
            surface.number('letterSpacing',
                label: 'Letter spacing', layerId: id),
            (binding) {
              final value = (binding.value?.toDouble() ?? 0.0).clamp(0, 6);
              return _EditorSlider(
                label: '',
                value: value.toDouble(),
                min: 0,
                max: 6,
                divisions: 12,
                valueLabel: value.toStringAsFixed(1),
                transactionIdentity: (provider, binding.scopeKey),
                asyncBinding: _asyncFieldBinding(binding),
                onCommit: binding.write,
              );
            },
          ),
        ],
        const SizedBox(height: 12),
        _animationControl(surface, id),
      ],
    ];
  }

  List<Widget> _buildImageLayerControls(
    _CanvasSurface surface,
    WebsiteCanvasLayerProjection active,
  ) {
    final id = active.id;
    final data = active.data;
    final productId = (data['productId'] ?? '').toString();
    final imageUrl = (data['imageUrl'] ?? '').toString();
    return <Widget>[
      if (inspectorSection != _InspectorSection.style) ...[
        const _SectionHeader('Producto vinculado (opcional)'),
        const SizedBox(height: 8),
        _mount<String>(
          surface.text('productId', label: 'Producto', layerId: id),
          (binding) => _CanvasProductSelector(
            currentProductId: binding.value ?? '',
            asyncBinding: _asyncFieldBinding(binding),
            onChanged: (next) => binding.writeMany(<String, Object?>{
              'productId': next,
              'imageSource': next.isEmpty ? 'manual' : 'product',
            }),
          ),
        ),
        if (productId.isNotEmpty) ...[
          const SizedBox(height: 12),
          _mount<String>(
            surface.text(
              'imageSource',
              label: 'Imagen visible',
              layerId: id,
              type: WebsiteBlockFieldType.select,
            ),
            (binding) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _EditorDropdown(
                  label: '',
                  value: binding.value ?? 'product',
                  options: const [
                    ('product', 'Imagen actual del catálogo'),
                    ('manual', 'Imagen seleccionada / recorte'),
                  ],
                  onChanged: binding.write,
                ),
                const SizedBox(height: 8),
                Text(
                  (binding.value ?? 'product') == 'manual'
                      ? 'La capa conserva el vínculo comercial, pero muestra el recurso seleccionado abajo. Útil para recortes transparentes y campañas.'
                      : 'La capa sigue automáticamente la imagen principal del producto en el catálogo.',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        const _SectionHeader('Imagen seleccionada'),
        const SizedBox(height: 8),
        _mount<String>(
          surface.text(
            'imageUrl',
            label: 'Imagen',
            layerId: id,
            type: WebsiteBlockFieldType.image,
          ),
          (binding) => _ImagePicker(
            currentUrl: binding.value ?? '',
            allowProductLink: true,
            asyncBinding: _asyncFieldBinding(binding),
            onAssetChanged: (selection) => binding.writeMany(<String, Object?>{
              'imageUrl': selection.publicUrl,
              if (selection.linksProduct) ...<String, Object?>{
                'productId': selection.productId ?? '',
                'imageSource':
                    selection.productImageIndex == 0 ? 'product' : 'manual',
              } else ...<String, Object?>{
                if (selection.comesFromProduct) 'productId': '',
                'imageSource': 'manual',
              },
            }),
          ),
        ),
        const SizedBox(height: 12),
        _mount<String>(
          surface.text('altText', label: 'Texto alternativo', layerId: id),
          (binding) => _EditorTextField(
            label: '',
            value: binding.value ?? '',
            asyncBinding: _asyncFieldBinding(binding),
            onChanged: binding.write,
          ),
        ),
      ],
      if (inspectorSection != _InspectorSection.content) ...[
        _mount<String>(
          surface.text(
            'fit',
            label: 'Fit',
            layerId: id,
            type: WebsiteBlockFieldType.select,
          ),
          (binding) => _EditorDropdown(
            label: '',
            value: binding.value ?? 'cover',
            options: const [
              ('cover', 'Cover'),
              ('contain', 'Contain'),
            ],
            onChanged: binding.write,
          ),
        ),
        const SizedBox(height: 12),
        _focalControl(
          surface: surface,
          imageUrl: imageUrl,
          label: 'Encuadre de la imagen',
          layerId: id,
        ),
        const Text(
          'En el lienzo: doble clic o usa Recortar; arrastra la imagen para reencuadrar y sus ocho bordes para cambiar el marco.',
          style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.3),
        ),
        const SizedBox(height: 12),
        _mount<num>(
          surface.number('radius', label: 'Radio', layerId: id),
          (binding) {
            final value = (binding.value?.toDouble() ?? 12).clamp(0, 32);
            return _EditorSlider(
              label: '',
              value: value.toDouble(),
              min: 0,
              max: 32,
              divisions: 32,
              valueLabel: '${value.toStringAsFixed(0)}px',
              transactionIdentity: (provider, binding.scopeKey),
              asyncBinding: _asyncFieldBinding(binding),
              onCommit: binding.write,
            );
          },
        ),
        const SizedBox(height: 12),
        _animationControl(surface, id),
      ],
    ];
  }

  List<Widget> _buildShapeLayerControls(
    _CanvasSurface surface,
    WebsiteCanvasLayerProjection active,
  ) {
    final id = active.id;
    final shape = (active.data['shape'] ?? 'rectangle').toString();
    return <Widget>[
      if (inspectorSection != _InspectorSection.style)
        _mount<String>(
          surface.text(
            'shape',
            label: 'Forma',
            layerId: id,
            type: WebsiteBlockFieldType.select,
          ),
          (binding) => _EditorDropdown(
            label: '',
            value: binding.value ?? 'rectangle',
            options: const [
              ('rectangle', 'Rectángulo'),
              ('ellipse', 'Elipse'),
            ],
            onChanged: binding.write,
          ),
        ),
      if (inspectorSection != _InspectorSection.content) ...[
        _mount<String>(
          surface.color('fillColor', label: 'Color de relleno', layerId: id),
          (binding) => WebsiteColorPickerField(
            label: '',
            value: binding.value ?? '#1F2937',
            allowAlpha: true,
            asyncBinding: _asyncFieldBinding(binding),
            onChanged: binding.write,
          ),
        ),
        const SizedBox(height: 12),
        _mount<String>(
          surface.color('borderColor', label: 'Color de borde', layerId: id),
          (binding) => WebsiteColorPickerField(
            label: '',
            value: binding.value ?? '#1F2937',
            allowAlpha: true,
            asyncBinding: _asyncFieldBinding(binding),
            onChanged: binding.write,
          ),
        ),
        const SizedBox(height: 12),
        _mount<num>(
          surface.number('borderWidth', label: 'Borde', layerId: id),
          (binding) {
            final value = (binding.value?.toDouble() ?? 0).clamp(0, 16);
            return _EditorSlider(
              label: '',
              value: value.toDouble(),
              min: 0,
              max: 16,
              divisions: 16,
              valueLabel: '${value.toStringAsFixed(0)}px',
              transactionIdentity: (provider, binding.scopeKey),
              asyncBinding: _asyncFieldBinding(binding),
              onCommit: binding.write,
            );
          },
        ),
        const SizedBox(height: 12),
        if (shape == 'rectangle')
          _mount<num>(
            surface.number('radius', label: 'Radio', layerId: id),
            (binding) {
              final value = (binding.value?.toDouble() ?? 0).clamp(0, 80);
              return _EditorSlider(
                label: '',
                value: value.toDouble(),
                min: 0,
                max: 80,
                divisions: 40,
                valueLabel: '${value.toStringAsFixed(0)}px',
                transactionIdentity: (provider, binding.scopeKey),
                asyncBinding: _asyncFieldBinding(binding),
                onCommit: binding.write,
              );
            },
          ),
      ],
    ];
  }

  List<Widget> _buildProductLayerControls(
    _CanvasSurface surface,
    WebsiteCanvasLayerProjection active,
  ) {
    final id = active.id;
    return <Widget>[
      if (inspectorSection != _InspectorSection.style) ...[
        _mount<String>(
          surface.text('productId', label: 'Producto', layerId: id),
          (binding) => _CanvasProductSelector(
            currentProductId: binding.value ?? '',
            asyncBinding: _asyncFieldBinding(binding),
            onChanged: binding.write,
          ),
        ),
        const SizedBox(height: 12),
        _mount<bool>(
          surface.boolean('showPrice', label: 'Mostrar precio', layerId: id),
          (binding) => _EditorToggle(
            label: '',
            value: binding.value ?? true,
            onChanged: binding.write,
          ),
        ),
      ],
      if (inspectorSection != _InspectorSection.content)
        _animationControl(surface, id),
    ];
  }

  List<Widget> _buildGalleryLayerControls(
    _CanvasSurface surface,
    WebsiteCanvasLayerProjection active,
  ) {
    final id = active.id;
    final data = active.data;
    final mode = (data['mode'] ?? 'latest').toString();
    final layout = (data['layout'] ?? 'grid').toString();
    return <Widget>[
      if (inspectorSection != _InspectorSection.style) ...[
        _mount<String>(
          surface.text(
            'mode',
            label: 'Modo',
            layerId: id,
            type: WebsiteBlockFieldType.select,
          ),
          (binding) => _EditorDropdown(
            label: '',
            value: binding.value ?? 'latest',
            options: const [
              ('latest', 'Últimos publicados'),
              ('manual', 'Manual (IDs)'),
            ],
            onChanged: binding.write,
          ),
        ),
        const SizedBox(height: 12),
        _mount<num>(
          surface.number('maxProducts', label: 'Máx productos', layerId: id),
          (binding) {
            final value = (binding.value?.toDouble() ?? 6).clamp(1, 24);
            return _EditorSlider(
              label: '',
              value: value.toDouble(),
              min: 1,
              max: 24,
              divisions: 23,
              valueLabel: '${value.round()}',
              transactionIdentity: (provider, binding.scopeKey),
              asyncBinding: _asyncFieldBinding(binding),
              onCommit: (v) => binding.write(v.round()),
            );
          },
        ),
        if (mode == 'manual') ...[
          const SizedBox(height: 12),
          _mount<List<String>>(
            surface.field<List<String>>(
              'productIds',
              label: 'Productos',
              layerId: id,
              decode: WebsiteResponsiveScalarBinding.decodeStringList,
            ),
            (binding) => _CanvasProductsMultiSelector(
              selectedIds: binding.value ?? const <String>[],
              asyncBinding: _asyncFieldBinding(binding),
              onConfirm: binding.write,
            ),
          ),
        ],
      ],
      if (inspectorSection != _InspectorSection.content) ...[
        _mount<String>(
          surface.text(
            'layout',
            label: 'Diseño',
            layerId: id,
            type: WebsiteBlockFieldType.select,
          ),
          (binding) => _EditorDropdown(
            label: '',
            value: binding.value ?? 'grid',
            options: const [
              ('grid', 'Cuadrícula'),
              ('carousel', 'Carrusel'),
            ],
            onChanged: binding.write,
          ),
        ),
        const SizedBox(height: 12),
        if (layout == 'grid')
          _mount<num>(
            surface.number('columns', label: 'Columnas', layerId: id),
            (binding) {
              final value = (binding.value?.toDouble() ?? 3).clamp(1, 4);
              return _EditorSlider(
                label: '',
                value: value.toDouble(),
                min: 1,
                max: 4,
                divisions: 3,
                valueLabel: '${value.round()}',
                transactionIdentity: (provider, binding.scopeKey),
                asyncBinding: _asyncFieldBinding(binding),
                onCommit: (v) => binding.write(v.round()),
              );
            },
          )
        else
          _mount<num>(
            surface.number('cardWidth', label: 'Ancho tarjeta', layerId: id),
            (binding) {
              final value = (binding.value?.toDouble() ?? 300).clamp(220, 380);
              return _EditorSlider(
                label: '',
                value: value.toDouble(),
                min: 220,
                max: 380,
                divisions: 32,
                valueLabel: '${value.toStringAsFixed(0)}px',
                transactionIdentity: (provider, binding.scopeKey),
                asyncBinding: _asyncFieldBinding(binding),
                onCommit: binding.write,
              );
            },
          ),
        const SizedBox(height: 12),
        _animationControl(surface, id),
      ],
    ];
  }

  Widget _animationControl(_CanvasSurface surface, String layerId) {
    return _mount<String>(
      surface.text(
        'anim',
        label: 'Animación',
        layerId: layerId,
        type: WebsiteBlockFieldType.select,
      ),
      (binding) => _EditorDropdown(
        label: '',
        value: binding.value ?? 'none',
        options: const [
          ('none', 'Ninguna'),
          ('fade', 'Fade'),
          ('fadeUp', 'Fade up'),
        ],
        onChanged: binding.write,
      ),
    );
  }

  static String _youtubeIdOf(String raw) {
    if (!raw.contains('youtube.com') && !raw.contains('youtu.be')) return raw;
    final regExp = RegExp(
      r'^.*((youtu.be\/)|(v\/)|(\/u\/\w\/)|(embed\/)|(watch\?))\??v?=?([^#&?]*).*',
    );
    final match = regExp.firstMatch(raw);
    if (match != null && match.groupCount >= 7) {
      final extracted = match.group(7);
      if (extracted != null && extracted.isNotEmpty) return extracted;
    }
    return raw;
  }
}

/// One framing control: the resolved value, and the picker on demand.
///
/// Reframing is precision, not a permanently mounted editor — the same
/// disclosure the canonical media row uses.
///
/// The shell is the ONLY label and status here: the picker is mounted with
/// `label: null`, so nothing calls a desktop value "móvil", and its own
/// `Centrar` is the only centring action. The picker also runs with
/// `continuousUpdates: false`, so a drag paints locally and persists `x` and
/// `y` once, when the gesture ends — a reframe is one history entry, and a
/// cancelled gesture is none.
class _CanvasFocalField extends StatefulWidget {
  const _CanvasFocalField({
    required this.state,
    required this.imageUrl,
    required this.asyncBinding,
    required this.onChanged,
    this.onCustomize,
    this.onReset,
  });

  final WebsiteResponsiveFieldState<Offset> state;
  final String imageUrl;
  final WebsiteAsyncFieldBinding asyncBinding;
  final void Function(double x, double y) onChanged;
  final VoidCallback? onCustomize;
  final VoidCallback? onReset;

  @override
  State<_CanvasFocalField> createState() => _CanvasFocalFieldState();
}

class _CanvasFocalFieldState extends State<_CanvasFocalField> {
  /// Transient. Reframing is a mode, never published data.
  bool _reframing = false;

  @override
  Widget build(BuildContext context) {
    final focal = widget.state.resolved.value ?? const Offset(0.5, 0.5);
    final blocked =
        widget.state.status == WebsiteResponsiveFieldStatus.unavailable ||
            widget.imageUrl.trim().isEmpty;

    return ResponsiveFieldShell<Offset>(
      state: widget.state,
      onCustomize: widget.onCustomize,
      onReset: widget.onReset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                // The value, in words, while the picker is closed. Open, the
                // picker shows the same pair as its own X/Y chips, so this
                // line steps aside instead of repeating them.
                child: _reframing
                    ? const SizedBox.shrink()
                    : Text(
                        '${(focal.dx * 100).round()}% · '
                        '${(focal.dy * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
              ),
              TextButton.icon(
                onPressed: blocked
                    ? null
                    : () => setState(() => _reframing = !_reframing),
                icon: const Icon(Icons.crop_free_rounded, size: 16),
                label: Text(_reframing ? 'Listo' : 'Reencuadrar'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF20C5C1),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          if (_reframing && !blocked) ...[
            const SizedBox(height: 8),
            FocalPointPicker(
              imageUrl: widget.imageUrl,
              focalX: focal.dx.clamp(0.0, 1.0),
              focalY: focal.dy.clamp(0.0, 1.0),
              // The shell already said what this field is and where it writes.
              label: null,
              // One drag is one change: local feedback, one atomic write.
              continuousUpdates: false,
              asyncBinding: widget.asyncBinding,
              onChanged: widget.onChanged,
            ),
          ],
        ],
      ),
    );
  }
}

/// The state of a Canvas that still speaks — or used to speak — the old model.
///
/// Design source: project `a0fa3196-6315-4b96-bde7-7cc801e7a74e`, page
/// `Website Builder Responsive Authoring`, turn **t10**, frame **10i · Estados
/// del sistema** (state `documento ambiguo`) and frame **10d · Capas
/// responsive** (badge `Duplicado legacy`). Components: **E-04 VbNotice**
/// (anchored to the content, at most one banner per surface), **E-01
/// VbStatusBadge** (informs, never executes), **A-01** text actions under the
/// rule *DISABLED SIEMPRE EXPLICA*, and **F-06 VbDensity**.
///
/// **Colour and type are not written here.** The notice and the badge already
/// carry the anatomy read from the guide; the actions are plain `TextButton`s,
/// so the theme resolver owns their colour, typography, focus, hover and
/// disabled states in both brightnesses; the explanation lines take
/// `textTheme.bodySmall` and the `neutral` semantic role. A literal here would
/// freeze light mode inside the widget — which is what produced white-on-white
/// text the first time.
///
/// **The only geometry declared** is the vertical rhythm, and it comes from
/// `F-04`'s published scale (2·4·6·8·10·12·14·16·18·24, t10
/// `components_used.F-04`); the action's minimum height is `F-06`'s, resolved
/// by [VbDensity], which forces 48 below 900 px.
///
/// It presents; it never migrates. Every action is a provider command, and
/// expanding the reasons changes nothing at all.
class _CanvasMigrationNotice extends StatefulWidget {
  const _CanvasMigrationNotice({
    required this.status,
    required this.onMigrate,
    required this.onMigrateKeepingLayers,
    required this.onRestore,
  });

  final WebsiteCanvasMigrationStatus status;
  final VoidCallback onMigrate;
  final VoidCallback onMigrateKeepingLayers;
  final VoidCallback onRestore;

  // The surface is private, so these string keys — not the constants — are
  // what a test addresses. They are part of the contract: an action that
  // changes a document has to be findable by identity, not by its wording.
  static const Key migrateKey = Key('canvas-migration-apply');
  static const Key keepDistinctKey = Key('canvas-migration-keep-distinct');
  static const Key restoreKey = Key('canvas-migration-restore');
  static const Key reviewKey = Key('canvas-migration-review');
  static const Key reasonsKey = Key('canvas-migration-reasons');

  /// `F-04` scale — the only dimensions this surface declares.
  static const double _gapSmall = 4;
  static const double _gap = 8;
  static const double _gapSection = 10;

  @override
  State<_CanvasMigrationNotice> createState() => _CanvasMigrationNoticeState();
}

class _CanvasMigrationNoticeState extends State<_CanvasMigrationNotice> {
  /// Transient. Reading the reasons is not a change to the document.
  bool _reasonsExpanded = false;

  /// One sentence per typed finding, naming the layers and the field.
  ///
  /// The code is never shown: an operator cannot act on
  /// `nonComplementaryVisibility`, and the plan forbids leaving this state in
  /// logs or as a raw enum.
  String _reason(WebsiteCanvasMigrationIssue issue) {
    final ids = issue.layerIds.toSet().toList();
    final named = ids.map((id) => '«$id»').join(' y ');
    final field = issue.propertyKey;
    return switch (issue.code) {
      WebsiteCanvasMigrationIssueCode.differingSharedValue =>
        'Las capas $named guardan un valor distinto en «$field». Unirlas '
            'obligaría a elegir cuál gana.',
      WebsiteCanvasMigrationIssueCode.missingPair =>
        'La capa $named no tiene su pareja de la otra versión, así que no hay '
            'nada que unir.',
      WebsiteCanvasMigrationIssueCode.incompatibleType =>
        'Las capas $named son de tipos distintos.',
      WebsiteCanvasMigrationIssueCode.nonComplementaryVisibility =>
        'Las capas $named no se reparten los dispositivos: no queda claro '
            'cuál se ve en cada uno.',
      WebsiteCanvasMigrationIssueCode.uncertainOrder =>
        'Las capas $named declaran su propio orden, y al unirlas habría dos '
            'órdenes en conflicto.',
      WebsiteCanvasMigrationIssueCode.duplicateStem =>
        'Hay más de una capa «${issue.stem}» para el mismo dispositivo.',
      WebsiteCanvasMigrationIssueCode.conflictingIdentity => ids.isEmpty
          ? 'La capa en la posición ${issue.stem.replaceFirst("index:", "")} '
              'no tiene identificador.'
          : 'Dos capas comparten el identificador «${issue.stem}».',
    };
  }

  /// `E-01`: informs, never executes. The word is the channel, not the colour.
  String get _badgeLabel => switch (widget.status.state) {
        WebsiteCanvasMigrationState.safe => 'Configuración anterior',
        WebsiteCanvasMigrationState.ambiguous => 'Revisar',
        WebsiteCanvasMigrationState.blocked => 'Revisar',
        WebsiteCanvasMigrationState.migrated => 'Actualizado',
        WebsiteCanvasMigrationState.canonical => 'Actualizado',
      };

  VbStatusTone get _badgeTone => switch (widget.status.state) {
        WebsiteCanvasMigrationState.safe => VbStatusTone.info,
        WebsiteCanvasMigrationState.ambiguous => VbStatusTone.warning,
        WebsiteCanvasMigrationState.blocked => VbStatusTone.warning,
        WebsiteCanvasMigrationState.migrated => VbStatusTone.success,
        WebsiteCanvasMigrationState.canonical => VbStatusTone.neutral,
      };

  /// `A-01` text action. No local style: the theme resolver owns colour,
  /// typography and every interaction state. `F-06` supplies the one number
  /// that must not be left to Material — the minimum touch target.
  Widget _action({
    required Key key,
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    required VbDensity density,
  }) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: density.controlHeight),
        child: TextButton.icon(
          key: key,
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    if (status.state == WebsiteCanvasMigrationState.canonical) {
      return const SizedBox.shrink();
    }

    final (String title, String body, VbNoticeTone tone) =
        switch (status.state) {
      WebsiteCanvasMigrationState.safe => (
          'Este bloque usa una configuración anterior',
          'Se sigue publicando tal cual. Actualizarla une las capas '
              'duplicadas por dispositivo y se puede deshacer.',
          VbNoticeTone.info,
        ),
      WebsiteCanvasMigrationState.ambiguous => (
          'Este bloque tiene capas duplicadas por dispositivo',
          'Se sigue publicando tal cual. Unirlas es una decisión tuya y se '
              'puede deshacer.',
          VbNoticeTone.warning,
        ),
      WebsiteCanvasMigrationState.blocked => (
          'Este bloque tiene capas sin identidad única',
          'No se puede actualizar desde aquí: sin un identificador propio por '
              'capa no se garantiza a cuál apunta cada cambio ni cómo '
              'deshacerlo. Se sigue publicando tal cual.',
          VbNoticeTone.warning,
        ),
      WebsiteCanvasMigrationState.migrated => (
          'Configuración actualizada',
          'Este bloque ya usa una capa por elemento, con sus diferencias por '
              'dispositivo. Puedes volver a la configuración anterior.',
          VbNoticeTone.success,
        ),
      WebsiteCanvasMigrationState.canonical => ('', '', VbNoticeTone.neutral),
    };

    final reasons = status.issues;
    final showReasons = _reasonsExpanded && reasons.isNotEmpty;
    final density = VbDensity.resolve(context);
    // The explanation lines are body copy of this surface: type from the
    // theme, colour from the neutral semantic role — the same pair the
    // canonical field shell uses for its own help text.
    final bodyStyle = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: VinabikeThemeRoles.of(context).neutral.accent);

    return Container(
      margin: const EdgeInsets.only(
        bottom: _CanvasMigrationNotice._gapSection,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          VbStatusBadge(label: _badgeLabel, tone: _badgeTone, dense: true),
          const SizedBox(height: _CanvasMigrationNotice._gap),
          VbNotice(title: title, body: body, tone: tone),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: _CanvasMigrationNotice._gapSmall),
            _action(
              key: _CanvasMigrationNotice.reviewKey,
              density: density,
              label: showReasons
                  ? 'Ocultar detalle'
                  : status.state == WebsiteCanvasMigrationState.blocked
                      ? 'Revisar identidades'
                      : 'Ver qué impide unirlas',
              icon: showReasons
                  ? Icons.expand_less_rounded
                  : Icons.expand_more_rounded,
              onPressed: () =>
                  setState(() => _reasonsExpanded = !_reasonsExpanded),
            ),
            if (showReasons)
              Padding(
                key: _CanvasMigrationNotice.reasonsKey,
                padding: const EdgeInsets.only(
                  left: _CanvasMigrationNotice._gap,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final issue in reasons) ...[
                      Text('· ${_reason(issue)}', style: bodyStyle),
                      const SizedBox(height: _CanvasMigrationNotice._gapSmall),
                    ],
                  ],
                ),
              ),
          ],
          if (status.canMigrateSafely)
            _action(
              key: _CanvasMigrationNotice.migrateKey,
              density: density,
              label: 'Actualizar configuración',
              icon: Icons.auto_fix_high_rounded,
              onPressed: widget.onMigrate,
            ),
          if (status.canMigrateKeepingLayers) ...[
            _action(
              key: _CanvasMigrationNotice.keepDistinctKey,
              density: density,
              label: 'Conservar capas separadas y actualizar',
              icon: Icons.call_split_rounded,
              onPressed: widget.onMigrateKeepingLayers,
            ),
            Padding(
              padding: const EdgeInsets.only(
                left: _CanvasMigrationNotice._gap,
              ),
              child: Text(
                'Ninguna capa se une ni se descarta: cada una queda por '
                'separado, con lo que ya muestra en cada dispositivo.',
                style: bodyStyle,
              ),
            ),
          ],
          if (status.canRestore)
            _action(
              key: _CanvasMigrationNotice.restoreKey,
              density: density,
              label: 'Restaurar configuración anterior',
              icon: Icons.history_rounded,
              onPressed: widget.onRestore,
            ),
        ],
      ),
    );
  }
}

/// The Canvas inspector on a target that owns no Canvas document yet.
///
/// A slide that is not composed has no layers to show and cannot take one, so
/// the surface says exactly that instead of rendering controls that would
/// silently write nothing.
class _CanvasNotComposedNotice extends StatelessWidget {
  const _CanvasNotComposedNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF242424),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Esta diapositiva todavía no usa capas',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Activa "Diseño avanzado por capas" para convertir su contenido en '
            'capas editables. Hasta entonces no hay nada que ordenar ni '
            'personalizar por dispositivo.',
            style: TextStyle(color: Colors.white38, fontSize: 11, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _CanvasProductSelector extends StatefulWidget {
  final String currentProductId;
  final ValueChanged<String> onChanged;
  final WebsiteAsyncFieldBinding asyncBinding;

  const _CanvasProductSelector({
    required this.currentProductId,
    required this.onChanged,
    required this.asyncBinding,
  });

  @override
  State<_CanvasProductSelector> createState() => _CanvasProductSelectorState();
}

class _CanvasProductsMultiSelector extends StatefulWidget {
  final List<String> selectedIds;
  final ValueChanged<List<String>> onConfirm;
  final WebsiteAsyncFieldBinding asyncBinding;

  const _CanvasProductsMultiSelector({
    required this.selectedIds,
    required this.onConfirm,
    required this.asyncBinding,
  });

  @override
  State<_CanvasProductsMultiSelector> createState() =>
      _CanvasProductsMultiSelectorState();
}

bool _sameCanvasProductIds(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

class _CanvasProductsMultiSelectorState
    extends State<_CanvasProductsMultiSelector> {
  bool _isLoadingProducts = true;
  List<Map<String, dynamic>> _availableProducts = const [];
  int _loadGeneration = 0;
  Object? _loadedOwnerRevision;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void didUpdateWidget(covariant _CanvasProductsMultiSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_loadedOwnerRevision != widget.asyncBinding.readOwnerIdentity) {
      _availableProducts = const [];
      _loadProducts();
    }
  }

  Future<void> _loadProducts() async {
    final openingBinding = widget.asyncBinding;
    final ownerRevision = openingBinding.readOwnerIdentity;
    final generation = ++_loadGeneration;
    _loadedOwnerRevision = ownerRevision;
    final arm = openingBinding.capture();
    final remoteAuthority = websiteRemoteAuthorityResolver(
      openingBinding: openingBinding,
      remoteArm: arm,
      liveBinding: () => widget.asyncBinding,
      isMounted: () => mounted,
      operation: 'cargar productos del selector Canvas',
    );
    setState(() => _isLoadingProducts = true);
    try {
      final authority = remoteAuthority?.call();
      if (authority == null) {
        throw const WebsiteEditorWriteSupersededException(
          'La sesión del catálogo Canvas cambió.',
        );
      }
      final readGuard = authority.claimForWrite();
      final supabase = Supabase.instance.client;
      readGuard();
      final productsResponse = await supabase
          .from('products')
          .select(
              'id, name, sku, price, image_url, is_active, is_published, stock_quantity, inventory_qty')
          .eq('tenant_id', authority.tenantId)
          .order('name', ascending: true)
          .limit(2000);
      readGuard();
      authority.ensureCurrent();
      if (!mounted ||
          generation != _loadGeneration ||
          widget.asyncBinding.readOwnerIdentity != ownerRevision) {
        return;
      }
      _availableProducts = List<Map<String, dynamic>>.from(productsResponse);
    } on WebsiteEditorWriteSupersededException {
      if (mounted && generation == _loadGeneration) {
        _availableProducts = const [];
      }
    } catch (_) {
      if (mounted &&
          generation == _loadGeneration &&
          widget.asyncBinding.readOwnerIdentity == ownerRevision) {
        _availableProducts = const [];
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _isLoadingProducts = false);
      }
    }
  }

  Future<void> _openPicker() async {
    final selectedIds = List<String>.unmodifiable(widget.selectedIds);
    if (_isLoadingProducts) return;
    final openingBinding = widget.asyncBinding;
    final arm = openingBinding.capture();
    if (arm == null) return;
    if (_availableProducts.isEmpty) {
      await _loadProducts();
      if (!mounted) return;
      if (widget.asyncBinding.identity != openingBinding.identity ||
          !_sameCanvasProductIds(widget.selectedIds, selectedIds)) {
        widget.asyncBinding.commit(
          arm,
          () => WebsiteInlineMutationResult.rejected,
        );
        return;
      }
      if (_availableProducts.isEmpty) {
        final accepted = widget.asyncBinding
            .commit(arm, () => WebsiteInlineMutationResult.unchanged)
            .accepted;
        if (accepted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudieron cargar los productos'),
            ),
          );
        }
        return;
      }
    }

    var armConsumed = false;
    // ignore: use_build_context_synchronously
    await showDialog(
      context: context,
      builder: (ctx) => _ProductPickerDialog(
        availableProducts: _availableProducts,
        selectedIds: selectedIds,
        onConfirm: (next) {
          if (!mounted || armConsumed) return;
          armConsumed = true;
          widget.asyncBinding.commit(arm, () {
            if (!_sameCanvasProductIds(widget.selectedIds, selectedIds)) {
              return WebsiteInlineMutationResult.rejected;
            }
            if (_sameCanvasProductIds(next, selectedIds)) {
              return WebsiteInlineMutationResult.unchanged;
            }
            widget.onConfirm(next);
            return WebsiteInlineMutationResult.committed;
          });
        },
      ),
    );
    if (mounted && !armConsumed) {
      widget.asyncBinding.commit(
        arm,
        () => WebsiteInlineMutationResult.unchanged,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedProducts = widget.selectedIds
        .map((id) => _availableProducts.firstWhere(
              (p) => p['id']?.toString() == id,
              orElse: () => <String, dynamic>{},
            ))
        .where((p) => p.isNotEmpty)
        .map((p) => Map<String, dynamic>.from(p))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Productos seleccionados (${widget.selectedIds.length})',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _isLoadingProducts ? null : _openPicker,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Agregar'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (widget.selectedIds.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white12),
            ),
            child: const Center(
              child: Text(
                'No hay productos seleccionados\nToca "Agregar" para elegir productos',
                style: TextStyle(color: Colors.white38, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ...selectedProducts.map((p) {
            final id = p['id']?.toString() ?? '';
            return _SelectedProductRow(
              product: p,
              onRemove: () {
                final next = List<String>.from(widget.selectedIds)..remove(id);
                widget.onConfirm(next);
              },
            );
          }),
      ],
    );
  }
}

class _CanvasProductSelectorState extends State<_CanvasProductSelector> {
  final _skuController = TextEditingController();
  bool _isSearchingSku = false;
  bool _isLoadingProducts = true;
  List<Map<String, dynamic>> _availableProducts = const [];
  bool _showAdvanced = false;
  int _loadGeneration = 0;
  Object? _loadedOwnerRevision;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void didUpdateWidget(covariant _CanvasProductSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_loadedOwnerRevision != widget.asyncBinding.readOwnerIdentity) {
      _skuController.clear();
      _availableProducts = const [];
      _isSearchingSku = false;
      _loadProducts();
    }
  }

  @override
  void dispose() {
    _skuController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    final openingBinding = widget.asyncBinding;
    final ownerRevision = openingBinding.readOwnerIdentity;
    final generation = ++_loadGeneration;
    _loadedOwnerRevision = ownerRevision;
    final arm = openingBinding.capture();
    final remoteAuthority = websiteRemoteAuthorityResolver(
      openingBinding: openingBinding,
      remoteArm: arm,
      liveBinding: () => widget.asyncBinding,
      isMounted: () => mounted,
      operation: 'cargar el producto del selector Canvas',
    );
    setState(() => _isLoadingProducts = true);
    try {
      final authority = remoteAuthority?.call();
      if (authority == null) {
        throw const WebsiteEditorWriteSupersededException(
          'La sesión del catálogo Canvas cambió.',
        );
      }
      final readGuard = authority.claimForWrite();
      final supabase = Supabase.instance.client;

      // Load active products for picker (and also load currently selected, even if inactive)
      readGuard();
      final productsResponse = await supabase
          .from('products')
          .select(
              'id, name, sku, price, image_url, is_active, is_published, stock_quantity, inventory_qty')
          .eq('tenant_id', authority.tenantId)
          .order('name', ascending: true)
          .limit(2000);
      readGuard();
      if (!mounted ||
          generation != _loadGeneration ||
          widget.asyncBinding.readOwnerIdentity != ownerRevision) {
        return;
      }

      var allProducts = List<Map<String, dynamic>>.from(productsResponse);

      final selectedId = widget.currentProductId.trim();
      if (selectedId.isNotEmpty) {
        final exists =
            allProducts.any((p) => p['id']?.toString() == selectedId);
        if (!exists) {
          final selectedResponse = await supabase
              .from('products')
              .select(
                  'id, name, sku, price, image_url, is_active, is_published, stock_quantity, inventory_qty')
              .eq('tenant_id', authority.tenantId)
              .inFilter('id', [selectedId]);
          readGuard();
          if (!mounted ||
              generation != _loadGeneration ||
              widget.asyncBinding.readOwnerIdentity != ownerRevision) {
            return;
          }
          for (final selected in selectedResponse) {
            allProducts.add(Map<String, dynamic>.from(selected));
          }
        }
      }

      authority.ensureCurrent();
      _availableProducts = allProducts;
    } on WebsiteEditorWriteSupersededException {
      if (mounted && generation == _loadGeneration) {
        _availableProducts = const [];
      }
    } catch (_) {
      if (mounted &&
          generation == _loadGeneration &&
          widget.asyncBinding.readOwnerIdentity == ownerRevision) {
        _availableProducts = const [];
      }
    } finally {
      if (mounted && generation == _loadGeneration) {
        setState(() => _isLoadingProducts = false);
      }
    }
  }

  Future<void> _pickProduct() async {
    final currentProductId = widget.currentProductId;
    if (_isLoadingProducts) return;
    final openingBinding = widget.asyncBinding;
    final arm = openingBinding.capture();
    if (arm == null) return;
    if (_availableProducts.isEmpty) {
      await _loadProducts();
      if (!mounted) return;
      if (widget.asyncBinding.identity != openingBinding.identity ||
          widget.currentProductId != currentProductId) {
        widget.asyncBinding.commit(
          arm,
          () => WebsiteInlineMutationResult.rejected,
        );
        return;
      }
      if (_availableProducts.isEmpty) {
        final accepted = widget.asyncBinding
            .commit(arm, () => WebsiteInlineMutationResult.unchanged)
            .accepted;
        if (accepted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No se pudieron cargar los productos'),
            ),
          );
        }
        return;
      }
    }

    final current = currentProductId.trim();
    final initial = current.isEmpty ? const <String>[] : <String>[current];

    // Reuse the exact same picker dialog used by the Products banner.
    // It is multi-select by design; for single product we just take the first selection.
    // ignore: use_build_context_synchronously
    var armConsumed = false;
    await showDialog(
      context: context,
      builder: (ctx) => _ProductPickerDialog(
        availableProducts: _availableProducts,
        selectedIds: initial,
        onConfirm: (selectedIds) {
          if (!mounted || armConsumed) return;
          armConsumed = true;
          final next = selectedIds.isNotEmpty ? selectedIds.first : '';
          widget.asyncBinding.commit(arm, () {
            if (widget.currentProductId != currentProductId) {
              return WebsiteInlineMutationResult.rejected;
            }
            if (next == currentProductId) {
              return WebsiteInlineMutationResult.unchanged;
            }
            widget.onChanged(next);
            return WebsiteInlineMutationResult.committed;
          });
        },
      ),
    );
    if (mounted && !armConsumed) {
      widget.asyncBinding.commit(
        arm,
        () => WebsiteInlineMutationResult.unchanged,
      );
    }
  }

  Future<void> _findBySku() async {
    final sku = _skuController.text.trim();
    if (sku.isEmpty) return;
    final currentProductId = widget.currentProductId;
    final openingBinding = widget.asyncBinding;
    final ownerRevision = openingBinding.readOwnerIdentity;
    final arm = openingBinding.capture();
    final remoteArm = openingBinding.capture();
    if (arm == null || remoteArm == null) return;
    final remoteAuthority = websiteRemoteAuthorityResolver(
      openingBinding: openingBinding,
      remoteArm: remoteArm,
      liveBinding: () => widget.asyncBinding,
      isMounted: () => mounted,
      operation: 'buscar un producto Canvas por SKU',
    );

    setState(() => _isSearchingSku = true);
    try {
      final authority = remoteAuthority?.call();
      if (authority == null) {
        throw const WebsiteEditorWriteSupersededException(
          'La sesión del catálogo Canvas cambió.',
        );
      }
      final readGuard = authority.claimForWrite();

      readGuard();
      final response = await Supabase.instance.client
          .from('products')
          .select('id, sku, name')
          .eq('tenant_id', authority.tenantId)
          .eq('sku', sku)
          .maybeSingle();
      readGuard();
      authority.ensureCurrent();

      final id = response?['id']?.toString();
      if (id == null || id.isEmpty) {
        if (mounted &&
            widget.asyncBinding
                .commit(arm, () => WebsiteInlineMutationResult.unchanged)
                .accepted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se encontró producto con SKU "$sku"')),
          );
        }
        return;
      }

      if (!mounted) return;
      final outcome = widget.asyncBinding.commit(arm, () {
        if (widget.currentProductId != currentProductId ||
            _skuController.text.trim() != sku) {
          return WebsiteInlineMutationResult.rejected;
        }
        if (id == currentProductId) {
          return WebsiteInlineMutationResult.unchanged;
        }
        widget.onChanged(id);
        return WebsiteInlineMutationResult.committed;
      });
      if (outcome.accepted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Producto seleccionado: ${response?['name'] ?? sku}')),
        );
      }
    } catch (error) {
      if (mounted &&
          widget.asyncBinding
              .commit(arm, () => WebsiteInlineMutationResult.unchanged)
              .accepted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo buscar el SKU: $error')),
        );
      }
    } finally {
      if (mounted && widget.asyncBinding.readOwnerIdentity == ownerRevision) {
        setState(() => _isSearchingSku = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedId = widget.currentProductId.trim();
    final selected = selectedId.isEmpty
        ? null
        : _availableProducts.firstWhere(
            (p) => p['id']?.toString() == selectedId,
            orElse: () => <String, dynamic>{},
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader('Producto'),
        const SizedBox(height: 12),
        Row(
          children: [
            Text(
              selectedId.isEmpty ? 'Ninguno seleccionado' : 'Seleccionado',
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: _isLoadingProducts ? null : _pickProduct,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF00A09D),
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                selectedId.isEmpty ? 'Elegir' : 'Cambiar',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (selectedId.isEmpty ||
            (selected is Map<String, dynamic> && selected.isEmpty))
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white12),
            ),
            child: const Center(
              child: Text(
                'No hay producto seleccionado\nToca "Elegir" para seleccionar uno',
                style: TextStyle(color: Colors.white38, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          _SelectedProductRow(
            product: Map<String, dynamic>.from(selected as Map),
            onRemove: () => widget.onChanged(''),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            TextButton.icon(
              onPressed: _isSearchingSku
                  ? null
                  : () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) {
                          final controller = TextEditingController();
                          return AlertDialog(
                            title: const Text('Buscar por SKU'),
                            content: TextField(
                              controller: controller,
                              decoration: const InputDecoration(
                                labelText: 'SKU',
                                prefixIcon: Icon(Icons.search),
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancelar'),
                              ),
                              FilledButton(
                                onPressed: () {
                                  _skuController.text = controller.text;
                                  Navigator.pop(ctx, true);
                                },
                                child: const Text('Buscar'),
                              ),
                            ],
                          );
                        },
                      );
                      if (ok == true) {
                        // ignore: use_build_context_synchronously
                        await _findBySku();
                      }
                    },
              icon: _isSearchingSku
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search, size: 18),
              label: const Text('Buscar SKU'),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
              child: Text(_showAdvanced ? 'Ocultar avanzado' : 'Avanzado'),
            ),
          ],
        ),
        if (_showAdvanced) ...[
          const SizedBox(height: 8),
          _EditorTextField(
            label: 'Product ID (interno)',
            value: widget.currentProductId,
            asyncBinding: widget.asyncBinding,
            onChanged: (v) => widget.onChanged(v.trim()),
          ),
          const SizedBox(height: 6),
          Text(
            'Tip: este campo usa Product ID (UUID). Normalmente selecciona desde “Elegir”.',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5), fontSize: 11),
          ),
        ],
      ],
    );
  }
}
