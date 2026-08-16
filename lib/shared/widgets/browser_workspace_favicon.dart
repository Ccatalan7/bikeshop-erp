import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/workspace_manager.dart';

/// Site-owned identity mark for browser tabs.
///
/// The surrounding tab already exposes the page/site name to semantics, so
/// this image remains decorative. A missing, slow or unsupported favicon falls
/// back to the existing browser globe without changing layout.
class BrowserWorkspaceFavicon extends StatelessWidget {
  const BrowserWorkspaceFavicon({
    super.key,
    required this.faviconUrl,
    required this.size,
    required this.fallbackColor,
  });

  final String? faviconUrl;
  final double size;
  final Color fallbackColor;

  Widget _fallback() => Icon(
        Icons.language_outlined,
        size: size,
        color: fallbackColor,
      );

  @override
  Widget build(BuildContext context) {
    final cleanUrl = sanitizeBrowserFaviconUrl(faviconUrl);
    if (cleanUrl == null) return _fallback();

    final uri = Uri.parse(cleanUrl);
    final isSvg = uri.path.toLowerCase().endsWith('.svg');
    return SizedBox.square(
      dimension: size,
      child: isSvg
          ? SvgPicture.network(
              cleanUrl,
              width: size,
              height: size,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
              placeholderBuilder: (_) => _fallback(),
              errorBuilder: (_, __, ___) => _fallback(),
            )
          : Image.network(
              cleanUrl,
              width: size,
              height: size,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
              excludeFromSemantics: true,
              loadingBuilder: (context, child, progress) =>
                  progress == null ? child : _fallback(),
              errorBuilder: (_, __, ___) => _fallback(),
            ),
    );
  }
}
