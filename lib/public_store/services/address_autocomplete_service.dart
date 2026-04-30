import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class AddressSuggestion {
  final String placeId;
  final String description;

  const AddressSuggestion({required this.placeId, required this.description});
}

class ResolvedAddress {
  final String formattedAddress;
  final String street;
  final String? streetNumber;
  final String? apartment;
  final String comuna;
  final String city;
  final String region;
  final String? postalCode;
  final double? latitude;
  final double? longitude;

  const ResolvedAddress({
    required this.formattedAddress,
    required this.street,
    this.streetNumber,
    this.apartment,
    required this.comuna,
    required this.city,
    required this.region,
    this.postalCode,
    this.latitude,
    this.longitude,
  });

  String formatForDisplay() {
    final parts = <String>[
      street,
      if (streetNumber != null && streetNumber!.isNotEmpty) streetNumber!,
      if (apartment != null && apartment!.isNotEmpty) apartment!,
      comuna,
      city,
      region,
    ];
    return parts.where((part) => part.isNotEmpty).join(', ');
  }
}

class AddressAutocompleteService extends ChangeNotifier {
  AddressAutocompleteService();

  final SupabaseClient _supabase = Supabase.instance.client;
  final Uuid _uuid = const Uuid();

  String? _tenantId;
  bool _isInitialized = false;
  bool _isEnabled = false;
  String? _sessionToken;

  bool get isEnabled => _isEnabled;
  String get sessionToken => _sessionToken ??= _uuid.v4();

  Future<void> initialize({String? tenantId}) async {
    if (_isInitialized && (tenantId == null || tenantId == _tenantId)) return;

    try {
      final scopedTenantId = tenantId?.trim();
      if (scopedTenantId == null || scopedTenantId.isEmpty) {
        _tenantId = null;
        _isEnabled = false;
        return;
      }

      final response = await _supabase.functions.invoke(
        'google-places-proxy',
        body: {
          'action': 'status',
          'tenantId': scopedTenantId,
        },
      );

      final data = response.data is Map<String, dynamic>
          ? response.data as Map<String, dynamic>
          : <String, dynamic>{};

      _tenantId = scopedTenantId;
      _isEnabled = response.status == 200 && data['enabled'] == true;
    } catch (error) {
      debugPrint('AddressAutocompleteService.init error: $error');
      _tenantId = tenantId;
      _isEnabled = false;
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<List<AddressSuggestion>> fetchSuggestions(String query) async {
    if (!_isInitialized) {
      await initialize(tenantId: _tenantId);
    }

    if (!_isEnabled || query.trim().length < 3 || _tenantId == null) {
      return [];
    }

    try {
      // Use Supabase Edge Function as proxy to avoid CORS issues
      final response = await _supabase.functions.invoke(
        'google-places-proxy',
        body: {
          'action': 'autocomplete',
          'input': query,
          'sessionToken': sessionToken,
          'tenantId': _tenantId,
        },
      );

      if (response.status != 200) {
        debugPrint('Google Places proxy error: ${response.data}');
        return [];
      }

      final data = response.data as Map<String, dynamic>;
      final status = data['status'] as String?;

      if (status != 'OK') {
        debugPrint(
            'Google Places status: $status - ${data['error_message'] ?? ''}');
        return [];
      }

      final predictions = data['predictions'] as List<dynamic>? ?? [];
      return predictions
          .map((raw) => AddressSuggestion(
                placeId: raw['place_id'] as String,
                description: raw['description'] as String,
              ))
          .toList();
    } catch (error) {
      debugPrint('Google Places autocomplete error: $error');
      return [];
    }
  }

  Future<ResolvedAddress?> resolvePlace(String placeId) async {
    if (!_isInitialized) {
      await initialize(tenantId: _tenantId);
    }

    if (!_isEnabled || _tenantId == null) return null;

    try {
      // Use Supabase Edge Function as proxy to avoid CORS issues
      final response = await _supabase.functions.invoke(
        'google-places-proxy',
        body: {
          'action': 'details',
          'placeId': placeId,
          'sessionToken': sessionToken,
          'tenantId': _tenantId,
        },
      );

      if (response.status != 200) {
        debugPrint('Google Places proxy error: ${response.data}');
        return null;
      }

      final data = response.data as Map<String, dynamic>;
      final status = data['status'] as String?;

      if (status != 'OK') {
        debugPrint('Google Places detail status: $status');
        return null;
      }

      final result = data['result'] as Map<String, dynamic>;
      final components = result['address_components'] as List<dynamic>? ?? [];

      String? getComponent(String type) {
        try {
          return components.firstWhere((component) {
            final types = (component['types'] as List<dynamic>).cast<String>();
            return types.contains(type);
          })['long_name']?.toString();
        } catch (_) {
          return null;
        }
      }

      final street = getComponent('route') ?? '';
      final number = getComponent('street_number');
      final apartment = getComponent('subpremise') ?? getComponent('premise');
      final comuna = getComponent('administrative_area_level_3') ??
          getComponent('locality') ??
          getComponent('sublocality_level_1') ??
          getComponent('sublocality') ??
          '';
      final city = getComponent('administrative_area_level_2') ??
          getComponent('locality') ??
          comuna;
      final region = getComponent('administrative_area_level_1') ?? '';
      final postalCode = getComponent('postal_code');

      final geometry = result['geometry'] as Map<String, dynamic>?;
      final location = geometry?['location'] as Map<String, dynamic>?;

      return ResolvedAddress(
        formattedAddress:
            (result['formatted_address'] as String?)?.trim() ?? '',
        street: street,
        streetNumber: number,
        apartment: apartment,
        comuna: comuna,
        city: city,
        region: region,
        postalCode: postalCode,
        latitude: (location?['lat'] as num?)?.toDouble(),
        longitude: (location?['lng'] as num?)?.toDouble(),
      );
    } catch (error) {
      debugPrint('Google Places details error: $error');
      return null;
    }
  }

  void resetSessionToken() {
    _sessionToken = _uuid.v4();
  }
}
