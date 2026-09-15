import 'dart:convert';

import '../providers/website_edit_mode_provider.dart';
import 'website_editor_capability.dart';
import 'website_editor_mode_route_binding.dart';

/// One TYPED, VERSIONED OAuth editor-return intent persisted under a single
/// storage key. It replaces the legacy loose boolean flags: a unique nonce,
/// the issuer (identity + storefront tenant + capability fingerprint), an
/// issue/expiry window, the sanitized internal return path and the
/// Integrations request all travel together. A return that cannot PROVE its
/// issuer fails closed and the one-shot is consumed safely.
class WebsiteEditorOAuthIntent {
  const WebsiteEditorOAuthIntent({
    required this.nonce,
    required this.issuerIdentity,
    required this.issuerTenantId,
    required this.issuerFingerprint,
    required this.issuedAtMs,
    required this.expiresAtMs,
    required this.returnPath,
    required this.openIntegrations,
  });

  /// Unique per issued intent: the consumer TAKES (removes) this exact
  /// nonce before any async await, so a replay or a second mount has
  /// nothing left to redeem, and a transient retry can only restore the
  /// very same nonce it took.
  final String nonce;
  final String issuerIdentity;
  final String issuerTenantId;
  final String issuerFingerprint;
  final int issuedAtMs;
  final int expiresAtMs;
  final String returnPath;
  final bool openIntegrations;

  Map<String, dynamic> toJson() => {
        'version': WebsiteEditorOAuthIntentGate.currentVersion,
        'nonce': nonce,
        'issuerIdentity': issuerIdentity,
        'issuerTenantId': issuerTenantId,
        'issuerFingerprint': issuerFingerprint,
        'issuedAtMs': issuedAtMs,
        'expiresAtMs': expiresAtMs,
        'returnPath': returnPath,
        'openIntegrations': openIntegrations,
      };
}

/// Pure single owner of intent encoding/validation. Storage semantics live
/// in [WebsiteEditorOAuthIntentStore].
class WebsiteEditorOAuthIntentGate {
  const WebsiteEditorOAuthIntentGate._();

  static const String storageKey = 'google_oauth_editor_intent';
  static const int currentVersion = 1;
  static const Duration timeToLive = Duration(minutes: 10);

  static int _nonceCounter = 0;

  /// Unique, non-secret nonce: monotonic per session + issue timestamp.
  static String newNonce(int nowMs) => 'oauth-$nowMs-${++_nonceCounter}';

  /// Return paths are same-app paths WITHOUT editor mode flags: entering
  /// Edit is decided by the capability gate, never by a stored URL.
  static String sanitizeReturnPath(String? raw) {
    final trimmed = (raw ?? '').trim();
    final uri = Uri.tryParse(trimmed);
    if (uri == null ||
        uri.hasScheme ||
        uri.host.isNotEmpty ||
        !uri.path.startsWith('/')) {
      return '/';
    }
    final cleaned =
        projectWebsiteEditorModeOntoUri(uri, WebsiteEditorMode.public);
    return Uri(
      path: cleaned.path,
      query:
          cleaned.hasQuery && cleaned.query.isNotEmpty ? cleaned.query : null,
    ).toString();
  }

  /// Issues a NEW intent for a GRANTED capability.
  static String issue({
    required WebsiteEditorCapabilitySnapshot capability,
    required int nowMs,
    required String nonce,
    required String? returnPath,
    required bool openIntegrations,
  }) {
    assert(capability.granted, 'Only a granted capability may issue');
    return jsonEncode(
      WebsiteEditorOAuthIntent(
        nonce: nonce,
        issuerIdentity: capability.identity,
        issuerTenantId: capability.storefrontTenantId,
        issuerFingerprint: capability.fingerprint,
        issuedAtMs: nowMs,
        expiresAtMs: nowMs + timeToLive.inMilliseconds,
        returnPath: sanitizeReturnPath(returnPath),
        openIntegrations: openIntegrations,
      ).toJson(),
    );
  }

