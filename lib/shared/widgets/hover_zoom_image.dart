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

  void _showOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  OverlayEntry _createOverlayEntry() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    return OverlayEntry(
      builder: (context) => Positioned(
        left: offset.dx + size.width + 10, // Show to the right
        top: offset.dy -
            100 +
            (size.height / 2), // Center vertically relative to target
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
                width: 250,
                height: 250,
                fit: BoxFit.cover,
                placeholder: (context, url) => const SizedBox(
                  width: 250,
                  height: 250,
                  child: Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (context, url, error) => const SizedBox(
                  width: 250,
                  height: 250,
                  child: Center(child: Icon(Icons.broken_image)),
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
        onEnter: (_) => _showOverlay(),
        onExit: (_) => _removeOverlay(),
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
    _removeOverlay();
    super.dispose();
  }
}
