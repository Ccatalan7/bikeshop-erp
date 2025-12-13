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
import '../../shared/widgets/branded_loading.dart';

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

      // Load the product - support both UUID and SKU-based lookups
      // SKU format: "sku:S56467" (from legacy /shop/ URLs)
      if (widget.productId.startsWith('sku:')) {
        final sku = widget.productId.substring(4); // Remove "sku:" prefix
        debugPrint('🔍 [ProductDetail] Looking up product by SKU: $sku');
        _product = await inventoryService.getProductBySku(sku);
      } else {
        _product = await inventoryService.getProductById(widget.productId);
      }

      if (_product != null) {
        debugPrint('✅ [ProductDetail] Found product: ${_product!.name}');
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
        debugPrint('❌ [ProductDetail] Product not found: ${widget.productId}');
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
      return const Center(child: BrandedLoading());
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
        decoration: const BoxDecoration(
          color: Colors.white,
        ),
        child: const Center(
          child: Icon(
            Icons.pedal_bike_outlined,
            size: 100,
            color: Colors.grey,
          ),
        ),
      );
    }

    return Column(
      children: [
        // Main Image - Clean, no border
        Container(
          height: 500,
          decoration: const BoxDecoration(
            color: Colors.white,
          ),
          padding: const EdgeInsets.all(24),
          child: Image.network(
            images[_selectedImageIndex],
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 64,
                  color: Colors.grey,
                ),
              );
            },
          ),
        ),

        // Thumbnail Gallery - Minimal styling
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
                        border: isSelected
                            ? Border.all(color: Colors.black, width: 2)
                            : null,
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Image.network(
                        images[index],
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(Icons.broken_image, size: 24);
                        },
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
    final inStock = _product!.stockQuantity > 0;

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Product Name - Clean uppercase style
          Text(
            _product!.name,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: Colors.black87,
              height: 1.3,
            ),
          ),

          const SizedBox(height: 12),

          // Brand
          if (_product!.brand != null && _product!.brand!.isNotEmpty)
            Text(
              _product!.brand!,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),

          const SizedBox(height: 12),

          // SKU - Minimal
          Text(
            'SKU: ${_product!.sku}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
            ),
          ),

          const SizedBox(height: 24),
          Divider(color: Colors.grey.shade200),
          const SizedBox(height: 24),

          // Price - Bold and prominent
          Text(
            ChileanUtils.formatCurrency(_product!.price),
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: PublicStoreTheme.primaryBlue,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            '+ IVA incluido',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
            ),
          ),

          const SizedBox(height: 24),

          // Stock Status - Clean badge style
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: inStock
                  ? Colors.green.shade50
                  : Colors.red.shade50,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  inStock ? Icons.check_circle_outline : Icons.cancel_outlined,
                  color: inStock ? Colors.green.shade700 : Colors.red.shade700,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  inStock ? 'Disponible' : 'Agotado',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: inStock ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Quantity & Add to Cart
          if (inStock) ...[
            // Quantity Selector - Minimal
            Row(
              children: [
                Text(
                  'Cantidad:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(width: 16),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: _quantity > 1
                            ? () => setState(() => _quantity--)
                            : null,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          child: Icon(
                            Icons.remove,
                            size: 18,
                            color: _quantity > 1 ? Colors.black87 : Colors.grey.shade400,
                          ),
                        ),
                      ),
                      Container(
                        width: 50,
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          border: Border.symmetric(
                            vertical: BorderSide(color: Colors.grey.shade300),
                          ),
                        ),
                        child: Text(
                          '$_quantity',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: _quantity < _product!.stockQuantity
                            ? () => setState(() => _quantity++)
                            : null,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          child: Icon(
                            Icons.add,
                            size: 18,
                            color: _quantity < _product!.stockQuantity 
                                ? Colors.black87 
                                : Colors.grey.shade400,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Add to Cart Button - Clean, minimal
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _addToCart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: inCart ? Colors.green.shade600 : Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(0),
                  ),
                  elevation: 0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      inCart ? Icons.check : Icons.shopping_bag_outlined,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      inCart ? 'AGREGADO AL CARRITO' : 'AGREGAR AL CARRITO',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // View Cart Link
            if (inCart) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => context.go('/tienda/carrito'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    side: const BorderSide(color: Colors.black87, width: 1),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(0),
                    ),
                  ),
                  child: const Text(
                    'VER CARRITO',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ],
          ] else ...[
            // Out of stock message
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cancel_outlined, color: Colors.red.shade700, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Agotado',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.red.shade700,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),
          Divider(color: Colors.grey.shade200),
          const SizedBox(height: 24),

          // Quick Info - Clean icons
          _buildInfoRow(Icons.local_shipping_outlined, 'Envío a todo Chile'),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.storefront_outlined, 'Retiro en tienda disponible'),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.verified_outlined, 'Garantía oficial'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(
          icon,
          size: 18,
          color: Colors.grey.shade600,
        ),
        const SizedBox(width: 12),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade700,
          ),
        ),
      ],
    );
  }

  Widget _buildProductDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header with vertical bar
        Row(
          children: [
            Container(
              width: 4,
              height: 28,
              color: Colors.black,
              margin: const EdgeInsets.only(right: 12),
            ),
            const Text(
              'DETALLES DEL PRODUCTO',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: Colors.black,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Description
              if (_product!.description != null && _product!.description!.isNotEmpty) ...[
                const Text(
                  'Descripción',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _product!.description!,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 24),
                Divider(color: Colors.grey.shade200),
                const SizedBox(height: 24),
              ],

              // Specifications
              if (_product!.specifications.isNotEmpty) ...[
                const Text(
                  'Especificaciones',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 16),
                ..._product!.specifications.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 180,
                          child: Text(
                            entry.key,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            entry.value,
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 16),
                Divider(color: Colors.grey.shade200),
                const SizedBox(height: 16),
              ],

              // General Info
              _buildDetailRow('Categoría', _product!.categoryName ?? 'Sin categoría'),
              if (_product!.brand != null && _product!.brand!.isNotEmpty)
                _buildDetailRow('Marca', _product!.brand!),
              if (_product!.model != null && _product!.model!.isNotEmpty)
                _buildDetailRow('Modelo', _product!.model!),
              if (_product!.weight > 0)
                _buildDetailRow('Peso', '${_product!.weight} kg'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black87,
              ),
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
        // Section header with vertical bar (like product cards section)
        Row(
          children: [
            Container(
              width: 4,
              height: 28,
              color: Colors.black,
              margin: const EdgeInsets.only(right: 12),
            ),
            const Text(
              'PRODUCTOS RELACIONADOS',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: Colors.black,
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            childAspectRatio: 0.75,
            crossAxisSpacing: 20,
            mainAxisSpacing: 20,
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
    final hasImage = product.imageUrl != null && product.imageUrl!.isNotEmpty;
    
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          context.go('/tienda/producto/${product.id}');
          setState(() {
            _selectedImageIndex = 0;
            _quantity = 1;
          });
          _loadProduct();
        },
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image - takes most of the space
              Expanded(
                flex: 4,
                child: Container(
                  width: double.infinity,
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  child: hasImage
                      ? Image.network(
                          product.imageUrl!,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return Center(
                              child: Icon(
                                Icons.pedal_bike_outlined,
                                size: 40,
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
              ),
              // Product info
              Expanded(
                flex: 2,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        product.name.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.3,
                          color: Colors.black87,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        ChileanUtils.formatCurrency(product.price),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
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
