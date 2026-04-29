import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../../modules/website/services/website_service.dart';
import '../../shared/utils/web_url.dart';
import '../providers/public_store_tenant_provider.dart';

/// SIMPLE bootstrap widget for public store
///
/// This is how Shopify/Wix/etc work:
/// 1. Detect tenant from URL (ONE TIME)
/// 2. Load all data in parallel (ONE TIME)
/// 3. Show child when ready
///
/// NO complex state management. NO multiple loading triggers.
/// Progressive boot: detect tenant first, then render immediately.
class PublicStoreBootstrap extends StatefulWidget {
  final Widget child;

  const PublicStoreBootstrap({super.key, required this.child});

  @override
  State<PublicStoreBootstrap> createState() => _PublicStoreBootstrapState();
}

class _PublicStoreBootstrapState extends State<PublicStoreBootstrap> {
  bool _splashHidden = false;
  bool _isBootstrapping = true;
  bool _hasTenant = false;
  String? _error;
  bool _bootstrapStarted = false;

  @override
  void initState() {
    super.initState();

    // Let Flutter paint first, then schedule bootstrap on the next task.
    // This avoids provider `notifyListeners()` running inside a build scope.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Timer.run(() {
        if (!mounted) return;
        _hideHtmlSplash();
        unawaited(_bootstrap());
      });
    });
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
        return;
      }

      // Step 2: Pre-populate from fresh sync cache for faster first paint.
      final didPreloadFromCache =
          websiteService.preloadPublicStoreFromSynchronousCache(tenantId);

      // Step 3: Allow the app to render immediately after tenant detection.
      setState(() {
        _isBootstrapping = false;
        _hasTenant = true;
        _error = null;
      });

      // Step 4: Load blocks/settings from network in the background.
      // Pages can render progressively using defaults/cache until data arrives.
      unawaited(() async {
        try {
          // Give the first frames a chance to render smoothly before doing
          // DNS/TLS/JSON work on the UI isolate.
          unawaited(websiteService.warmUpEdgeCacheHost());
          await Future<void>.delayed(
            didPreloadFromCache
                ? const Duration(milliseconds: 450)
                : const Duration(milliseconds: 150),
          );

          if (didPreloadFromCache) {
            await websiteService.loadPublicStoreDataUnified(
              tenantId,
              forceRefresh: true,
            );
            return;
          }

          await websiteService.loadPublicStoreDataUnified(tenantId);

          unawaited(() async {
            try {
              await Future<void>.delayed(const Duration(milliseconds: 250));
              await websiteService.loadPublicStoreDataUnified(
                tenantId,
                forceRefresh: true,
              );
            } catch (e) {
              debugPrint('⚠️ [Bootstrap] Origin revalidation failed: $e');
            }
          }());
        } catch (e) {
          debugPrint('⚠️ [Bootstrap] Network load failed: $e');
        }
      }());
    } catch (e) {
      setState(() {
        _isBootstrapping = false;
        _hasTenant = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // While bootstrapping (tenant detection), render the app shell immediately.
    // Pages can show their own progressive loading states.
    if (_isBootstrapping && !_hasTenant) {
      return widget.child;
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
