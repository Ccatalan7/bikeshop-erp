import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/modules/website/models/website_editor_capability.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_save_coordinator.dart';

const _tenantId = 'tenant-a';
const _pageId = 'page-a';
const _pageSlug = 'landing';
const _parentUuid = '11111111-1111-4111-8111-111111111111';
const _childUuid = '22222222-2222-4222-8222-222222222222';

void main() {
  // The provider defers notifications through the scheduler binding.
  TestWidgetsFlutterBinding.ensureInitialized();
  group('WebsiteSaveCoordinator', () {
    test(
        'an atomic block failure preserves published blocks and the client '
        'draft, then retry converges', () async {
      final originalBlocks = [_block('Published headline')];
      final document = _document(originalBlocks);
      addTearDown(document.dispose);
      document.updateBlockData('hero-1', 'headline', 'Draft headline');
      final attemptedDraft = _copyBlocks(document.blocks);

      final failure = StateError('replace_page_blocks failed');
      final gateway = _FakeWebsiteSaveGateway(originalBlocks)
        ..replaceFailure = failure
        ..replaceFailuresRemaining = 1;
      final coordinator = WebsiteSaveCoordinator(gateway);

      await expectLater(
        coordinator.save(tenantId: _tenantId, document: document),
        throwsA(same(failure)),
      );

      expect(gateway.publishedBlocks, equals(originalBlocks));
      expect(document.blocks, equals(attemptedDraft));
      expect(document.hasUnsavedChanges, isTrue);

      final result = await coordinator.save(
        tenantId: _tenantId,
        document: document,
      );

      expect(gateway.replaceCalls, 2);
      expect(gateway.publishedBlocks, equals(attemptedDraft));
      expect(result.freshBlocks, equals(attemptedDraft));
      expect(document.blocks, equals(attemptedDraft));
      expect(document.hasUnsavedChanges, isFalse);
    });

    test(
        'settings acknowledgment clears only matching snapshot values and '
        'keeps a concurrent edit', () async {
      final document = _document([_block('Published headline')]);
      addTearDown(document.dispose);
      document.updateSiteSettings({
        'store_name': 'Attempted name',
        'accent_color': '#111111',
      });

      final gateway = _FakeWebsiteSaveGateway(document.blocks)
        ..settingsGate = Completer<void>();
      final coordinator = WebsiteSaveCoordinator(gateway);

      final save = coordinator.save(
        tenantId: _tenantId,
        document: document,
      );
      await gateway.settingsStarted.future;

      document.updateSiteSetting('accent_color', '#222222');
      gateway.settingsGate!.complete();
      await save;

      expect(gateway.settingsCalls, [
        {
          'store_name': 'Attempted name',
          'accent_color': '#111111',
        },
      ]);
      expect(gateway.persistedSettings, {
        'store_name': 'Attempted name',
        'accent_color': '#111111',
      });
      expect(document.pendingSiteSettings, {
        'accent_color': '#222222',
      });
      expect(document.hasSiteSettingsChanges, isTrue);
      expect(document.hasUnsavedChanges, isTrue);
    });

    test('a stale page completion never replaces the new page document',
        () async {
      final document = _document([_block('Published headline')]);
      addTearDown(document.dispose);
      document.updateBlockData('hero-1', 'headline', 'Page A draft');
      final attemptedPageA = _copyBlocks(document.blocks);

      final gateway = _FakeWebsiteSaveGateway([_block('Published headline')])
        ..replaceGate = Completer<void>();
      final coordinator = WebsiteSaveCoordinator(gateway);

      final save = coordinator.save(
        tenantId: _tenantId,
        document: document,
      );
      await gateway.replaceStarted.future;

      final pageB = [_block('Page B document')];
      document.enterEditMode(
        pageB,
        const {},
        pageId: 'page-b',
        pageSlug: 'other-page',
      );
      gateway.replaceGate!.complete();
      final result = await save;

      expect(gateway.publishedBlocks, attemptedPageA);
      expect(result.appliedToActiveDocument, isFalse);
      expect(document.currentPageId, 'page-b');
      expect(document.currentPageSlug, 'other-page');
      expect(document.blocks, pageB);
    });

    test('a stale tenant completion cannot clear the next tenant draft',
        () async {
      final document = _document([_block('Tenant A')]);
      addTearDown(document.dispose);
      document.updateSiteSetting('store_name', 'Tenant A draft');

      final gateway = _FakeWebsiteSaveGateway(document.blocks)
        ..settingsGate = Completer<void>();
      final coordinator = WebsiteSaveCoordinator(gateway);
      final save = coordinator.save(
        tenantId: _tenantId,
        document: document,
      );
      await gateway.settingsStarted.future;

      gateway.activeTenantId = 'tenant-b';
      document.enterEditMode(
        [_block('Tenant B')],
        const {},
        pageId: 'page-b',
        pageSlug: 'tenant-b-page',
      );
      document.updateSiteSetting('store_name', 'Tenant B draft');
      gateway.settingsGate!.complete();
      final result = await save;

      expect(result.appliedToActiveDocument, isFalse);
      expect(document.pendingSiteSettings, {
        'store_name': 'Tenant B draft',
      });
      expect(
          document.getEffectiveSiteSetting('store_name', ''), 'Tenant B draft');
    });

    test('page scope is validated before the first mutable family', () async {
      final document = _document([_block('Published headline')]);
      addTearDown(document.dispose);
      document.updateBlockData('hero-1', 'headline', 'Must remain pending');
      document.updateSiteSetting('store_name', 'Must remain pending');
      final failure = StateError('page scope rejected');
      final gateway = _FakeWebsiteSaveGateway(document.blocks)
        ..resolveFailure = failure;
      final coordinator = WebsiteSaveCoordinator(gateway);

      await expectLater(
        coordinator.save(tenantId: _tenantId, document: document),
        throwsA(same(failure)),
      );

      expect(gateway.settingsCalls, isEmpty);
      expect(gateway.replaceCalls, 0);
      expect(document.pendingSiteSettings, {
        'store_name': 'Must remain pending',
      });
    });

    test('a sitewide-only save never resolves or replaces the active page',
        () async {
      final originalBlocks = [_block('Published headline')];
      final document = _document(originalBlocks);
      addTearDown(document.dispose);
      document.updateSiteSetting('store_name', 'Sitewide only');

      final gateway = _FakeWebsiteSaveGateway(originalBlocks);
      final coordinator = WebsiteSaveCoordinator(gateway);

      final result = await coordinator.save(
        tenantId: _tenantId,
        document: document,
      );

      expect(gateway.resolveCalls, 0);
      expect(gateway.replaceCalls, 0);
      expect(gateway.publishedBlocks, originalBlocks);
      expect(result.freshBlocks, originalBlocks);
      expect(
        result.completedSections,
        isNot(contains(WebsiteSaveSection.pageBlocks)),
      );
      expect(result.appliedToActiveDocument, isTrue);
      expect(document.pendingSiteSettings, isEmpty);
      expect(document.hasUnsavedChanges, isFalse);
    });

    test(
        'parent-child navigation retry upserts stable UUIDs without duplicate '
        'rows', () async {
      final document = _document([_block('Published headline')]);
      addTearDown(document.dispose);
      const parentDraftId = 'draft_$_parentUuid';
      const childDraftId = 'draft_$_childUuid';

      document.createFooterNavDraft(
        _navigation(
          id: parentDraftId,
          label: 'Parent',
        ),
      );
      document.createFooterNavDraft(
        _navigation(
          id: childDraftId,
          label: 'Child',
          parentId: parentDraftId,
        ),
      );

      final failure = StateError('child navigation upsert failed');
      final gateway = _FakeWebsiteSaveGateway(document.blocks)
        ..navigationFailure = failure
        ..failNavigationIdOnce = _childUuid;
      final coordinator = WebsiteSaveCoordinator(gateway);

      await expectLater(
        coordinator.save(tenantId: _tenantId, document: document),
        throwsA(same(failure)),
      );

      expect(gateway.navigationRows.keys, {_parentUuid});
      expect(
        document.pendingFooterNavCreates.keys,
        {parentDraftId, childDraftId},
      );

      await coordinator.save(tenantId: _tenantId, document: document);

      expect(gateway.navigationRows.keys, {_parentUuid, _childUuid});
      expect(gateway.navigationRows[_parentUuid]!.id, _parentUuid);
      expect(gateway.navigationRows[_parentUuid]!.parentId, isNull);
      expect(gateway.navigationRows[_childUuid]!.id, _childUuid);
      expect(gateway.navigationRows[_childUuid]!.parentId, _parentUuid);
      expect(gateway.navigationUpsertCalls, {
        _parentUuid: 2,
        _childUuid: 2,
      });
      expect(document.pendingFooterNavCreates, isEmpty);
      expect(document.hasFooterChanges, isFalse);
    });

    test(
        'a confirmed navigation update is cleared before a later update fails '
        'and is not replayed on retry', () async {
      final document = _document([_block('Published headline')]);
      addTearDown(document.dispose);
      document
        ..updateFooterNavLabel('nav-a', 'Attempted A')
        ..updateFooterNavLabel('nav-b', 'Attempted B');

      final gateway = _FakeWebsiteSaveGateway(document.blocks)
        ..navigationRows['nav-a'] = _navigation(id: 'nav-a', label: 'Saved A')
        ..navigationRows['nav-b'] = _navigation(id: 'nav-b', label: 'Saved B')
        ..navigationUpdateFailure = StateError('second update failed')
        ..failNavigationUpdateIdOnce = 'nav-b';
      final coordinator = WebsiteSaveCoordinator(gateway);

      await expectLater(
        coordinator.save(tenantId: _tenantId, document: document),
        throwsA(same(gateway.navigationUpdateFailure)),
      );

      expect(gateway.navigationRows['nav-a']!.label, 'Attempted A');
      expect(document.pendingFooterNavLabels, {
        'nav-b': 'Attempted B',
      });
      expect(gateway.navigationUpdateCalls, ['nav-a', 'nav-b']);

      gateway.navigationRows['nav-a'] =
          _navigation(id: 'nav-a', label: 'External A');
      final result = await coordinator.save(
        tenantId: _tenantId,
        document: document,
      );

      expect(gateway.navigationRows['nav-a']!.label, 'External A');
      expect(gateway.navigationRows['nav-b']!.label, 'Attempted B');
      expect(gateway.navigationUpdateCalls, ['nav-a', 'nav-b', 'nav-b']);
      expect(document.pendingFooterNavLabels, isEmpty);
      expect(
        result.completedSections,
        contains(WebsiteSaveSection.navigationUpdates),
      );
      expect(
        result.completedSections,
        isNot(contains(WebsiteSaveSection.navigationCreates)),
      );
    });

    test(
        'a confirmed navigation delete is cleared before block failure and '
        'is not replayed on retry', () async {
      final document = _document([_block('Published headline')]);
      addTearDown(document.dispose);
      final deletedNavigation = _navigation(id: 'nav-delete', label: 'Delete');
      document
        ..deleteFooterNavItem(deletedNavigation)
        ..updateBlockData('hero-1', 'headline', 'Page draft');

      final gateway = _FakeWebsiteSaveGateway(document.blocks)
        ..navigationRows[deletedNavigation.id] = deletedNavigation
        ..replaceFailure = StateError('replace failed after delete')
        ..replaceFailuresRemaining = 1;
      final coordinator = WebsiteSaveCoordinator(gateway);

      await expectLater(
        coordinator.save(tenantId: _tenantId, document: document),
        throwsA(same(gateway.replaceFailure)),
      );

      expect(gateway.navigationDeleteCalls, ['nav-delete']);
      expect(document.pendingFooterNavDeletes, isEmpty);

      gateway.navigationRows['nav-delete'] =
          _navigation(id: 'nav-delete', label: 'External replacement');
      await coordinator.save(tenantId: _tenantId, document: document);

      expect(gateway.navigationDeleteCalls, ['nav-delete']);
      expect(
        gateway.navigationRows['nav-delete']!.label,
        'External replacement',
      );
    });

    test(
        'a confirmed section order is cleared before a later reorder fails '
        'and is not replayed on retry', () async {
      final document = _document([_block('Published headline')]);
      addTearDown(document.dispose);
      document
        ..updateFooterSectionOrder(['section-a', 'section-b'])
        ..updateFooterLinkOrder('section-a', ['link-a', 'link-b']);

      final gateway = _FakeWebsiteSaveGateway(document.blocks)
        ..reorderFailure = StateError('second reorder failed')
        ..failReorderCallOnce = 2;
      final coordinator = WebsiteSaveCoordinator(gateway);

      await expectLater(
        coordinator.save(tenantId: _tenantId, document: document),
        throwsA(same(gateway.reorderFailure)),
      );

      expect(document.pendingFooterSectionOrder, isNull);
      expect(document.pendingFooterLinkOrder, {
        'section-a': ['link-a', 'link-b'],
      });
      expect(gateway.navigationReorderCalls, [
        ['section-a', 'section-b'],
        ['link-a', 'link-b'],
      ]);

      final result = await coordinator.save(
        tenantId: _tenantId,
        document: document,
      );

      expect(gateway.navigationReorderCalls, [
        ['section-a', 'section-b'],
        ['link-a', 'link-b'],
        ['link-a', 'link-b'],
      ]);
      expect(document.pendingFooterLinkOrder, isEmpty);
      expect(
        result.completedSections,
        contains(WebsiteSaveSection.navigationOrder),
      );
      expect(
        result.completedSections,
        isNot(contains(WebsiteSaveSection.navigationCreates)),
      );
    });

    test('simultaneous saves share one in-flight operation', () async {
      final document = _document([_block('Published headline')]);
      addTearDown(document.dispose);
      document.updateBlockData('hero-1', 'headline', 'Draft headline');

      final gateway = _FakeWebsiteSaveGateway(document.blocks)
        ..replaceGate = Completer<void>();
      final coordinator = WebsiteSaveCoordinator(gateway);

      final first = coordinator.save(
        tenantId: _tenantId,
        document: document,
      );
      await gateway.replaceStarted.future;
      final second = coordinator.save(
        tenantId: _tenantId,
        document: document,
      );

      expect(second, same(first));
      expect(gateway.replaceCalls, 1);

      gateway.replaceGate!.complete();
      final results = await Future.wait([first, second]);

      expect(gateway.replaceCalls, 1);
      expect(results[1], same(results[0]));
      expect(document.hasUnsavedChanges, isFalse);
    });

    test('an in-flight save rejects a different document scope', () async {
      final document = _document([_block('Page A')]);
      addTearDown(document.dispose);
      document.updateBlockData('hero-1', 'headline', 'Page A draft');

      final gateway = _FakeWebsiteSaveGateway(document.blocks)
        ..replaceGate = Completer<void>();
      final coordinator = WebsiteSaveCoordinator(gateway);
      final first = coordinator.save(
        tenantId: _tenantId,
        document: document,
      );
      await gateway.replaceStarted.future;

      document.enterEditMode(
        [_block('Page B')],
        const {},
        pageId: 'page-b',
        pageSlug: 'other-page',
      );
      document.updateBlockData('hero-1', 'headline', 'Page B draft');

      await expectLater(
        coordinator.save(tenantId: _tenantId, document: document),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('otro documento'),
          ),
        ),
      );
      expect(document.blocks.single['block_data']['headline'], 'Page B draft');
      expect(document.hasUnsavedChanges, isTrue);

      gateway.replaceGate!.complete();
      final firstResult = await first;
      expect(firstResult.appliedToActiveDocument, isFalse);
      expect(document.blocks.single['block_data']['headline'], 'Page B draft');
      expect(document.hasUnsavedChanges, isTrue);
    });
  });
}

