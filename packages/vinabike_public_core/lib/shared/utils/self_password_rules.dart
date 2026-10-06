// The self-service password change's rules without a Supabase client
// (2026-10-06): the apps' `SelfPasswordService` and the HTML store's portal,
// which calls Supabase Auth from its server, read an Auth refusal the same
// way.

/// Why Supabase Auth refused a password change.
enum SelfPasswordUpdateIssue {
  reauthenticationRequired,
  invalidVerificationCode,
  expiredVerificationCode,
  samePassword,
  unknown,
}

/// The issue in an Auth error: its `code` (`error_code` in the answer), or
/// a word of its message when an older Auth answers without one.
SelfPasswordUpdateIssue selfPasswordIssueOf({
  String? code,
  String message = '',
}) {
  final normalizedCode = code?.trim().toLowerCase();
  final normalizedMessage = message.toLowerCase();

  bool matches(String value) =>
      normalizedCode == value || normalizedMessage.contains(value);

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

/// Whether Auth refused a code request because it was asked too often.
bool selfPasswordRateLimited(String? code) {
  final normalized = code?.toLowerCase();
  return normalized == 'over_email_send_rate_limit' ||
      normalized == 'over_request_rate_limit';
}
