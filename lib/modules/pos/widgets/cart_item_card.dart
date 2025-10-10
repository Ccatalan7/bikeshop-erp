import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/pos_cart_item.dart';

class CartItemCard extends StatelessWidget {
  final POSCartItem item;
  final VoidCallback? onRemove;
  final ValueChanged<int>? onQuantityChanged;
  final ValueChanged<double>? onDiscountChanged;
  final bool showControls;

  const CartItemCard({
    super.key,
    required this.item,
    this.onRemove,
    this.onQuantityChanged,
    this.onDiscountChanged,
    this.showControls = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Product image
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: theme.colorScheme.surfaceVariant,
              ),
              child: item.product.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: item.product.imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      errorWidget: (context, url, error) => const Icon(
                        Icons.pedal_bike,
                        size: 24,
                      ),
                    )
                  : const Icon(
                      Icons.pedal_bike,
                      size: 24,
                    ),
            ),
            
            const SizedBox(width: 12),
            
            // Product details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product name
                  Text(
                    item.product.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  
                  // SKU
                  Text(
                    item.product.sku,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  
                  const SizedBox(height: 4),
                  
                  // Price per unit
                  Text(
                    '\$${item.unitPrice.toStringAsFixed(0)} c/u',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.secondary,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(width: 12),
            
            // Quantity controls and total
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Quantity controls
                if (showControls)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: item.quantity > 1
                            ? () => onQuantityChanged?.call(item.quantity - 1)
                            : onRemove,
                        icon: Icon(
                          item.quantity > 1 ? Icons.remove : Icons.delete,
                          size: 20,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: theme.colorScheme.surfaceVariant,
                          minimumSize: const Size(32, 32),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                      
                      Container(
                        width: 40,
                        alignment: Alignment.center,
                        child: Text(
                          '${item.quantity}',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      
                      IconButton(
                        onPressed: item.product.stockQuantity > item.quantity
                            ? () => onQuantityChanged?.call(item.quantity + 1)
                            : null,
                        icon: const Icon(Icons.add, size: 20),
                        style: IconButton.styleFrom(
                          backgroundColor: theme.colorScheme.surfaceVariant,
                          minimumSize: const Size(32, 32),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  )
                else
                  Text(
                    'Qty: ${item.quantity}',
                    style: theme.textTheme.bodyMedium,
                  ),
                
                const SizedBox(height: 8),
                
                // Discount (if any)
                if (item.discount > 0)
                  Text(
                    '-${item.discount.toStringAsFixed(0)}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                
                // Subtotal
                Text(
                  '\$${item.subtotal.toStringAsFixed(0)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    decoration: item.discount > 0 
                        ? TextDecoration.lineThrough 
                        : null,
                  ),
                ),
                
                // Total (after discount)
                if (item.discount > 0)
                  Text(
                    '\$${item.total.toStringAsFixed(0)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
              ],
            ),
            
            // Remove button
            if (showControls)
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close),
                style: IconButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                ),
              ),
          ],
        ),
      ),
    );
  }
}