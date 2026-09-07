import 'package:flutter/material.dart';

import '../themes/vinabike_theme_roles.dart';
import 'vb_segmented.dart' show VbDensity;

/// **A-01 · `VbButton`** — the one button of the shared vocabulary.
///
/// Four variants and no more: `primary` (accent fill, one per decision
/// surface), `secondary` (accent-soft fill with the accent border), `text`
/// (ink only) and `destructive` (danger fill). There is no outlined blue, no
/// success button and no elevated button; a colour-only difference is not a
/// variant, an icon is the same variant with [icon].
///
/// Anatomy from the guide: height by density (compact 32 · comfortable 38 ·
/// touch 48), horizontal padding 14 (16 in comfortable), radius 8, label
/// 12/600 on one line — a label that wraps or truncates was the wrong label.
/// A busy button keeps its label next to the spinner; a disabled button
/// explains itself with [disabledReason] next to it instead of a tooltip.
///
/// Migration target for `ElevatedButton`, `OutlinedButton`, `TextButton`
/// and every `InkWell` with a private style. Nobody passes a `ButtonStyle`
/// by hand again: the theme's 48 px Material buttons are what made the OCR
/// review rows read as «desnivelado» on 2026-09-05.
class VbButton extends StatelessWidget {
  const VbButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = VbButtonVariant.primary,
    this.density,
    this.icon,
    this.busy = false,
    this.disabledReason,
    this.expand = false,
    this.semanticLabel,
  }) : assert(label.length > 0, 'A-01: un botón dice lo que hace.');

  final String label;
  final VoidCallback? onPressed;
  final VbButtonVariant variant;

  /// Defaults to touch under 900 px of logical width, comfortable above.
  /// Rows of a table pass compact.
  final VbDensity? density;
  final IconData? icon;

  /// The action is running: inert, label kept, spinner beside it.
  final bool busy;

  /// Why the button is inert, shown beside it («Se habilita cuando…»).
  final String? disabledReason;

  /// Full-width CTA (phone footers).
  final bool expand;
  final String? semanticLabel;

  static const double radius = 8;
  static const double fontSize = 12;
  static const FontWeight fontWeight = FontWeight.w600;
  static const double iconSize = 15;
  static const double iconGap = 7;

  static double horizontalPadding(VbDensity density) =>
      density == VbDensity.comfortable ? 16 : 14;

  static VbDensity densityOf(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 900
          ? VbDensity.touch
          : VbDensity.comfortable;

  bool get _enabled => onPressed != null && !busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final roles = VinabikeThemeRoles.of(context);
    final resolvedDensity = density ?? densityOf(context);
    final enabled = _enabled;

    final Color fill;
    final Color border;
    final Color foreground;
    switch (variant) {
      case VbButtonVariant.primary:
        fill = enabled
            ? scheme.primary
            : busy
                ? scheme.primary.withValues(alpha: 0.55)
                : scheme.surface;
        border = enabled || busy ? scheme.primary : scheme.outlineVariant;
        foreground =
            enabled || busy ? scheme.onPrimary : roles.disabledForeground;
      case VbButtonVariant.secondary:
        fill = enabled || busy
            ? scheme.primaryContainer
            : scheme.surfaceContainerLow;
        border = enabled || busy ? roles.accentBorder : scheme.outlineVariant;
        foreground =
            enabled || busy ? scheme.primary : roles.disabledForeground;
      case VbButtonVariant.text:
        fill = Colors.transparent;
        border = Colors.transparent;
        foreground =
            enabled || busy ? scheme.primary : roles.disabledForeground;
      case VbButtonVariant.destructive:
        fill = enabled
            ? roles.danger.accent
            : busy
                ? roles.danger.accent.withValues(alpha: 0.55)
                : scheme.surface;
        border = enabled || busy ? roles.danger.accent : scheme.outlineVariant;
        foreground =
            enabled || busy ? roles.danger.onAccent : roles.disabledForeground;
    }

    final labelStyle =
        (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: foreground,
      height: 1.2,
    );
    final labelText = Text(
      label,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: labelStyle,
    );
    final Widget content;
    if (busy) {
      content = Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
        ),
        const SizedBox(width: iconGap),
        Flexible(child: labelText),
      ]);
    } else if (icon != null) {
      content = Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: iconSize, color: foreground),
        const SizedBox(width: iconGap),
        Flexible(child: labelText),
      ]);
    } else {
      content = labelText;
    }

    final button = Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          overlayColor: WidgetStatePropertyAll(
            foreground.withValues(alpha: 0.10),
          ),
          focusColor: roles.focusRing.withValues(alpha: 0.24),
          // `Center(widthFactor: 1)` keeps the button as wide as its label
          // inside a `Wrap` or a `Column`; a `Container` with `alignment`
          // would stretch to the cell and centre the label in it.
          child: SizedBox(
            height: resolvedDensity.controlHeight,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding(resolvedDensity),
              ),
              child: Center(widthFactor: 1, child: content),
            ),
          ),
        ),
      ),
    );
    final sized =
        expand ? SizedBox(width: double.infinity, child: button) : button;
    final reason = disabledReason?.trim();
    if (enabled || busy || reason == null || reason.isEmpty) return sized;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        sized,
        Text(
          reason,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

enum VbButtonVariant { primary, secondary, text, destructive }
