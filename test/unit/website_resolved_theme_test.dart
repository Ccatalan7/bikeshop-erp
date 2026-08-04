import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/models/website_font_registry.dart';
import 'package:vinabike_erp/modules/website/models/website_page_composition.dart';
import 'package:vinabike_erp/modules/website/theme/website_resolved_theme.dart';
import 'package:vinabike_erp/modules/website/theme/website_theme_builder.dart';

void main() {
  WebsiteResolvedTheme resolve(Map<String, String> values) {
    return WebsiteResolvedTheme.resolve(
      (key, fallback) => values[key] ?? fallback,
    );
  }

  test('canonical defaults cover every shell and composition token', () {
    final resolved = resolve(const {});

    expect(resolved.primaryColor, WebsiteResolvedTheme.defaultPrimaryColor);
    expect(resolved.accentColor, WebsiteResolvedTheme.defaultAccentColor);
    expect(
      resolved.backgroundColor,
      WebsiteResolvedTheme.defaultBackgroundColor,
    );
    expect(resolved.textColor, WebsiteResolvedTheme.defaultTextColor);
    expect(resolved.headingFont, WebsiteFontRegistry.headingDefault);
    expect(resolved.bodyFont, WebsiteFontRegistry.bodyDefault);
    expect(resolved.headingSize, 48);
    expect(resolved.bodySize, 16);
    expect(
      resolved.sectionSpacing,
      WebsitePageComposition.defaultSectionSpacing,
    );
    expect(resolved.containerPadding, 24);
    expect(resolved.buttonStyle, 'rounded');
    expect(resolved.buttonSize, 'medium');
  });

  test('reader precedence projects staged values without mutating saved data',
      () {
    const saved = <String, String>{
      'theme_primary_color': '#112233',
      'theme_heading_size': '42',
    };
    const pending = <String, String>{
      'theme_primary_color': '#445566',
      'theme_heading_size': '60',
    };

    final publicTheme = WebsiteResolvedTheme.resolve(
      (key, fallback) => saved[key] ?? fallback,
    );
    final editorTheme = WebsiteResolvedTheme.resolve(
      (key, fallback) => pending[key] ?? saved[key] ?? fallback,
    );

    expect(publicTheme.primaryColor, const Color(0xFF112233));
    expect(publicTheme.headingSize, 42);
    expect(editorTheme.primaryColor, const Color(0xFF445566));
    expect(editorTheme.headingSize, 60);
    expect(saved['theme_primary_color'], '#112233');
  });

  test('legacy color formats remain deterministic, including digit-only hex',
      () {
    expect(
      resolve(const {'theme_primary_color': '123456'}).primaryColor,
      const Color(0xFF123456),
    );
    expect(
      resolve(const {'theme_primary_color': '12345678'}).primaryColor,
      const Color(0x12345678),
    );
    expect(
      resolve(const {'theme_primary_color': '#ABCDEF'}).primaryColor,
      const Color(0xFFABCDEF),
    );
    expect(
      resolve(const {'theme_primary_color': '0xFF010203'}).primaryColor,
      const Color(0xFF010203),
    );
    expect(
      resolve(const {'theme_primary_color': 'Color(4278256131)'}).primaryColor,
      const Color(0xFF010203),
    );
    expect(
      resolve(const {'theme_primary_color': 'Color(0xFF010203)'}).primaryColor,
      const Color(0xFF010203),
    );
    expect(
      resolve(const {'theme_primary_color': '4278190335'}).primaryColor,
      const Color(0xFF0000FF),
    );
  });

  test('malformed values normalize through one bounded fallback contract', () {
    final resolved = resolve(const {
      'theme_primary_color': 'not-a-color',
      'theme_heading_font': 'Unbundled Font',
      'theme_body_font': 'Another Font',
      'theme_heading_size': '999',
      'theme_body_size': '-4',
      'theme_section_spacing': '999',
      'theme_container_padding': 'NaN',
      'button_style': 'blob',
      'button_size': 'huge',
    });

    expect(resolved.primaryColor, WebsiteResolvedTheme.defaultPrimaryColor);
    expect(resolved.headingFont, WebsiteFontRegistry.headingDefault);
    expect(resolved.bodyFont, WebsiteFontRegistry.bodyDefault);
    expect(resolved.headingSize, 72);
    expect(resolved.bodySize, 12);
    expect(resolved.sectionSpacing, 200);
    expect(resolved.containerPadding, 24);
    expect(resolved.buttonStyle, 'rounded');
    expect(resolved.buttonSize, 'medium');
  });

  test('implicit text fallback stays readable while explicit text stays exact',
      () {
    const darkBackground = Color(0xFF142119);

    for (final textValue in [null, 'not-a-color']) {
      final resolved = resolve({
        'theme_background_color': '#142119',
        if (textValue != null) 'theme_text_color': textValue,
      });
      expect(resolved.backgroundColor, darkBackground);
      expect(resolved.textColor, Colors.white);
      expect(
        _contrastRatio(resolved.textColor, resolved.backgroundColor),
        greaterThanOrEqualTo(4.5),
      );
    }

    final explicit = resolve(const {
      'theme_background_color': '#142119',
      'theme_text_color': '#17251B',
    });
    expect(explicit.textColor, const Color(0xFF17251B),
        reason: 'A valid editor value is never silently contrast-corrected.');
    expect(resolve(const {}).textColor, WebsiteResolvedTheme.defaultTextColor);
  });

  test('ThemeData publishes the exact resolved owner and text color', () {
    final resolved = WebsiteResolvedTheme.fallback.copyWith(
      primaryColor: const Color(0xFF315D8A),
      accentColor: const Color(0xFF9B4D22),
      backgroundColor: const Color(0xFFF8F4EA),
      textColor: const Color(0xFF30271F),
    );
    final theme = WebsiteThemeBuilder.build(
      base: ThemeData.light(useMaterial3: true),
      resolved: resolved,
    );

    expect(theme.extension<WebsiteResolvedTheme>(), same(resolved));
    expect(theme.colorScheme.primary, resolved.primaryColor);
    expect(theme.colorScheme.secondary, resolved.accentColor);
    expect(theme.colorScheme.surface, resolved.backgroundColor);
    expect(theme.colorScheme.onSurface, resolved.textColor);
    expect(theme.textTheme.bodyMedium?.color, resolved.textColor);
    expect(theme.textTheme.headlineMedium?.color, resolved.textColor);
  });

  test('public renderers consume the owner instead of parallel theme readers',
      () {
    const consumers = [
      'lib/public_store/pages/public_home_page.dart',
      'lib/public_store/pages/static_policy_page.dart',
      'lib/public_store/pages/dynamic_website_page.dart',
      'lib/public_store/pages/contact_page.dart',
    ];

    for (final path in consumers) {
      final source = File(path).readAsStringSync();
      expect(source, contains('WebsiteResolvedTheme.of(context)'),
          reason: path);
      expect(source, isNot(contains("getSetting('theme_")), reason: path);
      expect(source, isNot(contains('Color? _parseColor(')), reason: path);
      expect(source, isNot(contains('Color _resolveColor(')), reason: path);
      expect(source, isNot(contains('Color? _tryParseColor(')), reason: path);
    }

    final shell = File(
      'lib/public_store/widgets/public_store_layout.dart',
    ).readAsStringSync();
    expect(shell, contains('WebsiteResolvedTheme.resolve(getThemeSetting)'));
    expect(shell, contains('resolved: resolvedTheme'));

    final themeControl = File(
      'lib/modules/website/widgets/editor_panel/theme_tab.dart',
    ).readAsStringSync();
    expect(themeControl, contains('WebsiteResolvedTheme.resolve('));
    expect(themeControl, contains('editProvider.isInEditorContext'));
    expect(themeControl, contains('getEffectiveThemeSetting(key, saved)'));
    expect(
      themeControl,
      contains('serializeWebsiteEditorColor(resolved.textColor)'),
    );
    expect(themeControl, contains("label: 'Color de texto'"));
    expect(
      themeControl,
      contains("updateThemeSetting('theme_text_color', val)"),
    );
    expect(themeControl, contains('_sectionSpacing = resolved.sectionSpacing'));
    expect(
      themeControl,
      contains('_containerPadding = resolved.containerPadding'),
    );
    expect(themeControl, contains("'theme_section_spacing'"));
    expect(themeControl, contains("'theme_container_padding'"));
    expect(themeControl, contains("'Espaciado base'"));
    expect(themeControl, contains("'Margen del contenedor'"));

    final service = File(
      'lib/modules/website/services/website_service.dart',
    ).readAsStringSync();
    expect(service, isNot(contains('Future<void> updateThemeSettings(')),
        reason: 'Theme writes stage through the editor owner, never a direct '
            'service bypass.');
    expect(themeControl, isNot(contains('#00A09D')));
    expect(themeControl, isNot(contains('#FF6D00')));
  });
}

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
