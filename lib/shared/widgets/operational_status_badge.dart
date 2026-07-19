import 'package:flutter/material.dart';

import 'interactive_table_field.dart';

/// Canonical operational status badge shared by Jobs and other dense tables.
///
/// This is the Jobs-table implementation extracted without changing its
/// palette, dimensions, typography, animation or interactive treatment.
class OperationalStatusBadge extends StatelessWidget {
  const OperationalStatusBadge({
    super.key,
    required this.label,
    required this.accentColor,
    this.timestamp,
    this.metaText,
    this.metaIcon = Icons.access_time_rounded,
    this.onTap,
    this.maxWidth = 132,
    this.compact = false,
    this.tooltip,
  });

  final String label;
  final Color accentColor;
  final DateTime? timestamp;
  final String? metaText;
  final IconData metaIcon;
  final VoidCallback? onTap;
  final double maxWidth;
  final bool compact;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = _statusBadgePalette(accentColor, theme);
    final constrainedMaxWidth = maxWidth.isFinite ? maxWidth : 132.0;
    final minWidthTarget = compact ? 84.0 : 108.0;
    final minWidth = constrainedMaxWidth < minWidthTarget
        ? constrainedMaxWidth
        : minWidthTarget;
    final radius = BorderRadius.circular(7);
    final normalizedLabel =
        label.trim().isEmpty ? 'SIN ESTADO' : label.trim().toUpperCase();

    final badge = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      width: constrainedMaxWidth,
      constraints: BoxConstraints(
        minWidth: minWidth,
        maxWidth: constrainedMaxWidth,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: timestamp == null && metaText == null ? 6 : 5,
      ),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: radius,
        border: Border.all(color: palette.border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: theme.brightness == Brightness.dark ? 0.18 : 0.06,
            ),
            blurRadius: 5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 5 : 6,
                height: compact ? 5 : 6,
                decoration: BoxDecoration(
                  color: palette.dot,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: palette.dot.withValues(alpha: 0.22),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  normalizedLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 10.5 : 11.5,
                    fontWeight: FontWeight.w700,
                    height: 1.05,
                    letterSpacing: 0,
                    color: palette.foreground,
                  ),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 3),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: compact ? 13 : 15,
                  color: palette.foreground,
                ),
              ],
            ],
          ),
          if (timestamp != null) ...[
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.access_time_rounded,
                  size: compact ? 9 : 10,
                  color: palette.meta,
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    _formatStatusTimestamp(timestamp!),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 9 : 9.5,
                      fontWeight: FontWeight.w500,
                      height: 1.05,
                      color: palette.meta,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (metaText != null) ...[
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  metaIcon,
                  size: compact ? 9 : 10,
                  color: palette.meta,
                ),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    metaText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: compact ? 9 : 9.5,
                      fontWeight: FontWeight.w500,
                      height: 1.05,
                      color: palette.meta,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return tooltip == null ? badge : Tooltip(message: tooltip!, child: badge);
    }

    return Tooltip(
      message: tooltip ?? 'Cambiar estado y ver acciones',
      child: InteractiveTableField(
        onTap: onTap,
        accentColor: accentColor,
        padding: EdgeInsets.zero,
        borderRadius: radius,
        child: badge,
      ),
    );
  }
}

({Color background, Color border, Color foreground, Color meta, Color dot})
    _statusBadgePalette(Color accentColor, ThemeData theme) {
  final hsl = HSLColor.fromColor(accentColor);
  final isNeutral = hsl.saturation < 0.12;
  final isDark = theme.brightness == Brightness.dark;

  if (isNeutral) {
    return (
      background: isDark
          ? theme.colorScheme.surfaceContainerHigh
          : const Color(0xFFF8FAFC),
      border: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
      foreground: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
      meta: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
      dot: isDark ? const Color(0xFF94A3B8) : const Color(0xFF94A3B8),
    );
  }

  final surface =
      isDark ? theme.colorScheme.surfaceContainerHigh : Colors.white;
  final borderBase = isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB);
  final foreground = hsl
      .withSaturation((hsl.saturation * 0.82).clamp(0.42, 0.78).toDouble())
      .withLightness(
        (hsl.lightness * (isDark ? 1.12 : 0.68))
            .clamp(isDark ? 0.62 : 0.34, isDark ? 0.78 : 0.46)
            .toDouble(),
      )
      .toColor();

  return (
    background: Color.alphaBlend(
      accentColor.withValues(alpha: isDark ? 0.16 : 0.07),
      surface,
    ),
    border: Color.alphaBlend(
      accentColor.withValues(alpha: isDark ? 0.38 : 0.2),
      borderBase,
    ),
    foreground: foreground,
    meta: foreground.withValues(alpha: isDark ? 0.78 : 0.68),
    dot: accentColor,
  );
}

String _formatStatusTimestamp(DateTime timestamp) {
  final now = DateTime.now();
  final diff = now.difference(timestamp);

  if (diff.inMinutes < 1) return 'ahora';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes}m';
  if (diff.inHours < 24) return 'hace ${diff.inHours}h';
  if (diff.inDays < 7) return 'hace ${diff.inDays}d';

  const months = [
    'ene',
    'feb',
    'mar',
    'abr',
    'may',
    'jun',
    'jul',
    'ago',
    'sep',
    'oct',
    'nov',
    'dic',
  ];
  return '${timestamp.day} ${months[timestamp.month - 1]}';
}
