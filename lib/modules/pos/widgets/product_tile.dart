import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../shared/models/product.dart';
import '../../../shared/widgets/hover_scale.dart';

class ProductTile extends StatelessWidget {
  final Product product;
  final VoidCallback? onTap;
  final bool showStock;
  final bool showImage;

  const ProductTile({
    super.key,
    required this.product,
    this.onTap,
    this.showStock = true,
    this.showImage = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isService = product.productType == ProductType.service;
    final requiresStock = product.trackStock && !isService;
    final isOutOfStock = requiresStock && product.stockQuantity <= 0;
    final isLowStock = requiresStock && product.stockQuantity <= 5 && !isOutOfStock;

    return HoverScale(
      enabled: !isOutOfStock && onTap != null,
      hoverScale: 1.025,
      child: GestureDetector(
        onTap: isOutOfStock ? null : onTap,
        child: Container(
          decoration: BoxDecoration(
            color: isOutOfStock
                ? theme.colorScheme.surfaceContainerLowest
                : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isOutOfStock
                  ? theme.colorScheme.outlineVariant.withValues(alpha: 0.3)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
              width: 1,
            ),
            boxShadow: isOutOfStock
                ? null
                : [
                    BoxShadow(
                      color: theme.colorScheme.shadow.withValues(alpha: 0.06),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Image Area ──────────────────────────────────────────────
              if (showImage)
                Expanded(
                  flex: 11,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Background image / placeholder
                      Container(
                        color: theme.colorScheme.surfaceContainerLowest,
                        child: isOutOfStock
                            ? ColorFiltered(
                                colorFilter: const ColorFilter.matrix([
                                  0.2126, 0.7152, 0.0722, 0, 0,
                                  0.2126, 0.7152, 0.0722, 0, 0,
                                  0.2126, 0.7152, 0.0722, 0, 0,
                                  0, 0, 0, 0.4, 0,
                                ]),
                                child: _imageOrPlaceholder(theme, isService),
                              )
                            : _imageOrPlaceholder(theme, isService),
                      ),
                      // Top-left: service badge
                      if (isService)
                        Positioned(
                          top: 7,
                          left: 7,
                          child: _badge(
                            context,
                            label: 'Servicio',
                            bg: theme.colorScheme.secondaryContainer,
                            fg: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      // Top-right: stock pill
                      if (showStock && !isService)
                        Positioned(
                          top: 7,
                          right: 7,
                          child: isOutOfStock
                              ? _badge(context,
                                  label: 'Agotado',
                                  icon: Icons.warning_amber_rounded,
                                  bg: theme.colorScheme.errorContainer,
                                  fg: theme.colorScheme.onErrorContainer)
                              : _badge(
                                  context,
                                  label: '${product.stockQuantity} un.',
                                  bg: isLowStock
                                      ? theme.colorScheme.errorContainer
                                          .withValues(alpha: 0.85)
                                      : theme.colorScheme.surface
                                          .withValues(alpha: 0.88),
                                  fg: isLowStock
                                      ? theme.colorScheme.onErrorContainer
                                      : theme.colorScheme.onSurface,
                                ),
                        ),
                      // Bottom gradient overlay
                      if (!isOutOfStock)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          height: 36,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  theme.colorScheme.surface
                                      .withValues(alpha: 0.55),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

              // ── Info Area ──────────────────────────────────────────────
              Expanded(
                flex: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Product name
                      Text(
                        product.name,
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                          color: isOutOfStock
                              ? theme.colorScheme.onSurface
                                  .withValues(alpha: 0.38)
                              : theme.colorScheme.onSurface,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // Price row + add button
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              '\$${_formatPrice(product.price)}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.5,
                                color: isOutOfStock
                                    ? theme.colorScheme.onSurface
                                        .withValues(alpha: 0.38)
                                    : theme.colorScheme.primary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!isOutOfStock)
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.add_rounded,
                                size: 18,
                                color: theme.colorScheme.onPrimary,
                              ),
                            ),
                        ],
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

  Widget _imageOrPlaceholder(ThemeData theme, bool isService) {
    if (product.imageUrl != null) {
      return CachedNetworkImage(
        imageUrl: product.imageUrl!,
        fit: BoxFit.cover,
        memCacheWidth: 300,
        memCacheHeight: 300,
        placeholder: (_, __) => Center(
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: theme.colorScheme.outlineVariant,
          ),
        ),
        errorWidget: (_, __, ___) => _placeholder(theme, isService),
      );
    }
    return _placeholder(theme, isService);
  }

  Widget _placeholder(ThemeData theme, bool isService) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Center(
        child: Icon(
          isService ? Icons.miscellaneous_services_rounded : Icons.pedal_bike,
          size: 40,
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  Widget _badge(
    BuildContext context, {
    required String label,
    IconData? icon,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: fg),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: fg,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  String _formatPrice(double price) {
    // Format with thousands separator: 45000 → 45.000
    final rounded = price.toStringAsFixed(0);
    final buf = StringBuffer();
    int count = 0;
    for (int i = rounded.length - 1; i >= 0; i--) {
      if (count > 0 && count % 3 == 0) buf.write('.');
      buf.write(rounded[i]);
      count++;
    }
    return buf.toString().split('').reversed.join();
  }
}
