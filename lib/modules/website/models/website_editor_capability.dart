/// Resolved editor-entry capability for one exact identity.
///
/// The [fingerprint] binds the decision to the auth user, the active tenant,
/// the storefront tenant and the effective authority
/// (`admin`/`edit_settings`) as seen by the TenantService identity caches.
/// Logout, a user switch or a tenant switch changes the fingerprint through
/// the auth-event lifecycle and revokes the consumer lease immediately.
///
/// KNOWN LIMIT: a REMOTE role/permission change (another admin editing
/// user_profiles) is not observed by the local identity caches until the
/// TenantService auth lifecycle refreshes them. Enforcement for that window
/// is the server boundary: RLS blocks new reads/writes, and an editor load
/// the server rejects for AUTHORITY reasons surfaces as
/// [WebsiteEditorAuthorityException], which the CMS consumers convert into
/// lease revocation plus a public reload. Transient failures (network,
/// timeouts, 5xx) are never classified as authority loss and never discard
/// drafts. Event-driven cache invalidation belongs to the TenantService
/// owner as a follow-up.
/// The single producer is
/// `WebsiteService.editorCapabilitySync/resolveEditorCapability`.
class WebsiteEditorCapabilitySnapshot {
  const WebsiteEditorCapabilitySnapshot({
    required this.identity,
    required this.activeTenantId,
    required this.storefrontTenantId,
    required this.hasAuthority,
    this.authorityEpoch = 0,
  });

  /// Monotonic auth-identity epoch at snapshot time (see
  /// WebsiteService.identityEpoch). Two snapshots with the SAME fingerprint
  /// but different epochs are DIFFERENT authorities: an A→B→A sequence can
  /// reproduce A's fingerprint, never A's epoch, so adoption/save
  /// boundaries compare BOTH.
  final int authorityEpoch;

  /// Auth user id, or `'anon'` when signed out. Typed so consumers compare
  /// FIELDS — never parse a string protocol out of [fingerprint].
  final String identity;
  final String activeTenantId;
  final String storefrontTenantId;
  final bool hasAuthority;

  /// DERIVED, never stored: a snapshot cannot claim a grant its own typed
  /// fields contradict (impossible states are unrepresentable).
  bool get granted =>
      storefrontTenantId.isNotEmpty &&
      activeTenantId == storefrontTenantId &&
      hasAuthority;

  /// Derived identity-binding key (stable legacy format). Use it as an
  /// opaque equality token only; the typed fields above are the contract.
  String get fingerprint =>
      '$identity|$activeTenantId|$storefrontTenantId|$hasAuthority';
}

/// Transient failure to RESOLVE the capability (the identity/profile lookup
/// failed): callers must suspend the lease — retaining drafts hidden — and
/// retry later. Never a denial: fabricating "denied" from a network error
/// would consume the entry command and discard recoverable sessions.
class WebsiteEditorCapabilityUnresolvedException implements Exception {
  const WebsiteEditorCapabilityUnresolvedException(this.message);

  final String message;

  @override
  String toString() => 'WebsiteEditorCapabilityUnresolvedException: $message';
}

/// A SAVE completed (or failed) for an identity/epoch that is no longer
/// current. Typed outcome only: no denial latch, no revocation, no CMS
/// signal, and the NEW session is never touched.
class WebsiteEditorWriteSupersededException implements Exception {
  const WebsiteEditorWriteSupersededException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'WebsiteEditorWriteSupersededException: $message';
}

/// A CMS read returned rows that violate the page/tenant contract (foreign
/// tenant, malformed block, missing id). FAIL CLOSED: the snapshot is
/// rejected instead of silently filtered.
class WebsiteCmsReadContractException implements Exception {
  const WebsiteCmsReadContractException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'WebsiteCmsReadContractException: $message';
}

/// An editor read completed for an identity/epoch that is no longer the
/// current one (A -> B or A -> B -> A during the await). The result — late
/// success OR late rejection alike — is OBSOLETE: consumers discard it
/// silently (no error surface, no lease revocation, no denial latch, no
/// data adoption) and let the current identity issue its own read.
class WebsiteEditorReadSupersededException implements Exception {
  const WebsiteEditorReadSupersededException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'WebsiteEditorReadSupersededException: $message';
}

/// Authority loss on an editor read, raised by the single classification
/// point (`WebsiteService.loadEditorPageWithBlocks`): either the local
/// capability gate denies the identity outright, or the server (RLS/auth)
/// rejected a request a stale local grant still believed was authorized.
/// Consumers revoke the entry lease, close the session fail-closed and
/// reload public content. Transient failures never take this type.
class WebsiteEditorAuthorityException implements Exception {
  const WebsiteEditorAuthorityException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'WebsiteEditorAuthorityException: $message';
}
