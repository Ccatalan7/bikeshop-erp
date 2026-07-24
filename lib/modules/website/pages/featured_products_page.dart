import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/website_service.dart';
import '../models/website_models.dart';
import '../../../shared/services/inventory_service.dart';
import '../../../shared/models/product.dart';
import '../../../shared/utils/chilean_utils.dart';
import '../../../shared/widgets/branded_loading.dart';
import '../widgets/website_admin_ui.dart';

/// Page for selecting and managing featured products shown on website homepage
class FeaturedProductsPage extends StatefulWidget {
  const FeaturedProductsPage({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  @override
  State<FeaturedProductsPage> createState() => _FeaturedProductsPageState();
}

class _FeaturedProductsPageState extends State<FeaturedProductsPage> {
  final TextEditingController _searchController = TextEditingController();
  List<Product> _allProducts = [];
  List<Product> _filteredProducts = [];
  bool _isLoadingProducts = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WebsiteService>().loadFeaturedProducts();
      _loadProducts();
    });
    _searchController.addListener(_filterProducts);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoadingProducts = true);
    try {
      final products = await context.read<InventoryService>().getProducts();
      if (mounted) {
        setState(() {
          _allProducts = products;
          _filteredProducts = products;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingProducts = false);
      }
    }
  }

  void _filterProducts() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredProducts = _allProducts;
      } else {
        _filteredProducts = _allProducts.where((product) {
          return product.name.toLowerCase().contains(query) ||
              product.sku.toLowerCase().contains(query) ||
              (product.description?.toLowerCase().contains(query) ?? false);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final websiteService = context.watch<WebsiteService>();
    final featured = websiteService.featuredProducts;

    // Get full product details for featured products
    final featuredProductDetails = featured
        .map((fp) => _allProducts.firstWhere(
              (p) => p.id == fp.productId,
              orElse: () => Product(
                id: fp.productId,
                name: 'Producto no encontrado',
                sku: 'N/A',
                price: 0,
                cost: 0,
                stockQuantity: 0,
                category: ProductCategory.other,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            ))
        .toList();

    return WebsiteAdminShell(
      embedded: widget.embedded,
      showHeaderWhenEmbedded: false,
      title: 'Productos destacados',
      description:
          'Elige hasta ocho productos para los bloques con fuente Destacados.',
      child: websiteService.isLoading && featured.isEmpty
          ? const Center(child: BrandedLoading())
          : Column(
              children: [
                _buildFeaturedToolbar(
                  theme,
                  featuredCount: featured.length,
                  onRefresh: () {
                    websiteService.loadFeaturedProducts();
                    _loadProducts();
                  },
                ),
                if (featured.isNotEmpty)
                  _buildFeaturedOrder(
                    theme,
                    featured: featured,
                    products: featuredProductDetails,
                    service: websiteService,
                  ),
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
                Expanded(
                  child: _isLoadingProducts
                      ? const Center(child: BrandedLoading())
                      : _filteredProducts.isEmpty
                          ? Center(
                              child: Text(
                                _searchController.text.isEmpty
                                    ? 'No hay productos disponibles.'
                                    : 'No se encontraron productos.',
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                            )
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.fromLTRB(12, 10, 12, 12),
                              itemCount: _filteredProducts.length,
                              itemBuilder: (context, index) {
                                final product = _filteredProducts[index];
                                final isFeatured = featured.any(
                                  (item) => item.productId == product.id,
                                );
                                return _buildProductListItem(
                                  context,
                                  product,
                                  isFeatured,
                                  websiteService,
                                  featured.length >= 8,
                                );
                              },
                            ),
                ),
              ],
            ),
    );
  }

  Widget _buildFeaturedToolbar(
    ThemeData theme, {
    required int featuredCount,
    required VoidCallback onRefresh,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: theme.colorScheme.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 820;
          final status = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star_rounded, color: Colors.amber.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                '$featuredCount de 8 en portada',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          );
          final search = SizedBox(
            width: compact ? constraints.maxWidth : 380,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Buscar producto por nombre o SKU',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar búsqueda',
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: _searchController.clear,
                      ),
              ),
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: status),
                    IconButton.outlined(
                      tooltip: 'Actualizar productos',
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh_rounded, size: 19),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                search,
              ],
            );
          }

          return Row(
            children: [
              status,
              const SizedBox(width: 18),
              Expanded(child: search),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Actualizar productos',
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 19),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFeaturedOrder(
    ThemeData theme, {
    required List<FeaturedProduct> featured,
    required List<Product> products,
    required WebsiteService service,
  }) {
    return Container(
      height: 132,
      padding: const EdgeInsets.only(top: 8),
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(
                  'Orden en portada',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  'Arrastra para ordenar',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: products.length,
              onReorder: (oldIndex, newIndex) {
                _reorderFeatured(service, oldIndex, newIndex);
              },
              itemBuilder: (context, index) => _buildFeaturedProductCard(
                context,
                products[index],
                featured[index],
                service,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturedProductCard(
    BuildContext context,
    Product product,
    FeaturedProduct featuredItem,
    WebsiteService service,
  ) {
    final warningColor = Colors.orange.shade700;
    return Card(
      key: ValueKey(featuredItem.id),
      margin: const EdgeInsets.only(right: 8),
      child: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(8)),
              child: product.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: product.imageUrl!,
                      height: 54,
                      width: 150,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        height: 54,
                        color: Colors.white,
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        height: 54,
                        color: Colors.white,
                        child: const Icon(Icons.image, color: Colors.grey),
                      ),
                    )
                  : Container(
                      height: 54,
                      color: Colors.white,
                      child: const Icon(Icons.image, color: Colors.grey),
                    ),
            ),

            // Info
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (!product.isPublished || !product.isActive)
                        Tooltip(
                          message:
                              !product.isActive ? 'Inactivo' : 'No publicado',
                          child: Icon(
                            Icons.visibility_off_outlined,
                            size: 14,
                            color: warningColor,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          ChileanUtils.formatCurrency(product.price),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      InkWell(
                        onTap: () => _removeFeatured(service, featuredItem.id),
                        child: const Icon(
                          Icons.remove_circle,
                          size: 20,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductListItem(
    BuildContext context,
    Product product,
    bool isFeatured,
    WebsiteService service,
    bool maxReached,
  ) {
    final theme = Theme.of(context);
    final warningColor = Colors.orange.shade700;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: ListTile(
        dense: true,
        leading: product.imageUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CachedNetworkImage(
                  imageUrl: product.imageUrl!,
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    width: 50,
                    height: 50,
                    color: Colors.grey[300],
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: 50,
                    height: 50,
                    color: Colors.grey[300],
                    child: const Icon(Icons.image, size: 24),
                  ),
                ),
              )
            : Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.image, size: 24),
              ),
        title: Text(product.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('SKU: ${product.sku}'),
                const SizedBox(width: 12),
                Text(
                  ChileanUtils.formatCurrency(product.price),
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            if (!product.isPublished || !product.isActive)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.visibility_off_outlined,
                      size: 16,
                      color: warningColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      !product.isActive
                          ? 'Producto inactivo (no visible en web)'
                          : 'No publicado en la tienda online',
                      style: TextStyle(
                        color: warningColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        trailing: isFeatured
            ? const Tooltip(
                message: 'Ya está en la portada',
                child: Icon(Icons.star_rounded, color: Colors.amber),
              )
            : maxReached
                ? const Tooltip(
                    message: 'Ya hay 8 productos; quita uno para agregar otro',
                    child: Icon(Icons.block_outlined),
                  )
                : IconButton(
                    tooltip: 'Agregar a la portada',
                    icon: const Icon(Icons.add_circle),
                    color: theme.colorScheme.primary,
                    onPressed: () => _addFeatured(service, product.id),
                  ),
      ),
    );
  }

  void _reorderFeatured(
    WebsiteService service,
    int oldIndex,
    int newIndex,
  ) {
    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    final featured = List<FeaturedProduct>.from(service.featuredProducts);
    final item = featured.removeAt(oldIndex);
    featured.insert(newIndex, item);

    service.reorderFeaturedProducts(featured);
  }

  Future<void> _addFeatured(WebsiteService service, String productId) async {
    if (service.featuredProducts.length >= 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Máximo 8 productos destacados'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      await service.addFeaturedProduct(productId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Producto agregado a destacados')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _removeFeatured(WebsiteService service, String id) async {
    try {
      await service.removeFeaturedProduct(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Producto removido de destacados')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}
