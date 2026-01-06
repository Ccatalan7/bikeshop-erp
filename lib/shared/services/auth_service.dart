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

      // Check staff profile on sign in
      if (data.event == AuthChangeEvent.signedIn && _currentUser != null) {
        await _loadStaffProfile();
      } else if (data.event == AuthChangeEvent.signedOut) {
        _staffProfile = null;
      }

      notifyListeners();
    });

    // If currentSession exists on initialization, set isInitializing to false immediately
    // and load staff profile
    if (_session != null) {
      _isInitializing = false;
      _loadStaffProfile(); // Load async, will notifyListeners when done
    }

    // Auto-login for debug mode only
    // DISABLED to prevent infinite loops during Staff-Only Guard testing
    // if (kDebugMode && _session == null) {
    //   _autoLoginForDebug();
    // }
  }

  final SupabaseClient _client = Supabase.instance.client;
  StreamSubscription<AuthState>? _subscription;
  Session? _session;
  User? _currentUser;
  bool _isInitializing = true;
  Map<String, dynamic>? _staffProfile;
  bool _isStaffProfileLoaded = false;

  SupabaseClient get client => _client;
  Session? get currentSession => _session;
  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isInitializing => _isInitializing;
  bool get isStaff => _staffProfile != null;
  bool get isStaffProfileLoaded => _isStaffProfileLoaded;
  Map<String, dynamic>? get staffProfile => _staffProfile;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<User> signInWithEmailAndPassword(String email, String password) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    // DON'T notify yet - wait until staff profile is loaded to prevent flicker
    _syncAuth(response.session, notify: false);

    // Load staff profile BEFORE notifying UI
    await _loadStaffProfile();
    // _loadStaffProfile calls notifyListeners() when done

    final user = response.user ?? _client.auth.currentUser;
    if (user == null) {
      throw AuthException(
          'No se pudo obtener el usuario después del inicio de sesión.');
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
      throw AuthException(
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
    _isStaffProfileLoaded = false;
    _syncAuth(_client.auth.currentSession);
  }

  /// Load staff profile from user_profiles table
  /// Returns null if user is not a staff member (Customer only)
  Future<void> _loadStaffProfile() async {
    if (_currentUser == null) {
      _staffProfile = null;
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

      notifyListeners(); // Notify Router to re-evaluate
    } catch (e) {
      debugPrint('⚠️ [AuthService] Error loading staff profile: $e');
      _staffProfile = null;
      _isStaffProfileLoaded = true; // Still mark as loaded (failed check)
      notifyListeners();
    }
  }

  /// Force reload staff profile (call after profile changes)
  Future<void> refreshStaffProfile() async {
    await _loadStaffProfile();
    notifyListeners();
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
      throw AuthException('Error al actualizar la contraseña.');
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
        _syncAuth(response.session);
        debugPrint('✅ [AuthService] Auto-login successful!');
      } else {
        debugPrint('❌ [AuthService] Auto-login failed: No session returned');
      }
    } catch (e) {
      debugPrint('❌ [AuthService] Auto-login error: $e');
      // Don't throw - just let user login manually if auto-login fails
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
