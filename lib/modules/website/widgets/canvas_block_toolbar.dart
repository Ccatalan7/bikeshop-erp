import 'package:flutter/material.dart';

enum CanvasElementAlignment {
  left,
  horizontalCenter,
  right,
  top,
  verticalCenter,
  bottom,
}

enum _CanvasToolbarView { primary, align, layers }

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
  _CanvasToolbarView _view = _CanvasToolbarView.primary;
  String? _hoverLabel;

  String get type => widget.type;
  Map<String, dynamic> get properties => widget.properties;
  VoidCallback get onDelete => widget.onDelete;
  VoidCallback get onDuplicate => widget.onDuplicate;
  VoidCallback get onBringToFront => widget.onBringToFront;
  VoidCallback get onSendToBack => widget.onSendToBack;
  VoidCallback get onMoveForward => widget.onMoveForward;
  VoidCallback get onMoveBackward => widget.onMoveBackward;
  VoidCallback get onRotateQuarterTurn => widget.onRotateQuarterTurn;
  ValueChanged<CanvasElementAlignment> get onAlign => widget.onAlign;
  VoidCallback? get onToggleCrop => widget.onToggleCrop;
  VoidCallback? get onReplaceImage => widget.onReplaceImage;
  VoidCallback? get onResetImageFrame => widget.onResetImageFrame;
  VoidCallback? get onRemoveBackground => widget.onRemoveBackground;
  VoidCallback? get onRestoreOriginalImage => widget.onRestoreOriginalImage;
  bool get cropActive => widget.cropActive;
  Function(String key, dynamic value) get onUpdate => widget.onUpdate;

  @override
  void didUpdateWidget(covariant CanvasElementToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.type != widget.type) {
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
      _CanvasToolbarView.align => _buildAlignmentTools(),
      _CanvasToolbarView.layers => _buildLayerTools(),
    };
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.maxWidth),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(mainAxisSize: MainAxisSize.min, children: tools),
            ),
          ),
          if (_hoverLabel != null)
            Positioned(
              left: 0,
              right: 0,
              top: widget.hoverLabelBelow ? 44 : -28,
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
      if (type == 'text') ...[
        _buildIconButton(
          icon: Icons.format_bold,
          tooltip: 'Negrita',
          isActive: properties['fontWeight'] == 'w700',
          onTap: () => onUpdate(
            'fontWeight',
            properties['fontWeight'] == 'w700' ? 'w400' : 'w700',
          ),
        ),
        _buildIconButton(
          icon: Icons.format_italic,
          tooltip: 'Cursiva',
          isActive: properties['fontStyle'] == 'italic',
          onTap: () => onUpdate(
            'fontStyle',
            properties['fontStyle'] == 'italic' ? 'normal' : 'italic',
          ),
        ),
        _buildIconButton(
          icon: Icons.format_underlined,
          tooltip: 'Subrayado',
          isActive: properties['decoration'] == 'underline',
          onTap: () => onUpdate(
            'decoration',
            properties['decoration'] == 'underline' ? 'none' : 'underline',
          ),
        ),
        _buildDivider(),
        _buildIconButton(
          icon: Icons.format_align_left,
          tooltip: 'Alinear texto a la izquierda',
          isActive: properties['align'] == 'left',
          onTap: () => onUpdate('align', 'left'),
        ),
        _buildIconButton(
          icon: Icons.format_align_center,
          tooltip: 'Centrar texto',
          isActive: properties['align'] == 'center',
          onTap: () => onUpdate('align', 'center'),
        ),
        _buildIconButton(
          icon: Icons.format_align_right,
          tooltip: 'Alinear texto a la derecha',
          isActive: properties['align'] == 'right',
          onTap: () => onUpdate('align', 'right'),
        ),
        _buildDivider(),
        _buildIconButton(
          icon: Icons.remove,
          tooltip: 'Reducir texto',
          onTap: () {
            final size = (properties['fontSize'] as num?)?.toDouble() ?? 24;
            onUpdate('fontSize', (size - 2).clamp(8.0, 120.0));
          },
        ),
        Text(
          '${(properties['fontSize'] as num?)?.toInt() ?? 24}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        _buildIconButton(
          icon: Icons.add,
          tooltip: 'Aumentar texto',
          onTap: () {
            final size = (properties['fontSize'] as num?)?.toDouble() ?? 24;
            onUpdate('fontSize', (size + 2).clamp(8.0, 120.0));
          },
        ),
      ],
      if (type == 'button') ...[
        _buildIconButton(
          icon: Icons.circle,
          tooltip: 'Botón relleno',
          isActive: properties['style'] == 'filled',
          onTap: () => onUpdate('style', 'filled'),
        ),
        _buildIconButton(
          icon: Icons.circle_outlined,
          tooltip: 'Botón con borde',
          isActive: properties['style'] == 'outline',
          onTap: () => onUpdate('style', 'outline'),
        ),
        _buildIconButton(
          icon: Icons.text_fields,
          tooltip: 'Botón de texto',
          isActive: properties['style'] == 'text',
          onTap: () => onUpdate('style', 'text'),
        ),
      ],
      if (type == 'image') ...[
        _buildIconButton(
          key: const ValueKey('toolbar_replace_image'),
          icon: Icons.photo_library_outlined,
          tooltip: 'Reemplazar desde Biblioteca',
          onTap: onReplaceImage ?? () {},
        ),
        _buildIconButton(
          icon: Icons.fit_screen,
          tooltip: properties['fit'] == 'contain'
              ? 'Rellenar el marco'
              : 'Mostrar imagen completa',
          isActive: properties['fit'] == 'contain',
          onTap: () => onUpdate(
            'fit',
            properties['fit'] == 'contain' ? 'cover' : 'contain',
          ),
        ),
        _buildIconButton(
          key: const ValueKey('toolbar_crop'),
          icon: Icons.crop_rounded,
          tooltip: cropActive ? 'Terminar recorte' : 'Recortar y reencuadrar',
          isActive: cropActive,
          onTap: onToggleCrop ?? () {},
        ),
        if (onResetImageFrame != null)
          _buildIconButton(
            icon: Icons.center_focus_strong_rounded,
            tooltip: 'Centrar encuadre',
            onTap: onResetImageFrame!,
          ),
        if (onRemoveBackground != null)
          _buildIconButton(
            key: const ValueKey('toolbar_remove_background'),
            icon: widget.backgroundRemovalBusy
                ? Icons.hourglass_top_rounded
                : Icons.auto_fix_high_rounded,
            tooltip: widget.backgroundRemovalBusy
                ? 'Quitando fondo...'
                : 'Quitar fondo',
            isActive: widget.backgroundRemovalBusy,
            onTap: widget.backgroundRemovalBusy ? () {} : onRemoveBackground!,
          ),
        if (onRestoreOriginalImage != null)
          _buildIconButton(
            key: const ValueKey('toolbar_restore_background'),
            icon: Icons.restore_rounded,
            tooltip: 'Restaurar imagen original',
            onTap: onRestoreOriginalImage!,
          ),
      ],
      if (type == 'shape') ...[
        _buildIconButton(
          icon: Icons.rectangle_outlined,
          tooltip: 'Rectángulo',
          isActive: properties['shape'] != 'ellipse',
          onTap: () => onUpdate('shape', 'rectangle'),
        ),
        _buildIconButton(
          icon: Icons.circle_outlined,
          tooltip: 'Elipse',
          isActive: properties['shape'] == 'ellipse',
          onTap: () => onUpdate('shape', 'ellipse'),
        ),
      ],
      _buildDivider(),
      _buildIconButton(
        key: const ValueKey('toolbar_rotate_90'),
        icon: Icons.rotate_90_degrees_cw_rounded,
        tooltip: 'Girar 90°',
        onTap: onRotateQuarterTurn,
      ),
      _buildIconButton(
        key: const ValueKey('toolbar_more'),
        icon: Icons.more_horiz_rounded,
        tooltip: 'Alinear y ordenar',
        onTap: () => _setView(_CanvasToolbarView.align),
      ),
      _buildIconButton(
        key: const ValueKey('toolbar_duplicate'),
        icon: Icons.content_copy,
        tooltip: 'Duplicar',
        onTap: () {
          _setView(_CanvasToolbarView.primary);
          onDuplicate();
        },
      ),
      _buildIconButton(
        key: const ValueKey('toolbar_delete'),
        icon: Icons.delete_outline,
        tooltip: 'Eliminar',
        color: Colors.red,
        onTap: () {
          _setView(_CanvasToolbarView.primary);
          onDelete();
        },
      ),
    ];
  }

  List<Widget> _buildAlignmentTools() {
    final locked = properties['locked'] == true;
    final hasRotation =
        ((properties['rotation'] as num?)?.toDouble() ?? 0).abs() > 0.01;
    return [
      _buildIconButton(
        key: const ValueKey('toolbar_back'),
        icon: Icons.arrow_back_rounded,
        tooltip: 'Volver',
        onTap: () => _setView(_CanvasToolbarView.primary),
      ),
      _buildDivider(),
      _buildIconButton(
        key: const ValueKey('toolbar_align_left'),
        icon: Icons.align_horizontal_left_rounded,
        tooltip: 'Alinear a la izquierda',
        onTap: () => onAlign(CanvasElementAlignment.left),
      ),
      _buildIconButton(
        icon: Icons.align_horizontal_center_rounded,
        tooltip: 'Centrar horizontalmente',
        onTap: () => onAlign(CanvasElementAlignment.horizontalCenter),
      ),
      _buildIconButton(
        icon: Icons.align_horizontal_right_rounded,
        tooltip: 'Alinear a la derecha',
        onTap: () => onAlign(CanvasElementAlignment.right),
      ),
      _buildDivider(),
      _buildIconButton(
        icon: Icons.align_vertical_top_rounded,
        tooltip: 'Alinear arriba',
        onTap: () => onAlign(CanvasElementAlignment.top),
      ),
      _buildIconButton(
        icon: Icons.align_vertical_center_rounded,
        tooltip: 'Centrar verticalmente',
        onTap: () => onAlign(CanvasElementAlignment.verticalCenter),
      ),
      _buildIconButton(
        icon: Icons.align_vertical_bottom_rounded,
        tooltip: 'Alinear abajo',
        onTap: () => onAlign(CanvasElementAlignment.bottom),
      ),
      _buildDivider(),
      _buildIconButton(
        key: const ValueKey('toolbar_layers'),
        icon: Icons.layers_outlined,
        tooltip: 'Orden de capas',
        onTap: () => _setView(_CanvasToolbarView.layers),
      ),
      _buildIconButton(
        icon: locked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
        tooltip: locked
            ? 'Desbloquear ajustes directos'
            : 'Bloquear ajustes directos',
        onTap: () {
          _setView(_CanvasToolbarView.primary);
          onUpdate('locked', !locked);
        },
      ),
      if (hasRotation)
        _buildIconButton(
          icon: Icons.restart_alt_rounded,
          tooltip: 'Restablecer rotación',
          onTap: () {
            _setView(_CanvasToolbarView.primary);
            onUpdate('rotation', 0.0);
          },
        ),
    ];
  }

  List<Widget> _buildLayerTools() {
    return [
      _buildIconButton(
        key: const ValueKey('toolbar_back_to_align'),
        icon: Icons.arrow_back_rounded,
        tooltip: 'Volver a alineación',
        onTap: () => _setView(_CanvasToolbarView.align),
      ),
      _buildDivider(),
      _buildIconButton(
        icon: Icons.flip_to_front_rounded,
        tooltip: 'Mover una capa adelante',
        onTap: onMoveForward,
      ),
      _buildIconButton(
        icon: Icons.flip_to_back_rounded,
        tooltip: 'Mover una capa atrás',
        onTap: onMoveBackward,
      ),
      _buildIconButton(
        icon: Icons.vertical_align_top_rounded,
        tooltip: 'Traer al frente',
        onTap: onBringToFront,
      ),
      _buildIconButton(
        icon: Icons.vertical_align_bottom_rounded,
        tooltip: 'Enviar al fondo',
        onTap: onSendToBack,
      ),
    ];
  }

  Widget _buildIconButton({
    Key? key,
    required IconData icon,
    required VoidCallback onTap,
    bool isActive = false,
    Color? color,
    required String tooltip,
  }) {
    return Semantics(
      key: key,
      button: true,
      selected: isActive,
      label: tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hoverLabel = tooltip),
        onExit: (_) {
          if (_hoverLabel == tooltip) {
            setState(() => _hoverLabel = null);
          }
        },
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isActive ? Colors.black.withValues(alpha: 0.06) : null,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              icon,
              size: 18,
              color: isActive ? Colors.blue : (color ?? Colors.black87),
            ),
          ),
        ),
      ),
    );
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
