import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/website_action_button.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_content_presenters.dart';
import 'package:vinabike_erp/modules/website/widgets/website_block_renderer.dart';
import 'package:vinabike_erp/modules/website/widgets/website_canvas_editor_binding.dart';
import 'package:vinabike_erp/modules/website/widgets/website_carousel_edit_binding.dart';

Widget _host({
  required Map<String, dynamic> data,
  bool previewMode = false,
  MediaQueryData mediaQueryData = const MediaQueryData(
    size: Size(834, 900),
  ),
  WebsiteBlockContentPresenters? presenters,
  WebsiteCarouselEditBinding? editBinding,
  ValueChanged<String>? onNavigate,
  ThemeData? theme,
}) {
  return MaterialApp(
    theme: theme,
    home: MediaQuery(
      data: mediaQueryData,
      child: Scaffold(
        body: SizedBox(
          height: 520,
          width: double.infinity,
          child: WebsiteCarouselBlockContent(
            data: data,
            primaryColor: const Color(0xFF123456),
            accentColor: const Color(0xFF00A09D),
            previewMode: previewMode,
            onNavigate: onNavigate,
            presenters: presenters,
            editBinding: editBinding,
          ),
        ),
      ),
    ),
  );
}

/// An Edit binding that owns nothing but the transient selection.
///
/// The Canvas write path is a set of atomic commands addressed by layer
/// identity; there is no callback that hands back a rebuilt `elements` list.
/// These tests only need the binding to exist, so every command is omitted —
/// the Canvas then simply has no way to mutate a document from here.
WebsiteCanvasEditorBinding _inertCanvasBinding(int _) {
  return WebsiteCanvasEditorBinding(
    activeElementId: null,
    onActiveElementChanged: (_) {},
  );
}

