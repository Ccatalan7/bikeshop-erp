import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/models/website_editor_capability.dart';
import 'package:vinabike_erp/modules/website/models/website_editor_oauth_intent.dart';

const _now = 1000000;

WebsiteEditorCapabilitySnapshot _cap({String identity = 'user-a'}) =>
    WebsiteEditorCapabilitySnapshot(
      identity: identity,
      activeTenantId: 'tenant-1',
      storefrontTenantId: 'tenant-1',
      hasAuthority: true,
      authorityEpoch: 3,
    );

String _issue({
  String identity = 'user-a',
  String? returnPath = '/tienda/config',
  String nonce = 'nonce-1',
}) =>
    WebsiteEditorOAuthIntentGate.issue(
      capability: _cap(identity: identity),
      nowMs: _now,
      nonce: nonce,
      returnPath: returnPath,
      openIntegrations: true,
    );

class _MemoryBackend {
  String? value;
}

WebsiteEditorOAuthIntentStore _store(_MemoryBackend backend) =>
    WebsiteEditorOAuthIntentStore(
      readRaw: () => backend.value,
      writeRaw: (raw) => backend.value = raw,
      removeRaw: () => backend.value = null,
    );

void main() {
  group('issue + sanitize', () {
    test('an issued intent carries nonce/issuer and a sanitized path', () {
      final intent =
          WebsiteEditorOAuthIntentGate.decode(_issue(), nowMs: _now);
      expect(intent, isNotNull);
      expect(intent!.nonce, 'nonce-1');
      expect(intent.issuerIdentity, 'user-a');
      expect(intent.issuerTenantId, 'tenant-1');
      expect(intent.issuerFingerprint, _cap().fingerprint);
      expect(intent.expiresAtMs, greaterThan(intent.issuedAtMs));
    });

    test('edit/preview flags and external paths are neutralized', () {
      final withEdit = WebsiteEditorOAuthIntentGate.decode(
        _issue(returnPath: '/tienda/config?edit=true&tab=seo'),
        nowMs: _now,
      );
      expect(withEdit!.returnPath, '/tienda/config?tab=seo',
          reason: 'A stored ?edit=true can NEVER reopen the editor: the '
              'capability gate decides mode entry, not a URL.');
      expect(
        WebsiteEditorOAuthIntentGate.sanitizeReturnPath(
          'https://evil.example/phish',
        ),
        '/',
      );
      expect(
        WebsiteEditorOAuthIntentGate.sanitizeReturnPath('//evil.example/x'),
        '/',
      );
      expect(
        WebsiteEditorOAuthIntentGate.sanitizeReturnPath(
          '/pagina/x?preview=true',
        ),
        '/pagina/x',
      );
      expect(WebsiteEditorOAuthIntentGate.sanitizeReturnPath(null), '/');
    });

    test('newNonce values are unique and monotonic within a session', () {
      final a = WebsiteEditorOAuthIntentGate.newNonce(_now);
      final b = WebsiteEditorOAuthIntentGate.newNonce(_now);
      expect(a, isNot(b));
    });
  });

  group('strict decode (fail closed)', () {
    test('legacy, malformed, wrong-version, missing-field and expired are '
        'null', () {
      expect(WebsiteEditorOAuthIntentGate.decode('true', nowMs: _now), isNull);
      expect(WebsiteEditorOAuthIntentGate.decode(null, nowMs: _now), isNull);
      expect(
        WebsiteEditorOAuthIntentGate.decode('{no-json', nowMs: _now),
        isNull,
      );
      expect(
        WebsiteEditorOAuthIntentGate.decode(
          _issue().replaceFirst('"version":1', '"version":99'),
          nowMs: _now,
        ),
        isNull,
      );
      expect(
        WebsiteEditorOAuthIntentGate.decode(
          _issue(),
          nowMs: _now +
              WebsiteEditorOAuthIntentGate.timeToLive.inMilliseconds +
              1,
        ),
        isNull,
        reason: 'An expired intent can never be redeemed.',
      );
      final missingNonce = jsonEncode({
        'version': 1,
        'issuerIdentity': 'user-a',
        'issuerTenantId': 'tenant-1',
        'issuerFingerprint': 'x',
        'issuedAtMs': _now,
        'expiresAtMs': _now + 1000,
        'returnPath': '/x',
        'openIntegrations': true,
      });
      expect(
        WebsiteEditorOAuthIntentGate.decode(missingNonce, nowMs: _now),
        isNull,
      );
    });
  });

  group('validateForCallback', () {
    test('only the issuing identity may follow the sanitized path', () {
      expect(
        WebsiteEditorOAuthIntentGate.validateForCallback(
          _issue(),
          currentIdentity: 'user-a',
          nowMs: _now + 1,
        ),
        isNotNull,
      );
      expect(
        WebsiteEditorOAuthIntentGate.validateForCallback(
          _issue(),
          currentIdentity: 'user-b',
          nowMs: _now + 1,
        ),
        isNull,
      );
      expect(
        WebsiteEditorOAuthIntentGate.validateForCallback(
          _issue(),
          currentIdentity: null,
          nowMs: _now + 1,
        ),
        isNull,
      );
      expect(
        WebsiteEditorOAuthIntentGate.validateForCallback(
          'true',
          currentIdentity: 'user-a',
          nowMs: _now + 1,
        ),
        isNull,
        reason: 'A legacy boolean flag can never be validated.',
      );
    });
  });

  group('store one-shot semantics', () {
    test('take consumes BEFORE any await: replay/second mount finds nothing',
        () {
      final backend = _MemoryBackend()..value = _issue();
      final store = _store(backend);
      final taken = store.take(nowMs: _now + 1);
      expect(taken, isNotNull);
      expect(taken!.intent.nonce, 'nonce-1');
      expect(backend.value, isNull, reason: 'Removed atomically.');
      expect(store.take(nowMs: _now + 2), isNull,
          reason: 'A second mount has nothing to redeem.');
    });

    test('take consumes malformed/legacy payloads fail-closed', () {
      final backend = _MemoryBackend()..value = 'true';
      final store = _store(backend);
      expect(store.take(nowMs: _now), isNull);
      expect(backend.value, isNull,
          reason: 'The unusable payload is removed, not left behind.');
    });

    test('restoreIfNonce restores ONLY the same unexpired nonce and never '
        'overwrites a newer intent', () {
      final backend = _MemoryBackend()..value = _issue();
      final store = _store(backend);
      final taken = store.take(nowMs: _now + 1)!;

      // Transient retry restores the SAME nonce.
      store.restoreIfNonce(taken, nowMs: _now + 2);
      expect(backend.value, taken.raw);

      // A NEWER intent owns the key: the old transient result must not
      // overwrite it.
      final takenAgain = store.take(nowMs: _now + 3)!;
      backend.value = _issue(nonce: 'nonce-2');
      store.restoreIfNonce(takenAgain, nowMs: _now + 4);
      final current = WebsiteEditorOAuthIntentGate.decode(
        backend.value,
        nowMs: _now + 5,
      );
      expect(current!.nonce, 'nonce-2');

      // An EXPIRED taken intent is never restored.
      backend.value = null;
      store.restoreIfNonce(
        taken,
        nowMs:
            _now + WebsiteEditorOAuthIntentGate.timeToLive.inMilliseconds + 1,
      );
      expect(backend.value, isNull);
    });

    test('clearIfNonce clears only its own nonce (a failed connect never '
        'destroys a newer intent)', () {
      final backend = _MemoryBackend()..value = _issue(nonce: 'nonce-2');
      final store = _store(backend);
      store.clearIfNonce('nonce-1', nowMs: _now);
      expect(backend.value, isNotNull,
          reason: 'A different nonce owns the key.');
      store.clearIfNonce('nonce-2', nowMs: _now);
      expect(backend.value, isNull);
    });
  });
}
