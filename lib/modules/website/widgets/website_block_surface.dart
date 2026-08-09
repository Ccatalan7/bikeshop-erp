import 'package:flutter/material.dart';

import '../models/website_block_surface_style.dart';
import '../models/website_responsive_authoring.dart';

typedef WebsiteBlockSurfaceBuilder = Widget Function(
  BuildContext context,
  WebsiteBlockSurfaceStyle style,
);

/// One rendered surface boundary for Website Builder blocks.
///
/// Edit, Preview and Public all enter through [WebsiteBlockRenderer], which
/// mounts this widget before it builds a block family. The resolved style is
/// handed to the content builder so padding is consumed by the family at its
/// real content boundary, while background, border, radius and shadow are
/// painted exactly once here.
///
/// Canvas is a spatial document with its own surface contract and opts out via
/// [paintDecoration]. Platform-view blocks may opt out of clipping while still
/// consuming the same decoration; this avoids introducing a second parser or
/// Edit-only wrapper for that implementation detail.
class WebsiteBlockSurface extends StatelessWidget {
  const WebsiteBlockSurface({
    super.key,
    required this.data,
    required this.viewport,
    required this.builder,
    this.paintDecoration = true,
    this.clipContent = true,
    this.surfaceKey,
  });

  final Map<String, dynamic> data;
  final WebsiteViewport viewport;
  final WebsiteBlockSurfaceBuilder builder;
  final bool paintDecoration;
  final bool clipContent;
  final Key? surfaceKey;

  @visibleForTesting
  static const Key fallbackKey = Key('website-block-surface');

  @override
  Widget build(BuildContext context) {
    final style = WebsiteBlockSurfaceStyle.resolve(
      data: data,
      viewport: viewport,
    );
    final child = builder(context, style);
    if (!paintDecoration) {
      return KeyedSubtree(
        key: surfaceKey ?? fallbackKey,
        child: child,
      );
    }

    final decoration = style.decoration();
    final clipsRadius = clipContent && style.borderRadius > 0;
    return Container(
      key: surfaceKey ?? fallbackKey,
      width: double.infinity,
      decoration: decoration,
      clipBehavior: clipsRadius ? Clip.antiAlias : Clip.none,
      child: child,
    );
  }
}
