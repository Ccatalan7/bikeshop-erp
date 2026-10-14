import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/shipping_zone.dart';

abstract interface class ShippingZonesStore {
  Future<List<ShippingZone>> load();

  /// Replaces every zone in one transaction and answers what was saved.
  Future<List<ShippingZone>> save(List<ShippingZone> zones);
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
}
