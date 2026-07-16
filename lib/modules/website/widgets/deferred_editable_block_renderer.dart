import 'package:flutter/material.dart';

import '../models/website_block_type.dart';
import '../../../shared/models/product.dart';
import 'editable_block_renderer.dart' deferred as editable;

class DeferredEditableBlockRenderer {
  static Future<void>? _loadFuture;

  static Future<void> preload() {
    _loadFuture ??= editable.loadLibrary();
    return _loadFuture!;
  }

  static Widget build({
    required BuildContext context,
    required String blockId,
    required String blockType,
    required Map<String, dynamic> data,
    required Color primaryColor,
    required Color accentColor,
    List<Product>? featuredProducts,
    String? headingFont,
    String? bodyFont,
    double? headingSize,
    double? bodySize,
    void Function(String route)? onNavigate,
    bool isVisible = true,
    String? tenantId,
  }) {
    // If the type is not recognized, loading the editor library is pointless.
    final normalised = blockType.trim().toLowerCase();
    final isKnownType =
        WebsiteBlockType.values.any((t) => t.name.toLowerCase() == normalised);
    if (!isKnownType) {
      return const SizedBox.shrink();
    }

    _loadFuture ??= editable.loadLibrary();

    return FutureBuilder<void>(
      future: _loadFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          // Keep layout stable while editor code loads.
          return const SizedBox(
            height: 120,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error cargando editor: ${snapshot.error}',
              textAlign: TextAlign.center,
            ),
          );
        }

        return editable.EditableBlockRenderer.build(
          context: context,
          blockId: blockId,
          blockType: blockType,
          data: data,
          primaryColor: primaryColor,
          accentColor: accentColor,
          featuredProducts: featuredProducts,
          headingFont: headingFont,
          bodyFont: bodyFont,
          headingSize: headingSize,
          bodySize: bodySize,
          onNavigate: onNavigate,
          isVisible: isVisible,
          tenantId: tenantId,
        );
      },
    );
  }
}
