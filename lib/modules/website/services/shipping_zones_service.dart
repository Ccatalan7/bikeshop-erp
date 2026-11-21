import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/services/tenant_service.dart';
import '../models/shipping_zone.dart';

abstract interface class ShippingZonesStore {
  Future<List<ShippingZone>> load();

  /// Replaces every zone in one transaction and answers what was saved.
  Future<List<ShippingZone>> save(List<ShippingZone> zones);

  /// The categories that ship as a bicycle and the ones to choose from.
  Future<ShippingBikeCategories> loadBikeCategories();

  /// Replaces the categories that ship as a bicycle.
  Future<Set<String>> saveBikeCategories(Set<String> categoryIds);
}

/// The store's shipping zones, through the commands the checkout's quote
/// reads (`online_shipping_zones_for_editor`, `save_online_shipping_zones`).
class ShippingZonesService implements ShippingZonesStore {
  ShippingZonesService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  List<ShippingZone> _parse(Object? response) => [
        if (response is List)
          for (final zone in response.whereType<Map>())
            ShippingZone.fromJson(Map<String, dynamic>.from(zone)),
      ];

  @override
  Future<List<ShippingZone>> load() async =>
      _parse(await _client.rpc('online_shipping_zones_for_editor'));

  @override
  Future<List<ShippingZone>> save(List<ShippingZone> zones) async => _parse(
        await _client.rpc(
          'save_online_shipping_zones',
          params: {
            'p_zones': [for (final zone in zones) zone.toJson()],
          },
        ),
      );

  Set<String> _ids(Object? response) => {
        if (response is List)
          for (final row in response.whereType<Map>())
            if (row['id'] != null) row['id'].toString(),
      };

  @override
  Future<ShippingBikeCategories> loadBikeCategories() async {
    final tenantId = await TenantService().getTenantId();
    if (tenantId == null || tenantId.isEmpty) {
      throw StateError('No se pudo resolver el taller.');
    }
    final Future<Object?> categories = _client
        .from('product_categories')
        .select('id, name, full_path, level')
        .eq('tenant_id', tenantId)
        .eq('is_active', true)
        .order('full_path');
    final Future<Object?> marked =
        _client.rpc('online_shipping_bike_categories_for_editor');
    final results = await Future.wait<Object?>([categories, marked]);
    final rows = results[0];
    return (
      options: [
        if (rows is List)
          for (final row in rows.whereType<Map>())
            (
              id: row['id'].toString(),
              path: (row['full_path'] ?? row['name'] ?? '').toString(),
              level: (row['level'] as num?)?.toInt() ?? 0,
            ),
      ],
      selected: _ids(results[1]),
    );
  }

  @override
  Future<Set<String>> saveBikeCategories(Set<String> categoryIds) async =>
      _ids(await _client.rpc(
        'save_online_shipping_bike_categories_v1',
        params: {'p_category_ids': categoryIds.toList()},
      ));
}
