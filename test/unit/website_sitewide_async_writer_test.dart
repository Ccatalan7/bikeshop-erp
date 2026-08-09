import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _slice(String source, String start, String end) {
  final startIndex = source.indexOf(start);
  expect(startIndex, greaterThanOrEqualTo(0), reason: 'missing $start');
  final endIndex = source.indexOf(end, startIndex + start.length);
  expect(endIndex, greaterThan(startIndex),
      reason: 'missing $end after $start');
  return source.substring(startIndex, endIndex);
}

void _expectOrdered(String source, List<String> markers) {
  var cursor = -1;
  for (final marker in markers) {
    final next = source.indexOf(marker, cursor + 1);
    expect(next, greaterThan(cursor), reason: 'expected $marker after $cursor');
    cursor = next;
  }
}

void main() {
  test('header logo and colors use the canonical sitewide async transport', () {
    final header = File(
      'lib/modules/website/widgets/editor_panel/header_footer_controls.dart',
    ).readAsStringSync();
    final theme = File(
      'lib/modules/website/widgets/editor_panel/theme_tab.dart',
    ).readAsStringSync();

    expect(
      header,
      contains('didUpdateWidget(covariant _HeaderBlockControls oldWidget)'),
    );
    for (final key in const <String>[
      'logo_url',
      'header_bg_color',
      'header_menu_surface_color',
      'header_menu_rail_color',
    ]) {
      expect(header, contains("_headerAsyncBinding('$key')"));
    }

    final logo = _slice(
      theme,
      'Future<void> _pickAndUploadLogo() async',
      '@override\n  Widget build(BuildContext context)',
    );
    _expectOrdered(logo, <String>[
      'openingBinding?.capture()',
      'await showWebsiteMediaPicker(',
      'final liveBinding = widget.asyncBinding',
      'liveBinding.commit(arm, ()',
      'widget.onChanged(asset.publicUrl)',
    ]);
  });

  test('theme owns every async color and rebaselines on provider swap', () {
    final source = File(
      'lib/modules/website/widgets/editor_panel/theme_tab.dart',
    ).readAsStringSync();

    expect(source, contains('const _ThemeTab({required this.provider})'));
    expect(
      source,
      contains('didUpdateWidget(covariant _ThemeTab oldWidget)'),
    );
    expect(source, contains('identical(widget.provider, expectedProvider)'));
    expect(source, contains('identity: (provider, bucket, sourceKey)'));
    for (final key in const <String>[
      'theme_primary_color',
      'theme_accent_color',
      'theme_text_color',
      'theme_product_detail_accent_color',
      'theme_product_detail_text_color',
      'theme_product_detail_line_color',
      'theme_background_color',
    ]) {
      expect(source, contains("_themeAsyncBinding('$key')"));
    }
  });

  test('footer panel captures before await and commits through the live owner',
      () {
    final source = File(
      'lib/modules/website/widgets/editor_panel/header_footer_controls.dart',
    ).readAsStringSync();
    expect(
      source,
      contains('didUpdateWidget(covariant _FooterBlockControls oldWidget)'),
    );

    final deletion = _slice(
      source,
      'Future<void> _deleteFooterNav(WebsiteNavigation nav) async',
      'Future<void> _showFooterNavDialog({',
    );
    _expectOrdered(deletion, <String>[
      '_footerNavigationSourceSnapshot(',
      'captureSitewideAsyncIntent(',
      'await showDialog<bool>(',
      'final liveProvider = widget.provider',
      'liveProvider.commitSitewideAsyncIntent(intent, ()',
      '_footerNavigationSourceSnapshot(',
      '_findFooterNavigation(',
      'liveProvider.deleteFooterNavItem(liveNavigation)',
    ]);

    final creation = _slice(
      source,
      'Future<void> _showFooterNavDialog({',
      '@override\n  void dispose()',
    );
    _expectOrdered(creation, <String>[
      '_footerNavigationSourceSnapshot(',
      'captureSitewideAsyncIntent(',
      'await showDialog<void>(',
      'final liveProvider = widget.provider',
      'liveProvider.commitSitewideAsyncIntent(',
      '_footerNavigationSourceSnapshot(',
      'liveProvider.createFooterNavDraft(nav)',
    ]);
  });

  test('public footer async writers use sitewide capture and live commit', () {
    final source = File(
      'lib/public_store/widgets/public_store_layout.dart',
    ).readAsStringSync();

    final methods = <String>[
      _slice(
        source,
        'Future<void> _showInlineFooterNavDestinationDialog(',
        'WebsiteNavigation? _findFooterNavigationById(',
      ),
      _slice(
        source,
        'Future<void> _showFooterContactEditDialog(',
        'String _getHintForFooterContactSetting(',
      ),
      _slice(
        source,
        'Future<void> _showSocialMediaEditDialog(',
        'String _getHintForSetting(',
      ),
    ];

    _expectOrdered(methods.first, <String>[
      'final openingSnapshot = jsonEncode(',
      'await WebsiteLinkValueEditor.pickLink(',
      'liveWebsiteService = this.context.read<WebsiteService>()',
      'final liveBase = _findFooterNavigationById(',
      'jsonEncode(_footerNavigationIntentSnapshot(live)) !=',
      'openingSnapshot',
    ]);

    for (final method in methods) {
      _expectOrdered(method, <String>[
        'captureSitewideAsyncIntent(',
        'await ',
        'liveProvider = this.context.read<WebsiteEditModeProvider>()',
        'liveProvider.commitSitewideAsyncIntent(intent, ()',
      ]);
      expect(
        method.substring(method.indexOf('await ')),
        isNot(contains('editProvider.update')),
      );
    }
  });
}
