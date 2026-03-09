import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/inventory_service.dart' as shared_inventory;
import '../models/product.dart';

/// Flexible autocomplete field for products and services
/// Supports:
/// - Searching catalog products
/// - Selecting catalog products
/// - Entering ad-hoc/custom items (not in catalog)
/// - Adding notes/descriptions to catalog products
class ProductAutocompleteField extends StatefulWidget {
  final Function(ProductSelection) onProductSelected;
  final TextEditingController? controller;
  final FocusNode? focusNode; // Allow external focus control
  final String? initialValue;
  final bool allowCustomItems;
  final String? labelText;
  final String? hintText;
  final bool enabled;
  final bool showCost; // Show cost instead of price (for purchase invoices)
  final bool autoFocus; // Auto-focus when created

  const ProductAutocompleteField({
    super.key,
    required this.onProductSelected,
    this.controller,
    this.focusNode,
    this.initialValue,
    this.allowCustomItems = true,
    this.labelText = 'Artículo o servicio',
    this.hintText = 'Escriba para buscar o ingrese un artículo personalizado',
    this.enabled = true,
    this.showCost = false, // Default to showing price
    this.autoFocus = false,
  });

  @override
  State<ProductAutocompleteField> createState() =>
      _ProductAutocompleteFieldState();
}

