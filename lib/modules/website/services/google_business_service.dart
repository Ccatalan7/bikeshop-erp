import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// ignore: avoid_web_libraries_in_flutter
import 'package:web/web.dart'
    if (dart.library.io) 'google_business_service_stub.dart' as web;

class GoogleBusinessService with ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isLoading = false;
  String? _error;

  StreamSubscription<AuthState>? _authSub;
  bool _notifyScheduled = false;
  String? _lastProviderToken;
  List<String>? _lastIdentityProviders;

  static const _kWebReturnToEditorKey = 'google_oauth_return_to_editor';
  static const _kWebReturnToPathKey = 'google_oauth_return_path';
  static const _kWebOpenIntegrationsKey = 'google_oauth_open_integrations';

  // Edge Function URL for proxying Google Business API calls (bypasses CORS on web)
  static const String _edgeFunctionUrl =
      'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/google-business-reviews';

  GoogleBusinessService() {
    _lastProviderToken = _supabase.auth.currentSession?.providerToken;
    _lastIdentityProviders =
        _supabase.auth.currentUser?.identities?.map((i) => i.provider).toList();

    // Keep UI in sync when OAuth returns and the session changes.
    _authSub = _supabase.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      final providerToken = session?.providerToken;
      final identityProviders =
          session?.user.identities?.map((i) => i.provider).toList();

      final tokenChanged = providerToken != _lastProviderToken;
      final identitiesChanged = (identityProviders ?? const <String>[]) !=
          (_lastIdentityProviders ?? const <String>[]);

      if (tokenChanged || identitiesChanged) {
        _lastProviderToken = providerToken;
        _lastIdentityProviders = identityProviders;
        _safeNotifyListeners();
      }
    });
  }

  void _safeNotifyListeners() {
    if (_notifyScheduled) return;

    final phase = SchedulerBinding.instance.schedulerPhase;
    final inFrame = phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks;

    if (inFrame) {
      _notifyScheduled = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _notifyScheduled = false;
        notifyListeners();
      });
      return;
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  void _debugSessionSnapshot(String context) {
    final session = _supabase.auth.currentSession;
    final user = _supabase.auth.currentUser;
    final provider = user?.appMetadata['provider'];
    final identities = user?.identities?.map((i) => i.provider).toList();

    final json = session?.toJson();
    final map = json is Map
        ? Map<String, dynamic>.from(json as Map<dynamic, dynamic>)
        : null;
    final hasProviderTokenJson = map?['provider_token'] != null;
    final hasProviderRefreshTokenJson = map?['provider_refresh_token'] != null;

    debugPrint(
        '🧾 [GoogleBusinessService] SessionSnapshot($context): provider=$provider, identities=$identities, hasProviderToken=${session?.providerToken != null}, hasProviderTokenJson=$hasProviderTokenJson, hasProviderRefreshTokenJson=$hasProviderRefreshTokenJson');
  }

  bool get isLoading => _isLoading;
  String? get error => _error;

  bool get isLinked {
    final user = _supabase.auth.currentUser;
    return user?.identities?.any((i) => i.provider == 'google') ?? false;
  }

  bool get hasProviderToken {
    return _supabase.auth.currentSession?.providerToken != null;
  }

  /// Best-effort: after OAuth returns, some web runtimes may need a short
  /// rehydration window before `provider_token` becomes available to the
  /// running app. This avoids requiring a manual hard refresh.
  Future<bool> ensureProviderToken(
      {Duration timeout = const Duration(seconds: 3)}) async {
    if (hasProviderToken) return true;

    final start = DateTime.now();
    while (DateTime.now().difference(start) < timeout) {
      try {
        await _supabase.auth.refreshSession();
      } catch (_) {
        // ignore; we'll retry briefly
      }

      if (hasProviderToken) {
        _safeNotifyListeners();
        return true;
      }

      await Future.delayed(const Duration(milliseconds: 150));
    }

    _debugSessionSnapshot('ensureProviderToken timeout');
    return false;
  }

  void clearError() {
    _error = null;
    _safeNotifyListeners();
  }

  String _toFriendlyGoogleApiError({
    required String action,
    required http.Response response,
  }) {
    final status = response.statusCode;
    final rawBody = response.body;

    Map<String, dynamic>? decoded;
    try {
      final json = jsonDecode(rawBody);
      if (json is Map) {
        decoded = Map<String, dynamic>.from(json);
      }
    } catch (_) {
      // ignore - fall back to raw body
    }

    final err = decoded?['error'];
    final errMap = err is Map ? Map<String, dynamic>.from(err) : null;
    final errMessage = (errMap?['message'] as String?)?.trim();
    final errStatus = (errMap?['status'] as String?)?.trim();

    if (status == 429 || errStatus == 'RESOURCE_EXHAUSTED') {
      String? quotaLimitValue;
      String? quotaMetric;
      String? service;

      final details = errMap?['details'];
      if (details is List) {
        for (final d in details) {
          if (d is Map &&
              d['@type'] == 'type.googleapis.com/google.rpc.ErrorInfo') {
            final metadata = d['metadata'];
            if (metadata is Map) {
              final md = Map<String, dynamic>.from(metadata);
              quotaLimitValue = md['quota_limit_value']?.toString();
              quotaMetric = md['quota_metric']?.toString();
              service = md['service']?.toString();
              break;
            }
          }
        }
      }

      // If quota limit is literally 0, this is almost always a configuration/
      // access problem (API not enabled/approved or quota not granted).
      if (quotaLimitValue == '0') {
        final serviceLabel = service ?? 'la API de Google Business Profile';
        return 'Google rechazó la solicitud por cuota=0 (429 RESOURCE_EXHAUSTED) en $serviceLabel.\n\n'
            'Esto NO es un problema de tu sesión: estás conectado, pero el proyecto de Google Cloud no tiene cuota habilitada para esa API.\n\n'
            'Acción en Google Cloud (proyecto del OAuth Client):\n'
            '1) APIs & Services → Enabled APIs: habilita “Business Profile Account Management API” (mybusinessaccountmanagement) y “Business Profile Business Information API” (mybusinessbusinessinformation).\n'
            '2) APIs & Services → Quotas: busca “Requests per minute per project” y verifica que no esté en 0. Si está bloqueado, solicita aumento de cuota.\n\n'
            'Detalle: ${errMessage ?? 'Quota limit 0'}';
      }

      return 'Google está limitando las solicitudes (429).\n\n'
          'Espera 1–2 minutos y reintenta.\n'
          '${quotaMetric != null ? 'Métrica: $quotaMetric\n' : ''}'
          '${errMessage != null ? 'Detalle: $errMessage' : ''}';
    }

    if (status == 401) {
      return 'Google devolvió 401 (token inválido/expirado) al $action.\n\n'
          'Acción: pulsa “Autorizar Acceso” otra vez para renovar el token.';
    }

    if (status == 403) {
      return 'Google devolvió 403 (sin permisos) al $action.\n\n'
          'Este sync usa el scope restringido business.manage.\n'
          'Acción: asegúrate de estar en “Test users” del consentimiento OAuth o completa la verificación de Google.\n\n'
          'Detalle: ${errMessage ?? rawBody}';
    }

    // Fallback: show the best message we have.
    return 'Error al $action (HTTP $status): ${errMessage ?? rawBody}';
  }

  String _toFriendlyConnectError(Object error) {
    final raw = error.toString();
    final lower = raw.toLowerCase();

    // Supabase can disable manual identity linking at the project level.
    // In that case, linkIdentity() fails with:
    //   code: manual_linking_disabled
    if (lower.contains('manual_linking_disabled') ||
        lower.contains('manual linking is disabled')) {
      return 'Supabase tiene deshabilitado el enlace manual de identidades (manual_linking_disabled).\n\nPara usar “Conectar Cuenta Google” sin cambiar tu sesión, habilita el linking en: Supabase → Authentication → Settings (o Providers) → permite/enable “Manual linking / Link identities”.\n\nAlternativa: iniciar sesión en el ERP usando Google como método principal (si aplica).\n\nDetalle: $raw';
    }

    // Typical Google/Supabase OAuth misconfiguration errors
    if (lower.contains('invalid_client') ||
        lower.contains('client id') ||
        lower.contains('client_id') ||
        lower.contains('client secret') ||
        lower.contains('redirect_uri_mismatch') ||
        lower.contains('redirect uri') ||
        lower.contains('unauthorized_client')) {
      return 'Google OAuth no está configurado correctamente.\n\nVerifica en Supabase → Authentication → Providers → Google: habilitado + Client ID/Secret.\nLuego, en Google Cloud, crea el OAuth client y agrega los Redirect URLs de Supabase.\n\nDetalle: $raw';
    }

    // Restricted scope / consent screen issues
    if (lower.contains('access_denied') ||
        lower.contains('access blocked') ||
        lower.contains('acceso bloqueado') ||
        lower.contains('403')) {
      return 'Acceso bloqueado por Google (403).\n\nEste sync usa el scope restringido business.manage.\nSolución rápida (modo testing): agrega tu correo en Google Cloud → OAuth consent screen → Test users.\nPara uso público: completa la verificación de Google para ese scope.\n\nDetalle: $raw';
    }

    return 'Error conectando con Google: $raw';
  }

  /// Trigger Google Sign-In with "business.manage" scope
  Future<void> connect() async {
    _isLoading = true;
    _error = null;
    _safeNotifyListeners();

    try {
      // Determines redirect URL based on platform
      String? redirectTo;
      if (kIsWeb) {
        // Store a flag in localStorage so the app knows to re-enter edit mode
        // after OAuth redirect (Supabase may strip query params from callback)
        try {
          web.window.localStorage.setItem(_kWebReturnToEditorKey, 'true');
          debugPrint(
              '💾 [GoogleBusinessService] Saved edit mode flag to localStorage');

          // Also store the current route so the callback can bring the user
          // back to the Integraciones module instead of sending them to '/'
          // (which redirects to /dashboard on ERP hosts).
          final uri = Uri.base;
          final pathWithQuery =
              uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
          web.window.localStorage.setItem(_kWebReturnToPathKey, pathWithQuery);
          // Request opening Integraciones panel on return.
          web.window.localStorage.setItem(_kWebOpenIntegrationsKey, 'true');
          debugPrint(
              '💾 [GoogleBusinessService] Saved return path for OAuth: $pathWithQuery');
        } catch (e) {
          debugPrint(
              '⚠️ [GoogleBusinessService] Could not save to localStorage: $e');
        }

        // IMPORTANT:
        // Redirect back to a stable callback route to prevent the router from
        // immediately redirecting away from '/' and stripping the OAuth code.
        final origin = Uri.base.origin;
        redirectTo = '$origin/auth/callback';
        debugPrint('🔗 [GoogleBusinessService] OAuth redirectTo: $redirectTo');
      } else {
        redirectTo = 'io.supabase.vinabike://login-callback';
      }

      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('No estás autenticado');

      // Check if Google is already linked to this account
      final isLinked =
          user.identities?.any((i) => i.provider == 'google') ?? false;

      debugPrint(
          '🔍 [GoogleBusinessService] isLinked: $isLinked, calling OAuth...');

      final preSession = _supabase.auth.currentSession;
      final preUser = _supabase.auth.currentUser;
      final preProvider = preUser?.appMetadata['provider'];
      final preIdentityProviders =
          preUser?.identities?.map((i) => i.provider).toList();
      debugPrint(
          '🧾 [GoogleBusinessService] Pre-OAuth session: provider=$preProvider, identities=$preIdentityProviders, hasProviderToken=${preSession?.providerToken != null}, hasAccessToken=${preSession?.accessToken != null}');

      if (isLinked) {
        // If already linked, we must SignInWithOAuth to get the provider_token
        // This will refresh the session and include the token needed for APIs
        debugPrint(
            '🚀 [GoogleBusinessService] Calling signInWithOAuth (already linked)...');
        final result = await _supabase.auth.signInWithOAuth(
          OAuthProvider.google,
          scopes: 'https://www.googleapis.com/auth/business.manage',
          redirectTo: redirectTo,
          queryParams: {
            'access_type': 'offline',
            'prompt': 'consent',
          },
        );
        debugPrint(
            '✅ [GoogleBusinessService] signInWithOAuth returned: $result');
      } else {
        // If not linked, we try to link first
        debugPrint(
            '🚀 [GoogleBusinessService] Calling linkIdentity (not linked)...');
        try {
          final result = await _supabase.auth.linkIdentity(
            OAuthProvider.google,
            scopes: 'https://www.googleapis.com/auth/business.manage',
            redirectTo: redirectTo,
            queryParams: {
              'access_type': 'offline',
              'prompt': 'consent',
            },
          );
          debugPrint(
              '✅ [GoogleBusinessService] linkIdentity returned: $result');
        } catch (e) {
          debugPrint('⚠️ [GoogleBusinessService] linkIdentity error: $e');
          final msg = e.toString().toLowerCase();

          // If it says "already linked", it means we are good to sign in
          if (msg.contains('already linked') ||
              msg.contains('already_linked')) {
            debugPrint(
                '🔄 [GoogleBusinessService] Already linked, falling back to signInWithOAuth...');
            final result = await _supabase.auth.signInWithOAuth(
              OAuthProvider.google,
              scopes: 'https://www.googleapis.com/auth/business.manage',
              redirectTo: redirectTo,
              queryParams: {
                'access_type': 'offline',
                'prompt': 'consent',
              },
            );
            debugPrint(
                '✅ [GoogleBusinessService] signInWithOAuth (fallback) returned: $result');
            return;
          }

          // Otherwise rethrow to be caught by the main error handler
          // (This handles manual_linking_disabled, etc.)
          rethrow;
        }
      }

      // Note: The app will likely reload/redirect after this
    } catch (e) {
      _error = _toFriendlyConnectError(e);
      _safeNotifyListeners();
      return;
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  /// Fetch accounts and then locations
  Future<List<GoogleLocation>> fetchLocations() async {
    _isLoading = true;
    _error = null;
    _safeNotifyListeners();

    try {
      final session = _supabase.auth.currentSession;
      if (session == null) throw Exception('No estás autenticado');

      final token = session.providerToken;
      if (token == null) {
        _debugSessionSnapshot('fetchLocations_missingToken');
        throw Exception(
          'No se encontró un token de Google en tu sesión.'
          '\n\nEsto suele pasar cuando el callback de OAuth se pierde (por redirects) '
          'o cuando aún no se completó la autorización.'
          '\n\nAcción: pulsa "Autorizar Acceso" y completa el flujo. '
          'Si vuelves y sigue sin aparecer como autorizado, revisamos los logs.',
        );
      }

      Map<String, dynamic> accountsData;

      if (kIsWeb) {
        // On web, use Edge Function to bypass CORS
        final resp = await http.post(
          Uri.parse(_edgeFunctionUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${session.accessToken}',
          },
          body: jsonEncode({
            'action': 'fetchAccounts',
            'accessToken': token,
          }),
        );
        if (resp.statusCode != 200) {
          throw Exception('Edge Function error: ${resp.body}');
        }
        accountsData = jsonDecode(resp.body);
      } else {
        // On native, call Google API directly
        final accountsResp = await http.get(
          Uri.parse(
              'https://mybusinessaccountmanagement.googleapis.com/v1/accounts'),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (accountsResp.statusCode != 200) {
          throw Exception(
            _toFriendlyGoogleApiError(
              action: 'obtener cuentas (accounts)',
              response: accountsResp,
            ),
          );
        }
        accountsData = jsonDecode(accountsResp.body);
      }

      final accounts = (accountsData['accounts'] as List?) ?? [];

      if (accounts.isEmpty) {
        throw Exception(
            'No se encontraron cuentas de negocio asociadas a este correo.');
      }

      // 2. Get Locations for each account
      final List<GoogleLocation> allLocations = [];

      for (final account in accounts) {
        final accountName = account['name']; // e.g., "accounts/123456"

        Map<String, dynamic> locData;

        if (kIsWeb) {
          // On web, use Edge Function
          final resp = await http.post(
            Uri.parse(_edgeFunctionUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${session.accessToken}',
            },
            body: jsonEncode({
              'action': 'fetchLocations',
              'accessToken': token,
              'accountName': accountName,
            }),
          );
          if (resp.statusCode != 200) {
            throw Exception('Edge Function error: ${resp.body}');
          }
          locData = jsonDecode(resp.body);
        } else {
          // On native, call Google API directly
          final locationsResp = await http.get(
            Uri.parse(
                'https://mybusinessbusinessinformation.googleapis.com/v1/$accountName/locations?readMask=name,title,storeCode,latlng,phoneNumbers,regularHours,categories,metadata,languageCode,serviceArea'),
            headers: {'Authorization': 'Bearer $token'},
          );
          if (locationsResp.statusCode != 200) {
            throw Exception(
              _toFriendlyGoogleApiError(
                action: 'obtener ubicaciones (locations) para $accountName',
                response: locationsResp,
              ),
            );
          }
          locData = jsonDecode(locationsResp.body);
        }

        final locations = (locData['locations'] as List?) ?? [];
        // Prepend accountName to each location's name for the Reviews API v4
        allLocations.addAll(locations
            .map((l) => GoogleLocation.fromJson(l, accountName: accountName)));
      }

      return allLocations;
    } catch (e) {
      _error = e.toString();
      debugPrint(_error);
      rethrow;
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  /// Fetch reviews for a specific location
  /// Uses the v4 API (still the standard for reviews as of 2024/2025)
  Future<List<Map<String, dynamic>>> fetchReviews(String locationName) async {
    _isLoading = true;
    _error = null;
    _safeNotifyListeners();

    try {
      final session = _supabase.auth.currentSession;
      if (session == null) throw Exception('No estás autenticado');

      final token = session.providerToken;
      if (token == null) throw Exception('No token');

      Map<String, dynamic> data;

      if (kIsWeb) {
        // On web, use Edge Function to bypass CORS
        debugPrint(
            '🌐 [GoogleBusinessService] Fetching reviews via Edge Function');
        final resp = await http.post(
          Uri.parse(_edgeFunctionUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${session.accessToken}',
          },
          body: jsonEncode({
            'action': 'fetchReviews',
            'accessToken': token,
            'locationName': locationName,
          }),
        );
        if (resp.statusCode != 200) {
          throw Exception('Edge Function error: ${resp.body}');
        }
        data = jsonDecode(resp.body);
      } else {
        // On native, call Google API directly
        final url =
            'https://mybusiness.googleapis.com/v4/$locationName/reviews';
        final response = await http.get(
          Uri.parse(url),
          headers: {'Authorization': 'Bearer $token'},
        );
        if (response.statusCode != 200) {
          throw Exception(
            _toFriendlyGoogleApiError(
              action: 'obtener reseñas (reviews)',
              response: response,
            ),
          );
        }
        data = jsonDecode(response.body);
      }

      final reviews = (data['reviews'] as List?) ?? [];
      return reviews.map((r) => r as Map<String, dynamic>).toList();
    } catch (e) {
      _error = 'Error fetching reviews: $e';
      debugPrint(_error);
      _safeNotifyListeners();
      rethrow;
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
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

  factory GoogleLocation.fromJson(Map<String, dynamic> json,
      {String? accountName}) {
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

    // Build the full resource name for Reviews API v4
    // Google's v1 API returns "locations/XXX" but v4 reviews needs "accounts/YYY/locations/XXX"
    String name = json['name'] ?? '';
    if (accountName != null && name.startsWith('locations/')) {
      name = '$accountName/$name';
    }

    return GoogleLocation(
      name: name,
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
