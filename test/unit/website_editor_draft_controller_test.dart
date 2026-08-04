import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_editor_capability.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_editor_draft_controller.dart';
import 'package:vinabike_erp/modules/website/services/website_editor_draft_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clean document cannot erase recovery before explicit choice', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final snapshot = WebsiteEditorDraftSnapshot.capture(
      identity: harness.identity,
      updatedAt: DateTime.utc(2026, 8, 3),
      baseBlocks: _baseBlocks,
      draftBlocks: _draftBlocks,
      previewViewport: WebsiteViewport.mobile,
      writeScope: WebsiteWriteScope.viewport,
      selectedBlockId: 'hero-1',
    );
    await harness.store.save(snapshot);

    harness.controller.start();
    await harness.controller.flushNow();
    expect(harness.storage.values, isNotEmpty,
        reason: 'autosave is gated until recovery has been resolved');

    final recovery = await harness.controller.resolveRecovery();
    expect(recovery.canRestore, isTrue);
    expect(harness.controller.isAwaitingRecoveryChoice, isTrue);
    await harness.controller.flushNow();
    expect(harness.storage.values, isNotEmpty,
        reason: 'a clean server document cannot delete the pending recovery');
  });

  test('restore is authority-bound, undoable and keeps autosave active',
      () async {
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
    harness.controller.start();
    await harness.controller.resolveRecovery();

    final changed = await harness.controller.restorePending();

    expect(changed, isTrue);
    expect(harness.provider.getBlockData('hero-1')['title'], 'Recovered');
    expect(harness.provider.previewViewport, WebsiteViewport.mobile);
    expect(harness.provider.writeScope, WebsiteWriteScope.viewport);
    expect(harness.provider.selectedBlockId, 'hero-1');
    expect(harness.provider.canUndo, isTrue);
    expect(harness.storage.values, isNotEmpty);

    harness.provider.undo();
    await harness.controller.flushNow();
    expect(harness.provider.hasPageDraftChanges, isFalse);
    expect(harness.storage.values, isEmpty,
        reason: 'returning to the baseline clears the durable draft');
  });

  test('discard removes the pending recovery without mutating the provider',
      () async {
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
      ),
    );
    harness.controller.start();
    await harness.controller.resolveRecovery();

    await harness.controller.discardPending();

    expect(harness.storage.values, isEmpty);
    expect(harness.provider.getBlockData('hero-1')['title'], 'Base');
    expect(harness.provider.hasPageDraftChanges, isFalse);
  });

  test('stale baseline remains pending and cannot be restored silently',
      () async {
    final harness = _Harness(baseBlocks: _changedBaseBlocks);
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
    harness.controller.start();

    final result = await harness.controller.resolveRecovery();

    expect(result.disposition, WebsiteEditorDraftReadDisposition.staleBase);
    expect(harness.controller.isAwaitingRecoveryChoice, isTrue);
    expect(await harness.controller.restorePending(), isFalse);
    expect(harness.provider.getBlockData('hero-1')['title'], 'Remote');
    expect(harness.storage.values, isNotEmpty);
  });

  test('page switch during recovery produces a typed superseded outcome',
      () async {
    final delayed = _DelayedDraftStorage();
    final harness = _Harness(storage: delayed);
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
    harness.controller.start();
    delayed.holdReads = true;
    final resolving = harness.controller.resolveRecovery();
    await delayed.readStarted.future;

    harness.provider.activatePageDocument(
      _changedBaseBlocks,
      const {},
      pageId: 'page-b',
      pageSlug: 'otra',
    );
    delayed.releaseRead.complete();

    await expectLater(
      resolving,
      throwsA(isA<WebsiteEditorReadSupersededException>()),
    );
    expect(harness.provider.currentPageId, 'page-b');
    expect(harness.provider.getBlockData('hero-1')['title'], 'Remote');
  });

  test('autosave serializes newer edit after an older pending write', () async {
    final delayed = _DelayedDraftStorage()..holdWrites = true;
    final harness = _Harness(storage: delayed);
    addTearDown(harness.dispose);
    harness.controller.start();
    await harness.controller.resolveRecovery();

    harness.provider.updateBlockData('hero-1', 'title', 'First');
    final first = harness.controller.flushNow();
    await delayed.writeStarted.future;
    harness.provider.updateBlockData('hero-1', 'title', 'Second');
    final second = harness.controller.flushNow();
    delayed.releaseWrite.complete();
    await Future.wait([first, second]);

    final result = await harness.store.read(
      identity: harness.identity,
      currentBaseBlocks: _baseBlocks,
    );
    expect(result.snapshot!.blocks.single['block_data']['title'], 'Second');
  });

  test('page switch before debounce flushes the detached old-page snapshot',
      () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final pageAIdentity = harness.identity;
    final pageBIdentity = WebsiteEditorDraftIdentity.forPage(
      capability: _lease,
      pageId: 'page-b',
      pageSlug: 'otra',
    );
    harness.controller.start();
    await harness.controller.resolveRecovery();

    harness.provider.updateBlockData('hero-1', 'title', 'Fast route change');
    harness.provider.activatePageDocument(
      _changedBaseBlocks,
      const {},
      pageId: 'page-b',
      pageSlug: 'otra',
    );
    await harness.controller.flushNow();

    final pageA = await harness.store.read(
      identity: pageAIdentity,
      currentBaseBlocks: _baseBlocks,
    );
    final pageB = await harness.store.read(
      identity: pageBIdentity,
      currentBaseBlocks: _changedBaseBlocks,
    );
    expect(pageA.disposition, WebsiteEditorDraftReadDisposition.restorable);
    expect(
      pageA.snapshot!.blocks.single['block_data']['title'],
      'Fast route change',
    );
    expect(pageB.disposition, WebsiteEditorDraftReadDisposition.absent,
        reason: 'the old controller can never recapture the new page');
  });
}

