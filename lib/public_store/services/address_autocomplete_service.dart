import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
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
  AddressAutocompleteService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final SupabaseClient _supabase = Supabase.instance.client;
  final http.Client _httpClient;
  final Uuid _uuid = const Uuid();

  String? _apiKey;
  bool _isInitialized = false;
  bool _isEnabled = false;
  String? _sessionToken;

  bool get isEnabled => _isEnabled;
  String get sessionToken => _sessionToken ??= _uuid.v4();

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final response = await _supabase
          .from('website_settings')
          .select('value')
          .eq('key', 'google_places_api_key')
          .maybeSingle();

      _apiKey = (response?['value'] as String?)?.trim();
      _isEnabled = _apiKey != null && _apiKey!.isNotEmpty;
    } catch (error) {
      debugPrint('AddressAutocompleteService.init error: $error');
      _isEnabled = false;
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  Future<List<AddressSuggestion>> fetchSuggestions(String query) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (!_isEnabled || query.trim().length < 3) {
      return [];
    }

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/autocomplete/json',
      {
        'input': query,
        'types': 'address',
        'components': 'country:cl',
        'language': 'es',
        'sessiontoken': sessionToken,
        'key': _apiKey!,
      },
    );

    final response = await _httpClient.get(uri);

    if (response.statusCode != 200) {
      debugPrint('Google Places autocomplete error: ${response.body}');
      return [];
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final status = data['status'] as String?;

    if (status != 'OK') {
      debugPrint('Google Places status: $status');
      return [];
    }

    final predictions = data['predictions'] as List<dynamic>;
    return predictions
        .map((raw) => AddressSuggestion(
              placeId: raw['place_id'] as String,
              description: raw['description'] as String,
            ))
        .toList();
  }

  Future<ResolvedAddress?> resolvePlace(String placeId) async {
    if (!_isInitialized) {
      await initialize();
    }

    if (!_isEnabled) return null;

    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/details/json',
      {
        'place_id': placeId,
        'fields': 'formatted_address,address_component,geometry',
        'language': 'es',
        'sessiontoken': sessionToken,
        'key': _apiKey!,
      },
    );

    final response = await _httpClient.get(uri);

    if (response.statusCode != 200) {
      debugPrint('Google Places details error: ${response.body}');
      return null;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
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
      formattedAddress: (result['formatted_address'] as String?)?.trim() ?? '',
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
  }

  void resetSessionToken() {
    _sessionToken = _uuid.v4();
  }
}
