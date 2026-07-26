import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_redirect_urls.dart';
import 'browser_profile_service.dart';
import '../utils/auth_input_validation.dart';

class AuthService extends ChangeNotifier {
  static bool _capturedRecoveryIntent = false;
  static String? _capturedRecoveryCode;
  static String? _capturedRecoveryAccessToken;
  static String? _capturedRecoveryRefreshToken;

  static bool isPasswordRecoveryUri(Uri uri) {
    if (uri.path != '/reset-password') return false;

    final fragmentParameters = _fragmentParameters(uri.fragment);
    final recoveryType = uri.queryParameters['type'] == 'recovery' ||
        fragmentParameters['type'] == 'recovery';
    final hasCode = uri.queryParameters['code']?.isNotEmpty == true;
    final hasAccessToken =
        uri.queryParameters['access_token']?.isNotEmpty == true ||
            fragmentParameters['access_token']?.isNotEmpty == true;
    return (recoveryType || hasCode) && (hasCode || hasAccessToken);
  }

  /// Captures recovery evidence before Supabase initialization consumes the URL.
  static void captureInitialUrl(String? rawUrl) {
    _capturedRecoveryIntent = false;
    _capturedRecoveryCode = null;
    _capturedRecoveryAccessToken = null;
    _capturedRecoveryRefreshToken = null;
    if (rawUrl == null || rawUrl.isEmpty) return;

    try {
      final uri = Uri.parse(rawUrl);
      if (!isPasswordRecoveryUri(uri)) return;
      final fragmentParameters = _fragmentParameters(uri.fragment);
      _capturedRecoveryIntent = true;
      _capturedRecoveryCode = uri.queryParameters['code'];
      _capturedRecoveryAccessToken = uri.queryParameters['access_token'] ??
          fragmentParameters['access_token'];
      _capturedRecoveryRefreshToken = uri.queryParameters['refresh_token'] ??
          fragmentParameters['refresh_token'];
    } on FormatException {
      // Malformed input is not recovery evidence.
    }
  }

  static Map<String, String> _fragmentParameters(String fragment) {
    if (fragment.isEmpty) return const {};
    try {
      final normalized =
          fragment.startsWith('?') ? fragment.substring(1) : fragment;
      return Uri.splitQueryString(normalized);
    } on FormatException {
      return const {};
    }
  }

  AuthService() {
    _preserveInitialRecoveryUntilConsumed = _capturedRecoveryIntent;
    _initialRecoveryCode = _capturedRecoveryCode;
    _initialRecoveryAccessToken = _capturedRecoveryAccessToken;
    _initialRecoveryRefreshToken = _capturedRecoveryRefreshToken;
    _capturedRecoveryIntent = false;
    _capturedRecoveryCode = null;
    _capturedRecoveryAccessToken = null;
    _capturedRecoveryRefreshToken = null;

    _session = _client.auth.currentSession;
    _currentUser = _session?.user;
    _isPasswordRecovery = _preserveInitialRecoveryUntilConsumed &&
        _sessionMatchesInitialRecoveryEvidence(_session);

    // DON'T set _isInitializing to false here!
    // Wait for the auth state change listener to fire first

    _subscription = _client.auth.onAuthStateChange.listen((data) async {
      final previousUserId = _currentUser?.id;
      _session = data.session;
      _currentUser = data.session?.user;
      _isInitializing = false; // Now we can set it to false
      if (data.event == AuthChangeEvent.passwordRecovery) {
        _isPasswordRecovery = true;
        _preserveInitialRecoveryUntilConsumed = true;
      } else if (data.event == AuthChangeEvent.signedIn ||
          data.event == AuthChangeEvent.signedOut) {
        if (data.event == AuthChangeEvent.signedOut) {
          _isPasswordRecovery = false;
          _preserveInitialRecoveryUntilConsumed = false;
        } else if (!_preserveInitialRecoveryUntilConsumed) {
          _isPasswordRecovery = false;
        }
      }

      // CRITICAL: Only notify listeners on MEANINGFUL auth changes.
      // Token refreshes should NOT trigger GoRouter rebuilds, as that
      // destroys form state (e.g., sales invoice being edited for >5 min).
      final isSignificantEvent = data.event == AuthChangeEvent.signedIn ||
          data.event == AuthChangeEvent.signedOut ||
          data.event == AuthChangeEvent.passwordRecovery ||
          data.event == AuthChangeEvent.userUpdated;

      // Check access profiles on sign in
      if (data.event == AuthChangeEvent.signedIn && _currentUser != null) {
        if (previousUserId != null && previousUserId != _currentUser!.id) {
          await BrowserProfileService.clearWebsiteData(
            userId: previousUserId,
          );
        }
        await _loadAccessProfiles();
      } else if (data.event == AuthChangeEvent.signedOut) {
        await BrowserProfileService.clearWebsiteData(userId: previousUserId);
        _staffProfile = null;
        _workerProfile = null;
        _isStaffProfileLoaded = false;
        _isWorkerProfileLoaded = false;
      }

      // Only notify (and thus trigger GoRouter redirect) on real auth changes
      if (isSignificantEvent) {
        debugPrint('🔐 [AuthService] Significant auth event: ${data.event}');
        notifyListeners();
      } else {
        debugPrint(
            '🔄 [AuthService] Background auth event (no rebuild): ${data.event}');
      }
    });

    // If currentSession exists on initialization, set isInitializing to false immediately
    // and load staff profile
    if (_session != null) {
      _isInitializing = false;
      _loadAccessProfiles(); // Load async, will notifyListeners when done
      if (_preserveInitialRecoveryUntilConsumed && !_isPasswordRecovery) {
        unawaited(_restoreInitialRecoverySession());
      } else if (_isPasswordRecovery) {
        _clearInitialRecoveryEvidence();
      }
    } else if (_preserveInitialRecoveryUntilConsumed) {
      unawaited(_restoreInitialRecoverySession());
    }

    // Auto-login for debug mode only
    if (kDebugMode &&
        _session == null &&
        !_preserveInitialRecoveryUntilConsumed) {
      _autoLoginForDebug();
    }
  }

