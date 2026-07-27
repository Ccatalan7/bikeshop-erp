import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/auth_input_validation.dart';

enum SelfPasswordOtherSessionsRevocationOutcome {
  revoked,
  failed,
}

@immutable
class SelfPasswordUpdateResult {
  const SelfPasswordUpdateResult.complete()
      : passwordUpdated = true,
        otherSessionsRevocation =
            SelfPasswordOtherSessionsRevocationOutcome.revoked;

  const SelfPasswordUpdateResult.passwordUpdatedWithRevocationPending()
      : passwordUpdated = true,
        otherSessionsRevocation =
            SelfPasswordOtherSessionsRevocationOutcome.failed;

  final bool passwordUpdated;
  final SelfPasswordOtherSessionsRevocationOutcome otherSessionsRevocation;

  bool get otherSessionsRevoked =>
      otherSessionsRevocation ==
      SelfPasswordOtherSessionsRevocationOutcome.revoked;

  bool get needsOtherSessionsRevocationRetry =>
      passwordUpdated && !otherSessionsRevoked;
}

enum SelfPasswordUpdateIssue {
  reauthenticationRequired,
  invalidVerificationCode,
  expiredVerificationCode,
  samePassword,
  unknown,
}

typedef SelfPasswordIdentityUpdateCommand = Future<bool> Function(
  String newPassword,
  String? reauthenticationNonce,
);

typedef SelfPasswordVoidCommand = Future<void> Function();

/// Canonical self-service password command for an authenticated Auth identity.
///
/// Presentation remains host-specific, but ERP and storefront callers share
/// the same validation, reauthentication nonce, and other-session revocation
/// contract.
class SelfPasswordService {
  SelfPasswordService([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client,
        _requestReauthenticationCommand = null,
        _updatePasswordCommand = null,
        _revokeOtherSessionsCommand = null;

  @visibleForTesting
  SelfPasswordService.withCommands({
    SelfPasswordVoidCommand? requestReauthentication,
    required SelfPasswordIdentityUpdateCommand updatePassword,
    required SelfPasswordVoidCommand revokeOtherSessions,
  })  : _client = null,
        _requestReauthenticationCommand =
            requestReauthentication ?? (() async {}),
        _updatePasswordCommand = updatePassword,
        _revokeOtherSessionsCommand = revokeOtherSessions;

  final SupabaseClient? _client;
  final SelfPasswordVoidCommand? _requestReauthenticationCommand;
  final SelfPasswordIdentityUpdateCommand? _updatePasswordCommand;
  final SelfPasswordVoidCommand? _revokeOtherSessionsCommand;

  Future<void> requestReauthentication() {
    final command = _requestReauthenticationCommand;
    return command != null ? command() : _client!.auth.reauthenticate();
  }

  Future<SelfPasswordUpdateResult> updatePassword(
    String newPassword, {
    String? reauthenticationNonce,
  }) async {
    final validationError = AuthInputValidation.validatePassword(
      newPassword,
      isNewPassword: true,
    );
    if (validationError != null) {
      throw AuthException(validationError);
    }

    final normalizedNonce = reauthenticationNonce?.trim();
    final nonce = normalizedNonce?.isNotEmpty == true ? normalizedNonce : null;
    final command = _updatePasswordCommand;
    final passwordUpdated = command != null
        ? await command(newPassword, nonce)
        : (await _client!.auth.updateUser(
              UserAttributes(
                password: newPassword,
                nonce: nonce,
              ),
            ))
                .user !=
            null;
    if (!passwordUpdated) {
      throw const AuthException('No pudimos actualizar la contraseña.');
    }

    final revocation = await retryOtherSessionRevocation();
    return revocation == SelfPasswordOtherSessionsRevocationOutcome.revoked
        ? const SelfPasswordUpdateResult.complete()
        : const SelfPasswordUpdateResult.passwordUpdatedWithRevocationPending();
  }

  /// Retries only the post-password-change session cleanup.
  ///
  /// A failed cleanup never repeats the password mutation, because the new
  /// password may already be active even when session revocation failed.
  Future<SelfPasswordOtherSessionsRevocationOutcome>
      retryOtherSessionRevocation() async {
    try {
      final command = _revokeOtherSessionsCommand;
      if (command != null) {
        await command();
      } else {
        await _client!.auth.signOut(scope: SignOutScope.others);
      }
      return SelfPasswordOtherSessionsRevocationOutcome.revoked;
    } catch (_) {
      debugPrint('⚠️ [Auth] Other-session revocation failed');
      return SelfPasswordOtherSessionsRevocationOutcome.failed;
    }
  }

  static SelfPasswordUpdateIssue classifyUpdateError(Object error) {
    if (error is! AuthException) {
      return SelfPasswordUpdateIssue.unknown;
    }

    final code = error.code?.trim().toLowerCase();
    final message = error.message.toLowerCase();

    bool matches(String value) => code == value || message.contains(value);

    if (matches('reauthentication_needed')) {
      return SelfPasswordUpdateIssue.reauthenticationRequired;
    }
    if (matches('reauthentication_not_valid') ||
        matches('reauth_nonce_missing')) {
      return SelfPasswordUpdateIssue.invalidVerificationCode;
    }
    if (matches('otp_expired')) {
      return SelfPasswordUpdateIssue.expiredVerificationCode;
    }
    if (matches('same_password')) {
      return SelfPasswordUpdateIssue.samePassword;
    }
    return SelfPasswordUpdateIssue.unknown;
  }
}
