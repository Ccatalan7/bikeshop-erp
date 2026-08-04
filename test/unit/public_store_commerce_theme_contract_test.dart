import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vinabike_erp/modules/website/theme/website_commerce_theme.dart';
import 'package:vinabike_erp/modules/website/theme/website_resolved_theme.dart';
import 'package:vinabike_erp/modules/website/theme/website_theme_builder.dart';
import 'package:vinabike_erp/public_store/theme/public_store_surface_theme.dart';
import '../support/library_source.dart';

void main() {
  double contrastRatio(Color a, Color b) {
    final aLuminance = a.computeLuminance();
    final bLuminance = b.computeLuminance();
    final lighter = aLuminance > bLuminance ? aLuminance : bLuminance;
    final darker = aLuminance > bLuminance ? bLuminance : aLuminance;
    return (lighter + 0.05) / (darker + 0.05);
  }

  testWidgets('commerce tokens follow the nearest editor-owned ThemeData',
      (tester) async {
    const primary = Color(0xFF6C3EC1);
    const onPrimary = Color(0xFFFFF8FF);
    const surface = Color(0xFF16121C);
    const onSurface = Color(0xFFF0E9F7);
    const onSurfaceVariant = Color(0xFFC9BDCF);
    const line = Color(0xFF5E5267);
    const headingFamily = 'Editor Heading';
    const bodyFamily = 'Editor Body';

    PublicStoreSurfaceTheme? captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: surface,
          colorScheme: const ColorScheme.dark(
            primary: primary,
            onPrimary: onPrimary,
            surface: surface,
            onSurface: onSurface,
            onSurfaceVariant: onSurfaceVariant,
            outlineVariant: line,
          ),
          textTheme: const TextTheme(
            headlineMedium: TextStyle(fontFamily: headingFamily),
            bodyMedium: TextStyle(fontFamily: bodyFamily),
          ),
        ),
        home: Builder(
          builder: (context) {
            captured = PublicStoreSurfaceTheme.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(captured, isNotNull);
    expect(captured!.canvas, surface);
    expect(captured!.surface, surface);
    expect(captured!.primary, primary);
    expect(captured!.onPrimary, onPrimary);
    expect(captured!.textPrimary, onSurface);
    expect(captured!.textSecondary, onSurfaceVariant);
    expect(captured!.line, line);
    expect(captured!.text.headlineMedium?.fontFamily, headingFamily);
    expect(captured!.text.bodyMedium?.fontFamily, bodyFamily);
    expect(
      contrastRatio(captured!.success, captured!.surface),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrastRatio(captured!.onWarningSurface, captured!.warningSurface),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('cart checkout and product detail do not pin core brand colors', () {
    const paths = [
      'lib/public_store/pages/cart_page.dart',
      'lib/public_store/pages/checkout_page.dart',
      'lib/public_store/pages/product_detail_page.dart',
    ];

    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        contains('PublicStoreSurfaceTheme'),
        reason: '$path must consume the shared theme projection',
      );
      expect(source, isNot(contains('0xFF093357')), reason: path);
      expect(source, isNot(contains('0xFF123F68')), reason: path);
      expect(source, isNot(contains('_logoBlue')), reason: path);
      expect(source, isNot(contains('_catalogBlue')), reason: path);
      expect(source, isNot(contains('PublicStoreTheme.text')), reason: path);
      expect(source, isNot(contains('Colors.black87')), reason: path);
      expect(source, isNot(contains('Colors.white')), reason: path);
    }
  });

  test('product-detail palette round-trips through the editor-owned theme', () {
    const accent = Color(0xFF123F68);
    const text = Color(0xFF1E293B);
    const line = Color(0xFFE8E2D8);
    final theme = WebsiteThemeBuilder.build(
      base: ThemeData.light(),
      resolved: WebsiteResolvedTheme.fallback.copyWith(
        primaryColor: const Color(0xFF2E7D32),
        accentColor: const Color(0xFFFF6F00),
        backgroundColor: Colors.white,
        commerceAccentColor: accent,
        commerceTextColor: text,
        commerceLineColor: line,
      ),
    );
    final commerce = theme.extension<WebsiteCommerceTheme>();

    expect(commerce, isNotNull);
    expect(commerce!.accent, accent);
    expect(commerce.textPrimary, text);
    expect(commerce.line, line);

    final editorSource = readLibrarySource(
      'lib/modules/website/widgets/website_editor_panel.dart',
    );
    final layoutSource = readLibrarySource(
      'lib/public_store/widgets/public_store_layout.dart',
    );
    final resolvedThemeSource = File(
      'lib/modules/website/theme/website_resolved_theme.dart',
    ).readAsStringSync();
    final detailSource = File(
      'lib/public_store/pages/product_detail_page.dart',
    ).readAsStringSync();
    for (final key in const [
      'theme_product_detail_accent_color',
      'theme_product_detail_text_color',
      'theme_product_detail_line_color',
    ]) {
      expect(editorSource, contains(key), reason: key);
      expect(resolvedThemeSource, contains(key), reason: key);
    }
    expect(layoutSource, contains('WebsiteResolvedTheme.resolve'));
    expect(detailSource, contains('commerceAccent'));
    expect(detailSource, contains('commerceTextPrimary'));
    expect(detailSource, contains('commerceLine'));
  });

  test('only the product media feedback shadow keeps a black overlay', () {
    final source = File(
      'lib/public_store/pages/product_detail_page.dart',
    ).readAsStringSync();

    expect(
      RegExp(r'Colors\.black(?!87)').allMatches(source).length,
      1,
    );
    expect(
      source,
      contains('Colors.black.withValues(alpha: 0.16)'),
    );
  });
}
