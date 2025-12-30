import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../../modules/website/services/website_service.dart';
import '../../shared/utils/web_url.dart';
import '../providers/public_store_tenant_provider.dart';
import '../services/public_inventory_service.dart';

/// SIMPLE bootstrap widget for public store
///
/// This is how Shopify/Wix/etc work:
/// 1. Detect tenant from URL (ONE TIME)
/// 2. Load all data in parallel (ONE TIME)
/// 3. Show child when ready
///
/// NO complex state management. NO multiple loading triggers.
/// Just a simple FutureBuilder pattern.
class PublicStoreBootstrap extends StatefulWidget {
  final Widget child;

  const PublicStoreBootstrap({super.key, required this.child});

  @override
  State<PublicStoreBootstrap> createState() => _PublicStoreBootstrapState();
}

class _PublicStoreBootstrapState extends State<PublicStoreBootstrap> {
  late Future<bool> _initFuture;
  bool _splashHidden = false;

  @override
  void initState() {
    super.initState();
    _initFuture = _initialize();
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

  Future<bool> _initialize() async {
    final tenantProvider = context.read<PublicStoreTenantProvider>();
    final websiteService = context.read<WebsiteService>();

    // Step 1: Detect tenant
    if (!tenantProvider.hasTenant) {
      await tenantProvider.detectTenant();
    }

    final tenantId = tenantProvider.tenantId;
    if (tenantId == null) {
      _hideHtmlSplash(); // Hide splash even on error
      return false; // No tenant found
    }

    // Step 2: Pre-populate settings from sync cache for faster header render
    // But DON'T hide splash yet - we still need to load blocks
    websiteService.loadSettingsFromSynchronousCache(tenantId);

    // Step 3: Load ALL data from network (settings + blocks)
    // Always await this to ensure blocks are loaded before showing content
    try {
      await websiteService.loadPublicStoreDataUnified(tenantId);
    } catch (e) {
      debugPrint('⚠️ [Bootstrap] Network load failed: $e');
    }

    // Step 4: NOW hide the splash - all data is loaded
    _hideHtmlSplash();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _initFuture,
      builder: (context, snapshot) {
        // Still loading - show NOTHING (HTML splash is still visible behind)
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }

        // Error or no tenant
        if (snapshot.hasError || snapshot.data != true) {
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
                    tenantProvider.error ?? 'Tienda no encontrada',
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _initFuture = _initialize();
                      });
                    },
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          );
        }

        // Success - show the app
        return widget.child;
      },
    );
  }
}
