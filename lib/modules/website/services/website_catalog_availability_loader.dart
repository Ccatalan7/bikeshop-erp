import 'package:supabase_flutter/supabase_flutter.dart';

typedef WebsiteCatalogAvailabilityBatchRequest = Future<dynamic> Function(
  String tenantId,
  List<String> productIds,
);

/// Loads the reservation-aware availability used by the public storefront.
///
/// The database contract accepts at most 500 product IDs per call. Keeping the
/// batching here prevents management workspaces from silently falling back to
/// raw set-header stock when the ERP catalog grows beyond one PostgREST page.
class WebsiteCatalogAvailabilityLoader {
  WebsiteCatalogAvailabilityLoader(SupabaseClient client)
      : _requestBatch = ((tenantId, productIds) async {
          return await client.rpc(
            'get_product_available_quantities',
            params: {
              'p_tenant_id': tenantId,
              'p_product_ids': productIds,
            },
          );
        });

  WebsiteCatalogAvailabilityLoader.forTesting(this._requestBatch);

  static const int maxBatchSize = 500;

  final WebsiteCatalogAvailabilityBatchRequest _requestBatch;

  Future<Map<String, int>> load({
    required String tenantId,
    required Iterable<String> productIds,
  }) async {
    final normalizedTenantId = tenantId.trim();
    if (normalizedTenantId.isEmpty) {
      throw ArgumentError.value(tenantId, 'tenantId', 'Tenant is required.');
    }

    final normalizedIds = <String>{};
    for (final rawId in productIds) {
      final id = rawId.trim();
      if (id.isNotEmpty) normalizedIds.add(id);
    }
    if (normalizedIds.isEmpty) return const {};

    final ids = normalizedIds.toList(growable: false);
    final availabilityByProductId = <String, int>{};
    for (var start = 0; start < ids.length; start += maxBatchSize) {
      final proposedEnd = start + maxBatchSize;
      final end = proposedEnd < ids.length ? proposedEnd : ids.length;
      final batch = ids.sublist(start, end);
      final response = await _requestBatch(normalizedTenantId, batch);
      if (response is! List) {
        throw const FormatException(
          'Unexpected public availability response shape.',
        );
      }

      final returnedIds = <String>{};
      for (final rawRow in response) {
        if (rawRow is! Map) {
          throw const FormatException(
            'Unexpected public availability row shape.',
          );
        }
        final row = Map<String, dynamic>.from(rawRow);
        final productId = row['product_id']?.toString().trim() ?? '';
        final quantity = row['available_quantity'];
        if (productId.isEmpty || quantity is! num) {
          throw const FormatException(
            'Incomplete public availability row.',
          );
        }
        if (!batch.contains(productId) || !returnedIds.add(productId)) {
          throw const FormatException(
            'Unexpected product in public availability response.',
          );
        }
        availabilityByProductId[productId] = quantity.toInt();
      }

      if (returnedIds.length != batch.length) {
        throw StateError(
          'No se pudo calcular la disponibilidad pública de '
          '${batch.length - returnedIds.length} productos.',
        );
      }
    }

    return Map.unmodifiable(availabilityByProductId);
  }

  static void applyToRows({
    required List<Map<String, dynamic>> rows,
    required Map<String, int> availabilityByProductId,
  }) {
    for (final row in rows) {
      final productId = row['id']?.toString().trim() ?? '';
      final availability = availabilityByProductId[productId];
      if (productId.isEmpty || availability == null) {
        throw StateError(
          'No se pudo reconciliar la disponibilidad pública del catálogo.',
        );
      }
      row['inventory_qty'] = availability;
      row['stock_quantity'] = availability;
    }
  }
}
