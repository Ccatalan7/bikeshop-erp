import 'package:flutter/material.dart';

import 'canvas_block.dart' deferred as canvas_lib;

class DeferredCanvasBlock extends StatefulWidget {
  final Map<String, dynamic> data;
  final Color accentColor;
  final void Function(String route)? onNavigate;
  final String? tenantId;
  final String? bodyFont;

  const DeferredCanvasBlock({
    super.key,
    required this.data,
    required this.accentColor,
    this.onNavigate,
    this.tenantId,
    this.bodyFont,
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
          editable: false,
          accentColor: widget.accentColor,
          onNavigate: widget.onNavigate,
          tenantId: widget.tenantId,
          bodyFont: widget.bodyFont,
        );
      },
    );
  }
}
