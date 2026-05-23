import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/public_store_theme.dart';
import '../providers/cart_provider.dart';
import '../providers/public_store_tenant_provider.dart';
import '../services/public_inventory_service.dart';
import '../widgets/full_page_loading.dart';
import '../../shared/models/product.dart';
import '../../shared/models/public_product_visibility_policy.dart';
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
  bool _isLoadingTechnicalSpecs = false;
  int _selectedDetailsTab = 0;
  int _quantity = 1;
  int _selectedImageIndex = 0;
  int _loadToken = 0;
  List<_PublicProductTechnicalSpec> _technicalSpecs = const [];
  OverlayEntry? _productFeedbackOverlay;
  Timer? _productFeedbackTimer;
  Timer? _productFeedbackRemovalTimer;
  ValueNotifier<bool>? _productFeedbackVisible;

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
      _technicalSpecs = const [];
      _isLoadingTechnicalSpecs = false;
      _selectedDetailsTab = 0;
      _quantity = 1;
      _selectedImageIndex = 0;
      _loadProduct();
    }
  }

  @override
  void dispose() {
    _hideProductFeedbackBanner(animated: false);
    removeStructuredDataScript(_structuredDataScriptId);
    super.dispose();
  }

  Future<void> _loadProduct() async {
    final token = ++_loadToken;
    setState(() {
      _isLoading = true;
      _isLoadingRelated = false;
      _isLoadingTechnicalSpecs = false;
      _relatedProducts = [];
      _technicalSpecs = const [];
    });

    try {
      final inventoryService = context.read<PublicInventoryService>();
      final tenantProvider = context.read<PublicStoreTenantProvider>();
      final tenantId = tenantProvider.tenantId;

      if (tenantId == null) {
        debugPrint('❌ [ProductDetail] No tenant ID available');
        return;
      }
      final visibilityPolicy = _readVisibilityPolicy();

      // Load the product - support both UUID and SKU-based lookups
      // SKU format: "sku:S56467" (from legacy /shop/ URLs)
      final Product? loadedProduct;
      if (widget.productId.startsWith('sku:')) {
        final sku = widget.productId.substring(4); // Remove "sku:" prefix
        debugPrint('🔍 [ProductDetail] Looking up product by SKU: $sku');
        loadedProduct = await inventoryService.getProductBySku(
          sku: sku,
          tenantId: tenantId,
          policy: visibilityPolicy,
        );
      } else {
        loadedProduct = await inventoryService.getProductById(
          productId: widget.productId,
          tenantId: tenantId,
          policy: visibilityPolicy,
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
        _loadTechnicalSpecs(
          token: token,
          tenantId: tenantId,
          productId: _product!.id,
        );
        _loadRelatedProducts(
          token: token,
          inventoryService: inventoryService,
          tenantId: tenantId,
          product: _product!,
          visibilityPolicy: visibilityPolicy,
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

  Future<void> _loadTechnicalSpecs({
    required int token,
    required String tenantId,
    required String productId,
  }) async {
    if (productId.isEmpty) return;
    setState(() => _isLoadingTechnicalSpecs = true);
    try {
      final response = await Supabase.instance.client.rpc(
        'get_public_product_technical_specs',
        params: {
          'p_tenant_id': tenantId,
          'p_product_id': productId,
        },
      );
      if (!mounted || token != _loadToken) return;
      final specs = (response as List)
          .map((row) => _PublicProductTechnicalSpec.fromJson(
                Map<String, dynamic>.from(row as Map),
              ))
          .where((spec) => spec.displayValue.trim().isNotEmpty)
          .toList(growable: false);
      setState(() {
        _technicalSpecs = specs;
        _isLoadingTechnicalSpecs = false;
      });
    } catch (e) {
      debugPrint('[ProductDetailPage] Error loading technical specs: $e');
      if (!mounted || token != _loadToken) return;
      setState(() {
        _technicalSpecs = const [];
        _isLoadingTechnicalSpecs = false;
      });
    }
  }

  Future<void> _loadRelatedProducts({
    required int token,
    required PublicInventoryService inventoryService,
    required String tenantId,
    required Product product,
    required PublicProductVisibilityPolicy? visibilityPolicy,
  }) async {
    final categoryId = product.categoryId;
    if (categoryId == null || categoryId.isEmpty) return;

    setState(() => _isLoadingRelated = true);
    try {
      final allProducts = await inventoryService.getProductsForTenant(
        tenantId: tenantId,
        categoryId: categoryId,
        policy: visibilityPolicy,
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

  PublicProductVisibilityPolicy? _readVisibilityPolicy() {
    try {
      final service = context.read<WebsiteService>();
      if (!PublicProductVisibilityPolicy.hasAnySetting(service.settings)) {
        return null;
      }
      return PublicProductVisibilityPolicy.fromSettings(service.settings);
    } catch (_) {
      return null;
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
      _showProductFeedbackBanner(
        message: 'Stock insuficiente',
        backgroundColor: PublicStoreTheme.error,
      );
      return;
    }

    final cart = context.read<CartProvider>();
    cart.addProduct(_product!, quantity: _quantity);

    _showProductFeedbackBanner(
      message: '${_product!.name} agregado al carrito',
      backgroundColor: _logoBlue,
      actionLabel: 'Ver carrito',
      onActionPressed: () => context.go('/carrito'),
    );

    setState(() => _quantity = 1);
  }

  void _showProductFeedbackBanner({
    required String message,
    required Color backgroundColor,
    String? actionLabel,
    VoidCallback? onActionPressed,
  }) {
    final mediaQuery = MediaQuery.of(context);
    final screenWidth = mediaQuery.size.width;
    const bannerMaxWidth = 560.0;
    final horizontalMargin = screenWidth > bannerMaxWidth + 32
        ? (screenWidth - bannerMaxWidth) / 2
        : 16.0;
    final overlayState = Overlay.maybeOf(context, rootOverlay: true);

    if (overlayState == null) return;

    _hideProductFeedbackBanner(animated: false);

    final visible = ValueNotifier<bool>(false);

    final overlay = OverlayEntry(
      builder: (overlayContext) => Positioned(
        left: horizontalMargin,
        right: horizontalMargin,
        bottom: 20 + mediaQuery.padding.bottom,
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (context, isVisible, child) {
                return AnimatedSlide(
                  offset: isVisible ? Offset.zero : const Offset(0, 0.18),
                  duration: const Duration(milliseconds: 280),
                  curve: isVisible ? Curves.easeOutCubic : Curves.easeInCubic,
                  child: AnimatedOpacity(
                    opacity: isVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: isVisible ? Curves.easeOutCubic : Curves.easeInCubic,
                    child: child,
                  ),
                );
              },
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: bannerMaxWidth),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.16),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Expanded(
                          child: Text(
                            message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: PublicStoreTheme.defaultBodyFont,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        if (actionLabel != null && onActionPressed != null) ...[
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: () {
                              _hideProductFeedbackBanner(animated: false);
                              onActionPressed();
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              textStyle: const TextStyle(
                                fontFamily: PublicStoreTheme.defaultBodyFont,
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            child: Text(actionLabel),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlayState.insert(overlay);
    _productFeedbackOverlay = overlay;
    _productFeedbackVisible = visible;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_productFeedbackVisible == visible) {
        visible.value = true;
      }
    });
    _productFeedbackTimer = Timer(
      const Duration(milliseconds: 2600),
      () => _hideProductFeedbackBanner(),
    );
  }

  void _hideProductFeedbackBanner({bool animated = true}) {
    _productFeedbackTimer?.cancel();
    _productFeedbackTimer = null;
    _productFeedbackRemovalTimer?.cancel();
    _productFeedbackRemovalTimer = null;

    final overlay = _productFeedbackOverlay;
    final visible = _productFeedbackVisible;

    if (overlay == null) {
      visible?.dispose();
      _productFeedbackVisible = null;
      return;
    }

    if (!animated || visible == null) {
      overlay.remove();
      if (identical(_productFeedbackOverlay, overlay)) {
        _productFeedbackOverlay = null;
        _productFeedbackVisible = null;
      }
      visible?.dispose();
      return;
    }

    visible.value = false;
    _productFeedbackRemovalTimer = Timer(
      const Duration(milliseconds: 280),
      () {
        overlay.remove();
        if (identical(_productFeedbackOverlay, overlay)) {
          _productFeedbackOverlay = null;
          _productFeedbackVisible = null;
        }
        visible.dispose();
      },
    );
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
                        LayoutBuilder(
                          builder: (context, rowConstraints) {
                            final rowWidth = rowConstraints.maxWidth.isFinite
                                ? rowConstraints.maxWidth
                                : constraints.maxWidth - (horizontalMargin * 2);
                            final columnGap = isTablet ? 24.0 : 34.0;
                            final columnWidth =
                                ((rowWidth - columnGap) / 2).floorToDouble();

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: columnWidth,
                                  child: _buildImageGallery(),
                                ),
                                SizedBox(width: columnGap),
                                SizedBox(
                                  width: columnWidth,
                                  child: _buildProductInfo(),
                                ),
                              ],
                            );
                          },
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
    final isService = _product?.productType == ProductType.service;
    final catalogLabel = isService ? 'Servicios' : 'Productos';
    final catalogHref = isService ? '/servicios' : '/productos';

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildBreadcrumbLink('Inicio', () => context.go('/')),
        _buildBreadcrumbSeparator(),
        _buildBreadcrumbLink(catalogLabel, () => context.go(catalogHref)),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final galleryWidth =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? constraints.maxWidth
                : MediaQuery.sizeOf(context).width;
        final imageHeight = _productImageStageHeight(
          galleryWidth,
          isMobile: isMobile,
        );

        if (images.isEmpty) {
          return _buildProductImageStage(
            height: imageHeight,
            isMobile: isMobile,
            child: Center(
              child: Icon(
                Icons.pedal_bike_outlined,
                size: isMobile ? 60 : 100,
                color: Colors.grey,
              ),
            ),
          );
        }

        final mainStage = _buildProductImageStage(
          height: imageHeight,
          isMobile: isMobile,
          child: Image.network(
            images[_selectedImageIndex],
            alignment: Alignment.center,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
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
      },
    );
  }

  double _productImageStageHeight(
    double galleryWidth, {
    required bool isMobile,
  }) {
    final rawHeight = galleryWidth * (isMobile ? 0.88 : 0.82);
    return rawHeight
        .clamp(isMobile ? 300.0 : 400.0, isMobile ? 420.0 : 540.0)
        .toDouble();
  }

  Widget _buildProductImageStage({
    required double height,
    required bool isMobile,
    required Widget child,
  }) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Container(
        color: Colors.white,
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 2 : 4,
          vertical: isMobile ? 2 : 4,
        ),
        child: Center(
          child: SizedBox.expand(child: child),
        ),
      ),
    );
  }

  Widget _buildProductInfo({bool isMobile = false}) {
    final cart = context.watch<CartProvider>();
    final inCart = cart.hasProduct(_product!.id);
    final isStockTracked = _product!.tracksInventory;
    final inStock = isStockTracked ? _product!.stockQuantity > 0 : true;
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

    return Container(
      width: double.infinity,
      color: Colors.white,
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
                foreground: _catalogBlue,
                lineColor: _catalogBlue,
              ),
              SizedBox(height: isMobile ? 22 : 28),
              _buildDetailsTabs(),
              SizedBox(height: isMobile ? 24 : 30),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _selectedDetailsTab == 0
                    ? _buildDescriptionTab(description, isMobile: isMobile)
                    : _buildTechnicalFichaTab(isMobile: isMobile),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailsTabs() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: _warmLine),
        ),
      ),
      child: Row(
        children: [
          _buildDetailsTabButton('Descripción', 0),
          const SizedBox(width: 22),
          _buildDetailsTabButton('Ficha técnica', 1),
        ],
      ),
    );
  }

  Widget _buildDetailsTabButton(String label, int index) {
    final selected = _selectedDetailsTab == index;
    return InkWell(
      onTap: () => setState(() => _selectedDetailsTab = index),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? _catalogBlue : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontFamily: PublicStoreTheme.defaultBodyFont,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: selected ? _catalogBlue : PublicStoreTheme.textSecondary,
                letterSpacing: 0.9,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDescriptionTab(String description, {required bool isMobile}) {
    return ConstrainedBox(
      key: const ValueKey('product_description_tab'),
      constraints: BoxConstraints(maxWidth: isMobile ? double.infinity : 820),
      child: Text(
        description.isNotEmpty
            ? description
            : 'Estamos actualizando la descripción extendida de este producto.',
        style: const TextStyle(
          fontFamily: PublicStoreTheme.defaultBodyFont,
          fontSize: 15,
          color: PublicStoreTheme.textPrimary,
          height: 1.7,
        ),
      ),
    );
  }

  Widget _buildTechnicalFichaTab({required bool isMobile}) {
    if (_isLoadingTechnicalSpecs) {
      return const SizedBox(
        key: ValueKey('product_technical_specs_loading'),
        height: 96,
        child: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _catalogBlue,
            ),
          ),
        ),
      );
    }

    final groups = _buildTechnicalFichaGroups();
    if (groups.isEmpty) {
      return const Text(
        key: ValueKey('product_technical_specs_empty'),
        'La ficha técnica de este producto está en actualización.',
        style: TextStyle(
          fontFamily: PublicStoreTheme.defaultBodyFont,
          fontSize: 15,
          color: PublicStoreTheme.textSecondary,
          height: 1.6,
        ),
      );
    }

    return Column(
      key: const ValueKey('product_technical_specs_tab'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < groups.length; index++) ...[
          if (index > 0) SizedBox(height: isMobile ? 26 : 30),
          _buildTechnicalFichaGroup(groups[index], isMobile: isMobile),
        ],
      ],
    );
  }

  Widget _buildTechnicalFichaGroup(
    _TechnicalFichaGroup group, {
    required bool isMobile,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          group.title.toUpperCase(),
          style: const TextStyle(
            fontFamily: PublicStoreTheme.defaultBodyFont,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: _catalogBlue,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final itemWidth = isMobile
                ? constraints.maxWidth
                : constraints.maxWidth >= 1120
                    ? (constraints.maxWidth - 48) / 3
                    : (constraints.maxWidth - 24) / 2;
            return Wrap(
              spacing: 24,
              runSpacing: 14,
              children: [
                for (final item in group.items)
                  SizedBox(
                    width: itemWidth,
                    child: _buildDetailBandItem(
                      label: item.key,
                      value: item.value,
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  List<_TechnicalFichaGroup> _buildTechnicalFichaGroups() {
    final groups = <String, List<MapEntry<String, String>>>{};
    final seenLabels = <String>{};

    void addItem(String section, String label, String value) {
      final cleanLabel = label.trim();
      final cleanValue = value.trim();
      if (cleanLabel.isEmpty || cleanValue.isEmpty) return;
      final seenKey = _normalizeTechnicalToken(cleanLabel);
      if (seenLabels.contains(seenKey)) return;
      seenLabels.add(seenKey);
      groups.putIfAbsent(section, () => <MapEntry<String, String>>[]).add(
            MapEntry(cleanLabel, cleanValue),
          );
    }

    addItem('Identificación', 'SKU', _product!.sku);
    addItem('Identificación', 'Categoría', _product!.categoryName ?? '');
    addItem('Identificación', 'Marca', _product!.brand ?? '');
    addItem('Identificación', 'Modelo', _product!.model ?? '');
    addItem('Identificación', 'Fabricante', _product!.manufacturer ?? '');
    addItem(
        'Identificación', 'Código fabricante', _product!.manufacturerSku ?? '');
    addItem('Identificación', 'GTIN', _product!.gtin ?? '');

    addItem('Características', 'Color', _product!.color ?? '');
    addItem('Características', 'Talla / medida', _product!.size ?? '');
    addItem('Características', 'Material', _product!.material ?? '');
    if (_product!.weight > 0) {
      addItem('Características', 'Peso',
          '${_product!.weight.toStringAsFixed(2)} kg');
    }

    for (final spec in _technicalSpecs) {
      addItem(
        _sectionTitleForTechnicalSpec(spec.sectionKey),
        _labelForTechnicalSpec(spec.specKey, spec.specLabel),
        _valueForTechnicalSpec(spec),
      );
    }

    for (final entry in _product!.specifications.entries) {
      addItem('Especificaciones', entry.key, entry.value);
    }

    return groups.entries
        .where((entry) => entry.value.isNotEmpty)
        .map((entry) => _TechnicalFichaGroup(entry.key, entry.value))
        .toList(growable: false);
  }

  String _sectionTitleForTechnicalSpec(String sectionKey) {
    switch (_normalizeTechnicalToken(sectionKey)) {
      case 'identification':
      case 'identificacion':
      case 'general':
        return 'Características';
      case 'compatibility':
      case 'compatibilidad':
        return 'Compatibilidad';
      case 'drivetrain':
      case 'transmission':
      case 'transmision':
        return 'Transmisión';
      case 'brake':
      case 'brakes':
      case 'frenos':
        return 'Frenos';
      case 'wheel':
      case 'wheels':
      case 'ruedas':
        return 'Ruedas';
      case 'hub':
      case 'hubs':
      case 'mazas':
        return 'Mazas';
      case 'rim':
      case 'rims':
      case 'llantas':
        return 'Llantas';
      case 'tire':
      case 'tires':
      case 'neumaticos':
        return 'Neumáticos';
      case 'bottombracket':
      case 'bottom_bracket':
      case 'pedalier':
        return 'Pedalier';
      case 'construction':
      case 'construccion':
        return 'Construcción';
      case 'dimensions':
      case 'medidas':
        return 'Medidas';
      default:
        return _titleCaseTechnical(sectionKey.replaceAll('_', ' '));
    }
  }

  String _labelForTechnicalSpec(String key, String label) {
    final normalizedKey = _normalizeTechnicalToken(key);
    const labelByKey = <String, String>{
      'wheelsize': 'Medida de rueda',
      'wheel_size': 'Medida de rueda',
      'braketype': 'Tipo de freno',
      'brake_type': 'Tipo de freno',
      'rimbrakefamily': 'Familia de freno de llanta',
      'rim_brake_family': 'Familia de freno de llanta',
      'rotorsize': 'Diámetro de rotor',
      'rotor_size': 'Diámetro de rotor',
      'freehubtype': 'Núcleo / driver trasero',
      'freehub_type': 'Núcleo / driver trasero',
      'drivetrainspeeds': 'Velocidades',
      'drivetrain_speeds': 'Velocidades',
      'drivetrainconfig': 'Configuración de transmisión',
      'drivetrain_config': 'Configuración de transmisión',
      'frontchainringcount': 'Platos delanteros',
      'front_chainring_count': 'Platos delanteros',
      'rearcogcount': 'Coronas traseras',
      'rear_cog_count': 'Coronas traseras',
      'valvetype': 'Tipo de válvula',
      'valve_type': 'Tipo de válvula',
      'spokeholes': 'Perforaciones de rayos',
      'spoke_holes': 'Perforaciones de rayos',
      'hubspacingmm': 'Espaciado de maza',
      'hub_spacing_mm': 'Espaciado de maza',
      'bottombracketfamily': 'Familia de motor / pedalier',
      'bottom_bracket_family': 'Familia de motor / pedalier',
      'bbshellwidthmm': 'Ancho de caja',
      'bb_shell_width_mm': 'Ancho de caja',
      'bbshelldiametermm': 'Diámetro de caja',
      'bb_shell_diameter_mm': 'Diámetro de caja',
      'spindleinterface': 'Interfaz de eje',
      'spindle_interface': 'Interfaz de eje',
      'chainouterwidthmm': 'Ancho externo de cadena',
      'chain_outer_width_mm': 'Ancho externo de cadena',
      'largestcogteeth': 'Corona mayor',
      'largest_cog_teeth': 'Corona mayor',
      'smallestcogteeth': 'Corona menor',
      'smallest_cog_teeth': 'Corona menor',
      'riminternalwidthmm': 'Ancho interno de llanta',
      'rim_internal_width_mm': 'Ancho interno de llanta',
      'rimexternalwidthmm': 'Ancho externo de llanta',
      'rim_external_width_mm': 'Ancho externo de llanta',
      'erdmm': 'ERD',
      'erd_mm': 'ERD',
      'etrto': 'ETRTO',
    };
    final mapped = labelByKey[normalizedKey] ?? labelByKey[key];
    if (mapped != null) return mapped;

    final cleanLabel = label.trim();
    if (cleanLabel.isNotEmpty && !cleanLabel.contains('_')) {
      return cleanLabel;
    }
    return _titleCaseTechnical(key.replaceAll('_', ' '));
  }

  String _valueForTechnicalSpec(_PublicProductTechnicalSpec spec) {
    final raw = spec.displayValue.trim();
    if (raw.isEmpty) return raw;
    final values = raw
        .split(',')
        .map((value) => _spanishTechnicalValue(spec.specKey, value.trim()))
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
    var display = values.isEmpty ? raw : values.join(', ');
    final unit = spec.unit?.trim();
    if (unit != null &&
        unit.isNotEmpty &&
        !_valueAlreadyHasUnit(display, unit)) {
      display = '$display $unit';
    }
    return display;
  }

  bool _valueAlreadyHasUnit(String value, String unit) {
    return RegExp('(^|\\s)${RegExp.escape(unit)}\\.?\$', caseSensitive: false)
        .hasMatch(value.trim());
  }

  String _spanishTechnicalValue(String key, String value) {
    final normalized = _normalizeTechnicalToken(value);
    const valueMap = <String, String>{
      'true': 'Sí',
      'false': 'No',
      'yes': 'Sí',
      'no': 'No',
      'unknown': 'No confirmado',
      'disc': 'Disco',
      'dischydraulic': 'Disco hidráulico',
      'disc_hydraulic': 'Disco hidráulico',
      'discmechanical': 'Disco mecánico',
      'disc_mechanical': 'Disco mecánico',
      'rim': 'Freno de llanta',
      'vbrake': 'V-Brake',
      'v_brake': 'V-Brake',
      'cantilever': 'Cantilever',
      'roadcaliper': 'Caliper de ruta',
      'road_caliper': 'Caliper de ruta',
      'rollerbrake': 'Roller brake',
      'roller_brake': 'Roller brake',
      'drumbrake': 'Freno de tambor',
      'drum_brake': 'Freno de tambor',
      'coasterbrake': 'Contrapedal',
      'coaster_brake': 'Contrapedal',
      'presta': 'Presta',
      'schrader': 'Schrader / americana',
      'dunlop': 'Dunlop',
      'shimanohg': 'Shimano HG',
      'shimano_hg': 'Shimano HG',
      'shimanohgroad11': 'Shimano HG Road 11',
      'shimano_hg_road_11': 'Shimano HG Road 11',
      'microspline': 'Micro Spline',
      'micro_spline': 'Micro Spline',
      'sramxd': 'SRAM XD',
      'sram_xd': 'SRAM XD',
      'sramxdr': 'SRAM XDR',
      'sram_xdr': 'SRAM XDR',
      'campagnolo': 'Campagnolo',
      'campagnolon3w': 'Campagnolo N3W',
      'campagnolo_n3w': 'Campagnolo N3W',
      'threadedfreewheel': 'Rueda libre roscada',
      'threaded_freewheel': 'Rueda libre roscada',
      'fixedthreaded': 'Piñón fijo roscado',
      'fixed_threaded': 'Piñón fijo roscado',
      'bmxdriver': 'Driver BMX',
      'bmx_driver': 'Driver BMX',
      'single_speed': 'Single speed',
      'singlespeed': 'Single speed',
      'derailleur': 'Con cambios',
      'externalcup': 'Cazoletas externas',
      'external_cup': 'Cazoletas externas',
      'threadedbsa': 'Rosca BSA',
      'threaded_bsa': 'Rosca BSA',
      'squaretaper': 'Cuadradillo',
      'square_taper': 'Cuadradillo',
      'hollowtech24mm': 'Hollowtech / 24 mm externo',
      'hollowtech_24mm': 'Hollowtech / 24 mm externo',
      'bb30': 'BB30',
      'pf30': 'PF30',
      'dub': 'DUB',
      'jis': 'JIS',
      'iso': 'ISO',
      'front': 'Delantero',
      'rear': 'Trasero',
      'pair': 'Par',
      'universal': 'Universal',
      'aluminum': 'Aluminio',
      'aluminium': 'Aluminio',
      'steel': 'Acero',
      'carbon': 'Carbono',
      'alloy': 'Aleación',
      'tubeless': 'Tubeless',
      'tubelessready': 'Tubeless ready',
      'tubeless_ready': 'Tubeless ready',
      'clincher': 'Clincher',
      'folding': 'Plegable',
      'wire': 'Aro rígido',
    };
    final mapped = valueMap[normalized] ?? valueMap[value];
    if (mapped != null) return mapped;
    if (RegExp(r'^[0-9]+(\.[0-9]+)?$').hasMatch(value)) return value;
    return _titleCaseTechnical(value.replaceAll('_', ' ').replaceAll('-', ' '));
  }

  String _titleCaseTechnical(String value) {
    final clean = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (clean.isEmpty) return clean;
    const preserveUpper = {
      'hg',
      'xd',
      'xdr',
      'bsa',
      'bb30',
      'pf30',
      'dub',
      'jis',
      'iso',
      'erd',
      'etrto',
      'n3w',
      'bmx',
    };
    return clean.split(' ').map((word) {
      final lower = word.toLowerCase();
      if (preserveUpper.contains(lower)) return lower.toUpperCase();
      if (lower == 'mm' || lower == 'kg') return lower;
      return lower.isEmpty
          ? lower
          : '${lower[0].toUpperCase()}${lower.substring(1)}';
    }).join(' ');
  }

  Widget _buildDetailBandItem({
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.only(top: 14, bottom: 12),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(
            color: _warmLine,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontFamily: PublicStoreTheme.defaultBodyFont,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: PublicStoreTheme.textSecondary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontFamily: PublicStoreTheme.defaultBodyFont,
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
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

class _PublicProductTechnicalSpec {
  const _PublicProductTechnicalSpec({
    required this.sectionKey,
    required this.fieldSortOrder,
    required this.specKey,
    required this.specLabel,
    required this.displayValue,
    required this.unit,
    required this.dataType,
  });

  final String sectionKey;
  final int fieldSortOrder;
  final String specKey;
  final String specLabel;
  final String displayValue;
  final String? unit;
  final String dataType;

  factory _PublicProductTechnicalSpec.fromJson(Map<String, dynamic> json) {
    return _PublicProductTechnicalSpec(
      sectionKey: json['section_key']?.toString() ?? 'general',
      fieldSortOrder: (json['field_sort_order'] as num?)?.toInt() ?? 0,
      specKey: json['spec_key']?.toString() ?? '',
      specLabel: json['spec_label']?.toString() ?? '',
      displayValue: json['display_value']?.toString() ?? '',
      unit: json['unit']?.toString(),
      dataType: json['data_type']?.toString() ?? 'text',
    );
  }
}

class _TechnicalFichaGroup {
  const _TechnicalFichaGroup(this.title, this.items);

  final String title;
  final List<MapEntry<String, String>> items;
}

String _normalizeTechnicalToken(String value) {
  return value
      .toLowerCase()
      .replaceAll('á', 'a')
      .replaceAll('é', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '')
      .trim();
}
