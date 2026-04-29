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
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/public_store/utils/structured_data.dart';
import 'package:vinabike_erp/shared/widgets/safe_layout_builder.dart';

class ProductDetailPage extends StatefulWidget {
  final String productId;

  const ProductDetailPage({super.key, required this.productId});

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage>
    with AutomaticKeepAliveClientMixin {
  static const _structuredDataScriptId = 'vinabike-product-structured-data';
  static const Color _catalogBlue = Color(0xFF123F68);
  static const Color _logoBlue = Color(0xFF093357);
  static const Color _warmLine = Color(0xFFE8E2D8);
  static const Color _warmSurface = Color(0xFFF7F4EE);
  static const Color _softSurface = Color(0xFFFCFBF8);
  Product? _product;
  List<Product> _relatedProducts = [];
  bool _isLoading = true;
  bool _isLoadingRelated = false;
  int _quantity = 1;
  int _selectedImageIndex = 0;
  int _loadToken = 0;

  // DISABLED: AutomaticKeepAliveClientMixin causes element activation conflicts
  // during edit/preview mode switches. The performance cost of reloading is acceptable.
  @override
  bool get wantKeepAlive => false;

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
      'https://vinabike.cl',
    );

    final normalizedStoreUrl = storeUrl.replaceAll(RegExp(r'/+$'), '');
    final productUrl = '$normalizedStoreUrl/productos/${product.id}';
    final isStockTracked =
        product.productType != ProductType.service && product.trackStock;
    final availability = isStockTracked
        ? (product.stockQuantity > 0
            ? 'https://schema.org/InStock'
            : 'https://schema.org/OutOfStock')
        : 'https://schema.org/InStock';

    final imageList = <String>[];
    if (product.imageUrls.isNotEmpty) {
      imageList.addAll(product.imageUrls);
    } else if (product.imageUrl != null && product.imageUrl!.isNotEmpty) {
      imageList.add(product.imageUrl!);
    }

    final description = (product.description?.trim().isNotEmpty ?? false)
        ? product.description!.trim()
        : 'Encuentra $storeName online: ${product.name}';
    final cleanDescription = _cleanSeoText(description);

    final gtin = (product.gtin?.trim().isNotEmpty ?? false)
        ? product.gtin!.trim()
        : (product.barcode?.trim().isNotEmpty ?? false)
            ? product.barcode!.trim()
            : null;

    final priceString = product.price % 1 == 0
        ? product.price.toStringAsFixed(0)
        : product.price.toStringAsFixed(2);

