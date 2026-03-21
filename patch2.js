const fs = require('fs');

let content = fs.readFileSync('lib/shared/widgets/product_autocomplete_field.dart', 'utf8');

const startStr = '  Widget _buildProductTile(Product product, ThemeData theme) {';
let start = content.indexOf(startStr);

const endStr = '  Future<void> _loadProducts() async {';
const end = content.indexOf(endStr);
if (start === -1 || end === -1) {
  console.log("NOT FOUND", {start, end});
  process.exit(1);
}

const newStr = `  Widget _buildCompactBadge(IconData icon, String text, ThemeData theme, {Color? color}) {
    final textColor = color ?? theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: textColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: textColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: textColor),
          const SizedBox(width: 4),
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: textColor,
              fontSize: 10,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductTile(Product product, ThemeData theme) {
    final hasStock = product.stockQuantity > 0;
    bool isHovered = false;

    return StatefulBuilder(
      builder: (context, setHoverState) {
        return MouseRegion(
          onEnter: (_) => setHoverState(() => isHovered = true),
          onExit: (_) {
            setHoverState(() => isHovered = false);
            _hideImagePreview();
          },
          child: GestureDetector(
            onTapDown: (_) {
              // Prevent focus loss during tap
              _isTapInProgress = true;
            },
            onTap: () {
              _hideImagePreview();
              _selectProduct(product);
              _removeOverlay();
              // Reset flag after overlay removed
              Future.delayed(const Duration(milliseconds: 50), () {
                if (mounted) _isTapInProgress = false;
              });
            },
            onTapCancel: () {
              // Reset flag if tap is cancelled
              _isTapInProgress = false;
            },
            child: Builder(builder: (tileContext) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isHovered
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
                      : Colors.transparent,
                  border: Border(
                    bottom: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Product image with hover-to-enlarge
                    MouseRegion(
                      onEnter: (event) {
                        if (product.imageUrl != null) {
                          _scheduleImagePreview(
                              product.imageUrl!, event.position);
                        }
                      },
                      onExit: (_) => _hideImagePreview(),
                      child: product.imageUrl != null
                          ? Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: theme.colorScheme.outlineVariant),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: Image.network(
                                  product.imageUrl!,
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => _buildPlaceholderIcon(theme),
                                ),
                              ),
                            )
                          : _buildPlaceholderIcon(theme),
                    ),
                    const SizedBox(width: 16),
                    
                    // Product info - Wide and informative layout
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  product.name,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              // SKU Badge
                              _buildCompactBadge(
                                Icons.tag, 
                                "SKU: \${product.sku ?? 'N/A'}", 
                                theme
                              ),
                              
                              // Brand Badge
                              if (product.brand != null && product.brand!.isNotEmpty)
                                _buildCompactBadge(
                                  Icons.label_outline, 
                                  product.brand!, 
                                  theme,
                                  color: theme.colorScheme.primary,
                                ),
                                
                              // Category Badge  
                              if (product.categoryName != null && product.categoryName!.isNotEmpty)
                                _buildCompactBadge(
                                  Icons.folder_outlined, 
                                  product.categoryName!, 
                                  theme,
                                  color: theme.colorScheme.tertiary,
                                ),
                                
                              // Supplier Label (text format)
                              if (product.supplierName != null && product.supplierName!.isNotEmpty) ...[
                                Container(
                                  width: 1, 
                                  height: 12, 
                                  color: theme.colorScheme.outlineVariant,
                                  margin: const EdgeInsets.symmetric(horizontal: 2),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.local_shipping_outlined, 
                                        size: 12, color: theme.colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 4),
                                    Text(
                                      product.supplierName!,
                                      style: theme.textTheme.labelSmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    
                    // Stock indicator
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: hasStock 
                                  ? theme.colorScheme.primaryContainer 
                                  : theme.colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  hasStock ? Icons.check_circle_outline : Icons.error_outline,
                                  size: 14,
                                  color: hasStock 
                                      ? theme.colorScheme.onPrimaryContainer 
                                      : theme.colorScheme.onErrorContainer,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  hasStock 
                                      ? '\${product.stockQuantity} \${product.unit.name}' 
                                      : 'Sin stock',
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: hasStock 
                                        ? theme.colorScheme.onPrimaryContainer 
                                        : theme.colorScheme.onErrorContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Price/Cost - right-aligned
                    Expanded(
                      flex: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            widget.showCost ? 'Costo:' : 'Precio:',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            widget.showCost
                                ? '\\$\${product.cost.toStringAsFixed(0)}'
                                : '\\$\${product.price.toStringAsFixed(0)}',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: widget.showCost
                                  ? theme.colorScheme.tertiary
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildPlaceholderIcon(ThemeData theme) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Icon(
        Icons.inventory_2_outlined,
        size: 20,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

`;

content = content.substring(0, start) + newStr + content.substring(end);
fs.writeFileSync('lib/shared/widgets/product_autocomplete_field.dart', content);
console.log("SUCCESS");
