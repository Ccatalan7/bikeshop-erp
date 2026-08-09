import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_block_capabilities.dart';
import 'package:vinabike_erp/modules/website/models/website_block_definition.dart';
import 'package:vinabike_erp/modules/website/models/website_block_geometry.dart';
import 'package:vinabike_erp/modules/website/models/website_block_registry.dart';
import 'package:vinabike_erp/modules/website/models/website_block_type.dart';
import 'package:vinabike_erp/modules/website/models/website_font_registry.dart';
import 'package:vinabike_erp/modules/website/models/website_page_models.dart';
import 'package:vinabike_erp/modules/website/models/website_responsive_authoring.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import '../support/library_source.dart';

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
        WebsiteBlockType.hero,
        WebsiteBlockType.carousel,
        WebsiteBlockType.canvas,
        WebsiteBlockType.text,
        WebsiteBlockType.divider,
        WebsiteBlockType.button,
        WebsiteBlockType.products,
        WebsiteBlockType.services,
        WebsiteBlockType.about,
        WebsiteBlockType.testimonials,
        WebsiteBlockType.features,
        WebsiteBlockType.gallery,
        WebsiteBlockType.cta,
        WebsiteBlockType.contact,
        WebsiteBlockType.faq,
        WebsiteBlockType.pricing,
        WebsiteBlockType.team,
        WebsiteBlockType.stats,
        WebsiteBlockType.footer,
        WebsiteBlockType.categoryGrid,
        WebsiteBlockType.videoBanner,
        WebsiteBlockType.partnersBanner,
        WebsiteBlockType.brandLogos,
        WebsiteBlockType.googleReviews,
      },
    );

    const sharedContentTypes = <WebsiteBlockType>{
      WebsiteBlockType.hero,
      WebsiteBlockType.carousel,
      WebsiteBlockType.canvas,
      WebsiteBlockType.text,
      WebsiteBlockType.divider,
      WebsiteBlockType.button,
      WebsiteBlockType.products,
      WebsiteBlockType.services,
      WebsiteBlockType.about,
      WebsiteBlockType.testimonials,
      WebsiteBlockType.features,
      WebsiteBlockType.gallery,
      WebsiteBlockType.cta,
      WebsiteBlockType.contact,
      WebsiteBlockType.faq,
      WebsiteBlockType.pricing,
      WebsiteBlockType.team,
      WebsiteBlockType.stats,
      WebsiteBlockType.footer,
      WebsiteBlockType.categoryGrid,
      WebsiteBlockType.videoBanner,
      WebsiteBlockType.partnersBanner,
      WebsiteBlockType.brandLogos,
      WebsiteBlockType.googleReviews,
    };
    expect(
      WebsiteBlockCapabilityRegistry.typesUsingSharedContentRendererInEdit()
          .toSet(),
      sharedContentTypes,
    );
    final legacyTypes =
        WebsiteBlockType.values.toSet().difference(sharedContentTypes);
    expect(
      WebsiteBlockCapabilityRegistry.typesUsingLegacyDedicatedRenderer()
          .toSet(),
      legacyTypes,
    );
    expect(
      WebsiteBlockCapabilityRegistry.blockTypesNeedingRendererWork().toSet(),
      legacyTypes,
    );
    for (final profile in WebsiteBlockCapabilityRegistry.all) {
      expect(
        profile.usesSharedContentRendererInEdit ^
            profile.usesLegacyDedicatedRenderer,
        isTrue,
        reason: profile.type.name,
      );
    }
  });

  test('editor capability profiles do not allow mixed save semantics', () {
    expect(
      WebsiteBlockCapabilityRegistry.typesWithMixedSaveSemantics(),
      isEmpty,
    );
  });

  test('capability registry has no unresolved editor gaps', () {
    final unresolved = <String>[
      for (final profile in WebsiteBlockCapabilityRegistry.all)
        for (final gap in profile.gaps) '${profile.type.name}:${gap.name}',
    ];

    expect(unresolved, isEmpty);
  });

  test('capability registry is the single owner of block height behavior', () {
    const exact = <WebsiteBlockType>{
      WebsiteBlockType.hero,
      WebsiteBlockType.carousel,
      WebsiteBlockType.canvas,
      WebsiteBlockType.videoBanner,
    };
    const intrinsic = <WebsiteBlockType>{
      WebsiteBlockType.text,
      WebsiteBlockType.button,
      WebsiteBlockType.divider,
      WebsiteBlockType.footer,
    };

    for (final profile in WebsiteBlockCapabilityRegistry.all) {
      final expected = exact.contains(profile.type)
          ? WebsitePageBlockHeightBehavior.exact
          : intrinsic.contains(profile.type)
              ? WebsitePageBlockHeightBehavior.intrinsic
              : WebsitePageBlockHeightBehavior.minimum;
      expect(profile.heightBehavior, expected, reason: profile.type.name);
    }
  });

  test('inspector height semantics follow the canonical capability', () {
    expect(
      WebsitePageBlockHeightBehavior.intrinsic.inspectorLabel,
      isNull,
    );
    expect(
      WebsitePageBlockHeightBehavior.minimum.inspectorLabel,
      'Altura mínima',
    );
    expect(
      WebsitePageBlockHeightBehavior.minimum.inspectorResizeHint,
      'El contenido puede crecer; arrastra para cambiar el mínimo',
    );
    expect(
      WebsitePageBlockHeightBehavior.exact.inspectorLabel,
      'Altura',
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
      expect(field.altTextField, isNotNull, reason: field.key);
      expect(
        field.altTextField!.responsivePolicy,
        WebsiteResponsivePropertyPolicy.sharedOnly,
        reason: '${field.key}.${field.altTextKey}',
      );
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
    final panelSource = readLibrarySource(
        'lib/modules/website/widgets/website_editor_panel.dart');
    final rendererSource =
        File('lib/modules/website/widgets/website_block_renderer.dart')
            .readAsStringSync();
    final mediaBindingSource = File(
      'lib/modules/website/widgets/website_responsive_media_binding.dart',
    ).readAsStringSync();

    // Focal capability is owned by the canonical responsive media binding,
    // while the schema editor only mounts that binding. Keeping this assertion
    // on the panel would require the panel to re-interpret the same capability.
    expect(panelSource, contains('WebsiteResponsiveMediaBinding.root('));
    expect(mediaBindingSource, contains('field.hasFocalPointControl'));
    expect(panelSource, contains('field.hasAltTextControl'));
    expect(panelSource, contains('field.resolvedFormattingKey'));
    expect(panelSource, contains('TextFormattingToolbar('));
    expect(panelSource, contains("'titleFormatting'"));
    expect(
      mediaBindingSource,
      contains('WebsiteResponsiveFocalProjection.legacyReader('),
    );
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

    // The guard's invariant is unchanged — the picker may not hand-maintain a
    // list — but it now has ONE owner instead of a copy per surface. Asserting
    // the registry call inside each surface would force those copies back.
    final catalogSource =
        File('lib/modules/website/models/website_block_catalog.dart')
            .readAsStringSync();
    expect(catalogSource, contains('WebsiteBlockRegistry.all()'));
    expect(catalogSource, contains('type: type'));

    expect(addDialogSource, contains('WebsiteBlockCatalog.entries('));
    expect(addDialogSource, contains('entry.type.name'));
    expect(
      addDialogSource,
      isNot(contains('WebsiteBlockRegistry.all()')),
      reason: 'el diálogo consume el catálogo, no re-deriva el registro',
    );

    final panelSource = readLibrarySource(
        'lib/modules/website/widgets/website_editor_panel.dart');
    expect(panelSource, contains('WebsiteBlockCatalog.filtered('));
    expect(
      panelSource,
      isNot(contains('for (final definition in WebsiteBlockRegistry.all())')),
      reason: 'la pestaña Insertar consume el catálogo, no el registro directo',
    );

    // And the sheet is the third consumer of the same owner.
    final catalogSheetSource =
        File('lib/modules/website/widgets/website_block_catalog_sheet.dart')
            .readAsStringSync();
    expect(catalogSheetSource, contains('WebsiteBlockCatalog.filtered('));
    expect(catalogSheetSource, isNot(contains('WebsiteBlockRegistry')));
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
    final panelSource = readLibrarySource(
        'lib/modules/website/widgets/website_editor_panel.dart');
    final inlineActionSource =
        File('lib/modules/website/widgets/website_inline_action_editor.dart')
            .readAsStringSync();

    expect(panelSource, contains('WebsiteLinkValueEditor('));
    expect(inlineActionSource, contains('WebsiteLinkValueEditor('));

    expect(panelSource, isNot(contains('class _LinkPicker')));
    expect(panelSource, isNot(contains('_LinkPicker(')));
    expect(inlineActionSource, isNot(contains('class _DarkLinkPicker')));
    expect(inlineActionSource, isNot(contains('_DarkLinkPicker(')));
    expect(inlineActionSource, isNot(contains('class _InlineLinkPicker')));
    expect(inlineActionSource, isNot(contains('_InlineLinkPicker(')));
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
    final panelSource = readLibrarySource(
        'lib/modules/website/widgets/website_editor_panel.dart');
    final themeBuilderSource =
        File('lib/modules/website/theme/website_theme_builder.dart')
            .readAsStringSync();
    final resolvedThemeSource =
        File('lib/modules/website/theme/website_resolved_theme.dart')
            .readAsStringSync();
    final blockRendererSource =
        File('lib/modules/website/widgets/website_block_renderer.dart')
            .readAsStringSync();

    expect(panelSource, contains('WebsiteFontRegistry.supportedFamilies'));
    expect(panelSource, contains('WebsiteResolvedTheme.resolve('));
    expect(panelSource, contains('_headingFont = resolved.headingFont'));
    expect(panelSource, contains('_bodyFont = resolved.bodyFont'));
    expect(
      resolvedThemeSource,
      contains('WebsiteFontRegistry.resolveHeadingFont'),
    );
    expect(
      resolvedThemeSource,
      contains('WebsiteFontRegistry.resolveBodyFont'),
    );
    expect(themeBuilderSource, isNot(contains('WebsiteFontRegistry')),
        reason: 'The ThemeData projector consumes the already resolved owner.');
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

  test('backup restore reloads editor state instead of invoking save', () {
    final panelSource = readLibrarySource(
        'lib/modules/website/widgets/website_editor_panel.dart');
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
    expect(provider.pendingPageSeo, isEmpty);
    expect(
      provider.blocks.single['block_data']['text'],
      'Original',
    );
  });
}
