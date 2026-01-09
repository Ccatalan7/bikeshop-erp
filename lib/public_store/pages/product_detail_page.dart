import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../theme/public_store_theme.dart';
import '../providers/cart_provider.dart';
import '../providers/public_store_tenant_provider.dart';
import '../services/public_inventory_service.dart';
import '../widgets/full_page_loading.dart';
import '../../shared/models/product.dart';
import '../../shared/utils/chilean_utils.dart';
import '../../shared/utils/seo_helper.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/public_store/utils/structured_data.dart';

class ProductDetailPage extends StatefulWidget {
  final String productId;

  const ProductDetailPage({super.key, required this.productId});

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage>
    with AutomaticKeepAliveClientMixin {
  static const _structuredDataScriptId = 'vinabike-product-structured-data';
  Product? _product;
  List<Product> _relatedProducts = [];
  bool _isLoading = true;
  bool _isLoadingRelated = false;
  int _quantity = 1;
  int _selectedImageIndex = 0;
  int _loadToken = 0;

  // Keep this page alive in memory to prevent reloading on navigation
  @override
  bool get wantKeepAlive => true;

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
    final token = ++_loadToken;
    setState(() {
      _isLoading = true;
      _isLoadingRelated = false;
      _relatedProducts = [];
    });

    try {
      final inventoryService = context.read<PublicInventoryService>();
      final tenantProvider = context.read<PublicStoreTenantProvider>();
      final tenantId = tenantProvider.tenantId;

      if (tenantId == null) {
        debugPrint('❌ [ProductDetail] No tenant ID available');
        return;
      }

      // Load the product - support both UUID and SKU-based lookups
      // SKU format: "sku:S56467" (from legacy /shop/ URLs)
      final Product? loadedProduct;
      if (widget.productId.startsWith('sku:')) {
        final sku = widget.productId.substring(4); // Remove "sku:" prefix
        debugPrint('🔍 [ProductDetail] Looking up product by SKU: $sku');
        loadedProduct = await inventoryService.getProductBySku(
          sku: sku,
          tenantId: tenantId,
        );
      } else {
        loadedProduct = await inventoryService.getProductById(
          productId: widget.productId,
          tenantId: tenantId,
        );
      }

      if (!mounted || token != _loadToken) return;

      _product = loadedProduct;

      if (_product != null) {
        debugPrint('✅ [ProductDetail] Found product: ${_product!.name}');
        // Render immediately, then load related products in background.
        setState(() => _isLoading = false);
        _updateSeo();
        _updateStructuredData();
        _loadRelatedProducts(
          token: token,
          inventoryService: inventoryService,
          tenantId: tenantId,
          product: _product!,
        );
      } else {
        debugPrint('❌ [ProductDetail] Product not found: ${widget.productId}');
        removeStructuredDataScript(_structuredDataScriptId);
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('[ProductDetailPage] Error loading product: $e');
      removeStructuredDataScript(_structuredDataScriptId);
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadRelatedProducts({
    required int token,
    required PublicInventoryService inventoryService,
    required String tenantId,
    required Product product,
  }) async {
    final categoryId = product.categoryId;
    if (categoryId == null || categoryId.isEmpty) return;

    setState(() => _isLoadingRelated = true);
    try {
      final allProducts = await inventoryService.getProductsForTenant(
        tenantId: tenantId,
        categoryId: categoryId,
        onlyInStock: true,
        limit: 12,
      );

      if (!mounted || token != _loadToken) return;
      setState(() {
        _relatedProducts =
            allProducts.where((p) => p.id != product.id).take(4).toList();
        _isLoadingRelated = false;
      });
    } catch (_) {
      if (!mounted || token != _loadToken) return;
      setState(() => _isLoadingRelated = false);
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

    final productUrl = '$storeUrl/productos/${product.id}';
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

  void _updateSeo() {
    final product = _product;
    if (product == null) return;

    final websiteService = context.read<WebsiteService>();
    final storeName = websiteService.getSetting('store_name', 'Vinabike');

    // Templates are configurable via website_settings (and later via SEO editor UI).
    final titleTemplate = websiteService.getSetting(
      'seo_product_title_template',
      '{product_name} | {store_name}',
    );
    final descriptionTemplate = websiteService.getSetting(
      'seo_product_description_template',
      '{product_description}',
    );

    final resolvedTitle = _applySeoTemplate(
      template: titleTemplate,
      storeName: storeName,
      product: product,
    ).trim();

    final fallbackDescription = (product.description?.trim().isNotEmpty ?? false)
        ? product.description!.trim()
        : 'Compra ${product.name} online en $storeName. Envíos y retiro en tienda.';

    final resolvedDescription = _applySeoTemplate(
      template: descriptionTemplate,
      storeName: storeName,
      product: product,
      fallbackDescription: fallbackDescription,
    ).trim();

    final image = (product.imageUrls.isNotEmpty)
        ? product.imageUrls.first
        : (product.imageUrl?.isNotEmpty == true ? product.imageUrl : null);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SeoHelper.updateSeo(
        title: resolvedTitle.isNotEmpty ? resolvedTitle : '$storeName',
        description: resolvedDescription.isNotEmpty ? resolvedDescription : null,
        imageUrl: image,
      );
    });
  }

  String _applySeoTemplate({
    required String template,
    required String storeName,
    required Product product,
    String? fallbackDescription,
  }) {
    final priceText = ChileanUtils.formatCurrency(product.price);
    final brandText = (product.brand?.trim().isNotEmpty ?? false)
        ? product.brand!.trim()
        : storeName;

    final descriptionText = (product.description?.trim().isNotEmpty ?? false)
        ? product.description!.trim()
        : (fallbackDescription ?? '');

    return template
        .replaceAll('{store_name}', storeName)
        .replaceAll('{product_name}', product.name)
      .replaceAll('{product_sku}', product.sku.isNotEmpty ? product.sku : '')
        .replaceAll('{product_price}', priceText)
        .replaceAll('{product_brand}', brandText)
        .replaceAll('{product_description}', descriptionText);
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
          onPressed: () => context.go('/carrito'),
        ),
      ),
    );

    setState(() => _quantity = 1);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    if (_isLoading) {
      return const FullPageLoading();
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
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/productos');
                }
              },
              child: const Text('Volver a productos'),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 768;
        final horizontalMargin = isMobile ? 12.0 : 24.0;
        final verticalMargin = isMobile ? 16.0 : 48.0;

