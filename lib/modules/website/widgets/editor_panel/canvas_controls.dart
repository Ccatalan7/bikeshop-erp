part of '../website_editor_panel.dart';

/// Controls for the free-position Canvas block (Wix-like).
class _CanvasBlockControls extends StatelessWidget {
  final Map<String, dynamic> data;
  final String blockId;
  final WebsiteEditModeProvider provider;
  final int? slideIndex;
  final bool elementsOnly;
  final bool selectedElementOnly;
  final _InspectorSection? inspectorSection;
  final ValueChanged<List<Map<String, dynamic>>>? onElementsChanged;
  final ValueChanged<String?>? onActiveElementChanged;
  final void Function(String key, dynamic value)? onCanvasSettingChanged;

  const _CanvasBlockControls({
    required this.data,
    required this.blockId,
    required this.provider,
    this.slideIndex,
    this.elementsOnly = false,
    this.selectedElementOnly = false,
    this.inspectorSection,
    this.onElementsChanged,
    this.onActiveElementChanged,
    this.onCanvasSettingChanged,
  });

  List<Map<String, dynamic>> _elements() {
    final raw = data['elements'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  String? _activeElementId() {
    final id = provider
        .canvasElementSelection(blockId, slideIndex: slideIndex)
        ?.toString();
    if (id == null || id.trim().isEmpty) return null;
    return id.trim();
  }

  void _setActive(String? id) {
    if (onActiveElementChanged != null) {
      onActiveElementChanged!(id);
      return;
    }
    final block = provider.getBlock(blockId);
    final blockData = Map<String, dynamic>.from(
      block?['block_data'] ?? const <String, dynamic>{},
    );
    final slides = blockData['slides'];
    provider.selectCanvasElement(
      blockId,
      id,
      slideIndex: slideIndex,
      slideCount: slideIndex == null || slides is! List ? null : slides.length,
    );
  }

  void _setElements(List<Map<String, dynamic>> elements) {
    if (onElementsChanged != null) {
      onElementsChanged!(elements);
      return;
    }
    provider.updateBlockData(blockId, 'elements', elements);
  }

  void _setCanvasSetting(String key, dynamic value) {
    if (onCanvasSettingChanged != null) {
      onCanvasSettingChanged!(key, value);
      return;
    }
    provider.updateBlockData(blockId, key, value);
  }

  void _updateElement(
    String elementId,
    Map<String, dynamic> patch,
  ) {
    final elements = _elements();
    final idx = elements.indexWhere((e) => e['id']?.toString() == elementId);
    if (idx == -1) return;
    elements[idx] = {
      ...elements[idx],
      ...patch,
    };
    _setElements(elements);
  }

  void _deleteElement(String elementId) {
    final elements = _elements()
      ..removeWhere((e) => e['id']?.toString() == elementId);
    _setElements(elements);
    if (_activeElementId() == elementId) {
      _setActive(null);
    }
  }

  void _moveElement(String elementId, int delta) {
    final elements = _elements();
    final idx = elements.indexWhere((e) => e['id']?.toString() == elementId);
    if (idx == -1) return;
    final nextIdx = (idx + delta).clamp(0, elements.length - 1);
    if (nextIdx == idx) return;
    final item = elements.removeAt(idx);
    elements.insert(nextIdx, item);
    _setElements(elements);
  }

  void _moveElementToEdge(String elementId, {required bool front}) {
    final elements = _elements();
    final idx = elements.indexWhere((e) => e['id']?.toString() == elementId);
    if (idx == -1 || elements.length < 2) return;
    final target = front ? elements.length - 1 : 0;
    if (idx == target) return;
    final item = elements.removeAt(idx);
    elements.insert(front ? elements.length : 0, item);
    _setElements(elements);
  }

  void _alignElementToCanvas(String elementId, String alignment) {
    final elements = _elements();
    final idx = elements.indexWhere((e) => e['id']?.toString() == elementId);
    if (idx == -1 || elements[idx]['locked'] == true) return;

    final element = elements[idx];
    final width = (element['w'] as num?)?.toDouble() ?? 200;
    final height = (element['h'] as num?)?.toDouble() ?? 56;
    final designWidth = (data['designWidth'] as num?)?.toDouble() ?? 1200.0;
    final designHeight = (data['designHeight'] as num?)?.toDouble() ??
        (data['blockHeight'] as num?)?.toDouble() ??
        750.0;
    var x = (element['x'] as num?)?.toDouble() ?? 0;
    var y = (element['y'] as num?)?.toDouble() ?? 0;

    switch (alignment) {
      case 'left':
        x = 0;
        break;
      case 'hCenter':
        x = (designWidth - width) / 2;
        break;
      case 'right':
        x = designWidth - width;
        break;
      case 'top':
        y = 0;
        break;
      case 'vCenter':
        y = (designHeight - height) / 2;
        break;
      case 'bottom':
        y = designHeight - height;
        break;
    }
    _updateElement(elementId, {'x': x, 'y': y});
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

  Widget _buildElementArrangeControls(
    Map<String, dynamic> active,
    List<Map<String, dynamic>> elements,
  ) {
    final activeId = active['id']?.toString() ?? '';
    final index = elements.indexWhere((e) => e['id']?.toString() == activeId);
    final locked = active['locked'] == true;
    final canMoveBackward = index > 0;
    final canMoveForward = index >= 0 && index < elements.length - 1;

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
        const _SectionHeader('Orden de capas'),
        const SizedBox(height: 8),
        Row(
          children: [
            _inspectorLayoutAction(
              key: const ValueKey('inspector_layer_backward'),
              label: 'Una atrás',
              icon: Icons.flip_to_back_rounded,
              onPressed:
                  canMoveBackward ? () => _moveElement(activeId, -1) : null,
            ),
            const SizedBox(width: 8),
            _inspectorLayoutAction(
              key: const ValueKey('inspector_layer_forward'),
              label: 'Una adelante',
              icon: Icons.flip_to_front_rounded,
              onPressed:
                  canMoveForward ? () => _moveElement(activeId, 1) : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _inspectorLayoutAction(
              label: 'Al fondo',
              icon: Icons.vertical_align_bottom_rounded,
              onPressed: canMoveBackward
                  ? () => _moveElementToEdge(activeId, front: false)
                  : null,
            ),
            const SizedBox(width: 8),
            _inspectorLayoutAction(
              label: 'Al frente',
              icon: Icons.vertical_align_top_rounded,
              onPressed: canMoveForward
                  ? () => _moveElementToEdge(activeId, front: true)
                  : null,
            ),
          ],
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
                  locked ? null : () => _alignElementToCanvas(activeId, 'left'),
            ),
            const SizedBox(width: 6),
            _inspectorLayoutAction(
              label: 'Centro',
              icon: Icons.align_horizontal_center_rounded,
              onPressed: locked
                  ? null
                  : () => _alignElementToCanvas(activeId, 'hCenter'),
            ),
            const SizedBox(width: 6),
            _inspectorLayoutAction(
              label: 'Derecha',
              icon: Icons.align_horizontal_right_rounded,
              onPressed: locked
                  ? null
                  : () => _alignElementToCanvas(activeId, 'right'),
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
                  locked ? null : () => _alignElementToCanvas(activeId, 'top'),
            ),
            const SizedBox(width: 6),
            _inspectorLayoutAction(
              label: 'Medio',
              icon: Icons.align_vertical_center_rounded,
              onPressed: locked
                  ? null
                  : () => _alignElementToCanvas(activeId, 'vCenter'),
            ),
            const SizedBox(width: 6),
            _inspectorLayoutAction(
              label: 'Abajo',
              icon: Icons.align_vertical_bottom_rounded,
              onPressed: locked
                  ? null
                  : () => _alignElementToCanvas(activeId, 'bottom'),
            ),
          ],
        ),
      ],
    );
  }

