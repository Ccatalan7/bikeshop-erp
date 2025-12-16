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
  List<Product> _allProducts = [];
  Product? _selectedProduct;
  bool _isLoading = false;
  bool _isTapInProgress =
      false; // Track tap events to prevent premature overlay removal
  bool _hasUserInteracted =
      false; // Track if user has interacted with the field
  bool _isMouseOverDropdown = false; // Track if mouse is over the dropdown
  late shared_inventory.InventoryService _inventoryService;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _focusNode = widget.focusNode ?? FocusNode();
    _inventoryService =
        Provider.of<shared_inventory.InventoryService>(context, listen: false);
    _controller.text = widget.initialValue ?? '';
    _loadProducts();

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
    if (widget.controller == null) {
      _controller.dispose();
    }
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
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

    // Use wider dropdown (minimum 500px) like Zoho for better product info display
    final dropdownWidth = size.width < 500 ? 500.0 : size.width;

    // Calculate available space below and above the field
    final screenHeight = MediaQuery.of(context).size.height;
    final spaceBelow = screenHeight - position.dy - size.height;
    final spaceAbove = position.dy;

    // Dropdown max height
    const maxDropdownHeight = 400.0;

    // Decide whether to show above or below
    final showAbove = spaceBelow < maxDropdownHeight && spaceAbove > spaceBelow;
    final offset = showAbove
        ? Offset(0, -(maxDropdownHeight + 4)) // Position above
        : Offset(0, size.height + 4); // Position below

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: dropdownWidth,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: offset,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            child: _buildDropdownContent(Theme.of(context)),
          ),
        ),
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  Widget _buildDropdownContent(ThemeData theme) {
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
        constraints: const BoxConstraints(
          maxHeight: 400,
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

  Widget _buildProductTile(Product product, ThemeData theme) {
    final hasStock = product.stockQuantity > 0;
    bool isHovered = false;

    return StatefulBuilder(
      builder: (context, setHoverState) {
        return MouseRegion(
          onEnter: (_) => setHoverState(() => isHovered = true),
          onExit: (_) => setHoverState(() => isHovered = false),
          child: GestureDetector(
            onTapDown: (_) {
              // Prevent focus loss during tap
              _isTapInProgress = true;
            },
            onTap: () {
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
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isHovered
                    ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
                    : Colors.transparent,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Product image (keep - only thing better than Zoho!)
                  if (product.imageUrl != null)
                    ClipRRect(
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
                            color: theme.colorScheme.surfaceContainerHighest,
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
                  else
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        Icons.inventory_2,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
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
                          ? theme
                              .colorScheme.tertiary // Different color for cost
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    try {
      final products = await _inventoryService.getProducts();
      setState(() {
        _allProducts = products;
        _filteredProducts = products;
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _onTextChanged(String value) {
    if (value.isEmpty) {
      if (mounted) {
        setState(() {
          _filteredProducts = _allProducts;
          _selectedProduct = null;
        });
        _showOverlay();
      }
      return;
    }

    final searchLower = value.toLowerCase();
    if (mounted) {
      setState(() {
        _filteredProducts = _allProducts.where((product) {
          return product.name.toLowerCase().contains(searchLower) ||
              product.sku.toLowerCase().contains(searchLower) ||
              (product.supplierCode?.toLowerCase().contains(searchLower) ??
                  false) ||
              (product.brand?.toLowerCase().contains(searchLower) ?? false);
        }).toList();
      });
      _showOverlay();
    }
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

    // If user typed something and presses Enter, ALWAYS create ad-hoc item
    // Don't auto-select from search results - user must click to select a product
    if (widget.allowCustomItems &&
        _selectedProduct == null &&
        trimmedValue.isNotEmpty) {
      _selectCustomItem(trimmedValue);
    }
    // If no text and there are results, do nothing (user should click to select)
    // If custom items not allowed and no selection, do nothing
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
