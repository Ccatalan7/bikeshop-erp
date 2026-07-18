import 'package:flutter/material.dart';

enum CanvasElementAlignment {
  left,
  horizontalCenter,
  right,
  top,
  verticalCenter,
  bottom,
}

/// One contextual toolbar for every editor-native Canvas layer.
///
/// The primary rail deliberately keeps the two relative layer-order actions
/// visible. Secondary actions use one in-place palette (never an overlay) so
/// the toolbar remains safe inside transformed selection chrome on macOS.
enum _CanvasToolbarView { primary, textAlign, arrange, more }

class CanvasElementToolbar extends StatefulWidget {
  final String type;
  final Map<String, dynamic> properties;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final VoidCallback onBringToFront;
  final VoidCallback onSendToBack;
  final VoidCallback onMoveForward;
  final VoidCallback onMoveBackward;
  final VoidCallback onRotateQuarterTurn;
  final ValueChanged<CanvasElementAlignment> onAlign;
  final VoidCallback? onToggleCrop;
  final VoidCallback? onReplaceImage;
  final VoidCallback? onResetImageFrame;
  final VoidCallback? onRemoveBackground;
  final VoidCallback? onRestoreOriginalImage;
  final VoidCallback? onOpenInspector;
  final bool backgroundRemovalBusy;
  final bool cropActive;
  final double maxWidth;
  final bool hoverLabelBelow;
  final Function(String key, dynamic value) onUpdate;

  const CanvasElementToolbar({
    super.key,
    required this.type,
    required this.properties,
    required this.onDelete,
    required this.onDuplicate,
    required this.onBringToFront,
    required this.onSendToBack,
    required this.onMoveForward,
    required this.onMoveBackward,
    required this.onRotateQuarterTurn,
    required this.onAlign,
    this.onToggleCrop,
    this.onReplaceImage,
    this.onResetImageFrame,
    this.onRemoveBackground,
    this.onRestoreOriginalImage,
    this.onOpenInspector,
    this.backgroundRemovalBusy = false,
    this.cropActive = false,
    this.maxWidth = double.infinity,
    this.hoverLabelBelow = true,
    required this.onUpdate,
  });

  @override
  State<CanvasElementToolbar> createState() => _CanvasElementToolbarState();
}

class _CanvasElementToolbarState extends State<CanvasElementToolbar> {
  static const _accent = Color(0xFF008F8C);

  _CanvasToolbarView _view = _CanvasToolbarView.primary;
  String? _hoverLabel;

  String get type => widget.type;
  Map<String, dynamic> get properties => widget.properties;
  Function(String key, dynamic value) get onUpdate => widget.onUpdate;

