import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/models/website_editor_capability.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_editor_draft_store.dart';
import 'package:vinabike_erp/public_store/widgets/persistent_editor_shell.dart';

const _tenantId = 'tenant-a';

/// Switching between the Flutter canvas and the «Vista HTML» is a view
/// change, not a new editing session: the local-draft guard stays the same
/// one and never offers the operator's own unsaved work back as a draft to
/// «Restaurar» (seen in the app on 2026-10-07, after a layer was turned).
void main() {
  testWidgets('switching the view keeps the draft guard and offers nothing',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final provider = WebsiteEditModeProvider();
    addTearDown(provider.dispose);
    provider.adoptEditorEntryLease(
      0,
      const WebsiteEditorCapabilitySnapshot(
        identity: 'switch-user',
        activeTenantId: _tenantId,
        storefrontTenantId: _tenantId,
        hasAuthority: true,
      ),
    );
    provider.enterEditMode(
      const [
        {
          'id': 'text-1',
          'block_type': 'text',
          'block_data': {'text': 'Publicado'},
          'order_index': 0,
          'is_visible': true,
        },
      ],
      const {},
      pageId: 'page-a',
      // A page with no public path: the view's slot comes and goes as in the
      // app, but it draws nothing (no web view in a test).
      pageSlug: '',
    );
    provider.setShowsHtmlCanvas(false);
    final storage = _MemoryDraftStorage();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: MaterialApp(
          home: Scaffold(
            body: PersistentEditorShell(
              tenantIdResolver: () async => _tenantId,
              draftStore: WebsiteEditorDraftStore(
                storage: storage,
                clock: () => DateTime.utc(2026, 10, 7),
              ),
              child: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    provider.updateBlockData('text-1', 'text', 'Borrador');
    // Past the draft's debounce: the edit is in the local store.
    await tester.pump(const Duration(seconds: 3));
    expect(storage.values, isNotEmpty);

    final restore = find.byKey(const ValueKey('website-draft-restore-notice'));
    for (final html in [true, false, true]) {
      provider.setShowsHtmlCanvas(html);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(restore, findsNothing, reason: 'Vista HTML $html');
    }
    expect(storage.readCalls, 1,
        reason: 'the guard read the store once, when the session opened');
    expect(provider.getBlockData('text-1')['text'], 'Borrador');
  });
}

class _MemoryDraftStorage implements WebsiteEditorDraftStorage {
  final Map<String, String> values = {};
  int readCalls = 0;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async {
    readCalls++;
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
