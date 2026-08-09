import 'package:flutter/foundation.dart';

import '../../modules/purchases/services/supplier_credential_service.dart';
import '../models/current_user_profile.dart';

typedef BrowserSupplierCredentialRevealer
    = Future<SupplierCredentialOriginResolution?> Function(
  String canonicalOrigin,
);
typedef BrowserSupplierCredentialFinder = Future<SupplierCredentialOriginLookup>
    Function(
  String canonicalOrigin,
);

enum BrowserSupplierCredentialLookupStatus {
  matched,
  noMatch,
  unavailable,
}

@immutable
class BrowserSupplierCredentialLookupResult {
  const BrowserSupplierCredentialLookupResult._({
    required this.status,
    this.credential,
  });

  const BrowserSupplierCredentialLookupResult.matched(
    BrowserSupplierCredential credential,
  ) : this._(
          status: BrowserSupplierCredentialLookupStatus.matched,
          credential: credential,
        );

  const BrowserSupplierCredentialLookupResult.noMatch()
      : this._(status: BrowserSupplierCredentialLookupStatus.noMatch);

  const BrowserSupplierCredentialLookupResult.unavailable()
      : this._(status: BrowserSupplierCredentialLookupStatus.unavailable);

  final BrowserSupplierCredentialLookupStatus status;
  final BrowserSupplierCredential? credential;

  bool get isMatched =>
      status == BrowserSupplierCredentialLookupStatus.matched &&
      credential != null;
}

/// One exact supplier credential selected by the server-owned origin index.
///
/// This object is intentionally non-serializable and redacts its secret from
/// diagnostics. Consumers must discard it immediately after one guarded fill.
@immutable
class BrowserSupplierCredential {
  const BrowserSupplierCredential({
    required this.tenantId,
    required this.supplierId,
    required this.credentialKey,
    required this.origin,
    required this.username,
    required this.password,
    required this.updatedAt,
    this.engagementId,
    this.label,
  });

  final String tenantId;
  final String supplierId;
  final String credentialKey;
  final String? engagementId;
  final String origin;
  final String? label;
  final String username;
  final String password;
  final DateTime updatedAt;

  @override
  String toString() =>
      'BrowserSupplierCredential(supplierId: $supplierId, key: '
      '$credentialKey, origin: $origin, redacted: true)';
}

/// Captures the browser's exact Auth + profile + tenant authority generation.
///
/// The profile object identity is part of the lease. Returning to the same
/// user and tenant after a logout/scope transition (ABA) therefore does not
/// revive an in-flight credential operation.
@immutable
class BrowserCredentialAuthorityLease {
  const BrowserCredentialAuthorityLease._({
    required CurrentUserProfile profile,
    required this.userId,
    required this.tenantId,
    required this.canManageSupplierCredentials,
  }) : _profile = profile;

  static BrowserCredentialAuthorityLease? capture({
    required CurrentUserProfile? profile,
    required String? authUserId,
    required String browserProfileIdentity,
  }) {
    if (profile == null ||
        authUserId != profile.userId ||
        browserProfileIdentity != profile.userId) {
      return null;
    }
    return BrowserCredentialAuthorityLease._(
      profile: profile,
      userId: profile.userId,
      tenantId: profile.tenantId,
      canManageSupplierCredentials: profile.canManageSupplierCredentials,
    );
  }

  final CurrentUserProfile _profile;
  final String userId;
  final String tenantId;
  final bool canManageSupplierCredentials;

  bool isCurrent({
    required CurrentUserProfile? profile,
    required String? authUserId,
    required String browserProfileIdentity,
    required bool requireSupplierCredentialPermission,
  }) {
    return authUserId == userId &&
        browserProfileIdentity == userId &&
        identical(profile, _profile) &&
        profile?.userId == userId &&
        profile?.tenantId == tenantId &&
        (!requireSupplierCredentialPermission ||
            canManageSupplierCredentials &&
                profile?.canManageSupplierCredentials == true);
  }
}

/// Resolves a unique exact-origin reference without revealing a username or
/// secret. This is the correct boundary for informational actions such as
/// explaining where a site's managed credential comes from.
Future<SupplierCredentialOriginLookup?>
    resolveSupplierCredentialReferenceForOrigin({
  required String origin,
  required BrowserSupplierCredentialFinder findCredential,
}) async {
  final normalizedOrigin = normalizeSupplierBrowserOrigin(origin);
  if (normalizedOrigin == null) return null;
  final lookup = await findCredential(normalizedOrigin);
  return _isExactPortalLookup(lookup, normalizedOrigin) ? lookup : null;
}

