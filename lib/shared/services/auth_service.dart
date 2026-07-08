import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService extends ChangeNotifier {
  AuthService() {
    _session = _client.auth.currentSession;
    _currentUser = _session?.user;

    // DON'T set _isInitializing to false here!
    // Wait for the auth state change listener to fire first

    _subscription = _client.auth.onAuthStateChange.listen((data) async {
      _session = data.session;
      _currentUser = data.session?.user;
      _isInitializing = false; // Now we can set it to false

      // CRITICAL: Only notify listeners on MEANINGFUL auth changes.
      // Token refreshes should NOT trigger GoRouter rebuilds, as that
      // destroys form state (e.g., sales invoice being edited for >5 min).
      final isSignificantEvent = data.event == AuthChangeEvent.signedIn ||
          data.event == AuthChangeEvent.signedOut ||
          data.event == AuthChangeEvent.passwordRecovery ||
          data.event == AuthChangeEvent.userUpdated;

      // Check access profiles on sign in
      if (data.event == AuthChangeEvent.signedIn && _currentUser != null) {
        await _loadAccessProfiles();
      } else if (data.event == AuthChangeEvent.signedOut) {
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
    }

    // Auto-login for debug mode only
    if (kDebugMode && _session == null) {
      _autoLoginForDebug();
    }
  }

  final SupabaseClient _client = Supabase.instance.client;
  StreamSubscription<AuthState>? _subscription;
  Session? _session;
  User? _currentUser;
  bool _isInitializing = true;
  Map<String, dynamic>? _staffProfile;
  Map<String, dynamic>? _workerProfile;
  bool _isStaffProfileLoaded = false;
  bool _isWorkerProfileLoaded = false;

  SupabaseClient get client => _client;
  Session? get currentSession => _session;
  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isInitializing => _isInitializing;
  bool get isWorkerPortalAuthUser => _isWorkerPortalUser(_currentUser);
  bool get isStaff => _staffProfile != null;
  bool get isWorker => _workerProfile != null;
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
    final resolved = await _client.rpc(
      'resolve_worker_login',
      params: {
        'p_tenant': tenant.trim(),
        'p_username': username.trim(),
      },
    );
    final loginEmail = _extractWorkerLoginEmail(resolved);

    if (loginEmail == null || loginEmail.isEmpty) {
      throw const AuthException(
        'No encontramos ese trabajador para esta tienda.',
      );
    }

    final response = await _client.auth.signInWithPassword(
      email: loginEmail,
      password: password,
    );
    _syncAuth(response.session, notify: false);
    await _loadAccessProfiles();

    final user = response.user ?? _client.auth.currentUser;
    if (user == null) {
      throw const AuthException(
          'No se pudo obtener el trabajador después del inicio de sesión.');
    }
    return user;
  }

  Future<User> createUserWithEmailAndPassword(
      String email, String password) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: null,
    );
    _syncAuth(response.session);
    final user = response.user ?? _client.auth.currentUser;
    if (user == null) {
      throw const AuthException(
          'Revisa tu correo para confirmar la cuenta antes de iniciar sesión.');
    }
    return user;
  }

  Future<bool> signInWithGoogle() async {
    try {
      // Determine redirect URL based on platform
      String? redirectTo;

      if (kIsWeb) {
        // For web, redirect back to a stable callback route.
        // If we redirect to '/', the router might redirect immediately and strip
        // the OAuth query params before Supabase can exchange them.
        final origin = Uri.base.origin;
        redirectTo = '$origin/auth/callback';
        if (kDebugMode) {
          print('🔐 Google OAuth redirect URL: $redirectTo');
        }
      } else {
        // For desktop/mobile, use deep link
        redirectTo = 'io.supabase.vinabikeerp://login-callback/';
      }

      final response = await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectTo,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );

      if (kDebugMode) {
        print('🔐 OAuth response: $response');
      }

      // For web/desktop OAuth, the session is handled via redirect callback
      // The auth state listener will update automatically
      return response;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Google Sign-In error: $e');
      }
      throw AuthException(
          'Error al iniciar sesión con Google: ${e.toString()}');
    }
  }

  /// Force refresh the current session to get updated user metadata
  /// Call this after updating user metadata in the database
  Future<void> refreshSession() async {
    try {
      await _client.auth.refreshSession();
      _syncAuth(_client.auth.currentSession);
    } catch (e) {
      if (kDebugMode) {
        print('Session refresh error: $e');
      }
    }
  }

  Future<void> signOut() async {
    await _client.auth.signOut();
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
          .maybeSingle();

      _staffProfile = response;
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
    } catch (e) {
      debugPrint('⚠️ [AuthService] Error loading staff profile: $e');
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
    } catch (e) {
      debugPrint('⚠️ [AuthService] Error loading worker profile: $e');
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

  /// Send password reset email with redirect URL
  Future<void> sendPasswordResetEmail(String email) async {
    // Determine redirect URL based on platform
    String? redirectTo;

    if (kIsWeb) {
      // For web, redirect back to the current origin with reset-password path
      final origin = Uri.base.origin;
      redirectTo = '$origin/#/reset-password';
      if (kDebugMode) {
        print('🔐 Password reset redirect URL: $redirectTo');
      }
    } else {
      // For desktop/mobile, use deep link
      redirectTo = 'io.supabase.vinabikeerp://reset-password/';
    }

    await _client.auth.resetPasswordForEmail(
      email,
      redirectTo: redirectTo,
    );
  }

  /// Update user password (must be called after password reset link click)
  Future<void> updatePassword(String newPassword) async {
    final response = await _client.auth.updateUser(
      UserAttributes(password: newPassword),
    );

    if (response.user == null) {
      throw const AuthException('Error al actualizar la contraseña.');
    }

    _syncAuth(_client.auth.currentSession);
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
      // Read credentials from dart-defines (set in .vscode/launch.json)
      const debugEmail =
          String.fromEnvironment('DEBUG_EMAIL', defaultValue: '');
      const debugPassword =
          String.fromEnvironment('DEBUG_PASSWORD', defaultValue: '');

      if (debugEmail.isEmpty || debugPassword.isEmpty) {
        debugPrint(
            '⚠️ [AuthService] Auto-login skipped: No credentials configured');
        debugPrint(
            '💡 Set DEBUG_EMAIL and DEBUG_PASSWORD in .vscode/launch.json');
        return;
      }

      debugPrint('🚀 [AuthService] Attempting auto-login with: $debugEmail');

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
    } catch (e) {
      debugPrint('❌ [AuthService] Auto-login error: $e');
      // Don't throw - just let user login manually if auto-login fails
    }
  }

  String? _extractWorkerLoginEmail(dynamic resolved) {
    if (resolved is List && resolved.isNotEmpty) {
      final first = resolved.first;
      if (first is Map) return first['login_email']?.toString();
      return first?.toString();
    }
    if (resolved is Map) {
      return resolved['login_email']?.toString();
    }
    if (resolved is String && resolved.contains('@')) {
      return resolved;
    }
    return null;
  }

  bool _isWorkerPortalUser(User? user) {
    if (user == null) return false;
    return user.userMetadata?['account_type'] == 'worker_portal' ||
        user.appMetadata['account_type'] == 'worker_portal';
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
