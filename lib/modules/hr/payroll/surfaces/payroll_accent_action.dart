import 'package:flutter/material.dart';

import '../theme/payroll_tokens.dart';

/// Canonical disabled treatments an accent action may fall back to.
enum PayrollAccentDisabledStyle {
  /// White working surface with a hairline border (desktop commit CTA).
  surfaceBordered,

  /// Sunken surface with a hairline border (compact primary CTA).
  sunkenBordered,

  /// Quiet neutral container without a border (submit/filled buttons).
  neutral,
}

/// Sole owner of every accent-filled interactive control in Payroll.
///
/// The fill/foreground pair is one contract: `visual.accent` +
/// `visual.onAccent` while interactive (hover/focus overlays derive from
/// `onAccent`, never from a surface role), the selected
/// [PayrollAccentDisabledStyle] with `inkDisabled` content otherwise, and a
/// dimmed accent fill with an `onAccent` spinner while [busy].
///
/// The theme-architecture guard forbids raw `visual.accent` fills outside
/// this file; decorative/selection fills need an explicit
/// `// accent-fill:` marker instead.
class PayrollAccentAction extends StatelessWidget {
  const PayrollAccentAction({
    super.key,
    this.actionKey,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.busy = false,
    this.height,
    this.minHeight,
    this.fontSize = 12,
    this.horizontalPadding = 14,
    this.verticalPadding = 0,
    this.borderRadius,
    this.semanticLabel,
    this.disabledStyle = PayrollAccentDisabledStyle.surfaceBordered,
    this.animate = false,
    this.icon,
  });

  /// Key exposed on the [InkWell] so behavioural tests target the tap area.
  final Key? actionKey;
  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  final bool busy;
  final double? height;
  final double? minHeight;
  final double fontSize;
  final double horizontalPadding;
  final double verticalPadding;
  final double? borderRadius;
  final String? semanticLabel;
  final PayrollAccentDisabledStyle disabledStyle;

  /// Animates height changes (composer CTA grows on compact hosts).
  final bool animate;

  /// Optional leading icon; it always paints with the same foreground pair.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final visual = PayrollVisualTokens.of(context);
    final interactive = enabled && !busy && onTap != null;
    final fill = busy
        ? visual.accent.withValues(alpha: 0.55)
        : interactive
            ? visual.accent
            : switch (disabledStyle) {
                PayrollAccentDisabledStyle.surfaceBordered => visual.surface,
                PayrollAccentDisabledStyle.sunkenBordered =>
                  visual.surfaceSunken,
                PayrollAccentDisabledStyle.neutral => visual.neutralSoft,
              };
    final borderColor = interactive || busy
        ? visual.accent
        : switch (disabledStyle) {
            PayrollAccentDisabledStyle.neutral => Colors.transparent,
            _ => visual.border,
          };
    final radius = BorderRadius.circular(borderRadius ?? PayrollTokens.rField);
    final foreground =
        interactive || busy ? visual.onAccent : visual.inkDisabled;

    final labelText = Text(
      label,
      maxLines: 1,
      textAlign: TextAlign.center,
      style: visual.labelStrong.copyWith(
        fontSize: fontSize,
        color: foreground,
      ),
    );
    final content = busy
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: visual.onAccent,
            ),
          )
        : icon == null
            ? labelText
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 18, color: foreground),
                  const SizedBox(width: 6),
                  Flexible(child: labelText),
                ],
              );

    final padding = EdgeInsets.symmetric(
      horizontal: horizontalPadding,
      vertical: verticalPadding,
    );
    final Widget body = animate
        ? AnimatedContainer(
            duration: PayrollTokens.fast,
            height: height,
            padding: padding,
            alignment: Alignment.center,
            child: content,
          )
        : Container(
            height: height,
            constraints: minHeight == null
                ? null
                : BoxConstraints(minHeight: minHeight!),
            padding: padding,
            alignment: Alignment.center,
            child: content,
          );

    return Semantics(
      button: true,
      enabled: interactive,
      label: semanticLabel ?? label,
      excludeSemantics: semanticLabel != null,
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: borderColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: actionKey,
          onTap: interactive ? onTap : null,
          mouseCursor:
              interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
          hoverColor:
              interactive ? visual.onAccent.withValues(alpha: 0.12) : null,
          focusColor:
              interactive ? visual.onAccent.withValues(alpha: 0.16) : null,
          child: body,
        ),
      ),
    );
  }
}
