import 'package:flutter/material.dart';

import '../models/product.dart';
import 'product_autocomplete_field.dart';

/// Universal smart product field widget that provides consistent behavior across all modules.
/// 
/// Features:
/// - Shows search field when no product is selected
/// - Shows Zoho-style product card when product is selected
/// - X button clears the product and returns to search mode
/// - Auto-adds new empty line after product selection (optional)
/// - Supports both catalog products and ad-hoc/custom items
/// - Blank description for ad-hoc items (not copied from item name)
/// - Auto-focus on search field when empty
/// 
/// Used in: Sales Invoices, Purchase Invoices, Mechanic Jobs, POS
class SmartProductField extends StatefulWidget {
  /// Called when a product is selected or cleared
  final Function(ProductFieldSelection?) onProductChanged;
  
  /// Initial product data (if editing existing line)
  final ProductFieldData? initialData;
  
  /// Whether to show cost (purchases) or price (sales)
  final bool showCost;
  
  /// Whether to allow ad-hoc/custom items
  final bool allowCustomItems;
  
  /// Whether the field is editable
  final bool enabled;
  
  /// Callback for when product is selected and new line should be added
  final VoidCallback? onAutoAddLine;
  
  /// Callback for showing product edit dialog
  final Function(Product)? onEditProduct;
  
  /// Callback for showing product details pane
  final Function(Product)? onShowProductDetails;
  
  /// Hint text for the search field
  final String hintText;
  
  /// Whether to auto-focus when the field is empty
  final bool autoFocus;
  
  /// External focus node (optional)
  final FocusNode? focusNode;

  const SmartProductField({
    super.key,
    required this.onProductChanged,
    this.initialData,
    this.showCost = false,
    this.allowCustomItems = true,
    this.enabled = true,
    this.onAutoAddLine,
    this.onEditProduct,
    this.onShowProductDetails,
    this.hintText = 'Buscar producto o escribir nombre...',
    this.autoFocus = true,
    this.focusNode,
  });

  @override
  State<SmartProductField> createState() => _SmartProductFieldState();
}

class _SmartProductFieldState extends State<SmartProductField> {
  late TextEditingController _productNameController;
  late TextEditingController _descriptionController;
  late FocusNode _focusNode;
  
  Product? _product;
  String? _productName;
  String? _productSku;
  bool _isCatalogProduct = true;

  @override
  void initState() {
    super.initState();
    _productNameController = TextEditingController();
    _descriptionController = TextEditingController();
    _focusNode = widget.focusNode ?? FocusNode();
    
    // Initialize from initial data
    if (widget.initialData != null) {
      _product = widget.initialData!.product;
      _productName = widget.initialData!.productName;
      _productSku = widget.initialData!.productSku;
      _isCatalogProduct = widget.initialData!.isCatalogProduct;
      _productNameController.text = _productName ?? '';
      _descriptionController.text = widget.initialData!.description ?? '';
    }
  }

