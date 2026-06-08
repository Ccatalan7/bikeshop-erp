import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_block_capabilities.dart';
import 'package:vinabike_erp/modules/website/models/website_block_definition.dart';
import 'package:vinabike_erp/modules/website/models/website_block_registry.dart';
import 'package:vinabike_erp/modules/website/models/website_block_type.dart';
import 'package:vinabike_erp/modules/website/models/website_font_registry.dart';
import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';

Iterable<WebsiteBlockFieldSchema> flattenFields(
  Iterable<WebsiteBlockFieldSchema> fields,
) sync* {
  for (final field in fields) {
    yield field;
    yield* flattenFields(field.itemFields);
  }
}

void main() {
  test('every website block type has a capability profile', () {
    expect(WebsiteBlockCapabilityRegistry.missingProfileTypes(), isEmpty);

    final profiledTypes =
        WebsiteBlockCapabilityRegistry.all.map((profile) => profile.type);
    expect(profiledTypes.toSet(), WebsiteBlockType.values.toSet());
  });

  test('registry exposes capability profiles for every definition', () {
    for (final type in WebsiteBlockType.values) {
      final definition = WebsiteBlockRegistry.definitionFor(type);
      final profile = WebsiteBlockRegistry.capabilitiesFor(type);

      expect(definition.type, type);
      expect(profile.type, type);
      expect(profile.capabilities, isNotEmpty);
    }
  });

  test('registry discovery always returns every block type', () {
    expect(
      WebsiteBlockRegistry.all().map((definition) => definition.type).toSet(),
      WebsiteBlockType.values.toSet(),
    );
  });

  test('canonical schemas preserve legacy aliases without losing controls', () {
    final hero = WebsiteBlockRegistry.definitionFor(WebsiteBlockType.hero);
    final heroImage =
        hero.fields.firstWhere((field) => field.key == 'imageUrl');
    final heroLink = hero.fields.firstWhere((field) => field.key == 'ctaLink');

    expect(heroImage.migrationAliases, contains('backgroundImage'));
    expect(heroImage.hasFocalPointControl, isTrue);
    expect(heroLink.migrationAliases, contains('buttonLink'));
    expect(heroLink.type, WebsiteBlockFieldType.link);
  });

  test('known blocks without explicit editable renderers are tracked', () {
    expect(
      WebsiteBlockCapabilityRegistry.typesWithoutExplicitEditableRenderer()
          .toSet(),
      <WebsiteBlockType>{
        WebsiteBlockType.products,
        WebsiteBlockType.footer,
        WebsiteBlockType.categoryGrid,
        WebsiteBlockType.videoBanner,
        WebsiteBlockType.partnersBanner,
        WebsiteBlockType.brandLogos,
        WebsiteBlockType.googleReviews,
      },
    );

    expect(
      WebsiteBlockCapabilityRegistry.blockTypesNeedingRendererWork().toSet(),
      <WebsiteBlockType>{
        WebsiteBlockType.products,
        WebsiteBlockType.categoryGrid,
        WebsiteBlockType.videoBanner,
        WebsiteBlockType.partnersBanner,
        WebsiteBlockType.brandLogos,
        WebsiteBlockType.googleReviews,
      },
    );
  });

  test('editor capability profiles do not allow mixed save semantics', () {
    expect(
      WebsiteBlockCapabilityRegistry.typesWithMixedSaveSemantics(),
      isEmpty,
    );
  });

  test('schema fields resolve universal media, action, and formatting metadata',
      () {
    final fields = WebsiteBlockType.values
        .expand((type) => flattenFields(
              WebsiteBlockRegistry.definitionFor(type).fields,
            ))
        .toList();
    final imageFields =
        fields.where((field) => field.type == WebsiteBlockFieldType.image);
    final linkFields =
        fields.where((field) => field.type == WebsiteBlockFieldType.link);
    final formattedTextFields =
        fields.where((field) => field.supportsFormatting);

    expect(imageFields, isNotEmpty);
    expect(linkFields, isNotEmpty);
    expect(formattedTextFields, isNotEmpty);

    for (final field in imageFields) {
      expect(field.resolvedMediaRole, isNotNull, reason: field.key);
      expect(field.hasAltTextControl, isTrue, reason: field.key);
    }
    for (final field in linkFields) {
      expect(field.resolvedActionRole, isNotNull, reason: field.key);
      expect(field.isAction, isTrue, reason: field.key);
    }
    for (final field in formattedTextFields) {
      expect(field.resolvedFormattingKey, isNotEmpty, reason: field.key);
      expect(
        field.resolvedTextRole,
        isNot(WebsiteTextRole.plain),
        reason: field.key,
      );
    }

    const mediaKeys = {'imageUrl', 'backgroundImage', 'avatarUrl'};
    const actionKeys = {'link', 'ctaLink', 'buttonLink'};
    for (final field
        in fields.where((field) => mediaKeys.contains(field.key))) {
      expect(field.type, WebsiteBlockFieldType.image, reason: field.key);
    }
    for (final field
        in fields.where((field) => actionKeys.contains(field.key))) {
      expect(field.type, WebsiteBlockFieldType.link, reason: field.key);
    }
  });

  test('generic editor routes universal controls through canonical widgets',
      () {
    final panelSource =
        File('lib/modules/website/widgets/website_editor_panel.dart')
            .readAsStringSync();
    final rendererSource =
        File('lib/modules/website/widgets/website_block_renderer.dart')
            .readAsStringSync();

    expect(panelSource, contains('field.hasFocalPointControl'));
    expect(panelSource, contains('field.hasAltTextControl'));
    expect(panelSource, contains('field.resolvedFormattingKey'));
    expect(panelSource, contains('TextFormattingToolbar('));
    expect(panelSource, contains("'titleFormatting'"));
    expect(panelSource, contains("'mobileFocalPointX'"));
    expect(rendererSource, contains('_resolveFocalAlignment('));
    expect(rendererSource, contains('_resolveTextFormatting('));
    expect(
      panelSource,
      isNot(contains('if (parsed == WebsiteBlockType.hero) ...[')),
    );
  });

  test('add-block picker is registry-driven and legacy editors stay removed',
      () {
    final addDialogSource =
        File('lib/modules/website/widgets/add_block_dialog.dart')
            .readAsStringSync();

    expect(addDialogSource, contains('WebsiteBlockRegistry.all()'));
    expect(addDialogSource, contains('definition.type.name'));
    final panelSource =
        File('lib/modules/website/widgets/website_editor_panel.dart')
            .readAsStringSync();
    expect(panelSource,
        contains('for (final definition in WebsiteBlockRegistry.all())'));
    for (final legacyPath in [
      'lib/modules/website/widgets/inline_edit_toolbar.dart',
      'lib/public_store/widgets/editable_website.dart',
      'lib/modules/website/pages/visual_editor_page.dart',
      'lib/modules/website/pages/visual_editor_page_advanced.dart',
    ]) {
      expect(File(legacyPath).existsSync(), isFalse, reason: legacyPath);
    }
  });

  test('pricing plan CTA destinations are editor-owned link fields', () {
    final definition =
        WebsiteBlockRegistry.definitionFor(WebsiteBlockType.pricing);
    final plansField =
        definition.fields.firstWhere((field) => field.key == 'plans');
    final ctaLinkField =
        plansField.itemFields.firstWhere((field) => field.key == 'ctaLink');

    expect(ctaLinkField.type, WebsiteBlockFieldType.link);

    final defaultPlans = definition.defaultData['plans'] as List<dynamic>;
    expect(defaultPlans, isNotEmpty);
    for (final plan in defaultPlans.whereType<Map>()) {
      expect(plan['ctaLink'], isNotNull);
      expect(plan['ctaLink'].toString(), isNotEmpty);
    }
  });

  test('structured website lists do not use comma-separated URL chips', () {
    final partners = WebsiteBlockRegistry.definitionFor(
      WebsiteBlockType.partnersBanner,
    );
    final brands = WebsiteBlockRegistry.definitionFor(
      WebsiteBlockType.brandLogos,
    );
    final partnerItems =
        partners.fields.firstWhere((field) => field.key == 'items');
    final brandItems =
        brands.fields.firstWhere((field) => field.key == 'brands');

    expect(partnerItems.type, WebsiteBlockFieldType.repeater);
    expect(brandItems.type, WebsiteBlockFieldType.repeater);
    expect(
      brandItems.itemFields.firstWhere((field) => field.key == 'imageUrl').type,
      WebsiteBlockFieldType.image,
    );
    expect(
      brandItems.itemFields.firstWhere((field) => field.key == 'link').type,
      WebsiteBlockFieldType.link,
    );
  });

  test('editor button links use the canonical link editor', () {
    final panelSource =
        File('lib/modules/website/widgets/website_editor_panel.dart')
            .readAsStringSync();
    final editableRendererSource =
        File('lib/modules/website/widgets/editable_block_renderer.dart')
            .readAsStringSync();

    expect(panelSource, contains('WebsiteLinkValueEditor('));
    expect(editableRendererSource, contains('WebsiteLinkValueEditor('));

    expect(panelSource, isNot(contains('class _LinkPicker')));
    expect(panelSource, isNot(contains('_LinkPicker(')));
    expect(editableRendererSource, isNot(contains('class _DarkLinkPicker')));
    expect(editableRendererSource, isNot(contains('_DarkLinkPicker(')));
    expect(editableRendererSource, isNot(contains('class _InlineLinkPicker')));
    expect(editableRendererSource, isNot(contains('_InlineLinkPicker(')));
  });

  test('website theme fonts only expose bundled renderer-supported families',
      () {
    expect(
      WebsiteFontRegistry.supportedFamilies,
      <String>[
        WebsiteFontRegistry.headingDefault,
        WebsiteFontRegistry.bodyDefault,
      ],
    );
    expect(
      WebsiteFontRegistry.supportedFamilies.toSet().length,
      WebsiteFontRegistry.supportedFamilies.length,
    );
    expect(
      WebsiteFontRegistry.resolveHeadingFont('Roboto'),
      WebsiteFontRegistry.headingDefault,
    );
    expect(
      WebsiteFontRegistry.resolveBodyFont('Inter'),
      WebsiteFontRegistry.bodyDefault,
    );
    expect(WebsiteFontRegistry.resolveHeadingFont('  Oswald  '), 'Oswald');
    expect(WebsiteFontRegistry.resolveBodyFont('  Barlow  '), 'Barlow');
  });

  test('theme font picker and renderers use the central font registry', () {
    final panelSource =
        File('lib/modules/website/widgets/website_editor_panel.dart')
            .readAsStringSync();
    final themeBuilderSource =
        File('lib/modules/website/theme/website_theme_builder.dart')
            .readAsStringSync();
    final blockRendererSource =
        File('lib/modules/website/widgets/website_block_renderer.dart')
            .readAsStringSync();

    expect(panelSource, contains('WebsiteFontRegistry.supportedFamilies'));
    expect(panelSource, contains('WebsiteFontRegistry.resolveHeadingFont'));
    expect(panelSource, contains('WebsiteFontRegistry.resolveBodyFont'));
    expect(
      themeBuilderSource,
      contains('WebsiteFontRegistry.resolveHeadingFont'),
    );
    expect(
      themeBuilderSource,
      contains('WebsiteFontRegistry.resolveBodyFont'),
    );
    expect(
      blockRendererSource,
      contains('WebsiteFontRegistry.resolveOptionalHeadingFont'),
    );
    expect(
      blockRendererSource,
      contains('WebsiteFontRegistry.resolveOptionalBodyFont'),
    );

    expect(panelSource, isNot(contains("    'Roboto',")));
    expect(panelSource, isNot(contains("    'Inter',")));
    expect(panelSource, isNot(contains("    'Montserrat',")));
    expect(panelSource, isNot(contains("    'Poppins',")));
  });

  test('public store surfaces do not override editor-owned theme fonts', () {
    final files = Directory('lib/public_store')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) =>
            file.path.endsWith('.dart') &&
            !file.path.endsWith('public_store_theme.dart'));

    for (final file in files) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(contains('PublicStoreTheme.defaultHeadingFont')),
        reason: file.path,
      );
      expect(
        source,
        isNot(contains('PublicStoreTheme.defaultBodyFont')),
        reason: file.path,
      );
    }
  });

  test('footer navigation inline edits stage through the global save pipeline',
      () {
    final panelSource =
        File('lib/modules/website/widgets/website_editor_panel.dart')
            .readAsStringSync();
    final providerSource =
        File('lib/modules/website/providers/website_edit_mode_provider.dart')
            .readAsStringSync();
    final serviceSource =
        File('lib/modules/website/services/website_service.dart')
            .readAsStringSync();
    final publicLayoutSource =
        File('lib/public_store/widgets/public_store_layout.dart')
            .readAsStringSync();

    expect(providerSource, contains('updateFooterNavItem'));
    expect(serviceSource, contains('pendingFooterNavItems'));
    expect(serviceSource, contains('pendingFooterNavCreates'));
    expect(serviceSource, contains('pendingFooterNavDeletes'));
    expect(panelSource, contains('editProvider.updateFooterNavItem(updated)'));
    expect(panelSource, contains('editProvider.createFooterNavDraft'));
    expect(panelSource, contains('editProvider.deleteFooterNavItem'));
    expect(panelSource, contains("const Text('Aplicar')"));
    expect(
      publicLayoutSource,
      contains('updateFooterSetting(settingKey, value)'),
    );
    expect(
      panelSource,
      isNot(contains('await service.updateNavigation(updated)')),
    );
    expect(panelSource, isNot(contains('service.createNavigation(')));
    expect(panelSource, isNot(contains('service.deleteNavigation(')));
    expect(
      panelSource,
      isNot(contains("content: Text('Cambios guardados')")),
    );
    expect(
      publicLayoutSource,
      isNot(contains('saveSetting(settingKey, value)')),
    );
  });

  test('backup restore reloads editor state instead of invoking save', () {
    final panelSource =
        File('lib/modules/website/widgets/website_editor_panel.dart')
            .readAsStringSync();
    final shellSource =
        File('lib/public_store/widgets/persistent_editor_shell.dart')
            .readAsStringSync();

    expect(panelSource, contains('onRestoreComplete'));
    expect(panelSource, contains('final restored ='));
    expect(panelSource, isNot(contains('widget.onSave?.call()')));
    expect(shellSource, contains('_handleRestoreComplete'));
    expect(shellSource, contains('forceRefresh: true'));
  });

  test('footer navigation drafts preserve hierarchy and staged deletion', () {
    final provider = WebsiteEditModeProvider();
    final now = DateTime.now();
    final parent = provider.createFooterNavDraft(
      WebsiteNavigation(
        id: '',
        tenantId: 'tenant',
        menuLocation: MenuLocation.footer,
        label: 'Ayuda',
        linkType: NavLinkType.action,
        createdAt: now,
        updatedAt: now,
      ),
    );
    provider.createFooterNavDraft(
      WebsiteNavigation(
        id: '',
        tenantId: 'tenant',
        menuLocation: MenuLocation.footer,
        label: 'Contacto',
        linkValue: '/contacto',
        parentId: parent.id,
        createdAt: now,
        updatedAt: now,
      ),
    );

    final effective = provider.getEffectiveFooterNavigation(
      const <WebsiteNavigation>[],
    );
    expect(effective, hasLength(1));
    expect(effective.single.label, 'Ayuda');
    expect(effective.single.children.single.label, 'Contacto');

    provider.deleteFooterNavItem(effective.single);

    expect(
      provider.getEffectiveFooterNavigation(const <WebsiteNavigation>[]),
      isEmpty,
    );
    expect(provider.pendingFooterNavCreates, isEmpty);
  });

  test('discard restores blocks and clears all staged editor changes', () {
    final provider = WebsiteEditModeProvider();
    provider.enterEditMode(
      [
        {
          'id': 'block-1',
          'block_type': 'text',
          'block_data': {'text': 'Original'},
        },
      ],
      const {},
    );

    provider.updateBlockData('block-1', 'text', 'Changed');
    provider.updateThemeSetting('theme_heading_font', 'Barlow');
    provider.updateFooterSetting('contact_email', 'changed@example.com');
    provider.updateHeaderSettings({'header_logo_url': 'changed.png'});
    provider.updateSiteSetting('store_name', 'Changed');
    provider.updateCategoryVisibility('category-1', false);
    provider.updatePageSeo(
      routeKey: 'inicio',
      metaTitle: 'Changed',
      metaDescription: 'Changed',
    );
    provider.createFooterNavDraft(
      WebsiteNavigation(
        id: '',
        tenantId: 'tenant',
        menuLocation: MenuLocation.footer,
        label: 'Draft',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    provider.discardPendingChanges();

    expect(provider.hasUnsavedChanges, isFalse);
    expect(provider.pendingHeaderSettings, isEmpty);
    expect(provider.pendingSiteSettings, isEmpty);
    expect(provider.pendingThemeSettings, isEmpty);
    expect(provider.pendingFooterSettings, isEmpty);
    expect(provider.pendingFooterNavCreates, isEmpty);
    expect(provider.pendingCategoryVisibility, isEmpty);
    expect(provider.pendingPageSeo, isEmpty);
    expect(
      provider.blocks.single['block_data']['text'],
      'Original',
    );
  });
}
