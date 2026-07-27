import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shared/models/customer_address.dart';
import '../../shared/services/auth_redirect_urls.dart';
import '../../shared/services/self_password_service.dart';
import '../../shared/services/tenant_detection_service.dart';
import '../../shared/utils/auth_input_validation.dart';
import '../../shared/utils/web_url.dart';
import '../../modules/website/models/website_models.dart';

/// Service for managing customer accounts on the public store
///
/// Handles:
/// - Account creation and authentication
/// - Profile management
/// - Address book (multiple shipping addresses)
/// - Order history and tracking
/// - Bikes registered to customer
/// - Service history (mechanic jobs/trabajos)
enum CustomerAuthResult {
  success,
  emailVerificationRequired,
}

enum FirstPasswordInvitationTenantState {
  waiting,
  ready,
  unavailable,
}

enum CustomerPasswordUpdateIssue {
  reauthenticationRequired,
  invalidVerificationCode,
  expiredVerificationCode,
  samePassword,
  unknown,
}

class CustomerAccountService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  late final SelfPasswordService _passwordService =
      SelfPasswordService(_supabase);

  // Captured from the initial browser URL BEFORE Supabase.initialize() clears
  // the fragment. This is the only reliable way to detect a recovery session
  // because the passwordRecovery stream event fires during initialize() before
  // any subscriber has attached.
  static bool _wasInitiallyRecoveryUrl = false;
  static String? _initialRecoveryAccessToken;
  static String? _initialRecoveryRefreshToken;
  static String? _initialRecoveryCode;
  static String? _initialRecoveryTokenHash;
  static String? _initialInvitationTokenHash;

  static bool isPasswordRecoveryUri(Uri uri) {
    if (uri.path != '/cuenta/login') return false;
    final fragmentParams = _fragmentParameters(uri.fragment);
    final hasRecoveryType = uri.queryParameters['type'] == 'recovery' ||
        fragmentParams['type'] == 'recovery';
    final hasCode = uri.queryParameters['code']?.isNotEmpty == true;
    final hasAccessToken =
        uri.queryParameters['access_token']?.isNotEmpty == true ||
            fragmentParams['access_token']?.isNotEmpty == true;
    final tokenHash = fragmentParams['token_hash'];
    final hasTokenHash = tokenHash != null &&
        RegExp(r'^[A-Za-z0-9._~-]{20,512}$').hasMatch(tokenHash);
    return hasRecoveryType && (hasCode || hasAccessToken || hasTokenHash);
  }

  static bool isFirstPasswordInvitationUri(Uri uri) {
    if (uri.path != '/cuenta/login') return false;
    final fragmentParams = _fragmentParameters(uri.fragment);
    final tokenHash = fragmentParams['token_hash'];
    return fragmentParams['type'] == 'invite' &&
        tokenHash != null &&
        RegExp(r'^[A-Za-z0-9._~-]{20,512}$').hasMatch(tokenHash);
  }

  static FirstPasswordInvitationTenantState firstPasswordInvitationTenantState({
    required String? tenantId,
    required bool isLoading,
    required bool hasError,
  }) {
    if (tenantId?.trim().isNotEmpty == true) {
      return FirstPasswordInvitationTenantState.ready;
    }
    if (hasError && !isLoading) {
      return FirstPasswordInvitationTenantState.unavailable;
    }
    return FirstPasswordInvitationTenantState.waiting;
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

  /// Call this from main() BEFORE Supabase.initialize(), passing the raw
  /// browser URL (e.g. from getInitialBrowserUrl()).
  static void captureInitialUrl(String? url) {
    _wasInitiallyRecoveryUrl = false;
    _initialRecoveryAccessToken = null;
    _initialRecoveryRefreshToken = null;
    _initialRecoveryCode = null;
    _initialRecoveryTokenHash = null;
    _initialInvitationTokenHash = null;
    if (url == null || url.isEmpty) return;
    try {
      final parsedUrl = Uri.parse(url);
      final fragmentParams = _fragmentParameters(parsedUrl.fragment);
      final isRecovery = isPasswordRecoveryUri(parsedUrl);
      final isFirstPasswordInvitation = isFirstPasswordInvitationUri(parsedUrl);

      _wasInitiallyRecoveryUrl = isRecovery;
      _initialRecoveryAccessToken = isRecovery
          ? parsedUrl.queryParameters['access_token'] ??
              fragmentParams['access_token']
          : null;
      _initialRecoveryRefreshToken = isRecovery
          ? parsedUrl.queryParameters['refresh_token'] ??
              fragmentParams['refresh_token']
          : null;
      _initialRecoveryCode =
          isRecovery ? parsedUrl.queryParameters['code'] : null;
      _initialRecoveryTokenHash =
          isRecovery ? fragmentParams['token_hash'] : null;
      _initialInvitationTokenHash =
          isFirstPasswordInvitation ? fragmentParams['token_hash'] : null;
      if ((isRecovery || isFirstPasswordInvitation) &&
          parsedUrl.fragment.isNotEmpty) {
        clearSensitiveAuthFragment();
      }
    } on FormatException {
      // Malformed input is not Auth action evidence.
    }
  }

  User? _currentUser;
  Map<String, dynamic>? _customerProfile;
  String? _tenantId; // CRITICAL: Required for multi-tenant customer creation

  /// Set the tenant ID (must be called before any operations)
  void setTenantId(String? tenantId) {
    if (_tenantId == tenantId) return;
    _tenantId = tenantId;
    _customerProfile = null;
    if (_currentUser != null &&
        !_isFirstPasswordInvitationVerificationPending &&
        !_isPasswordRecoveryVerificationPending) {
      unawaited(_loadCustomerData());
    }
    notifyListeners();
  }

  String? get tenantId => _tenantId;
  List<CustomerAddress> _addresses = [];
  List<OnlineOrder> _orders = [];
  List<Map<String, dynamic>> _bikes = [];
  List<Map<String, dynamic>> _serviceHistory = [];
  bool _isLoading = false;
  String? _error;
  String? _pendingVerificationEmail;
  bool _isPasswordRecoverySession = false;
  bool _isPasswordRecoveryVerificationPending = false;
  bool _isCustomerMembershipLoading = false;
  bool _hasFirstPasswordInvitationIntent = false;
  bool _isRestoringInitialRecovery = false;
  bool _isFirstPasswordInvitationVerificationPending = false;
  String? _verifiedPasswordRecoveryUserId;
  String? _verifiedFirstPasswordInvitationUserId;
  String? _pendingOtherSessionsRevocationUserId;

  /// Expose so the ERP or test code can clear the flag after use.
  void clearPasswordRecoverySession() {
    _isPasswordRecoverySession = false;
    _isPasswordRecoveryVerificationPending = false;
    _verifiedPasswordRecoveryUserId = null;
    _wasInitiallyRecoveryUrl = false;
    _clearInitialRecoveryEvidence();
    notifyListeners();
  }

  User? get currentUser => _currentUser;
  Map<String, dynamic>? get customerProfile => _customerProfile;
  List<CustomerAddress> get addresses => _addresses;
  List<OnlineOrder> get orders => _orders;
  List<Map<String, dynamic>> get bikes => _bikes;
  List<Map<String, dynamic>> get serviceHistory => _serviceHistory;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get hasAuthSession => _currentUser != null;
  bool get isAuthenticated =>
      _currentUser != null &&
      _customerProfile?['auth_user_id']?.toString() == _currentUser!.id &&
      _customerProfile?['tenant_id']?.toString() == _tenantId;
  bool get isCustomerMembershipLoading => _isCustomerMembershipLoading;
  bool get requiresEmailVerification => _pendingVerificationEmail != null;
  String? get pendingVerificationEmail => _pendingVerificationEmail;
  bool get isPasswordRecoverySession => _isPasswordRecoverySession;
  bool get isPasswordRecoveryVerificationPending =>
      _isPasswordRecoveryVerificationPending;
  bool get hasFirstPasswordInvitationIntent =>
      _hasFirstPasswordInvitationIntent;
  bool get isFirstPasswordInvitationVerificationPending =>
      _isFirstPasswordInvitationVerificationPending;
  bool get hasPendingOtherSessionsRevocation =>
      _currentUser != null &&
      _pendingOtherSessionsRevocationUserId == _currentUser!.id;

  Future<bool> reloadCustomerMembership() => _loadCustomerData();

  CustomerAccountService() {
    final hasCapturedRecoveryIntent = _wasInitiallyRecoveryUrl;
    final recoveryTokenHash = _initialRecoveryTokenHash;
    final invitationTokenHash = _initialInvitationTokenHash;
    _wasInitiallyRecoveryUrl = false;
    _initialRecoveryTokenHash = null;
    _initialInvitationTokenHash = null;
    _isFirstPasswordInvitationVerificationPending = invitationTokenHash != null;

    final currentSession = _supabase.auth.currentSession;
    _currentUser = _supabase.auth.currentUser;
    _isPasswordRecoverySession = recoveryTokenHash == null &&
        hasCapturedRecoveryIntent &&
        _sessionMatchesInitialRecoveryEvidence(currentSession);
    _isPasswordRecoveryVerificationPending =
        hasCapturedRecoveryIntent && !_isPasswordRecoverySession;

    if (invitationTokenHash != null) {
      unawaited(_verifyInitialFirstPasswordInvitation(invitationTokenHash));
    } else if (recoveryTokenHash != null) {
      unawaited(_verifyInitialPasswordRecovery(recoveryTokenHash));
    } else if (_isPasswordRecoverySession) {
      _clearInitialRecoveryEvidence();
    } else if (hasCapturedRecoveryIntent) {
      unawaited(_restoreRecoverySessionFromInitialUrl());
    } else if (_currentUser != null) {
      unawaited(_loadCustomerData());
    }

    // Listen to auth state changes
    _supabase.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.passwordRecovery) {
        final nextUser = data.session?.user;
        if (_pendingOtherSessionsRevocationUserId != null &&
            _pendingOtherSessionsRevocationUserId != nextUser?.id) {
          _pendingOtherSessionsRevocationUserId = null;
        }
        _currentUser = nextUser;
        _verifiedPasswordRecoveryUserId = data.session?.user.id;
        _isPasswordRecoverySession = data.session != null;
        if (!_isFirstPasswordInvitationVerificationPending &&
            !_isPasswordRecoveryVerificationPending) {
          unawaited(_loadCustomerData());
        }
        notifyListeners();
      } else if (event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.initialSession) {
        // Don't override recovery mode if we just established it from the URL.
        final nextUser = data.session?.user;
        if (_pendingOtherSessionsRevocationUserId != null &&
            _pendingOtherSessionsRevocationUserId != nextUser?.id) {
          _pendingOtherSessionsRevocationUserId = null;
        }
        _currentUser = nextUser;
        if (_hasFirstPasswordInvitationIntent &&
            data.session?.user.id != _verifiedFirstPasswordInvitationUserId) {
          _clearFirstPasswordInvitationEvidence();
        }
        if (!_isPasswordRecoverySession &&
            !_isFirstPasswordInvitationVerificationPending &&
            !_isPasswordRecoveryVerificationPending) {
          unawaited(_loadCustomerData());
        }
        notifyListeners();
      } else if (event == AuthChangeEvent.userUpdated) {
        // Password was changed — clear recovery state and treat as normal sign-in.
        _isPasswordRecoverySession = false;
        _verifiedPasswordRecoveryUserId = null;
        _currentUser = data.session?.user;
        unawaited(_loadCustomerData());
        notifyListeners();
      } else if (event == AuthChangeEvent.signedOut) {
        _currentUser = null;
        _pendingOtherSessionsRevocationUserId = null;
        _isPasswordRecoverySession = false;
        _verifiedPasswordRecoveryUserId = null;
        _isCustomerMembershipLoading = false;
        _clearFirstPasswordInvitationEvidence();
        _customerProfile = null;
        _addresses = [];
        _orders = [];
        _bikes = [];
        _serviceHistory = [];
        notifyListeners();
      }
    });
  }

  Future<void> _verifyInitialPasswordRecovery(String tokenHash) async {
    try {
      final response = await _supabase.auth.verifyOTP(
        tokenHash: tokenHash,
        type: OtpType.recovery,
      );
      final recoverySession = response.session;
      if (recoverySession == null) {
        throw const AuthException(
          'No pudimos validar el enlace de recuperación.',
        );
      }

      _currentUser = recoverySession.user;
      _verifiedPasswordRecoveryUserId = recoverySession.user.id;
      _isPasswordRecoverySession = true;
    } catch (_) {
      _isPasswordRecoverySession = false;
      _verifiedPasswordRecoveryUserId = null;
      _currentUser = _supabase.auth.currentUser;
      debugPrint('⚠️ [CustomerAuth] Recovery verification failed');
    } finally {
      _clearInitialRecoveryEvidence();
      _isPasswordRecoveryVerificationPending = false;
      notifyListeners();
    }
  }

  Future<void> _verifyInitialFirstPasswordInvitation(String tokenHash) async {
    try {
      final response = await _supabase.auth.verifyOTP(
        tokenHash: tokenHash,
        type: OtpType.invite,
      );
      final invitationSession = response.session;
      if (invitationSession == null) {
        throw const AuthException(
          'No pudimos validar la invitación de acceso.',
        );
      }

      _currentUser = invitationSession.user;
      _verifiedFirstPasswordInvitationUserId = invitationSession.user.id;
      _hasFirstPasswordInvitationIntent = true;

      if (_tenantId?.isNotEmpty == true) {
        await _loadCustomerData(rethrowOnFailure: true);
      }
    } catch (_) {
      _hasFirstPasswordInvitationIntent = false;
      _verifiedFirstPasswordInvitationUserId = null;
      _currentUser = _supabase.auth.currentUser;
      debugPrint('⚠️ [CustomerAuth] Invitation verification failed');
    } finally {
      _isFirstPasswordInvitationVerificationPending = false;
      notifyListeners();
    }
  }

  Future<void> _restoreRecoverySessionFromInitialUrl() async {
    if (_isRestoringInitialRecovery) return;
    _isRestoringInitialRecovery = true;
    try {
      final existingSession = _supabase.auth.currentSession;
      if (_sessionMatchesInitialRecoveryEvidence(existingSession)) {
        _currentUser = existingSession?.user;
        _isPasswordRecoverySession = true;
        _verifiedPasswordRecoveryUserId = existingSession?.user.id;
        notifyListeners();
        return;
      }

      final refreshToken = _initialRecoveryRefreshToken;
      final recoveryCode = _initialRecoveryCode;
      var restoredFromCapturedCredential = false;

      if (refreshToken != null && refreshToken.isNotEmpty) {
        await _supabase.auth.setSession(refreshToken);
        restoredFromCapturedCredential = true;
      } else if (recoveryCode != null && recoveryCode.isNotEmpty) {
        await _supabase.auth.exchangeCodeForSession(recoveryCode);
        restoredFromCapturedCredential = true;
      }

      final session = _supabase.auth.currentSession;
      _isPasswordRecoverySession =
          restoredFromCapturedCredential && session != null;
      _currentUser = session?.user;
      _verifiedPasswordRecoveryUserId =
          _isPasswordRecoverySession ? session?.user.id : null;
    } catch (_) {
      _isPasswordRecoverySession = false;
      _verifiedPasswordRecoveryUserId = null;
      debugPrint('⚠️ [CustomerAuth] Recovery session restoration failed');
    } finally {
      _clearInitialRecoveryEvidence();
      _isPasswordRecoveryVerificationPending = false;
      _isRestoringInitialRecovery = false;
      notifyListeners();
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

    // A PKCE code cannot be correlated to an already-present session without
    // consuming it. Never infer recovery authority from recoverySentAt: that
    // could bind a link for user B to a recent session for user A.
    return false;
  }

  static void _clearInitialRecoveryEvidence() {
    _initialRecoveryAccessToken = null;
    _initialRecoveryRefreshToken = null;
    _initialRecoveryCode = null;
    _initialRecoveryTokenHash = null;
  }

  // ============================================================================
  // AUTHENTICATION
  // ============================================================================

  /// Sign up with email and password
  Future<CustomerAuthResult> signUp({
    required String email,
    required String password,
    required String name,
    String? phone,
  }) async {
    try {
      _requireStrongNewPassword(password);
      _isLoading = true;
      _error = null;
      notifyListeners();

      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo:
            kIsWeb ? '${Uri.base.origin}/cuenta/login?confirmed=true' : null,
        data: {
          'account_type': 'public_store_customer',
          'name': name,
          'phone': phone,
        },
      );

      final session = response.session;
      final user = response.user;

      if (session == null || user?.emailConfirmedAt == null) {
        // Email confirmation required before session becomes active.
        _pendingVerificationEmail = email;
        _currentUser = null;
        _customerProfile = null;
        _addresses = [];
        _orders = [];
        return CustomerAuthResult.emailVerificationRequired;
      }

      _pendingVerificationEmail = null;
      _currentUser = user;
      // Tenant authority comes from the current storefront URL. This invokes
      // the tenant-scoped provisioning RPC before reading the customer profile.
      await _loadCustomerData(rethrowOnFailure: true);

      // Update phone if provided
      if (phone != null && phone.isNotEmpty) {
        await updateProfile(phone: phone);
      }

      return CustomerAuthResult.success;
    } catch (_) {
      if (_currentUser != null && _customerProfile == null) {
        await _supabase.auth.signOut(scope: SignOutScope.local);
        _currentUser = null;
      }
      _error = 'No pudimos crear la cuenta.';
      debugPrint('⚠️ [CustomerAuth] Account signup failed');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sign in with email and password
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      _pendingVerificationEmail = null;
      _currentUser = response.user;
      await _loadCustomerData(rethrowOnFailure: true);
    } on AuthException catch (e) {
      if (_currentUser != null && _customerProfile == null) {
        await _supabase.auth.signOut(scope: SignOutScope.local);
        _currentUser = null;
      }
      if (e.message.toLowerCase().contains('email') &&
          e.message.toLowerCase().contains('confirm')) {
        _pendingVerificationEmail = email;
        _error =
            'Tu correo electrónico aún no está verificado. Revisa tu bandeja de entrada.';
      } else {
        _error = 'No pudimos iniciar sesión.';
      }
      debugPrint('⚠️ [CustomerAuth] Email sign-in failed');
      rethrow;
    } catch (_) {
      if (_currentUser != null && _customerProfile == null) {
        await _supabase.auth.signOut(scope: SignOutScope.local);
        _currentUser = null;
      }
      _error = 'No pudimos iniciar sesión.';
      debugPrint('⚠️ [CustomerAuth] Email sign-in failed');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> resendVerificationEmail() async {
    final email = _pendingVerificationEmail;
    if (email == null) return;

    try {
      await _supabase.auth.resend(
        type: OtpType.signup,
        email: email,
        emailRedirectTo:
            kIsWeb ? '${Uri.base.origin}/cuenta/login?confirmed=true' : null,
      );
    } catch (_) {
      debugPrint('⚠️ [CustomerAuth] Verification resend failed');
      rethrow;
    }
  }

  /// Sign in with Google
  Future<void> signInWithGoogle() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final tenantId = _tenantId;
      if (tenantId == null || tenantId.isEmpty) {
        throw StateError(
          'No pudimos identificar la tienda. Recarga la página antes de continuar con Google.',
        );
      }

      final redirectTo = AuthRedirectUrls.authCallback(isWeb: kIsWeb);
      if (redirectTo == null) {
        throw const AuthException(
          'El inicio de sesión con Google no está configurado para esta plataforma.',
        );
      }

      // OAuth cannot safely provision a storefront customer before the provider
      // redirects back. The auth listener calls the tenant-scoped, idempotent
      // provisioning RPC before reading any customer profile.
      await _supabase.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: redirectTo,
      );
    } catch (_) {
      _error = 'No pudimos iniciar sesión con Google.';
      debugPrint('⚠️ [CustomerAuth] Google sign-in failed');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
      _currentUser = null;
      _customerProfile = null;
      _addresses = [];
      _orders = [];
      _bikes = [];
      _serviceHistory = [];
      _isPasswordRecoverySession = false;
      _isPasswordRecoveryVerificationPending = false;
      _verifiedPasswordRecoveryUserId = null;
      _isCustomerMembershipLoading = false;
      _pendingOtherSessionsRevocationUserId = null;
      _clearFirstPasswordInvitationEvidence();
      _clearInitialRecoveryEvidence();
      notifyListeners();
    } catch (_) {
      _error = 'No pudimos cerrar la sesión.';
      debugPrint('⚠️ [CustomerAuth] Sign-out failed');
      rethrow;
    }
  }

  /// Reset password (send email)
  Future<void> resetPassword(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(
        email,
        redirectTo:
            kIsWeb ? '${Uri.base.origin}/cuenta/login?recovery=true' : null,
      );
    } catch (_) {
      _error = 'No pudimos procesar la recuperación.';
      debugPrint('⚠️ [CustomerAuth] Recovery request failed');
      rethrow;
    }
  }

  /// Update password for the currently signed-in customer.
  Future<SelfPasswordUpdateResult> updatePassword(
    String newPassword, {
    String? reauthenticationNonce,
  }) async {
    try {
      _requireStrongNewPassword(newPassword);
      if (_supabase.auth.currentSession == null && _isPasswordRecoverySession) {
        await _restoreRecoverySessionFromInitialUrl();
      }

      final session = _supabase.auth.currentSession;
      if (_isPasswordRecoveryVerificationPending ||
          (_isPasswordRecoverySession &&
              (_verifiedPasswordRecoveryUserId == null ||
                  session?.user.id != _verifiedPasswordRecoveryUserId))) {
        throw const AuthException(
          'No pudimos confirmar la sesión de recuperación.',
        );
      }

      final passwordUserId = session?.user.id ??
          _supabase.auth.currentUser?.id ??
          _currentUser?.id;
      final result = await _passwordService.updatePassword(
        newPassword,
        reauthenticationNonce: reauthenticationNonce,
      );
      _pendingOtherSessionsRevocationUserId =
          result.needsOtherSessionsRevocationRetry ? passwordUserId : null;
      _isPasswordRecoverySession = false;
      _verifiedPasswordRecoveryUserId = null;
      _clearInitialRecoveryEvidence();
      notifyListeners();
      return result;
    } catch (_) {
      _error = 'No pudimos actualizar la contraseña.';
      debugPrint('⚠️ [CustomerAuth] Password update failed');
      rethrow;
    }
  }

  Future<SelfPasswordOtherSessionsRevocationOutcome>
      retryOtherSessionRevocation() async {
    if (!hasPendingOtherSessionsRevocation) {
      throw StateError('No other-session revocation retry is pending');
    }

    final outcome = await _passwordService.retryOtherSessionRevocation();
    if (outcome == SelfPasswordOtherSessionsRevocationOutcome.revoked) {
      _pendingOtherSessionsRevocationUserId = null;
    }
    notifyListeners();
    return outcome;
  }

  /// Sends the signed-in customer a one-time code for a sensitive password
  /// change. Supabase decides whether the code is delivered by email or phone.
  Future<void> requestPasswordReauthentication() async {
    try {
      _error = null;
      await _passwordService.requestReauthentication();
    } catch (_) {
      _error = 'No pudimos enviar el código de verificación.';
      debugPrint('⚠️ [CustomerAuth] Password reauthentication request failed');
      rethrow;
    }
  }

  static CustomerPasswordUpdateIssue classifyPasswordUpdateError(
    Object error,
  ) {
    return switch (SelfPasswordService.classifyUpdateError(error)) {
      SelfPasswordUpdateIssue.reauthenticationRequired =>
        CustomerPasswordUpdateIssue.reauthenticationRequired,
      SelfPasswordUpdateIssue.invalidVerificationCode =>
        CustomerPasswordUpdateIssue.invalidVerificationCode,
      SelfPasswordUpdateIssue.expiredVerificationCode =>
        CustomerPasswordUpdateIssue.expiredVerificationCode,
      SelfPasswordUpdateIssue.samePassword =>
        CustomerPasswordUpdateIssue.samePassword,
      SelfPasswordUpdateIssue.unknown => CustomerPasswordUpdateIssue.unknown,
    };
  }

  /// Completes a password reset only for the user verified by the recovery
  /// credential captured from the current Auth link.
  Future<void> completePasswordRecovery(String newPassword) async {
    final session = _supabase.auth.currentSession;
    if (_isPasswordRecoveryVerificationPending ||
        !_isPasswordRecoverySession ||
        _verifiedPasswordRecoveryUserId == null ||
        session?.user.id != _verifiedPasswordRecoveryUserId) {
      throw const AuthException(
        'No pudimos confirmar la sesión de recuperación.',
      );
    }

    await updatePassword(newPassword);
  }

  /// Completes the first-password flow opened from an Auth invitation.
  ///
  /// The page must set the URL-resolved storefront tenant before calling this.
  /// Provisioning remains server-owned and tenant-scoped.
  Future<void> completeInvitedFirstPassword(String newPassword) async {
    final tenantId = _tenantId;
    final invitationSession = _supabase.auth.currentSession;
    if (!_hasFirstPasswordInvitationIntent ||
        invitationSession == null ||
        invitationSession.user.id != _verifiedFirstPasswordInvitationUserId ||
        tenantId == null ||
        tenantId.isEmpty) {
      throw const AuthException(
        'No pudimos validar la invitación de acceso.',
      );
    }

    await _loadCustomerData(rethrowOnFailure: true);
    if (_customerProfile?['tenant_id']?.toString() != tenantId) {
      throw const AuthException(
        'No pudimos preparar la cuenta para esta tienda.',
      );
    }

    await updatePassword(newPassword);
    _clearFirstPasswordInvitationEvidence();
  }

  void clearFirstPasswordInvitationIntent() {
    _clearFirstPasswordInvitationEvidence();
    notifyListeners();
  }

  void _clearFirstPasswordInvitationEvidence() {
    _hasFirstPasswordInvitationIntent = false;
    _verifiedFirstPasswordInvitationUserId = null;
    _initialInvitationTokenHash = null;
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

  // ============================================================================
  // PROFILE MANAGEMENT
  // ============================================================================

  Future<bool> _loadCustomerData({
    bool rethrowOnFailure = false,
  }) async {
    if (_currentUser == null) {
      _customerProfile = null;
      _isCustomerMembershipLoading = false;
      return false;
    }

    _isCustomerMembershipLoading = true;
    _customerProfile = null;
    _error = null;
    notifyListeners();

    try {
      // AUTO-DETECT tenant from URL if not already set
      if (_tenantId == null && kIsWeb) {
        final detectionService = TenantDetectionService();
        final tenant = await detectionService.detectTenant();
        if (tenant != null) {
          _tenantId = tenant.id;
          debugPrint(
              '🔍 Auto-detected tenant: ${tenant.shopName} (${tenant.id})');
        }
      }

      final tenantId = _tenantId;
      if (tenantId == null || tenantId.isEmpty) {
        throw const AuthException(
          'No pudimos identificar la tienda para esta cuenta.',
        );
      }

      // This RPC is idempotent and tenant-scoped. It is the only customer
      // provisioning path used after OAuth; direct client inserts are denied.
      await _supabase.rpc(
        'provision_current_public_store_customer',
        params: {'p_tenant_id': tenantId},
      );

      final profileResponse = await _supabase
          .from('customers')
          .select()
          .eq('auth_user_id', _currentUser!.id)
          .eq('tenant_id', tenantId)
          .maybeSingle();

      if (profileResponse == null) {
        throw const AuthException(
          'No pudimos preparar la cuenta para esta tienda.',
        );
      }

      _customerProfile = profileResponse;

      // Load addresses, orders, bikes, and service history in parallel
      await Future.wait([
        loadAddresses(),
        loadOrders(),
        loadBikes(),
        loadServiceHistory(),
      ]);
      _error = null;
      return true;
    } catch (error) {
      _customerProfile = null;
      _addresses = [];
      _orders = [];
      _bikes = [];
      _serviceHistory = [];
      _error = 'No pudimos cargar la cuenta de esta tienda.';
      debugPrint('⚠️ [CustomerAuth] Tenant customer load failed');
      if (rethrowOnFailure) rethrow;
      return false;
    } finally {
      _isCustomerMembershipLoading = false;
      notifyListeners();
    }
  }

  /// Update customer profile
  Future<void> updateProfile({
    String? name,
    String? phone,
    String? rut,
    String? imageUrl,
  }) async {
    if (_customerProfile == null) return;

    try {
      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      if (phone != null) updates['phone'] = phone;
      if (rut != null) updates['rut'] = rut;
      if (imageUrl != null) updates['image_url'] = imageUrl;

      if (updates.isEmpty) return;

      updates['updated_at'] = DateTime.now().toIso8601String();

      await _supabase
          .from('customers')
          .update(updates)
          .eq('id', _customerProfile!['id']);

      await _loadCustomerData();
    } catch (e) {
      _error = 'Error al actualizar perfil: $e';
      debugPrint(_error);
      rethrow;
    }
  }

  // ============================================================================
  // ADDRESS MANAGEMENT
  // ============================================================================

  Future<void> loadAddresses() async {
    if (_customerProfile == null) return;

    try {
      final response = await _supabase
          .from('customer_addresses')
          .select()
          .eq('customer_id', _customerProfile!['id'])
          .order('is_default', ascending: false)
          .order('created_at', ascending: false);

      _addresses = (response as List)
          .map((json) => CustomerAddress.fromJson(json))
          .toList();

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading addresses: $e');
    }
  }

  Future<void> addAddress(CustomerAddress address) async {
    if (_customerProfile == null) return;

    try {
      final data = address.toJson();
      data['customer_id'] = _customerProfile!['id'];
      data['tenant_id'] =
          _customerProfile!['tenant_id']; // CRITICAL: Required for RLS
      data.remove('id'); // Let database generate ID

      await _supabase.from('customer_addresses').insert(data);
      await loadAddresses();
    } catch (e) {
      _error = 'Error al agregar dirección: $e';
      debugPrint(_error);
      rethrow;
    }
  }

  Future<void> updateAddress(CustomerAddress address) async {
    try {
      await _supabase
          .from('customer_addresses')
          .update(address.toJson())
          .eq('id', address.id);

      await loadAddresses();
    } catch (e) {
      _error = 'Error al actualizar dirección: $e';
      debugPrint(_error);
      rethrow;
    }
  }

  Future<void> deleteAddress(String addressId) async {
    try {
      await _supabase.from('customer_addresses').delete().eq('id', addressId);

      await loadAddresses();
    } catch (e) {
      _error = 'Error al eliminar dirección: $e';
      debugPrint(_error);
      rethrow;
    }
  }

  Future<void> setDefaultAddress(String addressId) async {
    try {
      await _supabase
          .from('customer_addresses')
          .update({'is_default': true}).eq('id', addressId);

      await loadAddresses();
    } catch (e) {
      _error = 'Error al establecer dirección predeterminada: $e';
      debugPrint(_error);
      rethrow;
    }
  }

  CustomerAddress? get defaultAddress {
    try {
      return _addresses.firstWhere((addr) => addr.isDefault);
    } catch (e) {
      return _addresses.isNotEmpty ? _addresses.first : null;
    }
  }

  // ============================================================================
  // ORDER HISTORY
  // ============================================================================

  Future<void> loadOrders() async {
    if (_customerProfile == null) return;

    try {
      // Load orders with their items using Supabase foreign key relationship
      final response = await _supabase
          .from('online_orders')
          .select('''
            *,
            online_order_items (*)
          ''')
          .eq('customer_id', _customerProfile!['id'])
          .order('created_at', ascending: false);

      _orders = (response as List).map((json) {
        // Extract items from the nested response
        final itemsJson = json['online_order_items'] as List? ?? [];
        final items = itemsJson
            .map((item) =>
                OnlineOrderItem.fromJson(item as Map<String, dynamic>))
            .toList();

        // Create order with items
        return OnlineOrder.fromJson(json).copyWith(items: items);
      }).toList();

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading orders: $e');
    }
  }

  Future<OnlineOrder?> getOrderById(String orderId) async {
    try {
      // Load order with items
      final response = await _supabase.from('online_orders').select('''
            *,
            online_order_items (*)
          ''').eq('id', orderId).single();

      // Extract items
      final itemsJson = response['online_order_items'] as List? ?? [];
      final items = itemsJson
          .map((item) => OnlineOrderItem.fromJson(item as Map<String, dynamic>))
          .toList();

      return OnlineOrder.fromJson(response).copyWith(items: items);
    } catch (e) {
      debugPrint('Error loading order: $e');
      return null;
    }
  }

  // ============================================================================
  // BIKES MANAGEMENT
  // ============================================================================

  /// Load customer's registered bikes with service count
  Future<void> loadBikes() async {
    if (_customerProfile == null) return;

    try {
      _isLoading = true;
      notifyListeners();

      // Get bikes with brand/model info
      final response = await _supabase
          .from('bikes')
          .select('''
            *,
            bike_brands(name),
            bike_models(name)
          ''')
          .eq('customer_id', _customerProfile!['id'])
          .eq('is_active', true)
          .order('created_at', ascending: false);

      _bikes = List<Map<String, dynamic>>.from(response);

      // Enrich with service count and last service date
      for (var i = 0; i < _bikes.length; i++) {
        final bikeId = _bikes[i]['id'];

        // Get service count
        final countResponse = await _supabase
            .from('mechanic_jobs')
            .select('id')
            .eq('bike_id', bikeId)
            .isFilter('deleted_at', null);

        _bikes[i]['service_count'] = (countResponse as List).length;

        // Get last service date
        final lastServiceResponse = await _supabase
            .from('mechanic_jobs')
            .select('completed_at, delivered_at')
            .eq('bike_id', bikeId)
            .isFilter('deleted_at', null)
            .order('created_at', ascending: false)
            .limit(1);

        if ((lastServiceResponse as List).isNotEmpty) {
          final lastService = lastServiceResponse.first;
          _bikes[i]['last_service_date'] =
              lastService['delivered_at'] ?? lastService['completed_at'];
        }

        // Extract brand/model names from joins
        if (_bikes[i]['bike_brands'] != null) {
          _bikes[i]['brand_name'] = _bikes[i]['bike_brands']['name'];
        }
        if (_bikes[i]['bike_models'] != null) {
          _bikes[i]['model_name'] = _bikes[i]['bike_models']['name'];
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading bikes: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Get a single bike by ID
  Future<Map<String, dynamic>?> getBikeById(String bikeId) async {
    try {
      final response = await _supabase.from('bikes').select('''
            *,
            bike_brands(name),
            bike_models(name)
          ''').eq('id', bikeId).single();

      final bike = Map<String, dynamic>.from(response);

      // Extract brand/model names
      if (bike['bike_brands'] != null) {
        bike['brand_name'] = bike['bike_brands']['name'];
      }
      if (bike['bike_models'] != null) {
        bike['model_name'] = bike['bike_models']['name'];
      }

      return bike;
    } catch (e) {
      debugPrint('Error loading bike: $e');
      return null;
    }
  }

  // ============================================================================
  // SERVICE HISTORY (MECHANIC JOBS / PEGAS)
  // ============================================================================

  /// Load customer's service history (mechanic jobs)
  Future<void> loadServiceHistory() async {
    if (_customerProfile == null) return;

    try {
      _isLoading = true;
      notifyListeners();

      debugPrint(
          '📋 Loading service history for customer: ${_customerProfile!['id']}');

      // Query mechanic_jobs without join first (RLS might block joins)
      final response = await _supabase
          .from('mechanic_jobs')
          .select('*')
          .eq('customer_id', _customerProfile!['id'])
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false);

      debugPrint('📋 Found ${response.length} mechanic jobs');

      _serviceHistory = List<Map<String, dynamic>>.from(response);

      // Load bike info separately for each job
      for (var i = 0; i < _serviceHistory.length; i++) {
        final bikeId = _serviceHistory[i]['bike_id'];
        if (bikeId != null) {
          try {
            final bikeResponse = await _supabase
                .from('bikes')
                .select('brand, model, color, bike_type')
                .eq('id', bikeId)
                .maybeSingle();

            if (bikeResponse != null) {
              _serviceHistory[i]['bike_brand'] = bikeResponse['brand'] ?? '';
              _serviceHistory[i]['bike_model'] = bikeResponse['model'] ?? '';
              _serviceHistory[i]['bike_color'] = bikeResponse['color'];
              _serviceHistory[i]['bike_type'] = bikeResponse['bike_type'];
            }
          } catch (e) {
            debugPrint('⚠️ Could not load bike $bikeId: $e');
          }
        }
      }

      debugPrint('📋 Service history loaded: ${_serviceHistory.length} items');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error loading service history: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Get service history for a specific bike
  Future<List<Map<String, dynamic>>> getServiceHistoryForBike(
      String bikeId) async {
    try {
      final response = await _supabase
          .from('mechanic_jobs')
          .select('*')
          .eq('bike_id', bikeId)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error loading bike service history: $e');
      return [];
    }
  }

  /// Get a single service job by ID
  Future<Map<String, dynamic>?> getServiceById(String jobId) async {
    try {
      final response = await _supabase.from('mechanic_jobs').select('''
            *,
            bikes(brand, model, color, bike_type, serial_number),
            mechanic_job_parts(
              id,
              product_id,
              product_name,
              quantity,
              unit_price,
              subtotal
            )
          ''').eq('id', jobId).single();

      return Map<String, dynamic>.from(response);
    } catch (e) {
      debugPrint('Error loading service: $e');
      return null;
    }
  }

  /// Get active services count (not delivered or cancelled)
  int get activeServicesCount {
    return _serviceHistory
        .where((s) => !['ENTREGADO', 'CANCELADO'].contains(s['status']))
        .length;
  }

  /// Get services awaiting customer approval
  List<Map<String, dynamic>> get servicesAwaitingApproval {
    return _serviceHistory
        .where((s) =>
            s['status'] == 'ESPERANDO_APROBACION' &&
            s['approved_by_customer'] != true)
        .toList();
  }
}
