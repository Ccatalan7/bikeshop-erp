import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/website_editor_capability.dart';
import '../models/website_editor_oauth_intent.dart';

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

  // Edge Function URL for proxying Google Business API calls (bypasses CORS on web)
  static const String _edgeFunctionUrl =
      'https://xzdvtzdqjeyqxnkqprtf.supabase.co/functions/v1/google-business-reviews';

  Future<void>? _connectInFlight;

  /// Test seam: replaces the web localStorage-backed intent store.
  @visibleForTesting
  WebsiteEditorOAuthIntentStore? intentStoreOverride;

  /// Test seam: replaces the current auth user id lookup.
  @visibleForTesting
  String? Function()? currentUserIdOverride;

  /// Test seam: replaces the real OAuth/link launch. Receives the stage
  /// ('signIn' | 'link' | 'signInFallback') and returns the launcher bool.
  @visibleForTesting
  Future<bool> Function(String stage)? oauthLaunchOverride;

  /// Test seam: selects the linked/unlinked launcher branch without mutating
  /// the authenticated Supabase user.
  @visibleForTesting
  bool Function()? isLinkedOverride;

  WebsiteEditorOAuthIntentStore? get _intentStore =>
      intentStoreOverride ?? (kIsWeb ? _webIntentStore() : null);

  static WebsiteEditorOAuthIntentStore _webIntentStore() =>
      WebsiteEditorOAuthIntentStore(
        readRaw: () => web.window.localStorage
            .getItem(WebsiteEditorOAuthIntentGate.storageKey),
        writeRaw: (value) => web.window.localStorage
            .setItem(WebsiteEditorOAuthIntentGate.storageKey, value),
        removeRaw: () => web.window.localStorage
            .removeItem(WebsiteEditorOAuthIntentGate.storageKey),
      );

  /// A failed/aborted OAuth launch consumes ONLY the nonce issued by that
  /// invocation. Never read nonce ownership from mutable service state after
  /// awaiting an external launcher.
  void _consumeOwnIntentAfterFailedLaunch(String? nonce) {
    if (nonce == null) return;
    try {
      _intentStore?.clearIfNonce(
        nonce,
        nowMs: DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  /// Treats the launcher's `false` as a failed/aborted launch: the pending
  /// intent is consumed and a visible error is surfaced. Returns whether
  /// the launch actually succeeded.
  bool _handleOAuthLaunchResult(
    bool result,
    String stage,
    String? issuedIntentNonce,
  ) {
    if (result) return true;
    debugPrint(
        '⛔ [GoogleBusinessService] OAuth launch ($stage) returned false');
    _consumeOwnIntentAfterFailedLaunch(issuedIntentNonce);
    _error = 'No se pudo iniciar la conexión con Google. Inténtalo de nuevo.';
    _safeNotifyListeners();
    return false;
  }

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
    final override = isLinkedOverride;
    if (override != null) return override();
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

  /// Starts the Google Business OAuth operation ("business.manage" scope).
  ///
  /// The EDITOR capability comes from the consumer (the open editor session)
  /// — never from a cold singleton cache — and is validated BEFORE anything
  /// is persisted: only a granted capability whose identity is the current
  /// auth user may issue the one-shot typed return intent.
  ///
  /// Concurrency contract: this service is single-flight. Every caller that
  /// arrives while a launch is active joins the exact same [Future]; it never
  /// persists another intent, invokes another launcher, or owns another
  /// loading lifecycle. UI gating is defensive UX, not the concurrency owner.
  Future<void> connect({
    required WebsiteEditorCapabilitySnapshot? editorCapability,
  }) {
    final active = _connectInFlight;
    if (active != null) return active;

    // Install the shared Future BEFORE _connectOnce can notify listeners.
    // A listener may synchronously call connect() from the first loading
    // notification, so assigning after invoking _connectOnce leaves a real
    // reentrancy window.
    final completer = Completer<void>();
    final operation = completer.future;
    _connectInFlight = operation;
    unawaited(() async {
      try {
        await _connectOnce(editorCapability: editorCapability);
        completer.complete();
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      } finally {
        if (identical(_connectInFlight, operation)) {
          _connectInFlight = null;
        }
      }
    }());
    return operation;
  }

  Future<void> _connectOnce({
    required WebsiteEditorCapabilitySnapshot? editorCapability,
  }) async {
    _isLoading = true;
    _error = null;
    _safeNotifyListeners();

    final currentUserId =
        currentUserIdOverride?.call() ?? _supabase.auth.currentUser?.id;
    if (editorCapability == null ||
        !editorCapability.granted ||
        currentUserId == null ||
        editorCapability.identity != currentUserId) {
      _isLoading = false;
      _error = 'La sesión del editor no está autorizada para conectar Google.';
      _safeNotifyListeners();
      return;
    }

    String? issuedIntentNonce;
    try {
      // Determines redirect URL based on platform
      // ONE typed, versioned, one-shot intent replaces the legacy loose
      // flags: nonce + issuer identity + tenant + capability fingerprint,
      // issue/expiry window, sanitized return path and the Integrations
      // request all travel together. Persisting is transport-independent:
      // it happens whenever an intent store exists (web localStorage, or an
      // injected store under test).
      try {
        final uri = Uri.base;
        final pathWithQuery =
            uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        issuedIntentNonce = WebsiteEditorOAuthIntentGate.newNonce(nowMs);
        _intentStore?.put(
          WebsiteEditorOAuthIntentGate.issue(
            capability: editorCapability,
            nowMs: nowMs,
            nonce: issuedIntentNonce,
            returnPath: pathWithQuery,
            openIntegrations: true,
          ),
        );
        debugPrint(
            '💾 [GoogleBusinessService] Saved typed OAuth editor intent');
      } catch (e) {
        debugPrint(
            '⚠️ [GoogleBusinessService] Could not persist OAuth intent: $e');
      }

      String? redirectTo;
      if (kIsWeb) {
        // IMPORTANT:
        // Redirect back to a stable callback route to prevent the router from
        // immediately redirecting away from '/' and stripping the OAuth code.
        final origin = Uri.base.origin;
        redirectTo = '$origin/auth/callback';
        debugPrint('🔗 [GoogleBusinessService] OAuth redirectTo: $redirectTo');
      } else {
        redirectTo = 'io.supabase.vinabike://login-callback';
      }

      // The gate above already proved an authenticated identity (override or
      // real session) matching the capability. Link state only selects which
      // OAuth launcher branch runs.
      final isLinked = this.isLinked;

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
        final result = oauthLaunchOverride != null
            ? await oauthLaunchOverride!('signIn')
            : await _supabase.auth.signInWithOAuth(
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
        if (!_handleOAuthLaunchResult(
          result,
          'signIn',
          issuedIntentNonce,
        )) {
          return;
        }
      } else {
        // If not linked, we try to link first
        debugPrint(
            '🚀 [GoogleBusinessService] Calling linkIdentity (not linked)...');
        try {
          final result = oauthLaunchOverride != null
              ? await oauthLaunchOverride!('link')
              : await _supabase.auth.linkIdentity(
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
          if (!_handleOAuthLaunchResult(
            result,
            'link',
            issuedIntentNonce,
          )) {
            return;
          }
        } catch (e) {
          debugPrint('⚠️ [GoogleBusinessService] linkIdentity error: $e');
          final msg = e.toString().toLowerCase();

          // If it says "already linked", it means we are good to sign in
          if (msg.contains('already linked') ||
              msg.contains('already_linked')) {
            debugPrint(
                '🔄 [GoogleBusinessService] Already linked, falling back to signInWithOAuth...');
            final result = oauthLaunchOverride != null
                ? await oauthLaunchOverride!('signInFallback')
                : await _supabase.auth.signInWithOAuth(
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
            if (!_handleOAuthLaunchResult(
              result,
              'signInFallback',
              issuedIntentNonce,
            )) {
              return;
            }
            return;
          }

          // Otherwise rethrow to be caught by the main error handler
          // (This handles manual_linking_disabled, etc.)
          rethrow;
        }
      }

      // Note: The app will likely reload/redirect after this
    } catch (e) {
      _consumeOwnIntentAfterFailedLaunch(issuedIntentNonce);
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
                'https://mybusinessbusinessinformation.googleapis.com/v1/$accountName/locations?readMask=name,title,storeCode,storefrontAddress,latlng,phoneNumbers,regularHours,categories,metadata,languageCode,serviceArea'),
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

  Future<void> publishRegularHours({
    required String locationName,
    required Map<String, dynamic> regularHours,
  }) async {
    _isLoading = true;
    _error = null;
    _safeNotifyListeners();

    try {
      final session = _supabase.auth.currentSession;
      if (session == null) throw Exception('No estás autenticado');

      final token = session.providerToken;
      if (token == null) {
        _debugSessionSnapshot('publishRegularHours_missingToken');
        throw Exception(
          'No se encontró un token de Google en tu sesión. Renueva el acceso de Google Business Profile.',
        );
      }

      if (kIsWeb) {
        final resp = await http.post(
          Uri.parse(_edgeFunctionUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${session.accessToken}',
          },
          body: jsonEncode({
            'action': 'updateRegularHours',
            'accessToken': token,
            'locationName': locationName,
            'regularHours': regularHours,
          }),
        );
        if (resp.statusCode != 200) {
          throw Exception(
            _toFriendlyGoogleApiError(
              action: 'actualizar horario de Google Business Profile',
              response: resp,
            ),
          );
        }
        return;
      }

      final response = await http.patch(
        Uri.parse(
          'https://mybusinessbusinessinformation.googleapis.com/v1/${_businessInfoLocationName(locationName)}?updateMask=regularHours',
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'regularHours': regularHours}),
      );
      if (response.statusCode != 200) {
        throw Exception(
          _toFriendlyGoogleApiError(
            action: 'actualizar horario de Google Business Profile',
            response: response,
          ),
        );
      }
    } catch (e) {
      _error = e.toString();
      debugPrint(_error);
      rethrow;
    } finally {
      _isLoading = false;
      _safeNotifyListeners();
    }
  }

  String _businessInfoLocationName(String locationName) {
    final parts = locationName.split('/');
    final locationsIndex = parts.lastIndexOf('locations');
    if (locationsIndex >= 0 && parts.length > locationsIndex + 1) {
      return 'locations/${parts[locationsIndex + 1]}';
    }
    return locationName;
  }
}

class GoogleLocation {
  final String name; // Resource name "locations/..."
  final String title;
  final String? phone;
  final double? lat;
  final double? lng;
  final String? addressLine; // Simplified
  final String? addressStreet;
  final String? addressCity;
  final String? addressRegion;
  final String? addressPostalCode;
  final String? addressCountry;
  final Map<String, dynamic>? hours;
  final String? mapsUri;
  final String? newReviewUri;

  GoogleLocation({
    required this.name,
    required this.title,
    this.phone,
    this.lat,
    this.lng,
    this.addressLine,
    this.addressStreet,
    this.addressCity,
    this.addressRegion,
    this.addressPostalCode,
    this.addressCountry,
    this.hours,
    this.mapsUri,
    this.newReviewUri,
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

    final metadata = json['metadata'] is Map
        ? Map<String, dynamic>.from(json['metadata'] as Map)
        : const <String, dynamic>{};
    final storefrontAddress = json['storefrontAddress'] is Map
        ? Map<String, dynamic>.from(json['storefrontAddress'] as Map)
        : const <String, dynamic>{};
    final addressLines = storefrontAddress['addressLines'] is List
        ? (storefrontAddress['addressLines'] as List)
            .map((line) => line?.toString().trim() ?? '')
            .where((line) => line.isNotEmpty)
            .toList()
        : const <String>[];
    final addressStreet = addressLines.join(', ').trim();
    final addressCity = storefrontAddress['locality']?.toString().trim();
    final addressRegion =
        storefrontAddress['administrativeArea']?.toString().trim();
    final addressPostalCode =
        storefrontAddress['postalCode']?.toString().trim();
    final addressCountry = _countryNameFromRegionCode(
      storefrontAddress['regionCode']?.toString(),
    );
    final addressLine = [
      addressStreet,
      addressCity,
      addressRegion,
      addressCountry,
    ].where((part) => part != null && part.trim().isNotEmpty).join(', ');

    return GoogleLocation(
      name: name,
      title: json['title'] ?? 'Sin título',
      phone: phone,
      lat: lat,
      lng: lng,
      addressLine: addressLine.isEmpty ? null : addressLine,
      addressStreet: addressStreet.isEmpty ? null : addressStreet,
      addressCity: _emptyToNull(addressCity),
      addressRegion: _emptyToNull(addressRegion),
      addressPostalCode: _emptyToNull(addressPostalCode),
      addressCountry: _emptyToNull(addressCountry),
      hours: json['regularHours'],
      mapsUri: metadata['mapsUri']?.toString(),
      newReviewUri: metadata['newReviewUri']?.toString(),
    );
  }

  static String? _emptyToNull(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _countryNameFromRegionCode(String? rawCode) {
    final code = rawCode?.trim().toUpperCase() ?? '';
    if (code.isEmpty) return null;
    return switch (code) {
      'CL' => 'Chile',
      _ => code,
    };
  }
}
