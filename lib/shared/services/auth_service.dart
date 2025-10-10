import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService extends ChangeNotifier {
  AuthService() {
    _subscription = _auth.authStateChanges().listen((user) {
      _currentUser = user;
      _isInitializing = false;
      notifyListeners();
    });
  }

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  StreamSubscription<User?>? _subscription;
  User? _currentUser;
  bool _isInitializing = true;

  User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isInitializing => _isInitializing;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<UserCredential> signInWithEmailAndPassword(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    _syncUser(credential.user);
    return credential;
  }

  Future<UserCredential> createUserWithEmailAndPassword(String email, String password) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    _syncUser(credential.user);
    return credential;
  }

  Future<UserCredential> signInWithGoogle() async {
    if (kIsWeb) {
      final googleProvider = GoogleAuthProvider();
      googleProvider.addScope('email');
      final credential = await _auth.signInWithPopup(googleProvider);
      _syncUser(credential.user);
      return credential;
    }

    if (!kIsWeb && _isDesktopPlatform) {
      final googleProvider = GoogleAuthProvider()..addScope('email');
      final credential = await _auth.signInWithProvider(googleProvider);
      _syncUser(credential.user);
      return credential;
    }

    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        throw FirebaseAuthException(
          code: 'google-sign-in-cancelled',
          message: 'Inicio de sesión cancelado por el usuario.',
        );
      }

      final auth = await account.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: auth.accessToken,
        idToken: auth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
      _syncUser(userCredential.user);
      return userCredential;
    } on PlatformException catch (e) {
      throw FirebaseAuthException(
        code: 'google-sign-in-error',
        message: 'No se pudo iniciar sesión con Google: ${e.message}',
      );
    }
  }

  Future<UserCredential> signInAnonymously() async {
    final credential = await _auth.signInAnonymously();
    _syncUser(credential.user);
    return credential;
  }

  Future<void> signOut() async {
    await _auth.signOut();
    if (!kIsWeb) {
      await _googleSignIn.signOut();
    }
    _syncUser(null);
  }

  Future<void> sendPasswordResetEmail(String email) {
    return _auth.sendPasswordResetEmail(email: email);
  }

  void _syncUser(User? user) {
    _currentUser = user;
    _isInitializing = false;
    notifyListeners();
  }

  bool get _isDesktopPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}