WebsiteEditModeProvider _document(List<Map<String, dynamic>> blocks) {
  final provider = WebsiteEditModeProvider();
  // The save gate requires a typed document owner matching the current
  // granted lease and target tenant; adopt it before opening the document.
  provider.adoptEditorEntryLease(
    provider.editorEntryLeaseGeneration,
    const WebsiteEditorCapabilitySnapshot(
      identity: 'save-user',
      activeTenantId: _tenantId,
      storefrontTenantId: _tenantId,
      hasAuthority: true,
    ),
  );
  provider.enterEditMode(
    _copyBlocks(blocks),
    const {},
    pageId: _pageId,
    pageSlug: _pageSlug,
  );
  return provider;
}

Map<String, dynamic> _block(String headline) {
  return {
    'id': 'hero-1',
    'block_type': 'hero',
    'order_index': 0,
    'is_visible': true,
    'block_data': {
      'headline': headline,
    },
  };
}

WebsiteNavigation _navigation({
  required String id,
  required String label,
  String? parentId,
}) {
  final timestamp = DateTime.utc(2026, 7, 29);
  return WebsiteNavigation(
    id: id,
    tenantId: _tenantId,
    menuLocation: MenuLocation.footer,
    label: label,
    linkType: NavLinkType.page,
    linkValue: '/',
    parentId: parentId,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

class _FakeWebsiteSaveGateway implements WebsiteSaveGateway {
  @override
  void Function()? writeGuard;

  @override
  void recordEditorAuthorityRejection(String tenantId) {}

  @override
  int identityEpoch = 0;

  @override
  WebsiteEditorCapabilitySnapshot? currentCapability(String tenantId) =>
      const WebsiteEditorCapabilitySnapshot(
        identity: 'save-user',
        activeTenantId: 'tenant-a',
        storefrontTenantId: 'tenant-a',
        hasAuthority: true,
      );

  _FakeWebsiteSaveGateway(List<Map<String, dynamic>> publishedBlocks)
      : publishedBlocks = _copyBlocks(publishedBlocks);

  List<Map<String, dynamic>> publishedBlocks;
  final Map<String, String> persistedSettings = {};
  final List<Map<String, String>> settingsCalls = [];
  final Map<String, WebsiteNavigation> navigationRows = {};
  final Map<String, int> navigationUpsertCalls = {};
  final List<String> navigationUpdateCalls = [];
  final List<String> navigationDeleteCalls = [];
  final List<List<String>> navigationReorderCalls = [];

  final Completer<void> settingsStarted = Completer<void>();
  final Completer<void> replaceStarted = Completer<void>();
  Completer<void>? settingsGate;
  Completer<void>? replaceGate;

  Object? replaceFailure;
  Object? resolveFailure;
  int replaceFailuresRemaining = 0;
  Object? navigationFailure;
  String? failNavigationIdOnce;
  bool _didFailNavigation = false;
  Object? navigationUpdateFailure;
  String? failNavigationUpdateIdOnce;
  bool _didFailNavigationUpdate = false;
  Object? reorderFailure;
  int? failReorderCallOnce;
  bool _didFailReorder = false;
  int replaceCalls = 0;
  int resolveCalls = 0;
  String activeTenantId = _tenantId;

  @override
  bool isTenantProjectionActive(String tenantId) => tenantId == activeTenantId;

  @override
  Future<void> saveSettings(
    String tenantId,
    Map<String, String> settings,
  ) async {
    expect(tenantId, _tenantId);
    settingsCalls.add(Map<String, String>.from(settings));
    if (!settingsStarted.isCompleted) settingsStarted.complete();
    final gate = settingsGate;
    if (gate != null) await gate.future;
    persistedSettings.addAll(settings);
  }

  @override
  Future<void> savePageSeo({
    required String tenantId,
    required String routeKey,
    required Map<String, String> values,
  }) async {}

  @override
  Future<WebsiteEditorPageTarget> resolvePage({
    required String tenantId,
    required String? pageId,
    required String? pageSlug,
  }) async {
    expect(tenantId, _tenantId);
    expect(pageId, _pageId);
    expect(pageSlug, _pageSlug);
    resolveCalls++;
    if (resolveFailure case final failure?) throw failure;
    return const WebsiteEditorPageTarget(
      storagePageId: _pageId,
      editorPageId: _pageId,
      pageSlug: _pageSlug,
    );
  }

  @override
  Future<List<Map<String, dynamic>>> replacePageBlocks({
    required String tenantId,
    required String pageId,
    required List<Map<String, dynamic>> blocks,
  }) async {
    expect(tenantId, _tenantId);
    expect(pageId, _pageId);
    replaceCalls++;
    if (!replaceStarted.isCompleted) replaceStarted.complete();
    final gate = replaceGate;
    if (gate != null) await gate.future;

    if (replaceFailuresRemaining > 0) {
      replaceFailuresRemaining--;
      throw replaceFailure!;
    }

    publishedBlocks = _copyBlocks(blocks);
    return _copyBlocks(publishedBlocks);
  }

  @override
  Future<WebsiteNavigation?> getNavigation({
    required String tenantId,
    required String navigationId,
  }) async {
    return navigationRows[navigationId];
  }

  @override
  Future<void> updateNavigation({
    required String tenantId,
    required WebsiteNavigation navigation,
  }) async {
    navigationUpdateCalls.add(navigation.id);
    if (!_didFailNavigationUpdate &&
        navigation.id == failNavigationUpdateIdOnce) {
      _didFailNavigationUpdate = true;
      throw navigationUpdateFailure!;
    }
    navigationRows[navigation.id] = navigation;
  }

  @override
  Future<void> deleteNavigation({
    required String tenantId,
    required String navigationId,
  }) async {
    navigationDeleteCalls.add(navigationId);
    navigationRows.remove(navigationId);
  }

  @override
  Future<void> upsertNavigationCreate({
    required String tenantId,
    required String persistedId,
    required WebsiteNavigation navigation,
  }) async {
    expect(tenantId, _tenantId);
    expect(navigation.id, persistedId);
    navigationUpsertCalls.update(
      persistedId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );

    if (!_didFailNavigation && persistedId == failNavigationIdOnce) {
      _didFailNavigation = true;
      throw navigationFailure!;
    }
    navigationRows[persistedId] = navigation;
  }

  @override
  Future<void> reorderNavigation({
    required String tenantId,
    required List<String> orderedIds,
  }) async {
    navigationReorderCalls.add(List<String>.from(orderedIds));
    if (!_didFailReorder &&
        navigationReorderCalls.length == failReorderCallOnce) {
      _didFailReorder = true;
      throw reorderFailure!;
    }
  }
}

List<Map<String, dynamic>> _copyBlocks(
  List<Map<String, dynamic>> blocks,
) {
  return blocks
      .map(
        (block) => block.map(
          (key, value) => MapEntry(key, _copyValue(value)),
        ),
      )
      .toList(growable: false);
}

dynamic _copyValue(dynamic value) {
  if (value is Map) {
    return value.map(
      (key, nested) => MapEntry(key.toString(), _copyValue(nested)),
    );
  }
  if (value is List) return value.map(_copyValue).toList(growable: false);
  return value;
}
