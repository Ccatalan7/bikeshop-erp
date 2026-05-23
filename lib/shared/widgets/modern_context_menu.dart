import 'package:flutter/material.dart';

class ModernContextMenuAction<T> {
  final T value;
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color? iconColor;
  final bool isDestructive;
  final bool enabled;

  const ModernContextMenuAction({
    required this.value,
    required this.icon,
    required this.label,
    this.subtitle,
    this.iconColor,
    this.isDestructive = false,
    this.enabled = true,
  });
}

Future<T?> showModernContextMenu<T>({
  required BuildContext context,
  required Offset globalPosition,
  required List<ModernContextMenuAction<T>> actions,
  String? title,
  double minWidth = 260,
  double maxWidth = 320,
}) {
  final theme = Theme.of(context);
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
  final position = overlay.globalToLocal(globalPosition);

  return showMenu<T>(
    context: context,
    position: RelativeRect.fromLTRB(
      position.dx,
      position.dy,
      overlay.size.width - position.dx,
      overlay.size.height - position.dy,
    ),
    color: Colors.white,
    surfaceTintColor: Colors.transparent,
    elevation: 18,
    shadowColor: Colors.black.withValues(alpha: 0.18),
    constraints: BoxConstraints(
      minWidth: minWidth,
      maxWidth: maxWidth,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: Color(0xFFE2E8F0)),
    ),
    items: [
      if (title != null && title.trim().isNotEmpty)
        PopupMenuItem<T>(
          enabled: false,
          height: 34,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
            ),
          ),
        ),
      ...actions.map(
        (action) => PopupMenuItem<T>(
          value: action.value,
          enabled: action.enabled,
          height: action.subtitle == null ? 50 : 62,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: _ModernContextMenuTile<T>(
            action: action,
            theme: theme,
          ),
        ),
      ),
    ],
  );
}

class _ModernContextMenuTile<T> extends StatelessWidget {
  final ModernContextMenuAction<T> action;
  final ThemeData theme;

  const _ModernContextMenuTile({
    required this.action,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final accent = action.isDestructive
        ? const Color(0xFFDC2626)
        : action.iconColor ?? theme.colorScheme.primary;
    final foreground = action.enabled
        ? (action.isDestructive
            ? const Color(0xFF991B1B)
            : const Color(0xFF111827))
        : const Color(0xFF94A3B8);
    final subtitleColor =
        action.enabled ? const Color(0xFF64748B) : const Color(0xFFCBD5E1);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: action.enabled ? 0.10 : 0.05),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              action.icon,
              size: 17,
              color: action.enabled ? accent : const Color(0xFFCBD5E1),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (action.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    action.subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: subtitleColor,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
