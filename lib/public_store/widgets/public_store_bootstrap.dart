import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../../modules/website/services/website_service.dart';
import '../../shared/utils/web_url.dart';
import '../providers/cart_provider.dart';
import '../providers/public_store_tenant_provider.dart';
import '../services/meta_pixel_service.dart';
import '../services/public_inventory_service.dart';

/// Initializes the durable cart scope for a storefront tenant.
///
/// This is the single composition-root adapter between [CartProvider] and
/// [PublicInventoryService]. Keeping the authoritative catalog loader here
/// prevents the standalone storefront and the ERP-mounted storefront from
/// drifting into different restore semantics.
Future<void> restorePublicStoreCart(
  BuildContext context, {
  required String tenantId,
}) {
  return restorePublicStoreCartForTenant(
    cartProvider: context.read<CartProvider>(),
    inventoryService: context.read<PublicInventoryService>(),
    tenantId: tenantId,
  );
}

Future<void> restorePublicStoreCartForTenant({
  required CartProvider cartProvider,
  required PublicInventoryService inventoryService,
  required String tenantId,
}) async {
  final normalizedTenantId = tenantId.trim();
  if (normalizedTenantId.isEmpty) return;

  await cartProvider.restore(
    tenantId: normalizedTenantId,
    loadProducts: (productIds) async {
      if (productIds.isEmpty) return const [];
      final page = await inventoryService.getProductPageForTenant(
        tenantId: normalizedTenantId,
        productIds: productIds,
        onlyInStock: false,
        limit: productIds.length,
      );
      return page.products;
    },
  );
}

/// SIMPLE bootstrap widget for public store
///
/// This is how Shopify/Wix/etc work:
/// 1. Detect tenant from URL (ONE TIME)
/// 2. Load all data in parallel (ONE TIME)
/// 3. Show child when ready
///
/// NO complex state management. NO multiple loading triggers.
/// Progressive boot: detect tenant first, preload the public navigation, then
/// reveal the storefront. Rendering the shell before navigation is ready leaks
/// the hardcoded fallback menu for a frame.
class PublicStoreBootstrap extends StatefulWidget {
  final Widget child;

  const PublicStoreBootstrap({super.key, required this.child});

  @override
  State<PublicStoreBootstrap> createState() => _PublicStoreBootstrapState();
}