  void _addElement(String type) {
    final now = DateTime.now().microsecondsSinceEpoch;
    final id = 'el_$now';
    final elements = _elements();
    final next = createCanvasElement(id: id, type: type);
    elements.add(next);
    _setElements(elements);
    _setActive(id);
  }

  @override
  Widget build(BuildContext context) {
    final height = (data['blockHeight'] as num?)?.toDouble() ?? 420.0;
    final heightMode = (data['heightMode'] ?? 'fixed').toString();
    final vhPct = (data['vhPct'] as num?)?.toDouble() ?? 0.7;
    final fullBleed = (data['fullBleed'] as bool?) ?? false;
    final bg = (data['backgroundColor'] ?? '#FFFFFF').toString();
    final backgroundImageUrl = (data['backgroundImageUrl'] ?? '').toString();
    final focalPointX = (data['focalPointX'] as num?)?.toDouble() ?? 0.5;
    final focalPointY = (data['focalPointY'] as num?)?.toDouble() ?? 0.5;
    final mobileFocalPointX =
        (data['mobileFocalPointX'] as num?)?.toDouble() ?? focalPointX;
    final mobileFocalPointY =
        (data['mobileFocalPointY'] as num?)?.toDouble() ?? focalPointY;
    final backgroundVideoUrl = (data['backgroundVideoUrl'] ?? '').toString();
    final backgroundYoutubeId = (data['backgroundYoutubeId'] ?? '').toString();
    final overlayEnabled = (data['overlayEnabled'] as bool?) ?? false;
    final overlayOpacity = (data['overlayOpacity'] as num?)?.toDouble() ?? 0.35;
    final overlayColor = (data['overlayColor'] ?? '#000000').toString();
    final backgroundFit = (data['backgroundFit'] ?? 'cover').toString();
    final showGrid = (data['showGrid'] as bool?) ?? true;
    final snap = (data['snap'] as bool?) ?? true;
    final gridSize = (data['gridSize'] as num?)?.toDouble() ?? 8.0;
    final snapDistance = (data['snapDistance'] as num?)?.toDouble() ?? 6.0;

    final elements = _elements();
    final activeId = _activeElementId();
    final active = activeId == null
        ? null
        : elements.cast<Map<String, dynamic>?>().firstWhere(
              (e) => e?['id']?.toString() == activeId,
              orElse: () => null,
            );
    final activeType = (active?['type'] ?? '').toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!elementsOnly) ...[
          // ========== BLOCK SETTINGS ==========
          _CollapsibleSection(
            title: 'Block Settings',
            icon: Icons.settings_rounded,
            initiallyExpanded:
                active == null, // Only expanded when no element selected
            children: [
              _EditorToggle(
                label: 'Full-bleed (sin padding)',
                value: fullBleed,
                onChanged: (v) =>
                    provider.updateBlockData(blockId, 'fullBleed', v),
              ),
              const SizedBox(height: 12),
              _EditorDropdown(
                label: 'Altura',
                value: heightMode,
                options: const [
                  ('fixed', 'Fija'),
                  ('viewport', 'Viewport (pantalla)'),
                ],
                onChanged: (v) =>
                    provider.updateBlockData(blockId, 'heightMode', v),
              ),
              const SizedBox(height: 12),
              if (heightMode == 'viewport') ...[
                _EditorSlider(
                  label: 'Viewport height',
                  value: vhPct.clamp(0.2, 1.0),
                  min: 0.2,
                  max: 1.0,
                  divisions: 16,
                  valueLabel: '${(vhPct * 100).toStringAsFixed(0)}%',
                  onChanged: (v) =>
                      provider.updateBlockData(blockId, 'vhPct', v),
                ),
              ] else ...[
                _EditorSlider(
                  label: 'Altura del canvas',
                  value: height.clamp(220, 1600),
                  min: 220,
                  max: 1600,
                  divisions: 69,
                  valueLabel: '${height.toStringAsFixed(0)}px',
                  onChanged: (v) =>
                      provider.updateBlockData(blockId, 'blockHeight', v),
                ),
              ],
              const SizedBox(height: 12),
              WebsiteColorPickerField(
                label: 'Color de fondo',
                value: bg,
                allowAlpha: true,
                onChanged: (v) =>
                    provider.updateBlockData(blockId, 'backgroundColor', v),
              ),
            ],
          ),

          // ========== BACKGROUND & OVERLAY ==========
          _CollapsibleSection(
            title: 'Background & Overlay',
            icon: Icons.image_rounded,
            initiallyExpanded: false, // Always collapsed unless manually opened
            children: [
              _ImagePicker(
                currentUrl: backgroundImageUrl,
                onChanged: (url) => provider.updateBlockData(
                    blockId, 'backgroundImageUrl', url),
              ),
              if (backgroundImageUrl.isNotEmpty) ...[
                const SizedBox(height: 12),
                const _SectionHeader('Foco de imagen'),
                const SizedBox(height: 8),
                FocalPointPicker(
                  imageUrl: backgroundImageUrl,
                  focalX: focalPointX,
                  focalY: focalPointY,
                  onChanged: (x, y) => provider.updateBlockDataMultiple(
                    blockId,
                    {'focalPointX': x, 'focalPointY': y},
                  ),
                ),
                const SizedBox(height: 12),
                const _SectionHeader('Foco móvil'),
                const SizedBox(height: 8),
                FocalPointPicker(
                  imageUrl: backgroundImageUrl,
                  focalX: mobileFocalPointX,
                  focalY: mobileFocalPointY,
                  onChanged: (x, y) => provider.updateBlockDataMultiple(
                    blockId,
                    {'mobileFocalPointX': x, 'mobileFocalPointY': y},
                  ),
                ),
                const SizedBox(height: 12),
                _EditorTextField(
                  label: 'Texto alternativo',
                  value: (data['backgroundImageAltText'] ?? '').toString(),
                  onChanged: (value) => provider.updateBlockData(
                    blockId,
                    'backgroundImageAltText',
                    value,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const _SectionHeader('Video de fondo'),
              const SizedBox(height: 8),
              _VideoPicker(
                currentUrl: backgroundVideoUrl,
                onChanged: (url) => provider.updateBlockDataMultiple(
                  blockId,
                  {
                    'backgroundVideoUrl': url,
                    if (url.isNotEmpty) 'backgroundYoutubeId': '',
                  },
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
                  _EditorTextField(
                    label: 'URL directa de video (mp4/webm)',
                    value: backgroundVideoUrl,
                    onChanged: (v) => provider.updateBlockData(
                      blockId,
                      'backgroundVideoUrl',
                      v,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _EditorTextField(
                    label: 'YouTube URL / ID',
                    value: backgroundYoutubeId,
                    onChanged: (v) {
                      String id = v;
                      if (v.contains('youtube.com') || v.contains('youtu.be')) {
                        final regExp = RegExp(
                          r'^.*((youtu.be\/)|(v\/)|(\/u\/\w\/)|(embed\/)|(watch\?))\??v?=?([^#&?]*).*',
                        );
                        final match = regExp.firstMatch(v);
                        if (match != null && match.groupCount >= 7) {
                          final extracted = match.group(7);
                          if (extracted != null && extracted.isNotEmpty) {
                            id = extracted;
                          }
                        }
                      }
                      provider.updateBlockData(
                        blockId,
                        'backgroundYoutubeId',
                        id,
                      );
                    },
                    hint: 'Pega el enlace o ID',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _EditorDropdown(
                label: 'Fit',
                value: backgroundFit,
                options: const [
                  ('cover', 'Cover'),
                  ('contain', 'Contain'),
                ],
                onChanged: (v) =>
                    provider.updateBlockData(blockId, 'backgroundFit', v),
              ),
              const SizedBox(height: 12),
              _EditorToggle(
                label: 'Overlay',
                value: overlayEnabled,
                onChanged: (v) =>
                    provider.updateBlockData(blockId, 'overlayEnabled', v),
              ),
              if (overlayEnabled) ...[
                const SizedBox(height: 12),
                WebsiteColorPickerField(
                  label: 'Color del overlay',
                  value: overlayColor,
                  allowAlpha: false,
                  onChanged: (v) =>
                      provider.updateBlockData(blockId, 'overlayColor', v),
                ),
                const SizedBox(height: 12),
                _EditorSlider(
                  label: 'Opacidad overlay',
                  value: overlayOpacity.clamp(0.0, 0.9),
                  min: 0.0,
                  max: 0.9,
                  divisions: 18,
                  valueLabel: overlayOpacity.toStringAsFixed(2),
                  onChanged: (v) =>
                      provider.updateBlockData(blockId, 'overlayOpacity', v),
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
              _EditorToggle(
                label: 'Mostrar grid',
                value: showGrid,
                onChanged: (v) =>
                    provider.updateBlockData(blockId, 'showGrid', v),
              ),
              const SizedBox(height: 12),
              _EditorToggle(
                label: 'Snapping',
                value: snap,
                onChanged: (v) => provider.updateBlockData(blockId, 'snap', v),
              ),
              const SizedBox(height: 12),
              _EditorSlider(
                label: 'Tamaño grid',
                value: gridSize.clamp(4, 24),
                min: 4,
                max: 24,
                divisions: 20,
                valueLabel: '${gridSize.toStringAsFixed(0)}px',
                onChanged: (v) =>
                    provider.updateBlockData(blockId, 'gridSize', v),
              ),
              const SizedBox(height: 12),
              _EditorSlider(
                label: 'Distancia snap',
                value: snapDistance.clamp(2, 16),
                min: 2,
                max: 16,
                divisions: 14,
                valueLabel: '${snapDistance.toStringAsFixed(0)}px',
                onChanged: (v) =>
                    provider.updateBlockData(blockId, 'snapDistance', v),
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
              _EditorToggle(
                label: 'Restringir capas al área segura',
                value: data['constrainElementsToSafeArea'] != false,
                onChanged: (value) => _setCanvasSetting(
                  'constrainElementsToSafeArea',
                  value,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                data['constrainElementsToSafeArea'] == false
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

        // ========== CANVAS ELEMENTS ==========
        if (!selectedElementOnly)
          _CollapsibleSection(
            title: 'Canvas Elements (${elements.length})',
            icon: Icons.layers_rounded,
            initiallyExpanded:
                active == null, // Only expanded when no element selected
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _addElement('text'),
                      icon: const Icon(Icons.text_fields_rounded, size: 18),
                      label: const Text('Texto'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _addElement('button'),
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
                      onPressed: () => _addElement('image'),
                      icon: const Icon(Icons.image_outlined, size: 18),
                      label: const Text('Imagen'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _addElement('shape'),
                      icon: const Icon(Icons.rectangle_outlined, size: 18),
                      label: const Text('Forma'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (elements.isEmpty)
                Text(
                  'Agrega elementos y arrástralos en el canvas.',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                )
              else
                Column(
                  children: elements.map((e) {
                    final id = e['id']?.toString() ?? '';
                    final type = (e['type'] ?? 'text').toString();
                    final title = switch (type) {
                      'button' => (e['label'] ?? 'Botón').toString(),
                      'image' =>
                        (e['altText'] ?? 'Imagen').toString().trim().isEmpty
                            ? 'Imagen'
                            : e['altText'].toString(),
                      'shape' => 'Forma',
                      'product' => 'Producto',
                      'productsGallery' => 'Galería de productos',
                      _ => (e['text'] ?? 'Texto').toString(),
                    };
                    final isActive = id == activeId;
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
                          color: Colors.white70,
                          size: 18,
                        ),
                        title: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                        ),
                        onTap: () => _setActive(id),
                        trailing: IconButton(
                          tooltip: 'Eliminar',
                          icon: const Icon(Icons.delete_outline, size: 18),
                          color: Colors.red.shade300,
                          onPressed: () => _deleteElement(id),
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
              Row(
                children: [
                  Expanded(
                    child: _EditorTextField(
                      label: 'X',
                      value: ((active['x'] as num?)?.toDouble() ?? 0)
                          .toStringAsFixed(0),
                      onChanged: (v) {
                        final parsed = double.tryParse(v);
                        if (parsed != null) {
                          _updateElement(activeId!, {'x': parsed});
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _EditorTextField(
                      label: 'Y',
                      value: ((active['y'] as num?)?.toDouble() ?? 0)
                          .toStringAsFixed(0),
                      onChanged: (v) {
                        final parsed = double.tryParse(v);
                        if (parsed != null) {
                          _updateElement(activeId!, {'y': parsed});
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _EditorTextField(
                      label: 'Ancho',
                      value: ((active['w'] as num?)?.toDouble() ?? 200)
                          .toStringAsFixed(0),
                      onChanged: (v) {
                        final parsed = double.tryParse(v);
                        if (parsed != null) {
                          _updateElement(
                            activeId!,
                            {'w': parsed.clamp(40, 2000)},
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _EditorTextField(
                      label: 'Alto',
                      value: ((active['h'] as num?)?.toDouble() ?? 56)
                          .toStringAsFixed(0),
                      onChanged: (v) {
                        final parsed = double.tryParse(v);
                        if (parsed != null) {
                          _updateElement(
                            activeId!,
                            {'h': parsed.clamp(30, 2000)},
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _EditorSlider(
                label: 'Rotación',
                value: ((active['rotation'] as num?)?.toDouble() ?? 0)
                    .clamp(-180, 180),
                min: -180,
                max: 180,
                divisions: 360,
                valueLabel:
                    '${((active['rotation'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}°',
                onChanged: (v) => _updateElement(activeId!, {'rotation': v}),
              ),
              if (((active['rotation'] as num?)?.toDouble() ?? 0).abs() > 0.01)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _updateElement(activeId!, {'rotation': 0}),
                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                    label: const Text('Restablecer rotación'),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF20C5C1),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              _EditorToggle(
                label: 'Bloquear ajustes directos',
                value: active['locked'] == true,
                onChanged: (v) => _updateElement(activeId!, {'locked': v}),
              ),
              const SizedBox(height: 5),
              const Text(
                'Evita mover, redimensionar, recortar o rotar accidentalmente desde el lienzo. Los valores precisos siguen disponibles aquí.',
                style:
                    TextStyle(color: Colors.white38, fontSize: 11, height: 1.3),
              ),
              const SizedBox(height: 12),
              _EditorDropdown(
                label: 'Visibilidad adaptable',
                value: active['showOnMobile'] == true
                    ? 'mobile'
                    : active['hideOnMobile'] == true
                        ? 'desktop'
                        : 'all',
                options: const [
                  ('all', 'Escritorio y móvil'),
                  ('desktop', 'Solo escritorio'),
                  ('mobile', 'Solo móvil'),
                ],
                onChanged: (value) => _updateElement(activeId!, {
                  'hideOnMobile': value == 'desktop',
                  'showOnMobile': value == 'mobile',
                }),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildElementArrangeControls(active, elements),
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
              if (activeType == 'text') ...[
                if (inspectorSection != _InspectorSection.style) ...[
                  _EditorTextField(
                    label: 'Texto',
                    value: active['text']?.toString() ?? '',
                    onChanged: (v) => _updateElement(activeId!, {'text': v}),
                    maxLines: 3,
                  ),
                ],
                if (inspectorSection != _InspectorSection.content) ...[
                  _EditorSlider(
                    label: 'Tamaño fuente',
                    value: ((active['fontSize'] as num?)?.toDouble() ?? 24)
                        .clamp(10, 80),
                    min: 10,
                    max: 80,
                    divisions: 70,
                    valueLabel:
                        '${((active['fontSize'] as num?)?.toDouble() ?? 24).toStringAsFixed(0)}px',
                    onChanged: (v) =>
                        _updateElement(activeId!, {'fontSize': v}),
                  ),
                  const SizedBox(height: 12),
                  _EditorDropdown(
                    label: 'Tipografía del tema',
                    value: (active['fontRole'] ?? 'heading').toString(),
                    options: const [
                      ('heading', 'Títulos'),
                      ('body', 'Texto general'),
                    ],
                    onChanged: (v) =>
                        _updateElement(activeId!, {'fontRole': v}),
                  ),
                  const SizedBox(height: 12),
                  _EditorDropdown(
                    label: 'Peso',
                    value: (active['fontWeight'] ?? 'w600').toString(),
                    options: const [
                      ('w400', 'Normal'),
                      ('w500', 'Medio'),
                      ('w600', 'Semi-bold'),
                      ('w700', 'Bold'),
                    ],
                    onChanged: (v) =>
                        _updateElement(activeId!, {'fontWeight': v}),
                  ),
                  const SizedBox(height: 12),
                  _EditorDropdown(
                    label: 'Alineación',
                    value: (active['align'] ?? 'left').toString(),
                    options: const [
                      ('left', 'Izquierda'),
                      ('center', 'Centro'),
                      ('right', 'Derecha'),
                    ],
                    onChanged: (v) => _updateElement(activeId!, {'align': v}),
                  ),
                  const SizedBox(height: 12),
                  WebsiteColorPickerField(
                    label: 'Color del texto',
                    value: (active['color'] ?? '#111111').toString(),
                    allowAlpha: true,
                    onChanged: (v) => _updateElement(activeId!, {'color': v}),
                  ),
                  const SizedBox(height: 12),
                  _EditorSlider(
                    label: 'Espaciado de letras',
                    value: ((active['letterSpacing'] as num?)?.toDouble() ?? 0)
                        .clamp(-1, 8),
                    min: -1,
                    max: 8,
                    divisions: 18,
                    valueLabel:
                        ((active['letterSpacing'] as num?)?.toDouble() ?? 0)
                            .toStringAsFixed(1),
                    onChanged: (v) =>
                        _updateElement(activeId!, {'letterSpacing': v}),
                  ),
                  const SizedBox(height: 12),
                  _EditorSlider(
                    label: 'Interlineado',
                    value: ((active['lineHeight'] as num?)?.toDouble() ?? 1.1)
                        .clamp(0.8, 2.0),
                    min: 0.8,
                    max: 2.0,
                    divisions: 12,
                    valueLabel:
                        ((active['lineHeight'] as num?)?.toDouble() ?? 1.1)
                            .toStringAsFixed(1),
                    onChanged: (v) =>
                        _updateElement(activeId!, {'lineHeight': v}),
                  ),
                  const SizedBox(height: 12),
                  _EditorToggle(
                    label: 'MAYÚSCULAS',
                    value: active['uppercase'] == true,
                    onChanged: (v) =>
                        _updateElement(activeId!, {'uppercase': v}),
                  ),
                  const SizedBox(height: 12),
                  _EditorDropdown(
                    label: 'Animación',
                    value: (active['anim'] ?? 'none').toString(),
                    options: const [
                      ('none', 'Ninguna'),
                      ('fade', 'Fade'),
                      ('fadeUp', 'Fade up'),
                    ],
                    onChanged: (v) => _updateElement(activeId!, {'anim': v}),
                  ),
                ],
              ] else if (activeType == 'button') ...[
                if (inspectorSection != _InspectorSection.style) ...[
                  WebsiteActionEditor(
                    showVariant: true,
                    value: WebsiteActionValue.resolvePrimary(
                          active,
                          labelKeys: const ['label'],
                          hrefKeys: const ['link'],
                          variantKeys: const ['style'],
                          defaultLabel: 'Botón',
                          defaultHref: '/',
                          defaultVariant: WebsiteActionVariant.fromStorage(
                            active['style']?.toString(),
                          ),
                        ) ??
                        const WebsiteActionValue(
                          label: 'Botón',
                          href: '/',
                        ),
                    onChanged: (action) => _updateElement(activeId!, {
                      'label': action.label,
                      'link': action.href,
                      'style': action.variant.storageValue,
                      'actions': WebsiteActionValue.mergePrimary(
                        active['actions'],
                        action,
                      ),
                    }),
                  ),
                ],
                if (inspectorSection != _InspectorSection.content) ...[
                  _EditorToggle(
                    label: 'Usar estilo global del tema',
                    value: active['inheritTheme'] != false,
                    onChanged: (v) =>
                        _updateElement(activeId!, {'inheritTheme': v}),
                  ),
                  if (active['inheritTheme'] == false) ...[
                    const SizedBox(height: 12),
                    WebsiteColorPickerField(
                      label: 'Color del botón',
                      value: (active['bgColor'] ?? '#00A09D').toString(),
                      allowAlpha: true,
                      onChanged: (v) =>
                          _updateElement(activeId!, {'bgColor': v}),
                    ),
                    const SizedBox(height: 12),
                    WebsiteColorPickerField(
                      label: 'Color del texto',
                      value: (active['fgColor'] ?? '#FFFFFF').toString(),
                      allowAlpha: true,
                      onChanged: (v) =>
                          _updateElement(activeId!, {'fgColor': v}),
                    ),
                    const SizedBox(height: 12),
                    _EditorSlider(
                      label: 'Radio',
                      value: ((active['radius'] as num?)?.toDouble() ?? 12)
                          .clamp(0, 32),
                      min: 0,
                      max: 32,
                      divisions: 32,
                      valueLabel:
                          '${((active['radius'] as num?)?.toDouble() ?? 12).toStringAsFixed(0)}px',
                      onChanged: (v) =>
                          _updateElement(activeId!, {'radius': v}),
                    ),
                    const SizedBox(height: 12),
                    _EditorToggle(
                      label: 'Sombra',
                      value: (active['shadow'] as bool?) ?? false,
                      onChanged: (v) =>
                          _updateElement(activeId!, {'shadow': v}),
                    ),
                    const SizedBox(height: 12),
                    _EditorToggle(
                      label: 'MAYÚSCULAS',
                      value: (active['uppercase'] as bool?) ?? false,
                      onChanged: (v) =>
                          _updateElement(activeId!, {'uppercase': v}),
                    ),
                    const SizedBox(height: 12),
                    _EditorSlider(
                      label: 'Letter spacing',
                      value:
                          ((active['letterSpacing'] as num?)?.toDouble() ?? 0.0)
                              .clamp(0, 6),
                      min: 0,
                      max: 6,
                      divisions: 12,
                      valueLabel:
                          ((active['letterSpacing'] as num?)?.toDouble() ?? 0.0)
                              .toStringAsFixed(1),
                      onChanged: (v) =>
                          _updateElement(activeId!, {'letterSpacing': v}),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _EditorDropdown(
                    label: 'Animación',
                    value: (active['anim'] ?? 'none').toString(),
                    options: const [
                      ('none', 'Ninguna'),
                      ('fade', 'Fade'),
                      ('fadeUp', 'Fade up'),
                    ],
                    onChanged: (v) => _updateElement(activeId!, {'anim': v}),
                  ),
                ],
              ] else if (activeType == 'image') ...[
                if (inspectorSection != _InspectorSection.style) ...[
                  const _SectionHeader('Producto vinculado (opcional)'),
                  const SizedBox(height: 8),
                  _CanvasProductSelector(
                    currentProductId: (active['productId'] ?? '').toString(),
                    onChanged: (id) => _updateElement(activeId!, {
                      'productId': id,
                      'imageSource': id.isEmpty ? 'manual' : 'product',
                    }),
                  ),
                  if ((active['productId'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _EditorDropdown(
                      label: 'Imagen visible',
                      value: (active['imageSource'] ?? 'product').toString(),
                      options: const [
                        ('product', 'Imagen actual del catálogo'),
                        ('manual', 'Imagen seleccionada / recorte'),
                      ],
                      onChanged: (v) =>
                          _updateElement(activeId!, {'imageSource': v}),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      (active['imageSource'] ?? 'product') == 'manual'
                          ? 'La capa conserva el vínculo comercial, pero muestra el recurso seleccionado abajo. Útil para recortes transparentes y campañas.'
                          : 'La capa sigue automáticamente la imagen principal del producto en el catálogo.',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        height: 1.3,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const _SectionHeader('Imagen seleccionada'),
                  const SizedBox(height: 8),
                  _ImagePicker(
                    currentUrl: (active['imageUrl'] ?? '').toString(),
                    allowProductLink: true,
                    onAssetChanged: (selection) => _updateElement(activeId!, {
                      'imageUrl': selection.publicUrl,
                      if (selection.linksProduct) ...{
                        'productId': selection.productId ?? '',
                        'imageSource': selection.productImageIndex == 0
                            ? 'product'
                            : 'manual',
                      } else ...{
                        if (selection.comesFromProduct) 'productId': '',
                        'imageSource': 'manual',
                      },
                    }),
                  ),
                  const SizedBox(height: 12),
                  _EditorTextField(
                    label: 'Texto alternativo',
                    value: (active['altText'] ?? '').toString(),
                    onChanged: (v) => _updateElement(activeId!, {'altText': v}),
                  ),
                ],
                if (inspectorSection != _InspectorSection.content) ...[
                  _EditorDropdown(
                    label: 'Fit',
                    value: (active['fit'] ?? 'cover').toString(),
                    options: const [
                      ('cover', 'Cover'),
                      ('contain', 'Contain'),
                    ],
                    onChanged: (v) => _updateElement(activeId!, {'fit': v}),
                  ),
                  const SizedBox(height: 12),
                  _EditorSlider(
                    label: 'Encuadre horizontal',
                    value:
                        (((active['focalPointX'] as num?)?.toDouble() ?? 0.5) *
                                100)
                            .clamp(0, 100),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    valueLabel:
                        '${((((active['focalPointX'] as num?)?.toDouble() ?? 0.5) * 100)).round()}%',
                    onChanged: (v) =>
                        _updateElement(activeId!, {'focalPointX': v / 100}),
                  ),
                  const SizedBox(height: 12),
                  _EditorSlider(
                    label: 'Encuadre vertical',
                    value:
                        (((active['focalPointY'] as num?)?.toDouble() ?? 0.5) *
                                100)
                            .clamp(0, 100),
                    min: 0,
                    max: 100,
                    divisions: 100,
                    valueLabel:
                        '${((((active['focalPointY'] as num?)?.toDouble() ?? 0.5) * 100)).round()}%',
                    onChanged: (v) =>
                        _updateElement(activeId!, {'focalPointY': v / 100}),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => _updateElement(activeId!, {
                        'fit': 'cover',
                        'focalPointX': 0.5,
                        'focalPointY': 0.5,
                      }),
                      icon: const Icon(Icons.center_focus_strong_rounded,
                          size: 16),
                      label: const Text('Centrar encuadre'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF20C5C1),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                  const Text(
                    'En el lienzo: doble clic o usa Recortar; arrastra la imagen para reencuadrar y sus ocho bordes para cambiar el marco.',
                    style: TextStyle(
                        color: Colors.white38, fontSize: 11, height: 1.3),
                  ),
                  const SizedBox(height: 12),
                  _EditorSlider(
                    label: 'Radio',
                    value: ((active['radius'] as num?)?.toDouble() ?? 12)
                        .clamp(0, 32),
                    min: 0,
                    max: 32,
                    divisions: 32,
                    valueLabel:
                        '${((active['radius'] as num?)?.toDouble() ?? 12).toStringAsFixed(0)}px',
                    onChanged: (v) => _updateElement(activeId!, {'radius': v}),
                  ),
                  const SizedBox(height: 12),
                  _EditorDropdown(
                    label: 'Animación',
                    value: (active['anim'] ?? 'none').toString(),
                    options: const [
                      ('none', 'Ninguna'),
                      ('fade', 'Fade'),
                      ('fadeUp', 'Fade up'),
                    ],
                    onChanged: (v) => _updateElement(activeId!, {'anim': v}),
                  ),
                ],
              ] else if (activeType == 'shape') ...[
                if (inspectorSection != _InspectorSection.style) ...[
                  _EditorDropdown(
                    label: 'Forma',
                    value: (active['shape'] ?? 'rectangle').toString(),
                    options: const [
                      ('rectangle', 'Rectángulo'),
                      ('ellipse', 'Elipse'),
                    ],
                    onChanged: (v) => _updateElement(activeId!, {'shape': v}),
                  ),
                ],
                if (inspectorSection != _InspectorSection.content) ...[
                  WebsiteColorPickerField(
                    label: 'Color de relleno',
                    value: (active['fillColor'] ?? '#1F2937').toString(),
                    allowAlpha: true,
                    onChanged: (v) =>
                        _updateElement(activeId!, {'fillColor': v}),
                  ),
                  const SizedBox(height: 12),
                  WebsiteColorPickerField(
                    label: 'Color de borde',
                    value: (active['borderColor'] ?? '#1F2937').toString(),
                    allowAlpha: true,
                    onChanged: (v) =>
                        _updateElement(activeId!, {'borderColor': v}),
                  ),
                  const SizedBox(height: 12),
                  _EditorSlider(
                    label: 'Borde',
                    value: ((active['borderWidth'] as num?)?.toDouble() ?? 0)
                        .clamp(0, 16),
                    min: 0,
                    max: 16,
                    divisions: 16,
                    valueLabel:
                        '${((active['borderWidth'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}px',
                    onChanged: (v) =>
                        _updateElement(activeId!, {'borderWidth': v}),
                  ),
                  const SizedBox(height: 12),
                  if ((active['shape'] ?? 'rectangle') == 'rectangle')
                    _EditorSlider(
                      label: 'Radio',
                      value: ((active['radius'] as num?)?.toDouble() ?? 0)
                          .clamp(0, 80),
                      min: 0,
                      max: 80,
                      divisions: 40,
                      valueLabel:
                          '${((active['radius'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)}px',
                      onChanged: (v) =>
                          _updateElement(activeId!, {'radius': v}),
                    ),
                ],
              ] else if (activeType == 'product') ...[
                if (inspectorSection != _InspectorSection.style) ...[
                  _CanvasProductSelector(
                    currentProductId: (active['productId'] ?? '').toString(),
                    onChanged: (id) =>
                        _updateElement(activeId!, {'productId': id}),
                  ),
                  const SizedBox(height: 12),
                  _EditorToggle(
                    label: 'Mostrar precio',
                    value: (active['showPrice'] as bool?) ?? true,
                    onChanged: (v) =>
                        _updateElement(activeId!, {'showPrice': v}),
                  ),
                ],
                if (inspectorSection != _InspectorSection.content) ...[
                  _EditorDropdown(
                    label: 'Animación',
                    value: (active['anim'] ?? 'none').toString(),
                    options: const [
                      ('none', 'Ninguna'),
                      ('fade', 'Fade'),
                      ('fadeUp', 'Fade up'),
                    ],
                    onChanged: (v) => _updateElement(activeId!, {'anim': v}),
                  ),
                ],
              ] else if (activeType == 'productsGallery') ...[
                if (inspectorSection != _InspectorSection.style) ...[
                  _EditorDropdown(
                    label: 'Modo',
                    value: (active['mode'] ?? 'latest').toString(),
                    options: const [
                      ('latest', 'Últimos publicados'),
                      ('manual', 'Manual (IDs)'),
                    ],
                    onChanged: (v) => _updateElement(activeId!, {'mode': v}),
                  ),
                  const SizedBox(height: 12),
                  _EditorSlider(
                    label: 'Máx productos',
                    value: ((active['maxProducts'] as num?)?.toDouble() ?? 6)
                        .clamp(1, 24),
                    min: 1,
                    max: 24,
                    divisions: 23,
                    valueLabel: '${(active['maxProducts'] ?? 6)}',
                    onChanged: (v) => _updateElement(
                      activeId!,
                      {'maxProducts': v.round()},
                    ),
                  ),
                  if ((active['mode'] ?? 'latest').toString() == 'manual') ...[
                    const SizedBox(height: 12),
                    _CanvasProductsMultiSelector(
                      selectedIds: ((active['productIds'] as List?) ?? const [])
                          .map((e) => e.toString())
                          .where((e) => e.isNotEmpty)
                          .toList(),
                      onConfirm: (ids) =>
                          _updateElement(activeId!, {'productIds': ids}),
                    ),
                  ],
                ],
                if (inspectorSection != _InspectorSection.content) ...[
                  _EditorDropdown(
                    label: 'Diseño',
                    value: (active['layout'] ?? 'grid').toString(),
                    options: const [
                      ('grid', 'Cuadrícula'),
                      ('carousel', 'Carrusel'),
                    ],
                    onChanged: (v) => _updateElement(activeId!, {'layout': v}),
                  ),
                  const SizedBox(height: 12),
                  if ((active['layout'] ?? 'grid').toString() == 'grid')
                    _EditorSlider(
                      label: 'Columnas',
                      value: ((active['columns'] as num?)?.toDouble() ?? 3)
                          .clamp(1, 4),
                      min: 1,
                      max: 4,
                      divisions: 3,
                      valueLabel: '${(active['columns'] ?? 3)}',
                      onChanged: (v) => _updateElement(
                        activeId!,
                        {'columns': v.round()},
                      ),
                    )
                  else
                    _EditorSlider(
                      label: 'Ancho tarjeta',
                      value: ((active['cardWidth'] as num?)?.toDouble() ?? 300)
                          .clamp(220, 380),
                      min: 220,
                      max: 380,
                      divisions: 32,
                      valueLabel:
                          '${((active['cardWidth'] as num?)?.toDouble() ?? 300).toStringAsFixed(0)}px',
                      onChanged: (v) =>
                          _updateElement(activeId!, {'cardWidth': v}),
                    ),
                  const SizedBox(height: 12),
                  _EditorDropdown(
                    label: 'Animación',
                    value: (active['anim'] ?? 'none').toString(),
                    options: const [
                      ('none', 'Ninguna'),
                      ('fade', 'Fade'),
                      ('fadeUp', 'Fade up'),
                    ],
                    onChanged: (v) => _updateElement(activeId!, {'anim': v}),
                  ),
                ],
              ],
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
}

class _CanvasProductSelector extends StatefulWidget {
  final String currentProductId;
  final ValueChanged<String> onChanged;

  const _CanvasProductSelector({
    required this.currentProductId,
    required this.onChanged,
  });

  @override
  State<_CanvasProductSelector> createState() => _CanvasProductSelectorState();
}

class _CanvasProductsMultiSelector extends StatefulWidget {
  final List<String> selectedIds;
  final ValueChanged<List<String>> onConfirm;

  const _CanvasProductsMultiSelector({
    required this.selectedIds,
    required this.onConfirm,
  });

  @override
  State<_CanvasProductsMultiSelector> createState() =>
      _CanvasProductsMultiSelectorState();
}

class _CanvasProductsMultiSelectorState
    extends State<_CanvasProductsMultiSelector> {
  bool _isLoadingProducts = true;
  List<Map<String, dynamic>> _availableProducts = const [];

  Future<String?> _resolveTenantId() async {
    try {
      final service = context.read<TenantService>();
      return await service.getTenantId();
    } catch (_) {
      return await TenantService().getTenantId();
    }
  }

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoadingProducts = true);
    try {
      final tenantId = await _resolveTenantId();
      if (tenantId == null) {
        _availableProducts = const [];
        return;
      }
      final supabase = Supabase.instance.client;
      final productsResponse = await supabase
          .from('products')
          .select(
              'id, name, sku, price, image_url, is_active, is_published, stock_quantity, inventory_qty')
          .eq('tenant_id', tenantId)
          .order('name', ascending: true)
          .limit(2000);
      _availableProducts = List<Map<String, dynamic>>.from(productsResponse);
    } catch (_) {
      _availableProducts = const [];
    } finally {
      if (mounted) setState(() => _isLoadingProducts = false);
    }
  }

  Future<void> _openPicker() async {
    if (_isLoadingProducts) return;
    if (_availableProducts.isEmpty) {
      await _loadProducts();
      if (!mounted) return;
      if (_availableProducts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudieron cargar los productos')),
        );
        return;
      }
    }

    // ignore: use_build_context_synchronously
    await showDialog(
      context: context,
      builder: (ctx) => _ProductPickerDialog(
        availableProducts: _availableProducts,
        selectedIds: widget.selectedIds,
        onConfirm: (selectedIds) => widget.onConfirm(selectedIds),
      ),
    );
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

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _skuController.dispose();
    super.dispose();
  }

  Future<String?> _resolveTenantId() async {
    try {
      final service = context.read<TenantService>();
      return await service.getTenantId();
    } catch (_) {
      return await TenantService().getTenantId();
    }
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoadingProducts = true);
    try {
      final tenantId = await _resolveTenantId();
      if (tenantId == null) {
        _availableProducts = const [];
        return;
      }
      final supabase = Supabase.instance.client;

      // Load active products for picker (and also load currently selected, even if inactive)
      final productsResponse = await supabase
          .from('products')
          .select(
              'id, name, sku, price, image_url, is_active, is_published, stock_quantity, inventory_qty')
          .eq('tenant_id', tenantId)
          .order('name', ascending: true)
          .limit(2000);

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
              .eq('tenant_id', tenantId)
              .inFilter('id', [selectedId]);
          for (final selected in selectedResponse) {
            allProducts.add(Map<String, dynamic>.from(selected));
          }
        }
      }

      _availableProducts = allProducts;
    } catch (_) {
      _availableProducts = const [];
    } finally {
      if (mounted) setState(() => _isLoadingProducts = false);
    }
  }

  Future<void> _pickProduct() async {
    if (_isLoadingProducts) return;
    if (_availableProducts.isEmpty) {
      await _loadProducts();
      if (!mounted) return;
      if (_availableProducts.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudieron cargar los productos')),
        );
        return;
      }
    }

    final current = widget.currentProductId.trim();
    final initial = current.isEmpty ? const <String>[] : <String>[current];

    // Reuse the exact same picker dialog used by the Products banner.
    // It is multi-select by design; for single product we just take the first selection.
    // ignore: use_build_context_synchronously
    await showDialog(
      context: context,
      builder: (ctx) => _ProductPickerDialog(
        availableProducts: _availableProducts,
        selectedIds: initial,
        onConfirm: (selectedIds) {
          final next = selectedIds.isNotEmpty ? selectedIds.first : '';
          widget.onChanged(next);
        },
      ),
    );
  }

  Future<void> _findBySku() async {
    final sku = _skuController.text.trim();
    if (sku.isEmpty) return;

    setState(() => _isSearchingSku = true);
    try {
      final tenantId = await _resolveTenantId();
      if (tenantId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo identificar el tenant')),
          );
        }
        return;
      }

      final response = await Supabase.instance.client
          .from('products')
          .select('id, sku, name')
          .eq('tenant_id', tenantId)
          .eq('sku', sku)
          .maybeSingle();

      final id = response?['id']?.toString();
      if (id == null || id.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se encontró producto con SKU "$sku"')),
          );
        }
        return;
      }

      widget.onChanged(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Producto seleccionado: ${response?['name'] ?? sku}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSearchingSku = false);
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
