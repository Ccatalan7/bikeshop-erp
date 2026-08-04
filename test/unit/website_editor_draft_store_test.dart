import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_editor_capability.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/services/website_editor_draft_store.dart';

void main() {
  const capability = WebsiteEditorCapabilitySnapshot(
    identity: 'user-a',
    activeTenantId: 'tenant-a',
    storefrontTenantId: 'tenant-a',
    hasAuthority: true,
    authorityEpoch: 7,
  );
  final identity = WebsiteEditorDraftIdentity.forPage(
    capability: capability,
    pageId: 'page-a',
    pageSlug: 'ignored-when-id-exists',
  );
  final base = <Map<String, dynamic>>[
    {
      'id': 'hero-1',
      'block_type': 'hero',
      'block_data': {'title': 'Base'},
    },
  ];
  final draft = <Map<String, dynamic>>[
    {
      'id': 'hero-1',
      'block_type': 'hero',
      'block_data': {
        'title': 'Draft',
        'responsive': {
          'mobile': {
            'imageUrl': 'mobile.jpg',
          },
        },
      },
    },
  ];

  test('identity is page- and capability-bound without exposing raw ids', () {
    final otherPage = WebsiteEditorDraftIdentity.forPage(
      capability: capability,
      pageId: 'page-b',
    );
    final otherUser = WebsiteEditorDraftIdentity.forPage(
      capability: const WebsiteEditorCapabilitySnapshot(
        identity: 'user-b',
        activeTenantId: 'tenant-a',
        storefrontTenantId: 'tenant-a',
        hasAuthority: true,
        authorityEpoch: 7,
      ),
      pageId: 'page-a',
    );

    expect(identity.storageKey, isNot(otherPage.storageKey));
    expect(identity.storageKey, isNot(otherUser.storageKey));
    expect(identity.storageKey, isNot(contains('user-a')));
    expect(identity.storageKey, isNot(contains('page-a')));
    expect(identity.pageKey, 'id:page-a');
  });

  test('home and normalized home slugs share one durable identity', () {
    final home = WebsiteEditorDraftIdentity.forPage(
      capability: capability,
    );
    final inicio = WebsiteEditorDraftIdentity.forPage(
      capability: capability,
      pageSlug: '/INICIO/',
    );

    expect(home.pageKey, 'home');
    expect(inicio.pageKey, 'home');
    expect(home.storageKey, inicio.storageKey);
  });

  test('denied capability cannot create a durable draft identity', () {
    expect(
      () => WebsiteEditorDraftIdentity.forPage(
        capability: const WebsiteEditorCapabilitySnapshot(
          identity: 'user-a',
          activeTenantId: 'tenant-a',
          storefrontTenantId: 'tenant-b',
          hasAuthority: true,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('snapshot sanitizes transient Canvas state and keeps responsive data',
      () {
    final snapshot = WebsiteEditorDraftSnapshot.capture(
      identity: identity,
      updatedAt: DateTime.utc(2026, 8, 3),
      baseBlocks: base,
      draftBlocks: [
        {
          'id': 'canvas-1',
          'block_type': 'canvas',
          'block_data': {
            'activeElementId': 'transient',
            'elements': [
              {'id': 'layer-1', 'activeElementId': 'business-metadata'},
            ],
            'responsive': {
              'mobile': {
                'activeElementId': 'transient-mobile',
                'width': 320,
              },
            },
          },
        },
      ],
      previewViewport: WebsiteViewport.mobile,
      writeScope: WebsiteWriteScope.viewport,
      selectedBlockId: 'canvas-1',
    );

    final data = snapshot.blocks.single['block_data'] as Map<String, dynamic>;
    expect(data, isNot(contains('activeElementId')));
    expect(
      (data['elements'] as List).single['activeElementId'],
      'business-metadata',
    );
    expect(
      ((data['responsive'] as Map)['mobile'] as Map),
      {'width': 320},
    );
    expect(snapshot.selectedBlockId, 'canvas-1');
  });

  test('desktop recovery always coerces write scope to shared', () {
    final snapshot = WebsiteEditorDraftSnapshot.capture(
      identity: identity,
      updatedAt: DateTime.utc(2026, 8, 3),
      baseBlocks: base,
      draftBlocks: draft,
      previewViewport: WebsiteViewport.desktop,
      writeScope: WebsiteWriteScope.viewport,
    );

    expect(snapshot.writeScope, WebsiteWriteScope.shared);
    expect(
      WebsiteEditorDraftSnapshot.decode(snapshot.encode()).writeScope,
      WebsiteWriteScope.shared,
    );
  });

  test('matching authority and base returns a restorable snapshot', () async {
    final backend = _MemoryDraftStorage();
    final store = WebsiteEditorDraftStore(
      storage: backend,
      clock: () => DateTime.utc(2026, 8, 4),
    );
    final snapshot = WebsiteEditorDraftSnapshot.capture(
      identity: identity,
      updatedAt: DateTime.utc(2026, 8, 3),
      baseBlocks: base,
      draftBlocks: draft,
      previewViewport: WebsiteViewport.mobile,
      writeScope: WebsiteWriteScope.viewport,
      selectedBlockId: 'hero-1',
    );
    await store.save(snapshot);

    final result = await store.read(
      identity: identity,
      currentBaseBlocks: base,
    );

    expect(result.disposition, WebsiteEditorDraftReadDisposition.restorable);
    expect(result.canRestore, isTrue);
    expect(
      result.snapshot!.blocks.single['block_data']['title'],
      'Draft',
    );
    expect(result.snapshot!.previewViewport, WebsiteViewport.mobile);
    expect(result.snapshot!.writeScope, WebsiteWriteScope.viewport);
  });

  test('a changed server baseline never receives a silent local overlay',
      () async {
    final backend = _MemoryDraftStorage();
    final store = WebsiteEditorDraftStore(storage: backend);
    await store.save(
      WebsiteEditorDraftSnapshot.capture(
        identity: identity,
        updatedAt: DateTime.now(),
        baseBlocks: base,
        draftBlocks: draft,
        previewViewport: WebsiteViewport.mobile,
        writeScope: WebsiteWriteScope.viewport,
      ),
    );

    final result = await store.read(
      identity: identity,
      currentBaseBlocks: [
        {
          'id': 'hero-1',
          'block_type': 'hero',
          'block_data': {'title': 'Changed remotely'},
        },
      ],
    );

    expect(result.disposition, WebsiteEditorDraftReadDisposition.staleBase);
    expect(result.canRestore, isFalse);
    expect(backend.values, isNotEmpty,
        reason: 'stale is recoverable evidence until the user discards it');
  });

  test('authority epoch mismatch fails closed', () async {
    final backend = _MemoryDraftStorage();
    final store = WebsiteEditorDraftStore(storage: backend);
    final snapshot = WebsiteEditorDraftSnapshot.capture(
      identity: identity,
      updatedAt: DateTime.now(),
      baseBlocks: base,
      draftBlocks: draft,
      previewViewport: WebsiteViewport.mobile,
      writeScope: WebsiteWriteScope.viewport,
    );
    final envelope = jsonDecode(snapshot.encode()) as Map<String, dynamic>;
    (envelope['identity'] as Map<String, dynamic>)['authorityEpoch'] = 8;
    backend.values[identity.storageKey] = jsonEncode(envelope);

    final result = await store.read(
      identity: identity,
      currentBaseBlocks: base,
    );

    expect(
      result.disposition,
      WebsiteEditorDraftReadDisposition.authorityMismatch,
    );
    expect(result.canRestore, isFalse);
  });

  test('expired and malformed drafts are removed', () async {
    final backend = _MemoryDraftStorage();
    final store = WebsiteEditorDraftStore(
      storage: backend,
      retention: const Duration(days: 2),
      clock: () => DateTime.utc(2026, 8, 6),
    );
    await store.save(
      WebsiteEditorDraftSnapshot.capture(
        identity: identity,
        updatedAt: DateTime.utc(2026, 8, 3),
        baseBlocks: base,
        draftBlocks: draft,
        previewViewport: WebsiteViewport.mobile,
        writeScope: WebsiteWriteScope.viewport,
      ),
    );

    final expired = await store.read(
      identity: identity,
      currentBaseBlocks: base,
    );
    expect(expired.disposition, WebsiteEditorDraftReadDisposition.expired);
    expect(backend.values, isEmpty);

    backend.values[identity.storageKey] = '{bad json';
    final invalid = await store.read(
      identity: identity,
      currentBaseBlocks: base,
    );
    expect(invalid.disposition, WebsiteEditorDraftReadDisposition.invalid);
    expect(backend.values, isEmpty);
  });

  test('integrity mismatch fails closed and is removed', () async {
    final backend = _MemoryDraftStorage();
    final store = WebsiteEditorDraftStore(storage: backend);
    final snapshot = WebsiteEditorDraftSnapshot.capture(
      identity: identity,
      updatedAt: DateTime.now(),
      baseBlocks: base,
      draftBlocks: draft,
      previewViewport: WebsiteViewport.mobile,
      writeScope: WebsiteWriteScope.viewport,
    );
    final envelope = jsonDecode(snapshot.encode()) as Map<String, dynamic>;
    final payload = envelope['payload'] as Map<String, dynamic>;
    ((payload['blocks'] as List).single['block_data']
        as Map<String, dynamic>)['title'] = 'Tampered';
    backend.values[identity.storageKey] = jsonEncode(envelope);

    final result = await store.read(
      identity: identity,
      currentBaseBlocks: base,
    );

    expect(result.disposition, WebsiteEditorDraftReadDisposition.invalid);
    expect(backend.values, isEmpty);
  });

  test('discard removes only the exact identity/page key', () async {
    final backend = _MemoryDraftStorage();
    final store = WebsiteEditorDraftStore(storage: backend);
    final other = WebsiteEditorDraftIdentity.forPage(
      capability: capability,
      pageId: 'page-b',
    );
    backend.values[identity.storageKey] = 'a';
    backend.values[other.storageKey] = 'b';

    await store.discard(identity);

    expect(backend.values, {other.storageKey: 'b'});
  });
}

class _MemoryDraftStorage implements WebsiteEditorDraftStorage {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}