  final SupabaseClient _client = Supabase.instance.client;
  StreamSubscription<AuthState>? _subscription;
  Session? _session;
  User? _currentUser;
  bool _isInitializing = true;
  bool _isPasswordRecovery = false;
  bool _preserveInitialRecoveryUntilConsumed = false;
  bool _isRestoringInitialRecovery = false;
  String? _initialRecoveryCode;
  String? _initialRecoveryAccessToken;
  String? _initialRecoveryRefreshToken;
  Map<String, dynamic>? _staffProfile;
  Map<String, dynamic>? _workerProfile;
  bool _isStaffProfileLoaded = false;
  bool _isWorkerProfileLoaded = false;

  SupabaseClient get client => _client;
  Session? get currentSession => _session;
  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isInitializing => _isInitializing;
  bool get isPasswordRecovery => _isPasswordRecovery;
  bool get isWorkerPortalAuthUser => _isWorkerPortalUser(_currentUser);
  bool get isStaff => _staffProfile != null;
  bool get isWorker => _workerProfile != null;
  bool get workerMustResetPassword {
    final account = _workerProfile?['account'];
    return account is Map && account['mustResetPassword'] == true;
  }

  bool get isStaffProfileLoaded => _isStaffProfileLoaded;
  bool get isWorkerProfileLoaded => _isWorkerProfileLoaded;
  bool get isAccessProfileLoaded =>
      _isStaffProfileLoaded && _isWorkerProfileLoaded;
  Map<String, dynamic>? get staffProfile => _staffProfile;
  Map<String, dynamic>? get workerProfile => _workerProfile;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<User> signInWithEmailAndPassword(String email, String password) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    // DON'T notify yet - wait until staff profile is loaded to prevent flicker
    _syncAuth(response.session, notify: false);

    // Load staff profile BEFORE notifying UI
    await _loadAccessProfiles();
    // _loadAccessProfiles calls notifyListeners() when done

