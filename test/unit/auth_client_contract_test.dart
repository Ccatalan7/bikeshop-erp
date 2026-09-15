import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String loginSource;
  late String resetPasswordSource;
  late String authServiceSource;
  late String invitationSource;
  late String employeePageSource;
  late String hrServiceSource;
  late String userManagementPageSource;
  late String userManagementServiceSource;
  late String customerAuthPageSource;
  late String customerAccountServiceSource;
  late String selfPasswordServiceSource;
  late String publicStoreRouterSource;
  late String routerSource;
  late String tenantServiceSource;
  late String documentAccountingContextSource;

  setUpAll(() {
    loginSource =
        File('lib/shared/screens/login_screen.dart').readAsStringSync();
    resetPasswordSource = File(
      'lib/shared/screens/reset_password_screen.dart',
    ).readAsStringSync();
    authServiceSource =
        File('lib/shared/services/auth_service.dart').readAsStringSync();
    invitationSource = File(
      'lib/modules/auth/pages/accept_invitation_page.dart',
    ).readAsStringSync();
    employeePageSource = File(
      'lib/modules/hr/pages/employee_list_page.dart',
    ).readAsStringSync();
    hrServiceSource =
        File('lib/modules/hr/services/hr_service.dart').readAsStringSync();
    userManagementPageSource = File(
      'lib/modules/settings/pages/user_management_page.dart',
    ).readAsStringSync();
    userManagementServiceSource = File(
      'lib/shared/services/user_management_service.dart',
    ).readAsStringSync();
    customerAuthPageSource = File(
      'lib/public_store/pages/customer_auth_page.dart',
    ).readAsStringSync();
    customerAccountServiceSource = File(
      'lib/public_store/services/customer_account_service.dart',
    ).readAsStringSync();
    selfPasswordServiceSource = File(
      'lib/shared/services/self_password_service.dart',
    ).readAsStringSync();
    publicStoreRouterSource = File(
      'lib/public_store/routes/public_store_router.dart',
    ).readAsStringSync();
    routerSource = File('lib/shared/routes/app_router.dart').readAsStringSync();
    tenantServiceSource =
        File('lib/shared/services/tenant_service.dart').readAsStringSync();
    documentAccountingContextSource = File(
      'lib/shared/services/document_accounting_context_service.dart',
    ).readAsStringSync();
  });

  test('tenant-owner signup has one server-owned provisioning path', () {
    expect(loginSource, contains('authService.signUpTenantOwner('));
    expect(loginSource, isNot(contains('TenantSignupService')));
    expect(loginSource, isNot(contains(".from('tenants')")));
    expect(loginSource, isNot(contains(".from('user_profiles')")));
    expect(
      File('lib/shared/services/tenant_signup_service.dart').existsSync(),
      isFalse,
    );

    expect(authServiceSource, contains("'shop_name': shopName"));
    expect(authServiceSource, contains("'subdomain': subdomain"));
    expect(loginSource, contains("ValueKey('auth-email')"));
    expect(loginSource, contains('_formKey.currentState?.reset()'));
  });

  test('staff invitation lookup and acceptance stay server-authoritative', () {
    expect(
      invitationSource,
      contains("'lookup_user_invitation_identity'"),
    );
    expect(invitationSource, contains("invitation['account_exists']"));
    expect(invitationSource, contains("'p_token': token"));
    expect(invitationSource, contains('signUpStaffInvitation('));
    expect(invitationSource, contains("'accept_user_invitation'"));
    expect(invitationSource, contains('accepted != true'));
    expect(invitationSource, contains('signInWithEmailAndPassword(email,'));
    expect(invitationSource, contains('Ya tengo cuenta'));
    expect(invitationSource, isNot(contains(".from('user_invitations')")));
    expect(invitationSource, isNot(contains(".from('employees')")));
    expect(invitationSource, isNot(contains('debugPrint(')));
    expect(invitationSource, isNot(contains('already registered')));
    expect(
      invitationSource,
      contains('if (authResponse.session != null)'),
    );

    expect(
      authServiceSource,
      contains("'account_type': 'staff_invitation'"),
    );
    expect(
      authServiceSource,
      contains("'invitation_token': invitationToken"),
    );
  });

  test('invitation and recovery links are never exposed by Flutter UI', () {
    final dartSources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');

    expect(dartSources, isNot(contains('invitationLink')));
    expect(dartSources, isNot(contains('accessLink')));
    expect(dartSources, isNot(contains('temporaryPassword')));
    expect(dartSources, isNot(contains("'temporary_password'")));
    expect(dartSources, isNot(contains("'confirm_email'")));
    expect(dartSources, isNot(contains('Confirmar email manualmente')));
    expect(
      employeePageSource,
      contains("'employee-form-open-access-profile'"),
    );
    expect(
      userManagementServiceSource,
      contains("result['emailSent'] != true"),
    );
    expect(
      userManagementPageSource,
      contains('Invitación enviada por correo'),
    );
    expect(
      userManagementServiceSource,
      contains("result['accessEmailSent'] != true"),
    );
    expect(
      userManagementServiceSource,
      isNot(contains("result['passwordResetSent'] != true")),
    );
    expect(
      userManagementPageSource,
      contains('Correo de acceso seguro enviado'),
    );
    expect(
      userManagementServiceSource,
      isNot(contains('ArgumentError.value(password')),
    );
  });

  test('employee access delegates identity creation to the canonical admin edge',
      () {
    expect(
      userManagementServiceSource,
      contains("'action': 'create_internal_invitation'"),
    );
    expect(
      userManagementServiceSource,
      contains("'action': 'resend_internal_invitation'"),
    );
    expect(
      userManagementServiceSource,
      contains("'admin-user-management'"),
    );
    expect(
      employeePageSource,
      contains("'employee-form-open-access-profile'"),
    );
    expect(
      employeePageSource,
      isNot(contains("'action': 'create_internal_invitation'")),
    );
    expect(
      hrServiceSource,
      isNot(contains("'action': 'create_internal_invitation'")),
    );
    expect(hrServiceSource, isNot(contains(".from('user_invitations')")));
    expect(hrServiceSource, isNot(contains(".from('user_profiles')")));
    expect(hrServiceSource, isNot(contains("'send-invitation'")));
    expect(hrServiceSource, isNot(contains('linkEmployeeToUser(')));
    expect(hrServiceSource, isNot(contains('unlinkEmployeeFromUser(')));
  });

  test('auth redirects match registered routes and native schemes', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final androidManifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final iosInfo = File('ios/Runner/Info.plist').readAsStringSync();
    final macosInfo = File('macos/Runner/Info.plist').readAsStringSync();

    expect(mainSource, contains('usePathUrlStrategy();'));
    expect(
      mainSource,
      contains('AuthService.captureInitialUrl(_initialBrowserUrl)'),
    );
    expect(
      mainSource,
      contains(
        'CustomerAccountService.captureInitialUrl(_initialBrowserUrl)',
      ),
    );
    expect(routerSource, contains("path: '/auth/callback'"));
    expect(routerSource, contains("path: '/reset-password'"));
    expect(routerSource, contains('authService.isPasswordRecovery'));
    expect(publicStoreRouterSource, contains("path: '/auth/callback'"));
    expect(
      publicStoreRouterSource,
      contains("AuthCallbackPage(fallbackPath: '/cuenta')"),
    );
    expect(androidManifest, contains('android:scheme="vinabike"'));
    expect(androidManifest, contains('android:host="app"'));
    expect(iosInfo, contains('<string>vinabike</string>'));
    expect(macosInfo, contains('<string>vinabike</string>'));
    expect(authServiceSource, isNot(contains('/#/reset-password')));
    expect(
      authServiceSource,
      isNot(contains('io.supabase.vinabikeerp')),
    );
  });

  test('password reset requires the recovery auth event', () {
    expect(resetPasswordSource, contains('isPasswordRecovery'));
    expect(
        resetPasswordSource, contains('addListener(_handleAuthStateChanged)'));
    expect(resetPasswordSource, isNot(contains('auth.currentSession')));
    expect(resetPasswordSource, isNot(contains('currentSession;')));
    expect(authServiceSource, contains('isPasswordRecoveryUri(Uri uri)'));
    expect(authServiceSource, contains("uri.path != '/reset-password'"));
    expect(authServiceSource, contains('exchangeCodeForSession(code)'));
    expect(authServiceSource, contains('setSession(refreshToken)'));
    expect(
      authServiceSource,
      contains('_sessionMatchesInitialRecoveryEvidence(_session)'),
    );
    expect(
      authServiceSource,
      isNot(
        contains(
          '_preserveInitialRecoveryUntilConsumed && _session != null',
        ),
      ),
    );
    expect(
      customerAccountServiceSource,
      contains('_sessionMatchesInitialRecoveryEvidence(currentSession)'),
    );
    expect(
      customerAccountServiceSource,
      isNot(contains(
        '_isPasswordRecoverySession = _wasInitiallyRecoveryUrl',
      )),
    );
  });

  test('Google auth cannot create an ERP tenant and provisions store customers',
      () {
    expect(
      loginSource,
      contains("ValueKey('existing-account-google-login')"),
    );
    expect(loginSource, contains('if (!_isRegisterMode) ...['));
    expect(loginSource, contains('_handleAccessDeniedSession()'));
    expect(loginSource, contains('await authService.signOut()'));
    expect(
      loginSource,
      contains('!authService.isStaff &&'),
    );

    expect(customerAccountServiceSource,
        contains('AuthRedirectUrls.authCallback'));
    expect(
      customerAccountServiceSource,
      contains("'provision_current_public_store_customer'"),
    );
    expect(
      customerAccountServiceSource,
      contains("'p_tenant_id': tenantId"),
    );
    expect(
      customerAccountServiceSource,
      isNot(contains(".from('customers').insert")),
    );
    expect(
      customerAccountServiceSource,
      isNot(contains("'customer_tenant_id'")),
    );
    expect(
      customerAccountServiceSource,
      contains('Tenant authority comes from the current storefront URL'),
    );
    expect(
      customerAccountServiceSource,
      isNot(contains('io.supabase.vinabike://callback')),
    );
  });

  test('store confirmation and recovery redirects are explicitly allowlisted',
      () {
    final authConfig = File('supabase/config.toml').readAsStringSync();
    const storeOrigins = [
      'http://127.0.0.1:54330',
      'http://localhost:54330',
      'http://127.0.0.1:3000',
      'http://localhost:3000',
      'https://project-vinabike.web.app',
      'https://project-vinabike.firebaseapp.com',
      'https://vinabike.cl',
      'https://www.vinabike.cl',
      'https://vinabike-store.web.app',
      'https://vinabike-store.firebaseapp.com',
    ];

    expect(
      customerAccountServiceSource,
      contains('/cuenta/login?confirmed=true'),
    );
    expect(
      customerAccountServiceSource,
      contains('/cuenta/login?recovery=true'),
    );
    for (final origin in storeOrigins) {
      expect(
        authConfig,
        contains('"$origin/cuenta/login?confirmed=true"'),
        reason: 'Missing exact confirmation redirect for $origin',
      );
      expect(
        authConfig,
        contains('"$origin/cuenta/login?recovery=true"'),
        reason: 'Missing exact recovery redirect for $origin',
      );
      expect(
        authConfig,
        contains('"$origin/cuenta/login?invited=true"'),
        reason: 'Missing exact first-password invitation redirect for $origin',
      );
    }
  });

  test(
      'store invitation first-password flow waits for exact tenant and closes its session',
      () {
    expect(
      customerAuthPageSource,
      contains('isFirstPasswordInvitationVerificationPending'),
    );
    expect(
      customerAuthPageSource,
      contains('context.watch<PublicStoreTenantProvider>()'),
    );
    expect(
      customerAuthPageSource,
      contains('firstPasswordInvitationTenantState'),
    );
    expect(
      customerAuthPageSource,
      contains('await tenantProvider.detectTenant()'),
    );
    expect(
      customerAuthPageSource,
      contains("ValueKey('customer-invitation-tenant-loading')"),
    );
    expect(
      customerAuthPageSource,
      contains('completeInvitedFirstPassword'),
    );
    expect(
      customerAuthPageSource,
      contains('await accountService.signOut()'),
    );
    expect(
      customerAuthPageSource,
      contains(
        'Solicita a la tienda un nuevo correo de invitación.',
      ),
    );
    expect(
      customerAccountServiceSource,
      contains('isFirstPasswordInvitationUri(Uri uri)'),
    );
    expect(
      customerAccountServiceSource,
      contains('await _supabase.auth.verifyOTP('),
    );
    expect(
      customerAccountServiceSource,
      contains('type: OtpType.invite'),
    );
    expect(
      customerAccountServiceSource,
      isNot(contains(
        "uri.queryParameters['invited'] == 'true'",
      )),
    );

    final completionStart = customerAccountServiceSource.indexOf(
      'Future<void> completeInvitedFirstPassword',
    );
    final completionEnd = customerAccountServiceSource.indexOf(
      'void clearFirstPasswordInvitationIntent',
      completionStart,
    );
    expect(completionStart, greaterThanOrEqualTo(0));
    expect(completionEnd, greaterThan(completionStart));
    final completionSource = customerAccountServiceSource.substring(
      completionStart,
      completionEnd,
    );
    final membershipLoadIndex =
        completionSource.indexOf('await _loadCustomerData(');
    expect(membershipLoadIndex, greaterThanOrEqualTo(0));
    expect(
      membershipLoadIndex,
      lessThan(completionSource.indexOf('await updatePassword(newPassword)')),
    );
    expect(completionSource, contains("_customerProfile?['tenant_id']"));
    expect(completionSource, contains('invitationSession == null'));
    expect(
      completionSource,
      contains('_verifiedFirstPasswordInvitationUserId'),
    );
  });

  test('invitation tokens stay out of query strings and referrers', () {
    final redirectHtml = File('web/accept-invitation.html').readAsStringSync();

    expect(redirectHtml, contains('name="referrer" content="no-referrer"'));
    expect(redirectHtml, contains('window.location.hash.slice(1)'));
    expect(
      redirectHtml,
      contains(r'/accept-invitation#token=${encodeURIComponent(token)}'),
    );
    expect(redirectHtml, isNot(contains('/#/accept-invitation')));
    expect(redirectHtml, isNot(contains('window.location.search')));
    expect(routerSource, contains('invitationTokenFromUri(state.uri)'));
    expect(routerSource, contains('uri.fragment'));
    expect(routerSource, isNot(contains("uri.queryParameters['token']")));
  });

  test('startup and OAuth callback logs never print captured URLs or errors',
      () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final storeMainSource = File('lib/main_store.dart').readAsStringSync();
    final callbackSource =
        File('lib/shared/pages/auth_callback_page.dart').readAsStringSync();

    expect(
      RegExp(r'debugPrint\([^;]*_initialBrowserUrl', dotAll: true)
          .hasMatch(mainSource),
      isFalse,
    );
    expect(
      RegExp(r'debugPrint\([^;]*_initialBrowserUrl', dotAll: true)
          .hasMatch(storeMainSource),
      isFalse,
    );
    expect(callbackSource, isNot(contains(r'failed: $e')));
    expect(callbackSource, isNot(contains(r'flag=$flag')));
    expect(callbackSource, isNot(contains(r'back to: $returnPath')));
  });

  test('tenant, role and permission authority comes from one active DB profile',
      () {
    expect(tenantServiceSource, contains(".eq('is_active', true)"));
    expect(tenantServiceSource, contains('profiles.length != 1'));
    expect(tenantServiceSource, isNot(contains("appMetadata['tenant_id']")));
    expect(tenantServiceSource, isNot(contains("userMetadata?['tenant_id']")));
    expect(tenantServiceSource, isNot(contains("userMetadata?['role']")));
    expect(
      tenantServiceSource,
      isNot(contains("userMetadata?['permissions']")),
    );

    expect(authServiceSource, contains(".eq('is_active', true)"));
    expect(authServiceSource, contains('profiles.length == 1'));
    expect(
      authServiceSource,
      isNot(contains("user.userMetadata?['account_type'] == 'worker_portal'")),
    );

    expect(
      documentAccountingContextSource,
      contains(".eq('is_active', true)"),
    );
    expect(
      documentAccountingContextSource,
      contains('profiles.length != 1'),
    );
    expect(
      documentAccountingContextSource,
      isNot(contains("appMetadata['tenant_id']")),
    );
    expect(
      documentAccountingContextSource,
      isNot(contains("userMetadata?['tenant_id']")),
    );
  });

  test('public-store new passwords use the shared strong policy', () {
    final customerAuthSource =
        File('lib/public_store/pages/customer_auth_page.dart')
            .readAsStringSync();
    final checkoutSource =
        File('lib/public_store/pages/checkout_page.dart').readAsStringSync();
    final customerProfileSource =
        File('lib/public_store/pages/customer_profile_page.dart')
            .readAsStringSync();

    expect(
        customerAuthSource, contains('AuthInputValidation.validatePassword'));
    expect(customerAuthSource, contains('isNewPassword: !_isLogin'));
    expect(customerAuthSource, isNot(contains('Mínimo 6 caracteres')));
    expect(checkoutSource, contains('isNewPassword: true'));
    expect(checkoutSource, isNot(contains('Usa al menos 6 caracteres')));
    expect(customerProfileSource, contains('isNewPassword: true'));
    expect(customerAccountServiceSource, contains('_requireStrongNewPassword'));
  });

  test('password recovery UI is non-enumerating and never renders raw errors',
      () {
    final forgotSource = File('lib/shared/widgets/forgot_password_dialog.dart')
        .readAsStringSync();
    final customerAuthSource =
        File('lib/public_store/pages/customer_auth_page.dart')
            .readAsStringSync();

    expect(forgotSource, contains('Si existe una cuenta asociada'));
    expect(forgotSource, isNot(contains('No existe una cuenta')));
    expect(forgotSource, isNot(contains('e.toString()')));
    expect(forgotSource, isNot(contains(r'${e.message}')));
    expect(customerAuthSource, contains('Si existe una cuenta asociada'));
    expect(customerAuthSource, isNot(contains(r'$error')));
    expect(
      customerAuthSource,
      contains('accountService.completePasswordRecovery('),
    );
    expect(
      customerAccountServiceSource,
      contains("uri.path != '/cuenta/login'"),
    );
    expect(
      customerAccountServiceSource,
      contains('/cuenta/login?recovery=true'),
    );
    expect(loginSource, isNot(contains('e.toString()')));
    expect(loginSource, isNot(contains(r'${e.message}')));
    expect(resetPasswordSource, isNot(contains('e.toString()')));
    expect(resetPasswordSource, isNot(contains(r'${e.message}')));
  });

  test('store Auth links and customer membership fail closed', () {
    final customerAuthSource =
        File('lib/public_store/pages/customer_auth_page.dart')
            .readAsStringSync();
    final portalLayoutSource =
        File('lib/public_store/widgets/customer_portal_layout.dart')
            .readAsStringSync();
    final webUrlSource =
        File('lib/shared/utils/web_url_web.dart').readAsStringSync();

    expect(customerAccountServiceSource, contains('type: OtpType.recovery'));
    expect(
      customerAccountServiceSource,
      contains('Future<void> completePasswordRecovery'),
    );
    expect(
      customerAccountServiceSource,
      contains('!_isPasswordRecoverySession'),
    );
    expect(
      customerAccountServiceSource,
      contains('_verifiedPasswordRecoveryUserId'),
    );
    expect(
      customerAccountServiceSource,
      isNot(contains('session.user.recoverySentAt')),
    );
    expect(
      customerAccountServiceSource,
      contains('clearSensitiveAuthFragment()'),
    );
    expect(
      webUrlSource,
      contains('web.window.history.replaceState'),
    );
    expect(
      customerAccountServiceSource,
      contains('bool get hasAuthSession => _currentUser != null'),
    );
    expect(
      customerAccountServiceSource,
      contains("_customerProfile?['tenant_id']?.toString() == _tenantId"),
    );
    expect(
      customerAccountServiceSource,
      contains(
        "_customerProfile?['auth_user_id']?.toString() == _currentUser!.id",
      ),
    );
    expect(
      customerAccountServiceSource,
      contains('_isCustomerMembershipLoading'),
    );
    expect(
      portalLayoutSource,
      contains('_CustomerPortalAuthBoundary'),
    );
    expect(
      customerAuthSource,
      isNot(contains('_didHandleAccountConfirmation')),
    );
    expect(
      customerAuthSource,
      contains('`confirmed=true` is display-only'),
    );
  });

  test('self-service password changes revoke other refresh sessions only', () {
    expect(
      RegExp(r'signOut\(scope: SignOutScope\.others\)')
          .allMatches(authServiceSource)
          .length,
      2,
    );
    expect(
      RegExp(r'signOut\(scope: SignOutScope\.others\)')
          .allMatches(selfPasswordServiceSource)
          .length,
      1,
    );
    expect(
      customerAccountServiceSource,
      contains('SelfPasswordService(_supabase)'),
    );
    expect(authServiceSource, contains('await _client.auth.signOut();'));
    expect(
      authServiceSource,
      isNot(contains('SignOutScope.global')),
    );

    final authConfig = File('supabase/config.toml').readAsStringSync();
    expect(authConfig, contains('jwt_expiry = 3600'));
  });
}