class _ProductAutocompleteFieldState extends State<ProductAutocompleteField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  final LayerLink _layerLink = LayerLink();
  List<Product> _filteredProducts = [];
  Product? _selectedProduct;
  bool _isLoading = false;
  bool _isTapInProgress =
      false; // Track tap events to prevent premature overlay removal
  bool _hasUserInteracted =
      false; // Track if user has interacted with the field
  bool _isMouseOverDropdown = false; // Track if mouse is over the dropdown
  late shared_inventory.InventoryService _inventoryService;
  OverlayEntry? _overlayEntry;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _focusNode = widget.focusNode ?? FocusNode();
    _inventoryService =
        Provider.of<shared_inventory.InventoryService>(context, listen: false);
    _controller.text = widget.initialValue ?? '';
    _controller.text = widget.initialValue ?? '';

    // Defer loading to avoid "setState() called during build" if service notifies synchronously
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadProducts();
    });

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        // Only show overlay if user has explicitly interacted (tap/click/type)
        // Don't show on programmatic focus unless autoFocus is set
        if (_hasUserInteracted || widget.autoFocus) {
          _showOverlay();
        }
      } else {
        // Add delay to allow tap events and mouse-over-dropdown to register
        Future.delayed(const Duration(milliseconds: 250), () {
          // Don't remove if: still focused, tap in progress, or mouse is over dropdown
          if (!_focusNode.hasFocus &&
              mounted &&
              !_isTapInProgress &&
              !_isMouseOverDropdown) {
            _removeOverlay();
          }
        });
      }
    });

    // Auto-focus if requested (for newly added lines after selecting a product)
    if (widget.autoFocus) {
      _hasUserInteracted = true; // Mark as interacted since it's intentional
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _focusNode.requestFocus();
        }
      });
    }
  }

  @override
  void dispose() {
    _removeOverlay();
    _hideImagePreview();
    if (widget.controller == null) {
      _controller.dispose();
    }
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    _debounce?.cancel();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showOverlay() {
    _removeOverlay();

    if (_filteredProducts.isEmpty) return;

    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final position = renderBox.localToGlobal(Offset.zero);

    // Get actual overlay bounds (the true rendering area)
    final overlayBox = overlay.context.findRenderObject() as RenderBox;
    final overlaySize = overlayBox.size;
    final overlayPosition = overlayBox.localToGlobal(Offset.zero);

    // Position relative to overlay origin
    final relativeY = position.dy - overlayPosition.dy;
    final relativeX = position.dx - overlayPosition.dx;

    // Use wider dropdown (minimum 500px) for better product info display
    final dropdownWidth = size.width < 500 ? 500.0 : size.width;

    const margin = 8.0;
    final fieldBottomInOverlay = relativeY + size.height;
    final spaceBelow = overlaySize.height - fieldBottomInOverlay - margin;
    final spaceAbove = relativeY - margin;

    const preferredMaxHeight = 400.0;

    // Always show wherever there's more space — above or below
    final showAbove = spaceAbove > spaceBelow;

    final availableSpace = showAbove ? spaceAbove : spaceBelow;
    final dropdownMaxHeight = availableSpace.clamp(100.0, preferredMaxHeight);

    final left = relativeX.clamp(
        0.0, (overlaySize.width - dropdownWidth).clamp(0.0, double.infinity));

    final bottomAnchor = overlaySize.height - relativeY + 4;

    _overlayEntry = OverlayEntry(
      builder: (context) => showAbove
          ? Positioned(
              left: left,
              bottom: bottomAnchor,
              width: dropdownWidth,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                child:
                    _buildDropdownContent(Theme.of(context), dropdownMaxHeight),
              ),
            )
          : Positioned(
              left: left,
              top: fieldBottomInOverlay + 4,
              width: dropdownWidth,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                child:
                    _buildDropdownContent(Theme.of(context), dropdownMaxHeight),
              ),
            ),
    );

    overlay.insert(_overlayEntry!);
  }

  Widget _buildDropdownContent(ThemeData theme, double maxHeight) {
    return MouseRegion(
      onEnter: (_) {
        // Keep overlay open when mouse is over dropdown
        _isMouseOverDropdown = true;
      },
      onExit: (_) {
        _isMouseOverDropdown = false;
        // Check if we should close the overlay now
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted &&
              !_focusNode.hasFocus &&
              !_isTapInProgress &&
              !_isMouseOverDropdown) {
            _removeOverlay();
          }
        });
      },
      child: Container(
        constraints: BoxConstraints(
          maxHeight: maxHeight,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: theme.colorScheme.outline),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).shadowColor.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            itemCount:
                _filteredProducts.length + (widget.allowCustomItems ? 1 : 0),
            itemBuilder: (context, index) {
              // Custom item option at the end
              if (widget.allowCustomItems &&
                  index == _filteredProducts.length) {
                if (_controller.text.trim().isEmpty)
                  return const SizedBox.shrink();

                return _buildCustomItemTile(theme);
              }

              final product = _filteredProducts[index];
              return _buildProductTile(product, theme);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCustomItemTile(ThemeData theme) {
    return InkWell(
      onTap: () {
        _selectCustomItem(_controller.text);
        _removeOverlay();
      },
      hoverColor: theme.colorScheme.primary.withOpacity(0.08),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.add_circle,
                color: theme.colorScheme.secondary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Agregar: "${_controller.text}"',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    'Artículo personalizado (no en catálogo)',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Overlay entry for the enlarged image preview
  OverlayEntry? _imagePreviewOverlay;
  Timer? _imagePreviewTimer;

  void _scheduleImagePreview(String imageUrl, Offset mousePosition) {
    _cancelImagePreviewTimer();
    _imagePreviewTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) {
        _showImagePreview(imageUrl, mousePosition);
      }
    });
  }

  void _cancelImagePreviewTimer() {
    _imagePreviewTimer?.cancel();
    _imagePreviewTimer = null;
  }

  void _showImagePreview(String imageUrl, Offset mousePosition) {
    _hideImagePreview();
    final overlay = Overlay.of(context);

    // Get overlay origin to convert global mouse position to overlay-local
    final overlayBox = overlay.context.findRenderObject() as RenderBox;
    final overlaySize = overlayBox.size;
    final overlayPos = overlayBox.localToGlobal(Offset.zero);

    const previewSize = 250.0;
    const gap = 12.0;

    // Anchor X to the right edge of the dropdown (never overlaps the list)
    final fieldBox = context.findRenderObject() as RenderBox;
    final fieldPos = fieldBox.localToGlobal(Offset.zero);
    final fieldRelX = fieldPos.dx - overlayPos.dx;
    final dropdownWidth =
        fieldBox.size.width < 500 ? 500.0 : fieldBox.size.width;
    final dropdownRightEdge = fieldRelX + dropdownWidth;

    // Use cursor Y for vertical position (natural feel — preview is next to what you're hovering)
    final mouseRelY = mousePosition.dy - overlayPos.dy;

    // Try right side first, flip to left if not enough room
    final fitsRight =
        dropdownRightEdge + gap + previewSize < overlaySize.width - 8;
    final left = fitsRight
        ? dropdownRightEdge + gap
        : (fieldRelX - previewSize - gap)
            .clamp(8.0, overlaySize.width - previewSize - 8.0);

    // Vertically center preview on the cursor, clamp to screen
    final top = (mouseRelY - previewSize / 2)
        .clamp(8.0, overlaySize.height - previewSize - 8.0);

    _imagePreviewOverlay = OverlayEntry(
      builder: (context) => Positioned(
        left: left,
        top: top,
        child: IgnorePointer(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.scale(
                scale: 0.9 + 0.1 * value,
                alignment: Alignment.centerLeft,
                child: child,
              ),
            ),
            child: Material(
              elevation: 16,
              shadowColor: Colors.black45,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    width: 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: Image.network(
                    imageUrl,
                    width: previewSize,
                    height: previewSize,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_imagePreviewOverlay!);
  }

  void _hideImagePreview() {
    _cancelImagePreviewTimer();
    _imagePreviewOverlay?.remove();
    _imagePreviewOverlay = null;
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isHovered
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
                      : Colors.transparent,
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
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.network(
                                product.imageUrl!,
                                width: 40,
                                height: 40,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: theme
                                        .colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Icon(
                                    Icons.inventory_2,
                                    size: 20,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Icon(
                                Icons.inventory_2,
                                size: 20,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    // Product info - compact like Zoho
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            product.name,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'SKU: ${product.sku} • ${hasStock ? '${product.stockQuantity} ${product.unit.name}' : 'Sin stock'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: hasStock
                                  ? theme.colorScheme.onSurfaceVariant
                                  : theme.colorScheme.error,
                              fontSize: 12,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Price/Cost - right-aligned like Zoho
                    Text(
                      widget.showCost
                          ? '\$${product.cost.toStringAsFixed(0)}'
                          : '\$${product.price.toStringAsFixed(0)}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: widget.showCost
                            ? theme.colorScheme.tertiary
                            : theme.colorScheme.onSurface,
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

  Future<void> _loadProducts() async {
    // Only load initial/recent products to show as defaults when user taps field
    setState(() => _isLoading = true);
    try {
      final products = await _inventoryService.searchProducts('', limit: 20);
      setState(() {
        _filteredProducts = products;
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _onTextChanged(String value) {
    if (value.isEmpty) {
      _loadProducts();
      return;
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;

      setState(() => _isLoading = true);
      try {
        final results =
            await _inventoryService.searchProducts(value, limit: 20);
        if (mounted) {
          setState(() {
            _filteredProducts = results;
            _selectedProduct = null;
          });
          _showOverlay();
        }
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    });
  }

  void _selectProduct(Product product) {
    setState(() {
      _selectedProduct = product;
      _controller.text = product.name;
    });

    widget.onProductSelected(ProductSelection(
      isCatalogProduct: true,
      product: product,
      displayText: product.name,
    ));
  }

  void _selectCustomItem(String text) {
    if (text.trim().isEmpty) return;

    setState(() {
      _selectedProduct = null;
    });

    widget.onProductSelected(ProductSelection(
      isCatalogProduct: false,
      displayText: text.trim(),
      customDescription: text.trim(),
    ));
  }

  void _onSubmitted(String value) {
    final trimmedValue = value.trim();
    if (trimmedValue.isEmpty) return;

    // First: try exact match by SKU or barcode (handles barcode scanner input)
    // For exact match, we need to check the DB if not in current results
    _inventoryService.getProductBySku(trimmedValue).then((p) {
      if (p != null) {
        _selectProduct(p);
      } else {
        _inventoryService.getProductByBarcode(trimmedValue).then((pb) {
          if (pb != null) {
            _selectProduct(pb);
          } else if (widget.allowCustomItems && _selectedProduct == null) {
            _selectCustomItem(trimmedValue);
          }
        });
      }
    });
  }

  void _onTap() {
    // Mark that user has interacted - this allows overlay to show
    if (!_hasUserInteracted) {
      setState(() {
        _hasUserInteracted = true;
      });
    }
    // Show overlay when user explicitly taps the field
    if (_focusNode.hasFocus) {
      _showOverlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // RepaintBoundary prevents unnecessary repaints from parent hover state changes
    return RepaintBoundary(
      child: CompositedTransformTarget(
        link: _layerLink,
        child: GestureDetector(
          onTap: _onTap,
          behavior: HitTestBehavior.translucent,
          child: TextField(
            controller: _controller,
            focusNode: _focusNode,
            enabled: widget.enabled,
            decoration: InputDecoration(
              labelText: widget.labelText,
              hintText: widget.hintText,
              suffixIcon: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _controller.clear();
                            _onTextChanged('');
                          },
                        )
                      : Icon(
                          widget.allowCustomItems ? Icons.edit : Icons.search,
                          color: theme.colorScheme.primary,
                        ),
              prefixIcon: Icon(
                _selectedProduct != null
                    ? Icons.inventory_2
                    : Icons.add_shopping_cart,
                color:
                    _selectedProduct != null ? theme.colorScheme.primary : null,
              ),
            ),
            onTap: _onTap,
            onChanged: (value) {
              // Mark as interacted when user types
              if (!_hasUserInteracted) {
                _hasUserInteracted = true;
              }
              _onTextChanged(value);
            },
            onSubmitted: _onSubmitted,
          ),
        ),
      ),
    );
  }
}

/// Result of product selection
class ProductSelection {
  final bool isCatalogProduct;
  final Product? product; // Null if custom item
  final String displayText;
  final String? customDescription; // For ad-hoc items

  ProductSelection({
    required this.isCatalogProduct,
    this.product,
    required this.displayText,
    this.customDescription,
  });
}
