import 'package:flutter/material.dart';
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
}) {
  return MaterialApp(
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

WebsiteCanvasEditorBinding _inertCanvasBinding(int _) {
  return WebsiteCanvasEditorBinding(
    activeElementId: null,
    onElementsChanged: (_) {},
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
}
