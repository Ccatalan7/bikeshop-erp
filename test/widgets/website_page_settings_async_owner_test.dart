import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/services/website_service.dart';
import 'package:vinabike_erp/modules/website/widgets/website_editor_panel.dart';
import 'package:vinabike_erp/shared/services/tenant_service.dart';

class _DelayedPageSettingsService extends WebsiteService {
  _DelayedPageSettingsService()
      : super(
          supabase: SupabaseClient(
            'http://localhost:54321',
            'test-anon-key',
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
          tenantService: TenantService.testing(
            currentUserId: () => null,
            profileLookup: (_) async => const <Map<String, dynamic>>[],
          ),
        );

  final Map<String, Completer<WebsitePage?>> loads =
      <String, Completer<WebsitePage?>>{};

  @override
  Future<WebsitePage?> getPageById(String pageId) {
    return (loads[pageId] ??= Completer<WebsitePage?>()).future;
  }
}

WebsitePage _page(String id, String slug, String title, String description) {
  return WebsitePage(
    id: id,
    tenantId: 'tenant-a',
    slug: slug,
    title: title,
    metaTitle: title,
    metaDescription: description,
    createdAt: DateTime.utc(2026, 8, 9),
    updatedAt: DateTime.utc(2026, 8, 9),
  );
}

Widget _host(
  WebsiteEditModeProvider provider,
  WebsiteService websiteService,
) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<WebsiteEditModeProvider>.value(value: provider),
      ChangeNotifierProvider<WebsiteService>.value(value: websiteService),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: const Scaffold(
        body: SizedBox(
          width: 430,
          height: 850,
          child: WebsiteEditorPanel(),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'Page Settings rejects page A response after retained State moves to B',
    (tester) async {
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          const <Map<String, dynamic>>[],
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: 'a',
        );
      final service = _DelayedPageSettingsService();
      addTearDown(provider.dispose);
      addTearDown(service.dispose);

      await tester.pumpWidget(_host(provider, service));
      await tester.tap(find.text('Página'));
      await tester.pump();
      await tester.pump();
      expect(service.loads.keys, contains('page-a'));

      provider.openEditorDocument(
        const <Map<String, dynamic>>[],
        const <String, dynamic>{},
        mode: WebsiteEditorMode.edit,
        pageId: 'page-b',
        pageSlug: 'b',
      );
      await tester.pump();
      await tester.pump();
      expect(service.loads.keys, contains('page-b'));

      service.loads['page-a']!
          .complete(_page('page-a', 'a', 'Título A', 'Descripción A'));
      await tester.pump();
      expect(find.text('Título A'), findsNothing);

      service.loads['page-b']!
          .complete(_page('page-b', 'b', 'Título B', 'Descripción B'));
      await tester.pumpAndSettle();

      final titleField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.controller?.text == 'Título B',
      );
      final descriptionField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.controller?.text == 'Descripción B',
      );
      expect(titleField, findsOneWidget);
      expect(descriptionField, findsOneWidget);

      await tester.enterText(titleField, 'Título B editado');
      await tester.pump();

      expect(provider.getPendingPageSeo('a'), isNull);
      expect(
        provider.getPendingPageSeo('b'),
        containsPair('meta_description', 'Descripción B'),
      );
    },
  );

  testWidgets(
    'Page Settings clears page A controllers when the exact page B load fails',
    (tester) async {
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          const <Map<String, dynamic>>[],
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: 'a',
        );
      final service = _DelayedPageSettingsService();
      addTearDown(provider.dispose);
      addTearDown(service.dispose);

      await tester.pumpWidget(_host(provider, service));
      await tester.tap(find.text('Página'));
      await tester.pump();
      await tester.pump();
      service.loads['page-a']!
          .complete(_page('page-a', 'a', 'Título A', 'Descripción A'));
      await tester.pumpAndSettle();
      expect(find.text('Título A'), findsWidgets);

      provider.openEditorDocument(
        const <Map<String, dynamic>>[],
        const <String, dynamic>{},
        mode: WebsiteEditorMode.edit,
        pageId: 'page-b',
        pageSlug: 'b',
      );
      await tester.pump();
      await tester.pump();
      service.loads['page-b']!.completeError(StateError('B unavailable'));
      await tester.pumpAndSettle();

      expect(find.text('Título A'), findsNothing);
      expect(find.text('Descripción A'), findsNothing);
      final titleField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Título para Google',
      );
      expect(titleField, findsOneWidget);
      await tester.enterText(titleField, 'Título B editado');
      await tester.pump();

      expect(provider.getPendingPageSeo('a'), isNull);
      expect(
        provider.getPendingPageSeo('b'),
        isNot(containsPair('meta_description', 'Descripción A')),
      );
    },
  );
}