  @override
  void didUpdateWidget(covariant CanvasElementToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.type != widget.type ||
        oldWidget.properties['id'] != widget.properties['id']) {
      _view = _CanvasToolbarView.primary;
      _hoverLabel = null;
    }
  }

  void _setView(_CanvasToolbarView view) {
    setState(() {
      _view = view;
      _hoverLabel = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tools = switch (_view) {
      _CanvasToolbarView.primary => _buildPrimaryTools(),
      _CanvasToolbarView.textAlign => _buildTextAlignmentTools(),
      _CanvasToolbarView.arrange => _buildArrangeTools(),
      _CanvasToolbarView.more => _buildMoreTools(),
    };

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFCFCFD),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.16),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Row(mainAxisSize: MainAxisSize.min, children: tools),
            ),
          ),
          if (_hoverLabel != null)
            Positioned(
              left: 0,
              right: 0,
              top: widget.hoverLabelBelow ? 46 : -28,
              height: 24,
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(maxWidth: widget.maxWidth),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF202124),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      _hoverLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildPrimaryTools() {
    return [
      ..._buildTypeTools(),
      _buildDivider(),
      _buildIconButton(
        key: const ValueKey('toolbar_move_backward'),
        icon: Icons.flip_to_back_rounded,
        tooltip: 'Mover una capa atrás',
        compact: true,
        onTap: widget.onMoveBackward,
      ),
      _buildIconButton(
        key: const ValueKey('toolbar_move_forward'),
        icon: Icons.flip_to_front_rounded,
        tooltip: 'Mover una capa adelante',
        compact: true,
        onTap: widget.onMoveForward,
      ),
      _buildIconButton(
        key: const ValueKey('toolbar_arrange'),
        icon: Icons.layers_outlined,
        tooltip: 'Alinear y ordenar capas',
        compact: true,
        onTap: () => _setView(_CanvasToolbarView.arrange),
      ),
      _buildIconButton(
        key: const ValueKey('toolbar_more'),
        icon: Icons.tune_rounded,
        tooltip: 'Más ajustes',
        compact: true,
        onTap: () => _setView(_CanvasToolbarView.more),
      ),
      _buildDivider(),
      _buildIconButton(
        key: const ValueKey('toolbar_duplicate'),
        icon: Icons.content_copy_rounded,
        tooltip: 'Duplicar (⌘/Ctrl+D)',
        compact: true,
        onTap: () {
          _setView(_CanvasToolbarView.primary);
          widget.onDuplicate();
        },
      ),
      _buildIconButton(
        key: const ValueKey('toolbar_delete'),
        icon: Icons.delete_outline_rounded,
        tooltip: 'Eliminar (Supr)',
        color: const Color(0xFFD93025),
        compact: true,
        onTap: () {
          _setView(_CanvasToolbarView.primary);
          widget.onDelete();
        },
      ),
    ];
  }

  List<Widget> _buildTypeTools() {
    switch (type) {
      case 'text':
        return [
          _buildIconButton(
            key: const ValueKey('toolbar_text_bold'),
            icon: Icons.format_bold_rounded,
            tooltip: 'Negrita',
            compact: true,
            isActive: properties['fontWeight'] == 'w700',
            onTap: () => onUpdate(
              'fontWeight',
              properties['fontWeight'] == 'w700' ? 'w400' : 'w700',
            ),
          ),
          _buildIconButton(
            key: const ValueKey('toolbar_text_italic'),
            icon: Icons.format_italic_rounded,
            tooltip: 'Cursiva',
            compact: true,
            isActive: properties['fontStyle'] == 'italic',
            onTap: () => onUpdate(
              'fontStyle',
              properties['fontStyle'] == 'italic' ? 'normal' : 'italic',
            ),
          ),
          _buildIconButton(
            key: const ValueKey('toolbar_text_underline'),
            icon: Icons.format_underlined_rounded,
            tooltip: 'Subrayado',
            compact: true,
            isActive: properties['decoration'] == 'underline',
            onTap: () => onUpdate(
              'decoration',
              properties['decoration'] == 'underline' ? 'none' : 'underline',
            ),
          ),
          _buildFontSizeControl(),
          _buildIconButton(
            key: const ValueKey('toolbar_text_align'),
            icon: _textAlignmentIcon(),
            tooltip: 'Alineación del texto',
            compact: true,
            onTap: () => _setView(_CanvasToolbarView.textAlign),
          ),
        ];
      case 'button':
        return [
          _buildIconButton(
            key: const ValueKey('toolbar_button_filled'),
            icon: Icons.rectangle_rounded,
            tooltip: 'Botón relleno',
            compact: true,
            isActive: (properties['style'] ?? 'filled') == 'filled',
            onTap: () => onUpdate('style', 'filled'),
          ),
          _buildIconButton(
            key: const ValueKey('toolbar_button_outline'),
            icon: Icons.rectangle_outlined,
            tooltip: 'Botón con borde',
            compact: true,
            isActive: properties['style'] == 'outline',
            onTap: () => onUpdate('style', 'outline'),
          ),
          _buildIconButton(
            key: const ValueKey('toolbar_button_text'),
            icon: Icons.title_rounded,
            tooltip: 'Botón de texto',
            compact: true,
            isActive: properties['style'] == 'text',
            onTap: () => onUpdate('style', 'text'),
          ),
        ];
      case 'image':
        return [
          _buildLabeledButton(
            key: const ValueKey('toolbar_replace_image'),
            icon: Icons.photo_library_outlined,
            label: 'Reemplazar',
            tooltip: 'Reemplazar desde la biblioteca',
            onTap: widget.onReplaceImage,
          ),
          _buildIconButton(
            key: const ValueKey('toolbar_image_fit'),
            icon: properties['fit'] == 'contain'
                ? Icons.fit_screen_rounded
                : Icons.crop_free_rounded,
            tooltip: properties['fit'] == 'contain'
                ? 'Rellenar el marco'
                : 'Mostrar imagen completa',
            compact: true,
            isActive: properties['fit'] == 'contain',
            onTap: () => onUpdate(
              'fit',
              properties['fit'] == 'contain' ? 'cover' : 'contain',
            ),
          ),
          _buildIconButton(
            key: const ValueKey('toolbar_crop'),
            icon: widget.cropActive ? Icons.check_rounded : Icons.crop_rounded,
            tooltip: widget.cropActive
                ? 'Terminar recorte'
                : 'Recortar y reencuadrar',
            compact: true,
            isActive: widget.cropActive,
            onTap: widget.onToggleCrop,
          ),
        ];
      case 'shape':
        return [
          _buildIconButton(
            key: const ValueKey('toolbar_shape_rectangle'),
            icon: Icons.rectangle_outlined,
            tooltip: 'Rectángulo',
            compact: true,
            isActive: properties['shape'] != 'ellipse',
            onTap: () => onUpdate('shape', 'rectangle'),
          ),
          _buildIconButton(
            key: const ValueKey('toolbar_shape_ellipse'),
            icon: Icons.circle_outlined,
            tooltip: 'Elipse',
            compact: true,
            isActive: properties['shape'] == 'ellipse',
            onTap: () => onUpdate('shape', 'ellipse'),
          ),
        ];
      case 'product':
        return [
          _buildIconButton(
            key: const ValueKey('toolbar_product_price'),
            icon: Icons.sell_outlined,
            tooltip: properties['showPrice'] != false
                ? 'Ocultar precio'
                : 'Mostrar precio',
            compact: true,
            isActive: properties['showPrice'] != false,
            onTap: () =>
                onUpdate('showPrice', properties['showPrice'] == false),
          ),
        ];
      case 'productsGallery':
        return [
          _buildIconButton(
            key: const ValueKey('toolbar_gallery_layout'),
            icon: properties['layout'] == 'horizontal'
                ? Icons.view_column_outlined
                : Icons.grid_view_rounded,
            tooltip: properties['layout'] == 'horizontal'
                ? 'Usar cuadrícula'
                : 'Usar fila horizontal',
            compact: true,
            isActive: properties['layout'] == 'horizontal',
            onTap: () => onUpdate(
              'layout',
              properties['layout'] == 'horizontal' ? 'grid' : 'horizontal',
            ),
          ),
          _buildIconButton(
            key: const ValueKey('toolbar_gallery_price'),
            icon: Icons.sell_outlined,
            tooltip: properties['showPrice'] != false
                ? 'Ocultar precios'
                : 'Mostrar precios',
            compact: true,
            isActive: properties['showPrice'] != false,
            onTap: () =>
                onUpdate('showPrice', properties['showPrice'] == false),
          ),
        ];
      default:
        return const [];
    }
  }

  List<Widget> _buildTextAlignmentTools() {
    return [
      _buildBackButton(),
      _buildPaletteHeading('Texto'),
      _buildDivider(),
      _buildIconButton(
        key: const ValueKey('toolbar_text_align_left'),
        icon: Icons.format_align_left_rounded,
        tooltip: 'Alinear texto a la izquierda',
        isActive: (properties['align'] ?? 'left') == 'left',
        onTap: () {
          onUpdate('align', 'left');
          _setView(_CanvasToolbarView.primary);
        },
      ),
      _buildIconButton(
        key: const ValueKey('toolbar_text_align_center'),
        icon: Icons.format_align_center_rounded,
        tooltip: 'Centrar texto',
        isActive: properties['align'] == 'center',
        onTap: () {
          onUpdate('align', 'center');
          _setView(_CanvasToolbarView.primary);
        },
      ),
      _buildIconButton(
        key: const ValueKey('toolbar_text_align_right'),
        icon: Icons.format_align_right_rounded,
        tooltip: 'Alinear texto a la derecha',
        isActive: properties['align'] == 'right',
        onTap: () {
          onUpdate('align', 'right');
          _setView(_CanvasToolbarView.primary);
        },
      ),
    ];
  }

  List<Widget> _buildArrangeTools() {
    return [
      _buildBackButton(compact: true),
      _buildIconButton(
        key: const ValueKey('toolbar_send_to_back'),
        icon: Icons.vertical_align_bottom_rounded,
        tooltip: 'Enviar al fondo',
        compact: true,
        onTap: widget.onSendToBack,
      ),
      _buildIconButton(
        key: const ValueKey('toolbar_move_backward_palette'),
        icon: Icons.flip_to_back_rounded,
        tooltip: 'Mover una capa atrás',
        compact: true,
        onTap: widget.onMoveBackward,
      ),
      _buildIconButton(
        key: const ValueKey('toolbar_move_forward_palette'),
        icon: Icons.flip_to_front_rounded,
        tooltip: 'Mover una capa adelante',
        compact: true,
        onTap: widget.onMoveForward,
      ),
      _buildIconButton(
        key: const ValueKey('toolbar_bring_to_front'),
        icon: Icons.vertical_align_top_rounded,
        tooltip: 'Traer al frente',
        compact: true,
        onTap: widget.onBringToFront,
      ),
      _buildDivider(),
      _buildIconButton(
        key: const ValueKey('toolbar_align_left'),
        icon: Icons.align_horizontal_left_rounded,
        tooltip: 'Alinear al borde izquierdo',
        compact: true,
        onTap: () => widget.onAlign(CanvasElementAlignment.left),
      ),
      _buildIconButton(
        key: const ValueKey('toolbar_align_horizontal_center'),
        icon: Icons.align_horizontal_center_rounded,
        tooltip: 'Centrar horizontalmente',
        compact: true,
        onTap: () => widget.onAlign(CanvasElementAlignment.horizontalCenter),
      ),
      _buildIconButton(
        key: const ValueKey('toolbar_align_right'),
        icon: Icons.align_horizontal_right_rounded,
        tooltip: 'Alinear al borde derecho',
        compact: true,
        onTap: () => widget.onAlign(CanvasElementAlignment.right),
      ),
      _buildIconButton(
        key: const ValueKey('toolbar_align_top'),
        icon: Icons.align_vertical_top_rounded,
        tooltip: 'Alinear arriba',
        compact: true,
        onTap: () => widget.onAlign(CanvasElementAlignment.top),
      ),
      _buildIconButton(
        key: const ValueKey('toolbar_align_vertical_center'),
        icon: Icons.align_vertical_center_rounded,
        tooltip: 'Centrar verticalmente',
        compact: true,
        onTap: () => widget.onAlign(CanvasElementAlignment.verticalCenter),
      ),
      _buildIconButton(
        key: const ValueKey('toolbar_align_bottom'),
        icon: Icons.align_vertical_bottom_rounded,
        tooltip: 'Alinear abajo',
        compact: true,
        onTap: () => widget.onAlign(CanvasElementAlignment.bottom),
      ),
    ];
  }

  List<Widget> _buildMoreTools() {
    final locked = properties['locked'] == true;
    final hasRotation =
        ((properties['rotation'] as num?)?.toDouble() ?? 0).abs() > 0.01;

    return [
      _buildBackButton(),
      _buildPaletteHeading('Más'),
      _buildDivider(),
      if (widget.onOpenInspector != null)
        _buildLabeledButton(
          key: const ValueKey('toolbar_open_inspector'),
          icon: Icons.tune_rounded,
          label: 'Inspector',
          tooltip: 'Abrir los ajustes precisos',
          onTap: widget.onOpenInspector,
        ),
      if (type == 'image' && widget.onResetImageFrame != null)
        _buildIconButton(
          key: const ValueKey('toolbar_reset_image_frame'),
          icon: Icons.center_focus_strong_rounded,
          tooltip: 'Centrar encuadre',
          onTap: widget.onResetImageFrame,
        ),
      if (type == 'image' && widget.onRemoveBackground != null)
        _buildIconButton(
          key: const ValueKey('toolbar_remove_background'),
          icon: widget.backgroundRemovalBusy
              ? Icons.hourglass_top_rounded
              : Icons.auto_fix_high_rounded,
          tooltip:
              widget.backgroundRemovalBusy ? 'Quitando fondo…' : 'Quitar fondo',
          isActive: widget.backgroundRemovalBusy,
          onTap:
              widget.backgroundRemovalBusy ? null : widget.onRemoveBackground,
        ),
      if (type == 'image' && widget.onRestoreOriginalImage != null)
        _buildIconButton(
          key: const ValueKey('toolbar_restore_background'),
          icon: Icons.restore_rounded,
          tooltip: 'Restaurar imagen original',
          onTap: widget.onRestoreOriginalImage,
        ),
      _buildIconButton(
        key: const ValueKey('toolbar_rotate_90'),
        icon: Icons.rotate_90_degrees_cw_rounded,
        tooltip: 'Girar 90°',
        onTap: widget.onRotateQuarterTurn,
      ),
      if (hasRotation)
        _buildIconButton(
          key: const ValueKey('toolbar_reset_rotation'),
          icon: Icons.restart_alt_rounded,
          tooltip: 'Restablecer rotación',
          onTap: () => onUpdate('rotation', 0.0),
        ),
      _buildIconButton(
        key: const ValueKey('toolbar_lock'),
        icon: locked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
        tooltip: locked
            ? 'Desbloquear ajustes directos'
            : 'Bloquear ajustes directos',
        isActive: locked,
        onTap: () => onUpdate('locked', !locked),
      ),
    ];
  }

  Widget _buildFontSizeControl() {
    final size = (properties['fontSize'] as num?)?.toDouble() ?? 24;
    return Container(
      height: 32,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildIconButton(
            key: const ValueKey('toolbar_font_smaller'),
            icon: Icons.remove_rounded,
            tooltip: 'Reducir texto',
            compact: true,
            onTap: () => onUpdate('fontSize', (size - 2).clamp(8.0, 120.0)),
          ),
          Semantics(
            label: 'Tamaño de texto ${size.round()} píxeles',
            child: SizedBox(
              width: 26,
              child: Text(
                '${size.round()}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF3C4043),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          _buildIconButton(
            key: const ValueKey('toolbar_font_larger'),
            icon: Icons.add_rounded,
            tooltip: 'Aumentar texto',
            compact: true,
            onTap: () => onUpdate('fontSize', (size + 2).clamp(8.0, 120.0)),
          ),
        ],
      ),
    );
  }

  IconData _textAlignmentIcon() {
    return switch ((properties['align'] ?? 'left').toString()) {
      'center' => Icons.format_align_center_rounded,
      'right' => Icons.format_align_right_rounded,
      _ => Icons.format_align_left_rounded,
    };
  }

  Widget _buildBackButton({bool compact = false}) {
    return _buildIconButton(
      key: const ValueKey('toolbar_back'),
      icon: Icons.arrow_back_rounded,
      tooltip: 'Volver a herramientas principales',
      compact: compact,
      onTap: () => _setView(_CanvasToolbarView.primary),
    );
  }

  Widget _buildPaletteHeading(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF5F6368),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildLabeledButton({
    Key? key,
    required IconData icon,
    required String label,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Semantics(
      key: key,
      button: true,
      enabled: enabled,
      label: tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoverLabel = tooltip),
        onExit: (_) => _clearHoverLabel(tooltip),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: enabled ? const Color(0xFF3C4043) : Colors.black26,
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: enabled ? const Color(0xFF3C4043) : Colors.black26,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    Key? key,
    required IconData icon,
    required VoidCallback? onTap,
    bool isActive = false,
    bool compact = false,
    Color? color,
    required String tooltip,
  }) {
    final enabled = onTap != null;
    return Semantics(
      key: key,
      button: true,
      enabled: enabled,
      selected: isActive,
      label: tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoverLabel = tooltip),
        onExit: (_) => _clearHoverLabel(tooltip),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: compact ? 26 : 32,
            height: 32,
            margin: compact ? EdgeInsets.zero : const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: isActive ? _accent.withValues(alpha: 0.12) : null,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              icon,
              size: compact ? 16 : 18,
              color: !enabled
                  ? Colors.black26
                  : isActive
                      ? _accent
                      : (color ?? const Color(0xFF3C4043)),
            ),
          ),
        ),
      ),
    );
  }

  void _clearHoverLabel(String label) {
    if (_hoverLabel == label) {
      setState(() => _hoverLabel = null);
    }
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.black.withValues(alpha: 0.1),
    );
  }
}
