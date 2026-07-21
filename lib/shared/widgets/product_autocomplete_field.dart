import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/product_compatibility.dart';
import '../services/inventory_service.dart' as shared_inventory;
import '../models/product.dart';

enum _ProductCompatibilityBrowseMode {
  compatibleOnly,
  showAll,
}

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
  final Future<Map<String, ProductCompatibilityAssessment>> Function(
      List<Product> products)? compatibilityResolver;
  final Object? compatibilityContextKey;

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
    this.compatibilityResolver,
    this.compatibilityContextKey,
  });

  @override
  State<ProductAutocompleteField> createState() =>
      _ProductAutocompleteFieldState();
}

class _ProductAutocompleteFieldState extends State<ProductAutocompleteField> {
  static const int _compatibilityBatchSize = 60;

  late TextEditingController _controller;
  late FocusNode _focusNode;
  final LayerLink _layerLink = LayerLink();
  List<Product> _allFetchedProducts = [];
  Product? _selectedProduct;
  bool _isLoading = false;
  bool _compatibilityEngineEnabled = false;
  _ProductCompatibilityBrowseMode _compatibilityBrowseMode =
      _ProductCompatibilityBrowseMode.compatibleOnly;

  // Filter states
  bool _filterShowProducts = true;
  bool _filterShowServices = true;
  bool _filterInStockOnly = false;
  String? _selectedCategory;
  String? _selectedBrand;
  String? _selectedSupplier;

  bool get _hasActiveFilters {
    return _filterInStockOnly ||
        !_filterShowProducts ||
        !_filterShowServices ||
        _selectedCategory != null ||
        _selectedBrand != null ||
        _selectedSupplier != null;
  }

