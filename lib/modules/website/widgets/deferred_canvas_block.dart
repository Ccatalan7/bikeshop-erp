import 'package:flutter/material.dart';

import 'canvas_block.dart' deferred as canvas_lib;
import 'website_canvas_editor_binding.dart';

/// Starts fetching the deferred Canvas runtime before a composed carousel
/// slide becomes visible. `loadLibrary` is idempotent, so the active
/// `DeferredCanvasBlock` will reuse the same completed load.
Future<void> preloadDeferredCanvasLibrary() => canvas_lib.loadLibrary();

class DeferredCanvasBlock extends StatefulWidget {
  final Map<String, dynamic> data;
  final Color accentColor;
  final void Function(String route)? onNavigate;
  final bool Function(String href)? isNavigationEligible;
  final String? tenantId;
  final String? headingFont;
  final String? bodyFont;
  final bool fillAvailableHeight;
  final bool clipContentToBounds;
  final WebsiteCanvasEditorBinding? editorBinding;

  const DeferredCanvasBlock({
    super.key,
    required this.data,
    required this.accentColor,
    this.onNavigate,
    this.isNavigationEligible,
    this.tenantId,
    this.headingFont,
    this.bodyFont,
    this.fillAvailableHeight = false,
    this.clipContentToBounds = false,
    this.editorBinding,
  });

  @override
  State<DeferredCanvasBlock> createState() => _DeferredCanvasBlockState();
}

class _DeferredCanvasBlockState extends State<DeferredCanvasBlock> {
  late Future<void> _libraryFuture;

  @override
  void initState() {
    super.initState();
    _libraryFuture = canvas_lib.loadLibrary();
  }

  @override
  Widget build(BuildContext context) {
    final blockHeight = (widget.data['blockHeight'] as num?)?.toDouble();

    return FutureBuilder<void>(
      future: _libraryFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          // Keep layout stable while the deferred chunk is loading.
          if (blockHeight != null && blockHeight.isFinite && blockHeight > 0) {
            return SizedBox(height: blockHeight, width: double.infinity);
          }
          return const SizedBox.shrink();
        }

        return canvas_lib.CanvasBlock(
          data: widget.data,
          editable: widget.editorBinding != null,
          accentColor: widget.accentColor,
          activeElementId: widget.editorBinding?.activeElementId,
          onElementsChanged: widget.editorBinding?.onElementsChanged,
          onActiveElementChanged: widget.editorBinding?.onActiveElementChanged,
          onCanvasSizeChanged: widget.editorBinding?.onCanvasSizeChanged,
          onBackgroundTap: widget.editorBinding?.onBackgroundTap,
          onNavigate: widget.onNavigate,
          isNavigationEligible: widget.isNavigationEligible,
          tenantId: widget.tenantId,
          headingFont: widget.headingFont,
          bodyFont: widget.bodyFont,
          fillAvailableHeight: widget.fillAvailableHeight,
          clipContentToBounds: widget.clipContentToBounds,
        );
      },
    );
  }
}
