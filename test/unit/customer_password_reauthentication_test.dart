import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;
import 'package:vinabike_erp/public_store/services/customer_account_service.dart';

void main() {
  group('customer password update error classification', () {
    test('recognizes a required reauthentication by stable Auth code', () {
      expect(
        CustomerAccountService.classifyPasswordUpdateError(
          const AuthException(
            'Sensitive operation needs verification',
            code: 'reauthentication_needed',
          ),
        ),
        CustomerPasswordUpdateIssue.reauthenticationRequired,
      );
    });

    test('distinguishes invalid, missing, and expired verification codes', () {
      expect(
        CustomerAccountService.classifyPasswordUpdateError(
          const AuthException(
            'Invalid verification code',
            code: 'reauthentication_not_valid',
          ),
        ),
        CustomerPasswordUpdateIssue.invalidVerificationCode,
      );
      expect(
        CustomerAccountService.classifyPasswordUpdateError(
          const AuthException(
            'Missing verification code',
            code: 'reauth_nonce_missing',
          ),
        ),
        CustomerPasswordUpdateIssue.invalidVerificationCode,
      );
      expect(
        CustomerAccountService.classifyPasswordUpdateError(
          const AuthException(
            'Expired verification code',
            code: 'otp_expired',
          ),
        ),
        CustomerPasswordUpdateIssue.expiredVerificationCode,
      );
    });

    test('recognizes same-password and keeps unknown errors generic', () {
      expect(
        CustomerAccountService.classifyPasswordUpdateError(
          const AuthException(
            'Password did not change',
            code: 'same_password',
          ),
        ),
        CustomerPasswordUpdateIssue.samePassword,
      );
      expect(
        CustomerAccountService.classifyPasswordUpdateError(
          StateError('network unavailable'),
        ),
        CustomerPasswordUpdateIssue.unknown,
      );
    });

    test('retains compatibility when an older response omits Auth code', () {
      expect(
        CustomerAccountService.classifyPasswordUpdateError(
          const AuthException('reauthentication_needed'),
        ),
        CustomerPasswordUpdateIssue.reauthenticationRequired,
      );
    });
  });

  test('profile password flow uses Supabase nonce reauthentication API', () {
    final serviceSource = File(
      'lib/public_store/services/customer_account_service.dart',
    ).readAsStringSync();
    final passwordSource = File(
      'lib/shared/services/self_password_service.dart',
    ).readAsStringSync();
    final profileSource = File(
      'lib/public_store/pages/customer_profile_page.dart',
    ).readAsStringSync();

    expect(serviceSource, contains('SelfPasswordService(_supabase)'));
    expect(passwordSource, contains('nonce:'));
    expect(passwordSource, contains('SignOutScope.others'));
    expect(profileSource, contains('requestPasswordReauthentication()'));
    expect(profileSource, contains('reauthenticationNonce:'));
    expect(profileSource, contains('Reenviar código'));
    expect(profileSource, contains('AutofillHints.oneTimeCode'));
    expect(profileSource, contains('FilteringTextInputFormatter.digitsOnly'));
    expect(
      profileSource,
      contains("RegExp(r'^\\d{6}\$')"),
    );
    expect(profileSource, isNot(contains('error.message')));
  });

  test('storefront reports and retries a partial password outcome honestly',
      () {
    final serviceSource = File(
      'lib/public_store/services/customer_account_service.dart',
    ).readAsStringSync();
    final passwordSource = File(
      'lib/shared/services/self_password_service.dart',
    ).readAsStringSync();
    final profileSource = File(
      'lib/public_store/pages/customer_profile_page.dart',
    ).readAsStringSync();

    expect(
      passwordSource,
      contains('SelfPasswordUpdateResult.passwordUpdatedWithRevocationPending'),
    );
    expect(
      passwordSource,
      contains('retryOtherSessionRevocation()'),
    );
    expect(
      serviceSource,
      contains('hasPendingOtherSessionsRevocation'),
    );
    expect(
      serviceSource,
      contains('Future<SelfPasswordUpdateResult> updatePassword('),
    );
    expect(
      profileSource,
      contains('result.otherSessionsRevoked'),
    );
    expect(
      profileSource,
      contains('.retryOtherSessionRevocation()'),
    );
    expect(
      profileSource,
      contains('Tu contraseña ya quedó actualizada.'),
    );
    expect(
      profileSource,
      contains('no necesitas volver a ingresar ni cambiar tu contraseña'),
    );
  });
}
