import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../shared/models/product.dart';
import '../../../shared/utils/chilean_utils.dart';

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
    final isLowStock = requiresStock &&
        product.stockQuantity > 0 &&
        product.stockQuantity <= 5;
    final hasNoImage = product.imageUrl == null || product.imageUrl!.isEmpty;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(4),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: isOutOfStock ? null : onTap,
          hoverColor: theme.colorScheme.onSurface.withValues(alpha: 0.04),
          highlightColor: theme.colorScheme.onSurface.withValues(alpha: 0.02),
          splashColor: theme.colorScheme.onSurface.withValues(alpha: 0.06),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Image Section ──────────────────────────────────────────
              if (showImage)
                AspectRatio(
                  aspectRatio: 1.33,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.3),
                          border: Border(
                            bottom: BorderSide(
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: _imageOrPlaceholder(
                            theme, isService, hasNoImage, isOutOfStock),
                      ),
                      // Service badge
                      if (isService)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: _badge(
                            theme,
                            label: 'Servicio',
                            bg: theme.colorScheme.secondaryContainer,
                            fg: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      // Stock badge
                      if (showStock && !isService)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: isOutOfStock
                              ? _badge(
                                  theme,
                                  label: 'Agotado',
                                  bg: theme.colorScheme.errorContainer,
                                  fg: theme.colorScheme.onErrorContainer,
                                )
                              : _badge(
                                  theme,
                                  label: '${product.stockQuantity} un.',
                                  bg: isLowStock
                                      ? theme.colorScheme.errorContainer
                                          .withValues(alpha: 0.9)
                                      : theme.colorScheme.surface
                                          .withValues(alpha: 0.88),
                                  fg: isLowStock
                                      ? theme.colorScheme.onErrorContainer
                                      : theme.colorScheme.onSurface,
                                ),
                        ),
                    ],
                  ),
                ),

              // ── Content Section ────────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Brand • Category
                      Text(
                        [
                          if (product.brand != null &&
                              product.brand!.isNotEmpty)
                            product.brand!,
                          product.categoryName ?? 'Sin categoría',
                        ].join(' • ').toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 10,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),

                      // Product Name
                      Expanded(
                        child: Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                            color: isOutOfStock
                                ? theme.colorScheme.onSurface
                                    .withValues(alpha: 0.38)
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ),

                      // SKU
                      if (product.sku.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, bottom: 8),
                          child: Text(
                            'SKU: ${product.sku}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                              fontSize: 11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )
                      else
                        const SizedBox(height: 8),

                      // Price row + add button
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              ChileanUtils.formatCurrency(product.price),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: isOutOfStock
                                    ? theme.colorScheme.onSurface
                                        .withValues(alpha: 0.38)
                                    : theme.colorScheme.onSurface,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!isOutOfStock)
                            Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                borderRadius: BorderRadius.circular(6),
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

  Widget _imageOrPlaceholder(
      ThemeData theme, bool isService, bool hasNoImage, bool isOutOfStock) {
    Widget img;
    if (!hasNoImage) {
      img = CachedNetworkImage(
        imageUrl: product.imageUrl!,
        fit: BoxFit.contain,
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
    } else {
      img = _placeholder(theme, isService);
    }

    if (isOutOfStock) {
      return ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0.2126,
          0.7152,
          0.0722,
          0,
          0,
          0,
          0,
          0,
          0.4,
          0,
        ]),
        child: img,
      );
    }
    return img;
  }

  Widget _placeholder(ThemeData theme, bool isService) {
    return Center(
      child: Icon(
        isService ? Icons.build_circle_outlined : Icons.inventory_2_outlined,
        size: 36,
        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
      ),
    );
  }

  Widget _badge(
    ThemeData theme, {
    required String label,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1,
        ),
      ),
    );
  }
}
