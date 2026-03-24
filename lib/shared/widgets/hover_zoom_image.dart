import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

class HoverZoomImage extends StatefulWidget {
  final String imageUrl;
  final double size;

  const HoverZoomImage({
    super.key,
    required this.imageUrl,
    this.size = 30,
  });

  @override
  State<HoverZoomImage> createState() => _HoverZoomImageState();
}

class _HoverZoomImageState extends State<HoverZoomImage> {
  OverlayEntry? _overlayEntry;
  Timer? _hoverTimer;

  static const _hoverDelay = Duration(milliseconds: 400);
  static const double _zoomSize = 450;

  void _onHoverStart() {
    _hoverTimer?.cancel();
    _hoverTimer = Timer(_hoverDelay, () {
      if (mounted) _showOverlay();
    });
  }

  void _onHoverEnd() {
    _hoverTimer?.cancel();
    _hoverTimer = null;
    _removeOverlay();
  }

  void _showOverlay() {
    _removeOverlay();
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  OverlayEntry _createOverlayEntry() {
    final renderBox = context.findRenderObject() as RenderBox;
    final widgetSize = renderBox.size;

    // Get overlay origin so we can express coordinates relative to it
    final overlay = Overlay.of(context);
    final overlayBox = overlay.context.findRenderObject() as RenderBox;
    final overlaySize = overlayBox.size;
    final overlayPos = overlayBox.localToGlobal(Offset.zero);

    final widgetPos = renderBox.localToGlobal(Offset.zero);
    final relX = widgetPos.dx - overlayPos.dx;
    final relY = widgetPos.dy - overlayPos.dy;

    // Show to the right of the thumbnail if there's room, otherwise to the left
    final showOnRight =
        (relX + widgetSize.width + _zoomSize + 20) < overlaySize.width - 8;

    final left = showOnRight
        ? relX + widgetSize.width + 10
        : (relX - _zoomSize - 10)
            .clamp(8.0, overlaySize.width - _zoomSize - 8.0);

    // Center overlay vertically on the thumbnail, clamped to screen bounds
    final top = (relY - (_zoomSize / 2) + (widgetSize.height / 2))
        .clamp(8.0, overlaySize.height - _zoomSize - 8.0);

    return OverlayEntry(
      builder: (context) => Positioned(
        left: left,
        top: top,
        child: IgnorePointer(
          // Prevent overlay from stealing mouse events (would cause flickering)
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CachedNetworkImage(
                  imageUrl: widget.imageUrl,
                  width: _zoomSize,
                  height: _zoomSize,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => SizedBox(
                    width: _zoomSize,
                    height: _zoomSize,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                  errorWidget: (context, url, error) => SizedBox(
                    width: _zoomSize,
                    height: _zoomSize,
                    child: const Center(child: Icon(Icons.broken_image)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _onHoverStart(),
      onExit: (_) => _onHoverEnd(),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: CachedNetworkImage(
            imageUrl: widget.imageUrl,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(color: Colors.grey[200]),
            errorWidget: (context, url, error) =>
                const Icon(Icons.error, size: 12),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hoverTimer?.cancel();
    _removeOverlay();
    super.dispose();
  }
}
