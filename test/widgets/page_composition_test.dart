import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:vinabike_erp/modules/website/models/website_action.dart';
import 'package:vinabike_erp/modules/website/models/website_page_composition.dart';
import 'package:vinabike_erp/modules/website/providers/website_edit_mode_provider.dart';
import 'package:vinabike_erp/modules/website/widgets/block_spacer_handle.dart';
import 'package:vinabike_erp/modules/website/widgets/block_resize_handle.dart';
import 'package:vinabike_erp/modules/website/widgets/deferred_editable_block_renderer.dart';
import 'package:vinabike_erp/modules/website/widgets/inline_editable_text_v2.dart';
import 'package:vinabike_erp/modules/website/widgets/website_action_button.dart';
import 'package:vinabike_erp/modules/website/widgets/website_link_value_editor.dart';
import 'package:vinabike_erp/modules/website/widgets/website_text_block_content.dart';
import 'package:vinabike_erp/public_store/widgets/page_composition.dart';

Map<String, dynamic> _block({
  required String id,
  required String type,
  required int order,
  bool visible = true,
  Map<String, dynamic> data = const {},
}) {
  return {
    'id': id,
    'block_type': type,
    'order_index': order,
    'is_visible': visible,
    'block_data': data,
  };
}

Widget _host({
  required WebsitePageComposition composition,
  WebsiteEditModeProvider? provider,
  int? visibleBlockLimit,
  WebsitePageSpacingChanged? onSpacingChanged,
  ValueChanged<String>? onNavigate,
  bool Function(String href)? isNavigationEligible,
}) {
  final child = MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: PageComposition(
          composition: composition,
          visibleBlockLimit: visibleBlockLimit,
          primaryColor: Colors.blue,
          accentColor: Colors.green,
          textColor: Colors.black,
          containerPadding: 24,
          onAddBlock: (type, {atIndex}) {},
          onSpacingChanged: onSpacingChanged ?? (blockId, spacing) {},
          onNavigate: onNavigate,
          isNavigationEligible: isNavigationEligible,
        ),
      ),
    ),
  );
  if (provider == null) return child;
  return ChangeNotifierProvider.value(value: provider, child: child);
}

