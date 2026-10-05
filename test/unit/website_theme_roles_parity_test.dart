import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/theme/website_resolved_theme.dart';
import 'package:vinabike_erp/modules/website/theme/website_theme_builder.dart';
import 'package:vinabike_public_core/modules/website/theme/website_theme_roles.dart';

/// The HTML storefront draws the editor theme from the core
/// ([WebsiteThemeRoles]); the Flutter store from [WebsiteThemeBuilder]. Both
/// must give the same color for the same settings, decimals included.
void main() {
  const themes = <String, Map<String, String>>{
    // Viñabike's saved theme on 2026-10-05.
    'vinabike': {
      'theme_primary_color': '4279385960',
      'theme_accent_color': '4294930176',
      'theme_background_color': '4294967295',
      'theme_text_color': '3707764736',
      'theme_body_size': '16',
      'theme_heading_size': '48',
      'theme_container_padding': '24',
      'theme_section_spacing': '64',
    },
    'sin tema': {},
    'fondo oscuro sin texto': {
      'theme_background_color': '#101418',
      'theme_primary_color': '#F4C430',
      'theme_container_padding': '200',
      'theme_body_size': 'x',
    },
  };

  for (final entry in themes.entries) {
    test('${entry.key}: the core roles are the Flutter theme roles', () {
      final settings = entry.value;
      final resolved = WebsiteResolvedTheme.resolve(
        (key, fallback) => settings[key] ?? fallback,
      );
      final scheme = WebsiteThemeBuilder.build(
        base: ThemeData(useMaterial3: true),
        resolved: resolved,
      ).colorScheme;
      final roles = WebsiteThemeRoles.resolve((key) => settings[key] ?? '');

      void same(String role, WebsiteRgba core, Color flutter) {
        expect(core.a, closeTo(flutter.a, 1e-9), reason: '$role alpha');
        expect(core.r, closeTo(flutter.r, 1e-9), reason: '$role red');
        expect(core.g, closeTo(flutter.g, 1e-9), reason: '$role green');
        expect(core.b, closeTo(flutter.b, 1e-9), reason: '$role blue');
      }

      same('primary', roles.primary, scheme.primary);
      same('onPrimary', roles.onPrimary, scheme.onPrimary);
      same('accent', roles.accent, scheme.secondary);
      same('onAccent', roles.onAccent, scheme.onSecondary);
      same('surface', roles.background, scheme.surface);
      same('onSurface', roles.onSurface, scheme.onSurface);
      same('onSurfaceVariant', roles.onSurfaceVariant, scheme.onSurfaceVariant);
      same('surfaceContainerLow', roles.surfaceContainerLow,
          scheme.surfaceContainerLow);
      same('surfaceContainer', roles.surfaceContainer, scheme.surfaceContainer);
      same('surfaceContainerHigh', roles.surfaceContainerHigh,
          scheme.surfaceContainerHigh);
      same('outline', roles.outline, scheme.outline);
      same('outlineVariant', roles.outlineVariant, scheme.outlineVariant);
      expect(roles.headingFont, resolved.headingFont);
      expect(roles.bodyFont, resolved.bodyFont);
      expect(roles.headingSize, resolved.headingSize);
      expect(roles.bodySize, resolved.bodySize);
      expect(roles.sectionSpacing, resolved.sectionSpacing);
      expect(roles.containerPadding, resolved.containerPadding);
      expect(roles.buttonStyle, resolved.buttonStyle);
      expect(roles.buttonSize, resolved.buttonSize);
    });
  }

  test('a role is written for CSS with Flutter decimals', () {
    final roles = WebsiteThemeRoles.resolve(
      (key) => {
            'theme_text_color': '3707764736',
            'theme_background_color': '4294967295',
          }[key] ??
          '',
    );
    expect(roles.surfaceContainerLow.css, 'rgb(246.075 246.075 246.075 / 0.995)');
    expect(roles.background.css, 'rgb(255 255 255)');
  });
}