class _PublicStoreBootstrapState extends State<PublicStoreBootstrap>
    with WidgetsBindingObserver {
  bool _splashHidden = false;
  bool _isBootstrapping = true;
  bool _hasTenant = false;
  String? _error;
  bool _bootstrapStarted = false;
  Timer? _freshnessTimer;
  DateTime? _lastInventoryFreshnessPulse;
  DateTime? _lastWebsiteFreshnessPulse;
  bool _freshnessRefreshActive = false;
  bool _isForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Let Flutter paint first, then schedule bootstrap on the next task.
    // This avoids provider `notifyListeners()` running inside a build scope.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Timer.run(() {
        if (!mounted) return;
        unawaited(_bootstrap());
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _freshnessTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    if (_isForeground) {
      unawaited(_refreshActiveStorefront(onResume: true));
    }
  }

  void _hideHtmlSplash() {
    if (_splashHidden) return;
    _splashHidden = true;
    if (kIsWeb) {
      try {
        hideHtmlLoadingScreen();
      } catch (_) {}
    }
  }

  Future<void> _bootstrap() async {
    if (_bootstrapStarted) return;
    _bootstrapStarted = true;

    setState(() {
      _isBootstrapping = true;
      _hasTenant = false;
      _error = null;
    });

    final tenantProvider = context.read<PublicStoreTenantProvider>();
    final websiteService = context.read<WebsiteService>();
    final inventoryService = context.read<PublicInventoryService>();

    try {
      // Step 1: Detect tenant
      if (!tenantProvider.hasTenant) {
        await tenantProvider.detectTenant();
      }

      final tenantId = tenantProvider.tenantId;
      if (tenantId == null || tenantId.isEmpty) {
        setState(() {
          _isBootstrapping = false;
          _hasTenant = false;
          _error = tenantProvider.error ?? 'Tienda no encontrada';
        });
        _hideHtmlSplashAfterFrame();
        return;
      }

      // Category publication is a public-navigation eligibility boundary, not
      // merely catalog decoration. Start this preflight alongside the website
      // load so the first visible header never offers category destinations
      // before `show_on_website` can classify them.
      final categoryPublicationPreflight =
          inventoryService.getCategoriesForTenant(tenantId: tenantId);
      final pagePublicationPreflight = websiteService.loadPagesForTenant(
        tenantId,
        rethrowErrors: true,
      );

      // Step 2: Pre-populate from fresh sync cache for faster first paint.
      final didPreloadFromCache =
          websiteService.preloadPublicStoreFromSynchronousCache(tenantId);
      _configureMetaPixel(websiteService);

      // Start the heavier store-data load immediately. The shell only waits for
      // navigation below, so settings/blocks are already in flight by the time
      // the first visible Flutter frame is ready.
      unawaited(_loadStoreDataInBackground(
        websiteService,
        tenantId,
        didPreloadFromCache: didPreloadFromCache,
      ));

      // Old authenticated storefront sessions may have cached an empty
      // navigation response from before the public RLS policy allowed them to
      // read website_navigation. Do not let that stale cache render the
      // fallback header; fetch the real nav once before first store paint.
      if (!websiteService.hasVisibleHeaderNavigation) {
        try {
          await websiteService.loadNavigationForTenant(
            tenantId,
            notify: false,
            forceRefresh: true,
          );
        } catch (e) {
          debugPrint('⚠️ [Bootstrap] Navigation preflight failed: $e');
        }
      }

      try {
        await categoryPublicationPreflight;
      } catch (e) {
        // With no retained snapshot the navigation projection fails closed for
        // categories while preserving ordinary page/action destinations.
        debugPrint('⚠️ [Bootstrap] Category publication preflight failed: $e');
      }
      try {
        await pagePublicationPreflight;
      } catch (e) {
        // Editor-owned page destinations fail closed until an origin read
        // confirms their current publication state.
        debugPrint('⚠️ [Bootstrap] Page publication preflight failed: $e');
      }

      // Bring back a basket the visitor left behind. Revalidated against the
      // live catalog, so it never restores a price or a quantity the shop can
      // no longer honour. Off the critical path: the shell must not wait on it.
      unawaited(_restoreSavedCart(tenantId));

      // Step 3: Allow the app to render immediately after tenant detection.
      setState(() {
        _isBootstrapping = false;
        _hasTenant = true;
        _error = null;
      });
      _startFreshnessMonitoring();
      _hideHtmlSplashAfterFrame();
    } catch (e) {
      setState(() {
        _isBootstrapping = false;
        _hasTenant = false;
        _error = e.toString();
      });
      _hideHtmlSplashAfterFrame();
    }
  }

  void _startFreshnessMonitoring() {
    _lastInventoryFreshnessPulse ??= DateTime.now();
    _lastWebsiteFreshnessPulse ??= DateTime.now();
    _freshnessTimer ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_refreshActiveStorefront()),
    );
  }

  Future<void> _refreshActiveStorefront({bool onResume = false}) async {
    if (!mounted || !_hasTenant || !_isForeground || _freshnessRefreshActive) {
      return;
    }
    final tenantId =
        context.read<PublicStoreTenantProvider>().tenantId?.trim() ?? '';
    if (tenantId.isEmpty) return;
    final inventory = context.read<PublicInventoryService>();
    final websiteService = context.read<WebsiteService>();

    final now = DateTime.now();
    final inventoryAge = _lastInventoryFreshnessPulse == null
        ? const Duration(days: 1)
        : now.difference(_lastInventoryFreshnessPulse!);
    final websiteAge = _lastWebsiteFreshnessPulse == null
        ? const Duration(days: 1)
        : now.difference(_lastWebsiteFreshnessPulse!);
    final inventoryDue = inventoryAge >= Duration(seconds: onResume ? 8 : 30);
    final websiteDue = websiteAge >= Duration(seconds: onResume ? 15 : 60);
    if (!inventoryDue && !websiteDue) return;

    _freshnessRefreshActive = true;
    try {
      if (inventoryDue) {
        _lastInventoryFreshnessPulse = now;
        inventory.markCacheStale(tenantId: tenantId);
        // Refresh the category-publication snapshot as part of the same pulse.
        // Product pages keep their own SWR loaders, while the shared shell
        // needs this answer to update every navigation surface.
        await inventory.getCategoriesForTenant(tenantId: tenantId);
      }
      if (websiteDue) {
        _lastWebsiteFreshnessPulse = now;
        try {
          await Future.wait([
            websiteService.loadPublicStoreDataUnified(
              tenantId,
              forceRefresh: true,
            ),
            websiteService.loadPagesForTenant(
              tenantId,
              rethrowErrors: true,
            ),
          ]);
        } finally {
          // Unified data owns settings/navigation/home blocks. The page list
          // owns which editor pages may appear anywhere in public navigation,
          // while route-owned CMS pages revalidate their joined page+blocks
          // projection only when active.
          websiteService.requestActiveCmsPageOriginRevalidation();
        }
      }
    } catch (error) {
      debugPrint('⚠️ [Bootstrap] Background freshness check failed: $error');
    } finally {
      _freshnessRefreshActive = false;
    }
  }

  Future<void> _restoreSavedCart(String tenantId) async {
    try {
      await restorePublicStoreCart(context, tenantId: tenantId);
    } catch (error) {
      debugPrint('⚠️ [Bootstrap] Cart restore failed: $error');
    }
  }

  Future<void> _loadStoreDataInBackground(
    WebsiteService websiteService,
    String tenantId, {
    required bool didPreloadFromCache,
  }) async {
    try {
      unawaited(websiteService.warmUpEdgeCacheHost());

      if (didPreloadFromCache) {
        await websiteService.loadPublicStoreDataUnified(
          tenantId,
          forceRefresh: true,
        );
        _configureMetaPixel(websiteService);
        return;
      }

      await websiteService.loadPublicStoreDataUnified(tenantId);
      _configureMetaPixel(websiteService);

      // The fast path may use prefetch/edge cache. Keep the existing freshness
      // contract by following it with an origin read after first paint.
      try {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await websiteService.loadPublicStoreDataUnified(
          tenantId,
          forceRefresh: true,
        );
        _configureMetaPixel(websiteService);
      } catch (e) {
        debugPrint('⚠️ [Bootstrap] Origin revalidation failed: $e');
      }
    } catch (e) {
      debugPrint('⚠️ [Bootstrap] Network load failed: $e');
    }
  }

  void _configureMetaPixel(WebsiteService websiteService) {
    MetaPixelService.instance.initialize(
      websiteService.getSetting('seo_fb_pixel_id'),
    );
  }

  void _hideHtmlSplashAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _hideHtmlSplash();
    });
  }

  Widget _buildStartupScaffold() {
    return const ColoredBox(
      color: Colors.white,
      child: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keep the public shell hidden until tenant + navigation preflight finish.
    // Otherwise the layout briefly paints fallback header/footer links.
    if (_isBootstrapping && !_hasTenant) {
      return _buildStartupScaffold();
    }

    // Error or no tenant
    if (!_hasTenant) {
      final tenantProvider = context.read<PublicStoreTenantProvider>();
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.store_mall_directory,
                  size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                _error ?? tenantProvider.error ?? 'Tienda no encontrada',
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _bootstrapStarted = false;
                  });
                  _bootstrap();
                },
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    // Success - show the app (data loads progressively).
    return widget.child;
  }
}
