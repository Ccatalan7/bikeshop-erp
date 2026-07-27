import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/shared/services/self_password_service.dart';

void main() {
  const strongPassword = 'CambioSeguro-2026!';

  test('delegates the sensitive-action reauthentication request', () async {
    var requests = 0;
    final service = SelfPasswordService.withCommands(
      requestReauthentication: () async {
        requests++;
      },
      updatePassword: (newPassword, nonce) async => true,
      revokeOtherSessions: () async {},
    );

    await service.requestReauthentication();

    expect(requests, 1);
  });

  test('returns a complete outcome after password and session updates',
      () async {
    var passwordUpdates = 0;
    var revocations = 0;
    String? receivedNonce;
    final service = SelfPasswordService.withCommands(
      updatePassword: (newPassword, nonce) async {
        passwordUpdates++;
        receivedNonce = nonce;
        return true;
      },
      revokeOtherSessions: () async {
        revocations++;
      },
    );

    final result = await service.updatePassword(
      strongPassword,
      reauthenticationNonce: ' 123456 ',
    );

    expect(result.passwordUpdated, isTrue);
    expect(result.otherSessionsRevoked, isTrue);
    expect(result.needsOtherSessionsRevocationRetry, isFalse);
    expect(receivedNonce, '123456');
    expect(passwordUpdates, 1);
    expect(revocations, 1);
  });

  test(
    'keeps the successful password outcome and retries only revocation',
    () async {
      var passwordUpdates = 0;
      var revocations = 0;
      final service = SelfPasswordService.withCommands(
        updatePassword: (newPassword, nonce) async {
          passwordUpdates++;
          return true;
        },
        revokeOtherSessions: () async {
          revocations++;
          if (revocations == 1) {
            throw StateError('simulated network failure');
          }
        },
      );

      final result = await service.updatePassword(strongPassword);

      expect(result.passwordUpdated, isTrue);
      expect(result.otherSessionsRevoked, isFalse);
      expect(result.needsOtherSessionsRevocationRetry, isTrue);
      expect(passwordUpdates, 1);
      expect(revocations, 1);

      final retry = await service.retryOtherSessionRevocation();

      expect(retry, SelfPasswordOtherSessionsRevocationOutcome.revoked);
      expect(passwordUpdates, 1);
      expect(revocations, 2);
    },
  );

  test('does not attempt session revocation when password update fails',
      () async {
    var revocations = 0;
    final service = SelfPasswordService.withCommands(
      updatePassword: (newPassword, nonce) async => false,
      revokeOtherSessions: () async {
        revocations++;
      },
    );

    await expectLater(
      service.updatePassword(strongPassword),
      throwsA(isA<AuthException>()),
    );

    expect(revocations, 0);
  });

  test('validates the password before either Auth command', () async {
    var passwordUpdates = 0;
    var revocations = 0;
    final service = SelfPasswordService.withCommands(
      updatePassword: (newPassword, nonce) async {
        passwordUpdates++;
        return true;
      },
      revokeOtherSessions: () async {
        revocations++;
      },
    );

    await expectLater(
      service.updatePassword('weak'),
      throwsA(isA<AuthException>()),
    );

    expect(passwordUpdates, 0);
    expect(revocations, 0);
  });
}
