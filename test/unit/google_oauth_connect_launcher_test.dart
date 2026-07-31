import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/website/models/website_editor_capability.dart';
import 'package:vinabike_erp/modules/website/models/website_editor_oauth_intent.dart';
import 'package:vinabike_erp/modules/website/services/google_business_service.dart';

const _identity = 'user-oauth';

WebsiteEditorCapabilitySnapshot _cap() => const WebsiteEditorCapabilitySnapshot(
      identity: _identity,
      activeTenantId: 'tenant-1',
      storefrontTenantId: 'tenant-1',
      hasAuthority: true,
    );

class _MemoryBackend {
  String? value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  ({GoogleBusinessService service, _MemoryBackend backend}) buildService() {
    final backend = _MemoryBackend();
    final service = GoogleBusinessService()
      ..currentUserIdOverride = (() => _identity)
      ..intentStoreOverride = WebsiteEditorOAuthIntentStore(
        readRaw: () => backend.value,
        writeRaw: (raw) => backend.value = raw,
        removeRaw: () => backend.value = null,
      );
    return (service: service, backend: backend);
  }

  test(
      'a launcher that returns FALSE is a failed/aborted launch: the OWN '
      'intent is consumed and a visible error is surfaced', () async {
    final harness = buildService();
    var persistedDuringLaunch = false;
    harness.service.oauthLaunchOverride = (stage) async {
      // The intent must already be persisted when the launcher runs.
      persistedDuringLaunch = harness.backend.value != null;
      return false; // Aborted/failed launch.
    };

    await harness.service.connect(editorCapability: _cap());

    expect(persistedDuringLaunch, isTrue,
        reason: 'The one-shot intent is written before launching.');
    expect(harness.backend.value, isNull,
        reason: 'A FALSE launcher result consumes the pending intent — it '
            'never lingers until expiry.');
    expect(harness.service.error, isNotNull,
        reason: 'The user sees a visible error, never a silent no-op.');
  });

  test('a launcher FALSE clears ONLY its own nonce, never a newer intent',
      () async {
    final harness = buildService();
    harness.service.oauthLaunchOverride = (stage) async {
      // A NEWER intent takes the key while the old launch is in flight.
      harness.backend.value = WebsiteEditorOAuthIntentGate.issue(
        capability: _cap(),
        nowMs: DateTime.now().millisecondsSinceEpoch,
        nonce: 'nonce-newer',
        returnPath: '/tienda/config',
        openIntegrations: true,
      );
      return false;
    };

    await harness.service.connect(editorCapability: _cap());

    final surviving = WebsiteEditorOAuthIntentGate.decode(
      harness.backend.value,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    expect(surviving?.nonce, 'nonce-newer',
        reason: 'clearIfNonce protects the newer intent.');
    expect(harness.service.error, isNotNull);
  });

  test('a successful launch keeps the pending intent for the return trip',
      () async {
    final harness = buildService();
    harness.service.oauthLaunchOverride = (stage) async => true;

    await harness.service.connect(editorCapability: _cap());

    final intent = WebsiteEditorOAuthIntentGate.decode(
      harness.backend.value,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    expect(intent, isNotNull,
        reason: 'The intent survives so the callback/consumer can redeem '
            'it after the redirect.');
    expect(intent!.issuerIdentity, _identity);
    expect(harness.service.error, isNull);
  });

  test('an unauthorized capability persists NOTHING and never launches',
      () async {
    final harness = buildService();
    var launched = false;
    harness.service.oauthLaunchOverride = (stage) async {
      launched = true;
      return true;
    };

    await harness.service.connect(editorCapability: null);
    expect(launched, isFalse);
    expect(harness.backend.value, isNull);
    expect(harness.service.error, isNotNull);

    // Identity mismatch between capability and current user: same result.
    harness.service.currentUserIdOverride = (() => 'otro-usuario');
    await harness.service.connect(editorCapability: _cap());
    expect(launched, isFalse);
    expect(harness.backend.value, isNull);
  });
}
