import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/theme/website_resolved_theme.dart';
import 'package:vinabike_erp/modules/website/theme/website_theme_builder.dart';

void main() {
  double contrastRatio(Color a, Color b) {
    final aLuminance = a.computeLuminance();
    final bLuminance = b.computeLuminance();
    final lighter = aLuminance > bLuminance ? aLuminance : bLuminance;
    final darker = aLuminance > bLuminance ? bLuminance : aLuminance;
    return (lighter + 0.05) / (darker + 0.05);
  }

  test('light website palette derives readable shared surface tokens', () {
    const background = Color(0xFFF4F1E9);
    final resolved = WebsiteResolvedTheme.fallback.copyWith(
      primaryColor: const Color(0xFF155A37),
      accentColor: const Color(0xFFC96923),
      backgroundColor: background,
    );
    final theme = WebsiteThemeBuilder.build(
      base: ThemeData.light(useMaterial3: true),
      resolved: resolved,
    );

    expect(theme.brightness, Brightness.light);
    expect(theme.colorScheme.surface, background);
    expect(theme.colorScheme.onSurface.computeLuminance(), lessThan(0.2));
    expect(theme.colorScheme.onSurface, resolved.textColor);
    expect(theme.textTheme.bodyMedium?.color, resolved.textColor);
    expect(theme.extension<WebsiteResolvedTheme>(), same(resolved));
    expect(
      theme.colorScheme.onSurfaceVariant.computeLuminance(),
      lessThan(0.35),
    );
    expect(theme.textTheme.bodyMedium?.color, theme.colorScheme.onSurface);
    expect(theme.cardTheme.color, theme.colorScheme.surfaceContainerLow);
    expect(
      theme.dividerTheme.color,
      theme.colorScheme.outlineVariant,
    );
    expect(
      theme.inputDecorationTheme.fillColor,
      theme.colorScheme.surfaceContainerLow,
    );
  });

  test('dark website palette updates components and contrast as one theme', () {
    const background = Color(0xFF142119);
    const settings = <String, String>{
      'theme_primary_color': '#91D6A9',
      'theme_accent_color': '#FFC27D',
      'theme_background_color': '#142119',
    };
    final resolved = WebsiteResolvedTheme.resolve(
      (key, fallback) => settings[key] ?? fallback,
    );
    final theme = WebsiteThemeBuilder.build(
      base: ThemeData.light(useMaterial3: true),
      resolved: resolved,
    );

    expect(theme.brightness, Brightness.dark);
    expect(resolved.textColor, Colors.white,
        reason: 'An absent text setting resolves against the dark background.');
    expect(theme.colorScheme.onSurface, Colors.white);
    expect(theme.colorScheme.onSurface, resolved.textColor);
    expect(
      theme.colorScheme.onSurfaceVariant.computeLuminance(),
      greaterThan(0.55),
    );
    expect(theme.textTheme.titleLarge?.color, Colors.white);
    expect(theme.appBarTheme.backgroundColor, background);
    expect(theme.appBarTheme.foregroundColor, Colors.white);
    expect(
        theme.chipTheme.backgroundColor, theme.colorScheme.surfaceContainerLow);

    final enabledBorder =
        theme.inputDecorationTheme.enabledBorder as OutlineInputBorder;
    expect(enabledBorder.borderSide.color, theme.colorScheme.outlineVariant);
    expect(theme.iconTheme.color, theme.colorScheme.onSurfaceVariant);
  });

  test('primary and accent controls derive their own readable foregrounds', () {
    final theme = WebsiteThemeBuilder.build(
      base: ThemeData.light(useMaterial3: true),
      resolved: WebsiteResolvedTheme.fallback.copyWith(
        primaryColor: Colors.black,
        accentColor: Colors.white,
        backgroundColor: Colors.white,
      ),
    );

    expect(theme.colorScheme.onPrimary, Colors.white);
    expect(theme.colorScheme.onSecondary.computeLuminance(), lessThan(0.2));
  });

  test('editor colors keep normal text contrast across light and dark tones',
      () {
    const backgrounds = [
      Color(0xFFF4F1E9),
      Color(0xFF8B9A78),
      Color(0xFF365B49),
      Color(0xFF142119),
    ];

    for (final background in backgrounds) {
      final textColor = contrastRatio(Colors.white, background) >=
              contrastRatio(Colors.black, background)
          ? Colors.white
          : Colors.black;
      final theme = WebsiteThemeBuilder.build(
        base: ThemeData.light(useMaterial3: true),
        resolved: WebsiteResolvedTheme.fallback.copyWith(
          primaryColor: background,
          accentColor: background,
          backgroundColor: background,
          textColor: textColor,
        ),
      );

      expect(
        contrastRatio(theme.colorScheme.onSurface, background),
        greaterThanOrEqualTo(4.5),
        reason: 'Unreadable surface foreground for $background',
      );
      expect(
        contrastRatio(theme.colorScheme.onPrimary, background),
        greaterThanOrEqualTo(4.5),
        reason: 'Unreadable primary foreground for $background',
      );
    }
  });
}