    final structuredData = <String, dynamic>{
      '@context': 'https://schema.org/',
      '@type': 'Product',
      'name': product.name,
      'description': cleanDescription,
      'sku': product.sku,
      if (gtin != null && gtin.isNotEmpty) 'gtin': gtin,
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

    final resolvedTitle = _cleanSeoText(_applySeoTemplate(
      template: titleTemplate,
      storeName: storeName,
      product: product,
    ).trim());

    final fallbackDescription = (product.description?.trim().isNotEmpty ??
            false)
        ? product.description!.trim()
        : 'Compra ${product.name} online en $storeName. Envíos y retiro en tienda.';

    final resolvedDescription = _applySeoTemplate(
      template: descriptionTemplate,
      storeName: storeName,
      product: product,
      fallbackDescription: fallbackDescription,
    ).trim();

    final cleanResolvedDescription = _cleanSeoText(resolvedDescription);

    final image = (product.imageUrls.isNotEmpty)
        ? product.imageUrls.first
        : (product.imageUrl?.isNotEmpty == true ? product.imageUrl : null);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SeoHelper.updateSeo(
        title: resolvedTitle.isNotEmpty ? resolvedTitle : storeName,
        description: cleanResolvedDescription.isNotEmpty
            ? cleanResolvedDescription
            : null,
        imageUrl: image,
      );
    });
  }

  String _cleanSeoText(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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
    if (_product == null) return;

    final isStockTracked =
        _product!.productType != ProductType.service && _product!.trackStock;
    if (isStockTracked && _product!.stockQuantity < _quantity) {
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

    // Get edit mode for key to prevent element reactivation conflicts
    final editProvider = context.watch<WebsiteEditModeProvider>();
    final modeKey = editProvider.isEditMode
        ? 'edit'
        : (editProvider.isPreviewMode ? 'preview' : 'normal');

    return MediaQueryLayoutBuilder(
      key: ValueKey('product_detail_layout_$modeKey'),
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 768;
        final isTablet = constraints.maxWidth < 1100;
        final horizontalMargin = isMobile ? 16.0 : (isTablet ? 24.0 : 32.0);
        final verticalMargin = isMobile ? 18.0 : 34.0;

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1320),
                  margin: EdgeInsets.fromLTRB(
                    horizontalMargin,
                    verticalMargin,
                    horizontalMargin,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isMobile) _buildBreadcrumb(),
                      if (!isMobile) const SizedBox(height: 26),
                      if (isMobile) ...[
                        _buildImageGallery(isMobile: true),
                        const SizedBox(height: 24),
                        _buildProductInfo(isMobile: true),
                      ] else ...[
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: isTablet ? 6 : 6,
                              child: _buildImageGallery(),
                            ),
                            SizedBox(width: isTablet ? 14 : 18),
                            Expanded(
                              flex: isTablet ? 5 : 5,
                              child: _buildProductInfo(),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SizedBox(height: isMobile ? 48 : 64),
              _buildProductDetails(
                isMobile: isMobile,
                horizontalMargin: horizontalMargin,
              ),
              SizedBox(height: isMobile ? 56 : 80),
              if (_isLoadingRelated || _relatedProducts.isNotEmpty)
                Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 1320),
                    margin: EdgeInsets.symmetric(horizontal: horizontalMargin),
                    child: _isLoadingRelated
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(
                              child: SizedBox(
                                width: 40,
                                height: 40,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          )
                        : _buildRelatedProducts(),
                  ),
                ),
              SizedBox(height: isMobile ? 72 : 88),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBreadcrumb() {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildBreadcrumbLink('Inicio', () => context.go('/')),
        _buildBreadcrumbSeparator(),
        _buildBreadcrumbLink('Productos', () => context.go('/productos')),
        _buildBreadcrumbSeparator(),
        Text(
          _product!.name,
          style: const TextStyle(
            fontFamily: PublicStoreTheme.defaultBodyFont,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: PublicStoreTheme.textMuted,
          ),
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

    final imageHeight = isMobile ? 320.0 : 520.0;

    if (images.isEmpty) {
      return SizedBox(
        height: imageHeight,
        child: Center(
          child: Icon(
            Icons.pedal_bike_outlined,
            size: isMobile ? 60 : 100,
            color: Colors.grey,
          ),
        ),
      );
    }

    final mainStage = SizedBox(
      height: imageHeight,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 0,
          vertical: isMobile ? 0 : 6,
        ),
        child: Transform.translate(
          offset: Offset(isMobile ? 0 : 44, 0),
          child: Image.network(
            images[_selectedImageIndex],
            alignment: Alignment.center,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) {
              return const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 64,
                  color: PublicStoreTheme.textMuted,
                ),
              );
            },
          ),
        ),
      ),
    );

    if (!isMobile && images.length > 1) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            height: imageHeight,
            child: ListView.separated(
              itemCount: images.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final isSelected = index == _selectedImageIndex;
                return _buildThumbnail(
                  imageUrl: images[index],
                  isSelected: isSelected,
                  size: 82,
                  onTap: () => setState(() => _selectedImageIndex = index),
                );
              },
            ),
          ),
          const SizedBox(width: 20),
          Expanded(child: mainStage),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        mainStage,
        if (images.length > 1) ...[
          const SizedBox(height: 18),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: images.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final isSelected = index == _selectedImageIndex;
                return _buildThumbnail(
                  imageUrl: images[index],
                  isSelected: isSelected,
                  size: 72,
                  onTap: () => setState(() => _selectedImageIndex = index),
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
    final isStockTracked = _product!.tracksInventory;
    final inStock = isStockTracked ? _product!.stockQuantity > 0 : true;
    final leadText = _cleanSeoText(
      _product!.websiteDescription?.trim().isNotEmpty == true
          ? _product!.websiteDescription!
          : (_product!.description ?? ''),
    );
    final canIncrease = !isStockTracked || _quantity < _product!.stockQuantity;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (_product!.brand?.trim().isNotEmpty ?? false)
              _buildMetaPill(
                _product!.brand!.trim().toUpperCase(),
                foreground: _catalogBlue,
                background: _catalogBlue.withValues(alpha: 0.08),
              ),
            _buildMetaPill(
              (_product!.categoryName ?? 'PRODUCTO').toUpperCase(),
              foreground: PublicStoreTheme.textSecondary,
              background: _softSurface,
            ),
          ],
        ),
        SizedBox(height: isMobile ? 14 : 18),
        Text(
          _product!.name.toUpperCase(),
          style: TextStyle(
            fontFamily: PublicStoreTheme.defaultHeadingFont,
            fontSize: isMobile ? 34 : 40,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
            height: 1.06,
            letterSpacing: 0.2,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            if (_product!.sku.isNotEmpty)
              _buildMetaPill(
                'SKU ${_product!.sku}',
                foreground: PublicStoreTheme.textSecondary,
                background: _softSurface,
              ),
            _buildMetaPill(
              inStock ? 'EN STOCK' : 'AGOTADO',
              foreground: inStock ? _catalogBlue : PublicStoreTheme.error,
              background: (inStock ? _catalogBlue : PublicStoreTheme.error)
                  .withValues(alpha: 0.08),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          ChileanUtils.formatCurrency(_product!.price),
          style: TextStyle(
            fontFamily: PublicStoreTheme.defaultHeadingFont,
            fontSize: isMobile ? 42 : 46,
            fontWeight: FontWeight.w700,
            color: _catalogBlue,
            height: 0.95,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Precio final con IVA incluido',
          style: TextStyle(
            fontFamily: PublicStoreTheme.defaultBodyFont,
            fontSize: 13,
            color: PublicStoreTheme.textSecondary,
          ),
        ),
        if (leadText.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            leadText,
            style: const TextStyle(
              fontFamily: PublicStoreTheme.defaultBodyFont,
              fontSize: 13,
              color: Color(0xFF57534E),
              height: 1.55,
            ),
            maxLines: isMobile ? 4 : 5,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 16 : 16,
            vertical: isMobile ? 14 : 14,
          ),
          decoration: BoxDecoration(
            color: _warmSurface.withValues(alpha: 0.72),
            border: const Border(
              top: BorderSide(color: _warmLine),
              bottom: BorderSide(color: _warmLine),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(top: 5),
                    decoration: BoxDecoration(
                      color: inStock ? _catalogBlue : PublicStoreTheme.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          inStock
                              ? 'Disponible para compra'
                              : 'Temporalmente sin stock',
                          style: const TextStyle(
                            fontFamily: PublicStoreTheme.defaultBodyFont,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isStockTracked
                              ? (inStock
                                  ? '${_product!.stockQuantity} unidad${_product!.stockQuantity == 1 ? '' : 'es'} disponibles para despacho o retiro.'
                                  : 'Podemos ayudarte a revisar reposición o alternativas similares.')
                              : 'Producto disponible por compra directa o coordinación con tienda.',
                          style: const TextStyle(
                            fontFamily: PublicStoreTheme.defaultBodyFont,
                            fontSize: 13,
                            color: PublicStoreTheme.textSecondary,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (inStock) ...[
                if (isMobile) ...[
                  _buildQuantitySelector(
                    canIncrease: canIncrease,
                    expand: true,
                  ),
                  const SizedBox(height: 14),
                  _buildCartAction(
                    inCart: inCart,
                    width: double.infinity,
                  ),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildQuantitySelector(canIncrease: canIncrease),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildCartAction(
                          inCart: inCart,
                          width: double.infinity,
                        ),
                      ),
                    ],
                  ),
                if (inCart) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(
                        Icons.shopping_bag_outlined,
                        size: 16,
                        color: _catalogBlue,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Ya tienes este producto en el carrito.',
                          style: TextStyle(
                            fontFamily: PublicStoreTheme.defaultBodyFont,
                            fontSize: 13,
                            color: PublicStoreTheme.textSecondary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => context.go('/carrito'),
                        style: TextButton.styleFrom(
                          foregroundColor: _catalogBlue,
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Ver carrito',
                          style: TextStyle(
                            fontFamily: PublicStoreTheme.defaultBodyFont,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ] else
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'NO DISPONIBLE',
                    style: TextStyle(
                      fontFamily: PublicStoreTheme.defaultBodyFont,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      color: PublicStoreTheme.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Container(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: _warmLine),
            ),
          ),
          child: Column(
            children: [
              _buildInfoTile(
                icon: Icons.local_shipping_outlined,
                title: 'Despacho a todo Chile',
                subtitle: 'Coordinamos envío o retiro según tu compra.',
              ),
              _buildInfoTile(
                icon: Icons.storefront_outlined,
                title: 'Retiro en tienda',
                subtitle: 'Disponible en Alvarez 32, Local 17, Viña del Mar.',
              ),
              _buildInfoTile(
                icon: Icons.verified_outlined,
                title: 'Respaldo Vinabike',
                subtitle: 'Atención postventa y garantía según producto.',
                isLast: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProductDetails({
    required bool isMobile,
    required double horizontalMargin,
  }) {
    final description = _cleanSeoText(
      _product!.websiteDescription?.trim().isNotEmpty == true
          ? _product!.websiteDescription!
          : (_product!.description ?? ''),
    );
    final detailRows = <MapEntry<String, String>>[
      if (_product!.sku.isNotEmpty) MapEntry('SKU', _product!.sku),
      MapEntry('Categoría', _product!.categoryName ?? 'Sin categoría'),
      if (_product!.brand?.trim().isNotEmpty ?? false)
        MapEntry('Marca', _product!.brand!.trim()),
      if (_product!.model?.trim().isNotEmpty ?? false)
        MapEntry('Modelo', _product!.model!.trim()),
      if (_product!.weight > 0)
        MapEntry('Peso', '${_product!.weight.toStringAsFixed(2)} kg'),
      if (_product!.manufacturer?.trim().isNotEmpty ?? false)
        MapEntry('Fabricante', _product!.manufacturer!.trim()),
      if (_product!.gtin?.trim().isNotEmpty ?? false)
        MapEntry('GTIN', _product!.gtin!.trim()),
      ..._product!.specifications.entries
          .where((entry) =>
              entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty)
          .map((entry) => MapEntry(entry.key.trim(), entry.value.trim())),
    ];

    return Container(
      width: double.infinity,
      color: _logoBlue,
      padding: EdgeInsets.symmetric(vertical: isMobile ? 42 : 54),
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1320),
          margin: EdgeInsets.symmetric(horizontal: horizontalMargin),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeading(
                'Detalles del producto',
                foreground: Colors.white,
                lineColor: Colors.white,
              ),
              SizedBox(height: isMobile ? 28 : 34),
              ConstrainedBox(
                constraints:
                    BoxConstraints(maxWidth: isMobile ? double.infinity : 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DESCRIPCIÓN',
                      style: TextStyle(
                        fontFamily: PublicStoreTheme.defaultBodyFont,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.74),
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      description.isNotEmpty
                          ? description
                          : 'Estamos actualizando la descripción extendida de este producto.',
                      style: TextStyle(
                        fontFamily: PublicStoreTheme.defaultBodyFont,
                        fontSize: 15,
                        color: Colors.white.withValues(alpha: 0.96),
                        height: 1.7,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: isMobile ? 28 : 32),
              Container(
                width: double.infinity,
                height: 1,
                color: Colors.white.withValues(alpha: 0.16),
              ),
              SizedBox(height: isMobile ? 22 : 26),
              Text(
                (_product!.specifications.isNotEmpty
                        ? 'Ficha técnica'
                        : 'Ficha rápida')
                    .toUpperCase(),
                style: TextStyle(
                  fontFamily: PublicStoreTheme.defaultBodyFont,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.74),
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, specConstraints) {
                  final itemWidth = isMobile
                      ? specConstraints.maxWidth
                      : specConstraints.maxWidth >= 1120
                          ? (specConstraints.maxWidth - 48) / 3
                          : (specConstraints.maxWidth - 24) / 2;

                  return Wrap(
                    spacing: 24,
                    runSpacing: 18,
                    children: [
                      for (final entry in detailRows)
                        SizedBox(
                          width: itemWidth,
                          child: _buildDetailBandItem(
                            label: entry.key,
                            value: entry.value,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailBandItem({
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.only(top: 14, bottom: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.16),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontFamily: PublicStoreTheme.defaultBodyFont,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.70),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontFamily: PublicStoreTheme.defaultBodyFont,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.97),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRelatedProducts() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 1180
            ? 4
            : constraints.maxWidth >= 820
                ? 3
                : 2;
        final spacing = constraints.maxWidth >= 1180 ? 28.0 : 20.0;
        final aspectRatio = constraints.maxWidth >= 1180
            ? 0.73
            : constraints.maxWidth >= 820
                ? 0.71
                : 0.66;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeading('Productos relacionados'),
            const SizedBox(height: 28),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                childAspectRatio: aspectRatio,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing + 4,
              ),
              itemCount: _relatedProducts.length,
              itemBuilder: (context, index) {
                return _buildRelatedProductCard(_relatedProducts[index]);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildRelatedProductCard(Product product) {
    final brand = product.brand?.trim();
    final hasBrand = brand != null && brand.isNotEmpty;
    final displayImageUrl = product.imageUrlOptimized ?? product.imageUrl;
    final hasImage = displayImageUrl != null && displayImageUrl.isNotEmpty;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          context.go('/productos/${product.id}');
        },
        child: Container(
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      color: Colors.white,
                      padding: EdgeInsets.fromLTRB(
                        12,
                        10,
                        12,
                        hasBrand ? 28 : 10,
                      ),
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
                    if (hasBrand)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 6,
                        child: Text(
                          brand.toUpperCase(),
                          style: TextStyle(
                            fontFamily: PublicStoreTheme.defaultBodyFont,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade500,
                            letterSpacing: 0.45,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                height: 88,
                child: Container(
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: _warmLine),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name.toUpperCase(),
                        style: const TextStyle(
                          fontFamily: PublicStoreTheme.defaultHeadingFont,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                          height: 1.3,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ChileanUtils.formatCurrency(product.price),
                        style: const TextStyle(
                          fontFamily: PublicStoreTheme.defaultBodyFont,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
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

  Widget _buildBreadcrumbLink(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: PublicStoreTheme.defaultBodyFont,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: _catalogBlue,
        ),
      ),
    );
  }

  Widget _buildBreadcrumbSeparator() {
    return const Text(
      '/',
      style: TextStyle(
        fontFamily: PublicStoreTheme.defaultBodyFont,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: PublicStoreTheme.textMuted,
      ),
    );
  }

  Widget _buildThumbnail({
    required String imageUrl,
    required bool isSelected,
    required double size,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color:
              isSelected ? _catalogBlue.withValues(alpha: 0.04) : Colors.white,
          border: Border(
            bottom: BorderSide(
              color: isSelected ? _catalogBlue : _warmLine,
              width: isSelected ? 2 : 1,
            ),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 10),
        child: Image.network(
          imageUrl,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return const Icon(
              Icons.broken_image_outlined,
              size: 20,
              color: PublicStoreTheme.textMuted,
            );
          },
        ),
      ),
    );
  }

  Widget _buildMetaPill(
    String label, {
    required Color foreground,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: PublicStoreTheme.defaultBodyFont,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: foreground,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildQuantitySelector({
    required bool canIncrease,
    bool expand = false,
  }) {
    return Container(
      width: expand ? double.infinity : 152,
      constraints: const BoxConstraints(minWidth: 152),
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _warmLine),
      ),
      child: Row(
        children: [
          _buildQuantityButton(
            icon: Icons.remove,
            enabled: _quantity > 1,
            onTap: () => setState(() => _quantity--),
          ),
          Expanded(
            child: Container(
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                border: Border.symmetric(
                  vertical: BorderSide(color: _warmLine),
                ),
              ),
              child: Text(
                '$_quantity',
                style: const TextStyle(
                  fontFamily: PublicStoreTheme.defaultBodyFont,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
          _buildQuantityButton(
            icon: Icons.add,
            enabled: canIncrease,
            onTap: () => setState(() => _quantity++),
          ),
        ],
      ),
    );
  }

  Widget _buildQuantityButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: 44,
        height: 50,
        child: Icon(
          icon,
          size: 16,
          color: enabled ? Colors.black87 : PublicStoreTheme.textMuted,
        ),
      ),
    );
  }

  Widget _buildCartAction({
    required bool inCart,
    required double width,
  }) {
    return SizedBox(
      width: width,
      height: 50,
      child: FilledButton.icon(
        onPressed: _addToCart,
        style: FilledButton.styleFrom(
          backgroundColor: _catalogBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        icon: const Icon(Icons.shopping_bag_outlined, size: 16),
        label: Text(
          inCart ? 'AÑADIR OTRA UNIDAD' : 'AGREGAR AL CARRITO',
          style: const TextStyle(
            fontFamily: PublicStoreTheme.defaultBodyFont,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.9,
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String subtitle,
    bool isLast = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isLast ? Colors.transparent : _warmLine,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(
              Icons.circle,
              size: 8,
              color: _catalogBlue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: PublicStoreTheme.defaultBodyFont,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontFamily: PublicStoreTheme.defaultBodyFont,
                    fontSize: 13,
                    color: PublicStoreTheme.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          Icon(icon, size: 18, color: PublicStoreTheme.textSecondary),
        ],
      ),
    );
  }

  Widget _buildSectionHeading(
    String title, {
    Color foreground = Colors.black,
    Color lineColor = Colors.black,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontFamily: PublicStoreTheme.defaultHeadingFont,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: foreground,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: 72,
          height: 2,
          color: lineColor,
        ),
      ],
    );
  }
}
