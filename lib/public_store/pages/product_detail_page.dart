import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../theme/public_store_theme.dart';
import '../providers/cart_provider.dart';
import '../../shared/services/inventory_service.dart';
import '../../shared/models/product.dart';
import '../../shared/utils/chilean_utils.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/public_store/utils/structured_data.dart';

class ProductDetailPage extends StatefulWidget {
  final String productId;

  const ProductDetailPage({super.key, required this.productId});

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  static const _structuredDataScriptId = 'vinabike-product-structured-data';
  Product? _product;
  List<Product> _relatedProducts = [];
  bool _isLoading = true;
  int _quantity = 1;
  int _selectedImageIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadProduct();
  }

  @override
  void didUpdateWidget(ProductDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.productId != oldWidget.productId) {
      removeStructuredDataScript(_structuredDataScriptId);
      _product = null;
      _relatedProducts = [];
      _quantity = 1;
      _selectedImageIndex = 0;
      _loadProduct();
    }
  }

  @override
  void dispose() {
    removeStructuredDataScript(_structuredDataScriptId);
    super.dispose();
  }

  Future<void> _loadProduct() async {
    setState(() => _isLoading = true);

    try {
      final inventoryService = context.read<InventoryService>();

      // Load the product
      _product = await inventoryService.getProductById(widget.productId);

      if (_product != null) {
        // Load related products (same category)
        final allProducts = await inventoryService.getProducts();
        _relatedProducts = allProducts
            .where((p) =>
                p.id != _product!.id &&
                p.categoryId == _product!.categoryId &&
                p.stockQuantity > 0)
            .take(4)
            .toList();

        if (mounted) {
          _updateStructuredData();
        }
      } else {
        removeStructuredDataScript(_structuredDataScriptId);
      }
    } catch (e) {
      debugPrint('[ProductDetailPage] Error loading product: $e');
      removeStructuredDataScript(_structuredDataScriptId);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _updateStructuredData() {
    final product = _product;
    if (product == null) {
      removeStructuredDataScript(_structuredDataScriptId);
      return;
    }

    final websiteService = context.read<WebsiteService>();
    final storeName = websiteService.getSetting('store_name', 'Vinabike');
    final storeUrl = websiteService.getSetting(
      'store_url',
      'https://tienda.vinabike.cl',
    );

    final productUrl = '$storeUrl/tienda/producto/${product.id}';
    final availability = product.stockQuantity > 0
        ? 'https://schema.org/InStock'
        : 'https://schema.org/OutOfStock';

    final imageList = <String>[];
    if (product.imageUrls.isNotEmpty) {
      imageList.addAll(product.imageUrls);
    } else if (product.imageUrl != null && product.imageUrl!.isNotEmpty) {
      imageList.add(product.imageUrl!);
    }

    final description = (product.description?.trim().isNotEmpty ?? false)
        ? product.description!.trim()
        : 'Encuentra $storeName online: ${product.name}';

    final priceString = product.price % 1 == 0
        ? product.price.toStringAsFixed(0)
        : product.price.toStringAsFixed(2);

    final structuredData = <String, dynamic>{
      '@context': 'https://schema.org/',
      '@type': 'Product',
      'name': product.name,
      'description': description,
      'sku': product.sku,
      if (product.barcode != null && product.barcode!.isNotEmpty)
        'gtin': product.barcode,
      'brand': {
        '@type': 'Brand',
        'name': product.brand?.isNotEmpty == true ? product.brand : storeName,
      },
      'offers': {
        '@type': 'Offer',
        'priceCurrency': 'CLP',
        'price': priceString,
        'availability': availability,
        'url': productUrl,
        'seller': {
          '@type': 'Organization',
          'name': storeName,
        },
        'itemCondition': 'https://schema.org/NewCondition',
      },
    };

    if (imageList.isNotEmpty) {
      structuredData['image'] =
          imageList.length == 1 ? imageList.first : imageList;
    }

    if (product.categoryName != null && product.categoryName!.isNotEmpty) {
      structuredData['category'] = product.categoryName;
    }

    setStructuredDataScript(_structuredDataScriptId, structuredData);
  }

  void _addToCart() {
    if (_product == null || _product!.stockQuantity < _quantity) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Stock insuficiente'),
          backgroundColor: PublicStoreTheme.error,
        ),
      );
      return;
    }

    final cart = context.read<CartProvider>();
    cart.addProduct(_product!, quantity: _quantity);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${_product!.name} agregado al carrito'),
        backgroundColor: PublicStoreTheme.success,
        action: SnackBarAction(
          label: 'Ver Carrito',
          textColor: Colors.white,
          onPressed: () => context.go('/tienda/carrito'),
        ),
      ),
    );

    setState(() => _quantity = 1);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_product == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: PublicStoreTheme.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              'Producto no encontrado',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => context.go('/tienda/productos'),
              child: const Text('Volver a productos'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1200),
        margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Breadcrumb
            _buildBreadcrumb(),

            const SizedBox(height: 32),

            // Product Main Section
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image Gallery (Left)
                Expanded(
                  flex: 5,
                  child: _buildImageGallery(),
                ),

                const SizedBox(width: 48),

                // Product Info (Right)
                Expanded(
                  flex: 4,
                  child: _buildProductInfo(),
                ),
              ],
            ),

            const SizedBox(height: 64),

            // Product Details Tabs
            _buildProductDetails(),

            const SizedBox(height: 64),

            // Related Products
            if (_relatedProducts.isNotEmpty) _buildRelatedProducts(),
          ],
        ),
      ),
    );
  }

  Widget _buildBreadcrumb() {
    return Row(
      children: [
        InkWell(
          onTap: () => context.go('/tienda'),
          child: Text(
            'Inicio',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: PublicStoreTheme.primaryBlue,
                ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.chevron_right, size: 16),
        ),
        InkWell(
          onTap: () => context.go('/tienda/productos'),
          child: Text(
            'Productos',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: PublicStoreTheme.primaryBlue,
                ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Icon(Icons.chevron_right, size: 16),
        ),
        Text(
          _product!.name,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: PublicStoreTheme.textSecondary,
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildImageGallery() {
    final images = _product!.imageUrls.isNotEmpty
        ? _product!.imageUrls
        : _product!.imageUrl != null
            ? [_product!.imageUrl!]
            : <String>[];

    if (images.isEmpty) {
      return Container(
        height: 500,
        decoration: BoxDecoration(
          color: PublicStoreTheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Icon(
            Icons.pedal_bike,
            size: 128,
            color: PublicStoreTheme.textMuted,
          ),
        ),
      );
    }

    return Column(
      children: [
        // Main Image
        Container(
          height: 500,
          decoration: BoxDecoration(
            color: PublicStoreTheme.surface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: PublicStoreTheme.cardShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              images[_selectedImageIndex],
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return const Center(
                  child: Icon(
                    Icons.broken_image,
                    size: 64,
                    color: PublicStoreTheme.textMuted,
                  ),
                );
              },
            ),
          ),
        ),

        // Thumbnail Gallery
        if (images.length > 1) ...[
          const SizedBox(height: 16),
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              itemBuilder: (context, index) {
                final isSelected = index == _selectedImageIndex;
                return Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: InkWell(
                    onTap: () => setState(() => _selectedImageIndex = index),
                    child: Container(
                      width: 80,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isSelected
                              ? PublicStoreTheme.primaryBlue
                              : PublicStoreTheme.border,
                          width: isSelected ? 3 : 1,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          images[index],
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(Icons.broken_image, size: 24);
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildProductInfo() {
    final cart = context.watch<CartProvider>();
    final inCart = cart.hasProduct(_product!.id);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Product Name
            Text(
              _product!.name,
              style: Theme.of(context).textTheme.displaySmall,
            ),

            const SizedBox(height: 8),

            // Brand
            if (_product!.brand != null)
              Text(
                _product!.brand!,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: PublicStoreTheme.textSecondary,
                    ),
              ),

            const SizedBox(height: 16),

            // SKU
            Row(
              children: [
                Text(
                  'SKU: ',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: PublicStoreTheme.textMuted,
                      ),
                ),
                Text(
                  _product!.sku,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: PublicStoreTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 24),

            // Price
            Text(
              ChileanUtils.formatCurrency(_product!.price),
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    color: PublicStoreTheme.primaryBlue,
                    fontWeight: FontWeight.bold,
                  ),
            ),

            const SizedBox(height: 8),

            Text(
              '+ IVA incluido',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: PublicStoreTheme.textMuted,
                  ),
            ),

            const SizedBox(height: 24),

            // Stock Status
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: _product!.stockQuantity > 0
                    ? PublicStoreTheme.success.withOpacity(0.1)
                    : PublicStoreTheme.error.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _product!.stockQuantity > 0
                      ? PublicStoreTheme.success
                      : PublicStoreTheme.error,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _product!.stockQuantity > 0
                        ? Icons.check_circle
                        : Icons.cancel,
                    color: _product!.stockQuantity > 0
                        ? PublicStoreTheme.success
                        : PublicStoreTheme.error,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _product!.stockQuantity > 0
                        ? 'En stock (${_product!.stockQuantity} disponibles)'
                        : 'Agotado',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: _product!.stockQuantity > 0
                              ? PublicStoreTheme.success
                              : PublicStoreTheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Quantity Selector
            if (_product!.stockQuantity > 0) ...[
              Text(
                'Cantidad',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  IconButton(
                    onPressed: _quantity > 1
                        ? () => setState(() => _quantity--)
                        : null,
                    icon: const Icon(Icons.remove),
                    style: IconButton.styleFrom(
                      backgroundColor: PublicStoreTheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: PublicStoreTheme.border),
                      ),
                    ),
                  ),
                  Container(
                    width: 80,
                    alignment: Alignment.center,
                    child: Text(
                      '$_quantity',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: _quantity < _product!.stockQuantity
                        ? () => setState(() => _quantity++)
                        : null,
                    icon: const Icon(Icons.add),
                    style: IconButton.styleFrom(
                      backgroundColor: PublicStoreTheme.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: const BorderSide(color: PublicStoreTheme.border),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 32),

              // Add to Cart Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _addToCart,
                  icon: Icon(inCart ? Icons.check : Icons.shopping_cart),
                  label: Text(
                      inCart ? 'AGREGADO AL CARRITO' : 'AGREGAR AL CARRITO'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    backgroundColor: inCart
                        ? PublicStoreTheme.success
                        : PublicStoreTheme.primaryBlue,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // View Cart Button
              if (inCart)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => context.go('/tienda/carrito'),
                    child: const Text('VER CARRITO'),
                  ),
                ),
            ],

            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 24),

            // Quick Info
            _buildInfoRow(Icons.local_shipping_outlined, 'Envío a todo Chile'),
            const SizedBox(height: 12),
            _buildInfoRow(Icons.store_outlined, 'Retiro en tienda disponible'),
            const SizedBox(height: 12),
            _buildInfoRow(Icons.verified_user_outlined, 'Garantía oficial'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: PublicStoreTheme.primaryBlue,
        ),
        const SizedBox(width: 12),
        Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildProductDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Detalles del Producto',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Description
                if (_product!.description != null) ...[
                  Text(
                    'Descripción',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _product!.description!,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 32),
                ],

                // Specifications
                if (_product!.specifications.isNotEmpty) ...[
                  Text(
                    'Especificaciones',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  ..._product!.specifications.entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 200,
                            child: Text(
                              '${entry.key}:',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: PublicStoreTheme.textSecondary,
                                  ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              entry.value,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ],

                // General Info
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),

                _buildDetailRow(
                    'Categoría', _product!.categoryName ?? 'Sin categoría'),
                if (_product!.brand != null)
                  _buildDetailRow('Marca', _product!.brand!),
                if (_product!.model != null)
                  _buildDetailRow('Modelo', _product!.model!),
                if (_product!.weight > 0)
                  _buildDetailRow('Peso', '${_product!.weight} kg'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 200,
            child: Text(
              '$label:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: PublicStoreTheme.textSecondary,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRelatedProducts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Productos Relacionados',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 24),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            childAspectRatio: 0.75,
            crossAxisSpacing: 24,
            mainAxisSpacing: 24,
          ),
          itemCount: _relatedProducts.length,
          itemBuilder: (context, index) {
            return _buildRelatedProductCard(_relatedProducts[index]);
          },
        ),
      ],
    );
  }

  Widget _buildRelatedProductCard(Product product) {
    return InkWell(
      onTap: () {
        // Navigate to this product's detail page
        context.go('/tienda/producto/${product.id}');
        // Reload data for new product
        setState(() {
          _selectedImageIndex = 0;
          _quantity = 1;
        });
        _loadProduct();
      },
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            AspectRatio(
              aspectRatio: 1,
              child: Container(
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
            ),

            // Info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ChileanUtils.formatCurrency(product.price),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: PublicStoreTheme.primaryBlue,
                          fontWeight: FontWeight.bold,
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
}
