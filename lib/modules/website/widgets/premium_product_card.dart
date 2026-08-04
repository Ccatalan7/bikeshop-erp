import 'package:flutter/material.dart';

import '../../../public_store/utils/product_url.dart';
import '../../../shared/utils/chilean_utils.dart';

/// Commencal-style clean, minimal product card used across the website.
///
/// - [interactionsEnabled] is an EXPLICIT interaction flag: visitor surfaces
///   (public AND Preview) enable it; editors (Edit blocks, editable Canvas)
///   disable it. It carries no preview-data semantics.
/// - When interactive, tapping navigates to the product's public URL.
class PremiumProductCard extends StatefulWidget {
  final String productId;
  final String? productSku;
  final String name;
  final double price;
  final String? imageUrl;
  final String? bodyFont;
  final bool interactionsEnabled;
  final void Function(String route)? onNavigate;

  const PremiumProductCard({
    super.key,
    required this.productId,
    this.productSku,
    required this.name,
    required this.price,
    this.imageUrl,
    this.bodyFont,
    required this.interactionsEnabled,
    this.onNavigate,
  });

  @override
  State<PremiumProductCard> createState() => _PremiumProductCardState();
}

class _PremiumProductCardState extends State<PremiumProductCard> {
  bool _isHovered = false;

  bool get _isInteractive =>
      widget.interactionsEnabled && widget.onNavigate != null;

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
            : () => widget.onNavigate?.call(
                  buildPublicProductPath(
                    name: widget.name,
                    sku: widget.productSku ?? '',
                    fallbackProductId: widget.productId,
                  ),
                ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: const BoxDecoration(color: Colors.white),
          transform: _isInteractive && _isHovered
              ? (Matrix4.identity()..translateByDouble(0.0, -2.0, 0.0, 1.0))
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
                    // Only show hover button on desktop (not mobile/touch)
                    if (_isInteractive &&
                        _isHovered &&
                        MediaQuery.of(context).size.width >= 600)
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