    final user = response.user ?? _client.auth.currentUser;
    if (user == null) {
      throw const AuthException(
          'No se pudo obtener el usuario después del inicio de sesión.');
    }
    return user;
  }

  Future<User> signInWorkerWithUsername({
    required String tenant,
    required String username,
    required String password,
  }) async {
    var sessionEstablished = false;
    try {
      final response = await _client.functions.invoke(
        'worker-login',
        body: {
          'tenant': tenant.trim(),
          'username': username.trim(),
          'password': password,
        },
      );

      final data = response.data;
      if (response.status != 200 || data is! Map || data['success'] != true) {
        throw const AuthException('Credenciales inválidas.');
      }
      final refreshToken = data['refreshToken']?.toString();
      if (refreshToken == null || refreshToken.isEmpty) {
        throw const AuthException('Credenciales inválidas.');
      }

      final authResponse = await _client.auth.setSession(refreshToken);
      final session = authResponse.session ?? _client.auth.currentSession;
      if (session == null) {
        throw const AuthException('Credenciales inválidas.');
      }

      sessionEstablished = true;
      _syncAuth(session, notify: false);
      await _loadAccessProfiles();

      if (!isWorker) {
        throw const AuthException('Credenciales inválidas.');
      }

      return session.user;
    } catch (_) {
      if (sessionEstablished && _client.auth.currentSession != null) {
        try {
          await signOut();
        } catch (_) {
          // Keep the public error uniform even if local cleanup fails.
        }
      }
      throw const AuthException('Credenciales inválidas.');
    }
  }

  Future<AuthResponse> signUpTenantOwner({
    required String email,
    required String password,
    required String shopName,
    required String subdomain,
  }) async {
    _requireStrongNewPassword(password);
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: AuthRedirectUrls.authCallback(isWeb: kIsWeb),
      data: {
        'shop_name': shopName,
        'subdomain': subdomain,
      },
    );
    await _syncSignedUpSession(response);
    return response;
  }

  Future<AuthResponse> signUpStaffInvitation({
    required String email,
    required String password,
    required String invitationToken,
  }) async {
    _requireStrongNewPassword(password);
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: AuthRedirectUrls.authCallback(isWeb: kIsWeb),
      data: {
        'account_type': 'staff_invitation',
        'invitation_token': invitationToken,
      },
    );
    await _syncSignedUpSession(response);
    return response;
  }

  Future<void> _syncSignedUpSession(AuthResponse response) async {
    if (response.session == null) {
      return;
    }
    _syncAuth(response.session, notify: false);
    await _loadAccessProfiles();
  }

  Future<bool> signInWithGoogle() async {
    try {
      final redirectTo = AuthRedirectUrls.authCallback(isWeb: kIsWeb);
      if (redirectTo == null) {
        throw const AuthException(
          'El inicio de sesión con Google no está configurado para esta plataforma.',
        );
      }

      final response = await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectTo,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );

      // For web/desktop OAuth, the session is handled via redirect callback
      // The auth state listener will update automatically
      return response;
    } catch (_) {
      if (kDebugMode) {
        debugPrint('❌ [AuthService] Google sign-in failed');
      }
      throw const AuthException(
        'No pudimos iniciar sesión con Google. Inténtalo nuevamente.',
      );
    }
  }

  /// Force refresh the current session to get updated user metadata
  /// Call this after updating user metadata in the database
  Future<void> refreshSession() async {
    try {
      final response = await _client.auth.refreshSession();
      _syncAuth(response.session, notify: false);
      await _loadAccessProfiles();
    } catch (_) {
      if (kDebugMode) {
        debugPrint('⚠️ [AuthService] Session refresh failed');
      }
    }
  }

  Future<void> signOut() async {
    final signingOutUserId = _currentUser?.id;
    if (_client.auth.currentSession != null) {
      await _client.auth.signOut();
    }
    await BrowserProfileService.clearWebsiteData(userId: signingOutUserId);
    _isPasswordRecovery = false;
    _preserveInitialRecoveryUntilConsumed = false;
    _clearInitialRecoveryEvidence();
    _staffProfile = null;
    _workerProfile = null;
    _isStaffProfileLoaded = false;
    _isWorkerProfileLoaded = false;
    _syncAuth(_client.auth.currentSession);
  }

  Future<void> _loadAccessProfiles() async {
    await _loadStaffProfile(notify: false);
    await _loadWorkerProfile(notify: false);
    notifyListeners();
  }

  /// Load staff profile from user_profiles table.
  /// Returns null if user is not an ERP staff member.
  Future<void> _loadStaffProfile({bool notify = true}) async {
    if (_currentUser == null) {
      _staffProfile = null;
      _isStaffProfileLoaded = true;
      if (notify) notifyListeners();
      return;
    }

    if (isWorkerPortalAuthUser) {
      _staffProfile = null;
      _isStaffProfileLoaded = true;
      if (kDebugMode) {
        debugPrint(
          'ℹ️ [AuthService] Worker portal auth user: skipping staff profile',
        );
      }
      if (notify) notifyListeners();
      return;
    }

    try {
      final response = await _client
          .from('user_profiles')
          .select()
          .eq('user_id', _currentUser!.id)
          .eq('is_active', true)
          .limit(2);

      final profiles = List<Map<String, dynamic>>.from(response);
      _staffProfile = profiles.length == 1 ? profiles.single : null;
      _isStaffProfileLoaded = true;

      if (kDebugMode) {
        if (_staffProfile != null) {
          debugPrint(
              '✅ [AuthService] Staff profile loaded: ${_staffProfile!['role']}');
        } else {
          debugPrint('ℹ️ [AuthService] No staff profile found (Customer only)');
        }
      }

      if (notify) notifyListeners(); // Notify Router to re-evaluate
    } catch (_) {
      debugPrint('⚠️ [AuthService] Staff profile lookup failed');
      _staffProfile = null;
      _isStaffProfileLoaded = true; // Still mark as loaded (failed check)
      if (notify) notifyListeners();
    }
  }

  /// Load worker portal context for username-based mobile/worker access.
  Future<void> _loadWorkerProfile({bool notify = true}) async {
    if (_currentUser == null) {
      _workerProfile = null;
      _isWorkerProfileLoaded = true;
      if (notify) notifyListeners();
      return;
    }

    try {
      final response = await _client.rpc('get_my_worker_portal_context');
      if (response is Map && response.isNotEmpty) {
        _workerProfile = Map<String, dynamic>.from(response);
      } else {
        _workerProfile = null;
      }
      _isWorkerProfileLoaded = true;

      if (kDebugMode) {
        if (_workerProfile != null) {
          final employee = _workerProfile!['employee'];
          final name = employee is Map ? employee['fullName'] : null;
          debugPrint('✅ [AuthService] Worker profile loaded: $name');
        } else {
          debugPrint('ℹ️ [AuthService] No worker portal profile found');
        }
      }

      if (notify) notifyListeners();
    } catch (_) {
      debugPrint('⚠️ [AuthService] Worker profile lookup failed');
      _workerProfile = null;
      _isWorkerProfileLoaded = true;
      if (notify) notifyListeners();
    }
  }

  /// Force reload staff profile (call after profile changes)
  Future<void> refreshStaffProfile() async {
    await _loadAccessProfiles();
  }

  /// Force reload worker portal context after profile or shift settings change.
  Future<void> refreshWorkerProfile() async {
    await _loadWorkerProfile();
  }

  /// Replaces an administrator-issued worker credential, records completion
  /// server-side, and leaves sign-out to the caller after both steps succeed.
  Future<void> completeWorkerPasswordReset(String newPassword) async {
    if (!isWorker || !workerMustResetPassword) {
      throw const AuthException(
        'No hay un cambio de contraseña pendiente para esta cuenta.',
      );
    }

    final validationError =
        AuthInputValidation.validateAdminManagedPassword(newPassword);
    if (validationError != null) {
      throw AuthException(validationError);
    }

    final challengeStarted =
        await _client.rpc('begin_my_worker_password_reset');
    if (challengeStarted != true) {
      throw const AuthException(
        'No pudimos iniciar el cambio obligatorio de contraseña.',
      );
    }

    final response = await _client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
    if (response.user == null) {
      throw const AuthException('No pudimos actualizar la contraseña.');
    }

    final completed = await _client.rpc('complete_my_worker_password_reset');
    if (completed != true) {
      throw const AuthException(
        'No pudimos completar el cambio obligatorio de contraseña.',
      );
    }

    await _client.auth.signOut(scope: SignOutScope.others);
    await _loadWorkerProfile(notify: false);
  }

  /// Send password reset email with redirect URL
  Future<void> sendPasswordResetEmail(String email) async {
    final redirectTo = AuthRedirectUrls.passwordReset(isWeb: kIsWeb);
    if (redirectTo == null) {
      throw const AuthException(
        'La recuperación de contraseña no está configurada para esta plataforma.',
      );
    }

    await _client.auth.resetPasswordForEmail(
      email,
      redirectTo: redirectTo,
    );
  }

  /// Update user password (must be called after password reset link click)
  Future<void> updatePassword(String newPassword) async {
    _requireStrongNewPassword(newPassword);
    final response = await _client.auth.updateUser(
      UserAttributes(password: newPassword),
    );

    if (response.user == null) {
      throw const AuthException('Error al actualizar la contraseña.');
    }

    await _client.auth.signOut(scope: SignOutScope.others);
    _isPasswordRecovery = false;
    _preserveInitialRecoveryUntilConsumed = false;
    _clearInitialRecoveryEvidence();
    _syncAuth(_client.auth.currentSession);
  }

  void _requireStrongNewPassword(String password) {
    final validationError = AuthInputValidation.validatePassword(
      password,
      isNewPassword: true,
    );
    if (validationError != null) {
      throw AuthException(validationError);
    }
  }

  Future<void> _restoreInitialRecoverySession() async {
    if (_isRestoringInitialRecovery) return;
    _isRestoringInitialRecovery = true;
    try {
      final existingSession = _client.auth.currentSession;
      if (_sessionMatchesInitialRecoveryEvidence(existingSession)) {
        _syncAuth(existingSession, notify: false);
        _isPasswordRecovery = true;
        notifyListeners();
        return;
      }

      final code = _initialRecoveryCode;
      final refreshToken = _initialRecoveryRefreshToken;
      var restoredFromCapturedCredential = false;
      if (code != null && code.isNotEmpty) {
        await _client.auth.exchangeCodeForSession(code);
        restoredFromCapturedCredential = true;
      } else if (refreshToken != null && refreshToken.isNotEmpty) {
        await _client.auth.setSession(refreshToken);
        restoredFromCapturedCredential = true;
      }

      final session = _client.auth.currentSession;
      if (!restoredFromCapturedCredential || session == null) {
        _preserveInitialRecoveryUntilConsumed = false;
        _isPasswordRecovery = false;
        _isInitializing = false;
        notifyListeners();
        return;
      }

      _syncAuth(session, notify: false);
      _isPasswordRecovery = true;
      notifyListeners();
    } catch (_) {
      _preserveInitialRecoveryUntilConsumed = false;
      _isPasswordRecovery = false;
      _isInitializing = false;
      debugPrint('⚠️ [AuthService] Recovery session restoration failed');
      notifyListeners();
    } finally {
      _clearInitialRecoveryEvidence();
      _isRestoringInitialRecovery = false;
    }
  }

  bool _sessionMatchesInitialRecoveryEvidence(Session? session) {
    if (session == null) return false;

    final accessToken = _initialRecoveryAccessToken;
    if (accessToken != null &&
        accessToken.isNotEmpty &&
        session.accessToken == accessToken) {
      return true;
    }

    final refreshToken = _initialRecoveryRefreshToken;
    if (refreshToken != null &&
        refreshToken.isNotEmpty &&
        session.refreshToken == refreshToken) {
      return true;
    }

    // PKCE codes are consumed by Supabase initialization before this service
    // subscribes. A freshly issued recovery timestamp is the server-returned
    // evidence that the resulting session came from that consumed code.
    final code = _initialRecoveryCode;
    if (code == null || code.isEmpty) return false;
    final sentAt = DateTime.tryParse(session.user.recoverySentAt ?? '');
    if (sentAt == null) return false;
    final age = DateTime.now().toUtc().difference(sentAt.toUtc());
    return age >= const Duration(minutes: -5) &&
        age <= const Duration(minutes: 65);
  }

  void _clearInitialRecoveryEvidence() {
    _initialRecoveryCode = null;
    _initialRecoveryAccessToken = null;
    _initialRecoveryRefreshToken = null;
  }

  void _syncAuth(Session? session, {bool notify = true}) {
    _session = session;
    _currentUser = session?.user ?? _client.auth.currentUser;
    _isInitializing = false;
    if (notify) {
      notifyListeners();
    }
  }

  /// 🚀 AUTO-LOGIN FOR DEBUG MODE
  /// Automatically logs in with your credentials when running in debug mode
  Future<void> _autoLoginForDebug() async {
    try {
      // Read credentials only from local, runtime-supplied dart-defines.
      const debugEmail =
          String.fromEnvironment('DEBUG_EMAIL', defaultValue: '');
      const debugPassword =
          String.fromEnvironment('DEBUG_PASSWORD', defaultValue: '');

      if (debugEmail.isEmpty || debugPassword.isEmpty) {
        debugPrint(
            '⚠️ [AuthService] Auto-login skipped: No credentials configured');
        debugPrint(
            '💡 Supply DEBUG_EMAIL and DEBUG_PASSWORD only through a local '
            'secret-aware debug environment');
        return;
      }

      debugPrint('🚀 [AuthService] Attempting configured debug auto-login');

      await Future.delayed(const Duration(
          milliseconds: 500)); // Small delay to ensure Supabase is ready

      final response = await _client.auth.signInWithPassword(
        email: debugEmail,
        password: debugPassword,
      );

      if (response.session != null) {
        _syncAuth(response.session, notify: false);
        await _loadAccessProfiles();
        debugPrint('✅ [AuthService] Auto-login successful!');
      } else {
        debugPrint('❌ [AuthService] Auto-login failed: No session returned');
      }
    } catch (_) {
      debugPrint('❌ [AuthService] Auto-login failed');
      // Don't throw - just let user login manually if auto-login fails
    }
  }

  bool _isWorkerPortalUser(User? user) {
    if (user == null) return false;
    return user.appMetadata['account_type'] == 'worker_portal';
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
