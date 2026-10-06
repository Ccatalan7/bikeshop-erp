import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/models/website_editor_capability.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_document_binding.dart';

/// URL commands are honored only under a granted entry lease; these tests
/// exercise the document binding, so the harness adopts one explicitly (the
/// authority seam is covered by website_editor_entry_authority_test.dart).
WebsiteEditModeProvider providerWithGrantedLease() {
  final provider = WebsiteEditModeProvider();
  provider.adoptEditorEntryLease(
    provider.editorEntryLeaseGeneration,
    const WebsiteEditorCapabilitySnapshot(
      identity: 'test-user',
      activeTenantId: 'test-tenant',
      storefrontTenantId: 'test-tenant',
      hasAuthority: true,
    ),
  );
  return provider;
}

/// The shared Home/Dynamic/Policy document binding: idempotent, provider-mode
/// driven, and inert for offstage kept-alive pages.
final Object _defaultPublisher = Object();

void main() {
  const homeBlocks = <Map<String, dynamic>>[
    {
      'id': 'home-1',
      'block_type': 'about',
      'block_data': {'title': 'Home'},
      'order_index': 0,
    },
  ];
  const pageBlocks = <Map<String, dynamic>>[
    {
      'id': 'page-1',
      'block_type': 'about',
      'block_data': {'title': 'Oferta'},
      'order_index': 0,
    },
  ];
  const policyBlocks = <Map<String, dynamic>>[
    {
      'id': 'policy-1',
      'block_type': 'text',
      'block_data': {'text': 'Términos'},
      'order_index': 0,
    },
  ];

  Widget host({
    required WebsiteEditModeProvider provider,
    required bool ready,
    required List<Map<String, dynamic>> blocks,
    String? pageId,
    String? pageSlug,
    bool offstage = false,
    int? bindCalls,
    Object? publisher,
  }) {
    return MaterialApp(
      home: TickerMode(
        enabled: !offstage,
        child: Builder(
          builder: (context) {
            WebsiteEditorDocumentBinding.bind(
              context,
              editProvider: provider,
              ready: ready,
              blocks: () => List<Map<String, dynamic>>.from(blocks),
              settings: () => const <String, dynamic>{},
              pageId: pageId,
              pageSlug: pageSlug,
              publisher: publisher ?? _defaultPublisher,
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  testWidgets(
    'binding is inert outside an editor session and before data is ready',
    (tester) async {
      final provider = providerWithGrantedLease();
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        host(provider: provider, ready: true, blocks: homeBlocks),
      );
      expect(provider.mode, WebsiteEditorMode.public);
      expect(provider.blocks, isEmpty);

      provider.applyRouteModeCommand(WebsiteEditorMode.edit);
      await tester.pumpWidget(
        host(provider: provider, ready: false, blocks: homeBlocks),
      );
      await tester.pump();
      expect(provider.blocks, isEmpty, reason: 'not ready → no document');
    },
  );

  testWidgets(
    'a URL-entered session receives the routed document and later pages '
    'replace it idempotently across Home → Dynamic → Policy → Home',
    (tester) async {
      final provider = providerWithGrantedLease();
      addTearDown(provider.dispose);
      provider.applyRouteModeCommand(WebsiteEditorMode.edit);

      // Home binds the null-page document.
      await tester.pumpWidget(
        host(provider: provider, ready: true, blocks: homeBlocks),
      );
      await tester.pump();
      expect(provider.mode, WebsiteEditorMode.edit);
      expect(provider.ownsPageDocument(), isTrue);
      expect(provider.blocks.single['id'], 'home-1');

      // Re-binding the same page is a no-op (no notification storm).
      var notifications = 0;
      provider.addListener(() => notifications++);
      await tester.pumpWidget(
        host(provider: provider, ready: true, blocks: homeBlocks),
      );
      await tester.pump();
      expect(notifications, 0);

      // A dynamic CMS page replaces the document in the SAME mode.
      await tester.pumpWidget(
        host(
          provider: provider,
          ready: true,
          blocks: pageBlocks,
          pageId: 'page-a',
          pageSlug: 'oferta',
        ),
      );
      await tester.pump();
      expect(
        provider.ownsPageDocument(pageId: 'page-a', pageSlug: 'oferta'),
        isTrue,
      );
      expect(provider.blocks.single['id'], 'page-1');
      expect(provider.mode, WebsiteEditorMode.edit);

      // Preview keeps the same shared binding path.
      provider.setMode(WebsiteEditorMode.preview);
      await tester.pumpWidget(
        host(
          provider: provider,
          ready: true,
          blocks: policyBlocks,
          pageId: 'policy-a',
          pageSlug: 'terminos',
        ),
      );
      await tester.pump();
      expect(
        provider.ownsPageDocument(pageId: 'policy-a', pageSlug: 'terminos'),
        isTrue,
      );
      expect(provider.mode, WebsiteEditorMode.preview);

      // Back to Home.
      await tester.pumpWidget(
        host(provider: provider, ready: true, blocks: homeBlocks),
      );
      await tester.pump();
      expect(provider.ownsPageDocument(), isTrue);
      expect(provider.blocks.single['id'], 'home-1');
      expect(provider.mode, WebsiteEditorMode.preview);
    },
  );

  testWidgets(
    'an offstage kept-alive page never rebinds the active document',
    (tester) async {
      final provider = providerWithGrantedLease();
      addTearDown(provider.dispose);
      provider.applyRouteModeCommand(WebsiteEditorMode.edit);

      await tester.pumpWidget(
        host(
          provider: provider,
          ready: true,
          blocks: pageBlocks,
          pageId: 'page-a',
          pageSlug: 'oferta',
        ),
      );
      await tester.pump();
      expect(provider.blocks.single['id'], 'page-1');

      // An offstage Home must not steal the document.
      await tester.pumpWidget(
        host(
          provider: provider,
          ready: true,
          blocks: homeBlocks,
          offstage: true,
        ),
      );
      await tester.pump();
      expect(
        provider.ownsPageDocument(pageId: 'page-a', pageSlug: 'oferta'),
        isTrue,
      );
      expect(provider.blocks.single['id'], 'page-1');
    },
  );

  testWidgets(
    'only the page in view that owns the document is the block canvas',
    (tester) async {
      final provider = providerWithGrantedLease();
      addTearDown(provider.dispose);
      provider.applyRouteModeCommand(WebsiteEditorMode.edit);
      final page = Object();
      final home = Object();

      // Loading: the open document is not this page yet.
      await tester.pumpWidget(
        host(
          provider: provider,
          ready: false,
          blocks: pageBlocks,
          pageId: 'page-a',
          pageSlug: 'oferta',
          publisher: page,
        ),
      );
      await tester.pump();
      expect(provider.hasBlockCanvas, isFalse);

      await tester.pumpWidget(
        host(
          provider: provider,
          ready: true,
          blocks: pageBlocks,
          pageId: 'page-a',
          pageSlug: 'oferta',
          publisher: page,
        ),
      );
      await tester.pump();
      expect(provider.hasBlockCanvas, isTrue);

      // An offstage Home neither steals the document nor takes it back.
      await tester.pumpWidget(
        host(
          provider: provider,
          ready: true,
          blocks: homeBlocks,
          offstage: true,
          publisher: home,
        ),
      );
      await tester.pump();
      expect(provider.hasBlockCanvas, isTrue);

      // The page itself going offstage (a cart, a product page in front)
      // leaves no block page on the canvas.
      await tester.pumpWidget(
        host(
          provider: provider,
          ready: true,
          blocks: pageBlocks,
          pageId: 'page-a',
          pageSlug: 'oferta',
          offstage: true,
          publisher: page,
        ),
      );
      await tester.pump();
      expect(provider.hasBlockCanvas, isFalse);

      WebsiteEditorDocumentBinding.bind(
        tester.element(find.byType(SizedBox)),
        editProvider: provider,
        ready: true,
        blocks: () => List<Map<String, dynamic>>.from(pageBlocks),
        settings: () => const <String, dynamic>{},
        pageId: 'page-a',
        pageSlug: 'oferta',
        publisher: page,
      );
      WebsiteEditorDocumentBinding.release(provider, home);
      expect(provider.hasBlockCanvas, isFalse, reason: 'offstage context');
    },
  );
}
