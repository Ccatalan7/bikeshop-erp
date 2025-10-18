import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../shared/models/product.dart';

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

    return Card(
      elevation: 2,
      child: InkWell(
        onTap: isOutOfStock ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product image
              if (showImage) ...[
                Expanded(
                  flex: 3,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      color: theme.colorScheme.surfaceVariant,
                    ),
                    child: product.imageUrl != null
                        ? CachedNetworkImage(
                            imageUrl: product.imageUrl!,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => const Center(
                              child: CircularProgressIndicator(),
                            ),
                            errorWidget: (context, url, error) => Icon(
                              isService
                                  ? Icons.design_services
                                  : Icons.pedal_bike,
                              size: 40,
                            ),
                          )
                        : Icon(
                            isService
                                ? Icons.design_services
                                : Icons.pedal_bike,
                            size: 40,
                          ),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              // Product info
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Product name
                    Text(
                      product.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isOutOfStock ? theme.disabledColor : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    // SKU
                    Text(
                      product.sku,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),

                    const Spacer(),

                    // Price and stock row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Price
                        Text(
                          '\$${product.price.toStringAsFixed(0)}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isOutOfStock
                                ? theme.disabledColor
                                : theme.colorScheme.primary,
                          ),
                        ),

                        // Stock/service indicator
                        if (showStock)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isService
                                  ? theme.colorScheme.primaryContainer
                                  : isOutOfStock
                                      ? theme.colorScheme.error
                                      : product.stockQuantity <= 5
                                          ? theme.colorScheme.tertiary
                                          : theme.colorScheme.secondary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isService
                                  ? 'Servicio'
                                  : isOutOfStock
                                      ? 'Sin stock'
                                      : '${product.stockQuantity}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: isService
                                    ? theme.colorScheme.onPrimaryContainer
                                    : isOutOfStock
                                        ? theme.colorScheme.onError
                                        : product.stockQuantity <= 5
                                            ? theme.colorScheme.onTertiary
                                            : theme.colorScheme.onSecondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
