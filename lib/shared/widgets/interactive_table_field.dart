import 'package:flutter/material.dart';

/// Shared table-cell interaction used by the operational desktop tables.
///
/// The visual behavior intentionally matches the Jobs table: a restrained
/// 90 ms hover fill, a subtle hover border and a click cursor. It does not add
/// an idle chip or card around otherwise plain table content.
class InteractiveTableField extends StatefulWidget {
  const InteractiveTableField({
    super.key,
    required this.child,
    required this.onTap,
    this.accentColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    this.borderRadius = const BorderRadius.all(Radius.circular(7)),
    this.maxWidth,
    this.onSecondaryTapDown,
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color? accentColor;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final double? maxWidth;
  final GestureTapDownCallback? onSecondaryTapDown;

  @override
  State<InteractiveTableField> createState() => _InteractiveTableFieldState();
}

class _InteractiveTableFieldState extends State<InteractiveTableField> {
  bool _isHovered = false;

  bool get _isEnabled =>
      widget.onTap != null || widget.onSecondaryTapDown != null;

  @override
  Widget build(BuildContext context) {
    if (!_isEnabled) return widget.child;

    final theme = Theme.of(context);
    final accent = widget.accentColor ?? theme.colorScheme.primary;
    final hoverFill = accent.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.12 : 0.055,
    );
    final idleFill = accent.withValues(alpha: 0);
    final hoverBorder = accent.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.3 : 0.2,
    );
    final idleBorder = accent.withValues(alpha: 0);

    Widget content = widget.child;
    if (widget.maxWidth != null) {
      content = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.maxWidth!),
        child: content,
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onSecondaryTapDown: widget.onSecondaryTapDown,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: _isHovered ? hoverFill : idleFill,
            borderRadius: widget.borderRadius,
            border: Border.all(
              color: _isHovered ? hoverBorder : idleBorder,
              width: 1,
            ),
          ),
          child: content,
        ),
      ),
    );
  }
}