  void _clearFilters() {
    setState(() {
      _filterShowProducts = true;
      _filterShowServices = true;
      _filterInStockOnly = false;
      _selectedCategory = null;
      _selectedBrand = null;
      _selectedSupplier = null;
    });
    unawaited(_reloadProductsForCurrentQuery());
    _updateOverlay();
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted && _overlayEntry != null) _focusNode.requestFocus();
    });
  }

  bool get _hasCompatibilityCapability => widget.compatibilityResolver != null;

  bool get _isCompatibilityEngineActive =>
      _hasCompatibilityCapability && _compatibilityEngineEnabled;

  List<Product> get _baseFilteredProducts {
    final filteredProducts = _allFetchedProducts.where((p) {
      if (!_filterShowProducts && p.productType == ProductType.product) {
        return false;
      }
      if (!_filterShowServices && p.productType == ProductType.service) {
        return false;
      }
      if (_filterInStockOnly &&
          p.productType != ProductType.service &&
          p.availableStockQuantity <= 0) {
        return false;
      }

      if (_selectedCategory != null && p.categoryName != _selectedCategory) {
        return false;
      }
      if (_selectedBrand != null && p.brand != _selectedBrand) return false;
      if (_selectedSupplier != null && p.supplierName != _selectedSupplier) {
        return false;
      }

      return true;
    }).toList();

    return filteredProducts;
  }

  List<Product> get _filteredProducts {
    final filteredProducts = List<Product>.from(_baseFilteredProducts);

    if (_isCompatibilityEngineActive &&
        _compatibilityBrowseMode ==
            _ProductCompatibilityBrowseMode.compatibleOnly &&
        _compatibilityByProductId.isNotEmpty) {
      filteredProducts.removeWhere(
        (product) =>
            _compatibilityByProductId[product.id]?.level ==
            ProductCompatibilityLevel.incompatible,
      );
    }

    if (!_isCompatibilityEngineActive || _compatibilityByProductId.isEmpty) {
      return filteredProducts;
    }

    final originalOrder = <String, int>{
      for (var index = 0; index < filteredProducts.length; index++)
        filteredProducts[index].id: index,
    };

    filteredProducts.sort((a, b) {
      final aPriority = _compatibilityByProductId[a.id]?.sortPriority ?? 50;
      final bPriority = _compatibilityByProductId[b.id]?.sortPriority ?? 50;
      final priorityCompare = aPriority.compareTo(bPriority);
      if (priorityCompare != 0) {
        return priorityCompare;
      }
      return (originalOrder[a.id] ?? 0).compareTo(originalOrder[b.id] ?? 0);
    });

    return filteredProducts;
  }

  bool _isTapInProgress =
      false; // Track tap events to prevent premature overlay removal
  bool _hasUserInteracted =
      false; // Track if user has interacted with the field
  bool _isMouseOverDropdown = false; // Track if mouse is over the dropdown
  bool _isSearchDialogOpen = false;
  bool _isRefreshingCompatibility = false;
  late shared_inventory.InventoryService _inventoryService;
  OverlayEntry? _overlayEntry;
  Timer? _debounce;
  Map<String, ProductCompatibilityAssessment> _compatibilityByProductId = {};
  int _compatibilityRequestSerial = 0;
  int _catalogRequestSerial = 0;
  String? _lastCompatibilitySignature;

  ProductType? get _exclusiveProductTypeFilter {
    if (_filterShowServices && !_filterShowProducts) {
      return ProductType.service;
    }
    if (_filterShowProducts && !_filterShowServices) {
      return ProductType.product;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? TextEditingController();
    _focusNode = widget.focusNode ?? FocusNode();
    _compatibilityEngineEnabled = widget.compatibilityResolver != null;
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
        if (mounted && (_hasUserInteracted || widget.autoFocus)) {
          _showOverlay();
        }
      } else {
        // Add delay to allow tap events and mouse-over-dropdown to register
        Future.delayed(const Duration(milliseconds: 250), () {
          // Don't remove if: still focused, tap in progress, or mouse is over dropdown
          if (!_focusNode.hasFocus &&
              mounted &&
              !_isTapInProgress &&
              !_isMouseOverDropdown &&
              !_isSearchDialogOpen) {
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

  @override
  void didUpdateWidget(covariant ProductAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.compatibilityResolver == null &&
        widget.compatibilityResolver != null) {
      _compatibilityEngineEnabled = true;
      _compatibilityBrowseMode = _ProductCompatibilityBrowseMode.compatibleOnly;
    } else if (oldWidget.compatibilityResolver != null &&
        widget.compatibilityResolver == null) {
      _compatibilityEngineEnabled = false;
    }

    if (oldWidget.compatibilityContextKey != widget.compatibilityContextKey ||
        oldWidget.compatibilityResolver != widget.compatibilityResolver) {
      _lastCompatibilitySignature = null;
      if (_compatibilityByProductId.isNotEmpty) {
        setState(() {
          _compatibilityByProductId = {};
        });
      }
      unawaited(_refreshCompatibilityIfNeeded());
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _updateOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
    } else {
      _showOverlay();
    }
  }

  void _showOverlay() {
    if (!mounted) return;
    _removeOverlay();

    if (_filteredProducts.isEmpty &&
        _allFetchedProducts.isEmpty &&
        !widget.allowCustomItems) {
      return;
    }

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

    // Use a wider dropdown so the filter bar has room for all chips.
    final dropdownWidth = size.width < 980 ? 980.0 : size.width;

    const margin = 8.0;
    final fieldBottomInOverlay = relativeY + size.height;
    final spaceBelow = overlaySize.height - fieldBottomInOverlay - margin;
    final spaceAbove = relativeY - margin;

    const preferredMaxHeight = 520.0;

    // Always show wherever there's more space — above or below
    final showAbove = spaceAbove > spaceBelow;

    final availableSpace = showAbove ? spaceAbove : spaceBelow;
    final dropdownMaxHeight = availableSpace.clamp(100.0, preferredMaxHeight);

    final left = relativeX.clamp(
        0.0, (overlaySize.width - dropdownWidth).clamp(0.0, double.infinity));

    final horizontalOffset = left - relativeX;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: dropdownWidth,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          targetAnchor: showAbove ? Alignment.topLeft : Alignment.bottomLeft,
          followerAnchor: showAbove ? Alignment.bottomLeft : Alignment.topLeft,
          offset: Offset(horizontalOffset, showAbove ? -4 : 4),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            child: _buildDropdownContent(Theme.of(context), dropdownMaxHeight),
          ),
        ),
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  Widget _buildDropdownContent(ThemeData theme, double maxHeight) {
    final filteredProducts = _filteredProducts;
    final canShowCustomItem =
        widget.allowCustomItems && _controller.text.trim().isNotEmpty;

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
              !_isMouseOverDropdown &&
              !_isSearchDialogOpen) {
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
              color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_hasCompatibilityCapability)
                _buildCompatibilityControls(theme),
              _buildFiltersBar(theme),
              Flexible(
                child: filteredProducts.isEmpty && !canShowCustomItem
                    ? _buildEmptyResultsState(theme)
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: filteredProducts.length +
                            (widget.allowCustomItems ? 1 : 0),
                        itemBuilder: (context, index) {
                          // Custom item option at the end
                          if (widget.allowCustomItems &&
                              index == filteredProducts.length) {
                            if (_controller.text.trim().isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return _buildCustomItemTile(theme);
                          }

                          final product = filteredProducts[index];
                          return _buildProductTile(product, theme);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompatibilityControls(ThemeData theme) {
    final helperText = _isCompatibilityEngineActive
        ? (_isRefreshingCompatibility
            ? 'Aplicando compatibilidad al catálogo...'
            : 'Oculta incompatibles por defecto y permite revisar todo desde el buscador.')
        : 'Autocomplete normal, sin filtros ni marcas de compatibilidad.';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.tune_outlined,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Motor de compatibilidad',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      helperText,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch.adaptive(
                value: _isCompatibilityEngineActive,
                onChanged: (value) {
                  setState(() {
                    _compatibilityEngineEnabled = value;
                    if (value) {
                      _compatibilityBrowseMode =
                          _ProductCompatibilityBrowseMode.compatibleOnly;
                    }
                  });
                  unawaited(_refreshCompatibilityIfNeeded());
                  _updateOverlay();
                  _focusNode.requestFocus();
                },
              ),
            ],
          ),
          if (_isCompatibilityEngineActive) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<_ProductCompatibilityBrowseMode>(
                segments: const [
                  ButtonSegment<_ProductCompatibilityBrowseMode>(
                    value: _ProductCompatibilityBrowseMode.compatibleOnly,
                    label: Text('Solo compatibles'),
                  ),
                  ButtonSegment<_ProductCompatibilityBrowseMode>(
                    value: _ProductCompatibilityBrowseMode.showAll,
                    label: Text('Mostrar todo'),
                  ),
                ],
                selected: <_ProductCompatibilityBrowseMode>{
                  _compatibilityBrowseMode,
                },
                onSelectionChanged: (selected) {
                  if (selected.isEmpty) return;
                  setState(() {
                    _compatibilityBrowseMode = selected.first;
                  });
                  _updateOverlay();
                  _focusNode.requestFocus();
                },
                showSelectedIcon: false,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyResultsState(ThemeData theme) {
    final isCompatibilityFiltered = _isCompatibilityEngineActive &&
        _compatibilityBrowseMode ==
            _ProductCompatibilityBrowseMode.compatibleOnly &&
        _baseFilteredProducts.isNotEmpty;

    final title = isCompatibilityFiltered
        ? 'No hay resultados compatibles'
        : 'No se encontraron resultados';
    final subtitle = isCompatibilityFiltered
        ? 'Cambia a Mostrar todo o apaga compatibilidad para ver el resto del catálogo.'
        : 'Prueba con otro texto o ajusta los filtros.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isCompatibilityFiltered
                  ? Icons.rule_folder_outlined
                  : Icons.search_off_outlined,
              size: 24,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFiltersBar(ThemeData theme) {
    // Extract unique categories, brands, suppliers from _allFetchedProducts
    final categories = _allFetchedProducts
        .map((p) => p.categoryName)
        .where((c) => c != null && c.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList()
      ..sort();
    final brands = _allFetchedProducts
        .map((p) => p.brand)
        .where((b) => b != null && b.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList()
      ..sort();
    final suppliers = _allFetchedProducts
        .map((p) => p.supplierName)
        .where((s) => s != null && s.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList()
      ..sort();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text(
                    'Filtros:',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilterChip(
                    label: const Text('En stock'),
                    selected: _filterInStockOnly,
                    onSelected: (val) {
                      setState(() => _filterInStockOnly = val);
                      unawaited(_refreshCompatibilityIfNeeded());
                      _updateOverlay();
                      _focusNode.requestFocus();
                    },
                    visualDensity: VisualDensity.compact,
                    labelStyle: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Productos'),
                    selected: _filterShowProducts,
                    onSelected: (val) {
                      setState(() => _filterShowProducts = val);
                      unawaited(_reloadProductsForCurrentQuery());
                      _updateOverlay();
                      _focusNode.requestFocus();
                    },
                    visualDensity: VisualDensity.compact,
                    labelStyle: const TextStyle(fontSize: 12),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Servicios'),
                    selected: _filterShowServices,
                    onSelected: (val) {
                      setState(() => _filterShowServices = val);
                      unawaited(_reloadProductsForCurrentQuery());
                      _updateOverlay();
                      _focusNode.requestFocus();
                    },
                    visualDensity: VisualDensity.compact,
                    labelStyle: const TextStyle(fontSize: 12),
                  ),
                  if (categories.isNotEmpty ||
                      brands.isNotEmpty ||
                      suppliers.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Container(
                      width: 1,
                      height: 24,
                      color: theme.colorScheme.outlineVariant,
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (categories.isNotEmpty) ...[
                    _FilterPopoverButton(
                      placeholder: 'Categoría',
                      selectedValue: _selectedCategory,
                      items: categories.toList(),
                      onSelected: (val) {
                        setState(() => _selectedCategory = val);
                        unawaited(_refreshCompatibilityIfNeeded());
                        _updateOverlay();
                        Future.delayed(const Duration(milliseconds: 80), () {
                          if (mounted) _focusNode.requestFocus();
                        });
                      },
                      onPopoverOpen: () =>
                          setState(() => _isSearchDialogOpen = true),
                      onPopoverClose: () {
                        setState(() => _isSearchDialogOpen = false);
                        Future.delayed(const Duration(milliseconds: 80), () {
                          if (mounted && _overlayEntry != null) {
                            _focusNode.requestFocus();
                          }
                        });
                      },
                      onMouseEnterPanel: () =>
                          setState(() => _isMouseOverDropdown = true),
                      onMouseExitPanel: () =>
                          setState(() => _isMouseOverDropdown = false),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (brands.isNotEmpty) ...[
                    _FilterPopoverButton(
                      placeholder: 'Marca',
                      selectedValue: _selectedBrand,
                      items: brands.toList(),
                      onSelected: (val) {
                        setState(() => _selectedBrand = val);
                        unawaited(_refreshCompatibilityIfNeeded());
                        _updateOverlay();
                        Future.delayed(const Duration(milliseconds: 80), () {
                          if (mounted) _focusNode.requestFocus();
                        });
                      },
                      onPopoverOpen: () =>
                          setState(() => _isSearchDialogOpen = true),
                      onPopoverClose: () {
                        setState(() => _isSearchDialogOpen = false);
                        Future.delayed(const Duration(milliseconds: 80), () {
                          if (mounted && _overlayEntry != null) {
                            _focusNode.requestFocus();
                          }
                        });
                      },
                      onMouseEnterPanel: () =>
                          setState(() => _isMouseOverDropdown = true),
                      onMouseExitPanel: () =>
                          setState(() => _isMouseOverDropdown = false),
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (suppliers.isNotEmpty) ...[
                    _FilterPopoverButton(
                      placeholder: 'Proveedor',
                      selectedValue: _selectedSupplier,
                      items: suppliers.toList(),
                      onSelected: (val) {
                        setState(() => _selectedSupplier = val);
                        unawaited(_refreshCompatibilityIfNeeded());
                        _updateOverlay();
                        Future.delayed(const Duration(milliseconds: 80), () {
                          if (mounted) _focusNode.requestFocus();
                        });
                      },
                      onPopoverOpen: () =>
                          setState(() => _isSearchDialogOpen = true),
                      onPopoverClose: () {
                        setState(() => _isSearchDialogOpen = false);
                        Future.delayed(const Duration(milliseconds: 80), () {
                          if (mounted && _overlayEntry != null) {
                            _focusNode.requestFocus();
                          }
                        });
                      },
                      onMouseEnterPanel: () =>
                          setState(() => _isMouseOverDropdown = true),
                      onMouseExitPanel: () =>
                          setState(() => _isMouseOverDropdown = false),
                    ),
                  ],
                  if (_hasActiveFilters) ...[
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: _clearFilters,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: theme.colorScheme.onSurfaceVariant,
                      ),
                      icon: const Icon(Icons.close_rounded, size: 14),
                      label: const Text(
                        'Limpiar',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _isRefreshingCompatibility
                ? 'Aplicando compatibilidad...'
                : '${_filteredProducts.length} resultados',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomItemTile(ThemeData theme) {
    return InkWell(
      onTap: () {
        _selectCustomItem(_controller.text);
        _removeOverlay();
      },
      hoverColor: theme.colorScheme.primary.withValues(alpha: 0.08),
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

  void _hideImagePreview() {
    _cancelImagePreviewTimer();
    _imagePreviewOverlay?.remove();
    _imagePreviewOverlay = null;
  }

  Widget _buildCompactBadge(
    IconData icon,
    String text,
    ThemeData theme, {
    Color? color,
  }) {
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

  IconData _compatibilityIcon(ProductCompatibilityLevel level) {
    switch (level) {
      case ProductCompatibilityLevel.compatible:
        return Icons.check_circle_outline;
      case ProductCompatibilityLevel.caution:
        return Icons.rule_outlined;
      case ProductCompatibilityLevel.incompatible:
        return Icons.block_outlined;
    }
  }

  Color _compatibilityColor(
    ThemeData theme,
    ProductCompatibilityLevel level,
  ) {
    switch (level) {
      case ProductCompatibilityLevel.compatible:
        return theme.colorScheme.primary;
      case ProductCompatibilityLevel.caution:
        return theme.colorScheme.tertiary;
      case ProductCompatibilityLevel.incompatible:
        return theme.colorScheme.error;
    }
  }

  Widget _buildCompatibilityBadge(
    ProductCompatibilityAssessment compatibility,
    ThemeData theme,
  ) {
    final accentColor = _compatibilityColor(theme, compatibility.level);
    return _buildCompactBadge(
      _compatibilityIcon(compatibility.level),
      compatibility.label,
      theme,
      color: accentColor,
    );
  }

  bool _shouldShowCompatibilityFeedback(
    ProductCompatibilityAssessment? compatibility,
  ) {
    if (!_isCompatibilityEngineActive || compatibility == null) {
      return false;
    }

    if (_compatibilityBrowseMode != _ProductCompatibilityBrowseMode.showAll) {
      return false;
    }

    return compatibility.level != ProductCompatibilityLevel.compatible;
  }

  Widget? _buildCompatibilityDetail(
    ProductCompatibilityAssessment? compatibility,
    ThemeData theme,
  ) {
    if (!_shouldShowCompatibilityFeedback(compatibility)) {
      return null;
    }

    final detail = compatibility!.detail?.trim();
    if (detail == null || detail.isEmpty) {
      return null;
    }

    final accentColor = _compatibilityColor(theme, compatibility.level);
    return Text(
      detail,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(
        color: accentColor,
        height: 1.15,
      ),
    );
  }

  Widget _buildCompatibilityBlock(
    ProductCompatibilityAssessment compatibility,
    ThemeData theme,
  ) {
    final detailWidget = _buildCompatibilityDetail(compatibility, theme);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            _buildCompatibilityBadge(compatibility, theme),
          ],
        ),
        if (detailWidget != null) ...[
          const SizedBox(height: 4),
          detailWidget,
        ],
      ],
    );
  }

  Widget _buildProductTile(Product product, ThemeData theme) {
    // Only relevant for stockable products — services have no stock concept
    final hasStock = product.availableStockQuantity > 0;
    final compatibility = _compatibilityByProductId[product.id];
    final showCompatibilityFeedback =
        _shouldShowCompatibilityFeedback(compatibility);
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
              _isTapInProgress = true;
            },
            onTap: () {
              _hideImagePreview();
              _selectProduct(product);
              _removeOverlay();
              Future.delayed(const Duration(milliseconds: 50), () {
                if (mounted) _isTapInProgress = false;
              });
            },
            onTapCancel: () {
              _isTapInProgress = false;
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: isHovered
                    ? theme.colorScheme.primary.withValues(alpha: 0.08)
                    : Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color:
                        theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
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
                              width: 56,
                              height: 56,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _buildPlaceholderIcon(theme),
                            ),
                          )
                        : _buildPlaceholderIcon(theme),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _buildCompactBadge(
                                Icons.tag, 'SKU: ${product.sku}', theme),
                            if (product.isSetComponent)
                              _buildCompactBadge(
                                Icons.extension_outlined,
                                'Pieza de juego',
                                theme,
                                color: theme.colorScheme.tertiary,
                              ),
                            if (product.isSet)
                              _buildCompactBadge(
                                Icons.account_tree_outlined,
                                'Juego completo',
                                theme,
                                color: theme.colorScheme.primary,
                              ),
                            if (product.brand != null &&
                                product.brand!.isNotEmpty)
                              _buildCompactBadge(
                                Icons.label_outline,
                                product.brand!,
                                theme,
                                color: theme.colorScheme.primary,
                              ),
                            if (product.categoryName != null &&
                                product.categoryName!.isNotEmpty)
                              _buildCompactBadge(
                                Icons.folder_outlined,
                                product.categoryName!,
                                theme,
                                color: theme.colorScheme.tertiary,
                              ),
                            if (product.supplierName != null &&
                                product.supplierName!.isNotEmpty) ...[
                              Container(
                                width: 1,
                                height: 12,
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 2),
                                color: theme.colorScheme.outlineVariant,
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.local_shipping_outlined,
                                    size: 12,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
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
                        if (showCompatibilityFeedback &&
                            compatibility != null) ...[
                          const SizedBox(height: 6),
                          _buildCompatibilityBlock(compatibility, theme),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Services have no stock concept — hide the badge entirely
                  if (product.trackStock) ...[
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
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
                                hasStock
                                    ? Icons.check_circle_outline
                                    : Icons.error_outline,
                                size: 14,
                                color: hasStock
                                    ? theme.colorScheme.onPrimaryContainer
                                    : theme.colorScheme.onErrorContainer,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                hasStock
                                    ? '${product.availableStockQuantity} ${product.unit.name}'
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
                      ),
                    ),
                  ] else
                    const Expanded(child: SizedBox()),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 120,
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
                              ? '\$${product.cost.toStringAsFixed(0)}'
                              : '\$${product.price.toStringAsFixed(0)}',
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
            ),
          ),
        );
      },
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
        fieldBox.size.width < 980 ? 980.0 : fieldBox.size.width;
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

  Future<void> _loadProducts() async {
    await _reloadProductsForCurrentQuery();
  }

  Future<void> _reloadProductsForCurrentQuery() async {
    if (!mounted) return;

    final requestSerial = ++_catalogRequestSerial;
    final productType = _exclusiveProductTypeFilter;
    final showNoTypes = !_filterShowProducts && !_filterShowServices;
    setState(() => _isLoading = true);

    try {
      final products = showNoTypes
          ? const <Product>[]
          : await _inventoryService.searchProducts(
              _controller.text,
              limit: productType == ProductType.service ? 500 : 200,
              productType: productType,
            );
      if (!mounted || requestSerial != _catalogRequestSerial) return;

      setState(() {
        _allFetchedProducts = products;
        _selectedProduct = null;
      });
      await _refreshCompatibilityIfNeeded();
      if (!mounted || requestSerial != _catalogRequestSerial) return;

      if (_focusNode.hasFocus) {
        _showOverlay();
      } else {
        _overlayEntry?.markNeedsBuild();
      }
    } finally {
      if (mounted && requestSerial == _catalogRequestSerial) {
        setState(() => _isLoading = false);
        _overlayEntry?.markNeedsBuild();
      }
    }
  }

  void _onTextChanged(String value) {
    if (value.isEmpty) {
      _debounce
          ?.cancel(); // cancel any pending search before reloading full list
      _loadProducts();
      return;
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      await _reloadProductsForCurrentQuery();
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

  Future<void> _refreshCompatibilityIfNeeded() async {
    final resolver = widget.compatibilityResolver;
    if (resolver == null || !_isCompatibilityEngineActive) {
      _lastCompatibilitySignature = null;
      if (_compatibilityByProductId.isNotEmpty || _isRefreshingCompatibility) {
        setState(() {
          _compatibilityByProductId = {};
          _isRefreshingCompatibility = false;
        });
        _overlayEntry?.markNeedsBuild();
      }
      return;
    }

    final products = _baseFilteredProducts.toList(growable: false);
    if (products.isEmpty) {
      _lastCompatibilitySignature = null;
      if (_compatibilityByProductId.isNotEmpty || _isRefreshingCompatibility) {
        setState(() {
          _compatibilityByProductId = {};
          _isRefreshingCompatibility = false;
        });
        _overlayEntry?.markNeedsBuild();
      }
      return;
    }

    final signature = [
      widget.compatibilityContextKey?.toString() ?? 'none',
      ...products.map((product) => product.id),
    ].join('|');
    if (signature == _lastCompatibilitySignature &&
        _compatibilityByProductId.isNotEmpty &&
        !_isRefreshingCompatibility) {
      return;
    }

    _lastCompatibilitySignature = signature;
    final requestSerial = ++_compatibilityRequestSerial;
    setState(() {
      _compatibilityByProductId = {};
      _isRefreshingCompatibility = true;
    });
    _overlayEntry?.markNeedsBuild();

    final resolvedCompatibility = <String, ProductCompatibilityAssessment>{};
    for (var start = 0;
        start < products.length;
        start += _compatibilityBatchSize) {
      final end = (start + _compatibilityBatchSize < products.length)
          ? start + _compatibilityBatchSize
          : products.length;
      final batch = products.sublist(start, end);
      final batchCompatibility = await resolver(batch);

      if (!mounted || requestSerial != _compatibilityRequestSerial) {
        return;
      }

      resolvedCompatibility.addAll(batchCompatibility);
      setState(() {
        _compatibilityByProductId =
            Map<String, ProductCompatibilityAssessment>.from(
          resolvedCompatibility,
        );
      });
      _overlayEntry?.markNeedsBuild();
    }

    if (!mounted || requestSerial != _compatibilityRequestSerial) {
      return;
    }

    setState(() {
      _compatibilityByProductId = resolvedCompatibility;
      _isRefreshingCompatibility = false;
    });
    _overlayEntry?.markNeedsBuild();
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

// ─────────────────────────────────────────────────────────────────────────────
// _FilterPopoverButton: compact chip that opens an anchored popover
// with a live-search list. No modal dialog — the panel appears inline,
// directly below the button, and dismisses on outside tap.
// ─────────────────────────────────────────────────────────────────────────────
class _FilterPopoverButton extends StatefulWidget {
  final String placeholder;
  final String? selectedValue;
  final List<String> items;
  final ValueChanged<String?> onSelected;
  final VoidCallback? onPopoverOpen;
  final VoidCallback? onPopoverClose;
  final VoidCallback? onMouseEnterPanel;
  final VoidCallback? onMouseExitPanel;

  const _FilterPopoverButton({
    required this.placeholder,
    required this.selectedValue,
    required this.items,
    required this.onSelected,
    this.onPopoverOpen,
    this.onPopoverClose,
    this.onMouseEnterPanel,
    this.onMouseExitPanel,
  });

  @override
  State<_FilterPopoverButton> createState() => _FilterPopoverButtonState();
}

class _FilterPopoverButtonState extends State<_FilterPopoverButton> {
  final GlobalKey _anchorKey = GlobalKey();
  OverlayEntry? _barrierEntry;
  OverlayEntry? _overlayEntry;
  bool _isOpen = false;

  @override
  void dispose() {
    // Remove overlay entries directly — do NOT call setState here.
    // During dispose(), mounted is still true but the element is defunct,
    // so setState() would throw '_lifecycleState != _ElementLifecycle.defunct'.
    _overlayEntry?.remove();
    _overlayEntry = null;
    _barrierEntry?.remove();
    _barrierEntry = null;
    super.dispose();
  }

  void _togglePopover() {
    if (_isOpen) {
      _closePopover();
    } else {
      _openPopover();
    }
  }

  void _openPopover() {
    final overlay = Overlay.of(context);
    final theme = Theme.of(context);
    final anchorContext = _anchorKey.currentContext;
    if (anchorContext == null) return;

    // Barrier: opaque, full-screen — dismisses on tap-outside.
    // Inserted FIRST so it sits below the panel in Z-order.
    _barrierEntry = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: GestureDetector(
          onTap: _closePopover,
          behavior: HitTestBehavior.opaque,
          child: const SizedBox.expand(),
        ),
      ),
    );

    // Panel: inserted SECOND so it sits above the barrier.
    // Position is measured from the actual chip widget, not the state context.
    final anchorRenderBox = anchorContext.findRenderObject() as RenderBox;
    final overlayRenderBox = overlay.context.findRenderObject() as RenderBox;
    final buttonTopLeft = overlayRenderBox.globalToLocal(
      anchorRenderBox.localToGlobal(Offset.zero),
    );
    final buttonSize = anchorRenderBox.size;
    final panelTop = buttonTopLeft.dy + buttonSize.height + 4;
    final panelLeft = buttonTopLeft.dx;

    _overlayEntry = OverlayEntry(
      builder: (_) => Positioned(
        top: panelTop,
        left: panelLeft,
        width: 220,
        child: _FilterPopoverPanel(
          items: widget.items,
          selectedValue: widget.selectedValue,
          theme: theme,
          onSelected: (val) {
            widget.onSelected(val);
            _closePopover();
          },
          onMouseEnter: widget.onMouseEnterPanel,
          onMouseExit: widget.onMouseExitPanel,
        ),
      ),
    );

    overlay.insert(_barrierEntry!);
    overlay.insert(_overlayEntry!);
    setState(() => _isOpen = true);
    widget.onPopoverOpen?.call();
  }

  void _closePopover({bool notify = true}) {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _barrierEntry?.remove();
    _barrierEntry = null;
    if (mounted) setState(() => _isOpen = false);
    if (notify) widget.onPopoverClose?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = widget.selectedValue != null;

    return InkWell(
      key: _anchorKey,
      onTap: _togglePopover,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive
              ? theme.colorScheme.primary.withValues(alpha: 0.12)
              : theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? theme.colorScheme.primary.withValues(alpha: 0.5)
                : theme.colorScheme.outlineVariant,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isActive) ...[
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              widget.selectedValue ?? widget.placeholder,
              style: TextStyle(
                fontSize: 12,
                color: isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const SizedBox(width: 2),
            AnimatedRotation(
              turns: _isOpen ? 0.5 : 0,
              duration: const Duration(milliseconds: 150),
              child: Icon(
                Icons.keyboard_arrow_down,
                size: 16,
                color: isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterPopoverPanel extends StatefulWidget {
  final List<String> items;
  final String? selectedValue;
  final ThemeData theme;
  final ValueChanged<String?> onSelected;
  final VoidCallback? onMouseEnter;
  final VoidCallback? onMouseExit;

  const _FilterPopoverPanel({
    required this.items,
    required this.selectedValue,
    required this.theme,
    required this.onSelected,
    this.onMouseEnter,
    this.onMouseExit,
  });

  @override
  State<_FilterPopoverPanel> createState() => _FilterPopoverPanelState();
}

class _FilterPopoverPanelState extends State<_FilterPopoverPanel> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Normalize string for accent-insensitive search (camara matches cámara)
  String _norm(String s) => s
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('à', 'a')
      .replaceAll('ä', 'a')
      .replaceAll('â', 'a')
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ë', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ì', 'i')
      .replaceAll('ï', 'i')
      .replaceAll('î', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ò', 'o')
      .replaceAll('ö', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ù', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('û', 'u')
      .replaceAll('ñ', 'n')
      .replaceAll('ç', 'c');

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final filtered = widget.items
        .where((item) => _norm(item).contains(_norm(_query)))
        .toList();

    return MouseRegion(
      onEnter: (_) => widget.onMouseEnter?.call(),
      onExit: (_) => widget.onMouseExit?.call(),
      child: Material(
        elevation: 8,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(maxHeight: 280),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.colorScheme.outlineVariant,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Search field
              Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Buscar...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          BorderSide(color: theme.colorScheme.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(
                          color: theme.colorScheme.primary, width: 1.5),
                    ),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              // List
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: filtered.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      final isSelected = widget.selectedValue == null;
                      return _popoverItem(
                        label: 'Todas',
                        isSelected: isSelected,
                        isItalic: true,
                        theme: theme,
                        onTap: () => widget.onSelected(null),
                      );
                    }
                    final item = filtered[index - 1];
                    final isSelected = widget.selectedValue == item;
                    return _popoverItem(
                      label: item,
                      isSelected: isSelected,
                      isItalic: false,
                      theme: theme,
                      onTap: () => widget.onSelected(item),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _popoverItem({
    required String label,
    required bool isSelected,
    required bool isItalic,
    required ThemeData theme,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.1)
            : Colors.transparent,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check, size: 16, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }
}
