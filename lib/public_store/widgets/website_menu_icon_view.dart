import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:vinabike_public_core/modules/website/models/website_menu_icons.dart';

/// A header menu item's icon (`website_navigation.icon`) as the HTML store
/// draws it: the same line drawing from `WebsiteMenuIcons`, in [color].
/// An unknown or blank key draws nothing at the same size, so the row keeps
/// its place.
class WebsiteMenuIconView extends StatelessWidget {
  const WebsiteMenuIconView(
    this.iconKey, {
    super.key,
    required this.color,
    this.size = 20,
  });

  final String? iconKey;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = WebsiteMenuIcons.of(iconKey);
    if (icon == null) return SizedBox.square(dimension: size);
    return SvgPicture.string(
      icon.svg(size: size),
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      excludeFromSemantics: true,
    );
  }
}
