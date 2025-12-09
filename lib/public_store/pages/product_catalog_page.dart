import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../theme/public_store_theme.dart';
import '../services/public_inventory_service.dart';
import '../providers/public_store_tenant_provider.dart';
import '../../shared/models/product.dart';
import '../../shared/utils/chilean_utils.dart';
import '../providers/cart_provider.dart';
import '../../shared/widgets/branded_loading.dart';

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
    // Get tenant from provider (detected from subdomain)
    final tenantProvider = context.read<PublicStoreTenantProvider>();
    final tenantId = tenantProvider.tenantId;

    if (tenantId == null) {
      setState(() => _isLoading = false);
      return;
    }

    // Use public inventory service (works for anonymous users)
    final publicInventoryService = context.read<PublicInventoryService>();
    
    // Check if we already have cached products - instant render!
    if (publicInventoryService.hasProductsCache(tenantId)) {
      _allProducts = await publicInventoryService.getProductsForTenant(
        tenantId: tenantId,
        onlyInStock: false,
      );
      _updatePriceRange();
      _applyFilters();
      setState(() => _isLoading = false);
      return;
    }

    // No cache - show loading and fetch
    setState(() => _isLoading = true);

    try {
      _allProducts = await publicInventoryService.getProductsForTenant(
        tenantId: tenantId,
        onlyInStock: false, // Show all products
      );

      _updatePriceRange();
      _applyFilters();
    } catch (e) {
      debugPrint('[ProductCatalogPage] Error loading products: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _updatePriceRange() {
    if (_allProducts.isNotEmpty) {
      _minPrice =
          _allProducts.map((p) => p.price).reduce((a, b) => a < b ? a : b);
      _maxPrice =
          _allProducts.map((p) => p.price).reduce((a, b) => a > b ? a : b);
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
      return const Center(child: BrandedLoading());
    }

    return Container(
      color: Colors.white,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1400),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sidebar Filters
                SizedBox(
                  width: 260,
                  child: _buildFilters(),
                ),

                const SizedBox(width: 40),

                // Main Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 32),
                      _buildProductGrid(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Filtros',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 24),

        // Search
        TextField(
          decoration: InputDecoration(
            hintText: 'Buscar productos',
            hintStyle: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 20),
            filled: true,
            fillColor: Colors.grey.shade100,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(0),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          style: const TextStyle(fontSize: 14),
          onChanged: (value) {
            _searchQuery = value;
            _applyFilters();
          },
        ),

        const SizedBox(height: 32),
        Container(height: 1, color: Colors.grey.shade200),
        const SizedBox(height: 24),

        // Categories
        const Text(
          'Categorías',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 16),
        _buildCategoryFilters(),
      ],
    );
  }

  Widget _buildCategoryFilters() {
    final categories = _allProducts
        .where((p) => p.categoryId != null)
        .map((p) =>
            {'id': p.categoryId!, 'name': p.categoryName ?? 'Sin categoría'})
        .toSet()
        .toList();

    return Column(
      children: [
        _buildCategoryOption(null, 'Todas', _allProducts.length),
        ...categories.map((category) {
          final count =
              _allProducts.where((p) => p.categoryId == category['id']).length;
          return _buildCategoryOption(
            category['id'] as String,
            category['name'] as String,
            count,
          );
        }).toList(),
      ],
    );
  }

  Widget _buildCategoryOption(String? id, String name, int count) {
    final isSelected = _selectedCategoryId == id;
    return InkWell(
      onTap: () {
        setState(() => _selectedCategoryId = id);
        _applyFilters();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.black : Colors.grey.shade400,
                  width: isSelected ? 5 : 1,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$name ($count)',
                style: TextStyle(
                  fontSize: 13,
                  color: isSelected ? Colors.black : Colors.grey.shade700,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4,
                  height: 24,
                  color: Colors.black,
                  margin: const EdgeInsets.only(right: 12),
                ),
                const Text(
                  'PRODUCTOS',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${_filteredProducts.length} productos encontrados',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),

        // Sort Dropdown
        Row(
          children: [
            Text(
              'Ordenar por',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _sortBy,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black87,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'name', child: Text('Nombre')),
                    DropdownMenuItem(value: 'price_asc', child: Text('Precio: Menor a Mayor')),
                    DropdownMenuItem(value: 'price_desc', child: Text('Precio: Mayor a Menor')),
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
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProductGrid() {
    if (_filteredProducts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(64),
          child: Column(
            children: [
              Icon(
                Icons.inventory_2_outlined,
                size: 48,
                color: Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              const Text(
                'No se encontraron productos',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Intenta ajustar los filtros de búsqueda',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade500,
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
        childAspectRatio: 0.72,
        crossAxisSpacing: 20,
        mainAxisSpacing: 20,
      ),
      itemCount: _filteredProducts.length,
      itemBuilder: (context, index) {
        return _CatalogProductCard(product: _filteredProducts[index]);
      },
    );
  }
}

// Premium product card for catalog page
class _CatalogProductCard extends StatefulWidget {
  final Product product;
  
  const _CatalogProductCard({required this.product});
  
  @override
  State<_CatalogProductCard> createState() => _CatalogProductCardState();
}

class _CatalogProductCardState extends State<_CatalogProductCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final hasImage = product.imageUrl != null && product.imageUrl!.isNotEmpty;
    final inStock = product.stockQuantity > 0;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.go('/tienda/producto/${product.id}'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: const BoxDecoration(
            color: Colors.white,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Image
              Expanded(
                flex: 5,
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      color: Colors.white,
                      padding: const EdgeInsets.all(16),
                      child: hasImage
                          ? Image.network(
                              product.imageUrl!,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return Center(
                                  child: Icon(
                                    Icons.pedal_bike_outlined,
                                    size: 48,
                                    color: Colors.grey.shade400,
                                  ),
                                );
                              },
                            )
                          : Center(
                              child: Icon(
                                Icons.pedal_bike_outlined,
                                size: 48,
                                color: Colors.grey.shade400,
                              ),
                            ),
                    ),
                    // Out of stock badge
                    if (!inStock)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          color: Colors.black87,
                          child: const Text(
                            'AGOTADO',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    // Hover overlay
                    if (_isHovered)
                      Positioned(
                        bottom: 12,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            color: Colors.black,
                            child: const Text(
                              'VER PRODUCTO',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Product Info
              Expanded(
                flex: 3,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Brand
                      if (product.brand != null && product.brand!.isNotEmpty)
                        Text(
                          product.brand!.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade500,
                            letterSpacing: 0.5,
                          ),
                        ),
                      const SizedBox(height: 4),
                      // Product name
                      Expanded(
                        child: Text(
                          product.name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 8),
                      // Price
                      Text(
                        ChileanUtils.formatCurrency(product.price),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                      if (inStock)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Stock: ${product.stockQuantity}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
