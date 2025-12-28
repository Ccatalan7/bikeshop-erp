import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class GoogleBusinessService with ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoading = false;
  String? _error;

  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Trigger Google Sign-In with "business.manage" scope
  Future<void> connect() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Determines redirect URL based on platform
      String? redirectTo;
      if (kIsWeb) {
        redirectTo = Uri.base.toString(); // Return to current page (Editor)
      } else {
        redirectTo = 'io.supabase.vinabike://login-callback';
      }

      await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        scopes: 'https://www.googleapis.com/auth/business.manage',
        redirectTo: redirectTo,
        queryParams: {
          'access_type': 'offline', // Request refresh token
          'prompt': 'consent', // Force consent screen to ensure permissions
        },
      );

      // Note: The app will likely reload/redirect after this
    } catch (e) {
      _error = 'Error connecting to Google: $e';
      notifyListeners();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetch accounts and then locations
  Future<List<GoogleLocation>> fetchLocations() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final session = _supabase.auth.currentSession;
      if (session == null) throw Exception('No estÃ¡s autenticado');

      final token = session.providerToken;
      if (token == null) {
        throw Exception(
            'No se encontrÃ³ el token de Google. Por favor, desconecta y vuelve a conectar.');
      }

      // 1. Get Accounts
      // https://mybusinessaccountmanagement.googleapis.com/v1/accounts
      final accountsResp = await http.get(
        Uri.parse(
            'https://mybusinessaccountmanagement.googleapis.com/v1/accounts'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (accountsResp.statusCode != 200) {
        throw Exception('Error fetching accounts: ${accountsResp.body}');
      }

      final accountsData = jsonDecode(accountsResp.body);
      final accounts = (accountsData['accounts'] as List?) ?? [];

      if (accounts.isEmpty) {
        throw Exception(
            'No se encontraron cuentas de negocio asociadas a este correo.');
      }

      // 2. Get Locations for each account
      final List<GoogleLocation> allLocations = [];

      for (final account in accounts) {
        final accountName = account['name']; // e.g., "accounts/123456"

        // https://mybusinessbusinessinformation.googleapis.com/v1/{parent}/locations
        final locationsResp = await http.get(
          Uri.parse(
              'https://mybusinessbusinessinformation.googleapis.com/v1/$accountName/locations?readMask=name,title,storeCode,latlng,phoneNumbers,regularHours,categories,metadata,languageCode,serviceArea'),
          headers: {'Authorization': 'Bearer $token'},
        );

        if (locationsResp.statusCode == 200) {
          final locData = jsonDecode(locationsResp.body);
          final locations = (locData['locations'] as List?) ?? [];

          allLocations.addAll(locations.map((l) => GoogleLocation.fromJson(l)));
        } else {
          debugPrint(
              'Error getting locations for $accountName: ${locationsResp.body}');
        }
      }

      return allLocations;
    } catch (e) {
      _error = e.toString();
      debugPrint(_error);
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Fetch reviews for a specific location
  /// Uses the v4 API (still the standard for reviews as of 2024/2025)
  Future<List<Map<String, dynamic>>> fetchReviews(String locationName) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final session = _supabase.auth.currentSession;
      if (session == null) throw Exception('No estás autenticado');

      final token = session.providerToken;
      if (token == null) throw Exception('No token');

      // Note: locationName is like "accounts/X/locations/Y"
      // Endpoint: https://mybusiness.googleapis.com/v4/{name}/reviews
      final url = 'https://mybusiness.googleapis.com/v4/$locationName/reviews';

      final response = await http.get(
        Uri.parse(url),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode != 200) {
        throw Exception('Error fetching reviews: ${response.body}');
      }

      final data = jsonDecode(response.body);
      final reviews = (data['reviews'] as List?) ?? [];

      return reviews.map((r) => r as Map<String, dynamic>).toList();
    } catch (e) {
      _error = 'Error fetching reviews: $e';
      debugPrint(_error);
      notifyListeners();
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}

class GoogleLocation {
  final String name; // Resource name "locations/..."
  final String title;
  final String? phone;
  final double? lat;
  final double? lng;
  final String? addressLine; // Simplified
  final Map<String, dynamic>? hours;

  GoogleLocation({
    required this.name,
    required this.title,
    this.phone,
    this.lat,
    this.lng,
    this.addressLine,
    this.hours,
  });

  factory GoogleLocation.fromJson(Map<String, dynamic> json) {
    // Helper to extract phone
    String? phone;
    if (json['phoneNumbers'] != null) {
      phone = json['phoneNumbers']['primaryPhone'];
    }

    // Helper to extract lat/lng
    double? lat, lng;
    if (json['latlng'] != null) {
      lat = (json['latlng']['latitude'] as num?)?.toDouble();
      lng = (json['latlng']['longitude'] as num?)?.toDouble();
    }

    return GoogleLocation(
      name: json['name'] ?? '',
      title: json['title'] ?? 'Sin título',
      phone: phone,
      lat: lat,
      lng: lng,
      addressLine: json.toString(), // Store full debug/raw for now? Or parse?
      // Parsing address is complex (PostalAddress object).
      // We'll simplisticly store the raw JSON in hours/metadata for extraction later
      hours: json['regularHours'],
    );
  }
}
