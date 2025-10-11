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
      throw AuthException('No se pudo obtener el usuario después del inicio de sesión.');
    }
    return user;
  }

  Future<User> createUserWithEmailAndPassword(String email, String password) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: null,
    );
    _syncAuth(response.session);
    final user = response.user ?? _client.auth.currentUser;
    if (user == null) {
      throw AuthException('Revisa tu correo para confirmar la cuenta antes de iniciar sesión.');
    }
    return user;
  }

  Future<bool> signInWithGoogle() async {
    try {
      // For desktop/mobile apps, Supabase handles the OAuth flow automatically
      // The session will be updated via the auth state listener
      final response = await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        // No redirectTo needed - Supabase handles it automatically for desktop
      );
      return response;
    } catch (e) {
      throw AuthException('Error al iniciar sesión con Google: ${e.toString()}');
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