void main() {
  testWidgets('empty slides stay empty without fabricated visitor content',
      (tester) async {
    await tester.pumpWidget(
      _host(
        data: const <String, dynamic>{
          'slides': <Map<String, dynamic>>[],
        },
      ),
    );

    expect(
      find.byKey(WebsiteCarouselBlockContent.rootKey),
      findsNothing,
    );
    expect(find.byType(WebsiteActionButton), findsNothing);
    expect(find.text('Descubre la tienda'), findsNothing);
    expect(find.text('Título del Banner'), findsNothing);
    expect(find.text('Ver catálogo'), findsNothing);
    expect(find.text('Ver más'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('slide selection is transient and creates no dirty or undo state',
      (tester) async {
    const blocks = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'carousel-1',
        'block_type': 'carousel',
        'block_data': <String, dynamic>{
          'autoPlay': false,
          'showArrows': true,
          'slides': <Map<String, dynamic>>[
            <String, dynamic>{'title': 'Primero'},
            <String, dynamic>{'title': 'Segundo'},
          ],
        },
        'order_index': 0,
      },
    ];
    const carouselData = <String, dynamic>{
      'autoPlay': false,
      'showArrows': true,
      'slides': <Map<String, dynamic>>[
        <String, dynamic>{'title': 'Primero'},
        <String, dynamic>{'title': 'Segundo'},
      ],
    };
    final provider = WebsiteEditModeProvider()
      ..enterEditMode(blocks, const <String, dynamic>{});
    addTearDown(provider.dispose);
    final baseline = provider.blocks;

    await tester.pumpWidget(
      ChangeNotifierProvider<WebsiteEditModeProvider>.value(
        value: provider,
        child: Consumer<WebsiteEditModeProvider>(
          builder: (context, document, _) {
            return _host(
              data: carouselData,
              editBinding: WebsiteCarouselEditBinding(
                selectedSlideIndex:
                    document.carouselSlideSelection('carousel-1', 2),
                onSlideSelected: (index) =>
                    document.selectCarouselSlide('carousel-1', index, 2),
                canvasBindingForSlide: _inertCanvasBinding,
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(
      find.byKey(WebsiteCarouselBlockContent.nextButtonKey),
    );
    await tester.pump();

    expect(provider.carouselSlideSelection('carousel-1', 2), 1);
    expect(provider.blocks, baseline);
    expect(provider.hasPageDraftChanges, isFalse);
    expect(provider.hasUnsavedChanges, isFalse);
    expect(provider.canUndo, isFalse);
    expect(provider.canRedo, isFalse);
    expect(find.text('SEGUNDO'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an authored CTA with an empty href stays inert', (tester) async {
    final navigations = <String>[];
    final presenters = WebsiteBlockContentPresenters(
      action: (context, slot) => slot.child,
    );

    await tester.pumpWidget(
      _host(
        data: const <String, dynamic>{
          'autoPlay': false,
          'slides': <Map<String, dynamic>>[
            <String, dynamic>{
              'title': 'Campaña',
              'ctaText': 'Ver detalles',
              'ctaLink': '',
            },
          ],
        },
        presenters: presenters,
        onNavigate: navigations.add,
      ),
    );

    final action = tester.widget<WebsiteActionButton>(
      find.byType(WebsiteActionButton),
    );
    expect(action.action.href, isEmpty);
    expect(action.onPressed, isNull);
    await tester.tap(find.byType(WebsiteActionButton));
    await tester.pump();
    expect(navigations, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'reduced motion stops autoplay while manual arrows remain functional',
    (tester) async {
      await tester.pumpWidget(
        _host(
          mediaQueryData: const MediaQueryData(
            size: Size(834, 900),
            disableAnimations: true,
          ),
          data: const <String, dynamic>{
            'autoPlay': true,
            'intervalSeconds': 1,
            'showArrows': true,
            'animationDurationMs': 600,
            'slides': <Map<String, dynamic>>[
              <String, dynamic>{'title': 'Primero'},
              <String, dynamic>{'title': 'Segundo'},
            ],
          },
        ),
      );

      expect(find.text('PRIMERO'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('PRIMERO'), findsOneWidget);
      expect(find.text('SEGUNDO'), findsNothing);

      await tester.tap(
        find.byKey(WebsiteCarouselBlockContent.nextButtonKey),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('SEGUNDO'), findsOneWidget);
      expect(find.text('PRIMERO'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a VALID slide CTA renders the SAME enabled visitor styling in Edit and '
    'Preview: Edit activation is a pure no-op, empty href stays disabled',
    (tester) async {
      final routes = <String>[];
      const validData = <String, dynamic>{
        'autoPlay': false,
        'slides': <Map<String, dynamic>>[
          <String, dynamic>{
            'title': 'Campaña',
            'ctaText': 'Ver cámaras',
            'ctaLink': '/productos/categoria/camaras',
          },
        ],
      };
      final editPresenters = WebsiteBlockContentPresenters(
        action: (context, slot) => slot.child,
      );

      ({VoidCallback? onPressed, Color? foreground, Color? labelColor})
          readCta() {
        final action = tester.widget<WebsiteActionButton>(
          find.byType(WebsiteActionButton),
        );
        final material = tester.widget<ButtonStyleButton>(
          find.bySubtype<ButtonStyleButton>(),
        );
        // The EFFECTIVE rendered label color: the RenderParagraph carries
        // the fully resolved span style, including what the button's state
        // (enabled vs disabled) projected through DefaultTextStyle. The
        // empty-href phase renders a different label, so the read is
        // conditional on the valid CTA's label being mounted.
        final labelFinder = find.text('VER CÁMARAS');
        final labelColor = labelFinder.evaluate().isEmpty
            ? null
            : tester
                .renderObject<RenderParagraph>(labelFinder)
                .text
                .style
                ?.color;
        return (
          onPressed: action.onPressed,
          foreground:
              material.style?.foregroundColor?.resolve(const <WidgetState>{}),
          labelColor: labelColor,
        );
      }

      // EDIT (presenters injected): enabled-looking, inert.
      await tester.pumpWidget(
        _host(
          data: validData,
          presenters: editPresenters,
          onNavigate: routes.add,
        ),
      );
      final edit = readCta();
      expect(edit.onPressed, isNotNull,
          reason: 'a VALID destination must not render as Material-disabled '
              'in Edit');
      // Direct callback: the shared activation target is a pure no-op.
      edit.onPressed!();
      await tester.pump();
      // Pointer tap.
      await tester.tap(find.byType(WebsiteActionButton));
      await tester.pump();
      expect(routes, isEmpty,
          reason: 'the Edit no-op owns zero navigation on any activation');
      // REAL keyboard activation: focus the actual button, then Enter and
      // Space as real key events.
      final buttonFocus = Focus.of(
        tester.element(find.text('VER CÁMARAS')),
      );
      buttonFocus.requestFocus();
      await tester.pump();
      expect(buttonFocus.hasFocus, isTrue,
          reason: 'the real button must own keyboard focus');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(routes, isEmpty,
          reason: 'Enter on the focused Edit CTA never navigates');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(routes, isEmpty,
          reason: 'Space on the focused Edit CTA never navigates');

      // PREVIEW (visitor): same rendered styling, real navigation callback.
      await tester.pumpWidget(
        _host(
          data: validData,
          previewMode: true,
          onNavigate: routes.add,
        ),
      );
      final preview = readCta();
      expect(preview.onPressed, isNotNull);
      expect(preview.foreground, edit.foreground,
          reason: 'Edit and Preview must resolve the IDENTICAL enabled '
              'foreground');
      expect(edit.foreground, Colors.white,
          reason: 'the authored slide CTA foreground is white');
      expect(preview.labelColor, edit.labelColor,
          reason: 'the RENDERED label color must be identical in Edit and '
              'Preview');
      expect(edit.labelColor, Colors.white,
          reason: 'the effective painted CTA label is exactly white');

      // Empty href stays truly disabled, also under Edit presenters.
      await tester.pumpWidget(
        _host(
          data: const <String, dynamic>{
            'autoPlay': false,
            'slides': <Map<String, dynamic>>[
              <String, dynamic>{
                'title': 'Campaña',
                'ctaText': 'Ver detalles',
                'ctaLink': '',
              },
            ],
          },
          presenters: editPresenters,
          onNavigate: routes.add,
        ),
      );
      expect(readCta().onPressed, isNull,
          reason: 'an empty href keeps the disabled affordance in Edit');
      expect(routes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the arrow affordance has ONE owner: identical style with and without '
    'the edit binding under light/dark ambient themes, and real composed '
    'contrast over white and black media',
    (tester) async {
      const data = <String, dynamic>{
        'autoPlay': false,
        'showArrows': true,
        'slides': <Map<String, dynamic>>[
          <String, dynamic>{'title': 'Primero'},
          <String, dynamic>{'title': 'Segundo'},
        ],
      };

      ({Color surface, Color foreground, Color boundary, BoxShape shape})
          readArrow() {
        final container = tester.widget<Container>(
          find.descendant(
            of: find.byKey(WebsiteCarouselBlockContent.nextButtonKey),
            matching: find.byType(Container),
          ),
        );
        final decoration = container.decoration! as BoxDecoration;
        final icon = tester.widget<Icon>(
          find.descendant(
            of: find.byKey(WebsiteCarouselBlockContent.nextButtonKey),
            matching: find.byType(Icon),
          ),
        );
        return (
          surface: decoration.color!,
          foreground: icon.color!,
          boundary: (decoration.border! as Border).top.color,
          shape: decoration.shape,
        );
      }

      final styles = <({
        Color surface,
        Color foreground,
        Color boundary,
        BoxShape shape
      })>[];
      for (final theme in <ThemeData>[ThemeData.light(), ThemeData.dark()]) {
        for (final withBinding in <bool>[false, true]) {
          await tester.pumpWidget(
            _host(
              data: data,
              theme: theme,
              editBinding: withBinding
                  ? WebsiteCarouselEditBinding(
                      selectedSlideIndex: 0,
                      onSlideSelected: (_) {},
                      canvasBindingForSlide: _inertCanvasBinding,
                    )
                  : null,
            ),
          );
          await tester.pump();
          styles.add(readArrow());
        }
      }

      // EXACT parity: the editor binding and the ambient theme must never
      // recolor the visitor navigation control.
      final reference = styles.first;
      for (final style in styles.skip(1)) {
        expect(style.surface, reference.surface);
        expect(style.foreground, reference.foreground);
        expect(style.boundary, reference.boundary);
        expect(style.shape, reference.shape);
      }
      expect(
        reference.surface,
        WebsiteCarouselBlockContent.arrowSurfaceColor,
        reason: 'the shared owner is the single source of the style',
      );
      expect(
        reference.boundary,
        WebsiteCarouselBlockContent.arrowBoundaryColor,
      );

      // Real composition: WCAG relative luminance over the effective colors.
      double channel(double c) =>
          c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4).toDouble();
      double luminance(Color c) =>
          0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
      double ratio(Color a, Color b) {
        final la = luminance(a);
        final lb = luminance(b);
        final hi = max(la, lb);
        final lo = min(la, lb);
        return (hi + 0.05) / (lo + 0.05);
      }

      for (final media in <Color>[Colors.white, Colors.black]) {
        final surfaceOnMedia = Color.alphaBlend(reference.surface, media);
        final boundaryOnMedia = Color.alphaBlend(reference.boundary, media);
        expect(
          ratio(reference.foreground, surfaceOnMedia),
          greaterThanOrEqualTo(3.0),
          reason: 'the glyph must stay readable on its own scrim over '
              '$media photography',
        );
        expect(
          max(ratio(surfaceOnMedia, media), ratio(boundaryOnMedia, media)),
          greaterThanOrEqualTo(3.0),
          reason: 'scrim OR boundary ring must separate the control from '
              '$media photography',
        );
      }
      expect(tester.takeException(), isNull);
    },
  );
}
