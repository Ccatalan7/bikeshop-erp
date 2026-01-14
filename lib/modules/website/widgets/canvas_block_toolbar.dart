import 'package:flutter/material.dart';

class CanvasElementToolbar extends StatelessWidget {
  final String type;
  final Map<String, dynamic> properties;
  final VoidCallback onDelete;
  final VoidCallback onDuplicate;
  final VoidCallback onBringToFront;
  final VoidCallback onSendToBack;
  final Function(String key, dynamic value) onUpdate;

  const CanvasElementToolbar({
    super.key,
    required this.type,
    required this.properties,
    required this.onDelete,
    required this.onDuplicate,
    required this.onBringToFront,
    required this.onSendToBack,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (type == 'text') ...[
            _buildIconButton(
              icon: Icons.format_bold,
              isActive: properties['fontWeight'] == 'w700',
              onTap: () => onUpdate(
                'fontWeight',
                properties['fontWeight'] == 'w700' ? 'w400' : 'w700',
              ),
            ),
            _buildIconButton(
              icon: Icons.format_italic,
              isActive: properties['fontStyle'] == 'italic',
              onTap: () => onUpdate(
                'fontStyle',
                properties['fontStyle'] == 'italic' ? 'normal' : 'italic',
              ),
            ),
            _buildIconButton(
              icon: Icons.format_underlined,
              isActive: properties['decoration'] == 'underline',
              onTap: () => onUpdate(
                'decoration',
                properties['decoration'] == 'underline' ? 'none' : 'underline',
              ),
            ),
            _buildDivider(),
            _buildIconButton(
              icon: Icons.format_align_left,
              isActive: properties['align'] == 'left',
              onTap: () => onUpdate('align', 'left'),
            ),
            _buildIconButton(
              icon: Icons.format_align_center,
              isActive: properties['align'] == 'center',
              onTap: () => onUpdate('align', 'center'),
            ),
            _buildIconButton(
              icon: Icons.format_align_right,
              isActive: properties['align'] == 'right',
              onTap: () => onUpdate('align', 'right'),
            ),
            _buildDivider(),
            _buildIconButton(
              icon: Icons.remove,
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
              onTap: () {
                final size = (properties['fontSize'] as num?)?.toDouble() ?? 24;
                onUpdate('fontSize', (size + 2).clamp(8.0, 120.0));
              },
            ),
          ],
          if (type == 'button') ...[
            _buildIconButton(
              icon: Icons.circle,
              isActive: properties['style'] == 'filled',
              onTap: () => onUpdate('style', 'filled'),
            ),
            _buildIconButton(
              icon: Icons.circle_outlined,
              isActive: properties['style'] == 'outline',
              onTap: () => onUpdate('style', 'outline'),
            ),
            _buildIconButton(
              icon: Icons.text_fields,
              isActive: properties['style'] == 'text',
              onTap: () => onUpdate('style', 'text'),
            ),
          ],
          if (type == 'image') ...[
            _buildIconButton(
              icon: Icons.fit_screen,
              isActive: properties['fit'] == 'contain',
              onTap: () => onUpdate(
                'fit',
                properties['fit'] == 'contain' ? 'cover' : 'contain',
              ),
            ),
          ],
          _buildDivider(),
          _buildIconButton(
            icon: Icons.vertical_align_top,
            onTap: onBringToFront,
          ),
          _buildIconButton(
            icon: Icons.vertical_align_bottom,
            onTap: onSendToBack,
          ),
          _buildIconButton(
            icon: Icons.content_copy,
            onTap: onDuplicate,
          ),
          _buildIconButton(
            icon: Icons.delete_outline,
            color: Colors.red,
            onTap: onDelete,
          ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onTap,
    bool isActive = false,
    Color? color,
    String? tooltip,
  }) {
    final button = InkWell(
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
    );

    // Only wrap in Tooltip if there's actually a message.
    // This avoids OverlayPortal layout issues during rapid widget removal.
    if (tooltip != null && tooltip.isNotEmpty) {
      return Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 500),
        child: button,
      );
    }
    return button;
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
