import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService extends ChangeNotifier {
  AuthService() {
    debugPrint('🔐 [AuthService] Constructor: Initializing...');
    _session = _client.auth.currentSession;
    _currentUser = _session?.user;
    debugPrint('🔐 [AuthService] Initial session: ${_session != null ? "EXISTS" : "NULL"}');
    debugPrint('🔐 [AuthService] Initial user: ${_currentUser?.email ?? "NULL"}');
    
    // DON'T set _isInitializing to false here!
    // Wait for the auth state change listener to fire first
    
    _subscription = _client.auth.onAuthStateChange.listen((data) {
      debugPrint('🔐 [AuthService] Auth state changed: ${data.event}');
      _session = data.session;
      _currentUser = data.session?.user;
      _isInitializing = false;  // ✅ Now we can set it to false
      debugPrint('🔐 [AuthService] User after state change: ${_currentUser?.email ?? "NULL"}');
      debugPrint('🔐 [AuthService] isAuthenticated: ${_currentUser != null}');
      notifyListeners();
    });
    
    // If currentSession exists on initialization, set isInitializing to false immediately
    if (_session != null) {
      debugPrint('✅ [AuthService] Session exists on init, setting isInitializing=false');
      _isInitializing = false;
    }
    
    // 🚀 AUTO-LOGIN FOR DEBUG MODE
    if (kDebugMode && _session == null) {
      debugPrint('🚀 [AuthService] DEBUG MODE: Auto-login enabled');
      _autoLoginForDebug();
    }
  }

  final SupabaseClient _client = Supabase.instance.client;
  StreamSubscription<AuthState>? _subscription;
  Session? _session;
  User? _currentUser;
  bool _isInitializing = true;

  SupabaseClient get client => _client;
  Session? get currentSession => _session;
  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isInitializing => _isInitializing;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<User> signInWithEmailAndPassword(String email, String password) async {
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    _syncAuth(response.session);
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
        // For web, redirect back to the current origin
        final origin = Uri.base.origin;
        redirectTo = origin.endsWith('/') ? origin : '$origin/';
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
    _syncAuth(_client.auth.currentSession);
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

  void _syncAuth(Session? session) {
    _session = session;
    _currentUser = session?.user ?? _client.auth.currentUser;
    _isInitializing = false;
    notifyListeners();
  }
  
  /// 🚀 AUTO-LOGIN FOR DEBUG MODE
  /// Automatically logs in with your credentials when running in debug mode
  Future<void> _autoLoginForDebug() async {
    try {
      // Read credentials from dart-defines (set in .vscode/launch.json)
      const debugEmail = String.fromEnvironment('DEBUG_EMAIL', defaultValue: '');
      const debugPassword = String.fromEnvironment('DEBUG_PASSWORD', defaultValue: '');
      
      if (debugEmail.isEmpty || debugPassword.isEmpty) {
        debugPrint('⚠️ [AuthService] Auto-login skipped: No credentials configured');
        debugPrint('💡 Set DEBUG_EMAIL and DEBUG_PASSWORD in .vscode/launch.json');
        return;
      }
      
      debugPrint('🚀 [AuthService] Attempting auto-login with: $debugEmail');
      
      await Future.delayed(const Duration(milliseconds: 500)); // Small delay to ensure Supabase is ready
      
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
