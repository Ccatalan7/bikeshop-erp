import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';

void main() {
  WebsiteEditModeProvider provider({String savedTheme = '#112233'}) =>
      WebsiteEditModeProvider()
        ..enterEditMode(
          const <Map<String, dynamic>>[],
          <String, dynamic>{'theme_primary_color': savedTheme},
          pageId: 'home',
          pageSlug: '',
        );

  test('valid sitewide intent commits once and is one-shot', () {
    final editProvider = provider();
    addTearDown(editProvider.dispose);

    var notifications = 0;
    editProvider.addListener(() => notifications++);
    final intent = editProvider.captureSitewideAsyncIntent(
      bucket: WebsiteSitewideDraftBucket.theme,
      sourceKeys: const <String>{'theme_primary_color'},
    );
    expect(intent, isNotNull);
    expect(notifications, 0, reason: 'capture is side-effect free');

    final result = editProvider.commitSitewideAsyncIntent(intent!, () {
      editProvider.updateThemeSetting('theme_primary_color', '#445566');
      return WebsiteInlineMutationResult.committed;
    });

    expect(result, WebsiteInlineMutationResult.committed);
    expect(editProvider.pendingThemeSettings['theme_primary_color'], '#445566');
    expect(notifications, 1, reason: 'one accepted intent is one state write');

    var replayRan = false;
    final replay = editProvider.commitSitewideAsyncIntent(intent, () {
      replayRan = true;
      return WebsiteInlineMutationResult.committed;
    });
    expect(replay, WebsiteInlineMutationResult.rejected);
    expect(replayRan, isFalse);
    expect(notifications, 1);
  });

  test('same-bucket A to B to A rejects even when the source key matches', () {
    final editProvider = provider();
    addTearDown(editProvider.dispose);

    final intent = editProvider.captureSitewideAsyncIntent(
      bucket: WebsiteSitewideDraftBucket.theme,
      sourceKeys: const <String>{'theme_primary_color'},
    )!;
    editProvider
      ..updateThemeSetting('theme_primary_color', '#445566')
      ..updateThemeSetting('theme_primary_color', '#112233');

    var operationRan = false;
    final result = editProvider.commitSitewideAsyncIntent(intent, () {
      operationRan = true;
      return WebsiteInlineMutationResult.committed;
    });

    expect(result, WebsiteInlineMutationResult.rejected);
    expect(operationRan, isFalse);
    expect(editProvider.pendingThemeSettings['theme_primary_color'], '#112233');
  });

  test('provider A intent cannot be adopted by provider B with identical keys',
      () {
    final providerA = provider();
    final providerB = provider();
    addTearDown(providerA.dispose);
    addTearDown(providerB.dispose);

    final intentA = providerA.captureSitewideAsyncIntent(
      bucket: WebsiteSitewideDraftBucket.header,
      sourceKeys: const <String>{'logo_url'},
    )!;
    var operationRan = false;
    final result = providerB.commitSitewideAsyncIntent(intentA, () {
      operationRan = true;
      providerB.updateHeaderSettings(
        const <String, String>{'logo_url': 'https://stale/logo.png'},
      );
      return WebsiteInlineMutationResult.committed;
    });

    expect(result, WebsiteInlineMutationResult.rejected);
    expect(operationRan, isFalse);
    expect(providerA.pendingHeaderSettings, isEmpty);
    expect(providerB.pendingHeaderSettings, isEmpty);
  });

  test('another bucket does not invalidate a sitewide intent', () {
    final editProvider = provider();
    addTearDown(editProvider.dispose);

    final intent = editProvider.captureSitewideAsyncIntent(
      bucket: WebsiteSitewideDraftBucket.header,
      sourceKeys: const <String>{'logo_url'},
    )!;
    editProvider.updateThemeSetting('theme_primary_color', '#445566');

    final result = editProvider.commitSitewideAsyncIntent(intent, () {
      editProvider.updateHeaderSettings(
        const <String, String>{'logo_url': 'https://fresh/logo.png'},
      );
      return WebsiteInlineMutationResult.committed;
    });

    expect(result, WebsiteInlineMutationResult.committed);
    expect(
      editProvider.pendingHeaderSettings['logo_url'],
      'https://fresh/logo.png',
    );
  });

  test('site settings mutation does not advance the theme bucket', () {
    final editProvider = provider();
    addTearDown(editProvider.dispose);

    final intent = editProvider.captureSitewideAsyncIntent(
      bucket: WebsiteSitewideDraftBucket.theme,
      sourceKeys: const <String>{'theme_primary_color'},
    )!;
    editProvider.updateSiteSetting('custom_domain', 'example.test');

    final result = editProvider.commitSitewideAsyncIntent(
      intent,
      () => WebsiteInlineMutationResult.unchanged,
    );

    expect(result, WebsiteInlineMutationResult.unchanged);
  });

  test('sitewide intent survives a page route change in the same session', () {
    final editProvider = provider();
    addTearDown(editProvider.dispose);

    final intent = editProvider.captureSitewideAsyncIntent(
      bucket: WebsiteSitewideDraftBucket.header,
      sourceKeys: const <String>{'logo_url'},
    )!;
    editProvider.enterEditMode(
      const <Map<String, dynamic>>[],
      const <String, dynamic>{'theme_primary_color': '#112233'},
      pageId: 'contact',
      pageSlug: 'contacto',
    );

    final result = editProvider.commitSitewideAsyncIntent(intent, () {
      editProvider.updateHeaderSettings(
        const <String, String>{'logo_url': 'https://fresh/logo.png'},
      );
      return WebsiteInlineMutationResult.committed;
    });
    expect(result, WebsiteInlineMutationResult.committed);
  });

  test('edit to preview to edit invalidates the captured session context', () {
    final editProvider = provider();
    addTearDown(editProvider.dispose);

    final intent = editProvider.captureSitewideAsyncIntent(
      bucket: WebsiteSitewideDraftBucket.theme,
      sourceKeys: const <String>{'theme_primary_color'},
    )!;
    editProvider
      ..setMode(WebsiteEditorMode.preview)
      ..setMode(WebsiteEditorMode.edit);

    var operationRan = false;
    final result = editProvider.commitSitewideAsyncIntent(intent, () {
      operationRan = true;
      return WebsiteInlineMutationResult.committed;
    });
    expect(result, WebsiteInlineMutationResult.rejected);
    expect(operationRan, isFalse);
  });

  test('footer navigation uses the footer bucket and aggregate source', () {
    final editProvider = provider();
    addTearDown(editProvider.dispose);

    final intent = editProvider.captureSitewideAsyncIntent(
      bucket: WebsiteSitewideDraftBucket.footer,
      sourceKeys: const <String>{
        WebsiteSitewideAsyncSourceKey.footerNavigation,
      },
    )!;
    editProvider.createFooterNavDraft(
      WebsiteNavigation(
        id: '',
        tenantId: 'tenant-a',
        menuLocation: MenuLocation.footer,
        label: 'Ayuda',
        linkType: NavLinkType.page,
        linkValue: '/ayuda',
        orderIndex: 0,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );

    var operationRan = false;
    final result = editProvider.commitSitewideAsyncIntent(intent, () {
      operationRan = true;
      return WebsiteInlineMutationResult.committed;
    });
    expect(result, WebsiteInlineMutationResult.rejected);
    expect(operationRan, isFalse);
  });
}
