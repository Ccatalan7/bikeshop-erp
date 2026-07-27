import 'package:flutter/material.dart';

import 'deferred_customer_routes.dart' deferred as customer_routes;

/// Keeps customer-only screens out of the storefront's first JavaScript unit.
///
/// The public shell, header, theme, navigation and CMS renderer remain eager.
/// Visitors download this feature group only when they enter `/cuenta/**`.
class DeferredCustomerRoutePage extends StatefulWidget {
  const DeferredCustomerRoutePage({
    super.key,
    required this.routeKey,
    this.argument,
  });

  final String routeKey;
  final String? argument;

  static Future<void>? _preloadFuture;

  /// Starts downloading the account route unit as soon as navigation intent
  /// is known. It remains deferred, so first storefront paint is unaffected.
  static Future<void> preload() {
    return _preloadFuture ??= customer_routes.loadLibrary().catchError((error) {
      _preloadFuture = null;
      throw error;
    });
  }

  @override
  State<DeferredCustomerRoutePage> createState() =>
      _DeferredCustomerRoutePageState();
}

class _DeferredCustomerRoutePageState extends State<DeferredCustomerRoutePage> {
  late Future<void> _libraryFuture;

  @override
  void initState() {
    super.initState();
    _libraryFuture = DeferredCustomerRoutePage.preload();
  }

  void _retry() {
    setState(() {
      _libraryFuture = DeferredCustomerRoutePage.preload();
    });
  }

  @override
  Widget build(BuildContext context) {
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
                  const Text('No pudimos cargar esta sección.'),
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

        return customer_routes.buildCustomerRoutePage(
          routeKey: widget.routeKey,
          argument: widget.argument,
        );
      },
    );
  }
}