  /// STRICT decode: null on any legacy/malformed/expired payload.
  static WebsiteEditorOAuthIntent? decode(String? raw, {required int nowMs}) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      if (decoded['version'] != currentVersion) return null;
      final nonce = decoded['nonce'];
      final issuerIdentity = decoded['issuerIdentity'];
      final issuerTenantId = decoded['issuerTenantId'];
      final issuerFingerprint = decoded['issuerFingerprint'];
      final issuedAtMs = decoded['issuedAtMs'];
      final expiresAtMs = decoded['expiresAtMs'];
      final returnPath = decoded['returnPath'];
      final openIntegrations = decoded['openIntegrations'];
      if (nonce is! String ||
          nonce.isEmpty ||
          issuerIdentity is! String ||
          issuerIdentity.isEmpty ||
          issuerTenantId is! String ||
          issuerTenantId.isEmpty ||
          issuerFingerprint is! String ||
          issuerFingerprint.isEmpty ||
          issuedAtMs is! int ||
          expiresAtMs is! int ||
          returnPath is! String ||
          openIntegrations is! bool) {
        return null;
      }
      if (nowMs >= expiresAtMs) return null;
      return WebsiteEditorOAuthIntent(
        nonce: nonce,
        issuerIdentity: issuerIdentity,
        issuerTenantId: issuerTenantId,
        issuerFingerprint: issuerFingerprint,
        issuedAtMs: issuedAtMs,
        expiresAtMs: expiresAtMs,
        returnPath: sanitizeReturnPath(returnPath),
        openIntegrations: openIntegrations,
      );
    } catch (_) {
      return null;
    }
  }

  /// Callback-side inspection: a valid, unexpired intent whose issuer is
  /// the CURRENT auth identity. The callback follows ONLY the sanitized
  /// internal path and never projects edit/preview.
  static WebsiteEditorOAuthIntent? validateForCallback(
    String? raw, {
    required String? currentIdentity,
    required int nowMs,
  }) {
    final intent = decode(raw, nowMs: nowMs);
    if (intent == null) return null;
    if (currentIdentity == null ||
        currentIdentity.isEmpty ||
        intent.issuerIdentity != currentIdentity) {
      return null;
    }
    return intent;
  }
}

/// A taken intent together with its raw payload, so a classified TRANSIENT
/// failure can restore exactly the same nonce.
class WebsiteEditorOAuthIntentTake {
  const WebsiteEditorOAuthIntentTake({required this.intent, required this.raw});

  final WebsiteEditorOAuthIntent intent;
  final String raw;
}

/// SINGLE storage owner with one-shot semantics. The backend is injectable
/// (localStorage on web, in-memory in tests); all consumers go through the
/// semantic operations — never raw key access.
class WebsiteEditorOAuthIntentStore {
  WebsiteEditorOAuthIntentStore({
    required String? Function() readRaw,
    required void Function(String value) writeRaw,
    required void Function() removeRaw,
  })  : _readRaw = readRaw,
        _writeRaw = writeRaw,
        _removeRaw = removeRaw;

  final String? Function() _readRaw;
  final void Function(String value) _writeRaw;
  final void Function() _removeRaw;

  /// Non-consuming validity peek.
  WebsiteEditorOAuthIntent? peek({required int nowMs}) =>
      WebsiteEditorOAuthIntentGate.decode(_readRaw(), nowMs: nowMs);

  /// Persists a freshly issued intent.
  void put(String raw) => _writeRaw(raw);

  /// Atomically CONSUMES the stored intent BEFORE any async await: the key
  /// is removed even when the payload is legacy/malformed/expired (those
  /// return null after the safe consumption), so a replay or second mount
  /// finds nothing to redeem.
  WebsiteEditorOAuthIntentTake? take({required int nowMs}) {
    final raw = _readRaw();
    if (raw == null) return null;
    _removeRaw();
    final intent = WebsiteEditorOAuthIntentGate.decode(raw, nowMs: nowMs);
    if (intent == null) return null;
    return WebsiteEditorOAuthIntentTake(intent: intent, raw: raw);
  }

  /// Restores a TAKEN intent after a classified TRANSIENT failure — only
  /// that exact unexpired nonce, and only when no NEWER intent was issued
  /// in the meantime.
  void restoreIfNonce(
    WebsiteEditorOAuthIntentTake taken, {
    required int nowMs,
  }) {
    if (_readRaw() != null) return; // A newer intent owns the key.
    final intent = WebsiteEditorOAuthIntentGate.decode(taken.raw, nowMs: nowMs);
    if (intent == null || intent.nonce != taken.intent.nonce) return;
    _writeRaw(taken.raw);
  }

  /// Clears the key ONLY if it still holds [nonce] (an issuer cleaning up
  /// its own failed launch never destroys a newer intent).
  void clearIfNonce(String nonce, {required int nowMs}) {
    final raw = _readRaw();
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['nonce'] == nonce) {
        _removeRaw();
      }
    } catch (_) {
      // Malformed content under our key: consume it fail-closed.
      _removeRaw();
    }
  }
}
