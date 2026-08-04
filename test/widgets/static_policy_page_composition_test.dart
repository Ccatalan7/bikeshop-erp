import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vinabike_erp/modules/website/models/website_editor_capability.dart';
import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/modules/website/theme/website_resolved_theme.dart';
import 'package:vinabike_erp/modules/website/theme/website_theme_builder.dart';
import 'package:vinabike_erp/public_store/pages/static_policy_page.dart';
import 'package:vinabike_erp/public_store/providers/public_store_tenant_provider.dart';
import 'package:vinabike_erp/shared/models/tenant.dart';
import 'package:vinabike_erp/shared/services/tenant_detection_service.dart';
import 'package:vinabike_erp/shared/utils/seo_helper.dart';

const _tenantId = 'tenant-static-policy-test';
const _slug = 'terminos';
const _fallbackTitle = 'Información legal';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://127.0.0.1:54321',
      anonKey: 'test-anon-key',
    );
  });

  testWidgets(
    'public origin uses the policy shell and adapted canonical composition',
    (tester) async {
      final snapshot = _policySnapshot(isPublished: true);
      final result = PageSnapshotLoadResult.origin(snapshot);

      await _pumpPolicy(
        tester,
        mode: _PolicyMode.public,
        publicResult: result,
        editorSnapshot: snapshot,
      );

      expect(
        find.byKey(const ValueKey<String>('static-policy-public-view')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>(
            'static-policy-adapted-content-visible-policy',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Condiciones verificadas'), findsOneWidget);
      expect(find.text('Texto verificable del documento.'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('static-policy-freshness-notice')),
        findsNothing,
      );
      expect(
        StaticPolicyPublicationProjection.fromLoadResult(result).shouldIndex,
        isTrue,
      );
    },
  );

  testWidgets('Policy shell and unavailable state consume one resolved theme',
      (tester) async {
    final snapshot = _policySnapshot(isPublished: true);
    final resolved = WebsiteResolvedTheme.fallback.copyWith(
      backgroundColor: const Color(0xFF142119),
      textColor: const Color(0xFFF2F3EF),
    );
    final projected = WebsiteThemeBuilder.build(
      base: ThemeData.light(useMaterial3: true),
      resolved: resolved,
    );

    await _pumpPolicy(
      tester,
      mode: _PolicyMode.public,
      publicResult: PageSnapshotLoadResult.origin(snapshot),
      editorSnapshot: snapshot,
      resolvedTheme: resolved,
    );

    expect(
      tester
          .widget<Container>(
            find.byKey(const ValueKey<String>('static-policy-public-view')),
          )
          .color,
      resolved.backgroundColor,
    );
    expect(
      tester.widget<Text>(find.text('Condiciones verificadas')).style?.color,
      resolved.textColor,
    );
    expect(
      tester
          .widget<Text>(find.text('Resumen configurado por el editor.'))
          .style
          ?.color,
      projected.colorScheme.onSurfaceVariant,
    );

    await _pumpPolicy(
      tester,
      mode: _PolicyMode.public,
      publicResult: const PageSnapshotLoadResult.originMissing(),
      editorSnapshot: null,
      resolvedTheme: resolved,
    );

    expect(
      tester
          .widget<Container>(
            find.byKey(
              const ValueKey<String>('static-policy-unavailable-view'),
            ),
          )
          .color,
      resolved.backgroundColor,
    );
    expect(
      tester.widget<Text>(find.text(_fallbackTitle)).style?.color,
      resolved.textColor,
    );
  });

  testWidgets(
    'stale public snapshot stays visible with warning and remains noindex',
    (tester) async {
      final snapshot = _policySnapshot(isPublished: true);
      final result = PageSnapshotLoadResult.staleFallback(snapshot);

      await _pumpPolicy(
        tester,
        mode: _PolicyMode.public,
        publicResult: result,
        editorSnapshot: snapshot,
        peekSnapshot: snapshot,
      );

      expect(
        find.byKey(const ValueKey<String>('static-policy-public-view')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('static-policy-freshness-notice')),
        findsOneWidget,
      );
      expect(find.text('Texto verificable del documento.'), findsOneWidget);
      expect(
        StaticPolicyPublicationProjection.fromLoadResult(result).shouldIndex,
        isFalse,
      );
    },
  );

  for (final unavailableCase in <({
    String name,
    PageSnapshotLoadResult result,
  })>[
    (
      name: 'missing owner',
      result: const PageSnapshotLoadResult.originMissing(),
    ),
    (
      name: 'unpublished owner',
      result: PageSnapshotLoadResult.origin(
        _policySnapshot(isPublished: false),
      ),
    ),
  ]) {
    testWidgets(
      '${unavailableCase.name} shows only the neutral fallback and noindex',
      (tester) async {
        await _pumpPolicy(
          tester,
          mode: _PolicyMode.public,
          publicResult: unavailableCase.result,
          editorSnapshot: unavailableCase.result.snapshot,
        );

        expect(
          find.byKey(const ValueKey<String>('static-policy-unavailable-view')),
          findsOneWidget,
        );
        expect(find.text(_fallbackTitle), findsOneWidget);
        expect(
          find.text(
            'Esta página no tiene contenido público disponible en este '
            'momento.',
          ),
          findsOneWidget,
        );
        expect(find.text('Texto verificable del documento.'), findsNothing);
        expect(
          find.byKey(const ValueKey<String>('static-policy-public-view')),
          findsNothing,
        );
        expect(
          StaticPolicyPublicationProjection.fromLoadResult(
            unavailableCase.result,
          ).shouldIndex,
          isFalse,
        );
      },
    );
  }

  testWidgets(
    'Preview renders the draft through policy shell and contentAdapter',
    (tester) async {
      final draft = _policySnapshot(isPublished: false);

      await _pumpPolicy(
        tester,
        mode: _PolicyMode.preview,
        publicResult: const PageSnapshotLoadResult.originMissing(),
        editorSnapshot: draft,
      );

      expect(
        find.byKey(const ValueKey<String>('static-policy-public-view')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>(
            'static-policy-adapted-content-visible-policy',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Texto verificable del documento.'), findsOneWidget);
      expect(find.text('Borrador oculto.'), findsNothing,
          reason: 'Preview projects public visibility: hidden drafts render '
              'only in Edit.');
      expect(
        find.byKey(const ValueKey<String>('static-policy-freshness-notice')),
        findsNothing,
      );
      expect(
        projectStorefrontSeoRoute(
          Uri.parse('/terminos?preview=true'),
          isErpMounted: false,
          ownerIsPublished: false,
          hasEligibleContent: false,
        ).robots,
        'noindex,follow',
      );
    },
  );

  testWidgets(
    'Edit renders the SAME public shell and adapted content, adding the '
    'hidden draft block and editor chrome on top',
    (tester) async {
      final draft = _policySnapshot(isPublished: false);

      await _pumpPolicy(
        tester,
        mode: _PolicyMode.edit,
        publicResult: const PageSnapshotLoadResult.originMissing(),
        editorSnapshot: draft,
      );

      // Edit -> Preview -> Public parity: the trust shell and the adapted
      // canonical content are the SAME tree in all three modes.
      expect(
        find.byKey(const ValueKey<String>('static-policy-public-view')),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>(
            'static-policy-adapted-content-visible-policy',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Texto verificable del documento.'), findsOneWidget);

      // Edit-only additions: the hidden draft block stays editable and the
      // canvas chrome wraps the SAME adapted content — chrome, never a
      // second content tree.
      expect(find.text('Borrador oculto.'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>('page-composition-block-visible-policy'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(
          const ValueKey<String>('page-composition-block-hidden-policy'),
        ),
        findsOneWidget,
      );

      expect(
        projectStorefrontSeoRoute(
          Uri.parse('/terminos?edit=true'),
          isErpMounted: false,
          ownerIsPublished: false,
          hasEligibleContent: false,
        ).robots,
        'noindex,follow',
      );
    },
  );

  testWidgets(
    'a persisted style block keeps identical adapted geometry across '
    'Public, Preview and Edit at the same viewport',
    (tester) async {
      const adaptedKey =
          ValueKey<String>('static-policy-adapted-content-styled-policy');

      Future<Rect> rectFor(_PolicyMode mode) async {
        final snapshot = _policySnapshot(
          isPublished: mode == _PolicyMode.public,
          includeStyledBlock: true,
        );
        await _pumpPolicy(
          tester,
          mode: mode,
          publicResult: mode == _PolicyMode.public
              ? PageSnapshotLoadResult.origin(snapshot)
              : const PageSnapshotLoadResult.originMissing(),
          editorSnapshot: snapshot,
        );
        expect(find.byKey(adaptedKey), findsOneWidget);
        return tester.getRect(find.byKey(adaptedKey));
      }

      final publicRect = await rectFor(_PolicyMode.public);
      final previewRect = await rectFor(_PolicyMode.preview);
      final editRect = await rectFor(_PolicyMode.edit);

      expect(previewRect, publicRect,
          reason: 'Preview must not move or resize the adapted content.');
      // The hidden draft block sits BELOW this one, so Edit shares the full
      // Rect too: any offset or size drift would mean chrome or a second
      // style decoration changed the adapted geometry.
      expect(editRect, publicRect,
          reason: 'Edit chrome may wrap the adapted content but must not '
              'change its geometry (no double style decoration).');
    },
  );

  testWidgets(
    'an empty metaDescription with a hidden draft never alters the public '
    'shell summary in any mode',
    (tester) async {
      Future<void> pumpMode(_PolicyMode mode) async {
        final snapshot = _policySnapshot(
          isPublished: mode == _PolicyMode.public,
          metaDescription: '',
        );
        await _pumpPolicy(
          tester,
          mode: mode,
          publicResult: mode == _PolicyMode.public
              ? PageSnapshotLoadResult.origin(snapshot)
              : const PageSnapshotLoadResult.originMissing(),
          editorSnapshot: snapshot,
        );
      }

      // With no configured metaDescription the shell summary derives from
      // PUBLICLY visible content only: the visible text appears exactly
      // twice (summary + body) in every mode.
      await pumpMode(_PolicyMode.public);
      expect(find.text('Texto verificable del documento.'), findsNWidgets(2));
      expect(find.text('Borrador oculto.'), findsNothing);

      await pumpMode(_PolicyMode.preview);
      expect(find.text('Texto verificable del documento.'), findsNWidgets(2));
      expect(find.text('Borrador oculto.'), findsNothing);

      await pumpMode(_PolicyMode.edit);
      expect(find.text('Texto verificable del documento.'), findsNWidgets(2),
          reason: 'The hidden draft must not leak into the shell summary.');
      expect(find.text('Borrador oculto.'), findsOneWidget,
          reason: 'Exactly the canvas draft block — never the summary.');
    },
  );

  testWidgets(
    'a server authority rejection during the editor load revokes the lease '
    'and renders the public document fail-closed',
    (tester) async {
      final published = _policySnapshot(isPublished: true);

      final editMode = await _pumpPolicy(
        tester,
        mode: _PolicyMode.edit,
        publicResult: PageSnapshotLoadResult.origin(published),
        editorSnapshot: published,
        editorLoadError: const WebsiteEditorAuthorityException(
          'El servidor rechazó la autorización del editor.',
        ),
      );

      expect(editMode.mode, WebsiteEditorMode.public,
          reason: 'Authority loss closes the session fail-closed.');
      expect(editMode.editorEntryLeaseGranted, isFalse);
      expect(
        find.byKey(const ValueKey<String>('static-policy-public-view')),
        findsOneWidget,
      );
      expect(find.text('Texto verificable del documento.'), findsOneWidget);
      expect(find.text('Borrador oculto.'), findsNothing,
          reason: 'No editor-audience content may survive the revocation.');
    },
  );

  for (final transientCase in <({String name, Object error})>[
    (name: 'generic network failure', error: Exception('network down')),
    (
      // AuthException SUBTYPE meaning the auth endpoint was unreachable —
      // the adversarial case that must never be treated as authority loss.
      name: 'retryable auth fetch failure',
      error: AuthRetryableFetchException(message: 'fetch failed'),
    ),
  ]) {
    testWidgets(
      'a transient editor-load failure (${transientCase.name}) keeps the '
      'lease, the session and the document (no draft loss)',
      (tester) async {
        final draft = _policySnapshot(isPublished: false);

        final editMode = await _pumpPolicy(
          tester,
          mode: _PolicyMode.edit,
          publicResult: const PageSnapshotLoadResult.originMissing(),
          editorSnapshot: draft,
          editorLoadError: transientCase.error,
          settle: false,
        );

        expect(editMode.mode, WebsiteEditorMode.edit,
            reason: 'Transient failures must never revoke the session.');
        expect(editMode.editorEntryLeaseGranted, isTrue);
        expect(editMode.blocks, isNotEmpty,
            reason: 'The editing document survives the transient failure.');
      },
    );
  }

  testWidgets(
    'a SUPERSEDED editor read is discarded silently: no error surface, '
    'session, lease and document intact',
    (tester) async {
      final draft = _policySnapshot(isPublished: false);

      final editMode = await _pumpPolicy(
        tester,
        mode: _PolicyMode.edit,
        publicResult: const PageSnapshotLoadResult.originMissing(),
        editorSnapshot: draft,
        editorLoadError: const WebsiteEditorReadSupersededException(
          'lectura obsoleta de una identidad anterior',
        ),
        settle: false,
      );

      expect(editMode.mode, WebsiteEditorMode.edit,
          reason: 'An obsolete completion never demotes the session.');
      expect(editMode.editorEntryLeaseGranted, isTrue);
      expect(editMode.blocks, isNotEmpty);
      expect(find.textContaining('Error'), findsNothing,
          reason: 'Silent discard: nothing painted.');
    },
  );

  testWidgets(
    'EPOCH MATRIX (policy): the same fingerprint at a NEW authorityEpoch '
    'invalidates the retained editor content — the old snapshot is never '
    'reused under the new lease',
    (tester) async {
      final draft = _policySnapshot(isPublished: false);
      final editMode = await _pumpPolicy(
        tester,
        mode: _PolicyMode.edit,
        publicResult: const PageSnapshotLoadResult.originMissing(),
        editorSnapshot: draft,
      );
      expect(find.text('Borrador oculto.'), findsOneWidget,
          reason: 'Epoch-0 editor content is bound.');

      // Coalesced identity churn reproduces the fingerprint at epoch 1: the
      // provider takeover clears the session and the page's audience guard
      // must refuse to reuse the epoch-0 snapshot.
      editMode.adoptEditorEntryLease(
        editMode.editorEntryLeaseGeneration,
        const WebsiteEditorCapabilitySnapshot(
          identity: 'user-policy',
          activeTenantId: 'tenant-static-policy-test',
          storefrontTenantId: 'tenant-static-policy-test',
          hasAuthority: true,
          authorityEpoch: 1,
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      expect(editMode.blocks, isEmpty,
          reason: 'The takeover discarded the epoch-0 document.');
      expect(find.text('Borrador oculto.'), findsNothing,
          reason: 'Epoch-0 editor content is never reused under epoch 1.');
    },
  );
}

enum _PolicyMode {
  public,
  preview,
  edit,
}

Future<WebsiteEditModeProvider> _pumpPolicy(
  WidgetTester tester, {
  required _PolicyMode mode,
  required PageSnapshotLoadResult publicResult,
  required CachedPageSnapshot? editorSnapshot,
  CachedPageSnapshot? peekSnapshot,
  Object? editorLoadError,
  WebsiteResolvedTheme? resolvedTheme,
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final website = _StaticPolicyWebsiteService(
    publicResult: publicResult,
    editorSnapshot: editorSnapshot,
    peekSnapshot: peekSnapshot,
    editorLoadError: editorLoadError,
  );
  final editMode = WebsiteEditModeProvider();
  final tenant = PublicStoreTenantProvider(TenantDetectionService())
    ..setTenant(
      Tenant(
        id: _tenantId,
        shopName: 'Tienda de prueba',
        subdomain: 'prueba',
        createdAt: DateTime.utc(2026, 7, 29),
        updatedAt: DateTime.utc(2026, 7, 29),
      ),
    );
  if (editorSnapshot != null && mode != _PolicyMode.public) {
    // Editor loads validate the entry lease fingerprint; these tests
    // exercise composition parity, so the harness adopts a granted lease
    // explicitly (the authority seam is covered by
    // website_editor_entry_authority_test.dart).
    editMode.adoptEditorEntryLease(
      editMode.editorEntryLeaseGeneration,
      const WebsiteEditorCapabilitySnapshot(
        identity: 'user-policy',
        activeTenantId: 'tenant-static-policy-test',
        storefrontTenantId: 'tenant-static-policy-test',
        hasAuthority: true,
      ),
    );
    switch (mode) {
      case _PolicyMode.public:
        break;
      case _PolicyMode.preview:
        editMode.enterPreviewMode(
          editorSnapshot.blocks,
          const <String, dynamic>{},
          pageId: editorSnapshot.page.id,
          pageSlug: _slug,
        );
        break;
      case _PolicyMode.edit:
        editMode.enterEditMode(
          editorSnapshot.blocks,
          const <String, dynamic>{},
          pageId: editorSnapshot.page.id,
          pageSlug: _slug,
        );
        break;
    }
  }

  final query = switch (mode) {
    _PolicyMode.public => '',
    _PolicyMode.preview => '?preview=true',
    _PolicyMode.edit => '?edit=true',
  };
  final router = GoRouter(
    initialLocation: '/terminos$query',
    routes: [
      GoRoute(
        path: '/terminos',
        builder: (context, state) => MultiProvider(
          providers: [
            ChangeNotifierProvider<WebsiteService>.value(value: website),
            ChangeNotifierProvider<WebsiteEditModeProvider>.value(
              value: editMode,
            ),
            ChangeNotifierProvider<PublicStoreTenantProvider>.value(
              value: tenant,
            ),
          ],
          child: const Scaffold(
            body: StaticPolicyPage(
              slug: _slug,
              fallbackTitle: _fallbackTitle,
            ),
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  addTearDown(website.dispose);
  addTearDown(editMode.dispose);
  addTearDown(tenant.dispose);

  await tester.pumpWidget(
    MaterialApp.router(
      theme: resolvedTheme == null
          ? null
          : WebsiteThemeBuilder.build(
              base: ThemeData.light(useMaterial3: true),
              resolved: resolvedTheme,
            ),
      routerConfig: router,
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // Error/retry states keep an indeterminate animation alive; bounded
    // pumps let the load pipeline finish without waiting for quiescence.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }
  expect(tester.takeException(), isNull);
  return editMode;
}

CachedPageSnapshot _policySnapshot({
  required bool isPublished,
  String metaDescription = 'Resumen configurado por el editor.',
  bool includeStyledBlock = false,
}) {
  final timestamp = DateTime.utc(2026, 7, 29);
  return CachedPageSnapshot(
    page: WebsitePage(
      id: 'policy-page',
      tenantId: _tenantId,
      slug: _slug,
      title: 'Condiciones verificadas',
      metaDescription: metaDescription,
      isPublished: isPublished,
      createdAt: timestamp,
      updatedAt: timestamp,
    ),
    blocks: [
      {
        'id': 'visible-policy',
        'tenant_id': _tenantId,
        'page_id': 'policy-page',
        'block_type': 'text',
        'block_data': {
          'text': 'Texto verificable del documento.',
          'content': 'Texto verificable del documento.',
          'spacingAfter': 12,
        },
        'order_index': 0,
        'is_visible': true,
      },
      if (includeStyledBlock)
        {
          'id': 'styled-policy',
          'tenant_id': _tenantId,
          'page_id': 'policy-page',
          'block_type': 'text',
          'block_data': {
            'text': 'Cláusula con estilo persistido.',
            'content': 'Cláusula con estilo persistido.',
            'style': {
              'paddingTop': 24,
              'paddingBottom': 16,
              'paddingLeft': 12,
              'paddingRight': 12,
              'backgroundColor': '#EEF2FF',
            },
          },
          'order_index': 1,
          'is_visible': true,
        },
      {
        'id': 'hidden-policy',
        'tenant_id': _tenantId,
        'page_id': 'policy-page',
        'block_type': 'text',
        'block_data': {
          'text': 'Borrador oculto.',
          'content': 'Borrador oculto.',
        },
        'order_index': 2,
        'is_visible': false,
      },
    ],
  );
}

class _StaticPolicyWebsiteService extends WebsiteService {
  _StaticPolicyWebsiteService({
    required this.publicResult,
    required this.editorSnapshot,
    required this.peekSnapshot,
    this.editorLoadError,
  }) : super(supabase: Supabase.instance.client);

  final PageSnapshotLoadResult publicResult;
  final CachedPageSnapshot? editorSnapshot;
  final CachedPageSnapshot? peekSnapshot;

  /// When set, the editor load throws it (authority loss or transient).
  final Object? editorLoadError;

  @override
  CachedPageSnapshot? peekPageWithBlocks(
    String slug, {
    required String tenantId,
  }) {
    if (slug == _slug && tenantId == _tenantId) return peekSnapshot;
    return null;
  }

  @override
  Future<PageSnapshotLoadResult> loadPageWithBlocksResult(
    String slug, {
    required String tenantId,
  }) async {
    if (slug == _slug && tenantId == _tenantId) return publicResult;
    return const PageSnapshotLoadResult.originMissing();
  }

  @override
  Future<CachedPageSnapshot?> loadEditorPageWithBlocks(
    String slug, {
    required String tenantId,
  }) async {
    final error = editorLoadError;
    if (error != null) throw error;
    if (slug == _slug && tenantId == _tenantId) return editorSnapshot;
    return null;
  }
}
