import 'package:vinabike_erp/shared/services/auth_redirect_urls.dart';
import 'package:vinabike_erp/shared/services/auth_service.dart';
import 'package:vinabike_erp/public_store/services/customer_account_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web auth callbacks use clean registered application paths', () {
    final base = Uri.parse('https://erp.example.cl/login?from=test');

    expect(
      AuthRedirectUrls.authCallback(isWeb: true, webBase: base),
      'https://erp.example.cl/auth/callback',
    );
    expect(
      AuthRedirectUrls.passwordReset(isWeb: true, webBase: base),
      'https://erp.example.cl/reset-password',
    );
  });

  test('registered Apple and Android clients use the vinabike app scheme', () {
    for (final platform in const [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    ]) {
      expect(
        AuthRedirectUrls.authCallback(
          isWeb: false,
          platform: platform,
        ),
        'vinabike://app/auth/callback',
      );
      expect(
        AuthRedirectUrls.passwordReset(
          isWeb: false,
          platform: platform,
        ),
        'vinabike://app/reset-password',
      );
    }
  });

  test('does not invent an unregistered callback for desktop platforms', () {
    expect(
      AuthRedirectUrls.authCallback(
        isWeb: false,
        platform: TargetPlatform.windows,
      ),
      isNull,
    );
    expect(
      AuthRedirectUrls.passwordReset(
        isWeb: false,
        platform: TargetPlatform.linux,
      ),
      isNull,
    );
  });

  test('recovery intent requires the reset route and recovery evidence', () {
    expect(
      AuthService.isPasswordRecoveryUri(
        Uri.parse('https://erp.example.cl/reset-password?type=recovery'),
      ),
      isFalse,
    );
    expect(
      AuthService.isPasswordRecoveryUri(
        Uri.parse('https://erp.example.cl/reset-password?code=pkce-code'),
      ),
      isTrue,
    );
    expect(
      AuthService.isPasswordRecoveryUri(
        Uri.parse(
          'https://erp.example.cl/reset-password#access_token=token&type=recovery',
        ),
      ),
      isTrue,
    );
    expect(
      AuthService.isPasswordRecoveryUri(
        Uri.parse('https://erp.example.cl/reset-password'),
      ),
      isFalse,
    );
    expect(
      AuthService.isPasswordRecoveryUri(
        Uri.parse(
          'https://erp.example.cl/login#access_token=normal-session-token',
        ),
      ),
      isFalse,
    );
  });

  test('store recovery requires its real route, type and token evidence', () {
    expect(
      CustomerAccountService.isPasswordRecoveryUri(
        Uri.parse(
          'https://store.example.cl/cuenta/login?type=recovery&code=pkce-code',
        ),
      ),
      isTrue,
    );
    expect(
      CustomerAccountService.isPasswordRecoveryUri(
        Uri.parse(
          'https://store.example.cl/cuenta/login#type=recovery&access_token=token',
        ),
      ),
      isTrue,
    );
    expect(
      CustomerAccountService.isPasswordRecoveryUri(
        Uri.parse(
          'https://store.example.cl/cuenta/login?recovery=true'
          '#token_hash=0123456789abcdef0123456789abcdef&type=recovery',
        ),
      ),
      isTrue,
    );
    expect(
      CustomerAccountService.isPasswordRecoveryUri(
        Uri.parse('https://store.example.cl/cuenta/login?type=recovery'),
      ),
      isFalse,
    );
    expect(
      CustomerAccountService.isPasswordRecoveryUri(
        Uri.parse('https://store.example.cl/cuenta/login?recovery=true'),
      ),
      isFalse,
    );
    expect(
      CustomerAccountService.isPasswordRecoveryUri(
        Uri.parse(
          'https://store.example.cl/?type=recovery&code=pkce-code',
        ),
      ),
      isFalse,
    );
    expect(
      () => CustomerAccountService.captureInitialUrl(
        'https://store.example.cl/cuenta/login#type=%',
      ),
      returnsNormally,
    );
  });

  test('store first-password invitation requires a server-issued invite token',
      () {
    expect(
      CustomerAccountService.isFirstPasswordInvitationUri(
        Uri.parse(
          'https://store.example.cl/cuenta/login'
          '#token_hash=0123456789abcdef0123456789abcdef&type=invite',
        ),
      ),
      isTrue,
    );
    expect(
      CustomerAccountService.isFirstPasswordInvitationUri(
        Uri.parse(
          'https://store.example.cl/cuenta/login?invited=true',
        ),
      ),
      isFalse,
    );
    expect(
      CustomerAccountService.isFirstPasswordInvitationUri(
        Uri.parse(
          'https://store.example.cl/cuenta/login?invited=true&code=invite-code',
        ),
      ),
      isFalse,
    );
    expect(
      CustomerAccountService.isFirstPasswordInvitationUri(
        Uri.parse(
          'https://store.example.cl/cuenta/login'
          '#token_hash=0123456789abcdef0123456789abcdef&type=recovery',
        ),
      ),
      isFalse,
    );
    expect(
      CustomerAccountService.isFirstPasswordInvitationUri(
        Uri.parse(
          'https://store.example.cl/tienda/cuenta/login'
          '#token_hash=0123456789abcdef0123456789abcdef&type=invite',
        ),
      ),
      isFalse,
    );
  });

  test('invitation tenant waits for detection and fails only on final error',
      () {
    expect(
      CustomerAccountService.firstPasswordInvitationTenantState(
        tenantId: null,
        isLoading: false,
        hasError: false,
      ),
      FirstPasswordInvitationTenantState.waiting,
    );
    expect(
      CustomerAccountService.firstPasswordInvitationTenantState(
        tenantId: null,
        isLoading: true,
        hasError: false,
      ),
      FirstPasswordInvitationTenantState.waiting,
    );
    expect(
      CustomerAccountService.firstPasswordInvitationTenantState(
        tenantId: null,
        isLoading: false,
        hasError: true,
      ),
      FirstPasswordInvitationTenantState.unavailable,
    );
    expect(
      CustomerAccountService.firstPasswordInvitationTenantState(
        tenantId: ' tenant-id ',
        isLoading: false,
        hasError: false,
      ),
      FirstPasswordInvitationTenantState.ready,
    );
  });
}
