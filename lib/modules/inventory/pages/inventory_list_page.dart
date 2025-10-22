import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/main_layout.dart';
import '../../../shared/widgets/search_widget.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/services/database_service.dart';
import '../../../shared/services/image_service.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../models/inventory_models.dart';
import '../models/category_models.dart';
import '../services/category_service.dart';
import '../services/inventory_service.dart';

class InventoryListPage extends StatefulWidget {
  const InventoryListPage({super.key});

  @override
  State<InventoryListPage> createState() => _InventoryListPageState();
}

class _InventoryListPageState extends State<InventoryListPage> {
  late InventoryService _inventoryService;
  late CategoryService _categoryService;
  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  bool _isLoading = true;
  String _searchTerm = '';
  List<Category> _categories = [];
  String? _selectedCategoryId;
  bool _showLowStockOnly = false;

  @override
  void initState() {
    super.initState();
    _inventoryService = InventoryService(
      Provider.of<DatabaseService>(context, listen: false),
    );
    _categoryService = CategoryService(
      Provider.of<DatabaseService>(context, listen: false),
    );
    _loadCategories();
    _loadProducts();
  }

  Future<void> _loadCategories() async {
    try {
      final categories = await _categoryService.getCategories(activeOnly: true);
      if (mounted) {
        setState(() {
          _categories = categories;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando categorías: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    try {
      final products = await _inventoryService.getProducts(
        categoryId: _selectedCategoryId,
        lowStockOnly: _showLowStockOnly,
      );
      setState(() {
        _products = products;
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error cargando productos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _applyFilters() {
    List<Product> filtered = _products;

    if (_searchTerm.isNotEmpty) {
      filtered = filtered
          .where((product) =>
              product.name.toLowerCase().contains(_searchTerm.toLowerCase()) ||
              product.sku.toLowerCase().contains(_searchTerm.toLowerCase()) ||
              (product.brand
                      ?.toLowerCase()
                      .contains(_searchTerm.toLowerCase()) ??
                  false))
          .toList();
    }

    setState(() => _filteredProducts = filtered);
  }

  void _onSearchChanged(String searchTerm) {
    setState(() => _searchTerm = searchTerm);
    _applyFilters();
  }

  void _onCategoryIdChanged(String? categoryId) {
    setState(() => _selectedCategoryId = categoryId);
    _loadProducts();
  }

  void _onLowStockToggle(bool value) {
    setState(() => _showLowStockOnly = value);
    _loadProducts();
  }

  @override
  Widget build(BuildContext context) {
    return MainLayout(
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Inventario',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                AppButton(
                  text: 'Nuevo Producto',
                  icon: Icons.add,
                  onPressed: () {
                    context.push('/inventory/products/new').then((_) {
                      _loadProducts();
                    });
                  },
                ),
              ],
            ),
          ),

          // Search
          SearchWidget(
            hintText: 'Buscar por nombre, SKU o marca...',
            onSearchChanged: _onSearchChanged,
          ),

          // Filters
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    value: _selectedCategoryId,
                    decoration: const InputDecoration(
                      labelText: 'Categoría',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Todas las categorías'),
                      ),
                      ..._categories
                          .map((category) => DropdownMenuItem<String?>(
                                value: category.id,
                                child: Text(category.name),
                              )),
                    ],
                    onChanged: _onCategoryIdChanged,
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 150,
                  child: CheckboxListTile(
                    title: const Text('Stock Bajo'),
                    value: _showLowStockOnly,
                    onChanged: (value) => _onLowStockToggle(value ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Stats
          if (!_isLoading && _products.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  _buildStatItem('Total', _products.length.toString()),
                  const SizedBox(width: 24),
                  _buildStatItem(
                    'Stock Bajo',
                    _products.where((p) => p.isLowStock).length.toString(),
                    color: Colors.orange,
                  ),
                  const SizedBox(width: 24),
                  _buildStatItem(
                    'Sin Stock',
                    _products.where((p) => p.isOutOfStock).length.toString(),
                    color: Colors.red,
                  ),
                  const SizedBox(width: 24),
                  _buildStatItem(
                      'Mostrando', _filteredProducts.length.toString()),
                ],
              ),
            ),
          const SizedBox(height: 16),

          // Content
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildProductsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, {Color? color}) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color ?? Colors.blue,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: (color ?? Colors.blue).withOpacity(0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildProductsList() {
    if (_filteredProducts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _searchTerm.isEmpty &&
                      _selectedCategoryId == null &&
                      !_showLowStockOnly
                  ? 'No hay productos registrados'
                  : 'No se encontraron productos',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            if (_searchTerm.isEmpty &&
                _selectedCategoryId == null &&
                !_showLowStockOnly) ...[
              const SizedBox(height: 16),
              AppButton(
                text: 'Agregar Primer Producto',
                onPressed: () {
                  context.push('/inventory/products/new').then((_) {
                    _loadProducts();
                  });
                },
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadProducts,
      child: GridView.builder(
        padding: const EdgeInsets.all(16.0),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: _getCrossAxisCount(context),
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.75,
        ),
        itemCount: _filteredProducts.length,
        itemBuilder: (context, index) {
          final product = _filteredProducts[index];
          return _buildProductCard(product);
        },
      ),
    );
  }

  int _getCrossAxisCount(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 600) return 2;
    if (width < 900) return 3;
    if (width < 1200) return 4;
    return 5;
  }

  Widget _buildProductCard(Product product) {
    final categoryNames = {
      for (final category in _categories) category.id: category.name,
    };

    return Card(
      child: InkWell(
        onTap: () {
          context.push('/inventory/products/${product.id}/edit').then((_) {
            _loadProducts();
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product image
            Expanded(
              flex: 3,
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
                  ),
                  child: ImageService.buildProductImage(
                    imageUrl: product.imageUrl,
                    size: double.infinity,
                    isListThumbnail: false,
                  ),
                ),
              ),
            ),

            // Product info
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name and status
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            product.name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (product.isOutOfStock)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          )
                        else if (product.isLowStock)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.orange,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),

                    // SKU and category
                    Text(
                      'SKU: ${product.sku}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    Text(
                      product.categoryName ??
                          categoryNames[product.categoryId] ??
                          'Sin categoría',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    const Spacer(),

                    // Price and stock
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                ChileanUtils.formatCurrency(product.price),
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                              Text(
                                'Stock: ${product.inventoryQty}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: product.isOutOfStock
                                      ? Colors.red
                                      : product.isLowStock
                                          ? Colors.orange
                                          : Colors.grey[600],
                                  fontWeight:
                                      product.isOutOfStock || product.isLowStock
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          onPressed: () {
                            context
                                .push('/inventory/products/${product.id}/edit')
                                .then((_) {
                              _loadProducts();
                            });
                          },
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
    );
  }
}
