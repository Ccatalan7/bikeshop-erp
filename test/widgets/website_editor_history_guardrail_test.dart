import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_editor_capability.dart';
import 'package:vinabike_erp/modules/website/models/website_editor_mode_route_binding.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';

/// URL commands are honored only under a granted entry lease; these tests
/// exercise FSM semantics, so the harness adopts one explicitly (the
/// authority seam itself is covered by
/// website_editor_entry_authority_test.dart).
void adoptGrantedLease(WebsiteEditModeProvider provider) {
  provider.adoptEditorEntryLease(
    provider.editorEntryLeaseGeneration,
    const WebsiteEditorCapabilitySnapshot(
      identity: 'test-user',
      activeTenantId: 'test-tenant',
      storefrontTenantId: 'test-tenant',
      hasAuthority: true,
    ),
  );
}

void main() {
  const originalBlocks = <Map<String, dynamic>>[
    {
      'id': 'block-1',
      'block_type': 'about',
      'block_data': {'title': 'Original'},
      'order_index': 0,
    },
  ];

  testWidgets(
    'HP1: save rebases history so a later discard returns to the saved blocks',
    (tester) async {
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(originalBlocks, const <String, dynamic>{});

      provider.updateBlockData('block-1', 'title', 'Saved');

      const canonicalSavedBlocks = <Map<String, dynamic>>[
        {
          'id': 'block-1',
          'block_type': 'about',
          'block_data': {'title': 'Saved'},
          'order_index': 0,
        },
      ];
      provider.acknowledgeSavedBlocks(
        attemptedBlocks: provider.blocks,
        freshBlocks: canonicalSavedBlocks,
      );

      expect(provider.canUndo, isFalse);
      expect(provider.canRedo, isFalse);

      provider.updateBlockData('block-1', 'title', 'Second draft');
      provider.discardPendingChanges();

      expect(
        provider.blocks.single['block_data']['title'],
        'Saved',
      );
      expect(provider.hasUnsavedChanges, isFalse);
      expect(provider.canUndo, isFalse);
      expect(provider.canRedo, isFalse);
    },
  );

  testWidgets(
    'HP2: preview to edit establishes the loaded blocks as discard baseline',
    (tester) async {
      final provider = WebsiteEditModeProvider()
        ..enterPreviewMode(originalBlocks, const <String, dynamic>{})
        ..setMode(WebsiteEditorMode.edit);

      provider.updateBlockData('block-1', 'title', 'Draft from preview');
      provider.discardPendingChanges();

      expect(
        provider.blocks.single['block_data']['title'],
        'Original',
      );
      expect(provider.hasUnsavedChanges, isFalse);
      expect(provider.canUndo, isFalse);
      expect(provider.canRedo, isFalse);
    },
  );

  testWidgets(
    'simultaneous edit and preview URL flags enter exactly one canonical mode',
    (tester) async {
      final requestedMode = websiteEditorModeRequestFromUri(
        Uri.parse('/tienda?edit=true&preview=true'),
      );
      final provider = WebsiteEditModeProvider();
      addTearDown(provider.dispose);

      provider.openEditorDocument(
        originalBlocks,
        const <String, dynamic>{},
        mode: requestedMode,
      );

      expect(requestedMode, WebsiteEditorMode.edit);
      expect(provider.mode, WebsiteEditorMode.edit);
      expect(provider.isEditMode, isTrue);
      expect(provider.isPreviewMode, isFalse);
      expect(provider.isEditMode ^ provider.isPreviewMode, isTrue);
    },
  );

  testWidgets(
    'URI mode-request matrix is total and Edit wins deterministically',
    (tester) async {
      const cases = <(String, WebsiteEditorMode)>[
        ('/tienda', WebsiteEditorMode.public),
        ('/tienda?edit=true', WebsiteEditorMode.edit),
        ('/tienda?preview=true', WebsiteEditorMode.preview),
        ('/tienda?edit=true&preview=true', WebsiteEditorMode.edit),
        ('/tienda?preview=true&edit=true', WebsiteEditorMode.edit),
        ('/tienda?edit=false', WebsiteEditorMode.public),
        ('/tienda?preview=1', WebsiteEditorMode.public),
        ('/pagina/oferta?edit=true&q=cadenas', WebsiteEditorMode.edit),
      ];
      for (final (location, expected) in cases) {
        expect(
          websiteEditorModeRequestFromUri(Uri.parse(location)),
          expected,
          reason: location,
        );
      }
    },
  );

  testWidgets(
    'mode projection is write-through and preserves foreign query and '
    'fragment',
    (tester) async {
      final uri = Uri.parse('/productos?q=cadenas&marca=a&marca=b#frag');

      final edited = projectWebsiteEditorModeOntoUri(
        uri,
        WebsiteEditorMode.edit,
      );
      expect(edited.queryParameters['edit'], 'true');
      expect(edited.queryParameters.containsKey('preview'), isFalse);
      expect(edited.queryParameters['q'], 'cadenas');
      expect(edited.queryParametersAll['marca'], <String>['a', 'b']);
      expect(edited.fragment, 'frag');

      final previewed = projectWebsiteEditorModeOntoUri(
        Uri.parse('/productos?edit=true&q=cadenas'),
        WebsiteEditorMode.preview,
      );
      expect(previewed.queryParameters['preview'], 'true');
      expect(previewed.queryParameters.containsKey('edit'), isFalse);
      expect(previewed.queryParameters['q'], 'cadenas');

      final public = projectWebsiteEditorModeOntoUri(
        Uri.parse('/productos?edit=true&q=cadenas'),
        WebsiteEditorMode.public,
      );
      expect(public.queryParameters.containsKey('edit'), isFalse);
      expect(public.queryParameters.containsKey('preview'), isFalse);
      expect(public.queryParameters['q'], 'cadenas');

      // Round-trip: a projected URI parses back to the projected mode, and
      // an already-projected URI is recognized as stable (no write needed).
      expect(websiteEditorModeRequestFromUri(edited), WebsiteEditorMode.edit);
      expect(
        uriProjectsWebsiteEditorMode(edited, WebsiteEditorMode.edit),
        isTrue,
      );
      expect(
        uriProjectsWebsiteEditorMode(edited, WebsiteEditorMode.preview),
        isFalse,
      );

      // Stability is SEMANTIC, never raw string equality: a history entry
      // whose foreign parameters merely sit in a different order than the
      // canonical projection must not trigger a corrective navigation on
      // every browser Back visit.
      expect(
        uriProjectsWebsiteEditorMode(
          Uri.parse('/tienda?edit=true&utm=x&marca=a&marca=b'),
          WebsiteEditorMode.edit,
        ),
        isTrue,
      );
      expect(
        uriProjectsWebsiteEditorMode(
          Uri.parse('/tienda?utm=x&preview=true'),
          WebsiteEditorMode.preview,
        ),
        isTrue,
      );
      // Non-canonical flag combinations still demand a write-through.
      expect(
        uriProjectsWebsiteEditorMode(
          Uri.parse('/tienda?edit=true&preview=true'),
          WebsiteEditorMode.edit,
        ),
        isFalse,
      );
      expect(
        uriProjectsWebsiteEditorMode(
          Uri.parse('/tienda?edit=false'),
          WebsiteEditorMode.public,
        ),
        isFalse,
      );
    },
  );

  testWidgets(
    'FSM transitions are exclusive and idempotent; URL commands can enter '
    'but never exit; provider mode wins over an in-flight stale projection',
    (tester) async {
      final provider = WebsiteEditModeProvider();
      addTearDown(provider.dispose);
      adoptGrantedLease(provider);
      var notifications = 0;
      provider.addListener(() => notifications++);

      expect(provider.mode, WebsiteEditorMode.public);

      // Deep-link entry command (deferred notification, immediate state).
      provider.applyRouteModeCommand(WebsiteEditorMode.edit);
      expect(provider.mode, WebsiteEditorMode.edit);
      expect(provider.isEditMode && !provider.isPreviewMode, isTrue);
      await tester.pump();

      // Idempotent re-application of the same command notifies nobody.
      final afterEntry = notifications;
      provider.applyRouteModeCommand(WebsiteEditorMode.edit);
      await tester.pump();
      expect(notifications, afterEntry);

      // A public URL request is never an exit command.
      provider.applyRouteModeCommand(WebsiteEditorMode.public);
      expect(provider.mode, WebsiteEditorMode.edit);

      // Rapid toggles settle deterministically on the last revision without
      // any timers: state is synchronous.
      provider.setMode(WebsiteEditorMode.preview);
      provider.setMode(WebsiteEditorMode.edit);
      provider.setMode(WebsiteEditorMode.preview);
      expect(provider.mode, WebsiteEditorMode.preview);
      expect(provider.isPreviewMode && !provider.isEditMode, isTrue);

      // A stale URL command (the old projection still in flight) loses when
      // it matches the current mode, and an explicit differing URI command
      // (browser Back/forward) wins as a real mode transition.
      provider.applyRouteModeCommand(WebsiteEditorMode.preview);
      expect(provider.mode, WebsiteEditorMode.preview);
      provider.applyRouteModeCommand(WebsiteEditorMode.edit);
      expect(provider.mode, WebsiteEditorMode.edit);

      // setMode(public) delegates to the full close.
      provider.setMode(WebsiteEditorMode.public);
      expect(provider.mode, WebsiteEditorMode.public);
      expect(provider.isInEditorContext, isFalse);
      await tester.pump();
    },
  );

  testWidgets(
    'activating another page replaces only the page draft and preserves '
    'sitewide and cross-page SEO drafts',
    (tester) async {
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          originalBlocks,
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: 'page-a',
        )
        ..updateBlockData('block-1', 'title', 'Page A draft')
        ..updateSiteSetting('store_name', 'Sitewide draft')
        ..updateThemeSetting('primary_color', '#123456')
        ..updatePageSeo(
          routeKey: 'page-a',
          metaTitle: 'Draft title',
          metaDescription: 'Draft description',
        );

      const pageBBlocks = <Map<String, dynamic>>[
        {
          'id': 'block-b',
          'block_type': 'about',
          'block_data': {'title': 'Page B'},
          'order_index': 0,
        },
      ];
      provider.enterEditMode(
        pageBBlocks,
        const <String, dynamic>{},
        pageId: 'page-b',
        pageSlug: 'page-b',
      );

      expect(provider.currentPageId, 'page-b');
      expect(provider.blocks, pageBBlocks);
      expect(provider.hasPageDraftChanges, isFalse);
      expect(provider.pendingSiteSettings, {
        'store_name': 'Sitewide draft',
      });
      expect(provider.pendingThemeSettings, {
        'primary_color': '#123456',
      });
      expect(provider.pendingPageSeo.keys, {'page-a'});
      expect(provider.hasSitewideDraftChanges, isTrue);
      expect(provider.hasSeoDraftChanges, isTrue);
      expect(provider.hasUnsavedChanges, isTrue);
    },
  );

  testWidgets(
    'reactivating the same page in preview preserves its active block draft',
    (tester) async {
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          originalBlocks,
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: 'page-a',
        )
        ..updateBlockData('block-1', 'title', 'Unsaved draft');
      final revision = provider.documentSessionRevision;

      provider.enterPreviewMode(
        originalBlocks,
        const <String, dynamic>{},
        pageId: 'page-a',
        pageSlug: 'page-a',
      );

      expect(provider.isPreviewMode, isTrue);
      expect(provider.blocks.single['block_data']['title'], 'Unsaved draft');
      expect(provider.hasPageDraftChanges, isTrue);
      expect(provider.documentSessionRevision, revision);
    },
  );

  testWidgets('document snapshots cannot mutate the provider draft',
      (tester) async {
    final provider = WebsiteEditModeProvider()
      ..enterEditMode(
        originalBlocks,
        const <String, dynamic>{
          'theme': {'name': 'base'},
        },
        pageId: 'page-a',
        pageSlug: 'page-a',
      )
      ..updateSiteSetting('store_name', 'Draft');

    final snapshot = provider.document;
    expect(
      () => snapshot.blocks.single['block_data']['title'] = 'Mutation',
      throwsUnsupportedError,
    );
    expect(
      () => provider.blocks.single['block_data']['title'] = 'Mutation',
      throwsUnsupportedError,
    );
    expect(
      () => provider.settings['theme']['name'] = 'Mutation',
      throwsUnsupportedError,
    );
    expect(
      () => provider.pendingSiteSettings['store_name'] = 'Mutation',
      throwsUnsupportedError,
    );

    expect(provider.blocks.single['block_data']['title'], 'Original');
    expect(provider.settings['theme']['name'], 'base');
    expect(provider.pendingSiteSettings['store_name'], 'Draft');
    expect(snapshot.pageId, 'page-a');
    expect(snapshot.sessionRevision, provider.documentSessionRevision);
  });

  test('same empty document activation is idempotent and identity is ID-first',
      () {
    final provider = WebsiteEditModeProvider()
      ..enterEditMode(
        const <Map<String, dynamic>>[],
        const <String, dynamic>{},
        pageId: 'page-a',
        pageSlug: 'reused-slug',
      );
    addTearDown(provider.dispose);
    final revision = provider.documentSessionRevision;
    var notifications = 0;
    provider.addListener(() => notifications++);

    provider.enterEditMode(
      const <Map<String, dynamic>>[],
      const <String, dynamic>{},
      pageId: 'page-a',
      pageSlug: 'reused-slug',
    );

    expect(notifications, 0);
    expect(provider.documentSessionRevision, revision);
    expect(
      provider.ownsPageDocument(
        pageId: 'page-a',
        pageSlug: 'reused-slug',
      ),
      isTrue,
    );
    expect(
      provider.ownsPageDocument(
        pageId: 'page-b',
        pageSlug: 'reused-slug',
      ),
      isFalse,
    );
  });

  test('saved baseline survives more changes than the undo window', () {
    final provider = WebsiteEditModeProvider()
      ..enterEditMode(originalBlocks, const <String, dynamic>{});
    addTearDown(provider.dispose);

    for (var index = 0; index < 70; index++) {
      provider.updateBlockData('block-1', 'title', 'Draft $index');
    }
    provider.discardPendingChanges();

    expect(provider.blocks.single['block_data']['title'], 'Original');
    expect(provider.hasPageDraftChanges, isFalse);
  });

  test('structural block commands each create an undo snapshot', () {
    final provider = WebsiteEditModeProvider()
      ..enterEditMode(
        const [
          {
            'id': 'first',
            'block_type': 'divider',
            'block_data': <String, dynamic>{},
            'order_index': 0,
          },
          {
            'id': 'second',
            'block_type': 'divider',
            'block_data': <String, dynamic>{},
            'order_index': 1,
          },
        ],
        const <String, dynamic>{},
      );
    addTearDown(provider.dispose);

    provider.moveBlockDown('first');
    expect(provider.blocks.first['id'], 'second');
    provider.undo();
    expect(provider.blocks.first['id'], 'first');

    provider.deleteBlock('second');
    expect(provider.blocks.length, 1);
    provider.undo();
    expect(provider.blocks.length, 2);

    provider.toggleBlockVisibility('first');
    expect(provider.blocks.first['is_visible'], isFalse);
    provider.undo();
    expect(provider.blocks.first['is_visible'], isNot(false));

    provider.duplicateBlock('first');
    expect(provider.blocks.length, 3);
    provider.undo();
    expect(provider.blocks.length, 2);

    provider.addBlock('divider');
    expect(provider.blocks.length, 3);
    provider.undo();
    expect(provider.blocks.length, 2);
  });
}