Future<void> _pumpEditableHost(
  WidgetTester tester,
  Widget host,
) async {
  await tester.runAsync(DeferredEditableBlockRenderer.preload);
  await tester.pumpWidget(host);
  for (var attempt = 0; attempt < 10; attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
}

void main() {
  testWidgets(
    'public composition paints canonical order, visibility and one gap only',
    (tester) async {
      final composition = WebsitePageComposition.project(
        blocks: [
          _block(id: 'second', type: 'divider', order: 2),
          _block(
            id: 'first',
            type: 'divider',
            order: 1,
            data: {'spacingAfter': 37},
          ),
          _block(id: 'hidden', type: 'divider', order: 0, visible: false),
        ],
        mode: WebsitePageCompositionMode.public,
        breakpoint: 'desktop',
      );

      await tester.pumpWidget(_host(composition: composition));
      await tester.pump();

      final first = find.byKey(
        const ValueKey<String>('page-composition-block-first'),
      );
      final second = find.byKey(
        const ValueKey<String>('page-composition-block-second'),
      );
      expect(first, findsOneWidget);
      expect(second, findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>('page-composition-block-hidden'),
        ),
        findsNothing,
      );
      expect(
          tester.getTopLeft(first).dy, lessThan(tester.getTopLeft(second).dy));

      final gap = tester.widget<SizedBox>(
        find.byKey(const ValueKey<String>('page-composition-gap-first')),
      );
      expect(gap.height, 37);
      expect(
        find.byKey(const ValueKey<String>('page-composition-gap-second')),
        findsNothing,
      );
    },
  );

  testWidgets('Edit adds chrome while retaining hidden blocks and geometry',
      (tester) async {
    final blocks = [
      _block(
        id: 'hero',
        type: 'hero',
        order: 0,
        visible: false,
        data: {
          'title': 'Hidden hero',
          'blockHeight': 420,
        },
      ),
    ];
    final provider = WebsiteEditModeProvider()
      ..enterEditMode(
        blocks,
        const {},
        pageId: 'page-a',
        pageSlug: 'page-a',
      );
    addTearDown(provider.dispose);
    final composition = WebsitePageComposition.project(
      blocks: provider.blocks,
      mode: WebsitePageCompositionMode.edit,
      breakpoint: 'desktop',
    );

    await _pumpEditableHost(
      tester,
      _host(composition: composition, provider: provider),
    );

    expect(
      find.byKey(const ValueKey<String>('page-composition-block-hero')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('page-composition-height-hero')),
      findsNothing,
    );
    expect(
      tester
          .getSize(
            find.byKey(
              const ValueKey<String>('page-composition-block-hero'),
            ),
          )
          .height,
      420,
    );
    expect(find.text('Agregar nuevo bloque'), findsOneWidget);
  });

  testWidgets('progressive limit never leaves a trailing inter-block gap',
      (tester) async {
    final composition = WebsitePageComposition.project(
      blocks: [
        _block(
          id: 'first',
          type: 'divider',
          order: 0,
          data: {'spacingAfter': 48},
        ),
        _block(id: 'second', type: 'divider', order: 1),
      ],
      mode: WebsitePageCompositionMode.public,
      breakpoint: 'mobile',
    );

    await tester.pumpWidget(
      _host(composition: composition, visibleBlockLimit: 1),
    );

    expect(
      find.byKey(const ValueKey<String>('page-composition-block-first')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('page-composition-block-second')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('page-composition-gap-first')),
      findsNothing,
    );
  });

  testWidgets(
    'policy adapter preserves canonical order and geometry wrappers',
    (tester) async {
      final adaptedOrder = <String>[];
      final composition = WebsitePageComposition.project(
        blocks: [
          _block(
            id: 'padded',
            type: 'about',
            order: 2,
            data: {
              'blockHeight': 120,
              'fullBleed': false,
            },
          ),
          _block(
            id: 'full',
            type: 'hero',
            order: 1,
            data: {
              'blockHeight': 240,
              'fullBleed': true,
              'spacingAfter': 8,
            },
          ),
        ],
        mode: WebsitePageCompositionMode.public,
        breakpoint: 'desktop',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageComposition(
              composition: composition,
              primaryColor: Colors.blue,
              accentColor: Colors.green,
              textColor: Colors.black,
              containerPadding: 24,
              contentAdapter: (context, block, sharedContent) {
                adaptedOrder.add(block.id);
                return SizedBox(
                  key: ValueKey<String>('adapted-${block.id}'),
                );
              },
            ),
          ),
        ),
      );

      expect(adaptedOrder, ['full', 'padded']);
      expect(
        tester
            .widget<SizedBox>(
              find.byKey(
                const ValueKey<String>('page-composition-height-full'),
              ),
            )
            .height,
        240,
      );
      expect(
        tester
            .widget<ConstrainedBox>(
              find.byKey(
                const ValueKey<String>('page-composition-height-padded'),
              ),
            )
            .constraints
            .minHeight,
        120,
      );
      expect(
        tester
            .getSize(
              find.byKey(
                const ValueKey<String>('page-composition-gap-full'),
              ),
            )
            .height,
        8,
      );
    },
  );

  testWidgets(
    'divider uses shared content in Edit and chrome still owns selection',
    (tester) async {
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          [
            _block(
              id: 'divider',
              type: 'divider',
              order: 0,
              data: {
                'thickness': 7,
                'widthPct': 0.5,
                'color': '#FF0000',
                'blockHeight': 500,
              },
            ),
          ],
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: 'page-a',
        );
      addTearDown(provider.dispose);
      final composition = WebsitePageComposition.project(
        blocks: provider.blocks,
        mode: WebsitePageCompositionMode.edit,
        breakpoint: 'desktop',
      );

      await _pumpEditableHost(
        tester,
        _host(composition: composition, provider: provider),
      );

      final divider = tester.widget<Divider>(find.byType(Divider).first);
      expect(divider.thickness, 7);
      expect(divider.color, const Color(0xFFFF0000));

      await tester.tap(
        find.byKey(
          const ValueKey<String>('page-composition-block-divider'),
        ),
      );
      await tester.pump();
      expect(provider.selectedBlockId, 'divider');
      expect(find.byType(BlockResizeHandle), findsNothing);
      expect(
        tester
            .getSize(
              find.byKey(
                const ValueKey<String>('page-composition-block-divider'),
              ),
            )
            .height,
        lessThan(500),
      );
    },
  );

  testWidgets(
    'button shares its canonical action view and commits aliases atomically',
    (tester) async {
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          [
            _block(
              id: 'button',
              type: 'button',
              order: 0,
              data: const <String, dynamic>{
                'label': 'Comprar',
                'text': 'Comprar',
                'link': '/comprar',
                'style': 'outline',
                'actions': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'type': 'navigate',
                    'label': 'Comprar',
                    'to': '/comprar',
                    'variant': 'filled',
                  },
                ],
              },
            ),
          ],
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: 'page-a',
        );
      addTearDown(provider.dispose);
      final editComposition = WebsitePageComposition.project(
        blocks: provider.blocks,
        mode: WebsitePageCompositionMode.edit,
        breakpoint: 'desktop',
      );
      var navigated = false;

      await _pumpEditableHost(
        tester,
        _host(
          composition: editComposition,
          provider: provider,
          onNavigate: (_) => navigated = true,
        ),
      );

      final block = find.byKey(
        const ValueKey<String>('page-composition-block-button'),
      );
      final actionView = find.descendant(
        of: block,
        matching: find.byType(WebsiteActionButton),
      );
      expect(actionView, findsOneWidget);
      expect(
        tester.widget<WebsiteActionButton>(actionView).action.variant,
        WebsiteActionVariant.outline,
      );
      expect(
        find.descendant(of: block, matching: find.byType(OutlinedButton)),
        findsOneWidget,
      );

      final inlineLabel = find.byKey(
        const ValueKey<String>('website-button-inline-label-button'),
      );
      await tester.tap(inlineLabel);
      await tester.pump();
      expect(navigated, isFalse);
      expect(find.text('Editar acción'), findsOneWidget);
      // The popover exposes the label field plus the canonical typed
      // destination editor; a raw href text field must not exist inline.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(WebsiteLinkValueEditor), findsOneWidget);
      expect(find.text('Destino'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Comprar ahora');
      await tester.tapAt(const Offset(10, 590));
      await tester.pumpAndSettle();

      final data = Map<String, dynamic>.from(
        provider.blocks.single['block_data'] as Map,
      );
      final savedAction = Map<String, dynamic>.from(
        (data['actions'] as List).single as Map,
      );
      expect(data['label'], 'Comprar ahora');
      expect(data['text'], 'Comprar ahora');
      expect(data['link'], '/comprar');
      expect(data['style'], 'outline');
      expect(savedAction['label'], 'Comprar ahora');
      expect(savedAction['to'], '/comprar');
      expect(savedAction['variant'], 'outline');
      expect(provider.canUndo, isTrue);

      final previewComposition = WebsitePageComposition.project(
        blocks: provider.blocks,
        mode: WebsitePageCompositionMode.preview,
        breakpoint: 'desktop',
      );
      await tester.pumpWidget(
        _host(
          composition: previewComposition,
          onNavigate: (_) {},
        ),
      );
      await tester.pump();

      final previewAction = tester.widget<WebsiteActionButton>(
        find.byType(WebsiteActionButton),
      );
      expect(previewAction.action.label, 'Comprar ahora');
      expect(previewAction.action.variant, WebsiteActionVariant.outline);
      expect(find.byType(OutlinedButton), findsOneWidget);
    },
  );

  testWidgets(
    'text shares presentation, inline commits, and responsive width in all modes',
    (tester) async {
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          [
            _block(
              id: 'text',
              type: 'text',
              order: 0,
              data: const <String, dynamic>{
                'text': 'Mensaje original',
                'preset': 'heading',
                'maxWidth': 640,
                'formatting': <String, dynamic>{
                  'bold': true,
                  'fontSize': 28,
                  'textAlign': 'center',
                },
              },
            ),
          ],
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: 'page-a',
        );
      addTearDown(provider.dispose);

      WebsitePageComposition composition(WebsitePageCompositionMode mode) =>
          WebsitePageComposition.project(
            blocks: provider.blocks,
            mode: mode,
            breakpoint: 'desktop',
          );

      await _pumpEditableHost(
        tester,
        _host(
          composition: composition(WebsitePageCompositionMode.edit),
          provider: provider,
        ),
      );

      expect(find.byType(WebsiteTextBlockContent), findsOneWidget);
      final inlineFinder = find.byKey(
        const ValueKey<String>('website-text-inline-content-text'),
      );
      final inline = tester.widget<InlineEditableTextV2>(inlineFinder);
      expect(inline.maxWidth, 640);
      expect(inline.baseStyle, isNotNull);
      expect(inline.formatting, isNotNull);
      expect(
        tester
            .getSize(
              find.byKey(
                const ValueKey<String>('website-text-width-frame-box'),
              ),
            )
            .width,
        640,
      );
      final effectiveEditStyle = inline.formatting!.applyTo(inline.baseStyle!);

      inline.onFormattingChanged!(
        inline.formatting!.copyWith(
          isItalic: true,
          textAlign: TextAlign.end,
        ),
      );
      inline.onWidthChanged!(900);
      await tester.pump();
      var data = Map<String, dynamic>.from(
        provider.blocks.single['block_data'] as Map,
      );
      expect(data['maxWidth'], 900);
      expect(data['formatting']['italic'], isTrue);
      expect(data['formatting']['textAlign'], 'end');

      await _pumpEditableHost(
        tester,
        _host(
          composition: composition(WebsitePageCompositionMode.edit),
          provider: provider,
        ),
      );
      expect(
        tester
            .getSize(
              find.byKey(
                const ValueKey<String>('website-text-width-frame-box'),
              ),
            )
            .width,
        752,
      );

      await tester.tap(inlineFinder);
      await tester.pump();
      final editable = find.descendant(
        of: inlineFinder,
        matching: find.byType(EditableText),
      );
      await tester.enterText(editable, 'Mensaje guardado');
      await tester.tapAt(const Offset(790, 590));
      await tester.pumpAndSettle();
      data = Map<String, dynamic>.from(
        provider.blocks.single['block_data'] as Map,
      );
      expect(data['text'], 'Mensaje guardado');

      await tester.pumpWidget(
        _host(
          composition: composition(WebsitePageCompositionMode.preview),
        ),
      );
      await tester.pump();
      expect(find.byType(WebsiteTextBlockContent), findsOneWidget);
      final previewText = tester.widget<Text>(
        find.text('Mensaje guardado'),
      );
      expect(previewText.textAlign, TextAlign.end);
      expect(previewText.style?.fontSize, 28);
      expect(previewText.style?.fontWeight, FontWeight.bold);
      expect(previewText.style?.fontStyle, FontStyle.italic);
      expect(
        tester
            .getSize(
              find.byKey(
                const ValueKey<String>('website-text-width-frame-box'),
              ),
            )
            .width,
        752,
      );

      await tester.pumpWidget(
        _host(
          composition: composition(WebsitePageCompositionMode.public),
        ),
      );
      await tester.pump();
      final publicText = tester.widget<Text>(
        find.text('Mensaje guardado'),
      );
      expect(publicText.style, previewText.style);
      expect(publicText.textAlign, previewText.textAlign);
      expect(effectiveEditStyle.fontSize, previewText.style?.fontSize);
    },
  );

  testWidgets('empty text placeholder belongs only to Edit chrome',
      (tester) async {
    final blocks = [
      _block(
        id: 'text',
        type: 'text',
        order: 0,
        data: const <String, dynamic>{
          'text': '',
          'preset': 'paragraph',
          'maxWidth': 400,
        },
      ),
    ];
    final provider = WebsiteEditModeProvider()
      ..enterEditMode(
        blocks,
        const <String, dynamic>{},
        pageId: 'page-a',
        pageSlug: 'page-a',
      );
    addTearDown(provider.dispose);

    await _pumpEditableHost(
      tester,
      _host(
        composition: WebsitePageComposition.project(
          blocks: provider.blocks,
          mode: WebsitePageCompositionMode.edit,
          breakpoint: 'desktop',
        ),
        provider: provider,
      ),
    );
    expect(find.text('Haz clic para escribir'), findsOneWidget);

    await tester.pumpWidget(
      _host(
        composition: WebsitePageComposition.project(
          blocks: provider.blocks,
          mode: WebsitePageCompositionMode.preview,
          breakpoint: 'desktop',
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Haz clic para escribir'), findsNothing);
    expect(find.text('Texto'), findsNothing);
  });

  testWidgets(
    'unconfigured button stays editable but is absent from Preview',
    (tester) async {
      final blocks = [
        _block(
          id: 'button',
          type: 'button',
          order: 0,
          data: const <String, dynamic>{
            'label': 'Configurar destino',
            'text': 'Configurar destino',
            'link': '',
            'style': 'filled',
            'actions': <Map<String, dynamic>>[],
          },
        ),
      ];
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          blocks,
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: 'page-a',
        );
      addTearDown(provider.dispose);

      await _pumpEditableHost(
        tester,
        _host(
          composition: WebsitePageComposition.project(
            blocks: provider.blocks,
            mode: WebsitePageCompositionMode.edit,
            breakpoint: 'desktop',
          ),
          provider: provider,
        ),
      );
      expect(find.byType(WebsiteActionButton), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>('website-button-inline-label-button'),
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(
        _host(
          composition: WebsitePageComposition.project(
            blocks: provider.blocks,
            mode: WebsitePageCompositionMode.preview,
            breakpoint: 'desktop',
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(WebsiteActionButton), findsNothing);
    },
  );

  testWidgets(
    'minimum-height capability matches between Edit and Preview',
    (tester) async {
      final blocks = [
        _block(
          id: 'faq',
          type: 'faq',
          order: 0,
          data: {
            'blockHeight': 260,
            'title': 'Preguntas',
            'items': const <Map<String, String>>[],
          },
        ),
      ];
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          blocks,
          const {},
          pageId: 'page-a',
          pageSlug: 'page-a',
        );
      addTearDown(provider.dispose);
      final editComposition = WebsitePageComposition.project(
        blocks: provider.blocks,
        mode: WebsitePageCompositionMode.edit,
        breakpoint: 'desktop',
      );
      final previewComposition = WebsitePageComposition.project(
        blocks: provider.blocks,
        mode: WebsitePageCompositionMode.preview,
        breakpoint: 'desktop',
      );
      const blockKey = ValueKey<String>('page-composition-block-faq');

      await _pumpEditableHost(
        tester,
        _host(composition: editComposition, provider: provider),
      );
      final editHeight = tester.getSize(find.byKey(blockKey)).height;

      await tester.pumpWidget(_host(composition: previewComposition));
      await tester.pump();
      final previewHeight = tester.getSize(find.byKey(blockKey)).height;

      expect(editHeight, greaterThanOrEqualTo(260));
      expect(previewHeight, greaterThanOrEqualTo(260));
    },
  );

  testWidgets('Edit spacing chrome never enlarges canonical small gaps',
      (tester) async {
    final provider = WebsiteEditModeProvider()
      ..enterEditMode(
        [
          _block(id: 'first', type: 'divider', order: 0),
          _block(id: 'second', type: 'divider', order: 1),
        ],
        const <String, dynamic>{},
        pageId: 'page-a',
        pageSlug: 'page-a',
      );
    addTearDown(provider.dispose);

    for (final spacing in <double>[0, 8, 16]) {
      provider.updateBlockData('first', 'spacingAfter', spacing);
      final composition = WebsitePageComposition.project(
        blocks: provider.blocks,
        mode: WebsitePageCompositionMode.edit,
        breakpoint: 'desktop',
      );
      await _pumpEditableHost(
        tester,
        _host(composition: composition, provider: provider),
      );

      expect(
        tester
            .getSize(
              find.byKey(
                const ValueKey<String>('page-composition-gap-first'),
              ),
            )
            .height,
        spacing,
      );
    }
  });

  testWidgets(
    'zero spacing keeps zero geometry and an operable overlaid hit target',
    (tester) async {
      double? selectedSpacing;
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          [
            _block(
              id: 'first',
              type: 'divider',
              order: 0,
              data: {'spacingAfter': 0},
            ),
            _block(id: 'second', type: 'divider', order: 1),
          ],
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: 'page-a',
        );
      addTearDown(provider.dispose);
      final composition = WebsitePageComposition.project(
        blocks: provider.blocks,
        mode: WebsitePageCompositionMode.edit,
        breakpoint: 'desktop',
      );

      await _pumpEditableHost(
        tester,
        _host(
          composition: composition,
          provider: provider,
          onSpacingChanged: (blockId, spacing) {
            expect(blockId, 'first');
            selectedSpacing = spacing;
          },
        ),
      );

      expect(
        tester
            .getSize(
              find.byKey(
                const ValueKey<String>('page-composition-gap-first'),
              ),
            )
            .height,
        0,
      );
      final handle = find.byType(BlockSpacerHandle);
      expect(tester.getSize(handle).height, 24);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      await mouse.moveTo(tester.getCenter(handle));
      await tester.pump();
      await tester.tap(find.text('S'));
      await tester.pump();

      expect(selectedSpacing, 16);
      await mouse.removePointer();
    },
  );

  testWidgets(
    'the initial insert target overlays without moving the first block',
    (tester) async {
      final blocks = [
        _block(id: 'first', type: 'divider', order: 0),
      ];
      final provider = WebsiteEditModeProvider()
        ..enterEditMode(
          blocks,
          const <String, dynamic>{},
          pageId: 'page-a',
          pageSlug: 'page-a',
        );
      addTearDown(provider.dispose);
      final editComposition = WebsitePageComposition.project(
        blocks: provider.blocks,
        mode: WebsitePageCompositionMode.edit,
        breakpoint: 'desktop',
      );
      final previewComposition = WebsitePageComposition.project(
        blocks: provider.blocks,
        mode: WebsitePageCompositionMode.preview,
        breakpoint: 'desktop',
      );
      const firstKey = ValueKey<String>('page-composition-block-first');

      await _pumpEditableHost(
        tester,
        _host(composition: editComposition, provider: provider),
      );
      final editTop = tester.getTopLeft(find.byKey(firstKey)).dy;

      await tester.pumpWidget(_host(composition: previewComposition));
      await tester.pump();
      final previewTop = tester.getTopLeft(find.byKey(firstKey)).dy;

      expect(editTop, previewTop);
    },
  );
}
