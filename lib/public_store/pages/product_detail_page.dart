import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/public_store_theme.dart';
import '../theme/public_store_surface_theme.dart';
import '../models/public_commerce_product_projection.dart';
import '../providers/cart_provider.dart';
import '../providers/public_store_tenant_provider.dart';
import '../services/public_inventory_service.dart';
import '../utils/public_store_tenant_resolver.dart';
import '../widgets/full_page_loading.dart';
import '../widgets/public_store_layout.dart';
import '../../shared/models/product.dart';
import '../../shared/models/public_product_visibility_policy.dart';
import '../../shared/utils/chilean_utils.dart';
import '../../shared/utils/seo_helper.dart';
import '../../modules/inventory/models/category_models.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/modules/website/models/website_catalog_presentation.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/public_store/utils/product_url.dart';
import 'package:vinabike_erp/public_store/utils/structured_data.dart';
import 'package:vinabike_erp/shared/widgets/safe_layout_builder.dart';
import 'package:vinabike_erp/public_store/services/meta_pixel_service.dart';

void _productDetailDebugLog(String message) {
  if (kDebugMode || const bool.fromEnvironment('STORE_PERF_LOGS')) {
    debugPrint(message);
  }
}

class ProductDetailPage extends StatefulWidget {
  final String productId;

