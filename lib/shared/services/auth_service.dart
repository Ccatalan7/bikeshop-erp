import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService extends ChangeNotifier {
  AuthService() {
    _session = _client.auth.currentSession;
    _currentUser = _session?.user;
    _isInitializing = false;

    _subscription = _client.auth.onAuthStateChange.listen((data) {
      _session = data.session;
      _currentUser = data.session?.user;
      _isInitializing = false;
      notifyListeners();
    });
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
        // For web, redirect back to the app
        redirectTo = Uri.base.origin + '/';
      } else {
        // For desktop/mobile, use deep link
        redirectTo = 'io.supabase.vinabikeerp://login-callback/';
      }
      
      final response = await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectTo,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      
      // For web/desktop OAuth, the session is handled via redirect callback
      // The auth state listener will update automatically
      return response;
    } catch (e) {
      if (kDebugMode) {
        print('Google Sign-In error: $e');
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

  Future<void> sendPasswordResetEmail(String email) async {
    await _client.auth.resetPasswordForEmail(email);
  }

  void _syncAuth(Session? session) {
    _session = session;
    _currentUser = session?.user ?? _client.auth.currentUser;
    _isInitializing = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