const _lease = WebsiteEditorCapabilitySnapshot(
  identity: 'user-a',
  activeTenantId: 'tenant-a',
  storefrontTenantId: 'tenant-a',
  hasAuthority: true,
  authorityEpoch: 3,
);

const _baseBlocks = <Map<String, dynamic>>[
  {
    'id': 'hero-1',
    'block_type': 'hero',
    'block_data': {'title': 'Base'},
  },
];

const _changedBaseBlocks = <Map<String, dynamic>>[
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
    _MemoryDraftStorage? storage,
    List<Map<String, dynamic>> baseBlocks = _baseBlocks,
  }) : storage = storage ?? _MemoryDraftStorage() {
    provider.adoptEditorEntryLease(0, _lease);
    provider.openEditorDocument(
      baseBlocks,
      const {},
      mode: WebsiteEditorMode.edit,
      pageId: 'page-a',
      pageSlug: 'inicio',
    );
    store = WebsiteEditorDraftStore(
      storage: this.storage,
      clock: () => DateTime.utc(2026, 8, 4),
    );
    controller = WebsiteEditorDraftController(
      provider: provider,
      store: store,
      debounce: const Duration(days: 1),
      clock: () => DateTime.utc(2026, 8, 4),
    );
  }

  final WebsiteEditModeProvider provider = WebsiteEditModeProvider();
  final _MemoryDraftStorage storage;
  late final WebsiteEditorDraftStore store;
  late final WebsiteEditorDraftController controller;

  WebsiteEditorDraftIdentity get identity => WebsiteEditorDraftIdentity.forPage(
        capability: _lease,
        pageId: provider.currentPageId,
        pageSlug: provider.currentPageSlug,
      );

  Future<void> dispose() async {
    await controller.dispose();
    provider.dispose();
  }
}

class _MemoryDraftStorage implements WebsiteEditorDraftStorage {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

class _DelayedDraftStorage extends _MemoryDraftStorage {
  bool holdReads = false;
  bool holdWrites = false;
  final Completer<void> readStarted = Completer<void>();
  final Completer<void> releaseRead = Completer<void>();
  final Completer<void> writeStarted = Completer<void>();
  final Completer<void> releaseWrite = Completer<void>();

  @override
  Future<String?> read(String key) async {
    if (holdReads) {
      if (!readStarted.isCompleted) readStarted.complete();
      await releaseRead.future;
    }
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    if (holdWrites) {
      if (!writeStarted.isCompleted) writeStarted.complete();
      await releaseWrite.future;
      holdWrites = false;
    }
    await super.write(key, value);
  }
}