  @override
  void dispose() {
    _productNameController.dispose();
    _descriptionController.dispose();
    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  bool get _hasProduct => _productName?.isNotEmpty ?? false;

  void _clearProduct() {
    setState(() {
      _product = null;
      _productName = null;
      _productSku = null;
      _isCatalogProduct = true;
      _productNameController.clear();
      _descriptionController.clear();
    });
    
    widget.onProductChanged(null);
    
    // Auto-focus the search field after clearing
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  void _selectProduct(ProductSelection selection) {
    if (selection.isCatalogProduct && selection.product != null) {
      // Catalog product selected
      setState(() {
        _product = selection.product;
        _productName = selection.product!.name;
        _productSku = selection.product!.sku;
        _isCatalogProduct = true;
        _productNameController.text = selection.product!.name;
        
        // Auto-fill description from product (if exists)
        if (selection.product!.description != null && 
            selection.product!.description!.isNotEmpty) {
          _descriptionController.text = selection.product!.description!;
        }
        // Otherwise leave description BLANK (not copied from product name)
      });
      
      widget.onProductChanged(ProductFieldSelection(
        product: selection.product,
        productName: selection.product!.name,
        productSku: selection.product!.sku,
        isCatalogProduct: true,
        description: _descriptionController.text,
        price: widget.showCost 
            ? (selection.product!.cost > 0 ? selection.product!.cost : selection.product!.price)
            : selection.product!.price,
      ));
      
      // Auto-add new line if callback provided
      widget.onAutoAddLine?.call();
      
    } else if (!selection.isCatalogProduct) {
      // Ad-hoc/custom item
      setState(() {
        _product = null;
        _productName = selection.displayText;
        _productSku = null;
        _isCatalogProduct = false;
        _productNameController.text = selection.displayText;
        // Description stays BLANK for ad-hoc items
        _descriptionController.clear();
      });
      
      widget.onProductChanged(ProductFieldSelection(
        product: null,
        productName: selection.displayText,
        productSku: null,
        isCatalogProduct: false,
        description: '',
        price: 0,
      ));
      
      // Auto-add new line if callback provided
      widget.onAutoAddLine?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // If not editable, show as read-only text
    if (!widget.enabled) {
      return _buildReadOnlyView(theme);
    }
    
    // If product is set, show Zoho-style card
    if (_hasProduct) {
      return _buildProductCard(theme);
    }
    
    // Otherwise show search field
    return _buildSearchField(theme);
  }

  Widget _buildReadOnlyView(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _productName ?? 'Producto',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (_productSku != null && _productSku!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              'SKU: $_productSku',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ),
        if (_descriptionController.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _descriptionController.text,
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildProductCard(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Product row with image, name, menu and X button
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product image (48x48 like Zoho)
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: theme.colorScheme.outline.withOpacity(0.15),
                ),
              ),
              child: _product?.imageUrl != null && _product!.imageUrl!.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(
                        _product!.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.inventory_2_outlined,
                            size: 24,
                            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
                          );
                        },
                      ),
                    )
                  : Icon(
                      Icons.inventory_2_outlined,
                      size: 24,
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
                    ),
            ),
            const SizedBox(width: 12),
            // Product details column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product name with menu and X button
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _productName ?? '',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      // 3-dot menu button (only for catalog products)
                      if (_product != null && (widget.onEditProduct != null || widget.onShowProductDetails != null))
                        PopupMenuButton<String>(
                          icon: Icon(
                            Icons.more_horiz,
                            size: 20,
                            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 200),
                          onSelected: (value) {
                            if (value == 'edit' && widget.onEditProduct != null) {
                              widget.onEditProduct!(_product!);
                            } else if (value == 'details' && widget.onShowProductDetails != null) {
                              widget.onShowProductDetails!(_product!);
                            }
                          },
                          itemBuilder: (context) => [
                            if (widget.onEditProduct != null)
                              PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.edit_outlined,
                                      size: 18,
                                      color: theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 12),
                                    const Text('Editar artículo'),
                                  ],
                                ),
                              ),
                            if (widget.onShowProductDetails != null)
                              PopupMenuItem(
                                value: 'details',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.inventory_2_outlined,
                                      size: 18,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 12),
                                    const Text('Ver detalles del artículo'),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      // X button - CLEARS product and returns to search mode
                      InkWell(
                        onTap: _clearProduct,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.close,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // SKU
                  if (_productSku != null && _productSku!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'SKU (Código de artículo): $_productSku',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        // Description field - separate box below
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.colorScheme.outline.withOpacity(0.3),
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: TextField(
            controller: _descriptionController,
            decoration: InputDecoration(
              hintText: 'Agregue una descripción a su artículo',
              hintStyle: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                fontSize: 13,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 13,
            ),
            maxLines: 3,
            minLines: 3,
            onChanged: (value) {
              // Notify parent of description change
              widget.onProductChanged(ProductFieldSelection(
                product: _product,
                productName: _productName,
                productSku: _productSku,
                isCatalogProduct: _isCatalogProduct,
                description: value,
                price: _product != null 
                    ? (widget.showCost 
                        ? (_product!.cost > 0 ? _product!.cost : _product!.price)
                        : _product!.price)
                    : 0,
              ));
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return ProductAutocompleteField(
      key: ValueKey('smart_product_search_${widget.hashCode}'),
      controller: _productNameController,
      focusNode: _focusNode,
      autoFocus: widget.autoFocus,
      allowCustomItems: widget.allowCustomItems,
      labelText: null,
      hintText: widget.hintText,
      showCost: widget.showCost,
      onProductSelected: _selectProduct,
    );
  }
}

/// Data class for initializing SmartProductField with existing data
class ProductFieldData {
  final Product? product;
  final String? productName;
  final String? productSku;
  final bool isCatalogProduct;
  final String? description;

  const ProductFieldData({
    this.product,
    this.productName,
    this.productSku,
    this.isCatalogProduct = true,
    this.description,
  });
}

/// Result of product selection from SmartProductField
class ProductFieldSelection {
  final Product? product;
  final String? productName;
  final String? productSku;
  final bool isCatalogProduct;
  final String? description;
  final double price;

  const ProductFieldSelection({
    this.product,
    this.productName,
    this.productSku,
    required this.isCatalogProduct,
    this.description,
    required this.price,
  });
}
