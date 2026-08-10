import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_editor_capability.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_editor_draft_store.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_draft_recovery_host.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('offers explicit restore and restores the typed page draft',
      (tester) async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    await harness.store.save(
      WebsiteEditorDraftSnapshot.capture(
        identity: harness.identity,
        updatedAt: DateTime.utc(2026, 8, 3),
        baseBlocks: _baseBlocks,
        draftBlocks: _draftBlocks,
        previewViewport: WebsiteViewport.mobile,
        writeScope: WebsiteWriteScope.viewport,
        selectedBlockId: 'hero-1',
      ),
    );

    await _pumpHost(tester, harness);

    expect(find.byKey(const ValueKey('website-draft-restore-notice')),
        findsOneWidget);
    expect(find.text('Restaurar'), findsOneWidget);
    expect(find.text('Descartar'), findsOneWidget);
    expect(
      tester.getSize(find.widgetWithText(TextButton, 'Restaurar')).height,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull,
        reason: 'the recovery decision must fit a phone-width host');

    await tester.tap(find.text('Restaurar'));
    await tester.pumpAndSettle();

    expect(harness.provider.getBlockData('hero-1')['title'], 'Recovered');
    expect(harness.provider.previewViewport, WebsiteViewport.mobile);
    expect(harness.provider.writeScope, WebsiteWriteScope.viewport);
    expect(harness.provider.selectedBlockId, 'hero-1');
    expect(find.text('Hay un borrador local sin guardar'), findsNothing);
  });

  testWidgets('stale baseline never offers an unsafe restore', (tester) async {
    final harness = _Harness(baseBlocks: _remoteBlocks);
    addTearDown(harness.dispose);
    await harness.store.save(
      WebsiteEditorDraftSnapshot.capture(
        identity: harness.identity,
        updatedAt: DateTime.utc(2026, 8, 3),
        baseBlocks: _baseBlocks,
        draftBlocks: _draftBlocks,
        previewViewport: WebsiteViewport.mobile,
        writeScope: WebsiteWriteScope.viewport,
      ),
    );

    await _pumpHost(tester, harness);

    expect(find.byKey(const ValueKey('website-draft-stale-notice')),
        findsOneWidget);
    expect(find.text('Restaurar'), findsNothing);
    expect(find.text('Descartar'), findsOneWidget);

    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(harness.storage.values, isEmpty);
    expect(harness.provider.getBlockData('hero-1')['title'], 'Remote');
  });

  testWidgets('a failed local read has a real retry path', (tester) async {
    final storage = _MemoryDraftStorage()..readFailuresRemaining = 1;
    final harness = _Harness(storage: storage);
    addTearDown(harness.dispose);

    await _pumpHost(tester, harness);
    expect(find.byKey(const ValueKey('website-draft-recovery-error')),
        findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(storage.readCalls, 2);
    expect(find.byKey(const ValueKey('website-draft-recovery-error')),
        findsNothing);
  });
}

Future<void> _pumpHost(WidgetTester tester, _Harness harness) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.resolve(
        preset: AppearancePresets.all.first,
        brightness: Brightness.light,
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: WebsiteEditorDraftRecoveryHost(
            provider: harness.provider,
            store: harness.store,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _lease = WebsiteEditorCapabilitySnapshot(
  identity: 'user-a',
  activeTenantId: 'tenant-a',
  storefrontTenantId: 'tenant-a',
  hasAuthority: true,
  authorityEpoch: 4,
);

const _baseBlocks = <Map<String, dynamic>>[
  {
    'id': 'hero-1',
    'block_type': 'hero',
    'block_data': {'title': 'Base'},
  },
];

const _remoteBlocks = <Map<String, dynamic>>[
  {
    'id': 'hero-1',
    'block_type': 'hero',
    'block_data': {'title': 'Remote'},
  },
];

const _draftBlocks = <Map<String, dynamic>>[
  {
    'id': 'hero-1',
    'block_type': 'hero',
    'block_data': {'title': 'Recovered'},
  },
];

class _Harness {
  _Harness({
    List<Map<String, dynamic>> baseBlocks = _baseBlocks,
    _MemoryDraftStorage? storage,
  }) : storage = storage ?? _MemoryDraftStorage() {
    provider.adoptEditorEntryLease(0, _lease);
    provider.openEditorDocument(
      baseBlocks,
      const {},
      mode: WebsiteEditorMode.edit,
      pageId: 'page-a',
      pageSlug: 'inicio',
    );
    // The store keeps a draft for seven days and this harness saves one dated
    // 2026-08-03. Left on the wall clock the file passed until 2026-08-10 and
    // then began reporting the draft as expired — a red suite nobody caused,
    // on a day nobody touched the editor. A test about recovery must own its
    // clock, so what it asserts is behaviour and not the date it runs on.
    store = WebsiteEditorDraftStore(
      storage: this.storage,
      clock: () => DateTime.utc(2026, 8, 4),
    );
  }

  final WebsiteEditModeProvider provider = WebsiteEditModeProvider();
  final _MemoryDraftStorage storage;
  late final WebsiteEditorDraftStore store;

  WebsiteEditorDraftIdentity get identity => WebsiteEditorDraftIdentity.forPage(
        capability: _lease,
        pageId: provider.currentPageId,
        pageSlug: provider.currentPageSlug,
      );

  void dispose() => provider.dispose();
}

class _MemoryDraftStorage implements WebsiteEditorDraftStorage {
  final Map<String, String> values = {};
  int readFailuresRemaining = 0;
  int readCalls = 0;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async {
    readCalls++;
    if (readFailuresRemaining > 0) {
      readFailuresRemaining--;
      throw StateError('synthetic read failure');
    }
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