        return SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1200),
            margin: EdgeInsets.symmetric(
                horizontal: horizontalMargin, vertical: verticalMargin),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Breadcrumb (hide on mobile to save space)
                if (!isMobile) _buildBreadcrumb(),
                if (!isMobile) const SizedBox(height: 32),

                // Product Main Section - Responsive layout
                if (isMobile) ...[
                  // Mobile: Stack vertically
                  _buildImageGallery(isMobile: true),
                  const SizedBox(height: 24),
                  _buildProductInfo(isMobile: true),
                ] else ...[
                  // Desktop: Side by side
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 5,
                        child: _buildImageGallery(),
                      ),
                      const SizedBox(width: 48),
                      Expanded(
                        flex: 4,
                        child: _buildProductInfo(),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 64),

                // Product Details Tabs
                _buildProductDetails(),

                const SizedBox(height: 64),

                // Related Products
                if (_isLoadingRelated)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (_relatedProducts.isNotEmpty)
                  _buildRelatedProducts(),

                // Bottom spacing to prevent footer overlap
                SizedBox(height: isMobile ? 80 : 64),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBreadcrumb() {
    return Row(
      children: [
        InkWell(
          onTap: () => context.go('/'),
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
          onTap: () => context.go('/productos'),
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

  Widget _buildImageGallery({bool isMobile = false}) {
    final images = _product!.imageUrls.isNotEmpty
        ? _product!.imageUrls
        : _product!.imageUrl != null
            ? [_product!.imageUrl!]
            : <String>[];

    final imageHeight = isMobile ? 300.0 : 500.0;

    if (images.isEmpty) {
      return Container(
        height: imageHeight,
        decoration: const BoxDecoration(
          color: Colors.white,
        ),
        child: Center(
          child: Icon(
            Icons.pedal_bike_outlined,
            size: isMobile ? 60 : 100,
            color: Colors.grey,
          ),
        ),
      );
    }

    return Column(
      children: [
        // Main Image - Clean, no border
        Container(
          height: imageHeight,
          decoration: const BoxDecoration(
            color: Colors.white,
          ),
          padding: EdgeInsets.all(isMobile ? 12 : 24),
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

  Widget _buildProductInfo({bool isMobile = false}) {
    final cart = context.watch<CartProvider>();
    final inCart = cart.hasProduct(_product!.id);
    final inStock = _product!.stockQuantity > 0;

    return Container(
      padding: EdgeInsets.all(isMobile ? 16 : 32),
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
              color: inStock ? Colors.green.shade50 : Colors.red.shade50,
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
                    color:
                        inStock ? Colors.green.shade700 : Colors.red.shade700,
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
                            color: _quantity > 1
                                ? Colors.black87
                                : Colors.grey.shade400,
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
                  backgroundColor:
                      inCart ? Colors.green.shade600 : Colors.black,
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
                  onPressed: () => context.go('/carrito'),
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
                  Icon(Icons.cancel_outlined,
                      color: Colors.red.shade700, size: 18),
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
          _buildInfoRow(
              Icons.storefront_outlined, 'Retiro en tienda disponible'),
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
              if (_product!.description != null &&
                  _product!.description!.isNotEmpty) ...[
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
              _buildDetailRow(
                  'Categoría', _product!.categoryName ?? 'Sin categoría'),
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
    // Prefer optimized image for related products (thumbnails)
    final displayImageUrl = product.imageUrlOptimized ?? product.imageUrl;
    final hasImage = displayImageUrl != null && displayImageUrl.isNotEmpty;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          context.go('/productos/${product.id}');
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
                          displayImageUrl,
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
