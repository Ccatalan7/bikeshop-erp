import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../theme/public_store_theme.dart';
import '../../shared/services/inventory_service.dart';
import '../../shared/models/product.dart';
import '../../shared/utils/chilean_utils.dart';
import '../providers/cart_provider.dart';

class ProductCatalogPage extends StatefulWidget {
  const ProductCatalogPage({super.key});

  @override
  State<ProductCatalogPage> createState() => _ProductCatalogPageState();
}

class _ProductCatalogPageState extends State<ProductCatalogPage> {
  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  bool _isLoading = true;

  String _searchQuery = '';
  String? _selectedCategoryId;
  double _minPrice = 0;
  double _maxPrice = 1000000;
  String _sortBy = 'name'; // name, price_asc, price_desc, newest

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);

    try {
      final inventoryService = context.read<InventoryService>();
      _allProducts = await inventoryService.getProducts();

      // Calculate price range
      if (_allProducts.isNotEmpty) {
        _minPrice =
            _allProducts.map((p) => p.price).reduce((a, b) => a < b ? a : b);
        _maxPrice =
            _allProducts.map((p) => p.price).reduce((a, b) => a > b ? a : b);
      }

      _applyFilters();
    } catch (e) {
      debugPrint('[ProductCatalogPage] Error loading products: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredProducts = _allProducts.where((product) {
        // Search filter
        if (_searchQuery.isNotEmpty) {
          final query = _searchQuery.toLowerCase();
          if (!product.name.toLowerCase().contains(query) &&
              !product.sku.toLowerCase().contains(query) &&
              !(product.description?.toLowerCase().contains(query) ?? false)) {
            return false;
          }
        }

        // Category filter
        if (_selectedCategoryId != null &&
            product.categoryId != _selectedCategoryId) {
          return false;
        }

        // Price range filter
        if (product.price < _minPrice || product.price > _maxPrice) {
          return false;
        }

        return true;
      }).toList();

      // Apply sorting
      switch (_sortBy) {
        case 'name':
          _filteredProducts.sort((a, b) => a.name.compareTo(b.name));
          break;
        case 'price_asc':
          _filteredProducts.sort((a, b) => a.price.compareTo(b.price));
          break;
        case 'price_desc':
          _filteredProducts.sort((a, b) => b.price.compareTo(a.price));
          break;
        case 'newest':
          _filteredProducts.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 1400),
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sidebar Filters
          SizedBox(
            width: 280,
            child: _buildFilters(),
          ),

          const SizedBox(width: 32),

          // Main Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 24),
                _buildProductGrid(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Filtros',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 24),

            // Search
            TextField(
              decoration: const InputDecoration(
                labelText: 'Buscar productos',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                _searchQuery = value;
                _applyFilters();
              },
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),

            // Categories
            Text(
              'Categorías',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            _buildCategoryFilters(),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),

            // Price Range
            Text(
              'Rango de Precio',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Text(
              '${ChileanUtils.formatCurrency(_minPrice)} - ${ChileanUtils.formatCurrency(_maxPrice)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: PublicStoreTheme.textSecondary,
                  ),
            ),
            const SizedBox(height: 8),
            RangeSlider(
              values: RangeValues(_minPrice, _maxPrice),
              min: 0,
              max: _allProducts.isNotEmpty
                  ? _allProducts
                      .map((p) => p.price)
                      .reduce((a, b) => a > b ? a : b)
                  : 1000000,
              divisions: 20,
              labels: RangeLabels(
                ChileanUtils.formatCurrency(_minPrice),
                ChileanUtils.formatCurrency(_maxPrice),
              ),
              onChanged: (RangeValues values) {
                setState(() {
                  _minPrice = values.start;
                  _maxPrice = values.end;
                });
                _applyFilters();
              },
            ),

            const SizedBox(height: 24),

            // Reset Filters
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  setState(() {
                    _searchQuery = '';
                    _selectedCategoryId = null;
                    _minPrice = 0;
                    _maxPrice = _allProducts.isNotEmpty
                        ? _allProducts
                            .map((p) => p.price)
                            .reduce((a, b) => a > b ? a : b)
                        : 1000000;
                  });
                  _applyFilters();
                },
                child: const Text('Limpiar Filtros'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryFilters() {
    final categories = _allProducts
        .where((p) => p.categoryId != null)
        .map((p) =>
            {'id': p.categoryId!, 'name': p.categoryName ?? 'Sin categoría'})
        .toSet()
        .toList();

    if (categories.isEmpty) {
      return Text(
        'No hay categorías disponibles',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: PublicStoreTheme.textMuted,
            ),
      );
    }

    return Column(
      children: [
        RadioListTile<String?>(
          title: const Text('Todas'),
          value: null,
          groupValue: _selectedCategoryId,
          onChanged: (value) {
            setState(() => _selectedCategoryId = value);
            _applyFilters();
          },
          contentPadding: EdgeInsets.zero,
        ),
        ...categories.map((category) {
          final count =
              _allProducts.where((p) => p.categoryId == category['id']).length;

          return RadioListTile<String>(
            title: Text('${category['name']} ($count)'),
            value: category['id'] as String,
            groupValue: _selectedCategoryId,
            onChanged: (value) {
              setState(() => _selectedCategoryId = value);
              _applyFilters();
            },
            contentPadding: EdgeInsets.zero,
          );
        }).toList(),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Todos los Productos',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 8),
            Text(
              '${_filteredProducts.length} productos encontrados',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: PublicStoreTheme.textSecondary,
                  ),
            ),
          ],
        ),

        // Sort Dropdown
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<String>(
            value: _sortBy,
            decoration: const InputDecoration(
              labelText: 'Ordenar por',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'name', child: Text('Nombre')),
              DropdownMenuItem(
                  value: 'price_asc', child: Text('Precio: Menor a Mayor')),
              DropdownMenuItem(
                  value: 'price_desc', child: Text('Precio: Mayor a Menor')),
              DropdownMenuItem(value: 'newest', child: Text('Más Recientes')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() => _sortBy = value);
                _applyFilters();
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProductGrid() {
    if (_filteredProducts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 64,
                color: PublicStoreTheme.textMuted,
              ),
              const SizedBox(height: 16),
              Text(
                'No se encontraron productos',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: PublicStoreTheme.textSecondary,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Intenta ajustar los filtros de búsqueda',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: PublicStoreTheme.textMuted,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.75,
        crossAxisSpacing: 24,
        mainAxisSpacing: 24,
      ),
      itemCount: _filteredProducts.length,
      itemBuilder: (context, index) {
        return _buildProductCard(_filteredProducts[index]);
      },
    );
  }

  Widget _buildProductCard(Product product) {
    final cart = context.watch<CartProvider>();
    final inCart = cart.hasProduct(product.id);

    return InkWell(
      onTap: () => context.go('/tienda/producto/${product.id}'),
      child: Card(
        elevation: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Image
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: PublicStoreTheme.surface,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(12),
                      ),
                    ),
                    child: product.imageUrl != null
                        ? ClipRRect(
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(12),
                            ),
                            child: Image.network(
                              product.imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return const Center(
                                  child: Icon(
                                    Icons.image_not_supported,
                                    size: 48,
                                    color: PublicStoreTheme.textMuted,
                                  ),
                                );
                              },
                            ),
                          )
                        : const Center(
                            child: Icon(
                              Icons.pedal_bike,
                              size: 64,
                              color: PublicStoreTheme.textMuted,
                            ),
                          ),
                  ),

                  // Stock Badge
                  if (product.stockQuantity == 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: PublicStoreTheme.error,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Agotado',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ),
                    ),

                  // In Cart Badge
                  if (inCart)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          color: PublicStoreTheme.success,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Product Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (product.brand != null)
                      Text(
                        product.brand!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: PublicStoreTheme.textMuted,
                            ),
                      ),
                    const Spacer(),
                    Text(
                      ChileanUtils.formatCurrency(product.price),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: PublicStoreTheme.primaryBlue,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: product.stockQuantity > 0
                              ? Text(
                                  'Stock: ${product.stockQuantity}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: PublicStoreTheme.success,
                                      ),
                                )
                              : Text(
                                  'Sin stock',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: PublicStoreTheme.error,
                                      ),
                                ),
                        ),
                        Icon(
                          Icons.arrow_forward,
                          size: 16,
                          color: PublicStoreTheme.primaryBlue,
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
