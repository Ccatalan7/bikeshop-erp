import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/public_inventory_service.dart';
import '../providers/public_store_tenant_provider.dart';
import '../../shared/services/tenant_service.dart';
import '../../shared/models/product.dart';
import '../../shared/models/public_product_visibility_policy.dart';
import '../../modules/website/services/website_service.dart';
import '../../modules/website/widgets/website_editor_navigation_guard.dart';
import '../utils/product_url.dart';
import '../models/public_commerce_product_projection.dart';
import 'public_store_layout.dart';

class SearchOverlay extends StatefulWidget {
  final String tenantId;
  final Map<String, String> preserveQueryParameters;

  const SearchOverlay({
    super.key,
    required this.tenantId,
    this.preserveQueryParameters = const {},
  });

  /// Shows the search overlay with a nice fade transition.
  /// Handles tenant resolution internally to support both Public Store (visitor)
  /// and Website Editor (admin) contexts.
  static Future<void> show(BuildContext context, {String? tenantId}) {
    // Try to resolve tenant ID from various sources
    String? effectiveTenantId = tenantId;

    if (effectiveTenantId == null) {
      try {
        // 1. Try PublicStoreTenantProvider (visitor context)
        effectiveTenantId = context.read<PublicStoreTenantProvider>().tenantId;
      } catch (_) {}
    }

    if (effectiveTenantId == null) {
      try {
        // 2. Try TenantService (admin/editor context)
        effectiveTenantId = context.read<TenantService>().currentTenantId;
      } catch (_) {}
    }

    if (effectiveTenantId == null) {
      debugPrint(
          '❌ [SearchOverlay] Cannot show: No tenant ID found in context');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo establecer conexión con la tienda'),
          backgroundColor: Colors.red,
        ),
      );
      return Future.value();
    }

    final preserveQueryParameters =
        GoRouterState.of(context).uri.queryParameters;

    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar búsqueda',
      barrierColor: Colors.black.withAlpha(77), // ~30% opacity
      transitionDuration: const Duration(milliseconds: 150), // Snappier
      pageBuilder: (_, __, ___) => SearchOverlay(
        tenantId: effectiveTenantId!,
        preserveQueryParameters: preserveQueryParameters,
      ),
      transitionBuilder: (_, anim, __, child) {
        return FadeTransition(opacity: anim, child: child);
      },
    );
  }

  @override
  State<SearchOverlay> createState() => _SearchOverlayState();
}

