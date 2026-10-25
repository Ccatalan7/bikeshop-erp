import 'package:flutter/material.dart';
import 'package:vinabike_public_core/public_store/models/public_commerce_product_projection.dart';

import '../../shared/models/product.dart';
import '../../shared/utils/chilean_utils.dart';
import '../utils/product_url.dart';
import 'public_link_semantics.dart';
import 'public_store_layout.dart';

/// A product in the catalog and in a product page's related grid
/// (2026-10-24), as the HTML store's `ProductCard` draws it. It takes
/// Canyon's grid idea in Viñabike's voice: the photo on a flat grey tile with
/// square corners, which a white supplier photo melts into, and «Agotado» as
/// a tag in its corner. Under it, a fixed block holds the brand, the name as
/// the catalog writes it and the price in the heading font and the site's
/// color. The grid sets the card's proportion; the fixed block keeps a row
/// lined up.
class CatalogProductCard extends StatefulWidget {
  const CatalogProductCard({
    super.key,
    required this.product,
    this.inert = false,
  });

  final Product product;

  /// On the editor's canvas a card is part of its section and opens nothing.
  final bool inert;

  @override
  State<CatalogProductCard> createState() => _CatalogProductCardState();
}

class _CatalogProductCardState extends State<CatalogProductCard> {
  bool _isHovered = false;

  /// The HTML store's `--ink`, under the catalog's words and in the tile.
  static const _ink = Color(0xFF1E293B);
  static const _muted = Color(0xFF5B6B7F);

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final commerce = PublicCommerceProductProjection.fromProduct(product);
    final brand = commerce.brand.trim();
    // Prefer the optimized photo for faster loading, then the original.
    final displayImageUrl = product.imageUrlOptimized ??
        (commerce.imageUrls.isEmpty ? null : commerce.imageUrls.first);
    final hasImage = displayImageUrl != null && displayImageUrl.isNotEmpty;
    final isInStock =
        product.tracksInventory ? product.availableStockQuantity > 0 : true;
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.maybeOf(context);
    final reduceMotion = (mediaQuery?.disableAnimations ?? false) ||
        (mediaQuery?.accessibleNavigation ?? false);
    final hoverActive = _isHovered && !reduceMotion;
    final phone = (mediaQuery?.size.width ?? 1200) < 568;
    // `color-mix(in srgb, var(--ink) 6%, #fff)`, 9 % under the pointer.
    final tile = Color.alphaBlend(
      _ink.withValues(alpha: hoverActive ? 0.09 : 0.06),
      Colors.white,
    );
    const placeholder = Center(
      child: Icon(
        Icons.pedal_bike_outlined,
        size: 48,
        color: Color(0xFFC7CFDA),
      ),
    );

    return PublicLinkSemantics(
      href: publicProductPath(product),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.inert
              ? null
              : () => PublicStoreLayout.navigateToHref(
                    context,
                    publicProductPath(product),
                  ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  color: tile,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      FractionallySizedBox(
                        widthFactor: 0.76,
                        heightFactor: 0.76,
                        child: hasImage
                            ? ColorFiltered(
                                colorFilter:
                                    ColorFilter.mode(tile, BlendMode.multiply),
                                child: AnimatedScale(
                                  scale: hoverActive ? 1.04 : 1,
                                  duration: const Duration(milliseconds: 350),
                                  curve: Curves.easeOutCubic,
                                  child: Image.network(
                                    displayImageUrl,
                                    fit: BoxFit.contain,
                                    gaplessPlayback: true,
                                    errorBuilder: (context, error, stack) =>
                                        placeholder,
                                  ),
                                ),
                              )
                            : placeholder,
                      ),
                      if (!product.isService && !isInStock)
                        Positioned(
                          top: 10,
                          left: 10,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: _ink),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: Text(
                                'AGOTADO',
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.2,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.9,
                                  color: _ink,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // Fixed height keeps a row of cards aligned.
              SizedBox(
                height: phone ? 96 : 100,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(2, 12, 2, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 15,
                        child: Text(
                          brand.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 11,
                            height: 15 / 11,
                            fontWeight: FontWeight.w700,
                            color: _muted,
                            letterSpacing: 1.1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        commerce.title,
                        style: TextStyle(
                          fontSize: phone ? 14 : 15,
                          fontWeight: FontWeight.w500,
                          color: _ink,
                          height: 1.35,
                          decoration:
                              hoverActive ? TextDecoration.underline : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      Text(
                        commerce.price > 0
                            ? ChileanUtils.formatCurrency(commerce.price)
                            : 'Consultar',
                        style: TextStyle(
                          fontFamily: theme.textTheme.headlineSmall?.fontFamily,
                          fontSize: phone ? 20 : 22,
                          fontWeight: FontWeight.w500,
                          height: 1.15,
                          color: theme.colorScheme.primary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
