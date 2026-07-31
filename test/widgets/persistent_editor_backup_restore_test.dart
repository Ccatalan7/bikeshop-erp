
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/website/models/website_editor_capability.dart';
import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/public_store/widgets/persistent_editor_shell.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

WebsiteEditorCapabilitySnapshot _cap(
  String identity,
  String tenant, {
  int epoch = 0,
}) =>
    WebsiteEditorCapabilitySnapshot(
      identity: identity,
      activeTenantId: tenant,
      storefrontTenantId: tenant,
      hasAuthority: true,
      authorityEpoch: epoch,
    );

/// Gated fake: the test controls when the public refresh and the editor RPC
/// complete, so an identity switch can land inside either await window.
class _RestoreWebsiteService extends WebsiteService {
  _RestoreWebsiteService()
      : super(
          supabase: SupabaseClient(
            'https://example.supabase.co',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
            httpClient: MockClient(
              (request) async => http.Response(jsonEncode([]), 200,
                  headers: {'content-type': 'application/json'}),
            ),
          ),
          tenantService: TenantService.testing(
            currentUserId: () => null,
            profileLookup: (_) async => const [],
          ),
          httpClient: MockClient(
            (request) async => throw StateError('no edge calls'),
          ),
        );

  final Completer<void> refreshGate = Completer<void>();
  final Completer<CachedPageSnapshot?> editorGate =
      Completer<CachedPageSnapshot?>();
  int refreshCalls = 0;
  int editorLoadCalls = 0;

  @override
  Future<void> loadPublicStoreDataUnified(
    String tenantId, {
    bool forceRefresh = false,
    Duration? maxWait,
  }) async {
    refreshCalls++;
    await refreshGate.future;
  }

  @override
  Future<CachedPageSnapshot?> loadEditorPageWithBlocks(
    String slug, {
    required String tenantId,
  }) {
    editorLoadCalls++;
    return editorGate.future;
  }
}

WebsiteEditModeProvider _sessionA() {
  final provider = WebsiteEditModeProvider();
  provider.adoptEditorEntryLease(0, _cap('user-a', 'tenant-a'));
  provider.applyRouteModeCommand(WebsiteEditorMode.edit);
  provider.activatePageDocument(
    const [
      {
        'id': 'block-1',
        'block_type': 'about',
        'block_data': {'title': 'Original A'},
        'order_index': 0,
        'is_visible': true,
      },
    ],
    const <String, dynamic>{},
    pageId: 'page-a',
    pageSlug: 'page-a',
  );
  return provider;
}

void _switchToB(WebsiteEditModeProvider provider) {
  provider.revokeEditorEntryLease();
  provider.adoptEditorEntryLease(
    provider.editorEntryLeaseGeneration,
    _cap('user-b', 'tenant-a', epoch: 1),
  );
  provider.applyRouteModeCommand(WebsiteEditorMode.edit);
  provider.activatePageDocument(
    const [
      {
        'id': 'block-b',
        'block_type': 'about',
        'block_data': {'title': 'Documento B'},
        'order_index': 0,
        'is_visible': true,
      },
    ],
    const <String, dynamic>{},
    pageId: 'page-b',
    pageSlug: 'page-b',
  );
  provider.updateBlockData('block-b', 'title', 'Draft B');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'an identity switch DURING the public refresh supersedes the restore: '
    'no RPC, zero reopen, the new session stays intact',
    (tester) async {
      final provider = _sessionA();
      addTearDown(provider.dispose);
      final service = _RestoreWebsiteService();
      addTearDown(service.dispose);

      final pending = PersistentEditorShell.restoreEditorDocumentAfterBackup(
        editProvider: provider,
        websiteService: service,
        resolveTenantId: () async => 'tenant-a',
      );
      await tester.pump();
      expect(service.refreshCalls, 1);

      _switchToB(provider);
      service.refreshGate.complete();

      await expectLater(
        pending,
        throwsA(isA<WebsiteEditorReadSupersededException>()),
      );
      expect(service.editorLoadCalls, 0,
          reason: 'The stale restore never reaches the editor RPC.');
      expect(provider.currentPageId, 'page-b');
      expect(
        provider.blocks.single['block_data']['title'],
        'Draft B',
        reason: 'B\'s session and draft are untouched.',
      );
    },
  );

  testWidgets(
    'a LATE RPC success after an identity switch supersedes the restore: '
    'zero reopen, the new session stays intact',
    (tester) async {
      final provider = _sessionA();
      addTearDown(provider.dispose);
      final service = _RestoreWebsiteService();
      addTearDown(service.dispose);
      service.refreshGate.complete();

      final pending = PersistentEditorShell.restoreEditorDocumentAfterBackup(
        editProvider: provider,
        websiteService: service,
        resolveTenantId: () async => 'tenant-a',
      );
      await tester.pump();
      expect(service.editorLoadCalls, 1);

      _switchToB(provider);
      service.editorGate.complete(
        CachedPageSnapshot(
          page: WebsitePage(
            id: 'page-a',
            tenantId: 'tenant-a',
            slug: 'page-a',
            title: 'Página A',
            isPublished: false,
            createdAt: DateTime.utc(2026, 7, 30),
            updatedAt: DateTime.utc(2026, 7, 30),
          ),
          blocks: const [
            {
              'id': 'stale-a',
              'block_type': 'about',
              'block_data': {'title': 'Restaurada A'},
              'order_index': 0,
              'is_visible': true,
            },
          ],
        ),
      );

      await expectLater(
        pending,
        throwsA(isA<WebsiteEditorReadSupersededException>()),
      );
      expect(provider.currentPageId, 'page-b');
      expect(
        provider.blocks.single['block_data']['title'],
        'Draft B',
        reason: 'The stale snapshot never reopens over B.',
      );
    },
  );
}
