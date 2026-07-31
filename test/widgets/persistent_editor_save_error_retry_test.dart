import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:vinabike_erp/modules/website/models/website_editor_capability.dart';
import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_save_coordinator.dart';
import 'package:vinabike_erp/public_store/widgets/persistent_editor_shell.dart';

const _tenantId = 'tenant-a';
const _pageId = 'page-a';
const _pageSlug = 'landing';
const _draftNavigationId = 'draft_11111111-1111-4111-8111-111111111111';
const _persistedNavigationId = '11111111-1111-4111-8111-111111111111';

void main() {
  testWidgets(
    'failed Guardar shows an error, keeps the draft, and retries without '
    'duplicating navigation',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final provider = WebsiteEditModeProvider();
      addTearDown(provider.dispose);
      // The save gate requires a granted session/document owner.
      provider.adoptEditorEntryLease(
        0,
        const WebsiteEditorCapabilitySnapshot(
          identity: 'retry-user',
          activeTenantId: _tenantId,
          storefrontTenantId: _tenantId,
          hasAuthority: true,
        ),
      );
      const publishedBlocks = [
        {
          'id': 'text-1',
          'block_type': 'text',
          'block_data': {'text': 'Publicado'},
          'order_index': 0,
          'is_visible': true,
        },
      ];
      provider.enterEditMode(
        publishedBlocks,
        const {},
        pageId: _pageId,
        pageSlug: _pageSlug,
      );
      provider.updateBlockData('text-1', 'text', 'Borrador íntegro');
      provider.createFooterNavDraft(
        WebsiteNavigation(
          id: _draftNavigationId,
          tenantId: _tenantId,
          menuLocation: MenuLocation.footer,
          label: 'Enlace nuevo',
          linkType: NavLinkType.page,
          linkValue: '/pagina/nueva',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
      final attemptedDraft = _copyBlocks(provider.blocks);
      final gateway = _RetryGateway(publishedBlocks);

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: provider,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(0.45),
              ),
              child: child!,
            ),
            home: Scaffold(
              body: PersistentEditorShell(
                saveCoordinator: WebsiteSaveCoordinator(gateway),
                tenantIdResolver: () async => _tenantId,
                child: const ColoredBox(color: Colors.white),
              ),
            ),
          ),
        ),
      );
      await _pumpUntilFound(tester, find.text('Guardar'));

      await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text(
          'Error al guardar: Bad state: replace_page_blocks falló',
        ),
        findsOneWidget,
      );
      expect(gateway.replaceCalls, 1);
      expect(gateway.publishedBlocks, equals(publishedBlocks));
      expect(gateway.navigationUpserts, isEmpty);
      expect(provider.blocks, equals(attemptedDraft));
      expect(
        provider.pendingFooterNavCreates.keys,
        contains(_draftNavigationId),
      );
      expect(provider.hasUnsavedChanges, isTrue);
      expect(provider.isEditMode, isTrue);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Guardar'));
      await tester.pump();
      await _pumpUntil(tester, () => provider.isPreviewMode);
      expect(gateway.replaceCalls, 2);
      expect(gateway.publishedBlocks, equals(attemptedDraft));
      expect(gateway.navigationRows.keys, {_persistedNavigationId});
      expect(gateway.navigationUpserts, {
        _persistedNavigationId: 1,
      });
      expect(provider.hasUnsavedChanges, isFalse);
      expect(provider.isPreviewMode, isTrue);
      expect(provider.isEditMode, isFalse);
    },
  );
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder,
) async {
  for (var attempt = 0; attempt < 30 && finder.evaluate().isEmpty; attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsOneWidget);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition,
) async {
  for (var attempt = 0; attempt < 30 && !condition(); attempt++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(condition(), isTrue);
}

class _RetryGateway implements WebsiteSaveGateway {
  @override
  void Function()? writeGuard;

  @override
  void recordEditorAuthorityRejection(String tenantId) {}

  @override
  int identityEpoch = 0;

  @override
  WebsiteEditorCapabilitySnapshot? currentCapability(String tenantId) =>
      const WebsiteEditorCapabilitySnapshot(
        identity: 'retry-user',
        activeTenantId: _tenantId,
        storefrontTenantId: _tenantId,
        hasAuthority: true,
      );

  _RetryGateway(List<Map<String, dynamic>> publishedBlocks)
      : publishedBlocks = _copyBlocks(publishedBlocks);

  List<Map<String, dynamic>> publishedBlocks;
  final Map<String, WebsiteNavigation> navigationRows = {};
  final Map<String, int> navigationUpserts = {};
  int replaceCalls = 0;

  @override
  bool isTenantProjectionActive(String tenantId) => tenantId == _tenantId;

  @override
  Future<void> saveSettings(
    String tenantId,
    Map<String, String> settings,
  ) async {}

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
    if (replaceCalls == 1) {
      throw StateError('replace_page_blocks falló');
    }
    publishedBlocks = _copyBlocks(blocks);
    return _copyBlocks(publishedBlocks);
  }

  @override
  Future<WebsiteNavigation?> getNavigation({
    required String tenantId,
    required String navigationId,
  }) async {
    expect(tenantId, _tenantId);
    return navigationRows[navigationId];
  }

  @override
  Future<void> updateNavigation({
    required String tenantId,
    required WebsiteNavigation navigation,
  }) async {
    navigationRows[navigation.id] = navigation;
  }

  @override
  Future<void> deleteNavigation({
    required String tenantId,
    required String navigationId,
  }) async {
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
    navigationUpserts.update(
      persistedId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    navigationRows[persistedId] = navigation;
  }

  @override
  Future<void> reorderNavigation({
    required String tenantId,
    required List<String> orderedIds,
  }) async {}
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
