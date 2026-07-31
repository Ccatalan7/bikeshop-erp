import 'package:flutter/material.dart';

import '../models/website_action.dart';

typedef WebsiteActionLabelPresenter = Widget Function(
  BuildContext context,
  WebsiteActionValue action,
  TextStyle? textStyle,
);

/// Canonical storefront renderer for every navigational website action.
///
/// It intentionally sets only semantic colors. Shape, padding, minimum size,
/// and typography come from [WebsiteThemeBuilder]'s global button themes.
class WebsiteActionButton extends StatelessWidget {
  const WebsiteActionButton({
    super.key,
    required this.action,
    required this.onPressed,
    this.backgroundColor,
    this.foregroundColor,
    this.outlineColor,
    this.textStyle,
    this.style,
    this.labelPresenter,
    this.uppercase = false,
    this.expand = false,
  });

  final WebsiteActionValue action;
  final VoidCallback? onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? outlineColor;
  final TextStyle? textStyle;
  final ButtonStyle? style;
  final WebsiteActionLabelPresenter? labelPresenter;
  final bool uppercase;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final label = uppercase ? action.label.toUpperCase() : action.label;
    final presentedAction = uppercase ? action.copyWith(label: label) : action;
    final child = labelPresenter?.call(
          context,
          presentedAction,
          textStyle,
        ) ??
        Text(label, style: textStyle);
    final button = switch (action.variant) {
      WebsiteActionVariant.outline => OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: foregroundColor,
            side:
                outlineColor == null ? null : BorderSide(color: outlineColor!),
          ).merge(style),
          child: child,
        ),
      WebsiteActionVariant.text => TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(foregroundColor: foregroundColor)
              .merge(style),
          child: child,
        ),
      WebsiteActionVariant.filled => ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
          ).merge(style),
          child: child,
        ),
    };
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}
