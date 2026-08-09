import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vinabike_erp/modules/website/theme/website_resolved_theme.dart';
import 'package:vinabike_erp/modules/website/theme/website_theme_builder.dart';
import 'package:vinabike_erp/modules/website/widgets/google_reviews_carousel.dart';
import 'package:vinabike_erp/shared/themes/app_theme.dart';
import 'package:vinabike_erp/shared/themes/appearance_preset.dart';

void main() {
  Map<String, dynamic> reviewsData({String? backgroundColor}) =>
      <String, dynamic>{
        'title': 'Reseñas',
        'rating': 4.0,
        'totalReviews': 187,
        'minRating': 4,
        if (backgroundColor != null) 'backgroundColor': backgroundColor,
        'reviews': <Map<String, dynamic>>[
          <String, dynamic>{
            'author_name': 'Carla Pérez',
            'rating': 4,
            'text': 'Quedó impecable.',
            'relative_time': 'hace 2 semanas',
          },
        ],
      };

  WebsiteResolvedTheme resolvedTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return WebsiteResolvedTheme.fallback.copyWith(
      // These pairs deliberately require opposite foregrounds. The avatar
      // must therefore use onSecondary, never the primary foreground.
      primaryColor: isDark ? Colors.amber.shade300 : Colors.deepPurple.shade800,
      accentColor: isDark ? Colors.deepPurple.shade700 : Colors.amber.shade300,
      backgroundColor: isDark ? Colors.blueGrey.shade900 : Colors.grey.shade100,
      textColor: isDark ? Colors.grey.shade100 : Colors.blueGrey.shade900,
    );
  }

  ThemeData websiteTheme(WebsiteResolvedTheme resolved) =>
      WebsiteThemeBuilder.build(
        base: AppTheme.resolve(
          preset: AppearancePresets.pacific,
          brightness: ThemeData.estimateBrightnessForColor(
            resolved.backgroundColor,
          ),
        ),
        resolved: resolved,
      );

  Future<({ThemeData theme, WebsiteResolvedTheme resolved})> pumpCarousel(
    WidgetTester tester, {
    required Brightness brightness,
    required double width,
    bool previewMode = false,
    String? backgroundColor,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);

    final resolved = resolvedTheme(brightness);
    final theme = websiteTheme(resolved);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: GoogleReviewsCarousel(
              data: reviewsData(backgroundColor: backgroundColor),
              primaryColor: resolved.primaryColor,
              accentColor: resolved.accentColor,
              previewMode: previewMode,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (theme: theme, resolved: resolved);
  }

  Container rootContainer(WidgetTester tester) => tester.widget<Container>(
        find
            .descendant(
              of: find.byType(GoogleReviewsCarousel),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Container &&
                    widget.constraints?.maxWidth == double.infinity &&
                    widget.color != null,
              ),
            )
            .first,
      );

  BoxDecoration reviewCardDecoration(WidgetTester tester) => tester
      .widget<Container>(
        find
            .descendant(
              of: find.byType(ListView),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Container && widget.constraints?.maxWidth == 320,
              ),
            )
            .first,
      )
      .decoration! as BoxDecoration;

  group('GoogleReviewsCarousel theme consumption', () {
    for (final brightness in Brightness.values) {
      testWidgets('$brightness uses Website surface, ink and border roles',
          (tester) async {
        addTearDown(tester.view.reset);
        final (:theme, :resolved) = await pumpCarousel(
          tester,
          brightness: brightness,
          width: 834,
        );
        final scheme = theme.colorScheme;

        expect(rootContainer(tester).color, scheme.surface);

        final card = reviewCardDecoration(tester);
        expect(card.color, scheme.surfaceContainer);
        expect((card.border! as Border).top.color, scheme.outlineVariant);
        expect(
          card.boxShadow!.single.color,
          scheme.shadow.withValues(alpha: 0.05),
        );

        expect(
          tester.widget<Text>(find.text('RESEÑAS')).style?.color,
          scheme.onSurface,
        );
        expect(
          tester.widget<Text>(find.text('Quedó impecable.')).style?.color,
          scheme.onSurface,
        );
        expect(
          tester.widget<Text>(find.text('hace 2 semanas')).style?.color,
          scheme.onSurfaceVariant,
        );

        expect(
          tester.widget<Text>(find.text('4.0')).style?.color,
          resolved.primaryColor,
        );
        final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
        expect(avatar.backgroundColor, resolved.accentColor);
        expect(
          tester
              .widget<Text>(
                find.descendant(
                  of: find.byType(CircleAvatar),
                  matching: find.text('C'),
                ),
              )
              .style
              ?.color,
          scheme.onSecondary,
        );
        expect(scheme.onPrimary, isNot(scheme.onSecondary));

        final reviewStars = tester.widgetList<Icon>(
          find.descendant(
            of: find.byType(ListView),
            matching: find.byIcon(Icons.star),
          ),
        );
        expect(
          reviewStars.map((icon) => icon.color),
          contains(const Color(0xFFFBBC04)),
        );
        expect(
          reviewStars.map((icon) => icon.color),
          contains(scheme.outlineVariant),
        );
        expect(
          tester.widget<Text>(find.text('G')).style?.color,
          const Color(0xFF4285F4),
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('opposite authored surface uses the inverse Website ink role',
        (tester) async {
      addTearDown(tester.view.reset);
      final result = await pumpCarousel(
        tester,
        brightness: Brightness.light,
        width: 834,
        backgroundColor: '#102030',
      );

      expect(rootContainer(tester).color, const Color(0xFF102030));
      expect(
        tester.widget<Text>(find.text('RESEÑAS')).style?.color,
        result.theme.colorScheme.onInverseSurface,
      );
      expect(
        tester.widget<Text>(find.text('en Google (187 reseñas)')).style?.color,
        result.theme.colorScheme.onInverseSurface,
      );
      expect(tester.takeException(), isNull);
    });

    for (final brightness in Brightness.values) {
      for (final width in <double>[390, 834, 1440]) {
        testWidgets('$brightness at ${width.toInt()} has no overflow',
            (tester) async {
          addTearDown(tester.view.reset);
          await pumpCarousel(
            tester,
            brightness: brightness,
            width: width,
          );

          expect(find.byType(GoogleReviewsCarousel), findsOneWidget);
          expect(find.text('Quedó impecable.'), findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('Preview and public API resolve the same Website roles',
        (tester) async {
      addTearDown(tester.view.reset);
      final publicTheme = await pumpCarousel(
        tester,
        brightness: Brightness.dark,
        width: 834,
      );
      final publicSurface = rootContainer(tester).color;
      final publicCard = reviewCardDecoration(tester).color;

      final previewTheme = await pumpCarousel(
        tester,
        brightness: Brightness.dark,
        width: 834,
        previewMode: true,
      );

      expect(previewTheme.theme.colorScheme, publicTheme.theme.colorScheme);
      expect(rootContainer(tester).color, publicSurface);
      expect(reviewCardDecoration(tester).color, publicCard);
      expect(tester.takeException(), isNull);
    });
  });
}
