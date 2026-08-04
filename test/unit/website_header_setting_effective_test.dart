import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/public_store/widgets/public_store_layout.dart';

/// Focal contract for [WebsiteEditModeProvider.getEffectiveHeaderSetting]:
/// the header draft previews PENDING over saved, exactly like theme
/// settings, so the storefront logo and the reopened header control can
/// never disagree with the canvas they are previewing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pending > saved > default, and the draft survives control reopen', () {
    final provider = WebsiteEditModeProvider()
      ..enterEditMode(
        const <Map<String, dynamic>>[],
        const <String, dynamic>{'logo_url': 'https://saved/logo.png'},
      );
    addTearDown(provider.dispose);

    // Saved wins while nothing is staged.
    expect(
      provider.getEffectiveHeaderSetting('logo_url', 'https://saved/logo.png'),
      'https://saved/logo.png',
    );
    // Unknown key falls to the caller's default.
    expect(
      provider.getEffectiveHeaderSetting('header_style', 'solid'),
      'solid',
    );

    // Staging wins over saved…
    provider.updateHeaderSettings({'logo_url': 'https://staged/logo.png'});
    expect(
      provider.getEffectiveHeaderSetting('logo_url', 'https://saved/logo.png'),
      'https://staged/logo.png',
    );
    // …and SURVIVES closing/reopening the control (the provider owns the
    // draft; the control only hydrates from this same reader).
    expect(
      provider.getEffectiveHeaderSetting('logo_url', 'https://saved/logo.png'),
      'https://staged/logo.png',
    );

    // Discarding the sitewide draft restores saved.
    provider.discardSitewideDrafts();
    expect(
      provider.getEffectiveHeaderSetting('logo_url', 'https://saved/logo.png'),
      'https://saved/logo.png',
    );
  });

  test(
      'StorefrontLogoResolution.effectiveConfiguredUrl: Edit and Preview '
      'preview the staged draft; Public renders saved only', () {
    const saved = 'https://saved/logo.png';
    const staged = 'https://staged/logo.png';

    // Public: a pending draft never leaks outside the editor context.
    final publicProvider = WebsiteEditModeProvider()
      ..updateHeaderSettings({'logo_url': staged});
    addTearDown(publicProvider.dispose);
    expect(
      StorefrontLogoResolution.effectiveConfiguredUrl(saved, publicProvider),
      saved,
      reason: 'Public renders SAVED even with a staged draft present',
    );

    // Edit: staged wins.
    final editorProvider = WebsiteEditModeProvider()
      ..enterEditMode(
        const <Map<String, dynamic>>[],
        const <String, dynamic>{},
      )
      ..updateHeaderSettings({'logo_url': staged});
    addTearDown(editorProvider.dispose);
    expect(
      StorefrontLogoResolution.effectiveConfiguredUrl(saved, editorProvider),
      staged,
      reason: 'Edit previews the staged draft',
    );

    // Preview converges on the same staged value.
    editorProvider.setMode(WebsiteEditorMode.preview);
    expect(
      StorefrontLogoResolution.effectiveConfiguredUrl(saved, editorProvider),
      staged,
      reason: 'Preview converges with Edit on the staged draft',
    );

    // Back to Public with the draft STILL pending: saved wins again.
    editorProvider.setMode(WebsiteEditorMode.public);
    expect(
      StorefrontLogoResolution.effectiveConfiguredUrl(saved, editorProvider),
      saved,
      reason: 'Public renders saved even while a draft remains staged',
    );
  });

  test(
      'COMPLEMENT (never the sole evidence): the header control hydrates '
      'through getEffectiveHeaderSetting', () {
    final source = File(
      'lib/modules/website/widgets/editor_panel/header_footer_controls.dart',
    ).readAsStringSync();
    expect(source, contains('getEffectiveHeaderSetting'),
        reason: 'reopening _HeaderBlockControls must hydrate pending > '
            'saved through the provider owner; the behavioural half lives '
            'in this file and in public_store_header_responsive_test.dart');
  });
}
