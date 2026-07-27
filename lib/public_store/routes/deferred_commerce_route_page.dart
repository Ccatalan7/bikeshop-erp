import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/public_store_tenant_provider.dart';
import 'deferred_commerce_routes.dart' deferred as commerce_routes;

/// Loads checkout/payment code only when the visitor enters the buying flow.
class DeferredCommerceRoutePage extends StatefulWidget {
  const DeferredCommerceRoutePage({
    super.key,
    required this.routeKey,
    this.orderId,
    this.paymentStatus,
  });

  final String routeKey;
  final String? orderId;
  final String? paymentStatus;

  @override
  State<DeferredCommerceRoutePage> createState() =>
      _DeferredCommerceRoutePageState();
}

class _DeferredCommerceRoutePageState extends State<DeferredCommerceRoutePage> {
  late Future<void> _libraryFuture;

  @override
  void initState() {
    super.initState();
    _libraryFuture = commerce_routes.loadLibrary();
  }

  void _retry() {
    setState(() {
      _libraryFuture = commerce_routes.loadLibrary();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tenantId = context.select<PublicStoreTenantProvider, String?>(
      (provider) => provider.tenantId,
    );

    return FutureBuilder<void>(
      future: _libraryFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No pudimos cargar el flujo de compra.'),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _retry,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
          );
        }

        return commerce_routes.buildCommerceRoutePage(
          routeKey: widget.routeKey,
          tenantId: tenantId,
          orderId: widget.orderId,
          paymentStatus: widget.paymentStatus,
        );
      },
    );
  }
}