  const ProductDetailPage({super.key, required this.productId});

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage>
    with AutomaticKeepAliveClientMixin {
  // Static product snapshots use the same ID. A hydrated product replaces that
  // snapshot instead of leaving Google two conflicting Product entities.
  static const _structuredDataScriptId = 'seo-product-jsonld';
  static const _originTrustWindow = Duration(seconds: 8);

  PublicStoreSurfaceTheme get _storeTheme =>
      PublicStoreSurfaceTheme.of(context);
  Product? _product;
  List<Category> _categoryTrail = const [];
  List<Product> _relatedProducts = [];
  bool _isLoading = true;
  bool _isProductValidated = false;
  bool _productValidationFailed = false;
  bool _isLoadingRelated = false;
  bool _isLoadingTechnicalSpecs = false;
  bool _technicalSpecsRequested = false;
  String? _validatedTenantId;
  int _selectedDetailsTab = 0;
  int _quantity = 1;
  int _selectedImageIndex = 0;
  int _loadToken = 0;
  List<_PublicProductTechnicalSpec> _technicalSpecs = const [];
  OverlayEntry? _productFeedbackOverlay;
  Timer? _productFeedbackTimer;
  Timer? _productFeedbackRemovalTimer;
  ValueNotifier<bool>? _productFeedbackVisible;
  PublicInventoryService? _observedInventoryService;
  String? _seededRouteKey;
  String? _trackedProductIdForRoute;
  bool _inventoryRevalidationPending = false;

  // DISABLED: AutomaticKeepAliveClientMixin causes element activation conflicts
  // during edit/preview mode switches. The performance cost of reloading is acceptable.
  @override
  bool get wantKeepAlive => false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadProduct());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final inventoryService = context.read<PublicInventoryService>();
    if (!identical(_observedInventoryService, inventoryService)) {
      _observedInventoryService
          ?.removeListener(_handlePublicInventoryInvalidated);
      _observedInventoryService = inventoryService
        ..addListener(_handlePublicInventoryInvalidated);
    }
    _seedProductFromSessionSnapshot();
    if (_inventoryRevalidationPending && TickerMode.of(context)) {
      _inventoryRevalidationPending = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handlePublicInventoryInvalidated();
      });
    }
  }

  @override
  void didUpdateWidget(ProductDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.productId != oldWidget.productId) {
      removeStructuredDataScript(_structuredDataScriptId);
      _product = null;
      _categoryTrail = const [];
      _relatedProducts = [];
      _technicalSpecs = const [];
      _isProductValidated = false;
      _productValidationFailed = false;
      _isLoadingTechnicalSpecs = false;
      _technicalSpecsRequested = false;
      _validatedTenantId = null;
      _selectedDetailsTab = 0;
      _quantity = 1;
      _selectedImageIndex = 0;
      _seededRouteKey = null;
      _trackedProductIdForRoute = null;
      _seedProductFromSessionSnapshot();
      unawaited(_loadProduct());
    }
  }

  @override
  void dispose() {
    _observedInventoryService
        ?.removeListener(_handlePublicInventoryInvalidated);
    _hideProductFeedbackBanner(animated: false);
    removeStructuredDataScript(_structuredDataScriptId);
    super.dispose();
  }

  void _handlePublicInventoryInvalidated() {
    if (!mounted) return;
    if (!TickerMode.of(context)) {
      _inventoryRevalidationPending = true;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _isProductValidated = false;
        _productValidationFailed = false;
      });
      unawaited(_loadProduct());
    });
  }

  void _seedProductFromSessionSnapshot() {
    String tenantId;
    try {
      tenantId =
          context.read<PublicStoreTenantProvider>().tenantId?.trim() ?? '';
    } catch (_) {
      return;
    }
    if (tenantId.isEmpty) return;
    final routeKey = '$tenantId:${widget.productId}';
    if (_seededRouteKey == routeKey) return;
    _seededRouteKey = routeKey;

    final snapshot = context
        .read<PublicInventoryService>()
        .getCachedProductSnapshotForIdentifier(
          tenantId: tenantId,
          productIdentifier: widget.productId,
        );
    if (snapshot == null) return;

    _product = snapshot.value;
    _isLoading = false;
    _isProductValidated = snapshot.isOriginFresh(_originTrustWindow);
    _productValidationFailed = false;
    _validatedTenantId = _isProductValidated ? tenantId : null;
  }

  Future<void> _loadProduct() async {
    final token = ++_loadToken;
    final hadVisibleProduct = _product != null;
    final hadRecentValidation = _isProductValidated;
    setState(() {
      // A product card, related card, home block, search result or cart item
      // may already have given us a complete public projection. Keep it on
      // screen while origin data is revalidated instead of flashing a
      // full-page spinner between every storefront route.
      _isLoading = !hadVisibleProduct;
      _isProductValidated = hadRecentValidation;
      _productValidationFailed = false;
      if (!hadVisibleProduct) {
        _isLoadingRelated = false;
        _isLoadingTechnicalSpecs = false;
        _technicalSpecsRequested = false;
        _relatedProducts = [];
        _technicalSpecs = const [];
      }
    });
    // Product detail is the canonical SEO owner for every product route.
    // Install a restrictive state immediately so a slow, missing or rejected
    // product can never inherit indexable metadata from the previous page.
    // Session snapshots are a paint optimization only. Until the origin
    // confirms the current publication/visibility policy, do not emit Product
    // JSON-LD or indexable metadata for the cached projection.
    removeStructuredDataScript(_structuredDataScriptId);
    _updateUnavailableSeo(token, force: true);

    try {
      final inventoryService = context.read<PublicInventoryService>();
      final tenantId = await resolvePublicStoreTenantId(context);
      if (!mounted || token != _loadToken) return;

      if (tenantId == null) {
        debugPrint('❌ [ProductDetail] No tenant ID available');
        setState(() => _isLoading = false);
        _updateUnavailableSeo(token);
        return;
      }
      final visibilityPolicy = _readVisibilityPolicy();

      // Load the product - support both UUID and SKU-based lookups
      // SKU format: "sku:S56467" (from legacy /shop/ URLs)
      Product? loadedProduct;
      if (widget.productId.startsWith('sku:')) {
        final sku = widget.productId.substring(4); // Remove "sku:" prefix
        _productDetailDebugLog(
            '🔍 [ProductDetail] Looking up product by SKU: $sku');
        loadedProduct = await inventoryService.getProductBySku(
          sku: sku,
          tenantId: tenantId,
          policy: visibilityPolicy,
          rethrowErrors: true,
        );
      } else {
        loadedProduct = await inventoryService.getProductById(
          productId: widget.productId,
          tenantId: tenantId,
          policy: visibilityPolicy,
          rethrowErrors: true,
        );
      }

      // A previously published SKU or slug may no longer identify the current
      // product directly. Resolve the full historical path from durable URL
      // aliases so old links continue working even before the next hosting
      // deployment generates a server-side redirect.
      if (loadedProduct == null) {
        final aliasProductId = await _resolveProductAlias(tenantId);
        if (aliasProductId != null) {
          loadedProduct = await inventoryService.getProductById(
            productId: aliasProductId,
            tenantId: tenantId,
            policy: visibilityPolicy,
            rethrowErrors: true,
          );
        }
      }

      if (!mounted || token != _loadToken) return;

      final previousProduct = _product;
      _product = previousProduct != null &&
              loadedProduct != null &&
              _sameProductSnapshot(previousProduct, loadedProduct)
          ? previousProduct
          : loadedProduct;
      _categoryTrail = const [];

      if (_product != null) {
        _isProductValidated = true;
        _productValidationFailed = false;
        _validatedTenantId = tenantId;
        if (_trackedProductIdForRoute != _product!.id) {
          _trackedProductIdForRoute = _product!.id;
          MetaPixelService.instance.trackViewContent(
            contentId: MetaPixelService.catalogContentId(
              sku: _product!.sku,
              productId: _product!.id,
            ),
            contentName: _commerceProjection(_product!).title,
            value: _commerceProjection(_product!).price,
          );
        }
        _productDetailDebugLog(
            '✅ [ProductDetail] Found product: ${_product!.name}');
        // Paint the authoritative product immediately. Breadcrumb metadata,
        // technical specs and suggestions are independent and must never
        // extend the route's critical path.
        setState(() => _isLoading = false);
        _updateSeo();
        _updateStructuredData();
        unawaited(
          _loadCategoryTrail(
            token: token,
            inventoryService: inventoryService,
            tenantId: tenantId,
            product: _product!,
          ),
        );
        _loadRelatedProducts(
          token: token,
          inventoryService: inventoryService,
          tenantId: tenantId,
          product: _product!,
          visibilityPolicy: visibilityPolicy,
        );
        _scheduleCanonicalProductUrlReplacement(_product!, token);
      } else {
        _isProductValidated = false;
        debugPrint('❌ [ProductDetail] Product not found: ${widget.productId}');
        removeStructuredDataScript(_structuredDataScriptId);
        setState(() => _isLoading = false);
        _updateUnavailableSeo(token);
      }
    } catch (e) {
      debugPrint('[ProductDetailPage] Error loading product: $e');
      if (mounted && token == _loadToken && _product == null) {
        removeStructuredDataScript(_structuredDataScriptId);
        setState(() => _isLoading = false);
        _updateUnavailableSeo(token);
      } else if (mounted && token == _loadToken) {
        // A transport failure is not proof that the cached product vanished.
        // Keep the useful session snapshot visible and retry on the next
        // navigation/invalidation.
        setState(() {
          _isLoading = false;
          _productValidationFailed = true;
        });
      }
    }
  }

  bool _sameProductSnapshot(Product current, Product next) {
    return current.id == next.id &&
        current.updatedAt == next.updatedAt &&
        current.name == next.name &&
        current.sku == next.sku &&
        current.price == next.price &&
        current.stockQuantity == next.stockQuantity &&
        current.imageUrl == next.imageUrl &&
        current.imageUrlOptimized == next.imageUrlOptimized &&
        _sameStrings(current.imageUrls, next.imageUrls) &&
        current.websiteName == next.websiteName &&
        current.websitePrice == next.websitePrice &&
        current.websiteDescription == next.websiteDescription &&
        current.description == next.description &&
        current.brand == next.brand &&
        current.categoryId == next.categoryId &&
        current.categoryName == next.categoryName;
  }

  bool _sameStrings(List<String> current, List<String> next) {
    if (current.length != next.length) return false;
    for (var index = 0; index < current.length; index++) {
      if (current[index] != next[index]) return false;
    }
    return true;
  }

  Future<void> _loadCategoryTrail({
    required int token,
    required PublicInventoryService inventoryService,
    required String tenantId,
    required Product product,
  }) async {
    final categoryTrail = await _resolveCategoryTrail(
      inventoryService: inventoryService,
      tenantId: tenantId,
      product: product,
    );
    if (!mounted || token != _loadToken || _product?.id != product.id) return;
    setState(() => _categoryTrail = categoryTrail);
  }

  Future<List<Category>> _resolveCategoryTrail({
    required PublicInventoryService inventoryService,
    required String tenantId,
    required Product product,
  }) async {
    final categoryId = product.categoryId?.trim() ?? '';
    if (categoryId.isEmpty) return const [];

    final categories = await inventoryService.getCategoriesForTenant(
      tenantId: tenantId,
    );
    final byId = {
      for (final category in categories)
        if (category.id?.trim().isNotEmpty == true)
          category.id!.trim(): category,
    };
    final reversedTrail = <Category>[];
    final visited = <String>{};
    var currentId = categoryId;
    while (currentId.isNotEmpty && visited.add(currentId)) {
      final category = byId[currentId];
      if (category == null) break;
      reversedTrail.add(category);
      currentId = category.parentId?.trim() ?? '';
    }
    return List.unmodifiable(reversedTrail.reversed);
  }

  Future<String?> _resolveProductAlias(String tenantId) async {
    try {
      final aliasPath = normalizePublicProductRouteForRuntime(
        GoRouterState.of(context).uri.path,
        isErpMounted: false,
      );
      final result = await Supabase.instance.client.rpc(
        'resolve_public_product_url_alias',
        params: {
          'p_tenant_id': tenantId,
          'p_alias_path': aliasPath,
        },
      );
      final productId = result?.toString().trim() ?? '';
      return productId.isEmpty ? null : productId;
    } catch (error) {
      debugPrint('[ProductDetailPage] Alias lookup failed: $error');
      return null;
    }
  }

  void _scheduleCanonicalProductUrlReplacement(Product product, int token) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || token != _loadToken) return;

      final currentUri = GoRouterState.of(context).uri;
      final canonicalPath = normalizePublicProductRouteForRuntime(
        publicProductPath(product),
        isErpMounted: currentUri.path == '/tienda' ||
            currentUri.path.startsWith('/tienda/'),
      );
      if (currentUri.path == canonicalPath) return;

      final canonicalUri = currentUri.replace(path: canonicalPath);
      GoRouter.of(context).replace(canonicalUri.toString());
    });
  }

  Future<void> _loadTechnicalSpecs({
    required int token,
    required String tenantId,
    required String productId,
  }) async {
    if (productId.isEmpty || _technicalSpecsRequested) return;
    _technicalSpecsRequested = true;
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
      final page = await inventoryService.getProductPageForTenant(
        tenantId: tenantId,
        categoryIds: [categoryId],
        policy: visibilityPolicy,
        onlyInStock: true,
        limit: 12,
      );

      if (!mounted || token != _loadToken) return;
      final nextProducts = page.products
          .where((candidate) => candidate.id != product.id)
          .take(4)
          .toList(growable: false);
      if (_sameRelatedProducts(_relatedProducts, nextProducts)) {
        if (_isLoadingRelated) {
          setState(() => _isLoadingRelated = false);
        }
      } else {
        setState(() {
          _relatedProducts = nextProducts;
          _isLoadingRelated = false;
        });
      }
    } catch (_) {
      if (!mounted || token != _loadToken) return;
      setState(() => _isLoadingRelated = false);
    }
  }

  bool _sameRelatedProducts(List<Product> current, List<Product> next) {
    if (current.length != next.length) return false;
    for (var index = 0; index < current.length; index++) {
      if (!_sameProductSnapshot(current[index], next[index])) return false;
    }
    return true;
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
    final productUrl = '$normalizedStoreUrl${publicProductPath(product)}';
    final commerce = _commerceProjection(product);
    if (commerce.imageUrls.isEmpty) {
      removeStructuredDataScript(_structuredDataScriptId);
      return;
    }

    final structuredData = <String, dynamic>{
      '@context': 'https://schema.org/',
      '@type': 'Product',
      'name': commerce.title,
      if (commerce.description.isNotEmpty)
        'description': _cleanSeoText(commerce.description),
      'url': productUrl,
      if (commerce.sku.isNotEmpty) 'sku': commerce.sku,
      'image': commerce.imageUrls,
      if (commerce.gtin.isNotEmpty) 'gtin': commerce.gtin,
      if (commerce.mpn.isNotEmpty) 'mpn': commerce.mpn,
      if (commerce.brand.isNotEmpty)
        'brand': {
          '@type': 'Brand',
          'name': commerce.brand,
        },
      'offers': {
        '@type': 'Offer',
        'priceCurrency': commerce.currency,
        if (commerce.price > 0) 'price': commerce.formattedPrice,
        'availability': commerce.availability.schemaValue,
        'url': productUrl,
        'seller': {
          '@type': 'Organization',
          'name': storeName,
        },
        'itemCondition': 'https://schema.org/NewCondition',
      },
    };

    if (commerce.categoryPath.isNotEmpty) {
      structuredData['category'] = commerce.categoryPath;
    }

    setStructuredDataScript(_structuredDataScriptId, structuredData);
  }

  PublicCommerceProductProjection _commerceProjection(Product product) {
    return PublicCommerceProductProjection.fromProduct(
      product,
      categoryPath: _categoryTrail.isNotEmpty
          ? _categoryTrail.last.fullPath
          : product.categoryName,
    );
  }

  void _updateSeo() {
    final product = _product;
    if (product == null) return;

    final websiteService = context.read<WebsiteService>();
    final storeName = websiteService.getSetting('store_name', 'Vinabike');
    final storeUrl = websiteService.getSetting(
      'store_url',
      'https://vinabike.cl',
    );
    final canonicalUrl =
        '${storeUrl.replaceAll(RegExp(r'/+$'), '')}${publicProductPath(product)}';
    final commerce = _commerceProjection(product);
    final routeProjection = _productSeoRouteProjection(
      hasEligibleContent: true,
    );

    // Templates are configurable via website_settings (and later via SEO editor UI).
    final titleTemplate = websiteService.getSetting(
      'seo_product_title_template',
      '{product_name} | {store_name}',
    );
    final descriptionTemplate = websiteService.getSetting(
      'seo_product_description_template',
      '{product_description}',
    );

    final seoTitleOverride = product.websiteSeoTitle?.trim() ?? '';
    final resolvedTitle = _cleanSeoText(
      (seoTitleOverride.isNotEmpty
              ? seoTitleOverride
              : _applySeoTemplate(
                  template: titleTemplate,
                  storeName: storeName,
                  commerce: commerce,
                ))
          .trim(),
    );

    final seoDescriptionOverride = product.websiteSeoDescription?.trim() ?? '';
    final resolvedDescription = (seoDescriptionOverride.isNotEmpty
            ? seoDescriptionOverride
            : _applySeoTemplate(
                template: descriptionTemplate,
                storeName: storeName,
                commerce: commerce,
              ))
        .trim();

    final cleanResolvedDescription = _cleanSeoText(resolvedDescription);

    final image =
        commerce.imageUrls.isNotEmpty ? commerce.imageUrls.first : null;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SeoHelper.updateSeo(
        title: resolvedTitle.isNotEmpty ? resolvedTitle : storeName,
        description: cleanResolvedDescription.isNotEmpty
            ? cleanResolvedDescription
            : null,
        imageUrl: image,
        canonicalUrl: canonicalUrl,
        robots: routeProjection.robots,
      );
    });
  }

  void _updateUnavailableSeo(int token, {bool force = false}) {
    final websiteService = context.read<WebsiteService>();
    final storeName =
        websiteService.getSetting('store_name', 'Vinabike').trim();
    final routeProjection = _productSeoRouteProjection(
      hasEligibleContent: false,
    );
    final configuredStoreUrl =
        websiteService.getSetting('store_url', '').trim();
    final baseUri = configuredStoreUrl.isNotEmpty
        ? Uri.tryParse(configuredStoreUrl)
        : Uri.base.host.isEmpty
            ? null
            : Uri(
                scheme: Uri.base.scheme,
                host: Uri.base.host,
                port: Uri.base.hasPort ? Uri.base.port : null,
              );
    final canonicalUrl = baseUri
        ?.resolve(routeProjection.canonicalPath)
        .replace(query: null, fragment: null)
        .toString();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          token != _loadToken ||
          _isProductValidated ||
          (!force && _product != null)) {
        return;
      }
      SeoHelper.updateSeo(
        title:
            'Producto no disponible | ${storeName.isEmpty ? 'Tienda' : storeName}',
        canonicalUrl: canonicalUrl,
        robots: routeProjection.robots,
      );
    });
  }

  StorefrontSeoRouteProjection _productSeoRouteProjection({
    required bool hasEligibleContent,
  }) {
    final currentUri = GoRouterState.of(context).uri;
    var editorIsPrivate = false;
    try {
      final editProvider = context.read<WebsiteEditModeProvider>();
      editorIsPrivate = editProvider.isEditMode || editProvider.isPreviewMode;
    } catch (_) {
      // Standalone public storefronts do not need an editor provider.
    }
    final isErpMounted =
        currentUri.path == '/tienda' || currentUri.path.startsWith('/tienda/');
    return projectStorefrontSeoRoute(
      currentUri,
      isErpMounted: isErpMounted || editorIsPrivate,
      ownerAllowsIndexing: true,
      ownerIsPublished: hasEligibleContent,
      hasEligibleContent: hasEligibleContent,
    );
  }

  String _cleanSeoText(String text) {
    return text
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _formatHeroPrice(double value) {
    return ChileanUtils.formatCurrency(value).replaceFirst(r'$ ', r'$');
  }

  String _applySeoTemplate({
    required String template,
    required String storeName,
    required PublicCommerceProductProjection commerce,
  }) {
    final priceText = ChileanUtils.formatCurrency(commerce.price);

    return template
        .replaceAll('{store_name}', storeName)
        .replaceAll('{product_name}', commerce.title)
        .replaceAll('{product_sku}', commerce.sku)
        .replaceAll('{product_price}', priceText)
        .replaceAll('{product_brand}', commerce.brand)
        .replaceAll('{product_description}', commerce.description);
  }

  void _addToCart() {
    if (_product == null || !_isProductValidated) return;

    final isStockTracked =
        _product!.productType != ProductType.service && _product!.trackStock;
    if (isStockTracked && _product!.availableStockQuantity < _quantity) {
      _showProductFeedbackBanner(
        message: 'Stock insuficiente',
        backgroundColor: _storeTheme.error,
        foregroundColor: _storeTheme.onError,
      );
      return;
    }

    final cart = context.read<CartProvider>();
    cart.addProduct(_product!, quantity: _quantity);

    _showProductFeedbackBanner(
      message: '${_commerceProjection(_product!).title} agregado al carrito',
      backgroundColor: _storeTheme.commerceAccent,
      foregroundColor: _storeTheme.onCommerceAccent,
      actionLabel: 'Ver carrito',
      onActionPressed: () => context.go('/carrito'),
    );

    setState(() => _quantity = 1);
  }

  void _buyNow() {
    if (_product == null || !_isProductValidated) return;

    final isStockTracked =
        _product!.productType != ProductType.service && _product!.trackStock;
    if (isStockTracked && _product!.availableStockQuantity < _quantity) {
      _showProductFeedbackBanner(
        message: 'Stock insuficiente',
        backgroundColor: _storeTheme.error,
        foregroundColor: _storeTheme.onError,
      );
      return;
    }

    context.read<CartProvider>().addProduct(_product!, quantity: _quantity);
    setState(() => _quantity = 1);
    PublicStoreLayout.navigateToHref(context, '/checkout');
  }

  void _showProductFeedbackBanner({
    required String message,
    required Color backgroundColor,
    required Color foregroundColor,
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
                            style: _storeTheme.text.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: foregroundColor,
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
                              foregroundColor: foregroundColor,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              textStyle: _storeTheme.text.labelMedium?.copyWith(
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
            Icon(
              Icons.error_outline,
              size: 64,
              color: _storeTheme.commerceTextMuted,
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
        final horizontalMargin = isMobile ? 16.0 : (isTablet ? 24.0 : 48.0);
        final verticalMargin = isMobile ? 18.0 : 30.0;

        // PublicStoreLayout owns the single vertical scroll viewport. A nested
        // scroll view adds a second layout/paint pass and causes route-size
        // jumps while product data is revalidated.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 1420),
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
                    if (!isMobile) const SizedBox(height: 30),
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
                          final columnGap = isTablet ? 32.0 : 56.0;
                          final galleryWidth = isTablet
                              ? ((rowWidth - columnGap) * 0.52)
                              : ((rowWidth - columnGap) * 0.54);
                          final infoWidth = rowWidth - columnGap - galleryWidth;

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: galleryWidth,
                                child: _buildImageGallery(),
                              ),
                              SizedBox(width: columnGap),
                              SizedBox(
                                width: infoWidth,
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
                  child: _isLoadingRelated && _relatedProducts.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            if (_isLoadingRelated)
                              const SizedBox(
                                height: 2,
                                child: LinearProgressIndicator(minHeight: 2),
                              ),
                            _buildRelatedProducts(),
                          ],
                        ),
                ),
              ),
            SizedBox(height: isMobile ? 72 : 88),
          ],
        );
      },
    );
  }

  Widget _buildBreadcrumb() {
    final isService = _product?.productType == ProductType.service;
    final catalogLabel = isService ? 'Servicios' : 'Productos';
    final catalogHref = isService ? '/servicios' : '/productos';
    final categoryId = _product?.categoryId?.trim() ?? '';
    final categoryName = _product?.categoryName?.trim() ?? '';
    final fallbackCategory = _categoryTrail.isEmpty &&
            categoryId.isNotEmpty &&
            categoryName.isNotEmpty
        ? Category(
            id: categoryId,
            tenantId: '',
            name: categoryName,
            fullPath: categoryName,
            showOnWebsite: true,
          )
        : null;
    final breadcrumbCategories = _categoryTrail.isNotEmpty
        ? _categoryTrail
        : fallbackCategory == null
            ? const <Category>[]
            : [fallbackCategory];

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildBreadcrumbLink('Inicio', () => context.go('/')),
        _buildBreadcrumbSeparator(),
        _buildBreadcrumbLink(catalogLabel, () => context.go(catalogHref)),
        _buildBreadcrumbSeparator(),
        for (final category in breadcrumbCategories) ...[
          Builder(
            builder: (context) {
              if (!category.showOnWebsite) {
                return Text(
                  category.name,
                  style: _storeTheme.text.bodyMedium?.copyWith(
                    color: _storeTheme.commerceTextMuted,
                  ),
                );
              }
              WebsiteCatalogPresentation presentation;
              try {
                presentation = context
                        .read<WebsiteService>()
                        .catalogPresentationRegistry
                        .forCategory(category.id) ??
                    WebsiteCatalogPresentation.fallback(
                      categoryId: category.id!,
                      categoryName: category.name,
                    );
              } catch (_) {
                presentation = WebsiteCatalogPresentation.fallback(
                  categoryId: category.id!,
                  categoryName: category.name,
                );
              }
              return _buildBreadcrumbLink(
                category.name,
                () => PublicStoreLayout.navigateToHref(
                  context,
                  publicCategoryPath(
                    presentation: presentation,
                    services: isService,
                  ),
                ),
              );
            },
          ),
          _buildBreadcrumbSeparator(),
        ],
        Text(
          _commerceProjection(_product!).title,
          style: _storeTheme.text.bodyMedium?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: _storeTheme.commerceTextMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildImageGallery({bool isMobile = false}) {
    final images = _commerceProjection(_product!).imageUrls;

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
                color: _storeTheme.commerceTextMuted,
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
            gaplessPlayback: true,
            errorBuilder: (context, error, stackTrace) {
              return Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  size: 64,
                  color: _storeTheme.commerceTextMuted,
                ),
              );
            },
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            mainStage,
            if (images.length > 1) ...[
              SizedBox(height: isMobile ? 16 : 20),
              SizedBox(
                height: isMobile ? 72 : 92,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: images.length,
                  separatorBuilder: (_, __) =>
                      SizedBox(width: isMobile ? 12 : 18),
                  itemBuilder: (context, index) {
                    final isSelected = index == _selectedImageIndex;
                    return _buildThumbnail(
                      imageUrl: images[index],
                      isSelected: isSelected,
                      size: isMobile ? 72 : 92,
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
        color: _storeTheme.surface,
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
    final commerce = _commerceProjection(_product!);
    final isStockTracked = _product!.tracksInventory;
    final inStock = commerce.availability == PublicCommerceAvailability.inStock;
    final canIncrease =
        !isStockTracked || _quantity < _product!.availableStockQuantity;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          commerce.title.toUpperCase(),
          style: _storeTheme.text.headlineMedium?.copyWith(
            fontSize: isMobile ? 30 : 34,
            fontWeight: FontWeight.w700,
            color: _storeTheme.commerceTextPrimary,
            height: isMobile ? 1.18 : 1.2,
            letterSpacing: 0.2,
          ),
        ),
        SizedBox(height: isMobile ? 20 : 24),
        Divider(height: 1, color: _storeTheme.commerceLine),
        SizedBox(height: isMobile ? 20 : 24),
        Text(
          _formatHeroPrice(commerce.price),
          style: _storeTheme.text.displaySmall?.copyWith(
            fontSize: isMobile ? 38 : 40,
            fontWeight: FontWeight.w700,
            color: _storeTheme.commerceAccent,
            height: 0.95,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Precio final con IVA incluido',
          style: _storeTheme.text.bodySmall?.copyWith(
            fontSize: 13,
            color: _storeTheme.commerceTextSecondary,
          ),
        ),
        SizedBox(height: isMobile ? 20 : 24),
        Divider(height: 1, color: _storeTheme.commerceLine),
        SizedBox(height: isMobile ? 18 : 22),
        _buildStockSkuRow(inStock: inStock),
        const SizedBox(height: 10),
        SizedBox(
          height: 34,
          child: Row(
            children: [
              if (_isProductValidated)
                Icon(
                  Icons.check_circle_outline,
                  size: 15,
                  color: _storeTheme.commerceAccent,
                )
              else if (_productValidationFailed)
                Icon(
                  Icons.cloud_off_outlined,
                  size: 15,
                  color: _storeTheme.commerceTextSecondary,
                )
              else
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _storeTheme.commerceTextSecondary,
                  ),
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _isProductValidated
                      ? 'Precio y disponibilidad actualizados.'
                      : _productValidationFailed
                          ? 'No pudimos confirmar precio y disponibilidad.'
                          : 'Actualizando precio y disponibilidad…',
                  style: _storeTheme.text.bodySmall?.copyWith(
                    fontSize: 12,
                    color: _storeTheme.commerceTextSecondary,
                  ),
                ),
              ),
              if (_productValidationFailed)
                TextButton(
                  onPressed: () => unawaited(_loadProduct()),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Reintentar'),
                ),
            ],
          ),
        ),
        SizedBox(height: isMobile ? 18 : 22),
        if (inStock)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isMobile) ...[
                _buildQuantitySelector(
                  canIncrease: _isProductValidated && canIncrease,
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
                    _buildQuantitySelector(
                      canIncrease: _isProductValidated && canIncrease,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildCartAction(
                        inCart: inCart,
                        width: double.infinity,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 14),
              _buildBuyNowAction(isMobile: isMobile),
              if (inCart) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(
                      Icons.shopping_bag_outlined,
                      size: 16,
                      color: _storeTheme.commerceAccent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Ya tienes este producto en el carrito.',
                        style: _storeTheme.text.bodySmall?.copyWith(
                          fontSize: 13,
                          color: _storeTheme.commerceTextSecondary,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => context.go('/carrito'),
                      style: TextButton.styleFrom(
                        foregroundColor: _storeTheme.commerceAccent,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Ver carrito',
                        style: TextStyle(
                          fontFamily: null,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'NO DISPONIBLE',
              style: _storeTheme.text.labelMedium?.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: _storeTheme.commerceTextSecondary,
              ),
            ),
          ),
        const SizedBox(height: 28),
        Container(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: _storeTheme.commerceLine),
            ),
          ),
          child: Column(
            children: [
              _buildInfoTile(
                icon: Icons.local_shipping_outlined,
                title: 'Despacho a Chile continental',
                subtitle: 'Entrega estimada de 3 a 12 días hábiles.',
              ),
              _buildInfoTile(
                icon: Icons.storefront_outlined,
                title: 'Retiro en tienda',
                subtitle: 'Disponible en Alvarez 32, Local 17, Viña del Mar.',
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
    final description =
        _cleanSeoText(_commerceProjection(_product!).description);

    return Container(
      width: double.infinity,
      color: _storeTheme.surface,
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
                foreground: _storeTheme.commerceAccent,
                lineColor: _storeTheme.commerceAccent,
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
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: _storeTheme.commerceLine),
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
      onTap: () {
        setState(() => _selectedDetailsTab = index);
        final product = _product;
        final tenantId = _validatedTenantId;
        if (index == 1 &&
            _isProductValidated &&
            product != null &&
            tenantId != null) {
          unawaited(
            _loadTechnicalSpecs(
              token: _loadToken,
              tenantId: tenantId,
              productId: product.id,
            ),
          );
        }
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color:
                    selected ? _storeTheme.commerceAccent : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Text(
              label.toUpperCase(),
              style: _storeTheme.text.labelSmall?.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: selected
                    ? _storeTheme.commerceAccent
                    : _storeTheme.commerceTextSecondary,
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
        style: _storeTheme.text.bodyMedium?.copyWith(
          fontSize: 15,
          color: _storeTheme.commerceTextPrimary,
          height: 1.7,
        ),
      ),
    );
  }

  Widget _buildTechnicalFichaTab({required bool isMobile}) {
    if (_isLoadingTechnicalSpecs) {
      return SizedBox(
        key: const ValueKey('product_technical_specs_loading'),
        height: 96,
        child: Center(
          child: SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: _storeTheme.commerceAccent,
            ),
          ),
        ),
      );
    }

    final groups = _buildTechnicalFichaGroups();
    if (groups.isEmpty) {
      return Text(
        key: const ValueKey('product_technical_specs_empty'),
        'La ficha técnica de este producto está en actualización.',
        style: _storeTheme.text.bodyMedium?.copyWith(
          fontSize: 15,
          color: _storeTheme.commerceTextSecondary,
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
          style: _storeTheme.text.labelSmall?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: _storeTheme.commerceAccent,
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
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: _storeTheme.commerceLine,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: _storeTheme.text.labelSmall?.copyWith(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _storeTheme.commerceTextSecondary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: _storeTheme.text.bodyMedium?.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: _storeTheme.commerceTextPrimary,
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
    final commerce = _commerceProjection(product);
    final brand = commerce.brand;
    final hasBrand = brand.isNotEmpty;
    final displayImageUrl =
        commerce.imageUrls.isNotEmpty ? commerce.imageUrls.first : null;
    final hasImage = displayImageUrl != null && displayImageUrl.isNotEmpty;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          PublicStoreLayout.navigateToHref(
            context,
            publicProductPath(product),
          );
        },
        child: Container(
          color: _storeTheme.surface,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      color: _storeTheme.surface,
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
                                    color: _storeTheme.commerceTextMuted,
                                  ),
                                );
                              },
                            )
                          : Center(
                              child: Icon(
                                Icons.pedal_bike_outlined,
                                size: 48,
                                color: _storeTheme.commerceTextMuted,
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
                          style: _storeTheme.text.labelSmall?.copyWith(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _storeTheme.commerceTextMuted,
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
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: _storeTheme.commerceLine),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        commerce.title.toUpperCase(),
                        style: _storeTheme.text.bodySmall?.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _storeTheme.commerceTextPrimary,
                          height: 1.3,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        ChileanUtils.formatCurrency(commerce.price),
                        style: _storeTheme.text.bodyLarge?.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _storeTheme.commerceTextPrimary,
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
        style: _storeTheme.text.bodyMedium?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: _storeTheme.commerceAccent,
        ),
      ),
    );
  }

  Widget _buildBreadcrumbSeparator() {
    return Text(
      '/',
      style: _storeTheme.text.bodySmall?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: _storeTheme.commerceTextMuted,
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
          color: isSelected
              ? _storeTheme.commerceAccent.withValues(alpha: 0.04)
              : _storeTheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected
                ? _storeTheme.commerceAccent
                : _storeTheme.commerceLine,
            width: isSelected ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(8),
        child: Image.network(
          imageUrl,
          fit: BoxFit.contain,
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) {
            return Icon(
              Icons.broken_image_outlined,
              size: 20,
              color: _storeTheme.commerceTextMuted,
            );
          },
        ),
      ),
    );
  }

  Widget _buildStockSkuRow({required bool inStock}) {
    final sku = _product!.sku.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: inStock
                ? PublicStoreTheme.success
                : _storeTheme.commerceTextMuted,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          inStock ? 'En stock' : 'Agotado',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: inStock
                ? PublicStoreTheme.success
                : _storeTheme.commerceTextSecondary,
          ),
        ),
        if (sku.isNotEmpty) ...[
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'SKU: $sku',
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: _storeTheme.text.labelSmall?.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _storeTheme.commerceTextSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ],
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
        color: _storeTheme.surface,
        border: Border.all(color: _storeTheme.commerceLine),
      ),
      child: Row(
        children: [
          _buildQuantityButton(
            icon: Icons.remove,
            enabled: _isProductValidated && _quantity > 1,
            onTap: () => setState(() => _quantity--),
          ),
          Expanded(
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.symmetric(
                  vertical: BorderSide(color: _storeTheme.commerceLine),
                ),
              ),
              child: Text(
                '$_quantity',
                style: _storeTheme.text.labelLarge?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: _storeTheme.commerceTextPrimary,
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
          color: enabled
              ? _storeTheme.commerceTextPrimary
              : _storeTheme.commerceTextMuted,
        ),
      ),
    );
  }

  Widget _buildBuyNowAction({required bool isMobile}) {
    return SizedBox(
      width: double.infinity,
      height: isMobile ? 52 : 50,
      child: MouseRegion(
        onEnter: _isProductValidated
            ? (_) => PublicStoreLayout.prepareHref(context, '/checkout')
            : null,
        child: OutlinedButton(
          onPressed: _isProductValidated ? _buyNow : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: _storeTheme.commerceAccent,
            backgroundColor: _storeTheme.surface,
            side: BorderSide(color: _storeTheme.commerceLine),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          child: const Text(
            'Comprar ahora',
            style: TextStyle(
              fontFamily: null,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
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
        onPressed: _isProductValidated ? _addToCart : null,
        style: FilledButton.styleFrom(
          backgroundColor: _storeTheme.commerceAccent,
          foregroundColor: _storeTheme.onCommerceAccent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        icon: const Icon(Icons.shopping_cart_outlined, size: 17),
        label: Text(
          inCart ? 'Añadir otra unidad' : 'Agregar al carrito',
          style: const TextStyle(
            fontFamily: null,
            fontSize: 14,
            fontWeight: FontWeight.w700,
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
            color: isLast ? Colors.transparent : _storeTheme.commerceLine,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Icons.circle,
              size: 8,
              color: _storeTheme.commerceAccent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: _storeTheme.text.bodySmall?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _storeTheme.commerceTextPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: _storeTheme.text.bodySmall?.copyWith(
                    fontSize: 13,
                    color: _storeTheme.commerceTextSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            icon,
            size: 18,
            color: _storeTheme.commerceTextSecondary,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeading(
    String title, {
    Color? foreground,
    Color? lineColor,
  }) {
    final effectiveForeground = foreground ?? _storeTheme.commerceTextPrimary;
    final effectiveLineColor = lineColor ?? _storeTheme.commerceAccent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: _storeTheme.text.headlineMedium?.copyWith(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: effectiveForeground,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: 72,
          height: 2,
          color: effectiveLineColor,
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
