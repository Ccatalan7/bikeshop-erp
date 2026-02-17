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
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  Timer? _hoverTimer;

  static const _hoverDelay = Duration(milliseconds: 600);
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
    _removeOverlay(); // Ensure no duplicates
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  OverlayEntry _createOverlayEntry() {
    // Determine position logic
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);
    final screenSize = MediaQuery.of(context).size;

    // Check if there is enough space on the right
    final showOnRight =
        (offset.dx + size.width + _zoomSize + 20) < screenSize.width;

    // Check vertical space and clamp if needed
    final topOfOverlay = offset.dy - (_zoomSize / 2) + (size.height / 2);
    final bottomOfOverlay = topOfOverlay + _zoomSize + 8;
    double verticalOffset = 0;
    if (topOfOverlay < 8) {
      verticalOffset = 8 - topOfOverlay;
    } else if (bottomOfOverlay > screenSize.height - 8) {
      verticalOffset = (screenSize.height - 8) - bottomOfOverlay;
    }

    return OverlayEntry(
      builder: (context) => Positioned(
        width: _zoomSize + 10,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor:
              showOnRight ? Alignment.centerRight : Alignment.centerLeft,
          followerAnchor:
              showOnRight ? Alignment.centerLeft : Alignment.centerRight,
          offset: showOnRight
              ? Offset(10, verticalOffset)
              : Offset(-10, verticalOffset),
          child: IgnorePointer(
            // CRITICAL: Prevent the overlay from stealing mouse events, which causes flickering
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: MouseRegion(
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