/// Resolves one portal credential through the protected exact-origin RPC.
///
/// No supplier list, website field, host alias, or default credential key is
/// consulted here. The service owns ambiguity handling and reveals a secret
/// only after the origin has exactly one `(supplier, kind, key)` binding.
Future<BrowserSupplierCredential?> resolveSupplierCredentialForOrigin({
  required String origin,
  required BrowserSupplierCredentialRevealer revealCredential,
}) async {
  final normalizedOrigin = normalizeSupplierBrowserOrigin(origin);
  if (normalizedOrigin == null) return null;

  final resolution = await revealCredential(normalizedOrigin);
  if (resolution == null) return null;

  final lookup = resolution.lookup;
  final selected = lookup.match;
  final metadata = resolution.credential.metadata;
  if (!_isExactPortalLookup(lookup, normalizedOrigin) ||
      selected == null ||
      metadata.tenantId != lookup.tenantId ||
      metadata.supplierId != selected.supplierId ||
      metadata.kind != selected.kind ||
      metadata.credentialKey != selected.credentialKey ||
      metadata.engagementId != selected.engagementId ||
      metadata.originUrl != selected.originUrl) {
    return null;
  }

  final username = resolution.credential.username?.trim() ?? '';
  if (username.isEmpty || resolution.credential.secret.isEmpty) return null;

  return BrowserSupplierCredential(
    tenantId: metadata.tenantId,
    supplierId: metadata.supplierId,
    credentialKey: metadata.credentialKey,
    engagementId: metadata.engagementId,
    origin: normalizedOrigin,
    label: metadata.label ?? selected.label,
    username: username,
    password: resolution.credential.secret,
    updatedAt: metadata.updatedAt?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
}

/// Resolves the browser submission boundary without collapsing a protected
/// lookup failure into an affirmative "no managed credential" answer.
///
/// A caller may persist credentials in its local vault only for [noMatch]. An
/// ambiguous origin, malformed response, permission transition, or reveal
/// failure is [unavailable] and must fail closed.
Future<BrowserSupplierCredentialLookupResult>
    resolveBrowserSupplierCredentialLookup({
  required String origin,
  required BrowserSupplierCredentialFinder findCredential,
  required BrowserSupplierCredentialRevealer revealCredential,
}) async {
  final normalizedOrigin = normalizeSupplierBrowserOrigin(origin);
  if (normalizedOrigin == null) {
    return const BrowserSupplierCredentialLookupResult.unavailable();
  }

  try {
    final lookup = await findCredential(normalizedOrigin);
    if (_isExactPortalNoMatch(lookup, normalizedOrigin)) {
      return const BrowserSupplierCredentialLookupResult.noMatch();
    }
    if (!_isExactPortalLookup(lookup, normalizedOrigin)) {
      return const BrowserSupplierCredentialLookupResult.unavailable();
    }

    final credential = await resolveSupplierCredentialForOrigin(
      origin: normalizedOrigin,
      revealCredential: revealCredential,
    );
    final selected = lookup.match;
    if (credential == null ||
        selected == null ||
        !_sameBrowserCredentialBindingToReveal(selected, credential)) {
      return const BrowserSupplierCredentialLookupResult.unavailable();
    }
    return BrowserSupplierCredentialLookupResult.matched(credential);
  } catch (_) {
    return const BrowserSupplierCredentialLookupResult.unavailable();
  }
}

/// Extracts and canonicalizes the exact HTTPS origin of a browser URL.
///
/// `www`, sibling subdomains, and non-default ports remain distinct. Port 443
/// is normalized away by the shared server-contract canonicalizer.
String? normalizeSupplierBrowserOrigin(String? value) {
  final uri = Uri.tryParse(value?.trim() ?? '');
  if (uri == null || uri.host.isEmpty || uri.scheme.toLowerCase() != 'https') {
    return null;
  }
  return canonicalSupplierCredentialOrigin(uri.origin);
}

bool _isExactPortalLookup(
  SupplierCredentialOriginLookup lookup,
  String normalizedOrigin,
) {
  final selected = lookup.match;
  final candidate =
      lookup.candidates.length == 1 ? lookup.candidates.single : null;
  return lookup.isUnique &&
      lookup.status == SupplierCredentialOriginMatchStatus.unique &&
      lookup.matchCount == 1 &&
      candidate != null &&
      lookup.requestedKind == SupplierCredentialKind.portalPassword &&
      lookup.canonicalOrigin == normalizedOrigin &&
      selected != null &&
      _sameBrowserCredentialBinding(selected, candidate) &&
      selected.tenantId == lookup.tenantId &&
      selected.kind == SupplierCredentialKind.portalPassword &&
      selected.originUrl == normalizedOrigin;
}

bool _isExactPortalNoMatch(
  SupplierCredentialOriginLookup lookup,
  String normalizedOrigin,
) {
  return lookup.status == SupplierCredentialOriginMatchStatus.noMatch &&
      lookup.matchCount == 0 &&
      lookup.match == null &&
      lookup.candidates.isEmpty &&
      lookup.requestedKind == SupplierCredentialKind.portalPassword &&
      lookup.canonicalOrigin == normalizedOrigin;
}

bool _sameBrowserCredentialBindingToReveal(
  SupplierCredentialMetadata metadata,
  BrowserSupplierCredential credential,
) {
  final metadataVersion = metadata.updatedAt?.toUtc();
  return metadata.tenantId == credential.tenantId &&
      metadata.supplierId == credential.supplierId &&
      metadata.kind == SupplierCredentialKind.portalPassword &&
      metadata.credentialKey == credential.credentialKey &&
      metadata.engagementId == credential.engagementId &&
      metadata.originUrl == credential.origin &&
      metadataVersion != null &&
      metadataVersion.isAtSameMomentAs(credential.updatedAt.toUtc());
}

bool _sameBrowserCredentialBinding(
  SupplierCredentialMetadata left,
  SupplierCredentialMetadata right,
) {
  return left.tenantId == right.tenantId &&
      left.supplierId == right.supplierId &&
      left.kind == right.kind &&
      left.credentialKey == right.credentialKey &&
      left.engagementId == right.engagementId &&
      left.originUrl == right.originUrl;
}
