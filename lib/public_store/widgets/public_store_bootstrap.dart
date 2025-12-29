import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../../modules/website/services/website_service.dart';
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
  bool _isLoadedSync = false;

  @override
  void initState() {
    super.initState();
    _initFuture = _initialize();
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
      return false; // No tenant found
    }

    // Step 2: Try SYNCHRONOUS CACHE first (Instant Header)
    // This allows us to render in the VERY FIRST FRAME if data is available
    if (websiteService.loadSettingsFromSynchronousCache(tenantId)) {
      if (mounted) {
        setState(() {
          _isLoadedSync = true;
        });
      }
    }

    // Step 3: Trigger network refresh in background
    // If we have cache, we don't await this (UI renders now).
    final networkLoad = websiteService.loadPublicStoreDataUnified(tenantId);

    if (_isLoadedSync) {
      // Unblock UI immediately!
      networkLoad.catchError((e) {
        debugPrint('⚠️ [Bootstrap] Background network refresh failed: $e');
      });
      return true;
    } else {
      // First time load: must wait for network
      await networkLoad;
      return true;
    }
  }

  @override
  Widget build(BuildContext context) {
    // If loaded synchronously, show child IMMEDIATELY (no FutureBuilder overhead)
    if (_isLoadedSync) {
      return widget.child;
    }

    return FutureBuilder<bool>(
      future: _initFuture,
      builder: (context, snapshot) {
        // Still loading
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
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
