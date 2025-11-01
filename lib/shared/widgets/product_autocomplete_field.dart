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
  final String? initialValue;
  final bool allowCustomItems;
  final String? labelText;
  final String? hintText;
  final bool enabled;

  const ProductAutocompleteField({
    super.key,
    required this.onProductSelected,
    this.controller,
    this.initialValue,
    this.allowCustomItems = true,
    this.labelText = 'Artículo o servicio',
    this.hintText = 'Escriba para buscar o ingrese un artículo personalizado',
    this.enabled = true,
  });

  @override
  State<ProductAutocompleteField> createState() => _ProductAutocompleteFieldState();
}

class _ProductAutocompleteFieldState extends State<ProductAutocompleteField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  final LayerLink _layerLink = LayerLink();
  List<Product> _filteredProducts = [];
  List<Product> _allProducts = [];
  Product? _selectedProduct;
  bool _isLoading = false;
  late shared_inventory.InventoryService _inventoryService;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _focusNode = FocusNode();
    _inventoryService = Provider.of<shared_inventory.InventoryService>(context, listen: false);
    _controller.text = widget.initialValue ?? '';
    _loadProducts();
    
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _showOverlay();
      } else {
        // Add small delay to allow tap events to register
        Future.delayed(const Duration(milliseconds: 200), () {
          if (!_focusNode.hasFocus && mounted) {
            _removeOverlay();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _removeOverlay();
    if (widget.controller == null) {
      _controller.dispose();
    }
    _focusNode.dispose();
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
    
    // Use minimum 300px width for dropdown to show product info properly
    final dropdownWidth = size.width < 300 ? 300.0 : size.width;
    
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
      },
      child: Container(
        constraints: const BoxConstraints(
          maxHeight: 400, // Increased from 300 to show more items
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.outline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: _filteredProducts.length + (widget.allowCustomItems ? 1 : 0),
            itemBuilder: (context, index) {
            // Custom item option at the end
            if (widget.allowCustomItems && index == _filteredProducts.length) {
              if (_controller.text.trim().isEmpty) return const SizedBox.shrink();
              
              return InkWell(
                onTap: () {
                  _selectCustomItem(_controller.text);
                  _removeOverlay();
                },
                child: ListTile(
                  leading: Icon(Icons.add_circle, color: theme.colorScheme.secondary),
                  title: Text('Agregar: "${_controller.text}"'),
                  subtitle: const Text('Artículo personalizado (no en catálogo)'),
                ),
              );
            }

            final product = _filteredProducts[index];
            final hasStock = product.stockQuantity > 0;

            return InkWell(
              onTap: () {
                _selectProduct(product);
                _removeOverlay();
              },
              child: ListTile(
                leading: product.imageUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(
                          product.imageUrl!,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.inventory_2),
                        ),
                      )
                    : const Icon(Icons.inventory_2),
                title: Text(product.name),
                subtitle: Text(
                  'SKU: ${product.sku} • ${hasStock ? '${product.stockQuantity} ${product.unit.name}' : 'Sin stock'}',
                  style: TextStyle(
                    color: hasStock ? null : theme.colorScheme.error,
                  ),
                ),
                trailing: Text(
                  '\$${product.price.toStringAsFixed(0)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            );
          },
        ),
        ),
      ),
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
    if (_filteredProducts.isNotEmpty && _selectedProduct == null) {
      // Auto-select first match if user presses enter
      _selectProduct(_filteredProducts.first);
    } else if (widget.allowCustomItems && _selectedProduct == null && value.trim().isNotEmpty) {
      // Accept as custom item
      _selectCustomItem(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CompositedTransformTarget(
      link: _layerLink,
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
            _selectedProduct != null ? Icons.inventory_2 : Icons.add_shopping_cart,
            color: _selectedProduct != null ? theme.colorScheme.primary : null,
          ),
        ),
        onChanged: _onTextChanged,
        onSubmitted: _onSubmitted,
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