class _SearchOverlayState extends State<SearchOverlay> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  List<Product> _results = [];
  bool _isLoading = false;
  int _searchToken = 0;

  static const int _suggestionsLimit = 20;

  Future<void> _goToCatalogSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;

    final editorDecision = await WebsiteEditorNavigationGuard.authorize(
      context,
      intent: WebsiteEditorNavigationIntent.switchPage,
    );
    if (!editorDecision.isAllowed) return;
    if (!mounted) return;
    if (!await PublicStoreLayout.authorizeCheckoutExit(context)) return;
    if (!mounted) return;
    if (!editorDecision.commit()) return;
    final router = GoRouter.of(context);
    Navigator.of(context, rootNavigator: true).pop();

    final mergedQp = <String, String>{
      ...widget.preserveQueryParameters,
      'q': q,
    };

    final destination = Uri(
      path: '/tienda/productos',
      queryParameters: mergedQp,
    ).toString();
    router.push(destination);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    final searchToken = ++_searchToken;

    if (query.trim().isEmpty) {
      if (mounted) {
        setState(() {
          _results = [];
          _isLoading = false;
        });
      }
      return;
    }

    if (mounted) setState(() => _isLoading = true);

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      await _performSearch(query, searchToken);
    });
  }

  Future<void> _performSearch(String query, int searchToken) async {
    if (!mounted) return;

    final inventoryService = context.read<PublicInventoryService>();
    final visibilityPolicy = _readVisibilityPolicy();

    try {
      final results = await inventoryService.searchProductsFuzzy(
        tenantId: widget.tenantId, // Use passed tenantId
        searchTerm: query,
        policy: visibilityPolicy,
        limit: _suggestionsLimit,
      );

      if (!mounted || searchToken != _searchToken) return;

      setState(() {
        _results = results;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || searchToken != _searchToken) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ocurrió un error al buscar')),
      );

      setState(() {
        _isLoading = false;
      });
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

  Future<void> _goToProduct(Product product) async {
    final editorDecision = await WebsiteEditorNavigationGuard.authorize(
      context,
      intent: WebsiteEditorNavigationIntent.switchPage,
    );
    if (!editorDecision.isAllowed) return;
    if (!mounted) return;
    if (!await PublicStoreLayout.authorizeCheckoutExit(context)) return;
    if (!mounted) return;
    if (!editorDecision.commit()) return;
    final router = GoRouter.of(context);
    // Close the dialog first (use root navigator to be robust across shells).
    Navigator.of(context, rootNavigator: true).pop();

    final destination = Uri(
      path: publicProductPath(product),
      queryParameters: widget.preserveQueryParameters.isEmpty
          ? null
          : widget.preserveQueryParameters,
    ).toString();
    router.push(destination);
  }

  String _formatCurrency(double amount) {
    if (amount == 0) return '\$0';
    final str = amount.toInt().toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.');
    return '\$$str';
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 800;

    final currentQuery = _searchController.text.trim();
    final hasQuery = currentQuery.isNotEmpty;

    // Spotlight dimensions
    final width = isDesktop ? 640.0 : screenWidth - 32;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Blur backdrop
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),

          Align(
            alignment: Alignment.topCenter,
            child: Container(
              margin: EdgeInsets.only(top: isDesktop ? 120 : 60),
              width: width,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(51), // ~20% opacity
                    blurRadius: 40,
                    offset: const Offset(0, 20),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Search Header
                  Container(
                    height: 72,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      border:
                          Border(bottom: BorderSide(color: Colors.grey[100]!)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search, size: 28, color: Colors.grey[400]),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            focusNode: _focusNode,
                            onChanged: _onSearchChanged,
                            onSubmitted: _goToCatalogSearch,
                            style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.black87,
                                    ) ??
                                const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black87,
                                ),
                            decoration: InputDecoration(
                              hintText: 'Buscar...',
                              hintStyle: TextStyle(color: Colors.grey[400]),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        if (_isLoading)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'ESC',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Results
                  if (_results.isNotEmpty)
                    Flexible(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.6,
                        ),
                        child: ListView.separated(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shrinkWrap: true,
                          itemCount: _results.length,
                          separatorBuilder: (c, i) =>
                              const Divider(height: 1, indent: 76),
                          itemBuilder: (context, index) {
                            final product = _results[index];
                            final commerce =
                                PublicCommerceProductProjection.fromProduct(
                              product,
                            );
                            final imageUrl = commerce.imageUrls.isEmpty
                                ? null
                                : commerce.imageUrls.first;
                            return InkWell(
                              onTap: () => _goToProduct(product),
                              hoverColor: Colors.grey[50],
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[100],
                                        borderRadius: BorderRadius.circular(8),
                                        image: imageUrl == null
                                            ? null
                                            : DecorationImage(
                                                image: NetworkImage(imageUrl),
                                                fit: BoxFit.cover,
                                              ),
                                      ),
                                      child: imageUrl == null
                                          ? const Icon(
                                              Icons.shopping_bag_outlined,
                                              color: Colors.grey)
                                          : null,
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            product.name,
                                            style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ) ??
                                                const TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            product.sku,
                                            style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      fontSize: 13,
                                                      color: Colors.grey[500],
                                                    ) ??
                                                TextStyle(
                                                  fontSize: 13,
                                                  color: Colors.grey[500],
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          _formatCurrency(product.price),
                                          style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.black87,
                                                  ) ??
                                              const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.black87,
                                              ),
                                        ),
                                        const SizedBox(height: 2),
                                        Icon(Icons.arrow_forward_ios,
                                            size: 12, color: Colors.grey[300]),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                  if (hasQuery)
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(color: Colors.grey[100]!),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _results.isEmpty && !_isLoading
                                  ? 'Presiona Enter para buscar en el catálogo'
                                  : 'Ver todos los resultados en el catálogo',
                              style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Colors.grey[600]) ??
                                  TextStyle(color: Colors.grey[600]),
                            ),
                          ),
                          TextButton(
                            onPressed: () => _goToCatalogSearch(currentQuery),
                            child: const Text('Ver todos'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
