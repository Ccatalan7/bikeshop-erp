import 'package:flutter/material.dart';

import '../../../shared/utils/chilean_utils.dart';

/// Commencal-style clean, minimal product card used across the website.
///
/// - In **previewMode** the card is non-interactive.
/// - When interactive, tapping navigates to `/tienda/producto/<id>` via [onNavigate].
class PremiumProductCard extends StatefulWidget {
  final String productId;
  final String name;
  final double price;
  final String? imageUrl;
  final String? bodyFont;
  final bool previewMode;
  final void Function(String route)? onNavigate;

  const PremiumProductCard({
    super.key,
    required this.productId,
    required this.name,
    required this.price,
    this.imageUrl,
    this.bodyFont,
    required this.previewMode,
    this.onNavigate,
  });

  @override
  State<PremiumProductCard> createState() => _PremiumProductCardState();
}

class _PremiumProductCardState extends State<PremiumProductCard> {
  bool _isHovered = false;

  bool get _isInteractive => !widget.previewMode && widget.onNavigate != null;

  @override
  Widget build(BuildContext context) {
    final hasImage = widget.imageUrl != null && widget.imageUrl!.isNotEmpty;

    return MouseRegion(
      onEnter: _isInteractive ? (_) => setState(() => _isHovered = true) : null,
      onExit: _isInteractive ? (_) => setState(() => _isHovered = false) : null,
      cursor: _isInteractive ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: !_isInteractive
            ? null
            : () =>
                widget.onNavigate?.call('/tienda/producto/${widget.productId}'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: const BoxDecoration(color: Colors.white),
          transform: _isInteractive && _isHovered
              ? (Matrix4.identity()..translate(0.0, -2.0))
              : Matrix4.identity(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product image - takes most of the space
              Expanded(
                flex: 4,
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      color: Colors.white,
                      padding: const EdgeInsets.all(16),
                      child: hasImage
                          ? Image.network(
                              widget.imageUrl!,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return Center(
                                  child: Icon(
                                    Icons.pedal_bike_outlined,
                                    size: 48,
                                    color: Colors.grey.shade400,
                                  ),
                                );
                              },
                            )
                          : Center(
                              child: Icon(
                                Icons.pedal_bike_outlined,
                                size: 56,
                                color: Colors.grey.shade400,
                              ),
                            ),
                    ),
                    if (_isInteractive && _isHovered)
                      Positioned(
                        bottom: 12,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: const Text(
                              'VER DETALLES',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Product info
              Expanded(
                flex: 3,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        (widget.name.isEmpty ? 'Producto' : widget.name)
                            .toUpperCase(),
                        style: TextStyle(
                          fontFamily: widget.bodyFont,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.3,
                          color: Colors.black87,
                          height: 1.3,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        ChileanUtils.formatCurrency(widget.price),
                        style: TextStyle(
                          fontFamily: widget.bodyFont,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
